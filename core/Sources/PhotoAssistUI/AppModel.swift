import SwiftUI
import PhotoCore
import PhotoRaw
import PhotoAccess

public enum ImportPhase: Equatable { case idle, scanning, previews(done: Int, total: Int), analyzing(done: Int, total: Int), done, failed(String) }

/// Modelul aplicației (slice Lot 3a): bibliotecă = catalog + cache în `libraryDir` (ales de apelant; în dezvoltare, sub rădăcina de date de pe extern).
/// Importul NU scrie lângă originale: scanează read-only, scrie în catalog și în cache.
@MainActor
public final class AppModel: ObservableObject {
    /// Coada de editare aleasă EXPLICIT (selecție/album): nu se schimbă în tăcere la schimbarea filtrului sau a etapei; fotografiile scoase din coadă își păstrează reglajele și măștile în catalog.
    @Published public var editIds: [Int64]? { didSet { try? catalog.setSession("edit_ids", (editIds ?? []).map(String.init).joined(separator: ",")); try? catalog.setSession("edit_label", editLabel) } }
    @Published public var editLabel = ""
    @Published public var step: AppStep = .imp { didSet { try? catalog.setSession("step", "\(step.rawValue)"); if oldValue != step { editing.endCanvasGestures() } } }
    @Published public var phase: ImportPhase = .idle
    @Published public var sourceFolder: URL?
    @Published public var continueWithAll = false
    @Published public private(set) var importSummary: (added: Int, updated: Int, unchanged: Int, withPreview: Int, withoutPreview: Int, cameras: [String], skipped: [LibraryImporter.Skipped])?
    public let catalog: Catalog; public let session: SelectionSession; public let store: ImageStore; public let libraryDir: URL; public let faces: FaceCenter
    public let editing: EditingModel
    /// Dreptul de utilizare (verificatorul comun) + politica funcțiilor (separată; acum fără restricții).
    public let access: AccessModel
    @Published public var showAbout = false
    @Published public var showStorage = false
    @Published public var showLibrary = false
    /// Starea discului de lucru (setată de AppHost): `blocks` ⇒ operațiile care scriu sunt în pauză, rezultatele terminate se păstrează.
    @Published public var storageIssue: StorageHealth? { didSet { let b = storageIssue?.blocks ?? false; editing.storageBlocked = b; if b { faces.cancel() } } }
    @Published public var storageWarning: StorageHealth?
    public var storageLocation: StorageLocation?
    public var isDevStorage = false
    public var log: DiagnosticLog? { DiagnosticLog.shared }
    public var sessionID: String { log?.sessionID ?? "—" }
    public var debugActive: Bool { log?.debugActive ?? false }

    public init(libraryDir: URL, policy: PhotoFeaturePolicy = PhotoPolicies.standard()) throws {
        access = AccessModel(policy: policy)
        self.libraryDir = libraryDir
        try FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        catalog = try Catalog(url: libraryDir.appendingPathComponent("catalog.sqlite"))
        store = ImageStore(cache: try PreviewCache(catalog: catalog, directory: libraryDir.appendingPathComponent("cache"), detailProvider: LibRawDetailProvider()))
        session = try SelectionSession(catalog: catalog); faces = FaceCenter(catalog: catalog, store: store)
        editing = EditingModel(catalog: catalog, workDir: libraryDir.appendingPathComponent("work"))
        editing.featureGate = { [access] f in access.permits(f) }
        installFieldFocusMonitor()
        if let st = try? catalog.session("step"), let n = Int(st), let s = AppStep(rawValue: n), !session.photos.isEmpty { step = s; continueWithAll = (try? catalog.session("continue_all")) == "1"; restoreEditScope() }   // reluarea sesiunii
        if !session.photos.isEmpty { phase = .done }
        #if GDC_PA_TEST_TRUST
        // Doar în varianta de PROBĂ: import automat al unui folder de imagini redate (bibliotecă demonstrativă), fiindcă panoul de sistem «Deschide» nu poate fi condus de automatizarea de verificare.
        if let d = ProcessInfo.processInfo.environment["GDC_PA_AUTOEXPORT_DIR"] { editing.exportFolder = URL(fileURLWithPath: d) }   // destinația de export fixată pentru verificări (panoul «Alege folderul» e al sistemului)
        if let f = ProcessInfo.processInfo.environment["GDC_PA_AUTOIMPORT_RENDERED"], session.photos.isEmpty { Task { await self.importFolder(URL(fileURLWithPath: f), rendered: true) } }
        #if GDC_PA_DEV_OPEN   // doar în build-urile de dezvoltare: pregătește o bibliotecă de probă cu un folder RAW (importul pe gest rămâne calea normală)
        if let f = ProcessInfo.processInfo.environment["GDC_PA_AUTOIMPORT_RAW"], session.photos.isEmpty { Task { await self.importFolder(URL(fileURLWithPath: f), rendered: false) } }
        #endif
        #endif
    }

    public func importFolder(_ url: URL, rendered: Bool = false) async {
        if storageIssue?.blocks == true { phase = .failed(storageIssue?.message ?? L("Discul de lucru nu este disponibil.")); return }
        sourceFolder = url; phase = .scanning; let t0 = Date(); log?.log(.info, "import", "start", url.path, job: "imp")
        do {
            let cat = catalog
            let sum: LibraryImporter.Summary = try await store.run { cache in
                try LibraryImporter.run(directory: url, catalog: cat, cache: cache, recursive: true, rendered: rendered) { ph in
                    DispatchQueue.main.async { switch ph { case .scanning: self.phase = .scanning; case .previews(let d, let t): self.phase = .previews(done: d, total: t); case .analyzing(let d, let t): self.phase = .analyzing(done: d, total: t) } }
                }
            }
            try session.reload()
            var xmpN = 0   // evaluări din sidecar-uri .xmp de lângă RAW-uri (DOAR citire; apar doar pentru fotografiile fără evaluare)
            for ph in session.photos where ph.rating == 0 && !ph.isRendered { if let r = XMPSidecar.readRating(forRaw: ph.path), r > 0 { try? catalog.setRating(r, photoId: ph.id); xmpN += 1 } }
            if xmpN > 0 { try session.reload(); log?.log(.info, "import", "xmp.rating", "\(xmpN) evaluări citite din sidecar-uri .xmp (originalele neatinse)") }
            importSummary = (sum.added, sum.updated, sum.unchanged, sum.withPreview, sum.withoutPreview, Array(Set(session.photos.compactMap { $0.camera })).sorted(), sum.skipped)
            for k in sum.skipped { log?.log(.warning, "import", "omis", "\(k.path): \(k.reason)", job: "imp") }
            phase = .done; log?.log(.info, "import", "ok", "adăugate \(sum.added) neschimbate \(sum.unchanged)", job: "imp", durationMs: Date().timeIntervalSince(t0) * 1000)
        } catch { phase = .failed("\(error)"); log?.log(.error, "import", "fail", job: "imp", error: error) }
    }

    public var isBusy: Bool { switch phase { case .scanning, .previews, .analyzing: return true; default: return false } }
    /// Alege un folder (NSOpenPanel) și îl adaugă incremental în catalog; funcționează oricând după primul import.
    public func chooseAndImport() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false; p.prompt = L("Adaugă")
        if p.runModal() == .OK, let u = p.url { Task { await importFolder(u) } }
    }

    /// Cale EXPLICITĂ, separată de RAW: imagini display-referred (PNG/JPEG/TIFF) pentru demonstrații. Nu sunt RAW-uri și nu primesc DRT; apar cu indicatorul «Imagine redată · nu RAW».
    public func chooseAndImportRendered() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false; p.prompt = L("Adaugă imagini redate")
        p.message = L("Folder cu PNG/JPEG/TIFF (demonstrații). Nu sunt RAW-uri: nu primesc DRT și nu au date de scenă.")
        if p.runModal() == .OK, let u = p.url { Task { await importFolder(u, rendered: true) } }
    }

    private func restoreEditScope() { if let j = (try? catalog.session("edit_ids")) ?? nil, !j.isEmpty { editLabel = ((try? catalog.session("edit_label")) ?? nil) ?? ""; editIds = j.split(separator: ",").compactMap { Int64($0) } } }
    /// Etapele sunt accesibile prin click în condițiile lor reale: Bibliotecă oricând; Selecție dacă există fotografii; Editare/Revizuire/Export dacă există o coadă de editare. Navigarea nu schimbă decizii, reglaje sau aprobări; modelele rămân aceleași.
    public func canOpen(_ s: AppStep) -> Bool { switch s { case .imp: return true; case .selection: return !session.photos.isEmpty; default: return !editQueue.isEmpty } }
    private static var fieldMonitor: Any?
    /// Comportament standard macOS: clic în afara unui câmp de text în curs de editare îl face să iasă din editare (confirmă valoarea tastată). SwiftUI nu o face pentru clicuri pe zone fără control.
    private func installFieldFocusMonitor() {
        guard Self.fieldMonitor == nil else { return }
        Self.fieldMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            guard let w = e.window, let root = w.contentView, let tv = w.firstResponder as? NSTextView, tv.isFieldEditor else { return e }
            let hit = root.hitTest(root.convert(e.locationInWindow, from: nil))
            let inEditor = hit.map { $0 === tv || $0.isDescendant(of: tv) || ($0 as? NSTextField) != nil } ?? false
            if !inEditor { NotificationCenter.default.post(name: .gdcCommitNumericFields, object: nil); w.endEditing(for: nil); w.makeFirstResponder(root) }
            return e
        }
    }
    public func navigate(to s: AppStep) { NotificationCenter.default.post(name: .gdcCommitNumericFields, object: nil); guard s != step, canOpen(s) else { return }; if step == .style || step == .review { editing.flushSave() }; step = s }
    public func goToSelection() { step = .selection }
    /// Scoate fotografiile din catalog (nu din disc). Reglajele salvate, deciziile și apartenențele la albume ale lor se pierd; originalele și exporturile rămân. Coada de editare se curăță, iar ecranul se mută pe o etapă validă.
    @discardableResult public func removeFromLibrary(ids: [Int64]) -> Int {
        guard !ids.isEmpty else { return 0 }; editing.flushSave()
        let n = (try? catalog.removeFromCatalog(photoIds: ids)) ?? 0; let gone = Set(ids)
        if let e = editIds { editIds = e.filter { !gone.contains($0) }; try? catalog.setSession("edit_ids", (editIds ?? []).map(String.init).joined(separator: ",")) }
        try? session.reload()
        if session.photos.isEmpty { step = .imp; phase = .idle; importSummary = nil } else if (step == .style || step == .review || step == .export) && editQueue.isEmpty { step = .selection }
        log?.log(.info, "library", "remove", "\(n) fotografii scoase din catalog (fișierele nu s-au atins)")
        return n
    }
    /// Editează o listă EXPLICITĂ de fotografii (selecția sau albumul ales).
    public func proceedToEditing(ids: [Int64], label: String) { continueWithAll = false; try? catalog.setSession("continue_all", "0"); editLabel = label; editIds = ids; step = .style }
    /// Trecerea la editare: păstratele (implicit) sau toate (selecția sărită). Nu modifică nimic pe disc.
    public func proceedToEditing(all: Bool) { editIds = nil; editLabel = all ? L("toate fotografiile") : L("păstratele"); continueWithAll = all; try? catalog.setSession("continue_all", all ? "1" : "0"); step = .style }
    public var editQueue: [PhotoRecord] { if let ids = editIds { let set = Set(ids); return session.photos.filter { set.contains($0.id) } }; return session.editQueue(allPhotos: continueWithAll) }

    // MARK: diagnostic
    public func openLogsFolder() { if let d = log?.directory { NSWorkspace.shared.open(d) } }
    public func copySessionID() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(sessionID, forType: .string) }
    public func enableDebug() { log?.enableDebug(minutes: 30); objectWillChange.send(); log?.log(.info, "app", "debug.enabled", "30 min") }
    public func exportDiagnostics() {
        guard let l = log else { return }
        let p = NSSavePanel(); p.nameFieldStringValue = "FotoAsistGC-diagnostic-\(AppInfo.version)-\(sessionID).zip"; p.prompt = L("Exportă diagnosticul")
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try l.exportDiagnostics(to: u, settings: ["engine": editing.engineName, "output_transform": editing.outputTransformName, "version": AppInfo.version, "build": AppInfo.build, "step": "\(step.rawValue)"]); NSWorkspace.shared.activateFileViewerSelecting([u]); l.log(.info, "diagnostic", "export.ok") }
        catch { l.log(.error, "diagnostic", "export.fail", error: error) }
    }
}


