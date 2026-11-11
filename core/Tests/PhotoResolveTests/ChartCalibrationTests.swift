import XCTest
import CPhotoCore
import PhotoRaw
@testable import PhotoResolve

/// ColorChecker: referință (față de oracolul Colour), ΔE00, geometrie/orientare/perspectivă, eșantionare, validare, potrivire și aplicare — toate pe date SINTETICE (validarea pe fotografii reale cu chart rămâne DESCHISĂ).
final class ChartCalibrationTests: XCTestCase {
    let camera: [[Double]] = [[0.80, 0.15, 0.05], [0.10, 0.85, 0.05], [0.03, 0.22, 0.75]]   // „senzor” cu amestec de canale + WB greșit
    let wb: [Double] = [1.15, 1.0, 0.82]
    func ref(_ id: ChartModelID = .classicAfter2014) -> [ChartPatch] { ChartReference.load(id)!.patches }
    func measured(_ r: [Double], scale: Double) -> [Double] { let v = (0..<3).map { r[$0] * wb[$0] }; return (0..<3).map { scale * (camera[$0][0] * v[0] + camera[$0][1] * v[1] + camera[$0][2] * v[2]) } }
    /// Imagine sintetică: câmp negru-gri + chartul randat prin omografia colțurilor (cu goluri între petice); `tweak(patch, lx, ly, color) -> color` pentru anomalii.
    func render(_ grid: ChartGrid, w: Int = 640, h: Int = 440, scale: Double = 0.55, noise: Double = 0, patches: [ChartPatch]? = nil, tweak: ((Int, Double, Double, [Double]) -> [Double])? = nil) -> FloatImage {
        let P = patches ?? ref(); var img = [Float](repeating: 0.04, count: w * h * 3); var st: UInt32 = 99; func r() -> Double { st = st &* 1664525 &+ 1013904223; return Double(st >> 8) / 16777216 - 0.5 }
        for idx in 1...24 { let c0 = Double((idx - 1) % 6), r0 = Double((idx - 1) / 6); let base = measured(P[idx - 1].dwg, scale: scale)
            var ly = r0 + 0.06; while ly < r0 + 0.94 { var lx = c0 + 0.06; while lx < c0 + 0.94 { let p = grid.imagePoint(logicalX: lx, logicalY: ly); let x = Int(Double(p.x) * Double(w)), y = Int(Double(p.y) * Double(h))
                if x >= 0, y >= 0, x < w, y < h { var col = base; if let t = tweak { col = t(idx, lx - c0, ly - r0, base) }; for k in 0..<3 { img[(y * w + x) * 3 + k] = Float(col[k] * (1 + noise * r())) } }; lx += 0.004 }; ly += 0.004 } }
        return FloatImage(width: w, height: h, rgb: img)
    }
    func persp() -> ChartGrid { var g = ChartGrid(); g.corners = [CGPoint(x: 0.12, y: 0.20), CGPoint(x: 0.86, y: 0.14), CGPoint(x: 0.80, y: 0.84), CGPoint(x: 0.17, y: 0.78)]; return g }

    func testReferenceMatchesOracleAndDeltaE2000MatchesOracle() {
        for id in ChartModelID.allCases { let P = ref(id); XCTAssertEqual(P.count, 24); XCTAssertEqual(P[0].name, "dark skin"); XCTAssertTrue(P[18].name.hasPrefix("white")); XCTAssertTrue(P[23].name.hasPrefix("black"))
            let g = ChartOracleGolden.dwg[id.rawValue]!; var worst = 0.0; for i in 0..<24 { for k in 0..<3 { worst = max(worst, abs(P[i].dwg[k] - g[i][k])) } }; XCTAssertLessThan(worst, 2e-6, "\(id) față de oracol: \(worst)") }
        XCTAssertNotEqual(ref(.classicAfter2014)[18].lab, ref(.classicLegacy)[18].lab, "edițiile diferă (white 95.19 vs 96.54)")
        var w = 0.0; for (a, b, e) in ChartOracleGolden.de2000 { w = max(w, abs(DeltaE.ciede2000(a, b) - e)) }; XCTAssertLessThan(w, 1e-6, "ΔE00 vs oracol \(w)")
        var lab = ref()[3].lab, dwg = [0.0, 0.0, 0.0]; pc_chart_reference_dwg(&lab, &dwg); var back = [0.0, 0.0, 0.0]; pc_dwg_to_lab_d50(&dwg, &back); for k in 0..<3 { XCTAssertEqual(back[k], lab[k], accuracy: 1e-8, "dus-întors Lab↔DWG") }
        let info = ChartReference.load(.classicAfter2014)!; XCTAssertTrue(info.source.contains("X-Rite")); XCTAssertTrue(info.conditions.contains("D50")); XCTAssertTrue(info.rights.contains("Resolve"))
    }
    func testGridOrientationOrderPerspectiveAndMirror() {
        var g = ChartGrid(); g.corners = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.9, y: 0.7), CGPoint(x: 0.1, y: 0.7)]
        let p1 = g.patchCenter(1), p6 = g.patchCenter(6), p19 = g.patchCenter(19), p24 = g.patchCenter(24)
        XCTAssertLessThan(p1.x, 0.2); XCTAssertLessThan(p1.y, 0.2); XCTAssertGreaterThan(p6.x, 0.8); XCTAssertLessThan(p6.y, 0.2); XCTAssertLessThan(p19.x, 0.2); XCTAssertGreaterThan(p19.y, 0.55); XCTAssertGreaterThan(p24.x, 0.8); XCTAssertGreaterThan(p24.y, 0.55)
        var r = g; r.rotation = 1; let q1 = r.patchCenter(1); XCTAssertGreaterThan(q1.x, 0.75); XCTAssertLessThan(q1.y, 0.2, "rotit 90° orar: petic 1 la dreapta-sus")
        var r2 = g; r2.rotation = 2; XCTAssertGreaterThan(r2.patchCenter(1).x, 0.8); XCTAssertGreaterThan(r2.patchCenter(1).y, 0.55, "180°: petic 1 la dreapta-jos")
        var m = g; m.mirrored = true; XCTAssertGreaterThan(m.patchCenter(1).x, 0.8); XCTAssertLessThan(m.patchCenter(1).y, 0.2, "oglindit: petic 1 la dreapta-sus")
        let all = Set((1...24).map { i -> String in let p = g.patchCenter(i); return "\(Int(p.x * 100)),\(Int(p.y * 100))" }); XCTAssertEqual(all.count, 24, "24 de poziții distincte")
        let pg = persp(); let c = pg.imagePoint(logicalX: 3, logicalY: 2)   // centrul câmpului = intersecția diagonalelor (proprietate proiectivă)
        let (a, b, cc, d) = (pg.corners[0], pg.corners[2], pg.corners[1], pg.corners[3]); let den = (a.x - b.x) * (cc.y - d.y) - (a.y - b.y) * (cc.x - d.x)
        let ix = ((a.x * b.y - a.y * b.x) * (cc.x - d.x) - (a.x - b.x) * (cc.x * d.y - cc.y * d.x)) / den, iy = ((a.x * b.y - a.y * b.x) * (cc.y - d.y) - (a.y - b.y) * (cc.x * d.y - cc.y * d.x)) / den
        XCTAssertEqual(Double(c.x), Double(ix), accuracy: 1e-9); XCTAssertEqual(Double(c.y), Double(iy), accuracy: 1e-9)
    }
    func testSamplingRecoversPatchColoursUnderPerspectiveAndEveryOrientation() {
        let P = ref(); for rot in 0..<4 { for mir in [false, true] {
            var g = persp(); g.rotation = rot; g.mirrored = mir; let img = render(g); let S = ChartSampler.sample(image: img, grid: g, clipLevel: 0.98); var worst = 0.0
            for i in 0..<24 { let e = measured(P[i].dwg, scale: 0.55); for k in 0..<3 { worst = max(worst, abs(S[i].mean[k] - e[k]) / max(e[k], 0.01)) }; XCTAssertEqual(S[i].outsideFraction, 0) }
            XCTAssertLessThan(worst, 0.01, "rot \(rot) oglindit \(mir): eroare relativă \(worst)") } }
    }
    func testValidationFlagsCutOffClippedDarkNonUniformReflectionAndRefusesWhenInsufficient() {
        let P = ref(); let g = persp(); let thr = ChartValidator.Thresholds()
        let clean = ChartValidator.validate(ChartSampler.sample(image: render(g), grid: g, clipLevel: 0.98), reference: P, thresholds: thr); XCTAssertTrue(clean.ok, clean.message); XCTAssertEqual(clean.usable.count, 24)
        let img = render(g, tweak: { i, lx, ly, c in
            if i == 5 { return [1.2, 1.2, 1.2] }                                           // saturat
            if i == 9 { return c.map { $0 * (0.5 + 1.0 * lx) } }                             // neuniform (gradient)
            if i == 14 && lx > 0.3 && lx < 0.6 && ly > 0.3 && ly < 0.6 { return [3, 3, 3] } // reflexie (pată luminoasă)
            return c })
        var v = ChartValidator.validate(ChartSampler.sample(image: img, grid: g, clipLevel: 0.98), reference: P, thresholds: thr)
        XCTAssertTrue(v.issues[5]?.contains(.clipped) ?? false); XCTAssertTrue(v.issues[9]?.contains(.nonUniform) ?? false); XCTAssertTrue(v.issues[14]?.contains(.reflection) ?? false); XCTAssertNil(v.issues[1]); XCTAssertTrue(v.ok); XCTAssertEqual(v.usable.count, 21)
        let dark = render(g, scale: 0.0035); v = ChartValidator.validate(ChartSampler.sample(image: dark, grid: g, clipLevel: 0.98), reference: P, thresholds: thr); XCTAssertTrue(v.issues[24]?.contains(.tooDark) ?? false)
        var cut = g; cut.corners = [CGPoint(x: 0.12, y: 0.20), CGPoint(x: 1.25, y: 0.14), CGPoint(x: 1.2, y: 0.84), CGPoint(x: 0.17, y: 0.78)]; v = ChartValidator.validate(ChartSampler.sample(image: render(g), grid: cut, clipLevel: 0.98), reference: P, thresholds: thr)
        XCTAssertTrue(v.issues.values.contains { $0.contains(.cutOff) }, "petice în afara cadrului"); XCTAssertFalse(v.ok, "prea multe petice tăiate ⇒ refuz"); XCTAssertTrue(v.message.contains("utilizabile"))
        XCTAssertNil(ChartFit.correct(samples: ChartSampler.sample(image: render(g), grid: cut, clipLevel: 0.98), validation: v, reference: P, model: .classicAfter2014, grid: cut, cameraKey: nil, sourcePhotoID: nil), "fără date suficiente nu se propune nicio corecție")
        let bad = render(g, tweak: { i, _, _, c in i >= 19 ? c.map { $0 * (i == 20 ? 1.9 : (i == 23 ? 0.5 : 1)) } : c }); v = ChartValidator.validate(ChartSampler.sample(image: bad, grid: g, clipLevel: 0.98), reference: P, thresholds: thr)
        XCTAssertGreaterThan(v.neutralLightingCV, 0.15); XCTAssertFalse(v.ok, "neutre neproporționale ⇒ iluminare neuniformă / nesigur")
    }
    func testFitRemovesSyntheticCameraErrorAndGeneralisesOffChartWithHonestLeaveOneOutMetric() {
        let P = ref(); let g = persp(); let img = render(g, scale: 0.5, noise: 0.004); let S = ChartSampler.sample(image: img, grid: g, clipLevel: 0.98); let v = ChartValidator.validate(S, reference: P)
        XCTAssertTrue(v.ok, v.message); let c = ChartFit.correct(samples: S, validation: v, reference: P, model: .classicAfter2014, grid: g, cameraKey: "TestCam", sourcePhotoID: 7)!
        XCTAssertGreaterThan(c.metrics.meanBefore, 5, "înainte: eroare mare"); XCTAssertLessThan(c.metrics.meanAfter, 1.5, "după (pe peticele folosite): \(c.metrics.meanAfter)"); XCTAssertLessThan(c.metrics.looMean, 2.0, "leave-one-out: \(c.metrics.looMean)")
        XCTAssertGreaterThanOrEqual(c.metrics.looMean, c.metrics.meanAfter * 0.8, "eroarea LOO nu poate fi sub cea pe petice folosite"); XCTAssertEqual(c.exposureOffsetEV, log2(1.0), accuracy: 3.0)
        // off-chart: culori NEfolosite la potrivire, trecute prin aceeași „cameră”, apoi corecția → față de adevăr
        var st: UInt32 = 5; func r() -> Double { st = st &* 1664525 &+ 1013904223; return Double(st >> 8) / 16777216 }
        var worst = 0.0, sum = 0.0; let n = 200; let sc = 0.5
        for _ in 0..<n { let t = [0.02 + 0.6 * r(), 0.02 + 0.6 * r(), 0.02 + 0.6 * r()]; let m = measured(t, scale: sc); let cor = ChartFit.apply(c.matrix, m).map { $0 * ChartFit.fitScaleForTest(c, sc) }
            let de = DeltaE.ciede2000(ChartFit.lab(cor), ChartFit.lab(t)); worst = max(worst, de); sum += de }
        XCTAssertLessThan(sum / Double(n), 2.5, "ΔE00 medie pe culori din afara chartului: \(sum / Double(n))"); print("CHART-SYN before \(c.metrics.meanBefore) after \(c.metrics.meanAfter) loo \(c.metrics.looMean) offchart mean \(sum / Double(n)) max \(worst)")
    }
    func testCorrectionIsAppliedAtPipelineInputBeforeLinearToolsAndIsTechnicalNotCreative() throws {
        let m: [Double] = [1.1, -0.05, -0.05, 0.02, 0.95, 0.03, 0.0, -0.1, 1.1]; let corr = ChartCorrection(model: .classicAfter2014, matrix: m, exposureOffsetEV: 0, usedPatches: [1], excluded: [], metrics: ChartMetrics(meanBefore: 5, maxBefore: 9, meanAfter: 1, maxAfter: 2, looMean: 1.5, looMax: 3, patches: 20), cameraKey: nil, sourcePhotoID: nil, grid: ChartGrid(), provenance: "t")
        var a = AdjustmentSet(); a.exposure = 0.3; a.chart = corr; XCTAssertTrue(AdjustmentSet().isNeutral); a.exposure = 0; XCTAssertTrue(a.isNeutral, "corecția tehnică nu e reglaj creativ")
        var p = a.coreParams(estimate: nil, inputIsLinear: true); p.drt = 0; var q = AdjustmentSet().coreParams(estimate: nil, inputIsLinear: true); q.drt = 0
        let v: [Float] = [0.3, 0.2, 0.1]; let ex: [Float] = (0..<3).map { (r: Int) -> Float in let a: Double = m[r * 3] * 0.3; let b: Double = m[r * 3 + 1] * 0.2; let c: Double = m[r * 3 + 2] * 0.1; return Float(a + b + c) }; var o1: [Float] = [0, 0, 0], o2: [Float] = [0, 0, 0]
        pc_process_pixel_c(&p, v, &o1); pc_process_pixel_c(&q, ex, &o2); for k in 0..<3 { XCTAssertEqual(o1[k], o2[k], accuracy: 1e-5, "C aplicat la intrare = intrare pre-multiplicată") }
        var e = a; e.exposure = 1; var pe = e.coreParams(estimate: nil, inputIsLinear: true); pe.drt = 0; var o3: [Float] = [0, 0, 0]; pc_process_pixel_c(&pe, v, &o3); var q1 = AdjustmentSet(); q1.exposure = 1; var qe = q1.coreParams(estimate: nil, inputIsLinear: true); qe.drt = 0; var o4: [Float] = [0, 0, 0]; pc_process_pixel_c(&qe, ex, &o4); for k in 0..<3 { XCTAssertEqual(o3[k], o4[k], accuracy: 1e-5, "înaintea expunerii (instrumente liniare)") }
        let r = try JSONDecoder().decode(AdjustmentSet.self, from: JSONEncoder().encode(a)); XCTAssertEqual(r.chart?.matrix, m); XCTAssertNil(try JSONDecoder().decode(AdjustmentSet.self, from: Data(#"{"exposure":0.1}"#.utf8)).chart)
        XCTAssertTrue(a.fingerprint.contains("chart:")); XCTAssertFalse(AdjustmentSet().fingerprint.contains("chart:")); var d = a; d.disabledModules = ["chart"]; XCTAssertNil(d.effective.chart, "dezactivare"); XCTAssertNotNil(d.chart, "valorile se păstrează")
        a.chart!.matrix = [1, 0, 0, 0, 1, 0, 0, 0, 1]; XCTAssertFalse(a.fingerprint.contains("chart:"), "identitate = nicio schimbare"); XCTAssertEqual(AdjustmentSet().baseForCompare.chart == nil, true)
    }
}
extension ChartFit { static func fitScaleForTest(_ c: ChartCorrection, _ sc: Double) -> Double { pow(2, c.exposureOffsetEV) } }
