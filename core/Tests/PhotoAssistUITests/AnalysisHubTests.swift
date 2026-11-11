import XCTest
@testable import PhotoAssistUI
import PhotoCore
import PhotoResolve

/// Ferestre/panouri de analiză independente pe RAW real: identitate proprie, două instanțe ale aceleiași analize, nicio contaminare între ele, fotografie schimbată = rezultat vechi ascuns, fișier invalid = eroare explicită, cost măsurat cu 1/3/6 vizualizări.
@MainActor
final class AnalysisHubTests: XCTestCase {
    func setup() throws -> (EditingModel, [PhotoRecord], URL)? {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["GDC_PA_RAW_DIR"], let scratch = env["GDC_PA_SCRATCH"] else { return nil }
        let raws = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { ["arw", "cr2", "cr3"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted().prefix(2).map { dir + "/" + $0 }
        guard raws.count == 2 else { return nil }
        let work = URL(fileURLWithPath: scratch).appendingPathComponent("hub_\(UUID().uuidString.prefix(6))"); try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let bad = work.appendingPathComponent("BAD_0001.ARW"); FileManager.default.createFile(atPath: bad.path, contents: Data())
        let cat = try Catalog(url: work.appendingPathComponent("c.sqlite")); let paths = raws + [bad.path]
        _ = try cat.importFiles(paths.enumerated().map { ($1, ((try? FileManager.default.attributesOfItem(atPath: $1)[.size]) as? NSNumber)?.int64Value ?? 0, Int64(1), "Cam", Date(timeIntervalSince1970: Double($0))) })
        let ed = EditingModel(catalog: cat, workDir: work.appendingPathComponent("w")); ed.viewer.canvasSize = CGSize(width: 1200, height: 800); return (ed, try cat.photos(), work)
    }
    func wait(_ cond: @MainActor @escaping () -> Bool, _ s: Double = 120) async { let t = Date(); while !cond() && Date().timeIntervalSince(t) < s { try? await Task.sleep(nanoseconds: 100_000_000) } }

    func testIndependentViewsDuplicatesStaleAndInvalidFile() async throws {
        guard let (ed, ps, work) = try setup() else { throw XCTSkip("fără RAW") }; defer { try? FileManager.default.removeItem(at: work) }
        let hub = ed.analysisHub
        let a = AnalysisView(spec: AnalysisViewSpec(mode: .clipping)), b = AnalysisView(spec: AnalysisViewSpec(mode: .saturation)), c = AnalysisView(spec: AnalysisViewSpec(mode: .skin)), a2 = AnalysisView(spec: AnalysisViewSpec(mode: .clipping))
        ed.open(ps[0]); await wait { ed.afterImage != nil && !ed.rendering }
        [a, b, c, a2].forEach { hub.register($0) }
        await wait { [a, b, c, a2].allSatisfy { $0.result != nil } }
        XCTAssertTrue([a, b, c, a2].allSatisfy { $0.shownPhoto == ps[0].id && $0.result != nil }, "expunere, saturație, piele și o a doua instanță, simultan")
        XCTAssertEqual(a.result?.mode, .clipping); XCTAssertEqual(b.result?.mode, .saturation); XCTAssertEqual(c.result?.mode, .skin)
        XCTAssertEqual(hub.lastRun?.unique, 3, "două instanțe ale aceleiași analize se calculează o singură dată"); XCTAssertEqual(hub.lastRun?.views, 4)
        // schimbarea selectorului dintr-o fereastră nu le atinge pe celelalte și nu atinge analiza din inspector
        let bBefore = b.image, inspectorMode = ed.analysisMode
        a2.spec.mode = .chromaRel; await wait { a2.result?.mode == .chromaRel }
        XCTAssertEqual(a2.result?.mode, .chromaRel); XCTAssertEqual(a.result?.mode, .clipping); XCTAssertEqual(b.image, bBefore); XCTAssertEqual(ed.analysisMode, inspectorMode)
        // a doua instanță a aceleiași analize, cu opțiuni diferite (NR diferență ×2 vs ×8)
        let n1 = AnalysisView(spec: AnalysisViewSpec(mode: .nrDifference, nrGain: 2)), n2 = AnalysisView(spec: AnalysisViewSpec(mode: .nrDifference, nrGain: 8)); hub.register(n1); hub.register(n2)
        await wait { n1.result != nil && n2.result != nil }; XCTAssertEqual(n1.result?.nrGain, 2); XCTAssertEqual(n2.result?.nrGain, 8)
        // fotografie nouă: rezultatul vechi NU rămâne afișat drept al celei curente
        ed.open(ps[1]); XCTAssertNotEqual(a.shownPhoto, ed.current?.id, "până la calcul, analiza veche aparține altei fotografii (interfața o ascunde)")
        await wait { a.shownPhoto == ps[1].id && a.result != nil }; XCTAssertEqual(a.shownPhoto, ps[1].id)
        // fișier invalid: eroare explicită, restul navigării continuă
        ed.open(ps[2]); await wait { a.error != nil }; XCTAssertNotNil(a.error, "fișier gol ⇒ eroare explicită"); XCTAssertNil(a.result)
        [a, b, c, a2, n1, n2].forEach { hub.unregister($0) }
    }
    func testCostWithOneThreeAndSixViews() async throws {
        guard let (ed, ps, work) = try setup() else { throw XCTSkip("fără RAW") }; defer { try? FileManager.default.removeItem(at: work) }
        ed.open(ps[0]); await wait { ed.afterImage != nil && !ed.rendering }; ed.adjustments.detail.on = true; ed.adjustments.detail.nrLuma = 0.6; ed.adjustments.detail.nrChroma = 0.5; await wait { !ed.rendering }; try await Task.sleep(nanoseconds: 3_000_000_000)
        let hub = ed.analysisHub; var rows: [String] = []
        for n in [1, 3, 6] {
            let modes: [AnalysisMode] = [.clipping, .saturation, .skin, .falseColour, .chromaRel, .nrDifference]
            let vs = modes.prefix(n).map { AnalysisView(spec: AnalysisViewSpec(mode: $0)) }
            vs.forEach { $0.hub = hub }
            let t = Date(); vs.forEach { hub.register($0) }; await wait { vs.allSatisfy { $0.result != nil } }; let first = Date().timeIntervalSince(t)
            let t2 = Date(); ed.adjustments.contrast += 0.01; await wait { vs.allSatisfy { $0.shownFingerprint == ed.analysisSnapshot()?.fingerprint && $0.result != nil } }; let upd = Date().timeIntervalSince(t2)
            rows.append(String(format: "HUBCOST %d vizualizări: prima calculare %.0f ms · actualizare după un reglaj (inclusiv procesarea previzualizării) %.0f ms · analize unice %d", n, first * 1000, upd * 1000, hub.lastRun?.unique ?? 0))
            vs.forEach { hub.unregister($0) }
        }
        rows.forEach { print($0) }
    }
}
