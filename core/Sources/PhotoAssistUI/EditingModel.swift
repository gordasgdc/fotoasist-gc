import SwiftUI
import AppKit
import ImageIO
import PhotoCore
import PhotoRaw
import PhotoResolve
import PhotoAccess
import CPhotoCore
import Combine

/// Motorul de procesare: nucleul fotografic PROPRIU (implicit, în aplicație, fără Resolve/STYLE) sau Resolve + module STYLE (dependență TEMPORARĂ, doar comparație).
public enum EngineChoice: String, CaseIterable { case own, resolveStyle }
public enum EditConnection: Equatable { case idle, connecting, ready(String), needsConsent(String), unavailable(String) }
/// Moduri de comparație: „bază” = ACEEAȘI decodare fără ajustări (lanț GDC neutru) — baza comparației reglajelor; „cameră” = previzualizarea JPEG încorporată, reper SEPARAT (altă dezvoltare, nu randare GDC).
public enum CompareMode: String { case base, after, split, camera, resolve }
public enum HandoffUIState: Equatable { case idle, working(String), done(String), needsConsent(String), needsLocalsChoice(Int), failed(String) }
public enum LocalsPolicy: String { case bake, drop }
struct ChartSessionState: Codable { var model: ChartModelID; var grid: ChartGrid }
public enum ExportRunState: Equatable { case idle, running(done: Int, total: Int), finished(count: Int, folder: String), failed(String) }
/// Ce se exportă — alegere explicită, fără substituire automată: dacă „aprobate” e gol, nu se exportă nimic.
public enum ExportScope: String, CaseIterable { case approved, current, queue }
public enum ApprovalState: Equatable { case none, approved, invalidated }

enum LocalCorrectionError: LocalizedError { case ownEngineOnly, familyOwnEngineOnly
    var errorDescription: String? {
        switch self {
        case .ownEngineOnly: return L("Corecțiile locale se aplică doar cu motorul „Nucleu propriu”. Treci la Nucleu propriu sau oprește corecțiile locale.")
        case .familyOwnEngineOnly: return L("Familiile de lucru în afara celei DaVinci se aplică doar cu motorul „Nucleu propriu”. Treci la Nucleu propriu sau alege familia DaVinci.")
        }
    }
}

/// Rezultat randat afișabil: TIFF-ul Resolve (sRGB, fără profil) este etichetat sRGB la încărcare, fără conversie de valori.
enum ResultImage {
    static func load(_ url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil), let cs = CGColorSpace(name: CGColorSpace.sRGB), let t = img.copy(colorSpace: cs) else { return nil }
        return NSImage(cgImage: t, size: NSSize(width: t.width, height: t.height))
    }
}

/// Modelul etapelor Stil și ajustări → Revizuire → Export. Procesarea (decodare LibRaw + lanț GDC în Resolve) rulează pe o coadă serială; UI-ul primește doar rezultate etichetate.
@MainActor
public final class EditingModel: ObservableObject {
    @Published public var connection: EditConnection = .idle
    @Published public var engine: EngineChoice = .own { didSet { if oldValue != engine { engineChanged() } } }
    /// Transformarea de ieșire a motorului propriu (GDC DRT Natural adaptat = implicit; DRT p1 = experimental, doar pentru comparație explicită).
    @Published public var outputTransform: OutputTransform = .standard { didSet { if oldValue != outputTransform { outputTransformChanged() } } }
    @Published public var current: PhotoRecord?
    @Published public var adjustments = AdjustmentSet() { didSet { if !restoring && !revertingLocked && !featureGate(.editProcessing) { revertingLocked = true; adjustments = oldValue; revertingLocked = false; statusLine = Self.lockedMessage; return }; if restoring { retouchUndo = []; retouchRedo = [] } else { if !applyingHistory && gestureSnapshot == nil { redoState = nil }; trackRetouch(old: oldValue.retouch); activateEditedModules(old: oldValue); adjustmentsChanged() } } }
    @Published public var afterImage: NSImage?; @Published public var beforeImage: NSImage?
    /// Fișierul rezultat al ultimei randări „După” (pentru verificări și comparații; nu se afișează).
    public private(set) var afterResultURL: URL?
    @Published public var afterInfo = ""; @Published public var statusLine = ""
    @Published public var renderedInfo: RenderedInfo?   // intrare redată (PNG/JPEG/TIFF): profil/asumție de culoare; nil pentru RAW
    public var currentIsRendered: Bool { current?.isRendered ?? false }
    @Published public var decodeInfo: DecodeReport?   // raportul decodării RAW al fotografiei curente (aparat, decodor, balans, politici)
    @Published public var rendering = false
    /// Corecții locale: cea selectată pentru editare și afișarea zonei (roșu translucid) peste fotografie.
    @Published public var selectedLocal: String?
    @Published public var showZone = false          // umplerea măștii (roșu translucid)
    /// Ghidajele măștii (umplere + contur + puncte de control): ascunse ⇒ fotografia e curată și masca nu se poate muta accidental; efectul corecției rămâne. Independent de activarea corecției (ochiul) și de „Arată zona”.
    /// Vizibilitatea ghidajelor (comună: geometrie, măști, grilă): ascunderea NU schimbă rezultatul, unealta aflată în editare sau reglajele; fără ghidaje nu se poate modifica nimic prin tragere.
    @Published public var guidesHidden = false { didSet { if oldValue != guidesHidden, geometryMode == .crop { scheduleRender(immediate: true) } } }
    @Published public var gridTransient = false
    private var gridTask: Task<Void, Never>?
    /// Grilă vizibilă un moment în timpul ajustării (rotire/perspectivă), fără a porni comutatorul persistent.
    public func pulseGrid() { gridTransient = true; gridTask?.cancel(); gridTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 1_300_000_000); if !Task.isCancelled { self?.gridTransient = false } } }
    public var gridVisible: Bool { (showGrid || gridTransient) && !guidesHidden }
    /// Geometrie în editare: decupare (cadrul întreg + suprapunere de decupare) sau îndreptare cu 2 puncte; «cadrul sursă» arată fotografia necropată pentru editarea măștilor.
    public enum GeometryMode: Equatable { case none, crop, straighten }
    @Published public var geometryMode: GeometryMode = .none { didSet { if oldValue != geometryMode { scheduleRender(immediate: true) } } }
    @Published public var sourceFrameView = false { didSet { if oldValue != sourceFrameView { scheduleRender(immediate: true) } } }
    @Published public var showGrid = false
    @Published public var straightenPoints: [CGPoint] = []
    @Published public private(set) var sourceSize = CGSize.zero          // pixeli ai sursei la rezoluție plină (estimată din previzualizare ×2 până se încarcă rezultatul plin)
    /// Reglajele cu care se RANDEAZĂ vederea: în modul decupare se arată cadrul întreg (rotit), iar «cadrul sursă» arată fotografia fără geometrie; exportul folosește mereu reglajele reale.
    func viewAdj(_ a: AdjustmentSet) -> AdjustmentSet { var b = a; if sourceFrameView { b.geometry = Geometry() } else if geometryMode == .crop && !guidesHidden { b.geometry.crop = CropRect() }; return b }
    /// Analiză (culoare falsă, tăieri, saturație, ton piele, histogramă): vedere de lucru, NICIODATĂ în export.
    @Published public var analysisMode: AnalysisMode = .off { didSet { if oldValue != analysisMode { scheduleAnalysis() } } }
    @Published public var showHistogram = true { didSet { if oldValue != showHistogram { scheduleAnalysis() } } }
    @Published public var showVectorscope = false { didSet { if oldValue != showVectorscope { scheduleAnalysis() } } }
    @Published public var showParade = false { didSet { if oldValue != showParade { scheduleAnalysis() } } }
    /// Amplificarea diferenței NR (×); doar afișare, nu intră în reglaje.
    @Published public var nrDiffGain: Double = 4 { didSet { if oldValue != nrDiffGain, analysisMode == .nrDifference { scheduleAnalysis() } } }
    @Published public var analysisResult: AnalysisResult?
    @Published public var analysisImage: NSImage?
    @Published public var analysisBusy = false
    private var analysisGen = 0
    /// Construirea măștii (separată de reglajele corecției): componenta selectată, unealta activă, punctul selectat, pensula; anulare/refacere pe editările de mască.
    public enum MaskTool: Equatable { case select, drawPath, brushAdd, brushErase }
    @Published public var maskTool: MaskTool = .select
    @Published public var selectedComponent: String?
    @Published public var selectedPoint: Int?
    @Published public var brushRadius = 0.04          // rază = fracție din înălțimea fotografiei
    @Published public var brushSoftness = 0.5
    @Published public private(set) var maskUndo: [[LocalCorrection]] = []
    @Published public private(set) var maskRedo: [[LocalCorrection]] = []
    var maskGestureOpen = false
    /// Ultima resetare (parametru / secțiune / tot): starea anterioară, pentru „Anulează” (⌘Z). Dispare după câteva secunde sau la o modificare nouă.
    @Published public var lastReset: (message: String, previous: AdjustmentSet)?
    private var resetBannerTask: Task<Void, Never>?; private var keepBannerOnce = false
    /// Fotografia curentă are reglaje salvate sub o revizie mai veche a motorului (aspect schimbat de corectarea matematicii).
    @Published public var legacyNotice = ""
    // „Profilul meu” — registru de perechi RAW–final, confirmare explicită, ciorne de profil (fără estimare; vezi docs/PROFILE_FROM_EXAMPLES.md)
    @Published public var profileRegistry = ProfileRegistry() { didSet { if !loadingRegistry { try? profileRegistry.save(to: catalog) } } }
    @Published public var profileMessage = ""
    private var loadingRegistry = false
    private var editsDirty = false   // reglajele curente au fost modificate de utilizator (abia atunci se stampilează revizia curentă a motorului)
    // „Continuă în Resolve” (opțional; necesită DaVinci Resolve Studio)
    @Published public var handoff: HandoffUIState = .idle
    @Published public var resolveResultImage: NSImage?; @Published public var resolveReadback: [String] = []
    @Published public var resolveResultURL: URL?; @Published public var resolveExportNote = ""
    private var handoffBridge: ResolveHandoff?; private var handoffSize: (w: Int, h: Int)?; private var handoffStem = ""; private var handoffTimeline = ""
    @Published public var compare: CompareMode = .after
    @Published public var suggestion: ExposureSuggestion?
    @Published public private(set) var approvals: [Int64: String] = [:]      // id → amprenta reglajelor la aprobare; aprobarea e valabilă DOAR cât amprenta coincide cu reglajele salvate
    @Published public var approvalNote = ""
    @Published public private(set) var thumbs: [Int64: NSImage] = [:]
    @Published public var exportState: ExportRunState = .idle
    @Published public var exportScope: ExportScope = .approved
    @Published public var exportFormatJPEG = false; @Published public var jpegQuality = 0.95
    @Published public var exportFolder: URL?
    /// Setat de AppModel când discul de lucru nu e disponibil: exportul/predarea se opresc controlat (fără scriere pe alt disc).
    @Published public var storageBlocked = false
    @Published public var exportFailures: [(path: String, reason: String)] = []
    @Published public private(set) var exported: [(photo: String, path: String)] = []
    @Published public var batchProgress: (done: Int, total: Int)?
    // Revizuire: rezultatul unei miniaturi e «actual» doar când amprenta cu care a fost randat coincide cu amprenta reglajelor salvate (nimic depășit nu e prezentat drept final).
    @Published public private(set) var thumbFP: [Int64: String] = [:]
    @Published public private(set) var reviewFailures: [Int64: String] = [:]
    @Published public private(set) var reviewProcessing: Int64?
    private var reviewPending: [Int64] = []; private var reviewTask: Task<Void, Never>?
    /// Poarta funcțiilor (politica comercială, separată de verificarea dreptului). Implicit totul e permis; se leagă din AppModel.
    public var featureGate: (PhotoFeature) -> Bool = { _ in true }
    private var revertingLocked = false
    public static let lockedMessage = L("Editarea, profilurile și exportul sunt oprite până la reactivarea dreptului foto. Biblioteca, originalele și editările salvate rămân accesibile.")
    public var editsLocked: Bool { !featureGate(.editProcessing) }
    @Published public var exportCollision: ExportCollision = .unique { didSet { try? catalog.setSession("export_collision", exportCollision.rawValue); if exportCollision != .overwrite { exportOverwriteConfirmed = false } } }
    @Published public var exportOverwriteConfirmed = false
    public struct ExportItem: Identifiable, Equatable {
        public enum State: Equatable { case waiting, running, done(String), skipped(String), failed(String) }
        public let id: Int64; public let name: String; public var state: State
    }
    @Published public private(set) var exportItems: [ExportItem] = []
    // inspecție 100% a rezultatului procesat (la cerere)
    @Published public var detailOpen = false; @Published public var detailBusy = false
    @Published public var detailAfter: NSImage?; @Published public var detailBase: NSImage?; @Published public var detailInfo = ""; @Published public var detailError = ""

    public let catalog: Catalog; public let workDir: URL
    private var bridge: ResolveBridge?; private var resolveProcessor: PhotoProcessor?; var ownProcessor: OwnCoreProcessor?
    private let queue = DispatchQueue(label: "photoassist.resolve", qos: .userInitiated)
    /// Cozi separate: răspunsul interactiv nu așteaptă după previzualizări, analize sau rezoluția plină (măsurat: așteptarea pe coada comună era blocajul dominant, ~670 ms din ~1,8 s).
    private let interactiveQueue = DispatchQueue(label: "photoassist.interactive", qos: .userInteractive)
    private let analysisQueue = DispatchQueue(label: "photoassist.analysis", qos: .utility)
    private let fullQueue = DispatchQueue(label: "photoassist.fullres", qos: .utility)   // rezoluția plină nu blochează previzualizările
    public let viewer = ViewerState()
    public let panels = PanelState()
    /// Ferestre flotante opționale (analiză, histogramă, lupă): aceeași sursă de procesare, fără motor propriu.
    public let floating = FloatingPanels()
    public let analysisHub = AnalysisHub()
    /// Momentul ultimei actualizări a analizei (indicator în ferestrele flotante).
    @Published public var analysisUpdatedAt: Date?
    // Lupă de inspecție (vedere de lucru, nu intră în reglaje sau export)
    @Published public var loupeOn = false
    @Published public var loupeCenter = CGPoint(x: 0.5, y: 0.5)        // normalizat în imaginea de ieșire
    @Published public var loupeMag: CGFloat = 1                         // 1 = 100% (un pixel de imagine pe un pixel fizic)
    @Published public var loupeFollow = false                           // urmărește cursorul (implicit manual/fixat)
    @Published public var loupeBase = false
    @Published public var loupeViewPts = CGSize(width: 280, height: 280) // dimensiunea panoului lupei, în puncte
    @Published var faceFrameVerdict: [Int64: FaceFrameContract.Verdict] = [:]   // per fotografie: contractul cadrului de față verificat
    @Published public var loupeTarget = ""                              // descrierea țintei alese explicit (față/ochi/zonă)
    /// Unealta activă din bara de deasupra fotografiei; schimbarea ei NU șterge și nu dezactivează ajustările, doar arată opțiunile ei în inspector.
    public enum EditTool: String { case view, geometry, masks, analysis, chart, retouch }
    @Published public var activeTool: EditTool = .view
    public func moduleBinding(_ id: String) -> Binding<Bool> { Binding(get: { self.adjustments.isModuleEnabled(id) }, set: { on in if on { self.adjustments.disabledModules.remove(id) } else { self.adjustments.disabledModules.insert(id) } }) }
    /// Încheie coerent interacțiunea uneltei curente (comun pentru Gata și schimbarea uneltei): geometria și măștile rămân; dispar doar ghidajele uneltei. O formă neterminată se tratează EXPLICIT (contur ≥ 3 puncte se închide; mai puțin = anulat, cu mesaj și posibilitate de anulare).
    @discardableResult public func finishEditing() -> String? {
        var note: String?
        if let li = localIndex(selectedLocal) {
            let ci = componentIndex(li); let c = adjustments.locals[li].components[ci]
            if c.kind == .path && !c.closed && !(maskTool == .select && c.points.isEmpty && false) && maskTool == .drawPath {
                if c.points.count >= 3 { beginMaskEdit(); adjustments.locals[li].components[ci].closed = true; endMaskEdit(); note = LF("Conturul neterminat a fost închis (%@ puncte).", c.points.count) }
                else { registerReset("Conturul neterminat (\(c.points.count) puncte) a fost anulat"); if adjustments.locals[li].components.count > 1 { beginMaskEdit(); adjustments.locals[li].components.remove(at: ci); endMaskEdit() } else { adjustments.locals.remove(at: li); selectedLocal = nil }; selectedComponent = nil; note = L("Conturul neterminat a fost anulat.") }
            }
        }
        geometryMode = .none; straightenPoints = []; maskTool = .select; selectedPoint = nil; faceZoneIdle()
        return note
    }
    private func faceZoneIdle() {}
    /// «Editează decuparea»: revenire la cadrul întreg cu suprapunerea de decupare (decuparea alesă rămâne și se regăsește).
    public func editCrop() { selectTool(.geometry); geometryMode = .crop; guidesHidden = false }
    /// Încheie gesturile active pe pânză (navigare între ecrane, schimbarea uneltei): formele neterminate se tratează explicit, deplasarea/Space se resetează.
    public func endCanvasGestures() { finishEditing(); viewer.panning = false; viewer.spaceDown = false }
    public func selectTool(_ t: EditTool) {
        if t != activeTool || t == .view { finishEditing() }
        activeTool = t
        if t != .geometry { geometryMode = .none }; if t != .masks { maskTool = .select }
        switch t { case .view: break; case .geometry: panels.reveal("geometry"); case .masks: panels.reveal("locals"); case .analysis: panels.reveal("analysis"); case .chart: panels.reveal("chart"); case .retouch: panels.reveal("retouch") }
    }
    private var viewerSub: AnyCancellable?
    private var fullRefreshTask: Task<Void, Never>?
    @Published public var detailFingerprint: String?
    private var restoring = false; private var renderTask: Task<Void, Never>?; private var renderGen = 0
    private var saveTask: Task<Void, Never>?; private var detailTask: Task<Void, Never>?
    public static let projectName = "GDC_PHOTO_ASSIST_WORK_0001"

    public init(catalog: Catalog, workDir: URL) {
        defer { escObserver = NotificationCenter.default.addObserver(forName: .gdcCancelTool, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancelPickers() } } }
        self.catalog = catalog; self.workDir = workDir; bindViewer(); floating.ed = self; analysisHub.ed = self
        for m in PackagedResources.missing { DiagnosticLog.shared?.log(.error, "resources", "missing", "\(m.name) — \(m.module): funcția afectată arată eroare explicită") }
        ownProcessor = try? OwnCoreProcessor(workDir: workDir.appendingPathComponent("own"), log: DiagnosticLog.shared)
        if AppInfo.internalTools, (try? catalog.session("engine")) == "resolveStyle" { engine = .resolveStyle }   // motorul STYLE = unealtă internă de comparație, nu face parte din traseul clientului
        if let ot = try? catalog.session("output_transform"), let v = OutputTransform(rawValue: ot) { outputTransform = v.effective }
        ownProcessor?.outputTransform = outputTransform; _ = GDCDRTData.load(devRoot: AppInfo.devRoot)
        if let s = try? catalog.session("approved_v2"), let d = s.data(using: .utf8), let m = try? JSONDecoder().decode([String: String].self, from: d) { approvals = Dictionary(uniqueKeysWithValues: m.compactMap { k, v in Int64(k).map { ($0, v) } }) }
        // cheia veche „approved” (fără amprentă) nu se mai folosește: o aprobare fără amprentă nu poate fi verificată
        loadingRegistry = true; profileRegistry = ProfileRegistry.load(from: catalog); loadingRegistry = false
        if let f = try? catalog.session("export_folder") { exportFolder = URL(fileURLWithPath: f) }
        exportFormatJPEG = (try? catalog.session("export_format")) == "jpeg"
        fastGesturePreview = (try? catalog.session("fast_gesture_preview")) == "1"
        if let c = (try? catalog.session("export_collision")).flatMap({ $0 }).flatMap({ ExportCollision(rawValue: $0) }) { exportCollision = c }
    }

    // MARK: conexiune
    public func connect(allowSwitch: Bool = false) {
        guard connection != .connecting else { return }
        connection = .connecting
        let work = workDir
        queue.async { [weak self] in
            var result: EditConnection; var br: ResolveBridge?; var pr: PhotoProcessor?
            do {
                let b = try ResolveBridge(tempDir: work.appendingPathComponent("temp")); try b.start()
                do { try b.ensureProject(EditingModel.projectName, allowSwitch: allowSwitch) }
                catch BridgeError.remote(let code, _) where code == "switch_not_allowed" { b.stop(); result = .needsConsent(b.info?.currentProject ?? L("alt proiect")); DispatchQueue.main.async { self?.connection = result }; return }
                pr = try PhotoProcessor(bridge: b, workDir: work.appendingPathComponent("resolve"), projectName: EditingModel.projectName); br = b
                let i = b.info!; result = .ready("Resolve \(i.version)" + (i.verified ? "" : L(" · versiune neverificată")))
            } catch { result = .unavailable("\(error)") }
            DispatchQueue.main.async { guard let self = self else { return }; self.bridge = br; self.resolveProcessor = pr; self.connection = result; DiagnosticLog.shared?.log(.info, "resolve", "connect", "\(result)"); if case .ready = result { self.scheduleRender(immediate: true) } }
        }
    }
    public var isReady: Bool { switch engine { case .own: return ownProcessor != nil; case .resolveStyle: if case .ready = connection { return true }; return false } }
    /// Identificarea EXACTĂ a motorului și a transformării de ieșire (afișată în UI, export și diagnostic). „DRT p1” = PROTOTIP experimental, NU GDC DRT.
    public var engineName: String { engine == .own ? (!Edition.full ? L("Nucleu propriu (CPU) + redare deschisă") : outputTransform == .gdcDRTNatural ? L("Nucleu propriu (CPU) + GDC DRT Natural adaptat") : L("Prototip experimental (nucleu propriu CPU + DRT p1)")) : L("Resolve + STYLE (temporar; ieșire: GDC DRT Natural → sRGB)") }
    public var outputTransformName: String { engine == .own ? (!Edition.full ? L("Redare deschisă → sRGB") : outputTransform == .gdcDRTNatural ? L("GDC DRT (profil Natural), adaptat; redare → g2.4, apoi recodare sRGB o singură dată") : L("DRT p1 — PROTOTIP EXPERIMENTAL → sRGB (nu e GDC DRT)")) : "GDC DRT, profil Natural → sRGB (modulul STYLE, prin Resolve)" }
    private func outputTransformChanged() {
        try? catalog.setSession("output_transform", outputTransform.rawValue); ownProcessor?.outputTransform = outputTransform; DiagnosticLog.shared?.log(.info, "engine", "output_transform", outputTransform.rawValue)
        renderTask?.cancel(); afterImage = nil; beforeImage = nil; thumbs = [:]; thumbFP = [:]; afterInfo = ""; closeDetail(); if isReady { scheduleRender(immediate: true) }
    }
    /// Amprenta aprobării: reglajele + transformarea de ieșire (schimbarea DRT-ului schimbă imaginea aprobată).
    /// Amprenta reglajelor, MEMORATĂ (două intrări): view-urile o cer de mai multe ori la fiecare actualizare; calculul ei (formatare de zeci de valori) apărea în profilul firului principal în timpul gestului.
    private var fpMemo: [(adj: AdjustmentSet, fp: String)] = []
    func memoFingerprint(_ a: AdjustmentSet) -> String {
        if let m = fpMemo.first(where: { $0.adj == a }) { return m.fp }
        let f = a.fingerprint; fpMemo.insert((a, f), at: 0); if fpMemo.count > 3 { fpMemo.removeLast() }; return f
    }
    private func approvalFingerprint(_ a: AdjustmentSet) -> String { memoFingerprint(a) + "|" + (engine == .own ? outputTransform.rawValue : "style") + "|core\(AdjustmentSet.currentEngineRevision)" }   // revizia motorului în amprentă: aprobările făcute sub o revizie mai veche devin „anulate”
    private func engineChanged() {
        try? catalog.setSession("engine", engine.rawValue); DiagnosticLog.shared?.log(.info, "engine", "switch", engine.rawValue)
        renderTask?.cancel(); afterImage = nil; beforeImage = nil; thumbs = [:]; thumbFP = [:]; afterInfo = ""; closeDetail()
        if engine == .resolveStyle, case .idle = connection { connect() }
        if isReady { scheduleRender(immediate: true) }
    }

    // MARK: fotografia curentă (reglajele salvate se păstrează; nimic nu se aplică automat)
    public func open(_ p: PhotoRecord) {
        NotificationCenter.default.post(name: .gdcCommitNumericFields, object: nil)   // un câmp numeric în curs de editare se confirmă pe fotografia curentă, înainte de schimbare
        guard current?.id != p.id else { return }
        let zoomToKeep: CGFloat? = (current != nil && !viewer.isFit) ? viewer.custom : nil
        flushSave(); closeDetail(); viewer.setFit(); viewer.fullSize = .zero; viewer.carriedZoom = zoomToKeep
        resetBannerTask?.cancel(); lastReset = nil; redoState = nil; activationBanner = false; gestureSnapshot = nil   // istoricul aparține fotografiei editate: nu se aplică pe următoarea
        renderTask?.cancel(); current = p; afterImage = nil; beforeImage = nil; afterInfo = ""; suggestion = nil; approvalNote = ""
        restoring = true; adjustments = adjustmentsFor(p.id); restoring = false; editsDirty = false; loadChartSession(); loupeCenter = CGPoint(x: 0.5, y: 0.5); loupeTarget = ""   // la schimbarea cadrului nu se presupune aceeași persoană/ochi
        legacyNotice = adjustments.isFromOlderEngine ? L("Reglajele acestei fotografii au fost salvate cu motorul de calcul anterior (dev.4 și mai vechi). Valorile sunt păstrate, dar umbrele, luminile, saturația și balansul arată acum diferit după corectarea matematicii (aliniată cu STYLE V3). Aprobarea veche e anulată: verifică imaginea și aprob-o din nou.") : ""
        try? catalog.setSession("current_photo", "\(p.id)")
        if isReady { scheduleRender(immediate: true) }
    }
    /// Aplicare EXPLICITĂ a sugestiei: valoarea manuală devine sugestia rotunjită (modul manual); utilizatorul o poate modifica apoi.
    public func applySuggestion() { guard let s = suggestion else { return }; var a = adjustments; a.exposureAuto = false; a.exposure = max(-4, min(8, (s.stops * 10).rounded() / 10)); adjustments = a }
    public func setAutoMode(_ on: Bool) { var a = adjustments; a.exposureAuto = on; if on { a.autoOffset = 0 }; adjustments = a }
    public func applyPreset(_ id: String) { guard let pr = StylePreset.all.first(where: { $0.id == id }) else { return }; adjustments = pr.applied(to: adjustments) }
    /// Editările legate de POZIȚII din cadrul vechi (3:2): schimbarea cadrului în 4:3 le-ar deplasa, iar remaparea nu e verificată ⇒ actualizarea dezvoltării RAW se blochează cât există oricare.
    public func rawUpdateBlockers() -> [String] {
        let a = adjustments; var r: [String] = []
        if !a.geometry.isNeutral { r.append(L("decupare / geometrie")) }
        if !a.locals.isEmpty { r.append(L("corecții locale și măști")) }
        if !a.retouch.isEmpty { r.append(L("retuș")) }
        if !a.effects.framingIsNeutral || a.effects.lensVignette != 0 { r.append(L("optică (distorsiune, aberație, vinietă)")) }
        return r
    }
    /// Acțiune explicită și anulabilă: dezvoltarea RAW veche → corectată. Refuză dacă există editări legate de poziții din cadrul vechi.
    public func updateRawDevelopment() {
        guard adjustments.rawDev.isLegacyDecode, rawUpdateBlockers().isEmpty else { return }
        registerReset(L("Dezvoltarea RAW a fost actualizată (poți anula)")); var d = RawDevelopment(); d.baseline = adjustments.rawDev.baseline; d.manualEV = adjustments.rawDev.manualEV; adjustments.rawDev = d
    }
    /// „Resetează tot”: TOATE ajustările fotografiei (globale + corecții locale); anulabil.
    public func resetAdjustments() { registerReset(L("Toate ajustările au revenit la neutru")); var f = AdjustmentSet.fresh(adjustments.family); f.rawDev = adjustments.rawDev; adjustments = f; selectedLocal = nil }   /* dezvoltarea RAW (revizia + compensarea) NU se resetează în tăcere */   /* familia de lucru rămâne: nu e o reglare */
    /// Înregistrează starea ANTERIOARĂ unei resetări (apelat de rândul/secțiunea ÎNAINTE de a schimba valoarea). Resetarea însăși trece prin `adjustments` (cache, randare, invalidarea aprobării).
    public func registerReset(_ message: String) {
        redoState = nil; lastReset = (message, adjustments); activationBanner = false; keepBannerOnce = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.keepBannerOnce = false }; resetBannerTask?.cancel()
        resetBannerTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 12_000_000_000); if !Task.isCancelled { self?.lastReset = nil } }
    }
    public func undoLastReset() { guard let r = lastReset else { return }; resetBannerTask?.cancel(); lastReset = nil; activationBanner = false; let now = adjustments; applyingHistory = true; adjustments = r.previous; applyingHistory = false; setRedo((r.message, now)) }
    public func redoLastReset() {
        guard let r = redoState else { return }; redoState = nil; redoTask?.cancel(); let now = adjustments
        applyingHistory = true; adjustments = r.state; applyingHistory = false
        lastReset = (r.message, now); keepBannerOnce = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.keepBannerOnce = false }   // după Refă, Anulează e din nou disponibil
        resetBannerTask?.cancel(); resetBannerTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 12_000_000_000); if !Task.isCancelled { self?.lastReset = nil } }
    }
    /// Refacerea (⇧⌘Z) a ultimei anulări; se pierde la o modificare nouă sau după 12 s.
    @Published public private(set) var redoState: (message: String, state: AdjustmentSet)?
    private var redoTask: Task<Void, Never>?; private var applyingHistory = false
    private func setRedo(_ r: (String, AdjustmentSet)) { redoState = (r.0, r.1); redoTask?.cancel(); redoTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 12_000_000_000); if !Task.isCancelled { self?.redoState = nil } } }
    // Gest continuu pe o valoare (tragere / rafală de taste): O singură operație de anulare, indiferent de numărul de pași.
    private var gestureSnapshot: AdjustmentSet?; private var gestureLabel = ""
    public func beginGesture(_ label: String) { gestureSnapshot = adjustments; gestureLabel = label; redoState = nil }
    public func endGesture() {
        guard let s = gestureSnapshot else { return }; gestureSnapshot = nil
        guard s != adjustments else { return }
        let message = activationBanner ? (lastReset?.message ?? LF("«%@» a fost reglată", gestureLabel)) : LF("«%@» a fost reglată", gestureLabel)
        lastReset = (message, s); keepBannerOnce = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.keepBannerOnce = false }; resetBannerTask?.cancel()
        let wasActivation = activationBanner
        resetBannerTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 12_000_000_000); if !Task.isCancelled { self?.lastReset = nil; if wasActivation { self?.activationBanner = false } } }
    }
    /// Escape în timpul gestului: valoarea (și activarea automată a modulului) revin la starea de la începutul gestului.
    public func cancelGesture() { guard let s = gestureSnapshot else { return }; gestureSnapshot = nil; resetBannerTask?.cancel(); lastReset = nil; activationBanner = false; adjustments = s; lastReset = nil }
    /// D-WS-2: o modificare deliberată a valorilor unui modul opțional dezactivat îl ACTIVEAZĂ (stare vizibilă în comutator + mesaj cu «Anulează», care readuce starea dinainte). Deschiderea panoului nu schimbă nimic aici.
    private var activationBanner = false
    /// Numele AFIȘATE ale modulelor opționale (aceleași titluri ca în inspector), nu identificatorii interni.
    static let moduleTitles: [String: String] = ["tonalbalance": "Balans tonal (umbre / lumini)", "printer": "Lumini de imprimare (printer lights)", "channelmix": "Mixer de canale", "wheels": "Tonuri: LGG · roți · CDL",
        "huevectors": "Vectori de nuanță (6 culori)", "highlights": "Lumini și gamă", "color": "Culoare selectivă", "skin": "Piele (după culoare)", "diffusion": "Difuzie și bloom (filtru de obiectiv)", "look": "Look (caracter)",
        "detail": "Detalii (zgomot, claritate, accentuare)", "retouch": "Retuș (clonă și vindecare)", "optics": "Optică", "film": "Aspect pelicular (simplu)", "grain": "Grăunte (simplu)", "film3": "Film (fotochimic)",
        "cinema": "Stiluri cinema (bibliotecă)", "chart": "Chart de culoare (ColorChecker)"]
    static func activationMessage(_ ids: [String]) -> String {
        let names = ids.map { moduleTitles[$0].map { L($0) } ?? $0 }.joined(separator: ", ")
        return ids.count == 1 ? LF("Modulul s-a activat prin modificare: %@", names) : LF("Modulele s-au activat prin modificare: %@", names)
    }
    private func activateEditedModules(old: AdjustmentSet) {
        let ids = adjustments.modulesToActivate(from: old); guard !ids.isEmpty else { return }
        for i in ids { adjustments.disabledModules.remove(i) }
        lastReset = (Self.activationMessage(ids), old); activationBanner = true; keepBannerOnce = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.keepBannerOnce = false }; resetBannerTask?.cancel()
        resetBannerTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 12_000_000_000); if !Task.isCancelled { self?.lastReset = nil; self?.activationBanner = false } }
    }
    public func resetSection(_ name: String, _ change: (inout AdjustmentSet) -> Void) { registerReset(LF("Secțiunea «%@» a revenit la neutru", name)); var a = adjustments; change(&a); adjustments = a }
    public func resetLocalAdjustments(_ id: String) { guard let i = localIndex(id) else { return }; registerReset(LF("Ajustările «%@» au revenit la neutru", adjustments.locals[i].name)); adjustments.locals[i].resetAdjustments() }

    /// Exportul REZULTATULUI din Resolve (inclusiv măștile/nodurile adăugate de fotograf în Resolve, care nu există ca obiecte în FotoAsist): TIFF-ul randat de Resolve, cu profil ICC sRGB atașat, în folderul de export ales.
    public func exportResolveResult() {
        guard featureGate(.resolveHandoff) else { statusLine = Self.lockedMessage; return }
        let nLoc = adjustments.effective.locals.filter { $0.isActiveLocal }.count + (adjustments.effective.effects.hasPostEffects ? 1 : 0) + (adjustments.effective.tools.isNeutral ? 0 : 1) + (adjustments.effective.retouch.contains { $0.enabled } ? 1 : 0) + (adjustments.effective.chart == nil ? 0 : 1) + (adjustments.effective.look.on ? 1 : 0)   // efectele după eșantionare (vinietă, peliculă, grain) se tratează ca elemente care nu se transferă editabil
        if nLoc > 0 && handoffLocalsPolicy == nil { resolveExportNote = LF("Nu export: rezultatul din Resolve NU conține cele %@ elemente FotoAsist (corecții locale / vinietă, peliculă, grain). Predă din nou în Resolve alegând «integrate» (rezultatul lor se păstrează) sau «fără corecții locale» (excludere explicită).", nLoc); return }
        guard let url = resolveResultURL, let photo = current else { resolveExportNote = L("Nu există un rezultat din Resolve. Apasă „Actualizează din Resolve”."); return }
        guard let dest = exportFolder else { chooseExportFolder(); if exportFolder == nil { return }; exportResolveResult(); return }
        do { let stem = ((photo.path as NSString).lastPathComponent as NSString).deletingPathExtension
            let out = try ExportService.export(result: url, original: URL(fileURLWithPath: photo.path), to: dest, name: stem + "_GDC_Resolve", format: exportFormatJPEG ? .jpeg(quality: jpegQuality) : .tiff16)
            try? catalog.logExport(photoId: photo.id, path: out.path, format: exportFormatJPEG ? "jpeg" : "tiff16"); resolveExportNote = LF("Exportat din Resolve: %@", out.path)
        } catch { resolveExportNote = "\(error)" }
    }

    // MARK: „Profilul meu”
    public func addExamplePair(photographer: String, setName: String) {
        let o = NSOpenPanel(); o.canChooseFiles = true; o.canChooseDirectories = false; o.allowsMultipleSelection = false; o.message = L("Alege fișierul RAW"); o.prompt = L("Alege RAW")
        guard o.runModal() == .OK, let raw = o.url else { return }
        o.message = L("Alege finalul editat al aceleiași fotografii (JPEG/TIFF)"); o.prompt = "Alege finalul"
        guard o.runModal() == .OK, let fin = o.url else { return }
        do { try profileRegistry.addPair(raw: raw.path, final: fin.path, photographer: photographer, setName: setName); profileMessage = L("Pereche înregistrată ca PROPUSĂ; nu devine exemplu până o confirmi.") } catch { profileMessage = "\(error)" }
    }
    // MARK: schimb de profil (export / import)
    /// Salvează profilul ca fișier de schimb versionat (fără fotografii de antrenare, căi sau date personale). Alegerea locației e a utilizatorului.
    public func exportProfile(_ id: String) {
        guard let pr = profileRegistry.profiles.first(where: { $0.id == id }) else { return }
        do {
            let data = try ProfileExchange.export(pr, engineIdentity: ProfileEstimator.engineIdentity, paramSet: ProfileEstimator.parameterNames, trustLabel: profileTrustLabel(pr))
            let panel = NSSavePanel(); panel.nameFieldStringValue = pr.name.replacingOccurrences(of: "/", with: "-") + ".gdcprofile.json"; panel.title = L("Exportă profilul")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic); profileMessage = LF("Profil exportat: %@ (doar parametrii estimați; fără fotografii, căi sau date personale).", url.lastPathComponent)
        } catch { profileMessage = "\(error)" }
    }
    /// Importă un profil dintr-un fișier de schimb: validează formatul, suma de control, motorul și parametrii; tratează duplicatele; NU îl face «evaluat».
    public func importProfile(photographer: String, setName: String) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false; panel.title = L("Importă profil")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= ProfileExchange.maxBytes else { profileMessage = ProfileExchange.ImportError.tooLarge.description; return }
        guard let data = try? Data(contentsOf: url) else { profileMessage = L("Fișierul nu a putut fi citit."); return }
        var reg = profileRegistry
        switch ProfileExchange.importProfile(data, into: &reg, photographer: photographer, setName: setName, engineIdentity: ProfileEstimator.engineIdentity, paramSet: ProfileEstimator.parameterNames, engineVersionLabel: engineName + " · " + String(cString: pc_version())) {
        case .failure(let e): profileMessage = e.description
        case .success(.duplicate(let ex)): profileMessage = LF("Profilul există deja («%@» v%@); nu s-a adăugat nimic.", ex.name, ex.version)
        case .success(.added(let p)): profileRegistry = reg; profileMessage = LF("Profil importat: «%@» v%@ — NEEVALUAT pe exemplele tale (transferabilitatea între camere și iluminări rămâne de evaluat).", p.name, p.version)
        }
    }
    public func confirmPair(_ id: String) { do { try profileRegistry.confirm(id, statement: ProfileRegistry.confirmationText); profileMessage = "" } catch { profileMessage = "\(error)" } }
    public func rejectPair(_ id: String) { try? profileRegistry.reject(id) }
    public func removePair(_ id: String) { profileRegistry.remove(id) }
    public func createDraftProfile(name: String, photographer: String, setName: String) {
        let ids = profileRegistry.confirmedPairs(photographer: photographer, setName: setName).map { $0.id }
        do { let p = try profileRegistry.makeDraftProfile(name: name, pairIDs: ids, engineVersion: engineName + " · " + String(cString: pc_version()), technicalPolicy: L("LibRaw · alb per cameră · balans cameră · politică lumini clipSaturated · decupare implicită")); profileMessage = LF("Ciornă «%@» v%@ creată din %@ perechi confirmate. ", p.name, p.version, p.pairIDs.count) + (profileRegistry.estimationBlocker(for: p) ?? "") } catch { profileMessage = "\(error)" }
    }

    // Color / Skin: selecția vizibilă pe imagine + Pick Color (SPEC §23)
    @Published public var selectionKind: Int?          // nil = ascuns · 0 = selecția Color · 1 = pielea detectată
    @Published public var colorPicking = false
    /// «Doar fotografia»: ascunde filmul, inspectorul și barele (doar vizualizare; nicio valoare nu se schimbă, starea editării se păstrează).
    @Published public var photoOnly = false
    @Published public var retouchNewMode: RetouchSpot.Mode = .heal
    @Published public var retouchNewRadius = 0.02
    @Published public var selectedRetouch: String?
    /// Istoric propriu al retușului (orice schimbare: punct nou, tragere, rază, mod, ștergere); gesturile apropiate (<0,8 s) se unesc într-un singur pas.
    @Published public private(set) var retouchUndo: [[RetouchSpot]] = []
    @Published public private(set) var retouchRedo: [[RetouchSpot]] = []
    private var retouchStamp = Date.distantPast
    private var inRetouchHistory = false
    private func trackRetouch(old: [RetouchSpot]) {
        guard !inRetouchHistory, old != adjustments.retouch else { return }
        let now = Date(); if now.timeIntervalSince(retouchStamp) > 0.8 || retouchUndo.isEmpty { retouchUndo.append(old); if retouchUndo.count > 100 { retouchUndo.removeFirst() } }
        retouchStamp = now; retouchRedo = []
    }
    public func undoRetouch() { guard let p = retouchUndo.popLast() else { return }; inRetouchHistory = true; retouchRedo.append(adjustments.retouch); adjustments.retouch = p; inRetouchHistory = false; retouchStamp = .distantPast; fixRetouchSelection() }
    public func redoRetouch() { guard let p = retouchRedo.popLast() else { return }; inRetouchHistory = true; retouchUndo.append(adjustments.retouch); adjustments.retouch = p; inRetouchHistory = false; retouchStamp = .distantPast; fixRetouchSelection() }
    private func fixRetouchSelection() { if let s = selectedRetouch, !adjustments.retouch.contains(where: { $0.id == s }) { selectedRetouch = nil } }
    /// Adaugă un punct de retuș în coordonatele sursei; sursa se pune lângă destinație (pe orizontală, la 2,6 raze), de tras pe o zonă curată.
    public func addRetouch(nx: Double, ny: Double) {
        guard current != nil else { return }; registerReset(L("Punct de retuș adăugat"))
        var s = RetouchSpot(); s.mode = retouchNewMode; s.radius = retouchNewRadius; s.x = nx; s.y = ny
        let aspect = max(0.1, Double(sourceSize.height / max(1, sourceSize.width))); let off = 2.6 * s.radius * aspect
        s.sx = nx + off <= 0.97 ? nx + off : max(0.03, nx - off); s.sy = ny
        adjustments.retouch.append(s); selectedRetouch = s.id
    }
    @Published public var histogramScale: HistogramScale = HistogramScale(rawValue: UserDefaults.standard.string(forKey: "gdcpa.histogram.scale") ?? "") ?? .linear { didSet { UserDefaults.standard.set(histogramScale.rawValue, forKey: "gdcpa.histogram.scale") } }
    /// Fotografii care nu s-au putut procesa (motivul se raportează; coada continuă cu celelalte, nimic nu se scoate din catalog automat).
    @Published public var failedPhotos: [Int64: String] = [:]
    /// Imaginea afișată e previzualizarea interactivă (redusă); rezultatul complet (`preview`) urmează după pauză. Doar indicator; nu schimbă procesarea.
    @Published public var refining = false
    /// Opacitatea petecelor colorate de referință peste fotografie, în modul Chart (preferință de vizualizare; nu intră în procesare sau export).
    @Published public var chartOverlayOpacity = 0.35
    @Published public var colorPickNote = ""
    public func pickColor(nx: Double, ny: Double) {
        guard let own = ownProcessor, let photo = current else { return }; let a = adjustments
        Task.detached { [weak self] in
            let r = try? own.pickColor(photoPath: photo.path, nx: nx, ny: ny, adjustments: a)
            await MainActor.run { guard let self = self else { return }
                if let r = r { self.registerReset(L("Culoare aleasă pentru selecție")); self.adjustments.tools.colorOn = true; self.adjustments.tools.colorHue = r.hue; self.adjustments.tools.colorC = r.c; self.adjustments.tools.colorL = r.l; self.colorPickNote = String(format: L("Aleasă: nuanță %.0f° · croma %.2f · %+.1f st"), r.hue, r.c, r.l); self.selectionKind = 0; self.colorPicking = false }
                else { self.colorPickNote = L("Punctul ales e gri sau fără nuanță definită: alege o zonă colorată.") } }
        }
    }
    @Published public var rangePicking = false
    @Published public var wbPicking = false
    private var escObserver: NSObjectProtocol?
    /// Escape: oprește orice prelevare activă (pipetă balans de alb, culoare, gamă); cursorul revine la săgeată odată cu dispariția stratului.
    func cancelPickers() { if wbPicking || colorPicking || rangePicking { wbPicking = false; colorPicking = false; rangePicking = false } }
    @Published public var wbNote = ""
    /// Pipeta de balans de alb: zona aleasă (clic = peticul 9×9, sau dreptunghi tras) devine neutră prin temperatură + tentă; un singur pas de anulare; limitele și zonele nepotrivite se raportează.
    public func pickNeutral(points: [(x: Double, y: Double)]) {
        guard let own = ownProcessor, let photo = current else { return }
        Task.detached { [weak self] in
            let rgb = try? own.linearSample(photoPath: photo.path, points: points); let r = rgb.flatMap { NeutralSolve.solve(rgb: $0) }
            await MainActor.run { guard let self = self else { return }; self.wbPicking = false
                guard let r = r else { self.wbNote = L("Zona aleasă e prea întunecată sau goală: alege o zonă gri luminată."); return }
                self.registerReset(L("Balans de alb din pipetă")); self.adjustments.temperature = r.temperature; self.adjustments.tint = r.tint
                self.wbNote = String(format: L("Neutru ales: temperatură %+.0f mired · tentă %+.3f. "), r.temperature, r.tint) + r.warnings.joined(separator: " ") }
        }
    }
    /// Pick Range: puncte din zona trasă (coordonate normalizate ale sursei) → centru + intervalele deduse din distribuție (mod dominant, outlieri respinși); puține eșantioane ⇒ doar centrul.
    public func pickRange(points: [(x: Double, y: Double)]) {
        guard let own = ownProcessor, let photo = current else { return }; let a = adjustments
        Task.detached { [weak self] in
            let r = try? own.pickRange(photoPath: photo.path, points: points, adjustments: a)
            await MainActor.run { guard let self = self else { return }
                if let r = r { self.registerReset(L("Gama de culoare aleasă pentru selecție")); var t = self.adjustments.tools; t.colorOn = true; t.colorHue = r.hue; t.colorC = r.c; t.colorL = r.l
                    if r.hasRange != 0 { t.colorRange = r.range; t.colorSatRange = r.satRange; t.colorLumRange = r.lumRange }; self.adjustments.tools = t
                    self.colorPickNote = String(format: L("Gamă aleasă din %d eșantioane (%d cromatice, %d folosite): nuanță %.0f° · croma %.2f · %+.1f st%@"), Int(r.samples), Int(r.chromatic), Int(r.used), r.hue, r.c, r.l, r.hasRange != 0 ? "" : L(" — puține eșantioane: doar centrul, intervalele rămân ale tale")); self.selectionKind = 0; self.rangePicking = false }
                else { self.colorPickNote = L("Zona aleasă e gri sau fără nuanță definită: trage peste o zonă colorată.") } }
        }
    }
    /// Matte-ul selecției (Color/Skin) pe grila vederii, ca imagine semi-transparentă (cyan); calculat în fundal.
    public func selectionImage(kind: Int, width: Int, height: Int) async -> NSImage? {
        guard let own = ownProcessor, let photo = current else { return nil }; let a = adjustments
        return await Task.detached { () -> NSImage? in
            guard let m = try? own.selectionMatte(photoPath: photo.path, adjustments: a, which: kind, width: width, height: height) else { return nil }
            var px = [UInt8](repeating: 0, count: width * height * 4); for i in 0..<(width * height) { let w = max(0, min(1, m[i])); px[i * 4] = 0; px[i * 4 + 1] = UInt8(220 * w * 0.8); px[i * 4 + 2] = UInt8(235 * w * 0.8); px[i * 4 + 3] = UInt8(255 * 0.7 * w) }
            guard let ctx = px.withUnsafeMutableBytes({ CGContext(data: $0.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) }), let cg = ctx.makeImage() else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: width, height: height)) }.value
    }
    // Chart de culoare (ColorChecker): poziționare manuală a grilei, validare, corecție tehnică, aplicare pe grup ales (SPEC §24)
    @Published public var chartModel: ChartModelID = .classicAfter2014
    @Published public var chartGrid = ChartGrid() { didSet { if chartGrid.isValid { lastValidChartGrid = chartGrid }; if oldValue != chartGrid { chartValidation = nil; chartProposal = nil }; saveChartSession() } }
    /// Ultima geometrie valida (pentru «Revino»): o grilă încrucișată în timpul tragerii nu se eșantionează și nu se pierde ultima bună.
    public private(set) var lastValidChartGrid = ChartGrid()
    public func chartRestoreLastValid() { chartGrid = lastValidChartGrid }
    @Published public var chartValidation: ChartValidation?
    @Published public var chartProposal: ChartCorrection?
    @Published public var chartBusy = false
    @Published public var chartMessage = ""
    private func chartKey(_ id: Int64) -> String { "chart_session:\(id)" }
    func saveChartSession() { guard let p = current, let d = try? JSONEncoder().encode(ChartSessionState(model: chartModel, grid: chartGrid)), let t = String(data: d, encoding: .utf8) else { return }; try? catalog.setSession(chartKey(p.id), t) }
    func loadChartSession() {
        chartValidation = nil; chartProposal = nil; chartMessage = ""
        guard let p = current, let t = (try? catalog.session(chartKey(p.id))) ?? nil, let st = try? JSONDecoder().decode(ChartSessionState.self, from: Data(t.utf8)) else { chartGrid = ChartGrid(); return }
        chartModel = st.model; chartGrid = st.grid
    }
    public func chartRotate() { chartGrid.rotate(); chartValidation = nil; chartProposal = nil }
    public func chartMirror() { chartGrid.mirrored.toggle(); chartValidation = nil; chartProposal = nil }
    public func chartResetGrid() { chartGrid = ChartGrid(); chartValidation = nil; chartProposal = nil }
    public func chartValidate() {
        guard chartGrid.isValid else { chartMessage = LF("Grila e nevalidă: %@. Corectează colțurile sau apasă «Revino la ultima grilă validă».", chartGrid.invalidReason ?? ""); return }
        guard !chartBusy, let own = ownProcessor, let photo = current else { return }; chartBusy = true; chartMessage = L("Eșantionez peticele…"); let grid = chartGrid, model = chartModel
        Task.detached { [weak self] in
            do {
                guard let info = ChartReference.load(model) else { throw NSError(domain: "chart", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Datele de referință ale chartului lipsesc.")]) }
                let inp = try own.estimationInputs(photoPath: photo.path); let samples = ChartSampler.sample(image: inp.image, grid: grid, clipLevel: ChartSampler.clipLevel(inp.image)); let v = ChartValidator.validate(samples, reference: info.patches)
                let prop = ChartFit.correct(samples: samples, validation: v, reference: info.patches, model: model, grid: grid, cameraKey: photo.camera, sourcePhotoID: photo.id)
                await MainActor.run { self?.chartValidation = v; self?.chartProposal = prop; self?.chartBusy = false; self?.chartMessage = v.message }
            } catch { await MainActor.run { self?.chartBusy = false; self?.chartMessage = LF("Validarea a eșuat: %@", error.localizedDescription) } }
        }
    }
    public func chartApply() {
        guard let c = chartProposal else { return }; registerReset(L("Corecția chartului a fost aplicată (poți anula)")); adjustments.chart = c; adjustments.disabledModules.remove("chart"); chartMessage = L("Corecție aplicată fotografiei curente.")
    }
    public func chartRemove() { guard adjustments.chart != nil else { return }; registerReset(L("Corecția chartului a fost eliminată (poți anula)")); adjustments.chart = nil }
    /// Aplică ACEEAȘI corecție unui grup ales EXPLICIT (nu se propagă automat): reglajele fiecărei fotografii se citesc din catalog (sau pornesc neutre), li se adaugă corecția, apoi se salvează. Întoarce (aplicate, sărite).
    @discardableResult public func chartApplyToGroup(_ ids: [Int64]) -> (applied: Int, skipped: Int) {
        guard let c = adjustments.chart ?? chartProposal else { return (0, ids.count) }; var ok = 0, sk = 0
        for id in ids {
            if id == current?.id { var a = adjustments; a.chart = c; a.disabledModules.remove("chart"); adjustments = a; ok += 1; continue }
            var a = ((try? catalog.edits(photoId: id)) ?? nil).flatMap { try? JSONDecoder().decode(AdjustmentSet.self, from: Data($0.utf8)) } ?? AdjustmentSet.neutral(adjustments.family)
            a.chart = c; a.disabledModules.remove("chart"); if let d = try? JSONEncoder().encode(a), let t = String(data: d, encoding: .utf8) { do { try catalog.setEdits(photoId: id, json: t); ok += 1 } catch { sk += 1 } } else { sk += 1 }
        }
        chartMessage = LF("Corecția a fost aplicată %@ fotografii alese%@.", ok, sk > 0 ? " (\(sk) sărite)" : ""); return (ok, sk)
    }
    // Copiere / lipire / sincronizare de reglaje pe categorii (sursă explicită; vezi AdjustmentSync.swift)
    @Published public var clipboard: (set: AdjustmentSet, from: String)?
    @Published public var syncMessage = ""
    private var lastPasteUndo: [Int64: String?] = [:]
    public func copyAdjustments() { guard let p = current else { return }; clipboard = (adjustments, (p.path as NSString).lastPathComponent); syncMessage = LF("Copiat din %@: %@. Alege unde lipești.", (p.path as NSString).lastPathComponent, clipboard!.from) }
    /// Lipește categoriile alese în fotografiile indicate (curentă și/sau altele); salvează starea anterioară pentru «Anulează ultima lipire»; aprobările fotografiilor modificate se invalidează prin schimbarea amprentei.
    @discardableResult public func pasteAdjustments(_ cats: Set<AdjustmentCategory>, to ids: [Int64]) -> (applied: Int, skipped: Int) {
        guard featureGate(.editProcessing) else { syncMessage = Self.lockedMessage; return (0, ids.count) }
        guard let src = clipboard?.set, !cats.isEmpty else { return (0, ids.count) }; var ok = 0, sk = 0; lastPasteUndo = [:]
        for id in ids {
            if id == current?.id { lastPasteUndo[id] = (try? JSONEncoder().encode(adjustments)).flatMap { String(data: $0, encoding: .utf8) }; registerReset(LF("Lipire de reglaje din %@", clipboard?.from ?? "")); adjustments = src.pasting(cats, onto: adjustments); ok += 1; continue }
            let prevJSON = (try? catalog.edits(photoId: id)) ?? nil; let snapshot: String? = prevJSON ?? (try? JSONEncoder().encode(AdjustmentSet.neutral(adjustments.family))).flatMap { String(data: $0, encoding: .utf8) }; lastPasteUndo[id] = .some(snapshot)   // tip explicit: într-un dicționar [Int64: String?] expresia `prev ?? …` s-ar împacheta ca .some(nil) și anularea ar fi sărită
            let base = prevJSON.flatMap { try? JSONDecoder().decode(AdjustmentSet.self, from: Data($0.utf8)) } ?? AdjustmentSet.neutral(adjustments.family)
            let a = src.pasting(cats, onto: base)
            if let d = try? JSONEncoder().encode(a), let t = String(data: d, encoding: .utf8) { do { try catalog.setEdits(photoId: id, json: t); ok += 1 } catch { sk += 1 } } else { sk += 1 }
        }
        syncMessage = LF("Lipit în %@ fotografii%@. Categorii: %@.", ok, sk > 0 ? " (\(sk) sărite)" : "", cats.map { $0.rawValue }.sorted().joined(separator: ", ")); return (ok, sk)
    }
    public var canUndoPaste: Bool { !lastPasteUndo.isEmpty }
    public func undoLastPaste() {
        for (id, prev) in lastPasteUndo {
            if id == current?.id { if let j = prev, let a = try? JSONDecoder().decode(AdjustmentSet.self, from: Data(j.utf8)) { adjustments = a } }
            else if let j = prev { try? catalog.setEdits(photoId: id, json: j) }
        }
        lastPasteUndo = [:]; syncMessage = L("Ultima lipire a fost anulată.")
    }
    // Estimarea profilului (set inițial de 7 parametri; metoda autorizată: local, determinist; vezi ProfileEstimator)
    @Published public var profileProgress: String = ""
    @Published public var profileBusy = false
    /// Oprire/reluare: potrivirile deja făcute se păstrează pe perechi (estimatorul e determinist), deci «Reia» sare peste ele. Cache-ul se golește la schimbarea motorului.
    private final class CancelBox { var v = false }
    private var profileCancel = CancelBox()
    private var profileFitCache: [String: ProfileEstimator.PairFit] = [:]; private var profileFitCacheEngine = ""
    @Published public var profileStopped = false
    public func stopProfileEstimation() { profileCancel.v = true; profileProgress = L("Se oprește după perechea curentă…") }
    public func estimateProfile(_ id: String) {
        guard featureGate(.profileEstimation) else { profileMessage = Self.lockedMessage; return }
        guard !profileBusy, let own = ownProcessor, let prof = profileRegistry.profiles.first(where: { $0.id == id }) else { return }
        if let b = profileRegistry.estimationBlocker(for: prof) { profileMessage = b; return }
        _ = GDCDRTData.load(devRoot: AppInfo.devRoot); var natural = false; if case .loaded = GDCDRTData.status { natural = true }
        guard natural else { profileMessage = "\(ProfileEstimator.EstimatorError.drtUnavailable)"; return }
        let pairs = profileRegistry.pairs.filter { prof.pairIDs.contains($0.id) && $0.learningApproved }; let (fitPairs, heldPairs) = ProfileRegistry.split(pairs)
        profileBusy = true; profileStopped = false; profileProgress = LF("Pregătesc %@ perechi…", pairs.count)
        let cancel = CancelBox(); profileCancel = cancel
        if profileFitCacheEngine != ProfileEstimator.engineIdentity { profileFitCache = [:]; profileFitCacheEngine = ProfileEstimator.engineIdentity }
        let cached = profileFitCache
        Task.detached { [weak self] in
            var fits: [ProfileEstimator.PairFit] = [], held: [ProfileEstimator.Prepared] = [], excluded: [String] = []
            func prep(_ p: ExamplePair) -> ProfileEstimator.Prepared? {
                do { let inp = try own.estimationInputs(photoPath: p.rawPath); let fin = try ProfileEstimator.readFinal(p.finalPath); return try ProfileEstimator.prepare(raw: inp.image, final: fin, estimate: inp.estimate) }
                catch { excluded.append("\((p.rawPath as NSString).lastPathComponent): \(error)"); return nil }   // o pereche invalidă se raportează și se omite; lotul continuă
            }
            var spent: [Double] = []           // secunde măsurate pe perechile potrivite acum (cele din cache nu intră în medie)
            for (i, p) in fitPairs.enumerated() {
                if cancel.v { break }
                if let f = cached[p.id] { fits.append(f); continue }
                let left = fitPairs[i...].filter { cached[$0.id] == nil }.count
                let eta = spent.isEmpty ? "" : LF(" · rămas ≈ %@ s (media măsurată pe %@ perechi)", Int((spent.reduce(0, +) / Double(spent.count) * Double(left)).rounded()), spent.count)
                await MainActor.run { self?.profileProgress = LF("Potrivesc perechea %@/%@…", i + 1, fitPairs.count) + eta }
                let t0 = Date()
                if let pr = prep(p) { let f = ProfileEstimator.fit(pairID: p.id, prepared: pr, drtNatural: true); fits.append(f); await MainActor.run { self?.profileFitCache[p.id] = f } }
                spent.append(Date().timeIntervalSince(t0))
            }
            if cancel.v { await MainActor.run { self?.profileBusy = false; self?.profileProgress = ""; self?.profileStopped = true; self?.profileMessage = L("Estimare oprită. Potrivirile terminate sunt păstrate; «Reia» continuă de unde a rămas.") }; return }
            for p in heldPairs { if let pr = prep(p) { held.append(pr) } }
            let agg = ProfileEstimator.aggregate(fits, technicalPolicy: prof.parameters.technicalPolicy); excluded += agg.excluded.map { "\($0.0): \($0.1)" }
            let ev = held.isEmpty ? nil : ProfileEstimator.evaluate(agg.parameters, held: held, drtNatural: true)
            await MainActor.run {
                guard let self = self else { return }; self.profileBusy = false; self.profileProgress = ""
                if agg.used.isEmpty { self.profileMessage = LF("Nicio pereche utilizabilă pentru ajustare (%@ omise). Profilul rămâne ciornă.", excluded.count); return }
                self.profileRegistry.storeEstimate(profileID: id, parameters: agg.parameters, estimatorVersion: ProfileEstimator.version, paramSet: ProfileEstimator.parameterNames, evaluation: ev?.summary ?? L("fără perechi reținute: profil NEEVALUAT"), heldOut: heldPairs.map { $0.id }, excluded: excluded, engineIdentity: ProfileEstimator.engineIdentity, evalDetail: ev.map { ($0.heldOut, $0.meanBaselineDE, $0.meanProfileDE, $0.improvedCount, $0.consistent) })
                self.profileMessage = LF("Profil estimat (EXPERIMENTAL) din %@ perechi. ", agg.used.count) + (ev?.summary ?? "NEEVALUAT.")
            }
        }
    }
    /// Etichetă de încredere a profilului, derivată din date (nu din denumire): preset ≠ profil învățat.
    public func profileTrustLabel(_ pr: PersonalProfile) -> String {
        guard pr.status == .estimated else { return L("CIORNĂ · fără estimare") }
        if pr.importedFrom != nil { return L("IMPORTAT · NEEVALUAT pe exemplele tale (transferabilitate de evaluat)") }
        let fitN = max(0, pr.pairIDs.count - (pr.heldOutPairIDs?.count ?? 0)); let held = pr.evalHeld ?? pr.heldOutPairIDs?.count ?? 0
        guard held > 0, let b = pr.evalBaselineDE, let p = pr.evalProfileDE, let imp = pr.evalImproved else { return L("ESTIMAT · NEEVALUAT (nicio pereche reținută)") }
        let res = String(format: L("ΔE medie %.2f cu profil vs %.2f fără, %d din %d îmbunătățite"), p, b, imp, held)
        if held < ProfileRegistry.experimentalHeldOut { return LF("EXPERIMENTAL · set mic · evaluare INDICATIVĂ pe %@ pereche(i) reținută(e) (%@); sub %@ reținute nu există dispersie", held, res, ProfileRegistry.experimentalHeldOut) }
        let passes = held >= ProfileRegistry.evaluatedHeldOut && fitN >= ProfileRegistry.evaluatedFit && Double(imp) >= 0.7 * Double(held) && p < b && pr.evalConsistent == true
        if passes { return LF("EVALUAT · protocol: perechi reținute disjuncte (hash RAW, fiecare a 4-a), ≥%@ reținute, ≥70% îmbunătățite, ΔE sub referința fără profil, parametri consistenți · rezultat: %@ · situațiile de lumină nu se măsoară încă", ProfileRegistry.evaluatedHeldOut, res) }
        return LF("EXPERIMENTAL · evaluat pe %@ reținute, protocolul «evaluat» NEÎNDEPLINIT (cere ≥%@ reținute, ≥%@ de ajustare, ≥70% îmbunătățite, parametri consistenți) · %@", held, ProfileRegistry.evaluatedHeldOut, ProfileRegistry.evaluatedFit, res)
    }
    private var profileCompareBackup: AdjustmentSet?
    public var profileCompareActive: Bool { profileCompareBackup != nil }
    /// Comparație: aplică profilul fotografiei curente și păstrează reglajele de dinainte; a doua apăsare le restaurează exact.
    public func toggleProfileCompare(_ id: String) {
        if let b = profileCompareBackup { adjustments = b; profileCompareBackup = nil; return }
        guard current != nil else { return }; let before = adjustments; applyProfile(id); profileCompareBackup = before
    }
    /// Aplică profilul unor fotografii din coadă (doar cei 8 parametri estimați; restul fotografiei rămâne neatins); reutilizează anularea ultimei lipiri.
    @discardableResult public func applyProfileToBatch(_ id: String, ids: [Int64]) -> Int {
        guard let prof = profileRegistry.profiles.first(where: { $0.id == id }), prof.status == .estimated else { return 0 }
        lastPasteUndo = [:]; var ok = 0
        for pid in ids where !((try? catalog.photo(id: pid))?.isRendered ?? false) {
            if pid == current?.id { lastPasteUndo[pid] = (try? JSONEncoder().encode(adjustments)).flatMap { String(data: $0, encoding: .utf8) }; applyProfile(id); ok += 1; continue }
            let prev = (try? catalog.edits(photoId: pid)) ?? nil; let snapshot: String? = prev ?? (try? JSONEncoder().encode(AdjustmentSet.neutral(adjustments.family))).flatMap { String(data: $0, encoding: .utf8) }; lastPasteUndo[pid] = .some(snapshot)
            var a = prev.flatMap { try? JSONDecoder().decode(AdjustmentSet.self, from: Data($0.utf8)) } ?? AdjustmentSet.neutral(adjustments.family)
            let p = ProfileEstimator.adjustments(from: prof, estimate: nil, family: a.family)
            a.exposureAuto = p.exposureAuto; a.autoOffset = p.autoOffset; a.contrast = p.contrast; a.saturation = p.saturation; a.shadows = p.shadows; a.highlights = p.highlights; a.temperature = p.temperature; a.tint = p.tint
            if let d = try? JSONEncoder().encode(a), let t = String(data: d, encoding: .utf8), (try? catalog.setEdits(photoId: pid, json: t)) != nil { ok += 1 }
        }
        syncMessage = LF("Profilul «%@» v%@ aplicat la %@ fotografii (anulabil din meniul «Reglaje»).", prof.name, prof.version, ok); return ok
    }
    /// Aplică profilul fotografiei curente: doar cei 7 parametri; locale, efecte, geometrie și toate celelalte module rămân neatinse.
    public func applyProfile(_ id: String) {
        guard featureGate(.profileEstimation) else { profileMessage = Self.lockedMessage; return }
        guard !currentIsRendered else { profileMessage = L("Profilul personal se aplică doar fotografiilor RAW; imaginea curentă e redată (nu RAW)."); return }
        guard let prof = profileRegistry.profiles.first(where: { $0.id == id }), prof.status == .estimated else { return }
        let p = ProfileEstimator.adjustments(from: prof, estimate: suggestion?.stops, family: adjustments.family)
        registerReset(LF("Reglajele au fost înlocuite cu cele din profilul «%@» (poți anula)", prof.name))
        var a = adjustments; a.exposureAuto = p.exposureAuto; a.autoOffset = p.autoOffset; a.contrast = p.contrast; a.saturation = p.saturation; a.shadows = p.shadows; a.highlights = p.highlights; a.temperature = p.temperature; a.tint = p.tint; adjustments = a
    }
    // MARK: „Continuă în Resolve” — pagina Color cu 3 noduri-etapă într-o versiune de culoare proprie; reîntoarcerea = reglajele pluginului + rezultatul randat din Resolve
    private var ofxStatusCache: (at: Date, text: String)?
    /// Citit de pe disc: păstrat 10 s (se evalua la fiecare redesenare a inspectorului).
    public var ofxStatus: String {
        if let c = ofxStatusCache, Date().timeIntervalSince(c.at) < 10 { return c.text }
        let t = ofxStatusUncached; ofxStatusCache = (Date(), t); return t
    }
    private var ofxStatusUncached: String {
        guard let v = ResolveHandoff.installedOFXVersion() else { return L("Componenta FotoAsist GC OFX nu e instalată.") }
        guard ResolveHandoff.supportsStages(v) else { return LF("FotoAsist GC OFX %@ instalat · FĂRĂ etape separate (necesită 0.3.0): nodurile rulează traseul complet.", v) }
        return ResolveHandoff.supportsFamilies(v) ? LF("FotoAsist GC OFX %@ instalat · etape separate și familii de lucru disponibile.", v) : LF("FotoAsist GC OFX %@ instalat · etape separate disponibile; familiile de lucru în afara celei DaVinci cer 0.4.0 (până atunci predarea în Resolve se oprește explicit, nu interpretează imaginea în altă familie).", v)
    }
    /// Ultima politică de predare pentru corecțiile locale: `bake` = integrate în intermediar (rezultatul lor se păstrează; instrumentele globale devin neutre în Resolve ca să nu se aplice de două ori); `drop` = lăsate afară, explicit. Fără alegere, predarea cu corecții locale active NU pornește.
    @Published public var handoffLocalsPolicy: LocalsPolicy?
    /// Pornire de la zero a unei predări: alegerea anterioară pentru corecții NU se reutilizează (se cere din nou); după consimțământul pentru proiect, alegerea făcută rămâne.
    public func beginResolveHandoff() { handoffLocalsPolicy = nil; continueInResolve() }
    public func continueInResolve(allowSwitch: Bool = false, locals policy: LocalsPolicy? = nil) {
        guard featureGate(.resolveHandoff) else { statusLine = Self.lockedMessage; return }
        guard engine == .own, let photo = current, let own = ownProcessor else { handoff = .failed(L("Alege o fotografie și motorul „Nucleu propriu”.")); return }
        if adjustments.effective.drtProfile != 0 { handoff = .failed(L("Profilul DRT ales nu există în pluginul Resolve (doar Natural): predarea s-ar reda diferit. Alege profilul Natural sau exportă din FotoAsist.")); return }
        let activeLocals = adjustments.effective.locals.filter { $0.isActiveLocal }.count + (adjustments.effective.effects.hasPostEffects ? 1 : 0) + (adjustments.effective.tools.isNeutral ? 0 : 1) + (adjustments.effective.chart == nil ? 0 : 1) + (adjustments.effective.look.on ? 1 : 0)
        let pol = policy ?? (activeLocals > 0 ? handoffLocalsPolicy : nil)   // alegerea făcută rămâne valabilă după consimțământul pentru proiect (altfel se cerea la nesfârșit)
        if activeLocals > 0 && pol == nil { handoff = .needsLocalsChoice(activeLocals); return }
        handoffLocalsPolicy = activeLocals > 0 ? pol : nil
        flushSave(); handoff = .working(L("Pregătesc intermediarul la rezoluție plină și lanțul în Resolve…")); let adj = adjustments.effective; let est = suggestion?.stops
        queue.async { [weak self] in
            var st: HandoffUIState
            do {
                let bake: AdjustmentSet? = (pol == .bake && activeLocals > 0) ? adj : nil
                let ex = try own.intermediateEXR(photoPath: photo.path, family: adj.family, geometry: adj.geometry, effects: adj.effects, bake: bake, rawDev: adj.rawDev)
                let hb: ResolveHandoff; if let h = DispatchQueue.main.sync(execute: { self?.handoffBridge }) { hb = h } else { hb = try ResolveHandoff() }
                try hb.ensureProject(allowSwitch: allowSwitch)
                // numele cronologiei poartă identitatea intermediarului (ultimele 8 caractere din numele EXR): o cronologie existentă păstrează MEDIA ei, deci un intermediar diferit (BAKED, geometrie, estimare) cere o cronologie diferită — altfel versiunea nouă s-ar aplica peste media veche
                let exrStem = ex.url.deletingPathExtension().lastPathComponent; let idTag = String(exrStem.split(separator: "_").last ?? "")
                let tlName = "FotoAsist · " + ((photo.path as NSString).lastPathComponent as NSString).deletingPathExtension + (idTag.isEmpty ? "" : " · " + idTag)
                let r = try hb.handoff(exr: ex.url, width: ex.width, height: ex.height, timelineName: tlName, adjustments: bake != nil ? { var n = AdjustmentSet.neutral(adj.family); n.disabledModules = []; return n }() : adj, estimate: est)
                Thread.sleep(forTimeInterval: 3.0)                         // graful se citește într-un apel ulterior (blocări Resolve observate la citirea imediată)
                let v = (try? hb.verify(timeline: tlName)) ?? []
                let stem = ((photo.path as NSString).lastPathComponent as NSString).deletingPathExtension
                DispatchQueue.main.async { self?.handoffBridge = hb; self?.handoffSize = (ex.width, ex.height); self?.handoffStem = stem; self?.handoffTimeline = tlName; if let c = self?.catalog { try? c.setSession("handoff_last_v1", "{\"stem\":\"\(stem)\",\"timeline\":\"\(tlName)\",\"w\":\(ex.width),\"h\":\(ex.height)}") } }
                let names = v.isEmpty ? r.nodes : v.map { $0.label.isEmpty ? ($0.tools.first ?? "") : $0.label }
                st = r.applied ? .done(LF("%@Gata în Resolve (pagina Color): cronologia «%@», versiunea «%@», %@ noduri: %@.%@ %@", bake != nil ? "Corecțiile (globale + \(activeLocals) locale) sunt INTEGRATE în intermediar (fișier «BAKED», cod înainte de DRT); nodurile 1–2 sunt neutre în Resolve ca ajustările să nu se aplice de două ori; măștile NU sunt editabile în Resolve. " : (activeLocals > 0 ? "ATENȚIE: cele \(activeLocals) corecții locale au fost LĂSATE AFARĂ la cererea ta (nu apar în Resolve). " : ""), r.timeline, r.version, names.count, names.joined(separator: " → "), adj.geometry.isNeutral ? "" : " Cadrul ales (decupare/rotire/perspectivă) e APLICAT în intermediar (\(ex.width)×\(ex.height) px, fișier marcat «GEO»); nu se aplică a doua oară și nu e editabil în Resolve.", r.stageParam ? "" : "Atenție: OFX \(r.ofxVersion) nu separă etapele; fiecare nod rulează traseul complet până la instalarea 0.3.0.")) : .failed(L("Resolve nu a aplicat lanțul (ApplyGradeFromDRX)."))
            } catch HandoffError.needsConsent(let p) { st = .needsConsent(p) }
            catch { st = .failed("\(error)") }
            DispatchQueue.main.async { self?.handoff = st }
        }
    }
    /// Reîntoarcerea: reglajele pluginului din Resolve (doar parametrii ≠ implicit) + rezultatul REAL randat din Resolve (cu toate nodurile fotografului). Nu e sincronizare completă (fără măști, keyframe-uri, alte efecte).
    public func refreshFromResolve() {
        // contextul ultimei predări supraviețuiește repornirii aplicației (sesiune)
        if handoffSize == nil, let j = (try? catalog.session("handoff_last_v1")).flatMap({ $0 }), let d = j.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let w = o["w"] as? Int, let h = o["h"] as? Int, let st = o["stem"] as? String { handoffSize = (w, h); handoffStem = st; handoffTimeline = (o["timeline"] as? String) ?? "" }
        guard let size = handoffSize else { handoff = .failed(L("Nu există o fotografie pregătită în Resolve. Apasă întâi „Continuă în Resolve”.")); return }
        handoff = .working(L("Citesc reglajele și randez rezultatul din Resolve…")); let dir = workDir.appendingPathComponent("handoff/results"); let stem = handoffStem; let savedTimeline = handoffTimeline; let existing = handoffBridge
        queue.async { [weak self] in
            var st: HandoffUIState = .idle; var lines: [String] = []; var img: NSImage?; var rurl: URL?
            do {
                let hb: ResolveHandoff = try existing ?? ResolveHandoff(); let tlName = savedTimeline.isEmpty ? "FotoAsist · " + stem : savedTimeline
                DispatchQueue.main.async { self?.handoffBridge = hb }
                let rb = try hb.readBack(timeline: tlName); lines = rb.nodes.map { n in "\(n.label.isEmpty ? "nod \(n.index)" : n.label): " + (n.params.isEmpty ? L("valori implicite") : n.params.sorted { $0.key < $1.key }.map { "\($0.key.replacingOccurrences(of: "ph", with: "")) \($0.value)" }.joined(separator: " · ")) }
                let url = try hb.render(to: dir, name: "\(stem)_din_Resolve", width: size.w, height: size.h, timeline: tlName); img = ResultImage.load(url); rurl = url
                st = .done(LF("Rezultat randat în Resolve (versiunea «%@»). Reglajele pluginului sunt citite; măștile și alte efecte adăugate în Resolve apar în imagine, dar NU sunt citite în FotoAsist.", rb.version))
            } catch { st = .failed("\(error)") }
            DispatchQueue.main.async { self?.resolveReadback = lines; if let i = img { self?.resolveResultImage = i; self?.compare = .resolve }; self?.handoff = st }
            if let u = rurl { DispatchQueue.main.async { self?.resolveResultURL = u } }
        }
    }

    // MARK: corecții locale (zonă manuală + reglaje; doar motorul propriu)
    public func addLocal(_ kind: ZoneKind) {
        guard current != nil else { return }
        let n = adjustments.locals.filter { $0.kind == kind }.count + 1; let l = LocalCorrection.make(kind, number: n)
        adjustments.locals.append(l); activeTool = .masks; geometryMode = .none; selectedLocal = l.id; selectedComponent = nil; selectedPoint = nil; maskTool = kind == .path ? .drawPath : (kind == .brush ? .brushAdd : .select); maskUndo = []; maskRedo = []; showZone = true; guidesHidden = false   // o corecție nouă se definește pe fotografie: ghidajele apar
    }
    // MARK: mască de SUBIECT (Vision, local; NU e hartă de adâncime): contur închis în masca existentă (Undo/Redo, persistență, geometrie ca la orice contur)
    @Published public var subjectBusy = false
    @Published public var subjectNote = ""
    private func subjectAlpha(_ photo: PhotoRecord, family: WorkingFamily) throws -> SubjectMask.Result? {
        guard let own = ownProcessor else { return nil }
        let r = try own.process(photoPath: photo.path, quality: .preview, adjustments: AdjustmentSet.neutral(family))      // cadrul sursă, fără geometria utilizatorului: aceleași coordonate ca masca
        let fin = try TIFF16.read(r.url); let f = max(1, (max(fin.width, fin.height) + 1023) / 1024); let w = fin.width / f, h = fin.height / f
        var px = [UInt8](repeating: 255, count: w * h * 4); for y in 0..<h { for x in 0..<w { let i = ((y * f) * fin.width + x * f) * 3, o = (y * w + x) * 4; for c in 0..<3 { px[o + c] = UInt8(max(0, min(255, fin.rgb[i + c] * 255 + 0.5))) } } }
        guard let cg = px.withUnsafeMutableBytes({ CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage() }) else { return nil }
        return SubjectMask.generate(cg)
    }
    public func addSubjectMask() {
        guard let photo = current, engine == .own, !subjectBusy else { return }
        guard SubjectMask.isAvailable else { subjectNote = L("Selecția subiectului cere macOS 14 sau mai nou. Folosește elipsa, conturul sau pensula."); return }
        subjectBusy = true; subjectNote = ""; let fam = adjustments.family; let pid = photo.id
        analysisQueue.async { [weak self] in
            let res = try? self?.subjectAlpha(photo, family: fam)
            let c = res.flatMap { SubjectMask.contour(alpha: $0.alpha, width: $0.width, height: $0.height) }
            DispatchQueue.main.async { guard let self = self else { return }; self.subjectBusy = false
                guard self.current?.id == pid else { return }          // fotografia s-a schimbat între timp: rezultatul nu se aplică pe alta
                guard let c = c else { self.subjectNote = L("Nu s-a găsit un subiect clar în această fotografie. Nu s-a creat nicio mască."); return }
                let n = self.adjustments.locals.filter { $0.kind == .path }.count + 1; var l = LocalCorrection.make(.path, number: n); l.name = LF("Subiect %@", n)
                l.components[0].points = c.map { MaskPoint(x: min(1, max(0, $0.x)), y: min(1, max(0, $0.y))) }; l.components[0].closed = true; l.components[0].feather = 0.35
                self.adjustments.locals.append(l); self.activeTool = .masks; self.geometryMode = .none; self.selectedLocal = l.id; self.selectedComponent = l.components[0].id; self.selectedPoint = nil; self.maskTool = .select; self.maskUndo = []; self.maskRedo = []
                self.subjectNote = LF("Subiect: contur cu %@ puncte (poți muta punctele și regla marginea moale; nu e hartă de adâncime).", c.count) }
        }
    }
    /// Matte PNG (alb = subiect) lângă exporturi, pentru a fi importat în Resolve ca matte extern. NU creează noduri Resolve (API-ul nu expune masca/Magic Mask).
    public func exportSubjectMatte() {
        guard let photo = current, engine == .own, !subjectBusy else { return }
        guard SubjectMask.isAvailable else { subjectNote = L("Selecția subiectului cere macOS 14 sau mai nou."); return }
        subjectBusy = true; subjectNote = ""; let fam = adjustments.family
        analysisQueue.async { [weak self] in
            let res = try? self?.subjectAlpha(photo, family: fam)
            var url: URL?; if let r = res, let d = SubjectMask.mattePNG(alpha: r.alpha, width: r.width, height: r.height) {
                let dir = (self?.workDir ?? FileManager.default.temporaryDirectory).appendingPathComponent("mattes", isDirectory: true); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let u = dir.appendingPathComponent(((photo.path as NSString).lastPathComponent as NSString).deletingPathExtension + "_subject_matte.png"); if (try? d.write(to: u, options: .atomic)) != nil { url = u } }
            DispatchQueue.main.async { guard let self = self else { return }; self.subjectBusy = false
                if let u = url { self.subjectNote = LF("Matte salvat: %@ (alb = subiect, cadrul sursă fără decupare). În Resolve se importă ca fișier; nu se creează noduri automat.", u.path); NSWorkspace.shared.activateFileViewerSelecting([u]) }
                else { self.subjectNote = L("Nu s-a găsit un subiect clar; nu s-a scris niciun matte.") } }
        }
    }
    // MARK: decupare și geometrie (reglaje nedistructive; aceeași stare `adjustments`, deci același salvare/cache/aprobare/export)
    public var orientedSize: CGSize { let g = adjustments.geometry; return g.rotate90 % 2 == 0 ? sourceSize : CGSize(width: sourceSize.height, height: sourceSize.width) }
    public var finalPixelSize: (w: Int, h: Int)? { guard sourceSize.width > 0 else { return nil }; let p = adjustments.geometry.plan(srcW: Int(sourceSize.width), srcH: Int(sourceSize.height)); return (p.outW, p.outH) }
    public func aspectValue(_ g: Geometry) -> Double? {
        let o = orientedSize; var v: Double?
        switch g.aspect { case "original": v = o.height > 0 ? Double(o.width / o.height) : nil; case "1:1": v = 1; case "4:5": v = 4.0 / 5; case "3:2": v = 3.0 / 2; case "16:9": v = 16.0 / 9; case "custom": v = g.customH > 0 ? g.customW / g.customH : nil; default: v = nil }
        if let a = v, g.aspect != "original", g.aspect != "1:1" { return g.portrait ? 1 / a : a }; return v
    }
    public func setAspect(_ name: String) {
        registerReset(LF("Raportul de decupare: «%@»", name)); var g = adjustments.geometry; g.aspect = name; if name == "free" { adjustments.geometry = g; return }
        let o = orientedSize; if let a = aspectValue(g), o.width > 0 { g.crop = Geometry.centeredCrop(aspect: a, orientedW: Double(o.width), orientedH: Double(o.height)) }; adjustments.geometry = g
    }
    public func swapAspectOrientation() { var g = adjustments.geometry; g.portrait.toggle(); adjustments.geometry = g; setAspect(g.aspect) }
    public func rotate90(_ d: Int) { registerReset("Rotire 90°"); var g = adjustments.geometry; g.rotate90 = ((g.rotate90 + d) % 4 + 4) % 4; g.crop = CropRect(); g.aspect = "free"; adjustments.geometry = g }
    public func flip(h: Bool) { registerReset(h ? L("Oglindire orizontală") : L("Oglindire verticală")); var g = adjustments.geometry; if h { g.flipH.toggle() } else { g.flipV.toggle() }; adjustments.geometry = g }
    /// Decupare automată EXPLICITĂ a marginilor goale (cel mai mare cadru centrat fără margini goale).
    public func autoCropEdges() {
        let o = orientedSize; guard o.width > 0 else { return }; registerReset(L("Decupare automată a marginilor")); var g = adjustments.geometry
        g.crop = Geometry.autoCrop(angle: g.angle, orientedW: Double(o.width), orientedH: Double(o.height), aspect: aspectValue(g)); adjustments.geometry = g
    }
    /// Resetează doar perspectiva/cadrarea (corecție verticală/orizontală, scară, deplasare).
    public func resetPerspective() { registerReset(L("Perspectiva și cadrarea au revenit la neutru")); var g = adjustments.geometry; g.keystoneV = 0; g.keystoneH = 0; g.scale = 1; g.shiftX = 0; g.shiftY = 0; adjustments.geometry = g }
    public func resetGeometry() { registerReset(L("Decuparea și geometria au revenit la neutru")); adjustments.geometry = Geometry(); geometryMode = .none; straightenPoints = [] }
    /// Îndreptare cu două puncte (coordonate normalizate ale vederii curente): linia devine orizontală sau verticală (rotirea cea mai mică).
    public func straighten(from a: CGPoint, to b: CGPoint, imageSize s: CGSize) {
        let dx = Double((b.x - a.x) * s.width), dy = Double((b.y - a.y) * s.height); guard hypot(dx, dy) > 4 else { return }
        var ang = atan2(dy, dx) * 180 / .pi; if ang > 90 { ang -= 180 }; if ang < -90 { ang += 180 }
        let delta = abs(ang) <= 45 ? -ang : (ang > 0 ? 90 - ang : -90 - ang)
        registerReset(L("Îndreptare cu două puncte")); var g = adjustments.geometry; var n = g.angle + delta; while n > 45 { n -= 90 }; while n < -45 { n += 90 }; g.angle = (n * 100).rounded() / 100; adjustments.geometry = g
    }

    // MARK: construirea măștii (puncte, componente, pensulă) — aceeași stare `adjustments.locals`, deci același mecanism de salvare/cache/aprobare/randare
    /// Indicele componentei selectate a corecției selectate (implicit prima).
    public func componentIndex(_ li: Int) -> Int { let cs = adjustments.locals[li].components; return selectedComponent.flatMap { id in cs.firstIndex { $0.id == id } } ?? 0 }
    /// Păstrează starea ANTERIOARĂ unei editări de mască (o dată per gest) pentru anulare/refacere.
    public func beginMaskEdit() { guard !maskGestureOpen else { return }; maskGestureOpen = true; maskUndo.append(adjustments.locals); if maskUndo.count > 100 { maskUndo.removeFirst() }; maskRedo = [] }
    public func endMaskEdit() { maskGestureOpen = false }
    public func undoMaskEdit() { guard let p = maskUndo.popLast() else { return }; maskRedo.append(adjustments.locals); adjustments.locals = p; fixMaskSelection() }
    public func redoMaskEdit() { guard let p = maskRedo.popLast() else { return }; maskUndo.append(adjustments.locals); adjustments.locals = p; fixMaskSelection() }
    private func fixMaskSelection() { if let id = selectedLocal, !adjustments.locals.contains(where: { $0.id == id }) { selectedLocal = nil }; if let li = localIndex(selectedLocal) { if let c = selectedComponent, !adjustments.locals[li].components.contains(where: { $0.id == c }) { selectedComponent = nil }; if let pi = selectedPoint, pi >= adjustments.locals[li].components[componentIndex(li)].points.count { selectedPoint = nil } } else { selectedComponent = nil; selectedPoint = nil } }
    /// O componentă nouă în masca corecției selectate (adaugă/scade): elipsă și degrade apar gata de tras; contur: se desenează punct cu punct; pensulă: se pictează pe fotografie.
    public func addComponent(_ kind: ZoneKind, op: MaskOp) {
        guard let li = localIndex(selectedLocal) else { return }
        if kind == .brush { maskTool = op == .add ? .brushAdd : .brushErase; guidesHidden = false; showZone = true; selectedPoint = nil; return }   // pensula: fiecare tușă creează componenta ei
        beginMaskEdit(); defer { endMaskEdit() }
        var c = MaskComponent(kind: kind); c.op = op
        switch kind {
        case .ellipse: c.x1 = 0.5; c.y1 = 0.5; c.x2 = 0.2; c.y2 = 0.2; c.feather = 0.4
        case .gradient: c.x1 = 0.5; c.y1 = 0.0; c.x2 = 0.5; c.y2 = 0.5; c.feather = 0.5
        case .path: c.feather = 0.25
        case .brush: break
        }
        adjustments.locals[li].components.append(c); selectedComponent = c.id; selectedPoint = nil; guidesHidden = false; showZone = true
        maskTool = kind == .path ? .drawPath : .select
    }
    public func deleteComponent(_ id: String) {
        guard let li = localIndex(selectedLocal), adjustments.locals[li].components.count > 1, let ci = adjustments.locals[li].components.firstIndex(where: { $0.id == id }) else { return }
        beginMaskEdit(); adjustments.locals[li].components.remove(at: ci); endMaskEdit(); if selectedComponent == id { selectedComponent = nil }; selectedPoint = nil; maskTool = .select
    }
    public func setComponentOp(_ id: String, _ op: MaskOp) { guard let li = localIndex(selectedLocal), let ci = adjustments.locals[li].components.firstIndex(where: { $0.id == id }), ci > 0 else { return }; beginMaskEdit(); adjustments.locals[li].components[ci].op = op; endMaskEdit() }
    public func selectComponent(_ id: String) { selectedComponent = id; selectedPoint = nil; maskTool = .select }
    /// Contur: adaugă un punct (sau închide conturul dacă se apasă lângă primul punct și există ≥ 3 puncte).
    public func addPathPoint(_ x: Double, _ y: Double, closeIfNearFirst tol: Double = 0) {
        guard let li = localIndex(selectedLocal) else { return }; let ci = componentIndex(li); guard adjustments.locals[li].components[ci].kind == .path, !adjustments.locals[li].components[ci].closed else { return }
        beginMaskEdit(); defer { endMaskEdit() }
        let pts = adjustments.locals[li].components[ci].points
        if pts.count >= 3, let f = pts.first, hypot(f.x - x, f.y - y) <= tol { adjustments.locals[li].components[ci].closed = true; maskTool = .select; selectedPoint = nil; return }
        adjustments.locals[li].components[ci].points.append(MaskPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))); selectedPoint = pts.count
    }
    public func closePath() { guard let li = localIndex(selectedLocal) else { return }; let ci = componentIndex(li); guard adjustments.locals[li].components[ci].points.count >= 3 else { return }; beginMaskEdit(); adjustments.locals[li].components[ci].closed = true; endMaskEdit(); maskTool = .select; selectedPoint = nil }
    public func reopenPath() { guard let li = localIndex(selectedLocal) else { return }; let ci = componentIndex(li); guard adjustments.locals[li].components[ci].kind == .path else { return }; beginMaskEdit(); adjustments.locals[li].components[ci].closed = false; endMaskEdit(); maskTool = .drawPath }
    public func deleteSelectedPoint() {
        guard let li = localIndex(selectedLocal), let pi = selectedPoint else { return }; let ci = componentIndex(li); guard pi < adjustments.locals[li].components[ci].points.count else { return }
        beginMaskEdit(); adjustments.locals[li].components[ci].points.remove(at: pi); if adjustments.locals[li].components[ci].points.count < 3 { adjustments.locals[li].components[ci].closed = false }; endMaskEdit(); selectedPoint = nil
    }
    public func toggleSmooth(_ pi: Int) { guard let li = localIndex(selectedLocal) else { return }; let ci = componentIndex(li); guard pi < adjustments.locals[li].components[ci].points.count else { return }; beginMaskEdit(); adjustments.locals[li].components[ci].points[pi].smooth.toggle(); endMaskEdit() }
    /// Inserează un punct pe segmentul cel mai apropiat de (x, y) (coordonate normalizate); `sx, sy` = dimensiunea de afișare, pentru distanță izotropă.
    public func insertPathPoint(near x: Double, _ y: Double, sx: Double, sy: Double, maxDistance: Double) {
        guard let li = localIndex(selectedLocal) else { return }; let ci = componentIndex(li); let c = adjustments.locals[li].components[ci]; guard c.kind == .path, let n = MaskGeometry.nearestSegment(c.points, closed: c.closed, to: (x * sx, y * sy), sx: sx, sy: sy), n.distance <= maxDistance else { return }
        beginMaskEdit(); let a = c.points[n.segment], b = c.points[(n.segment + 1) % c.points.count]
        adjustments.locals[li].components[ci].points.insert(MaskPoint(x: n.point.x, y: n.point.y, smooth: a.smooth || b.smooth), at: n.segment + 1); endMaskEdit(); selectedPoint = n.segment + 1
    }
    /// O tușă de pensulă (Adaugă/Șterge) = o componentă nouă cu traiectoria ei; dacă baza corecției e o pensulă încă goală, tușa o umple.
    public func addBrushStroke(_ pts: [(x: Double, y: Double)], erase: Bool) {
        guard let li = localIndex(selectedLocal), !pts.isEmpty else { return }; beginMaskEdit(); defer { endMaskEdit() }
        let mp = pts.map { MaskPoint(x: min(1, max(0, $0.x)), y: min(1, max(0, $0.y))) }
        if adjustments.locals[li].components.count == 1, adjustments.locals[li].components[0].kind == .brush, adjustments.locals[li].components[0].points.isEmpty, !erase {
            adjustments.locals[li].components[0].points = mp; adjustments.locals[li].components[0].radius = brushRadius; adjustments.locals[li].components[0].softness = brushSoftness; selectedComponent = adjustments.locals[li].components[0].id; return }
        var c = MaskComponent(kind: .brush); c.points = mp; c.radius = brushRadius; c.softness = brushSoftness; c.op = erase ? .subtract : .add; adjustments.locals[li].components.append(c); selectedComponent = c.id
    }
    /// Recalculează analiza pentru fotografia curentă și reglajele curente (în fundal; rezultatul vechi nu se afișează după o schimbare).
    public func scheduleAnalysis() {
        analysisHub.refresh()      // ferestrele/tabloul de analiză independente (calculează doar ce cer vizualizările active)
        guard analysisMode != .off || showHistogram || showVectorscope || showParade, engine == .own, let photo = current, let own = ownProcessor else { analysisGen += 1; analysisResult = nil; analysisImage = nil; analysisBusy = false; return }
        analysisGen += 1; let gen = analysisGen; let adj = viewAdj(adjustments); let mode = analysisMode; let vs = showVectorscope; let pr = showParade; let gain = Float(nrDiffGain); analysisBusy = true
        analysisQueue.async { [weak self] in
            let r = try? own.analyze(photoPath: photo.path, adjustments: adj, mode: mode, vectorscope: vs, parade: pr, nrGain: gain)
            DispatchQueue.main.async { guard let self = self, gen == self.analysisGen else { return }; self.analysisBusy = false; self.analysisResult = r; self.analysisImage = r?.makeImage(); self.analysisUpdatedAt = Date() }
        }
    }
    public func deleteLocal(_ id: String) { adjustments.locals.removeAll { $0.id == id }; if selectedLocal == id { selectedLocal = nil } }
    public func localIndex(_ id: String?) -> Int? { id.flatMap { i in adjustments.locals.firstIndex { $0.id == i } } }
    /// Zona ca imagine translucidă (aceeași funcție de mască ca la procesare), pentru afișare peste previzualizare.
    private struct ZoneKey: Equatable { var comps: [MaskComponent]; var invert: Bool; var aspect: Int; var w: Int; var geometry: Geometry?; var effects: Effects; var source: CGSize }
    private var zoneCache: (key: ZoneKey, img: NSImage)?
    private var zoneWanted: ZoneKey?; private var zoneTask: Task<Void, Never>?; private var zoneChangedAt = 0.0
    @Published private(set) var zoneTick = 0
    /// Zona ca imagine translucidă (aceeași funcție de mască ca la procesare), pentru afișare peste previzualizare. NU se mai calculează pe firul principal în corpul view-ului (profilul real al gestului arăta ~70 ms/cadru acolo):
    /// rezultatul se păstrează în cache și se recalculează în fundal (ultima cerere câștigă); în timpul gestului ghidajul se desenează la rezoluție redusă, apoi se rafinează după o scurtă pauză. Până la sosire se afișează ultima imagine.
    func zoneOverlayImage(_ l: LocalCorrection, aspect: CGFloat, zoom: CGFloat = 0.3, geometry: Geometry? = nil, effects: Effects = Effects(), source: CGSize = .zero) -> NSImage? {
        let full = zoom > 1.2 ? 1400 : (zoom > 0.6 ? 960 : 480)
        let moving = MonoClock.now - zoneChangedAt < 0.3
        let w = moving ? min(full, 320) : full
        let key = ZoneKey(comps: l.components, invert: l.invert, aspect: Int((Double(aspect) * 1000).rounded()), w: w, geometry: geometry, effects: effects, source: source)
        if let c = zoneCache, c.key == key { return c.img }
        if zoneWanted != key {
            if let c = zoneCache, c.key.comps != key.comps || c.key.geometry != key.geometry { zoneChangedAt = MonoClock.now }
            zoneWanted = key; zoneTask?.cancel()
            let lc = l; let ww = w; let h = max(8, Int((Double(w) / Double(max(aspect, 0.1))).rounded())); let geo = geometry; let fx = effects; let src = source
            zoneTask = Task { [weak self] in
                let img: NSImage? = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                    let m = (geo != nil && (!geo!.isNeutral || !fx.framingIsNeutral) && src.width > 0) ? lc.maskValuesInView(geometry: geo!, effects: fx, srcW: Int(src.width), srcH: Int(src.height), width: ww, height: h) : lc.maskValues(width: ww, height: h)
                    var px = [UInt8](repeating: 0, count: ww * h * 4); for i in 0..<(ww * h) { let a = Double(m[i]) * 0.5; px[4 * i] = UInt8(235 * a); px[4 * i + 1] = UInt8(50 * a); px[4 * i + 2] = UInt8(60 * a); px[4 * i + 3] = UInt8(255 * a) }
                    guard let ctx = CGContext(data: &px, width: ww, height: h, bitsPerComponent: 8, bytesPerRow: ww * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let cg = ctx.makeImage() else { return nil }
                    return NSImage(cgImage: cg, size: NSSize(width: ww, height: h)) }.value
                guard !Task.isCancelled, let self = self, let img = img, self.zoneWanted == key else { return }
                self.zoneCache = (key, img); self.zoneTick += 1
                if moving { try? await Task.sleep(nanoseconds: 320_000_000); if !Task.isCancelled, self.zoneWanted == key { self.zoneTick += 1 } }   // după pauză, view-ul cere varianta rafinată
            }
        }
        return zoneCache?.img
    }

    // MARK: aprobare = (id, amprenta reglajelor); orice schimbare de reglaj o invalidează
    public func approvalState(_ id: Int64) -> ApprovalState {
        guard let fp = approvals[id] else { return .none }
        let cur = approvalFingerprint(id == current?.id ? adjustments : adjustmentsFor(id))
        return fp == cur ? .approved : .invalidated
    }
    public func isApproved(_ id: Int64) -> Bool { approvalState(id) == .approved }
    public func approvedCount(in q: [PhotoRecord]) -> Int { q.filter { isApproved($0.id) }.count }
    public func toggleApproved() {
        guard let c = current else { return }
        if isApproved(c.id) { approvals.removeValue(forKey: c.id); approvalNote = "" }
        else { flushSave(); approvals[c.id] = approvalFingerprint(adjustments); approvalNote = "" }
        persistApprovals()
    }
    private func persistApprovals() {
        let m = Dictionary(uniqueKeysWithValues: approvals.map { (String($0.key), $0.value) })
        if let d = try? JSONEncoder().encode(m), let s = String(data: d, encoding: .utf8) { try? catalog.setSession("approved_v2", s) }
    }

    private func adjustmentsChanged() {
        guard let c = current else { return }
        if let fp = approvals[c.id], fp != approvalFingerprint(adjustments) { approvals.removeValue(forKey: c.id); persistApprovals(); approvalNote = "Aprobarea a fost anulată: reglajele s-au schimbat." }
        if keepBannerOnce { keepBannerOnce = false } else if !activationBanner { lastReset = nil }   // o modificare nouă (nu resetarea) închide „Anulează”
        legacyNotice = ""; editsDirty = true   // orice modificare nouă pornește din motorul curent
        saveTask?.cancel(); let a = adjustments
        saveTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 300_000_000); if Task.isCancelled { return }; self?.writeEdits(c.id, a) }
        scheduleRender(immediate: false)
    }
    private func writeEdits(_ id: Int64, _ a0: AdjustmentSet) { var a = a0; if editsDirty { a.engineRevision = AdjustmentSet.currentEngineRevision }; if let d = try? JSONEncoder().encode(a), let s = String(data: d, encoding: .utf8) { try? catalog.setEdits(photoId: id, json: s) } }
    /// Scrie imediat reglajele curente (înainte de aprobare/export/schimbarea fotografiei), ca starea salvată să coincidă cu cea afișată.
    public func flushSave() { saveTask?.cancel(); if let c = current { writeEdits(c.id, adjustments) } }

    // MARK: preîncărcare a fotografiei vecine (doar navigarea «Doar fotografia»): decodarea RAW domină deschiderea la rece (măsurat 8–12 s față de 2,7–3,8 s cu decodarea în cache)
    private let prefetchQueue = DispatchQueue(label: "gdc.prefetch", qos: .utility)
    private var prefetchItem: DispatchWorkItem?
    public private(set) var prefetchedPath: String?
    func prefetchNeighbor(_ p: PhotoRecord) {
        guard engine == .own, let own = ownProcessor, !p.isRendered, failedPhotos[p.id] == nil else { return }
        let adj = viewAdj(adjustmentsFor(p.id)); prefetchItem?.cancel(); prefetchedPath = p.path
        let w = DispatchWorkItem { _ = try? own.process(photoPath: p.path, quality: .preview, adjustments: adj) }; prefetchItem = w
        prefetchQueue.asyncAfter(deadline: .now() + 0.6, execute: w)   // dacă utilizatorul continuă să navigheze, cererea veche se anulează
    }
    // MARK: randare (ultima cerere câștigă; o randare în curs nu se întrerupe, dar rezultatul învechit se ignoră)
    private func scheduleRender(immediate: Bool) {
        guard isReady, let photo = current else { return }
        renderTask?.cancel(); renderGen += 1; let gen = renderGen; let adj = viewAdj(adjustments); let fpAtStart = approvalFingerprint(adjustments)
        if !immediate && engine == .own { eventSeq += 1; latestEventId = eventSeq; latestEventAt = MonoClock.now; stall.touch(); refining = true; runInteractive(photo) }
        renderTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(nanoseconds: engine == .own ? 250_000_000 : 350_000_000) }
            guard !Task.isCancelled, let self = self else { return }
            self.rendering = true; self.statusLine = self.engine == .own ? L("Se procesează…") : L("Se randează în DaVinci Resolve…")
            do {
                let after = try await self.process(photo, adj, .preview)
                guard gen == self.renderGen, self.current?.id == photo.id else { return }
                self.previewShownGen = gen; self.afterResultURL = after.url; self.decodeInfo = after.decode; self.renderedInfo = after.rendered; self.scheduleAnalysis(); if after.sourceWidth > 0 { self.sourceSize = CGSize(width: after.sourceWidth * 2, height: after.sourceHeight * 2) }; if !self.fullResolutionIsCurrent { self.viewer.fullSize = CGSize(width: after.width * 2, height: after.height * 2); self.viewer.applyCarriedZoom(); self.viewer.revalidate() }; if self.viewer.wantsFullResolution { self.scheduleFullRefresh() }; self.afterImage = ResultImage.load(after.url); self.suggestion = after.suggestion ?? self.suggestion
                let ex = after.effectiveExposure
                self.afterInfo = after.rendered != nil ? LF("Imagine redată · %@×%@ · fără DRT, fără normalizare RAW · %@", after.width, after.height, after.rendered!.summary) : LF("Previzualizare · %@×%@ · %@ · expunere efectivă %@ st · %@", after.width, after.height, self.engineName, String(format: "%+.2f", ex), after.fromResultCache ? L("din cache") : String(format: "%.1f s", after.resolveSeconds + after.decodeSeconds))
                self.thumbs[photo.id] = self.afterImage; self.thumbFP[photo.id] = fpAtStart
                if self.beforeImage == nil || !adj.isNeutral {
                    let base = adj.isNeutral ? after : try await self.process(photo, adj.baseForCompare, .preview)
                    if gen == self.renderGen { self.beforeImage = adj.isNeutral ? self.afterImage : ResultImage.load(base.url) }
                }
                self.statusLine = ""; self.failedPhotos[photo.id] = nil
            } catch { if !(error is CancellationError) { self.statusLine = "\(error)"; self.failedPhotos[photo.id] = "\(error)"; if gen == self.renderGen, self.current?.id == photo.id { self.analysisHub.refresh() }; DiagnosticLog.shared?.log(.warning, "edit", "photo.failed", "\(photo.path): \(error)") } }
            self.rendering = false; if gen == self.renderGen { self.refining = false; self.previewSimplified = false }
        }
    }

    /// Răspuns în timpul gestului: previzualizare redusă (≤ ~1400 px), UN SINGUR calcul în zbor (restul se contopește în «murdar» și se reia cu reglajele cele mai noi); un rezultat se publică doar dacă reglajele curente sunt încă cele randate. Rafinarea la `preview` urmează după pauză.
    private var previewShownGen = 0
    private var interactiveBusy = false, interactiveDirty = false
    /// «Preview rapid» (manual): în timpul gestului previzualizarea interactivă NU aplică reducerea de zgomot; rafinarea (după pauză) o aplică. Nu schimbă reglajul salvat, aprobarea sau exportul.
    @Published public var fastGesturePreview = false { didSet { if oldValue != fastGesturePreview { try? catalog.setSession("fast_gesture_preview", fastGesturePreview ? "1" : "0") } } }
    /// Automat și vizibil: dacă calculul interactiv CU reducere de zgomot depășește pragul măsurat (pe un Mac mai lent), cadrele interactive o omit până la eliberare.
    @Published public private(set) var autoSimplified = false
    /// Adevărat cât timp cadrul afișat în timpul gestului este simplificat (fără reducere de zgomot); se stinge când rezultatul final e gata.
    @Published public private(set) var previewSimplified = false
    private var nrComputeEMA = 0.0
    static let nrAutoThresholdMs = 140.0   // măsurat: cu NR cadrul interactiv ≈ 35–45 ms pe M2 Pro; peste 3× = degradare vizibilă
    // Urmărire fără intervale negative: fiecare eveniment de reglaj primește un id și un moment monoton; fiecare cerere reține ultimul eveniment pe care îl include; cadrul publicat poartă ambele.
    private var eventSeq = 0, latestEventId = 0, latestEventAt = 0.0
    private var traceSeq = 0
    let stall = StallMonitor()
    private func runInteractive(_ photo: PhotoRecord) {
        if interactiveBusy { interactiveDirty = true; return }
        interactiveBusy = true
        Task { [weak self] in
            var again = true
            while again {
                again = false; guard let self = self, self.current?.id == photo.id else { break }
                var adj = self.viewAdj(self.adjustments)
                let hasNR = adj.detail.on && (adj.detail.nrLuma > 0 || adj.detail.nrChroma > 0)
                let simplify = hasNR && (self.fastGesturePreview || self.autoSimplified)
                if simplify { adj.detail.nrLuma = 0; adj.detail.nrChroma = 0 }   // doar copia pentru cadrul interactiv; reglajul salvat rămâne
                self.previewSimplified = simplify
                let evId = self.latestEventId, evAt = self.latestEventAt; let tReq = MonoClock.now; let g0 = self.renderGen; let box = StageBox(); self.traceSeq += 1; let tid = self.traceSeq
                let r = try? await self.process(photo, adj, .interactive, stages: box)
                let tResume = MonoClock.now
                if hasNR && !simplify { let c = (box.tDone - box.tStart) * 1000; self.nrComputeEMA = self.nrComputeEMA == 0 ? c : self.nrComputeEMA * 0.7 + c * 0.3; if self.nrComputeEMA > Self.nrAutoThresholdMs { self.autoSimplified = true; DiagnosticLog.shared?.log(.warning, "interactive", "nr.auto_simplified", String(format: "calcul interactiv cu NR %.0f ms (mediu) > %.0f ms: cadrele din gest omit reducerea de zgomot; rafinarea o aplică", self.nrComputeEMA, Self.nrAutoThresholdMs)) } }
                if !hasNR { self.nrComputeEMA = 0; self.autoSimplified = false }
                if let r = r, self.current?.id == photo.id, self.previewShownGen < g0 {   // un rezultat interactiv nu înlocuiește niciodată o previzualizare mai nouă sau la fel de nouă
                    let img = ResultImage.load(r.url); self.afterImage = img; let tPub = MonoClock.now
                    let sup = self.latestEventId > evId   // între timp au apărut reglaje mai noi: cadrul reflectă evenimentul evId, nu ultimul
                    let total = (tPub - evAt) * 1000
                    let parts = [("eveniment→cerere", (tReq - evAt) * 1000), ("cerere→coadă", (box.tEnq - tReq) * 1000), ("așteptare coadă", (box.tStart - box.tEnq) * 1000), ("calcul+TIFF", (box.tDone - box.tStart) * 1000), ("coadă→fir principal", (tResume - box.tDone) * 1000), ("încărcare+publicare", (tPub - tResume) * 1000)]
                    let sum = parts.reduce(0) { $0 + $1.1 }; let st = self.stall.stats(from: evAt, to: tPub)
                    DiagnosticLog.shared?.log(.info, "interactive", "frame", String(format: "cadru#%d (eveniment#%d, înlocuit=%@) %dx%d cache=%@ · ", tid, evId, sup ? "da" : "nu", r.width, r.height, r.fromResultCache ? "da" : "nu") + parts.map { String(format: "%@ %.1f", $0.0, $0.1) }.joined(separator: " · ") + String(format: " · total %.1f ms (verificare: suma %.1f, diferență %.2f) · fir principal: %d eșantioane, mediană %.1f, p95 %.1f, max %.1f ms, >16 ms: %d", total, sum, total - sum, st.n, st.p50, st.p95, st.max, st.over16), durationMs: total)
                } else if r != nil { DiagnosticLog.shared?.log(.info, "interactive", "dropped", "cadru#\(tid) (eveniment#\(evId)) nepublicat: fotografia s-a schimbat sau există o previzualizare mai nouă") }
                if self.interactiveDirty { self.interactiveDirty = false; again = true }
            }
            self?.interactiveBusy = false
        }
    }

    func process(_ photo: PhotoRecord, _ adj: AdjustmentSet, _ q: ProcessQuality, stages: StageBox? = nil) async throws -> ProcessedImage {
        if engine == .resolveStyle, adj.family != .dwg { throw LocalCorrectionError.familyOwnEngineOnly }   // fără reinterpretare tăcută
        if engine == .resolveStyle, adj.locals.contains(where: { $0.enabled && !$0.adjustmentIsNeutral }) { throw LocalCorrectionError.ownEngineOnly }   // fără omisiune tăcută
        let proc: (any PhotoProcessing)? = engine == .own ? ownProcessor : resolveProcessor
        guard let proc = proc else { throw BridgeError.resolveNotRunning }
        stages?.tEnq = MonoClock.now
        return try await withCheckedThrowingContinuation { c in (q == .full ? fullQueue : (q == .interactive ? interactiveQueue : queue)).async {
            stages?.tStart = MonoClock.now; let r = Result { try proc.process(photoPath: photo.path, quality: q, adjustments: adj) }; stages?.tDone = MonoClock.now
            c.resume(with: r) } }
    }
    func adjustmentsFor(_ id: Int64) -> AdjustmentSet {
        if let j = try? catalog.edits(photoId: id), let a = try? JSONDecoder().decode(AdjustmentSet.self, from: Data(j.utf8)) { return a }; return AdjustmentSet.fresh(sessionFamily)
    }
    /// Familia cu care pornesc fotografiile FĂRĂ reglaje salvate (ultima aleasă în sesiune; se păstrează în catalog). Fotografiile cu reglaje salvate își păstrează propria familie.
    public var sessionFamily: WorkingFamily {
        get { ((try? catalog.session("family_default_v1")).flatMap { $0 }.flatMap { Int($0) }).flatMap { WorkingFamily(rawValue: $0) } ?? .dwg }
        set { try? catalog.setSession("family_default_v1", String(newValue.rawValue)) }
    }
    /// Schimbarea familiei de lucru: păstrează valorile fotografului și schimbă domeniul în care lucrează instrumentele (ASPECTUL se poate schimba); anulabilă, trece prin același mecanism (cache, randare, invalidarea aprobării).
    public func setFamily(_ f: WorkingFamily) {
        guard f != adjustments.family else { return }
        registerReset(LF("Familia de lucru: «%@». Valorile tale au rămas; aspectul se poate schimba.", f.shortLabel))
        var a = adjustments; a.family = f; adjustments = a; sessionFamily = f
        DiagnosticLog.shared?.log(.info, "family", "set", f.id)
    }

    // MARK: rezoluție plină la cerere (vederea comună: zoom/100%) — rezultatul procesat la rezoluție plină, doar pentru fotografia curentă; se eliberează la schimbarea fotografiei
    public var fullResolutionBusy: Bool { detailBusy }
    /// Rezultatul plin corespunde reglajelor curente (altfel e vechi și nu se afișează).
    public var fullResolutionIsCurrent: Bool { detailAfter != nil && detailFingerprint == fullFingerprint(viewAdj(adjustments)) }
    private func fullFingerprint(_ a: AdjustmentSet) -> String { memoFingerprint(a) + "|" + (engine == .own ? outputTransform.rawValue : "style") + "|\(AdjustmentSet.currentEngineRevision)" }
    /// Imaginea de afișat: rezoluție plină când zoomul o cere și e la zi; altfel previzualizarea (mărită), cu stare vizibilă în vedere.
    func viewAfter(_ v: ViewerState) -> NSImage? { v.wantsFullResolution && fullResolutionIsCurrent ? detailAfter : afterImage }
    func viewBefore(_ v: ViewerState) -> NSImage? { v.wantsFullResolution && fullResolutionIsCurrent && detailBase != nil ? detailBase : beforeImage }
    private func bindViewer() {
        viewerSub = viewer.$custom.combineLatest(viewer.$isFit).removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self = self, self.viewer.wantsFullResolution else { return }; self.requestFullResolution() }
    }
    /// 100% / Potrivit din bara de sus: aceeași vedere, fără un al doilea editor.
    public func openDetail() { viewer.set100(); requestFullResolution() }
    public func requestFullResolution() {
        guard isReady, let photo = current, !detailBusy, !fullResolutionIsCurrent else { return }
        flushSave(); detailBusy = true; detailError = ""; let adj = viewAdj(adjustments); let fp = fullFingerprint(adj)
        detailTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let r = try await self.process(photo, adj, .full)
                guard self.current?.id == photo.id else { self.detailBusy = false; return }
                let img = ResultImage.load(r.url)
                var base: NSImage? = img
                if !adj.isNeutral { let b = try await self.process(photo, adj.baseForCompare, .full); base = ResultImage.load(b.url) }
                guard self.current?.id == photo.id else { self.detailBusy = false; return }
                self.detailAfter = img; self.detailBase = base; self.detailFingerprint = fp; self.viewer.fullSize = CGSize(width: r.width, height: r.height); if r.sourceWidth > 0 { self.sourceSize = CGSize(width: r.sourceWidth, height: r.sourceHeight) }; self.viewer.revalidate()
                self.detailInfo = LF("Rezultat procesat · rezoluție plină %@×%@ · %@ · decupare %@", r.width, r.height, r.decode?.model ?? L("imagine redată"), r.decode?.cropPlan.defaultCropSource.rawValue ?? L("sursă redată"))
            } catch { if !(error is CancellationError) { self.detailError = "\(error)" } }
            self.detailBusy = false
            if self.viewer.wantsFullResolution, !self.fullResolutionIsCurrent, self.detailError.isEmpty { self.scheduleFullRefresh() }   // reglajele s-au schimbat între timp
        }
    }
    /// După o schimbare de reglaje la un zoom care cere rezoluție plină: reîmprospătare după o scurtă pauză (rezultatul vechi nu se afișează).
    func scheduleFullRefresh() {
        fullRefreshTask?.cancel()
        fullRefreshTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 1_200_000_000); guard !Task.isCancelled, let self = self, self.viewer.wantsFullResolution else { return }; self.requestFullResolution() }
    }
    public func closeDetail() { detailTask?.cancel(); fullRefreshTask?.cancel(); detailOpen = false; detailBusy = false; detailAfter = nil; detailBase = nil; detailError = ""; detailFingerprint = nil }

    // MARK: revizuire — previzualizări cu reglajele salvate ale fiecărei fotografii (neatinsele rămân neutre; nimic nu se aplică automat)
    /// Înregistrează un rezultat randat împreună cu amprenta cu care a fost produs (folosit de coada de revizuire; testabil).
    func storeReviewResult(_ id: Int64, _ image: NSImage?, fingerprint: String) { thumbs[id] = image; thumbFP[id] = fingerprint }
    func currentFingerprint(of id: Int64) -> String { approvalFingerprint(id == current?.id ? adjustments : adjustmentsFor(id)) }
    public enum ReviewStatus: Equatable { case approved, toCheck, processing, failed }
    /// Rezultatul afișat corespunde reglajelor salvate actuale (aceeași amprentă cu a aprobării)?
    public func thumbIsFresh(_ id: Int64) -> Bool { thumbs[id] != nil && thumbFP[id] == approvalFingerprint(id == current?.id ? adjustments : adjustmentsFor(id)) }
    public func reviewStatus(_ id: Int64) -> ReviewStatus {
        if reviewFailures[id] != nil { return .failed }
        if reviewProcessing == id || reviewPending.contains(id) { return .processing }
        return isApproved(id) ? .approved : .toCheck
    }
    /// Aprobarea e legată de rezultatul EVALUAT: se acordă doar când miniatura afișată e cea actuală; retragerea e oricând posibilă.
    @discardableResult public func setApproval(_ id: Int64, _ on: Bool) -> Bool {
        if !on { approvals.removeValue(forKey: id); persistApprovals(); return true }
        guard thumbIsFresh(id) else { return false }
        if id == current?.id { flushSave() }
        approvals[id] = approvalFingerprint(id == current?.id ? adjustments : adjustmentsFor(id)); persistApprovals(); return true
    }
    /// Procesare controlată (una câte una, previzualizare — niciodată full-resolution): doar fotografiile fără rezultat actual; reluabilă și anulabilă.
    public func reviewEnqueue(_ p: PhotoRecord) {
        guard isReady, !thumbIsFresh(p.id), reviewProcessing != p.id, !reviewPending.contains(p.id), reviewFailures[p.id] == nil else { return }
        reviewPending.append(p.id); batchProgress = (batchProgress?.done ?? 0, (batchProgress?.total ?? 0) + 1); objectWillChange.send(); reviewDrain(queueSource: nil)
    }
    public func reviewEnqueueAll(_ queue: [PhotoRecord], retryFailed: Bool = false) {
        if retryFailed { for p in queue { reviewFailures[p.id] = nil } }
        for p in queue { reviewEnqueue(p) }
        reviewKnown = Dictionary(uniqueKeysWithValues: queue.map { ($0.id, $0) })
    }
    private var reviewKnown: [Int64: PhotoRecord] = [:]
    public func reviewCancel() { reviewTask?.cancel(); reviewTask = nil; reviewPending = []; reviewProcessing = nil; batchProgress = nil; objectWillChange.send() }
    public var reviewStaleCount: (pending: Int, processing: Bool) { (reviewPending.count, reviewProcessing != nil) }
    private func reviewDrain(queueSource: [Int64: PhotoRecord]?) {
        guard reviewTask == nil else { return }
        flushSave()
        reviewTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled, let id = self.reviewPending.first {
                self.reviewPending.removeFirst(); self.reviewProcessing = id
                if let p = self.reviewKnown[id] ?? self.reviewPhoto(id) {
                    let adj = self.adjustmentsFor(p.id); let fp = self.approvalFingerprint(adj)
                    do { let r = try await self.process(p, adj, .preview); if Task.isCancelled { break }; self.storeReviewResult(p.id, ResultImage.load(r.url), fingerprint: fp); self.reviewFailures[p.id] = nil; self.failedPhotos[p.id] = nil }
                    catch { if error is CancellationError { break }; self.reviewFailures[p.id] = "\(error)"; self.failedPhotos[p.id] = "\(error)"; DiagnosticLog.shared?.log(.warning, "review", "photo.failed", "\(p.path): \(error)") }
                }
                self.reviewProcessing = nil; self.batchProgress = ((self.batchProgress?.done ?? 0) + 1, self.batchProgress?.total ?? 0)
            }
            self.reviewProcessing = nil; self.reviewTask = nil
            if self.reviewPending.isEmpty { self.batchProgress = nil }
        }
    }
    private func reviewPhoto(_ id: Int64) -> PhotoRecord? { (try? catalog.photos())?.first { $0.id == id } }
    /// Compatibil cu apelurile existente: pune în coadă DOAR fotografiile al căror rezultat e depășit sau lipsește.
    public func renderAll(_ queue: [PhotoRecord]) { guard isReady else { return }; flushSave(); reviewEnqueueAll(queue, retryFailed: true) }

    // MARK: export (rezoluție plină) — țintele vin DOAR din alegerea explicită
    public func exportTargets(_ queue: [PhotoRecord]) -> [PhotoRecord] {
        switch exportScope {
        case .approved: return queue.filter { isApproved($0.id) }
        case .current: return current.map { [$0] } ?? []
        case .queue: return queue
        }
    }
    public func chooseExportFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.prompt = L("Alege folderul de export")
        if p.runModal() == .OK, let u = p.url { exportFolder = u; try? catalog.setSession("export_folder", u.path) }
    }
    /// Planul exact al lotului curent (aceleași reguli ca la scriere): nume de ieșire, fișiere existente, omiteri.
    public func exportPlan(_ targets: [PhotoRecord]) -> [(photo: PhotoRecord, planned: PlannedOutput)] {
        guard let dest = exportFolder else { return [] }
        let names = targets.map { (($0.path as NSString).lastPathComponent as NSString).deletingPathExtension + "_GDC" }
        let plan = ExportService.plan(dir: dest, names: names, ext: exportFormatJPEG ? "jpg" : "tif", policy: exportCollision)
        return Array(zip(targets, plan)).map { (photo: $0.0, planned: $0.1) }
    }
    public var exportCanStart: Bool { exportCollision != .overwrite || exportOverwriteConfirmed }
    public func runExport(_ queue: [PhotoRecord]) {
        let targets = exportTargets(queue)
        guard isReady, let dest = exportFolder, case .idle = exportState, !targets.isEmpty, exportCanStart else { return }
        guard featureGate(.exportImages) else { exportState = .failed(Self.lockedMessage); return }
        guard !storageBlocked else { exportState = .failed(L("Discul de lucru nu este disponibil; exportul e în pauză. Reconectează discul (Setări → Stocare).")); return }
        let perImage: Int64 = exportFormatJPEG ? 30 * 1_048_576 : 220 * 1_048_576            // estimare prudentă pe fotografie (full-res)
        let dh = StorageConfig.checkExportDestination(dest, needed: perImage * Int64(targets.count))
        guard !dh.blocks, case .ok = dh else { exportState = .failed(dh.message); return }
        flushSave(); try? catalog.setSession("export_format", exportFormatJPEG ? "jpeg" : "tiff16")
        exportState = .running(done: 0, total: targets.count); exported = []
        exportItems = targets.map { ExportItem(id: $0.id, name: ($0.path as NSString).lastPathComponent, state: .waiting) }
        let fmt: ExportFormat = exportFormatJPEG ? .jpeg(quality: jpegQuality) : .tiff16; let policy = exportCollision
        exportFailures = []
        Task { [weak self] in
            guard let self = self else { return }
            var ok = 0, skipped = 0
            for (i, p) in targets.enumerated() {
                self.setExportItem(p.id, .running)
                do {   // o fotografie ilizibilă/invalidă se raportează și se omite; lotul continuă; originalul nu se modifică
                    let r = try await self.process(p, self.adjustmentsFor(p.id), .full)
                    let stem = ((p.path as NSString).lastPathComponent as NSString).deletingPathExtension
                    let out = try ExportService.export(result: r.url, original: URL(fileURLWithPath: p.path), to: dest, name: stem + "_GDC", format: fmt, rating: XMPSidecar.ratingForExport(decision: p.decision, stars: p.rating), collision: policy)
                    try? self.catalog.logExport(photoId: p.id, path: out.path, format: self.exportFormatJPEG ? "jpeg" : "tiff16")
                    self.exported.append((stem, out.path)); ok += 1; self.setExportItem(p.id, .done(out.lastPathComponent))
                } catch let e as PipelineError {
                    if case .outputExists = e { skipped += 1; self.setExportItem(p.id, .skipped("\(e)")) }
                    else { self.exportFailures.append((p.path, "\(e)")); self.setExportItem(p.id, .failed("\(e)")); DiagnosticLog.shared?.log(.warning, "export", "omis", "\(p.path): \(e)") }
                } catch { self.exportFailures.append((p.path, "\(error)")); self.setExportItem(p.id, .failed("\(error)")); DiagnosticLog.shared?.log(.warning, "export", "omis", "\(p.path): \(error)") }
                self.exportState = .running(done: i + 1, total: targets.count)
            }
            if ok == 0 && !self.exportFailures.isEmpty { self.exportState = .failed(LF("Nicio fotografie nu a putut fi exportată (%@ omise): %@", self.exportFailures.count, self.exportFailures[0].1)) }
            else { self.exportState = .finished(count: ok, folder: dest.path) }
            _ = skipped
        }
    }
    private func setExportItem(_ id: Int64, _ st: ExportItem.State) { if let i = exportItems.firstIndex(where: { $0.id == id }) { exportItems[i].state = st } }
    public func resetExport() { exportState = .idle }
}
