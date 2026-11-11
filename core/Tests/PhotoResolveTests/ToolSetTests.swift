import XCTest
import CPhotoCore
@testable import PhotoResolve

/// Maparea AdjustmentSet.tools → nucleu: aceleași rânduri de aur ca StyleParityV2Tests, dar construite prin API-ul Swift al produsului.
final class ToolSetTests: XCTestCase {
    func adj(_ v: [Double], fam: WorkingFamily) -> AdjustmentSet {
        var a = AdjustmentSet.neutral(fam); a.exposure = v[0]; a.shadows = v[2]; a.highlights = v[4]; a.temperature = v[9]; a.tint = v[10]; a.contrast = v[53]; a.saturation = v[56]
        var t = ToolSet(); t.black = v[1]; t.midtones = v[3]; t.shadowsTemp = v[5]; t.shadowsTint = v[6]; t.highlightsTemp = v[7]; t.highlightsTint = v[8]; t.printerMaster = v[11]; t.printerR = v[12]; t.printerG = v[13]; t.printerB = v[14]
        t.cm = Array(v[15..<24]); t.cmKeep = v[24] != 0; t.ebMix = v[25]; t.lift = v[26]; t.gamma = v[27]; t.gain = v[28]; t.shadowLimit = v[29]; t.highlightStart = v[30]; t.wheels = Array(v[31..<43])
        t.slope = Array(v[43..<46]); t.offset = Array(v[46..<49]); t.power = Array(v[49..<52]); t.cdlSat = v[52]; t.pivot = v[54]; t.toneMix = v[55]; t.hueRotate = v[57]; t.hsvSat = v[58]; t.hsvVal = v[59]; t.shMix = v[60]
        a.tools = t; return a
    }
    func testSwiftProductAPIReproducesAuthoritativeVectors() {
        let fams: [WorkingFamily] = [.dwg, .acesAP1, .awg3, .awg4]; var worst = 0.0, n = 0
        for (fi, rows) in StyleParityGolden2Mirror.rows.enumerated() { for r in rows.prefix(240) where !r.o.contains(where: { $0.isNaN }) {
            var p = adj(r.p, fam: fams[fi]).coreParams(estimate: nil, inputIsLinear: false); p.drt = 0
            var out: [Float] = [0, 0, 0]; let inp = r.i.map { Float($0) }; pc_process_pixel_c(&p, inp, &out); n += 1; for c in 0..<3 { worst = max(worst, abs(Double(out[c]) - r.o[c])) } } }
        XCTAssertGreaterThan(n, 400); XCTAssertLessThan(worst, 3e-5, "eroare maximă \(worst)")
    }
    func testNeutralFingerprintLegacyJSONModulesAndCompareBase() throws {
        let a = AdjustmentSet(); XCTAssertTrue(a.tools.isNeutral); XCTAssertFalse(a.fingerprint.contains("tl:"))
        let legacy = try JSONDecoder().decode(AdjustmentSet.self, from: Data(#"{"exposure":0.2}"#.utf8)); XCTAssertTrue(legacy.tools.isNeutral)
        var b = a; b.tools.lift = 0.05; b.tools.hueRotate = 20; b.tools.printerR = 3; b.tools.cm[1] = 0.2
        XCTAssertFalse(b.isNeutral); XCTAssertTrue(b.fingerprint.contains("tl:")); XCTAssertEqual(try JSONDecoder().decode(AdjustmentSet.self, from: JSONEncoder().encode(b)).tools, b.tools)
        b.disabledModules = ["wheels"]; XCTAssertEqual(b.effective.tools.lift, 0); XCTAssertEqual(b.effective.tools.hueRotate, 20, "alt modul neatins"); XCTAssertEqual(b.tools.lift, 0.05, "valorile se păstrează")
        b.disabledModules = ["printer", "colour"]; XCTAssertEqual(b.effective.tools.printerR, 0); XCTAssertEqual(b.effective.tools.hueRotate, 0); XCTAssertEqual(b.effective.tools.lift, 0.05)
        XCTAssertTrue(b.baseForCompare.tools.isNeutral)
        var c = a; c.tools.black = 0.02; for g in ToolSet.Group.allCases { var d = c; d.tools.reset(g); XCTAssertTrue(d.tools.isNeutral(g)) }
    }

    func testDRTProfileIsAnOutputChoiceNotACreativeAdjustment() throws {
        var a = AdjustmentSet(); XCTAssertEqual(a.drtProfile, 0); XCTAssertFalse(a.fingerprint.contains("drt:"))
        a.drtProfile = 1; XCTAssertTrue(a.isNeutral, "profilul DRT nu e reglaj creativ"); XCTAssertTrue(a.fingerprint.contains("drt:1")); XCTAssertEqual(a.baseForCompare.drtProfile, 1, "Bază compară aceeași redare")
        if Edition.full { XCTAssertEqual(a.coreParams(estimate: nil, inputIsLinear: true).drtProfile, 1) }   // profilurile aparțin GDC DRT (ediția completă)
        let r = try JSONDecoder().decode(AdjustmentSet.self, from: JSONEncoder().encode(a)); XCTAssertEqual(r.drtProfile, 1)
        XCTAssertEqual(try JSONDecoder().decode(AdjustmentSet.self, from: Data(#"{"exposure":0.1}"#.utf8)).drtProfile, 0)
        XCTAssertEqual(try JSONDecoder().decode(AdjustmentSet.self, from: Data(#"{"drtProfile":9}"#.utf8)).drtProfile, 2, "valoare invalidă limitată")
    }
}
