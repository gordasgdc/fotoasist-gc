import SwiftUI
import AppKit
import Combine
import PhotoCore
import PhotoResolve

/// Identitatea și opțiunile UNEI vizualizări de analiză (fereastră separată sau panou din tablou): analiza aleasă și, unde există, opțiunile de afișare. Independentă de analiza din inspector.
public struct AnalysisViewSpec: Codable, Equatable, Identifiable {
    public var id = UUID(); public var mode: AnalysisMode = .clipping; public var nrGain: Double = 4
    public init(mode: AnalysisMode = .clipping, nrGain: Double = 4) { self.mode = mode; self.nrGain = nrGain }
}

/// O vizualizare de analiză: starea ei proprie (rezultat, încărcare, eroare). NU deține fotografia și NU copiază sesiunea de editare: sursa e unică (`EditingModel`), iar rezultatele se calculează de `AnalysisHub`.
@MainActor public final class AnalysisView: ObservableObject, Identifiable {
    public let id: UUID
    @Published public var spec: AnalysisViewSpec { didSet { if oldValue.mode != spec.mode || oldValue.nrGain != spec.nrGain { reset(); hub?.refresh() }; hub?.persistDashboardIfNeeded(self) } }
    @Published public private(set) var result: AnalysisResult?
    @Published public private(set) var image: NSImage?
    /// Fotografia și amprenta reglajelor pentru care e calculat `result` (o analiză a altei fotografii NU se arată drept a celei curente).
    @Published public private(set) var shownPhoto: Int64?
    @Published public private(set) var shownFingerprint = ""
    @Published public private(set) var busy = false
    @Published public private(set) var error: String?
    @Published public private(set) var updatedAt: Date?
    weak var hub: AnalysisHub?
    public init(spec: AnalysisViewSpec) { self.spec = spec; id = spec.id }
    func reset() { result = nil; image = nil; shownPhoto = nil; shownFingerprint = ""; error = nil; updatedAt = nil }
    func markBusy(forPhoto p: Int64) { busy = true; if shownPhoto != p { result = nil; image = nil; shownPhoto = nil; shownFingerprint = "" } ; error = nil }
    func receive(_ r: AnalysisResult, photo: Int64, fingerprint: String) { result = r; image = r.makeImage(); shownPhoto = photo; shownFingerprint = fingerprint; busy = false; error = nil; updatedAt = Date() }
    func fail(_ message: String, photo: Int64) { result = nil; image = nil; shownPhoto = photo; busy = false; error = message }
    func idle() { busy = false }
    /// Titlul vizualizării (ferestrele îl afișează în bara de titlu).
    public var title: String { L("Analiză") + " · " + spec.mode.label + (spec.mode == .nrDifference ? " ×" + String(format: "%g", spec.nrGain) : "") }
}

/// Calculează DOAR analizele cerute de vizualizările active, o singură dată per (analiză, amplificare), pe imaginea procesată deja existentă (rezultatul din cache, fără decodare nouă); ignoră rezultatele depășite.
@MainActor public final class AnalysisHub: ObservableObject {
    weak var ed: EditingModel?
    private var registered: [UUID: Weak] = [:]
    private final class Weak { weak var v: AnalysisView?; init(_ v: AnalysisView) { self.v = v } }
    private final class Gen: @unchecked Sendable { private let l = NSLock(); private var n = 0; func bump() -> Int { l.lock(); n += 1; defer { l.unlock() }; return n }; var value: Int { l.lock(); defer { l.unlock() }; return n } }
    private let gen = Gen(); private let queue = DispatchQueue(label: "photoassist.analysishub", qos: .utility)
    /// Ultimele măsurători (informativ): câte analize unice și cât a durat setul.
    @Published public private(set) var lastRun: (unique: Int, views: Int, seconds: Double)?
    // configurația tabloului (panouri alese de utilizator), păstrată între porniri
    @Published public private(set) var dashboard: [AnalysisView] = []
    static let dashKey = "gdcpa.analysis.dashboard"

    public func register(_ v: AnalysisView) { v.hub = self; registered[v.id] = Weak(v); refresh() }
    public func unregister(_ v: AnalysisView) { registered[v.id] = nil; if registered.isEmpty { _ = gen.bump() } }
    public var activeCount: Int { registered.values.filter { $0.v != nil }.count }

    // tabloul comun
    public func loadDashboard() {
        if dashboard.isEmpty {
            let saved = (UserDefaults.standard.data(forKey: Self.dashKey)).flatMap { try? JSONDecoder().decode([AnalysisViewSpec].self, from: $0) } ?? []
            let specs = saved.isEmpty ? [AnalysisViewSpec(mode: .clipping), AnalysisViewSpec(mode: .saturation), AnalysisViewSpec(mode: .skin)] : saved
            dashboard = specs.map { AnalysisView(spec: $0) }
        }
        dashboard.forEach { register($0) }
    }
    public func unloadDashboard() { dashboard.forEach { unregister($0) }; dashboard.removeAll() }
    public func addPanel(_ mode: AnalysisMode = .clipping) { guard dashboard.count < 9 else { return }; let v = AnalysisView(spec: AnalysisViewSpec(mode: mode)); dashboard.append(v); register(v); persistDashboard() }
    public func removePanel(_ id: UUID) { if let v = dashboard.first(where: { $0.id == id }) { unregister(v); dashboard.removeAll { $0.id == id }; persistDashboard() } }
    func persistDashboardIfNeeded(_ v: AnalysisView) { if dashboard.contains(where: { $0.id == v.id }) { persistDashboard() } }
    func persistDashboard() { if let d = try? JSONEncoder().encode(dashboard.map { $0.spec }) { UserDefaults.standard.set(d, forKey: Self.dashKey) } }

    /// Reîmprospătează vizualizările active pentru fotografia și reglajele curente. Apelat la fiecare schimbare relevantă (aceleași declanșatoare ca analiza din inspector).
    public func refresh() {
        guard let ed = ed else { return }
        let views = registered.values.compactMap { $0.v }; registered = registered.filter { $0.value.v != nil }
        guard !views.isEmpty else { return }
        guard let snap = ed.analysisSnapshot() else { views.forEach { $0.idle(); if $0.result != nil { $0.reset() } }; return }
                let g = gen.bump(); let t0 = Date()
        var keys: [String: (AnalysisMode, Double)] = [:]
        // o vizualizare PROASPĂTĂ (aceeași fotografie și aceleași reglaje, fără eroare) nu se recalculează; una cu aceeași analiză ca o vizualizare proaspătă primește rezultatul acesteia, fără calcul nou
        let fresh = views.filter { $0.result != nil && $0.error == nil && $0.shownPhoto == snap.photo.id && $0.shownFingerprint == snap.fingerprint }
        for v in views {
            if fresh.contains(where: { $0 === v }) { continue }
            if let twin = fresh.first(where: { Self.key($0.spec) == Self.key(v.spec) }), let r = twin.result { v.receive(r, photo: snap.photo.id, fingerprint: snap.fingerprint); continue }
            v.markBusy(forPhoto: snap.photo.id); keys[Self.key(v.spec)] = (v.spec.mode, v.spec.mode == .nrDifference ? v.spec.nrGain : 0)
        }
        guard !keys.isEmpty else { return }
        let gens = gen, photo = snap.photo, adj = snap.adj, own = snap.own, fp = snap.fingerprint
        queue.async { [weak self] in
            for (k, (mode, gain)) in keys {
                if gens.value != g { return }                               // cerere depășită: restul nu se mai calculează
                let r = Result { try own.analyze(photoPath: photo.path, adjustments: adj, mode: mode, nrGain: Float(gain == 0 ? 4 : gain)) }
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    guard let self = self, gens.value == g, self.ed?.current?.id == photo.id else { return }       // alt cadru sau alt set între timp: nu se prezintă
                    for v in self.registered.values.compactMap({ $0.v }) where Self.key(v.spec) == k {
                        switch r { case .success(let res): v.receive(res, photo: photo.id, fingerprint: fp); case .failure(let e): let ns = e as NSError; v.fail(ns.domain == NSCocoaErrorDomain ? ns.localizedDescription : "\(e)", photo: photo.id) } }
                } }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { guard let self = self, gens.value == g else { return }; self.lastRun = (keys.count, views.count, Date().timeIntervalSince(t0)) } }
        }
    }
    static func key(_ s: AnalysisViewSpec) -> String { s.mode == .nrDifference ? "\(s.mode.rawValue)|\(s.nrGain)" : s.mode.rawValue }
}

extension EditingModel {
    /// Fotografia, reglajele afișate și procesorul pentru analize (nimic nu se copiază; fotografia se procesează o singură dată, din cache).
    func analysisSnapshot() -> (photo: PhotoRecord, adj: AdjustmentSet, own: OwnCoreProcessor, fingerprint: String)? {
        guard engine == .own, let p = current, let own = ownProcessor else { return nil }
        let a = viewAdj(adjustments); return (p, a, own, a.fingerprint)
    }
}
