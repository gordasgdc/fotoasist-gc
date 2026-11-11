import XCTest
import CPhotoCore

/// Paritate cu referința host STYLE V3 pe lanțul COMPLET: Exposure + Balance (negru, mijloc+gardă, Tonal Balance, Printer Lights+Master, Channel Mix+Keep, Mix) → Tone (LGG, Wheels, CDL, Contrast+Pivot, Mix) → Saturation + Hue/HSV (Mix).
/// Vectorii: StyleParityGolden2.swift (generat din referințele STYLE; STYLE nu e necesar la rulare).
final class StyleParityV2Tests: XCTestCase {
    static func params(_ v: [Double], family: Int32) -> pc_params {
        var p = pc_params(); pc_default_params(&p); p.family = family; p.inputIsLinear = 0; p.drt = 0
        p.exposure = v[0]; p.black = v[1]; p.shadows = v[2]; p.midtones = v[3]; p.highlights = v[4]; p.shadowsTemp = v[5]; p.shadowsTint = v[6]; p.highlightsTemp = v[7]; p.highlightsTint = v[8]
        p.temperature = v[9]; p.tint = v[10]; p.printerMaster = v[11]; p.printerR = v[12]; p.printerG = v[13]; p.printerB = v[14]
        withUnsafeMutableBytes(of: &p.cm) { b in for i in 0..<9 { b.storeBytes(of: v[15 + i], toByteOffset: i * 8, as: Double.self) } }
        p.cmKeepNeutrals = v[24] != 0 ? 1 : 0; p.ebMix = v[25]; p.lift = v[26]; p.gamma = v[27]; p.gain = v[28]; p.shadowLimit = v[29]; p.highlightStart = v[30]
        withUnsafeMutableBytes(of: &p.wheels) { b in for i in 0..<12 { b.storeBytes(of: v[31 + i], toByteOffset: i * 8, as: Double.self) } }
        withUnsafeMutableBytes(of: &p.slope) { b in for i in 0..<3 { b.storeBytes(of: v[43 + i], toByteOffset: i * 8, as: Double.self) } }
        withUnsafeMutableBytes(of: &p.offset) { b in for i in 0..<3 { b.storeBytes(of: v[46 + i], toByteOffset: i * 8, as: Double.self) } }
        withUnsafeMutableBytes(of: &p.power) { b in for i in 0..<3 { b.storeBytes(of: v[49 + i], toByteOffset: i * 8, as: Double.self) } }
        p.cdlSat = v[52]; p.contrast = v[53]; p.pivot = v[54]; p.toneMix = v[55]; p.saturation = v[56]; p.hueRotate = v[57]; p.hsvSat = v[58]; p.hsvVal = v[59]; p.shMix = v[60]
        return p
    }
    func testFullChainMatchesAuthoritativeReferenceOnAllFamilies() {
        var worst = 0.0, worstRow = "", n = 0
        for (fam, rows) in StyleParityGolden2.rows.enumerated() {
            for (k, r) in rows.enumerated() {
                var p = Self.params(r.p, family: Int32(fam)); let inp: [Float] = r.i.map { Float($0) }; var out: [Float] = [0, 0, 0]
                pc_process_pixel_c(&p, inp, &out); n += 1
                for c in 0..<3 { if r.o[c].isNaN { XCTAssertTrue(out[c].isNaN, "NaN așteptat fam \(fam) rând \(k)"); continue }; let e = abs(Double(out[c]) - r.o[c]); if e > worst { worst = e; worstRow = "fam \(fam) rând \(k) canal \(c): \(out[c]) vs \(r.o[c])" } }
            }
        }
        XCTAssertGreaterThan(n, 1000); XCTAssertLessThan(worst, 3e-5, "eroare maximă \(worst) la \(worstRow)")
        print("PARITY2 rânduri \(n), eroare maximă \(worst)")
    }

    func testHighlightsGamutMatchesAuthoritativeReference() {
        var worst = 0.0, n = 0, worstRow = ""
        for (fam, rows) in StyleParityGoldenHG.rows.enumerated() { for (k, r) in rows.enumerated() {
            var p = pc_params(); pc_default_params(&p); p.family = Int32(fam); p.inputIsLinear = 0; p.drt = 0
            p.hgPathAmount = r.p[0]; p.hgPathOnset = r.p[1]; p.hgGamutAmount = r.p[2]; p.hgGamutThreshold = r.p[3]; p.hgHlAmount = r.p[4]; p.hgHlKnee = r.p[5]; p.hgMix = r.p[6]
            var out: [Float] = [0, 0, 0]; let inp = r.i.map { Float($0) }; pc_process_pixel_c(&p, inp, &out); n += 1
            for c in 0..<3 { if r.o[c].isNaN { XCTAssertTrue(out[c].isNaN); continue }; let e = abs(Double(out[c]) - r.o[c]); if e > worst { worst = e; worstRow = "fam \(fam) rând \(k) canal \(c)" } } } }
        XCTAssertGreaterThan(n, 400); XCTAssertLessThan(worst, 3e-5, "eroare maximă \(worst) la \(worstRow)"); print("PARITYHG rânduri \(n), eroare maximă \(worst)")
    }
}
