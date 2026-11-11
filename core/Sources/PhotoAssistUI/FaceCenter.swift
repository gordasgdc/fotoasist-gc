import SwiftUI
import AppKit
import PhotoCore

/// Analiza de fețe INCREMENTALĂ: sare peste fotografiile cu rezultat valid (versiune + fișier), lucrează cu concurență limitată (2) pe previzualizarea de 1400 px (etapa 1; rezoluția maximă nu e necesară), se poate ANULA și RELUA (reia exact ce lipsește) și nu blochează navigarea.
/// Sugestiile derivate sunt explicabile și reversibile; nu schimbă decizii, nu aleg cadre și nu resping nimic.
@MainActor public final class FaceCenter: ObservableObject {
    @Published public private(set) var done = 0
    @Published public private(set) var total = 0
    @Published public private(set) var running = false
    @Published public private(set) var tick = 0                     // se schimbă la fiecare rezultat nou (reîmprospătare UI)
    @Published public var drawingZone = false
    @Published public var focus: CGRect?                            // zona de arătat în lupă (normalizată)
    @Published public private(set) var lastSeconds = 0.0
    /// Cadre pe care analiza a rulat dar NU a putut evalua (motiv în cuvinte); rămân «de analizat» și se pot relua. Doar în sesiune (nu e verdict despre fotografie).
    @Published public private(set) var failed: [Int64: String] = [:]
    /// Ultimul set analizat (ca să se poată arăta rezultatul pe fotografii: cu fețe / fără fețe / nu s-a putut evalua / neanalizate).
    @Published public private(set) var lastRun: (label: String, ids: [Int64])?
    public func tally(_ ps: [PhotoRecord]) -> (withFaces: Int, noFaces: Int, failed: Int, pending: Int) {
        _ = tick; var w = 0, n = 0, f = 0, p = 0
        for ph in ps { if let r = catalog.faceResult(for: ph) { if r.faces.isEmpty { n += 1 } else { w += 1 } } else if failed[ph.id] != nil { f += 1 } else { p += 1 } }
        return (w, n, f, p)
    }
    let catalog: Catalog; let store: ImageStore; private var task: Task<Void, Never>?
    /// Analizorul (înlocuibil în teste).
    var analyze: @Sendable (CGImage) throws -> [FaceObservation] = { try FaceAnalyzer.analyze($0) }
    public init(catalog: Catalog, store: ImageStore) { self.catalog = catalog; self.store = store }

    public func result(_ p: PhotoRecord) -> FaceResult? { _ = tick; return catalog.faceResult(for: p) }
    public func pending(_ ps: [PhotoRecord]) -> [PhotoRecord] { ps.filter { catalog.faceResult(for: $0) == nil } }
    public func subject(_ p: PhotoRecord) -> SubjectState { _ = tick; return catalog.subject(photoId: p.id) }
    public func setSubject(_ s: SubjectState, _ p: PhotoRecord) { try? catalog.setSubject(s, photoId: p.id); tick += 1 }

    public func start(_ photos: [PhotoRecord], label: String = L("selecția")) {
        guard !running else { return }; let todo = pending(photos); guard !todo.isEmpty else { return }
        lastRun = (label, photos.map { $0.id }); failed = failed.filter { k, _ in !todo.contains { $0.id == k } }
        running = true; total = todo.count; done = 0
        let cat = catalog, st = store, fn = analyze
        task = Task { [weak self] in
            var idx = 0
            while idx < todo.count, !Task.isCancelled {
                let batch = Array(todo[idx..<min(idx + 2, todo.count)]); idx += batch.count      // concurență limitată: 2
                await withTaskGroup(of: (PhotoRecord, FaceResult?, String?).self) { g in
                    for p in batch { g.addTask {
                        guard !Task.isCancelled else { return (p, nil, nil) }
                        guard let ns = await st.image(for: p, kind: .view), let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return (p, nil, L("Nu există o imagine de analizat (fișier lipsă, gol sau nedecodabil).")) }
                        let t0 = Date(); guard let fs = try? fn(cg) else { return (p, nil, L("Detectorul de fețe nu a putut procesa imaginea.")) }
                        return (p, FaceResult(version: FaceAnalyzer.version, size: p.size, mtimeNs: p.mtimeNs, previewW: cg.width, previewH: cg.height, faces: fs.map(FaceAnalyzer.stored), seconds: Date().timeIntervalSince(t0), config: FaceAnalyzer.configLabel), nil) } }
                    for await (p, r, why) in g { if let r = r { try? cat.setFaceResult(r, photoId: p.id); await MainActor.run { self?.failed[p.id] = nil; self?.lastSeconds = r.seconds; self?.tick += 1 } } else if let why { await MainActor.run { self?.failed[p.id] = why; self?.tick += 1 } }; await MainActor.run { self?.done += 1 } }
                }
            }
            await MainActor.run { self?.running = false }
        }
    }
    /// Anulează: ce e gata rămâne în cache; «Reia» (start) continuă cu ce lipsește.
    public func cancel() { task?.cancel(); running = false }

    /// Sugestii explicabile pentru un cadru (observații, nu verdicte). Detecția clipirii e EXPERIMENTALĂ: raportul geometric al ochiului nu e o probabilitate.
    public struct Hint: Identifiable, Equatable { public var id: Int; public var symbol: String; public var title: String; public var why: String }
    public func hints(_ p: PhotoRecord) -> [Hint] {
        if result(p) == nil, let why = failed[p.id] { return [Hint(id: 0, symbol: "exclamationmark.triangle", title: L("Nu se poate evalua"), why: why)] }
        guard let r = result(p) else { return [Hint(id: 0, symbol: "clock", title: L("Analiză neefectuată"), why: L("Fețele nu au fost încă analizate pentru acest cadru."))] }
        if r.faces.isEmpty { return [Hint(id: 0, symbol: "questionmark.circle", title: L("Nicio față detectată"), why: L("Nu înseamnă fotografie fără persoane (față mică, profil, mască, față acoperită sau în afara detectorului) și nu e un scor de calitate. Poți indica manual subiectul."))] }
        let eyeHints: [Hint] = r.faces.enumerated().map { i, f in
            let b = FaceAnalyzer.blinkSuggestion(FaceAnalyzer.observation(f))
            let sym: String; switch b.state { case .closed: sym = "eye.slash"; case .open: sym = "eye"; case .uncertain: sym = "questionmark.circle"; case .notEvaluated: sym = "minus.circle" }
            return Hint(id: i + 1, symbol: sym, title: LF("Față %@: %@ · experimental", i + 1, b.text), why: LF("Raport geometric al conturului ochiului (st %@, dr %@), praguri inițiale NEevaluate; nu e probabilitatea ca ochiul să fie închis; ochii închiși pot fi intenționați.", f.left.map { String(format: "%.2f", $0.openness) } ?? "—", f.right.map { String(format: "%.2f", $0.openness) } ?? "—"))
        }
        let qh: [Hint] = r.faces.enumerated().compactMap { (i, f) -> Hint? in
            let o = FaceAnalyzer.observation(f); guard let q = o.captureQuality else { return nil }
            let small = o.box.height < FaceQualityCompare.minFaceHeight
            return Hint(id: 100 + i, symbol: "sparkle.magnifyingglass", title: LF("Față %@: calitate de captură %@ (Vision)", i + 1, String(format: "%.2f", q)),
                        why: small ? L("Față mică: scorul e puțin de încredere. Scor relativ 0–1 (claritate, expunere, poziție); NU e focalizarea pe ochi și nu e un verdict.") : L("Scor relativ 0–1 (claritate, expunere, poziție, expresie), util în a compara aceeași față între cadre. NU e focalizarea pe ochi, nu e un verdict; profilul, ochelarii și lumina slabă îl coboară."))
        }
        return eyeHints + qh
    }
}
