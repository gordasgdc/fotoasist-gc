import XCTest
import CPhotoCore

/// Verificări ale nucleului fotografic propriu (matematica): identitate, domeniu (negative / supraunitare / neutre), monotonie, continuitate, curba neutră a DRT-ului.
final class PhotoCoreTests: XCTestCase {
    func params() -> pc_params { var p = pc_params(); pc_default_params(&p); return p }
    func run(_ p: pc_params, _ rgb: [Float]) -> [Float] { var q = p; var o = [Float](repeating: 0, count: 3); rgb.withUnsafeBufferPointer { i in pc_process_pixel_c(&q, i.baseAddress, &o) }; return o }

    func testNeutralParamsWithoutDRTAreIdentityOnDICodes() {
        var p = params(); p.drt = 0
        for c in stride(from: -0.2 as Float, through: 0.98, by: 0.013) { let o = run(p, [c, c * 0.5 + 0.1, c * 0.9]); XCTAssertEqual(o[0], c, accuracy: 2e-6); XCTAssertEqual(o[1], c * 0.5 + 0.1, accuracy: 2e-6); XCTAssertEqual(o[2], c * 0.9, accuracy: 2e-6) }
    }
    func testDIRoundTripAndContinuityAtTheLinearCut() {
        for l in [-0.5, -0.01, 0, 1e-4, 0.00262409, 0.003, 0.18, 1, 8, 32, 64] { XCTAssertEqual(pc_di_decode(pc_di_encode(l)), l, accuracy: max(1e-9, abs(l) * 1e-9), "lin \(l)") }
        let e = 1e-7; XCTAssertEqual(pc_di_encode(0.00262409 - e), pc_di_encode(0.00262409 + e), accuracy: 2e-5)      // continuitate la îmbinare (constantele publicate)
    }
    func testExposureDoublesLinearLightAndKeepsOverUnityAndNegatives() {
        var p = params(); p.drt = 0; p.exposure = 1
        for l in [-0.05, 0.01, 0.18, 1, 6, 30] { let o = run(p, [Float(pc_di_encode(l)), Float(pc_di_encode(l)), Float(pc_di_encode(l))]); XCTAssertEqual(pc_di_decode(Double(o[1])), 2 * l, accuracy: abs(2 * l) * 3e-5 + 2e-7, "lin \(l)") }
    }
    func testLinearInputPathMatchesDIPath() {
        var a = params(); a.drt = 0; a.exposure = 0.7; var b = a; b.inputIsLinear = 1
        let lin: [Double] = [0.2, 0.05, 3.0]; let oa = run(a, lin.map { Float(pc_di_encode($0)) }); let ob = run(b, lin.map { Float($0) })
        for i in 0..<3 { XCTAssertEqual(oa[i], ob[i], accuracy: 3e-6) }
    }
    func testBalanceIsNeutralPreservingAndDirectionIsDocumented() {
        var m = [Double](repeating: 0, count: 9); pc_balance_matrix(0, 0, &m); XCTAssertEqual(m, [1, 0, 0, 0, 1, 0, 0, 0, 1])
        pc_balance_matrix(40, 0, &m)   // pozitiv = mai cald: roșu ↑, albastru ↓ pe gri
        let grey = [m[0] + m[1] + m[2], m[3] + m[4] + m[5], m[6] + m[7] + m[8]]; XCTAssertGreaterThan(grey[0], 1); XCTAssertLessThan(grey[2], 1)
        pc_balance_matrix(0, 0.02, &m); let g2 = [m[0] + m[1] + m[2], m[3] + m[4] + m[5], m[6] + m[7] + m[8]]; XCTAssertLessThan(g2[1], (g2[0] + g2[2]) / 2)   // tentă pozitivă = mai magenta (verde ↓)
        pc_balance_matrix(-60, 0.03, &m); XCTAssertTrue(m.allSatisfy { $0.isFinite })
    }
    func testShadowsHighlightsActOnlyInTheirWindowsAndKeepHue() {
        var p = params(); p.drt = 0; p.shadows = 1
        let lowIn = Float(pc_di_encode(0.002)), midIn = Float(pc_di_encode(0.18)), hiIn = Float(pc_di_encode(4))
        let lo = pc_di_decode(Double(run(p, [lowIn, lowIn, lowIn])[1])), mid = pc_di_decode(Double(run(p, [midIn, midIn, midIn])[1])), hi = pc_di_decode(Double(run(p, [hiIn, hiIn, hiIn])[1]))
        XCTAssertEqual(lo / 0.002, 2, accuracy: 0.05); XCTAssertEqual(mid / 0.18, 1, accuracy: 0.25); XCTAssertEqual(hi / 4, 1, accuracy: 1e-4)   // umbre ×2; mijloc aproape neatins; lumini neatinse
        let o = run(p, [Float(pc_di_encode(0.01)), Float(pc_di_encode(0.02)), Float(pc_di_encode(0.005))]); let r = pc_di_decode(Double(o[0])) / 0.01, g = pc_di_decode(Double(o[1])) / 0.02, b = pc_di_decode(Double(o[2])) / 0.005
        XCTAssertEqual(r, g, accuracy: 1e-4); XCTAssertEqual(g, b, accuracy: 1e-4)         // același câștig pe canale = nuanța păstrată
    }
    func testContrastPivotIsAFixedPointAndSaturationZeroGivesNeutral() {
        var p = params(); p.drt = 0; p.contrast = 1.5; let pivot = Float(pc_di_encode(0.18)); let o = run(p, [pivot, pivot, pivot]); XCTAssertEqual(o[1], pivot, accuracy: 2e-6)
        var s = params(); s.drt = 0; s.saturation = 0; let g = run(s, [0.3, 0.5, 0.2]); XCTAssertEqual(g[0], g[1], accuracy: 2e-6); XCTAssertEqual(g[1], g[2], accuracy: 2e-6)
        var s1 = s; s1.saturation = 1; let id = run(s1, [0.3, 0.5, 0.2]); XCTAssertEqual(id[0], 0.3, accuracy: 2e-6)
    }
    func testDRTNeutralAxisFollowsTheFittedCurveAndIsMonotonicAndBounded() {
        let p = params(); var prev: Float = -1
        for l in stride(from: -3.0, through: 6.0, by: 0.01) {            // 2^−3 … 2^6 în stopuri față de 1.0
            let x = pow(2, l); let c = Float(pc_di_encode(x)); let o = run(p, [c, c, c]); XCTAssertGreaterThanOrEqual(o[1], prev - 1e-7); prev = o[1]; XCTAssertTrue(o[1] >= 0 && o[1] <= 1)
            XCTAssertEqual(o[0], o[1], accuracy: 2e-5); XCTAssertEqual(o[1], o[2], accuracy: 2e-5)   // axa neutră rămâne neutră
        }
        // ținte măsurate pe răspunsul neutru al DRT-ului STYLE existent (cod sRGB): toleranță = max. eroare a ajustării (0.0128) + margine
        let targets: [(Double, Float)] = [(0.18, 0.3537), (1.0, 0.8109), (1.99, 0.9039), (4.02, 0.9551), (7.99, 0.9801), (16.09, 0.9929), (32, 0.999)]
        for (x, t) in targets { let c = Float(pc_di_encode(x)); XCTAssertEqual(run(p, [c, c, c])[1], t, accuracy: 0.03, "scena \(x)") }
    }
    func testDRTHandlesNegativesOverUnityAndNonFinite() {
        let p = params()
        for v in [[-0.3, 0.2, 0.1], [0.9, -0.5, 0.5], [-1, -1, -1], [50, 0.001, -0.02], [1e6, 1e6, 1e6], [Float.nan, 0.5, Float.infinity], [0, 0, 0], [-0.2, -0.2, -0.2]] as [[Float]] {
            let o = run(p, v); XCTAssertTrue(o.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, "\(v) → \(o)")
        }
        XCTAssertEqual(run(p, [-0.2, -0.2, -0.2]), [0, 0, 0])    // codul DI negativ = lumină negativă → negru
    }
    func testImageAPIMatchesPixelAPIAndIsThreadIndependent() {
        var p = params(); p.exposure = 0.4; p.contrast = 1.2; p.saturation = 1.1; p.temperature = 15
        let w = 37, h = 23; var img = [Float](); for i in 0..<(w * h * 3) { img.append(Float((i * 7919) % 1000) / 1000 * 0.9 - 0.05) }
        var o1 = [Float](repeating: 0, count: img.count), o8 = o1; _ = pc_process_image(&p, img, &o1, Int32(w), Int32(h), 1); _ = pc_process_image(&p, img, &o8, Int32(w), Int32(h), 8)
        XCTAssertEqual(o1, o8)
        for px in [0, 100, w * h - 1] { let o = run(p, Array(img[(3 * px)..<(3 * px + 3)])); XCTAssertEqual(Array(o1[(3 * px)..<(3 * px + 3)]), o) }
    }
}
