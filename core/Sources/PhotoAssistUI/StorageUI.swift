import SwiftUI
import AppKit
import PhotoCore

/// Starea de pornire a aplicației: alegerea folderului de lucru (primul start), disc indisponibil, biblioteca deschisă. Deține și monitorizarea discului de lucru și migrarea locației.
/// Dezvoltare: `GDC_PA_LIBRARY` / `GDCPADevRoot` păstrează configurația și garda „EXTERNAL TEST STORAGE NOT AVAILABLE”; stocarea nu se schimbă din interfață.
@MainActor public final class AppHost: ObservableObject {
    public enum State { case needsSetup, ready(AppModel), unavailable(StorageHealth, StorageLocation), failed(String) }
    @Published public private(set) var state: State = .needsSetup
    @Published public var lastMigratedFrom: URL?
    @Published public var migrationNote = ""
    public let store: StorageConfigStore
    public private(set) var isDev = false
    private let forceClient: Bool                                   // teste: ignoră configurația de dezvoltare din mediu
    private var timer: Timer?; private var unmountObs: NSObjectProtocol?; private var wasBlocked = false

    public init(store: StorageConfigStore = StorageConfigStore(), forceClient: Bool = false) {
        self.store = store; self.forceClient = forceClient; start()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
        unmountObs = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
    }
    deinit { timer?.invalidate(); if let o = unmountObs { NSWorkspace.shared.notificationCenter.removeObserver(o) } }

    // MARK: pornire
    func start() {
        let env = ProcessInfo.processInfo.environment
        if !forceClient && (env["GDC_PA_LIBRARY"] != nil || AppInfo.devRoot != nil) {
            isDev = true
            switch AppBootstrap.make() {
            case .success(let m):
                if let r = AppInfo.devRoot, env["GDC_PA_LIBRARY"] == nil { m.storageLocation = StorageConfig.make(root: URL(fileURLWithPath: r)) }
                m.isDevStorage = true; state = .ready(m)
            case .failure(let e): state = .failed("\(e)")
            }
            return
        }
        guard let loc = store.location else { state = .needsSetup; return }
        open(loc)
    }
    func open(_ loc: StorageLocation) {
        let (h, url) = StorageConfig.health(loc)
        guard h.blocks == false, let root = url else { state = .unavailable(h, loc); return }
        switch AppBootstrap.open(libDir: StorageLayout.library(in: root), logDir: AppBootstrap.clientLogDir) {
        case .success(let m): m.storageLocation = loc; if case .lowSpace = h { m.storageWarning = h }; state = .ready(m)
        case .failure(let e): state = .failed("\(e)")
        }
    }
    /// Alege (sau creează) biblioteca într-un folder: dacă există deja o bibliotecă acolo o deschide, altfel o creează.
    public func choose(root: URL) {
        let loc = StorageConfig.make(root: root); store.location = loc; open(loc)
    }
    public func retry() { if let loc = store.location { open(loc) } else { state = .needsSetup } }
    public func chooseOther() { state = .needsSetup }

    // MARK: monitorizare
    func check() {
        guard case .ready(let m) = state, let loc = m.storageLocation else { return }
        let h = StorageConfig.health(loc).health
        if h.blocks {
            if m.storageIssue != h { m.storageIssue = h; DiagnosticLog.shared?.log(.error, "storage", "indisponibil", h.message) }
            wasBlocked = true
        } else {
            m.storageWarning = h.isOK ? nil : h
            if wasBlocked {                                   // discul a revenit: redeschidem biblioteca (mânerele vechi pot fi invalide după demontare/remontare, eventual la alt punct de montare)
                wasBlocked = false; DiagnosticLog.shared?.log(.info, "storage", "revenit", "redeschid biblioteca")
                if isDev { m.storageIssue = nil } else { open(loc) }
            } else if m.storageIssue != nil { m.storageIssue = nil }
        }
    }

    // MARK: migrare
    public final class Cancel: @unchecked Sendable { private let l = NSLock(); private var v = false; public var value: Bool { l.lock(); defer { l.unlock() }; return v }; public func set() { l.lock(); v = true; l.unlock() } }
    public enum MigrationError: Error, CustomStringConvertible { case busy, notReady; public var description: String { switch self { case .busy: return L("Există operații în curs (import, analiză, export). Așteaptă sau oprește-le înainte de a muta biblioteca."); case .notReady: return L("Biblioteca nu e deschisă.") } } }
    /// COPIERE → VERIFICARE → COMUTARE. Locația veche rămâne neatinsă (o poți muta la Coș explicit după verificare); originalele nu se ating.
    public func migrate(toRoot newRoot: URL, cancel: Cancel, progress: @escaping @Sendable (Double, String) -> Void) async throws -> StorageMigration.Report {
        guard case .ready(let m) = state, !isDev else { throw MigrationError.notReady }
        if m.isBusy || m.editing.exportState != .idle && !isFinished(m.editing.exportState) || m.faces.running { throw MigrationError.busy }
        let cat = m.catalog, src = m.libraryDir
        let digest = try cat.contentDigest()          // fotografii + căi originale, decizii, reglaje/măști, profiluri, albume, analiză, jurnal export
        let rep = try await Task.detached(priority: .userInitiated) {
            try StorageMigration.run(from: src, toRoot: newRoot, snapshotCatalog: { try cat.snapshot(to: $0) }, verifyCatalog: { u in try Catalog(url: u).contentDigest() == digest },
                                     progress: progress, isCancelled: { cancel.value })
        }.value
        let old = src
        let loc = StorageConfig.make(root: newRoot); store.location = loc
        open(loc); lastMigratedFrom = old
        migrationNote = LF("Migrat: %@ fișiere, %@. Copia a fost verificată; folosesc acum %@.", rep.files, StorageFormat.bytes(rep.bytes), rep.destination.path)
        if case .ready(let nm) = state { nm.showStorage = true }
        DiagnosticLog.shared?.log(.info, "storage", "migrat", "\(rep.files) fișiere, \(StorageFormat.bytes(rep.bytes))", fields: ["to": rep.destination.path])
        return rep
    }
    private func isFinished(_ s: ExportRunState) -> Bool { switch s { case .finished, .failed: return true; default: return false } }
    public func trashOldLibrary() throws { guard let o = lastMigratedFrom else { return }; try FileManager.default.trashItem(at: o, resultingItemURL: nil); lastMigratedFrom = nil }
}

// MARK: primul start / disc indisponibil
struct DiskLine: View {
    let url: URL
    var body: some View {
        let vi = StorageConfig.volumeInfo(for: url); let free = StorageConfig.freeBytes(at: url)
        HStack(spacing: 6) { Image(systemName: "internaldrive").foregroundColor(Theme.accent); Text("\(vi.name ?? L("Disc necunoscut"))").font(Theme.f(12, weight: .semibold)); Text(free.map { LF("· %@ liberi", StorageFormat.bytes($0)) } ?? "").font(Theme.f(12)).foregroundColor(Theme.muted) }
    }
}

public struct FirstRunStorageView: View {
    @ObservedObject var host: AppHost
    @State private var root: URL = StorageConfigStore.suggestedRoot
    public init(host: AppHost) { self.host = host }
    public var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            BrandLockup(height: 34, tint: Theme.text)
            Text(L("Alege folderul de lucru")).font(Theme.f(24, weight: .semibold))
            Text(L("Aplicația păstrează într-un singur folder organizat tot ce produce: catalogul, miniaturile și previzualizările, cache-ul de analiză și fișierele intermediare. Poate fi pe discul intern sau pe un disc extern și îl poți schimba oricând din Setări → Stocare.")).font(Theme.f(13.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Box(title: L("Folder de lucru")) {
                HStack { Image(systemName: "folder").foregroundColor(Theme.accent); Text(StorageLayout.library(in: root).path).font(Theme.f(12, design: .monospaced)).textSelection(.enabled).lineLimit(2) }
                DiskLine(url: root)
                HStack { Button(L("Alege alt folder…")) { if let u = Self.pick(L("Folosește acest folder")) { root = u } }.buttonStyle(SoftButtonStyle()); Button(L("Folosește acest folder")) { host.choose(root: root) }.buttonStyle(PrimaryButtonStyle()) }
            }
            Box(title: L("Ce se scrie acolo")) {
                ForEach([StorageCategory.catalog, .previews, .analysis, .intermediates], id: \.self) { c in VStack(alignment: .leading, spacing: 1) { Text(c.title).font(Theme.f(12, weight: .semibold)); Text(c.consequence).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) } }
            }
            Box(title: L("Ce NU se mută și NU se copiază")) {
                Text(L("Originalele rămân exact unde sunt (orice folder sau disc) și sunt doar citite. Destinația exportului se alege separat, pentru fiecare lot; aplicația reține ultima alegere.")).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Text(L("Dacă alegi un disc extern, trebuie să fie conectat când lucrezi; dacă se deconectează, operațiile se opresc controlat și rezultatele terminate se păstrează.")).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(40).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity) }.background(Theme.app).foregroundColor(Theme.text)
    }
    static func pick(_ prompt: String) -> URL? {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.allowsMultipleSelection = false; p.prompt = prompt
        return p.runModal() == .OK ? p.url : nil
    }
}

public struct StorageUnavailableView: View {
    @ObservedObject var host: AppHost; let health: StorageHealth; let location: StorageLocation
    public init(host: AppHost, health: StorageHealth, location: StorageLocation) { self.host = host; self.health = health; self.location = location }
    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(Theme.f(40)).foregroundColor(Theme.check)
            Text(L("Discul de lucru nu este disponibil")).font(Theme.f(20, weight: .semibold))
            Text(health.message).font(Theme.f(13)).foregroundColor(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 560)
            Text(LF("Disc: %@ · folder: %@", location.volumeName ?? "necunoscut", location.root)).font(Theme.f(11, design: .monospaced)).foregroundColor(Theme.faint).textSelection(.enabled)
            Text(L("Nu mut nimic pe discul intern și nu creez o bibliotecă nouă fără alegerea ta.")).font(Theme.f(12)).foregroundColor(Theme.muted)
            HStack { Button(L("Verifică din nou")) { host.retry() }.buttonStyle(PrimaryButtonStyle()); Button(L("Alege altă locație…")) { host.chooseOther() }.buttonStyle(SoftButtonStyle()) }
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.app).foregroundColor(Theme.text)
    }
}

/// Bandă afișată peste ecran cât timp discul de lucru e indisponibil sau aproape plin; Setările rămân accesibile (fără ecran fără ieșire).
struct StorageBanner: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let h = model.storageIssue ?? model.storageWarning {
            HStack(spacing: 10) {
                Image(systemName: h.blocks ? "externaldrive.badge.xmark" : "exclamationmark.triangle").foregroundColor(Theme.check)
                Text(h.message).font(Theme.f(12)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(L("Setări → Stocare")) { model.showStorage = true }.buttonStyle(SoftButtonStyle())
            }.padding(.horizontal, 16).padding(.vertical, 8).background(Theme.check.opacity(0.16)).foregroundColor(Theme.text)
        }
    }
}

// MARK: Setări → Stocare
public struct StorageSettingsSheet: View {
    @ObservedObject var model: AppModel; var host: AppHost?
    @Environment(\.dismiss) var dismiss
    @State private var usage: [StorageUsage] = []
    @State private var cleaning: StorageCategory?
    @State private var note = ""
    @State private var migrating = false; @State private var progress = 0.0; @State private var progressFile = ""; @State private var cancel = AppHost.Cancel()
    @State private var pendingRoot: URL?
    public init(model: AppModel, host: AppHost?) { self.model = model; self.host = host }
    var health: StorageHealth? { model.storageLocation.map { StorageConfig.health($0).health } }
    func refresh() {
        let lib = model.libraryDir; let st: (count: Int, bytes: Int64) = (try? model.catalog.sessionStats(prefix: "faces:")) ?? (count: 0, bytes: 0)
        usage = StorageConfig.usage(library: lib, analysis: (st.count, st.bytes))
    }
    public var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            HStack { Text(L("Setări")).font(Theme.f(20, weight: .semibold)); Spacer(); Button(L("Închide")) { dismiss() }.buttonStyle(SoftButtonStyle()) }
            Text(L("Aici alegi limba aplicației și unde își ține datele. Se pot deschide și din meniul ⋯ sau cu ⌘,.")).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            LanguageBox()
            Text(L("Stocare")).font(Theme.f(15, weight: .semibold)).padding(.top, 4)
            Box(title: L("Folderul de lucru")) {
                Text(model.libraryDir.path).font(Theme.f(11.5, design: .monospaced)).textSelection(.enabled)
                DiskLine(url: model.libraryDir)
                if let h = health { Text(h.message).font(Theme.f(12)).foregroundColor(h.isOK ? Theme.keep : Theme.check).fixedSize(horizontal: false, vertical: true) }
                if model.isDevStorage { Text(L("Build de dezvoltare: stocarea este fixată pe discul extern de test (garda „EXTERNAL TEST STORAGE NOT AVAILABLE”); nu se schimbă din interfață.")).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                else {
                    HStack {
                        Button(L("Schimbă locația…")) { if let u = FirstRunStorageView.pick(L("Mută aici")) { pendingRoot = u } }.buttonStyle(SoftButtonStyle()).disabled(migrating || host == nil)
                        Button(L("Arată în Finder")) { NSWorkspace.shared.activateFileViewerSelecting([model.libraryDir]) }.buttonStyle(SoftButtonStyle())
                    }
                }
                if let r = pendingRoot, !migrating {
                    Text(LF("Voi COPIA biblioteca în %@, voi verifica copia și abia apoi voi comuta. Locația veche rămâne neatinsă; originalele nu se ating. Decizii, reglaje, măști, profiluri și albume se păstrează.", StorageLayout.library(in: r).path)).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    HStack { Button(L("Copiază și comută")) { startMigration(r) }.buttonStyle(PrimaryButtonStyle()); Button(L("Renunță")) { pendingRoot = nil }.buttonStyle(SoftButtonStyle()) }
                }
                if migrating {
                    ProgressView(value: progress).tint(Theme.accent); Text(LF("Se copiază… %@", progressFile)).font(Theme.f(11)).foregroundColor(Theme.faint).lineLimit(1)
                    Button(L("Anulează migrarea")) { cancel.set() }.buttonStyle(SoftButtonStyle())
                }
                if let old = host?.lastMigratedFrom {
                    Text(LF("Migrare terminată și verificată. Biblioteca veche (neatinsă): %@", old.path)).font(Theme.f(12)).foregroundColor(Theme.keep).fixedSize(horizontal: false, vertical: true)
                    Button(L("Mută biblioteca veche la Coș")) { do { try host?.trashOldLibrary(); note = L("Biblioteca veche a fost mutată la Coș.") } catch { note = LF("Nu am putut-o muta la Coș: %@", error.localizedDescription) } }.buttonStyle(SoftButtonStyle())
                }
                if let mn = host?.migrationNote, !mn.isEmpty { Text(mn).font(Theme.f(12)).foregroundColor(Theme.keep).fixedSize(horizontal: false, vertical: true) }
                if !note.isEmpty { Text(note).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Box(title: L("Spațiu folosit")) {
                ForEach(usage, id: \.category) { u in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text(u.category.title).font(Theme.f(12.5, weight: .semibold)); Spacer(); Text(StorageFormat.bytes(u.bytes)).font(Theme.f(12)).foregroundColor(Theme.muted)
                            if u.category.regenerable { Button(L("Curăță…")) { cleaning = u.category }.buttonStyle(SoftButtonStyle()).disabled(u.bytes == 0 && u.files == 0) } }
                        Text(u.category.consequence).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Box(title: L("Originale și export")) {
                Text(L("Originalele rămân unde sunt și sunt doar citite — nu se mută și nu se copiază. Destinația exportului se alege pentru fiecare lot (ecranul Export); ultima alegere se reține.")).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                if let f = model.editing.exportFolder { Text(LF("Ultima destinație: %@", f.path)).font(Theme.f(11.5, design: .monospaced)).textSelection(.enabled); Text(StorageConfig.checkExportDestination(f, needed: 1).message).font(Theme.f(11.5)).foregroundColor(Theme.muted) }
                Button(L("Alege destinația de export…")) { model.editing.chooseExportFolder() }.buttonStyle(SoftButtonStyle())
            }
            Box(title: L("Excepții: ce se scrie în afara folderului de lucru")) {
                Text(L("Preferințele aplicației (mărime text, panouri, pointerul către folderul de lucru) și jurnalele de diagnostic (mici; ~/Library/Logs/GDC Photo Assist, ca să existe și când discul de lucru lipsește) rămân pe discul de sistem. Cache-urile proprii ale DaVinci Resolve nu sunt gestionate de aplicație și nu li se schimbă setările globale.")).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading) }.frame(minWidth: 560, idealWidth: 700, maxWidth: 820, minHeight: 480, idealHeight: 640).background(Theme.app).foregroundColor(Theme.text)
        .onAppear { refresh() }
        .alert(item: Binding(get: { cleaning.map { CleanItem(category: $0) } }, set: { cleaning = $0?.category })) { it in
            Alert(title: Text(LF("Curăț: %@?", it.category.title)), message: Text(it.category.consequence + L("\n\nCatalogul, reglajele, măștile, profilurile și albumele nu se ating.")), primaryButton: .destructive(Text(L("Curăță"))) { clean(it.category) }, secondaryButton: .cancel(Text(L("Renunță"))))
        }
    }
    struct CleanItem: Identifiable { var category: StorageCategory; var id: String { category.rawValue } }
    func clean(_ c: StorageCategory) {
        do {
            if c == .analysis { try model.catalog.removeSession(prefix: "faces:"); note = L("Cache-ul de analiză a fost șters.") }
            else { let n = try StorageConfig.clean(c, library: model.libraryDir); note = "Eliberat: \(StorageFormat.bytes(n))." }
        } catch { note = LF("Curățarea a eșuat: %@", error) }
        refresh()
    }
    func startMigration(_ root: URL) {
        guard let host = host else { return }
        migrating = true; progress = 0; cancel = AppHost.Cancel(); note = ""; let c = cancel
        Task {
            do {
                let rep = try await host.migrate(toRoot: root, cancel: c) { p, f in Task { @MainActor in progress = p; progressFile = f } }
                _ = rep; pendingRoot = nil
            } catch { note = "\(error)" }
            migrating = false
        }
    }
}

/// Setări → Limbă: urmează sistemul sau alegere explicită RO / EN / ES. Se aplică imediat (interfața se reconstruiește). Numele fișierelor, identificatorii tehnici și numele proprii nu se traduc.
struct LanguageBox: View {
    @ObservedObject private var loc = Localizer.shared
    var body: some View {
        Box(title: L("Limbă / Language / Idioma")) {
            Picker("", selection: $loc.choice) {
                Text(L("Urmează sistemul")).tag(AppLanguage.system)
                ForEach([AppLanguage.ro, .en, .es], id: \.rawValue) { Text($0.nativeName).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            Text(loc.choice == .system ? LF("Limba sistemului: %@. Dacă sistemul folosește altă limbă decât română, engleză sau spaniolă, se folosește engleza.", loc.resolved.nativeName) : L("Limba aleasă se aplică imediat. Poți reveni oricând la «Urmează sistemul»."))
                .font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            Text(L("Nu se traduc: numele fișierelor, identificatorii tehnici, numele profilurilor și albumelor tale.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
        }
    }
}
