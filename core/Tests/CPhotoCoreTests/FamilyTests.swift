import XCTest
import CPhotoCore

/// Familii de lucru: transformările tehnice (gamut, curbă, adaptor DRT) separate de diferențele creative. Neutralii, expunerea liniară, valorile supraunitare și ieșirea DRT pe rampe, pentru fiecare familie.
final class FamilyTests: XCTestCase {
    func loadDRT() throws {
        guard let r = ProcessInfo.processInfo.environment["GDC_PA_ROOT"], let d = try? Data(contentsOf: URL(fileURLWithPath: r + "/data/drt/drt_1.bin")) else { throw XCTSkip("fără drt_1.bin") }
        var err = [CChar](repeating: 0, count: 128); XCTAssertEqual(d.withUnsafeBytes { pc_drt_load($0.bindMemory(to: UInt8.self).baseAddress, UInt(d.count), &err, 128) }, 0)
    }
    func params(_ f: Int32, drt: Int32 = 0) -> pc_params { var p = pc_params(); pc_default_params(&p); p.family = f; p.drt = drt; p.drtOutput = 2; return p }
    func run(_ p: pc_params, _ c: [Float]) -> [Float] { var q = p; var o = [Float](repeating: 0, count: 3); c.withUnsafeBufferPointer { pc_process_pixel_c(&q, $0.baseAddress, &o) }; return o }

    func testFamiliesAreTheFourStyleProfilesWithDWGFirst() {
        XCTAssertEqual(pc_family_count(), 4)
        XCTAssertEqual((0..<4).map { String(cString: pc_family_id(Int32($0))) }, ["dwg-davinci-intermediate", "ap1-acescct", "awg3-logc3-ei800", "awg4-logc4"])
        XCTAssertEqual((0..<4).map { String(cString: pc_family_label(Int32($0))) }, ["DaVinci WG / Intermediate", "ACES AP1 / ACEScct", "ARRI AWG3 / LogC3 EI800", "ARRI AWG4 / LogC4"])
        var p = pc_params(); pc_default_params(&p); XCTAssertEqual(p.family, 0)                       // implicit = DWG, varianta de revenire
    }
    func testTransferRoundTripAndMiddleGreyPerFamily() {
        for f in Int32(0)..<4 {
            for l in [-0.02, 0.0, 0.001, 0.01, 0.18, 1, 8, 60, 100] { XCTAssertEqual(pc_family_decode(f, pc_family_encode(f, l)), l, accuracy: max(1e-9, abs(l) * 1e-9), "familia \(f) lin \(l)") }
            let g = pc_family_encode(f, 0.18); XCTAssertTrue(g > 0.2 && g < 0.5, "18% gri codat plauzibil: \(g)")
        }
        XCTAssertEqual(pc_family_encode(1, 0.18), 0.4135884, accuracy: 1e-6); XCTAssertEqual(pc_family_encode(2, 0.18), 0.3910068, accuracy: 1e-6); XCTAssertEqual(pc_family_encode(3, 0.18), 0.2784, accuracy: 1e-3)   // valorile publicate (ACEScct, LogC3 EI800, LogC4)
    }
    func testLinearExposureDoublesLightOnEveryFamilyIncludingOverUnityAndNeutralsStayNeutral() {
        for f in Int32(0)..<4 {
            var p = params(f); p.exposure = 1
            for l in [0.002, 0.18, 1, 6, 40] {
                let c = Float(pc_family_encode(f, l)); let o = run(p, [c, c, c]).map { pc_family_decode(f, Double($0)) }
                for k in 0..<3 { XCTAssertEqual(o[k], 2 * l, accuracy: 2 * l * 2e-5, "familia \(f) l=\(l)") }   // +1 stop = ×2 în liniar, canale egale (neutru rămâne neutru)
            }
        }
    }
    func testNeutralRampGivesTheSameDisplayOutputOnEveryFamilyAndIsMonotoneOverUnity() throws {
        try loadDRT(); var ref: [Float] = []
        for f in Int32(0)..<4 {
            var out: [Float] = []; var prev: Float = -1
            for e in stride(from: -9.0, through: 9.0, by: 0.25) {
                let l = 0.18 * pow(2.0, e); let c = Float(pc_family_encode(f, l)); let o = run(params(f, drt: 2), [c, c, c]); out.append(o[1])
                XCTAssertGreaterThanOrEqual(o[1], prev - 1e-6, "familia \(f) monotonie la \(e) stopuri"); prev = o[1]; XCTAssertTrue(o.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
            }
            if f == 0 { ref = out } else { var worst: Float = 0; for k in 0..<out.count { worst = max(worst, abs(out[k] - ref[k])) }; XCTAssertLessThan(worst, 3e-5, "familia \(f) vs DWG pe rampa neutră") }   // conversie TEHNICĂ: același neutru ⇒ același afișaj
        }
    }
    func testWhitePointAdaptationKeepsGreyNeutralForAP1D60AndAWG() {
        for f in Int32(0)..<4 { var p = params(f); p.temperature = 0; for l in [0.05, 0.18, 2.0] { let c = Float(pc_family_encode(f, l)); let o = run(p, [c, c, c]); XCTAssertEqual(o[0], o[1], accuracy: 1e-7); XCTAssertEqual(o[1], o[2], accuracy: 1e-7) } }
        var q = [Float](repeating: 0.5, count: 3); pc_convert_dwg_to_family(1, [0.18, 0.18, 0.18], &q, 1)                       // gri DWG → AP1: rămâne gri (alb D65 → D60 prin Bradford)
        XCTAssertEqual(q[0], q[1], accuracy: 1e-5); XCTAssertEqual(q[1], q[2], accuracy: 1e-5); XCTAssertEqual(q[1], 0.18, accuracy: 2e-3)
    }
    func testDwgLinearInputModeConvertsIntoTheFamilyGamutAndEqualsEncodingByHand() {
        for f in Int32(0)..<4 {
            var p = params(f); p.inputIsLinear = 2; p.stage = 1                                                                // intrare DWG liniar → etapa liniară ⇒ cod log al familiei
            let dwg: [Float] = [0.30, 0.12, 0.05]; var fam = [Float](repeating: 0, count: 3); pc_convert_dwg_to_family(f, dwg, &fam, 1)
            let o = run(p, dwg); for k in 0..<3 { XCTAssertEqual(Double(o[k]), pc_family_encode(f, Double(fam[k])), accuracy: 2e-6) }
        }
    }
    func testDefaultFamilyIsBitIdenticalToTheDWGPath() {
        let c: [Float] = [0.31, 0.4, 0.22]; var a = params(0); a.contrast = 1.2; a.saturation = 1.1; a.temperature = 20; a.exposure = 0.5; var b = a; b.family = 0
        XCTAssertEqual(run(a, c), run(b, c))
    }
}
