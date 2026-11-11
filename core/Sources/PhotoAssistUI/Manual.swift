import SwiftUI
import AppKit
import PhotoCore

/// Manualul de utilizare inclus în aplicație (PDF, 3 ediții independente RO/EN/ES): se deschide offline, fără licență activă, din fișierele livrate în pachet.
/// Ediția are versiunea în nume și în PDF; o ediție pentru ALTĂ versiune nu se prezintă ca descriind versiunea instalată.
public enum ManualLibrary {
    public static func fileName(version: String = AppInfo.version, language: AppLanguage) -> String { "FotoAsistGC-Manual-\(version)-\(language.rawValue).pdf" }
    public static func url(language: AppLanguage, bundle: Bundle = .main) -> URL? {
        guard language != .system, let dir = bundle.resourceURL?.appendingPathComponent("Manual", isDirectory: true) else { return nil }
        let f = dir.appendingPathComponent(fileName(language: language)); return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }
    /// Intrările de manual apar în meniuri NUMAI dacă pachetul conține cel puțin o ediție pentru această versiune (un build fără manuale nu arată o comandă care ar eșua).
    public static func anyEditionAvailable(bundle: Bundle = .main) -> Bool { [AppLanguage.ro, .en, .es].contains { url(language: $0, bundle: bundle) != nil } }
    /// Ediția implicită = limba aplicației (rezolvată); dacă lipsește, nu se înlocuiește pe tăcute cu alta: se spune clar.
    @MainActor public static func open(_ language: AppLanguage? = nil) {
        let lang = language ?? Localizer.shared.resolved
        if let u = url(language: lang) { NSWorkspace.shared.open(u); return }
        let a = NSAlert(); a.messageText = L("Manualul de utilizare nu este disponibil"); a.informativeText = LF("Ediția %@ a manualului pentru versiunea %@ nu este inclusă în această instalare. Reinstalează versiunea curentă sau descarcă manualul de pe pagina FotoAsist GC.", lang.nativeName, AppInfo.version)
        a.addButton(withTitle: "OK"); a.runModal()
    }
}

/// Meniu cu cele trei ediții (alegere explicită) — folosit în meniul Ajutor și în zona «Detalii».
struct ManualMenuItems: View {
    var body: some View {
        if ManualLibrary.anyEditionAvailable() {
            Button(L("Manual de utilizare…")) { ManualLibrary.open() }
            Menu(L("Alege ediția manualului")) {
                Button("Română") { ManualLibrary.open(.ro) }; Button("English") { ManualLibrary.open(.en) }; Button("Español") { ManualLibrary.open(.es) }
            }
        }
    }
}
