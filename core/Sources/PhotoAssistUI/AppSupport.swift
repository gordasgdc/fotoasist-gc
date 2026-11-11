import SwiftUI
import AppKit
import PhotoCore
import PhotoResolve

/// Informații despre build (din Info.plist-ul aplicației asamblate; în dezvoltare cu `swift run` cad pe valori implicite).
public enum AppInfo {
    public static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0-dev" }
    public static var build: String { Bundle.main.infoDictionary?["GDCPABuild"] as? String ?? "local" }
    /// Rădăcina de date a build-ului de dezvoltare (extern). Prezentă DOAR în aplicația de dezvoltare asamblată de `scripts/dev/make_dev_app.sh`.
    /// Unelte INTERNE (comparația temporară „Resolve + STYLE”): ascunse în traseul clientului; se activează doar explicit (`GDC_PA_INTERNAL=1`). Independența de STYLE: motorul intern nu face parte din fluxul clientului.
    public static var internalTools: Bool { ProcessInfo.processInfo.environment["GDC_PA_INTERNAL"] == "1" }
    public static var devRoot: String? { Bundle.main.infoDictionary?["GDCPADevRoot"] as? String }
}

public enum BootError: Error { case externalStorageUnavailable(String) }

@MainActor public enum AppBootstrap {
    /// Dezvoltare/teste: GDC_PA_LIBRARY sau rădăcina de pe extern (`GDCPADevRoot`). Dacă volumul lipsește → „EXTERNAL TEST STORAGE NOT AVAILABLE” (fără fallback pe discul intern). Clientul folosește `AppHost` (locația aleasă de utilizator).
    public static func make() -> Result<AppModel, BootError> {
        let env = ProcessInfo.processInfo.environment
        let libDir: URL, logDir: URL
        if let l = env["GDC_PA_LIBRARY"] { libDir = URL(fileURLWithPath: l); logDir = libDir.deletingLastPathComponent().appendingPathComponent("logs") }
        else if let root = AppInfo.devRoot {
            var isDir: ObjCBool = false
            let vol = URL(fileURLWithPath: root).pathComponents.prefix(3).joined(separator: "/").replacingOccurrences(of: "//", with: "/")
            guard FileManager.default.fileExists(atPath: vol, isDirectory: &isDir), isDir.boolValue, FileManager.default.isWritableFile(atPath: vol) else { return .failure(.externalStorageUnavailable(root)) }
            libDir = URL(fileURLWithPath: root).appendingPathComponent("app_data/library"); logDir = URL(fileURLWithPath: root).appendingPathComponent("app_data/logs")
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            libDir = base.appendingPathComponent("GDC Photo Assist"); logDir = clientLogDir
        }
        return open(libDir: libDir, logDir: logDir)
    }
    /// Jurnalele clientului rămân pe discul de sistem (mici; necesare tocmai când discul de lucru lipsește) — excepție documentată de la „totul în folderul de lucru”.
    public static var clientLogDir: URL { FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/GDC Photo Assist") }
    public static func open(libDir: URL, logDir: URL) -> Result<AppModel, BootError> {
        let log = DiagnosticLog.shared ?? DiagnosticLog(directory: logDir, version: AppInfo.version, build: AppInfo.build); DiagnosticLog.shared = log
        log.log(.info, "app", "start", "versiune \(AppInfo.version) build \(AppInfo.build)", fields: ["library": libDir.path])
        log.log(.info, "drt", "data", "\(GDCDRTData.load(devRoot: AppInfo.devRoot))")
        do { return .success(try AppModel(libraryDir: libDir)) }
        catch { log.log(.critical, "app", "init.fail", error: error); return .failure(.externalStorageUnavailable("\(error)")) }
    }
}

public struct StorageMissingView: View {
    let detail: String
    public init(detail: String) { self.detail = detail }
    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(Theme.f(40)).foregroundColor(Theme.check)
            Text(L("EXTERNAL TEST STORAGE NOT AVAILABLE")).font(Theme.f(20, weight: .semibold))
            Text(L("Aceasta este o versiune de dezvoltare: scrie datele (bibliotecă, cache, rezultate, jurnale) doar pe discul extern de test. Montează volumul și redeschide aplicația. Nu se folosește discul intern ca rezervă.")).font(Theme.f(13)).foregroundColor(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 520)
            Text(detail).font(Theme.f(11, design: .monospaced)).foregroundColor(Theme.faint).textSelection(.enabled)
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.app).foregroundColor(Theme.text)
    }
}

/// Meniu „Diagnostic”: deschide folderul de loguri, copiază ID-ul sesiunii, exportă pachetul local de diagnostic, debug extins temporar.
struct DiagnosticMenu: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Menu {
            Button(L("Despre această versiune…")) { model.showAbout = true }
            ManualMenuItems()
            Divider()
            Button(L("Setări (limbă, stocare)…")) { model.showStorage = true }.keyboardShortcut(",", modifiers: .command)
            Button(L("Deschide folderul de loguri")) { model.openLogsFolder() }
            Button(L("Copiază ID-ul sesiunii")) { model.copySessionID() }
            Button(L("Exportă diagnosticul…")) { model.exportDiagnostics() }
            Button(model.debugActive ? L("Debug extins activ (30 min)") : L("Activează debug extins (30 min)")) { model.enableDebug() }.disabled(model.debugActive)
        } label: { Image(systemName: "ellipsis.circle").font(Theme.f(15)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).help(L("Diagnostic și informații"))
    }
}

public struct AboutSheet: View {
    @ObservedObject var model: AppModel; @Environment(\.dismiss) var dismiss
    public init(model: AppModel) { self.model = model }
    func row(_ ok: Bool, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 8) { Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle").foregroundColor(ok ? Theme.keep : Theme.faint).padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) { Text(t).font(Theme.f(12.5, weight: .semibold)); Text(d).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) } }
    }
    public var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            HStack { VStack(alignment: .leading, spacing: 8) { BrandLockup(height: 40, tint: Theme.text); BuildIdentityView(session: model.sessionID) }; Spacer() }
            Box(title: L("Actualizări")) { UpdateSection() }
            Box(title: L("Ce poți verifica acum")) {
                row(true, L("Import și Selecție"), L("RAW din orice folder (citit fără scriere); previzualizări din cameră, 100% din RAW, decizii păstrează/respinge reversibile, comparație, semnale clasice (sugestii)."))
                row(true, L("Stil și ajustări"), L("Nucleu propriu (CPU) cu GDC DRT Natural adaptat (sau, explicit, DRT p1 experimental): expunere, balans (temperatură/tentă), umbre/lumini, contrast, saturație, presetări de parametri; Bază / După / Împărțit / Cameră; inspecție 100% la cerere; aprobare care se anulează la modificări."))
                row(true, L("Revizuire și Export"), L("Previzualizări per fotografie; export explicit (aprobate / curentă / coadă) TIFF 16 biți sau JPEG, sRGB cu profil ICC, la rezoluție plină."))
                row(true, "Diagnostic", L("Jurnal structurat redactat, folder de loguri, ID de sesiune, pachet de diagnostic local (nu se trimite nimic)."))
            }
            Box(title: L("Indisponibil sau provizoriu")) {
                row(false, L("GDC DRT adaptat: în verificare"), L("Implicit se folosește GDC DRT (profil Natural), adaptat din sursa autoritară a proprietarului (tag v2.10.0): paritate numerică verificată, dar adaptarea e nouă și neevaluată pe imagini reale de către proprietar. DRT p1 rămâne exclusiv experimental (NU GDC DRT; selectabil explicit). Verificarea interfeței nu reprezintă aprobarea culorii."))
                row(false, L("Estimatorul de expunere"), L("Experimental și nevalidat; dezactivat implicit (se aplică doar deliberat)."))
                row(false, "Resolve + STYLE", L("Motor alternativ, dependență temporară (doar comparație). Necesită Resolve Studio pornit."))
                row(false, L("OFX fotografic în Resolve"), L("Pregătit (fișiere + plan reversibil), NEinstalat și neexercitat în Resolve: cere acordul tău pentru instalare și repornirea Resolve."))
                row(false, L("Culling automat complet"), L("NEimplementat: nu există detecție automată de focalizare, de ochi închiși pe toate cadrele, de expunere greșită sau de orizont; sugestiile (grupuri, ochi, claritate locală pe fețe) sunt doar indicii, iar îndreptarea e manuală. Vezi docs/CULLING_CAPABILITIES.md."))
                row(false, L("Independență față de STYLE"), L("NEdemonstrată într-un mediu fără STYLE; motorul propriu nu apelează STYLE, dar acceptanța pe un sistem curat nu a fost făcută."))
            }
            Box(title: L("Date și jurnale")) { Text(LF("Bibliotecă: %@", model.libraryDir.path)).font(Theme.f(11, design: .monospaced)).textSelection(.enabled); Text(LF("Loguri: %@", model.log?.directory.path ?? "—")).font(Theme.f(11, design: .monospaced)).textSelection(.enabled) }
        }.padding(22) }.frame(width: 700, height: 640).background(Theme.app).foregroundColor(Theme.text)
    }
}
