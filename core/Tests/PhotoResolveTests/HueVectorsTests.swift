import XCTest
import CPhotoCore
import PhotoResolve

/// Hue/HSV (215) + Hue Vectors (230): paritate cu applyHue215/applyHue230 (HueGolden.swift) pe coduri incl. negative, >1, saturate, aproape-gri — prin traseul de produs (stage 2, instrumente log).
final class HueVectorsTests: XCTestCase {
    func render(_ p: [Double], _ inp: [Float], vectors: Bool = true, family: Int32 = 0) -> [Float] {
        var q = pc_params(); pc_default_params(&q); q.family = family; q.inputIsLinear = 0; q.drt = 0; q.stage = 2
        q.hueRotate = p[0]; q.hsvSat = p[1]; q.hsvVal = p[2]; q.hvWidth = p[3]
        if vectors { withUnsafeMutableBytes(of: &q.hv) { r in for i in 0..<18 { r.storeBytes(of: p[4 + i], toByteOffset: i * 8, as: Double.self) } } }
        var out = [Float](repeating: 0, count: inp.count); XCTAssertEqual(pc_process_image(&q, inp, &out, Int32(inp.count / 3), 1, 1), 0); return out
    }
    func inputs() -> [Float] {
        var st: UInt32 = 2024; func r() -> Double { st = st &* 1664525 &+ 1013904223; return Double(st >> 8) / 16777216.0 }
        var v = [Float](); for i in 0..<500 { let m = i % 10; var c = [0.0, 0.0, 0.0]
            if m == 0 { let g = -0.2 + 1.6 * r(); c = [g, g, g] } else if m == 1 { c = [-0.1 + 0.2 * r(), r(), 1.2 + r()] } else if m == 2 { c = [2.0 + 3.0 * r(), 0.1 * r(), 0.05 * r()] } else { c = [-0.1 + 1.3 * r(), -0.1 + 1.3 * r(), -0.1 + 1.3 * r()] }
            v += c.map { Float($0) } }
        return v
    }
    func testMatchesStyleReference() {
        let inp = inputs(); var worst = 0.0
        for (si, r) in StyleParityGoldenHue.rows.enumerated() {
            let out = render(r.p, inp); XCTAssertEqual(out.count, r.o.count)
            for i in 0..<out.count { let d = abs(Double(out[i]) - r.o[i]) / max(1.0, abs(r.o[i])); if d > worst { worst = d }; if d > 1e-3 { XCTFail("set \(si) i \(i): \(out[i]) vs \(r.o[i])"); return } }
        }
        print("HUE-PARITY worst rel diff \(worst)")
    }
    func testNeutralVectorsAreBitIdenticalAndGraysUntouched() {
        let inp = inputs(); let neutral = [0.0, 1, 1, 60] + [Double](repeating: 0, count: 0)
        var p = neutral; for _ in 0..<6 { p += [0, 1, 1] }; XCTAssertEqual(render(p, inp), render(p, inp, vectors: false))
        var q = p; q[4] = 40; q[5] = 2                                   // doar roșu modificat: griurile și negrul rămân neatinse
        let gray: [Float] = [0.3, 0.3, 0.3, 0.0, 0.0, 0.0, -0.1, -0.1, -0.1]; XCTAssertEqual(render(q, gray), gray)
    }
}

final class HueModelAndAnalysisTests: XCTestCase {
    func testHueVectorsModelNeutralResetFingerprintAndCoreParams() throws {
        var t = ToolSet(); XCTAssertTrue(t.isNeutral); XCTAssertTrue(t.isNeutral(.hueVectors))
        t.hv[3] = 20; t.hv[4] = 1.4; t.hvWidth = 80; XCTAssertFalse(t.isNeutral(.hueVectors)); XCTAssertTrue(t.fingerprint.contains("hv:"))
        let d = try JSONDecoder().decode(ToolSet.self, from: JSONEncoder().encode(t)); XCTAssertEqual(d, t)
        var p = pc_params(); pc_default_params(&p); t.apply(to: &p); XCTAssertEqual(p.hvWidth, 80); XCTAssertEqual(withUnsafeBytes(of: p.hv) { $0.load(fromByteOffset: 3 * 8, as: Double.self) }, 20)
        t.reset(.hueVectors); XCTAssertTrue(t.isNeutral(.hueVectors)); XCTAssertEqual(ToolSet.Group.hueVectors.module, "huevectors")
        var a = AdjustmentSet(); a.tools.hv[0] = 10; a.disabledModules.insert("huevectors"); XCTAssertEqual(a.tools.hv[0], 10)   // dezactivat: valorile rămân (efectul se anulează în traseu prin modul)
        let old = try JSONDecoder().decode(ToolSet.self, from: Data("{\"hueRotate\":5}".utf8)); XCTAssertTrue(old.isNeutral(.hueVectors)); XCTAssertEqual(old.hueRotate, 5)
    }
    func testSaturationMetricsAreDistinctAndDeclared() {
        let red: [Float] = [0.2, 0.0, 0.0], gray: [Float] = [0.5, 0.5, 0.5], bright: [Float] = [1.0, 0.2, 0.2]
        let hsvDark = PhotoAnalysis.saturationHSV(finalRGB: red, width: 1, height: 1), hsvGray = PhotoAnalysis.saturationHSV(finalRGB: gray, width: 1, height: 1)
        XCTAssertEqual(hsvDark.legend.last?.fraction, 1)                                   // roșu închis: S = 1 (foarte intens în HSV)
        XCTAssertEqual(hsvGray.legend.first?.fraction, 1)                                  // gri: neutru
        let abs = PhotoAnalysis.saturation(finalRGB: red, width: 1, height: 1), rel = PhotoAnalysis.chromaRelative(finalRGB: red, width: 1, height: 1)
        XCTAssertNotEqual(abs.legend.map { $0.fraction }, rel.legend.map { $0.fraction })    // metrici diferite, nu o singură «saturație»
        let dark = PhotoAnalysis.chromaRelative(finalRGB: [0.001, 0.0, 0.0], width: 1, height: 1); XCTAssertEqual(dark.rgb8, [25, 25, 25])   // exclus (L < 0,05)
        _ = bright; XCTAssertTrue(AnalysisMode.saturation.domain.contains("ABSOLUTĂ") && AnalysisMode.saturationHSV.domain.contains("HSV") && AnalysisMode.chromaRel.domain.contains("C/L"))
    }
}

final class AdjustmentSyncTests: XCTestCase {
    func testPasteReplacesOnlyChosenCategoriesAndKeepsTargetSpecificData() {
        var src = AdjustmentSet(); src.exposure = 1; src.temperature = 40; src.tools.wheels[0] = 0.2; src.tools.hv[0] = 15; src.tools.colorOn = true; src.look.on = true; src.geometry.angle = 5; src.effects.distortion = 20; src.effects.film3.on = true; src.effects.grainAmount = 30
        var tgt = AdjustmentSet(); tgt.geometry.angle = -2; tgt.effects.distortion = -10; tgt.chart = nil; tgt.contrast = 1.3
        let basic = src.pasting([.basic], onto: tgt); XCTAssertEqual(basic.exposure, 1); XCTAssertEqual(basic.temperature, 40); XCTAssertEqual(basic.tools.wheels[0], 0)   // tonurile avansate nu intră în «Bază»
        XCTAssertEqual(basic.geometry.angle, -2); XCTAssertEqual(basic.effects.distortion, -10); XCTAssertFalse(basic.look.on)                                         // geometria și lentila țintei rămân
        let adv = src.pasting([.toneColour, .selective], onto: tgt); XCTAssertEqual(adv.tools.wheels[0], 0.2); XCTAssertEqual(adv.tools.hv[0], 15); XCTAssertTrue(adv.tools.colorOn); XCTAssertEqual(adv.exposure, 0); XCTAssertEqual(adv.contrast, 1.3)
        let eff = src.pasting([.effects], onto: tgt); XCTAssertEqual(eff.effects.grainAmount, 30); XCTAssertEqual(eff.effects.distortion, -10); XCTAssertFalse(eff.effects.film3.on)                  // lentila rămâne, filmul nu se copiază cu «Efecte»
        let film = src.pasting([.filmCinema, .look], onto: tgt); XCTAssertTrue(film.effects.film3.on); XCTAssertTrue(film.look.on)
        let all = src.pasting(Set(AdjustmentCategory.allCases), onto: tgt); XCTAssertEqual(all.geometry.angle, 5); XCTAssertEqual(all.effects.distortion, 20)
        XCTAssertFalse(AdjustmentCategory.geometry.defaultOn || AdjustmentCategory.locals.defaultOn || AdjustmentCategory.chart.defaultOn || AdjustmentCategory.lens.defaultOn)
        XCTAssertEqual(src.pasting([], onto: tgt), tgt)
    }
}
