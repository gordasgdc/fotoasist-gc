import XCTest
@testable import PhotoRaw

final class RawDecoderTests: XCTestCase {
    private func sample(_ n: String) throws -> String {
        guard let d = ProcessInfo.processInfo.environment["GDC_PA_RAW_DIR"] else { throw XCTSkip("fără GDC_PA_RAW_DIR") }; return d + "/" + n }

    /// Decuparea implicită + orientarea dau dimensiunea DefaultCrop rotită; valorile sunt finite, negativele sub negru se păstrează, iar intermediarul EXR se recitește identic.
    func testSonyDefaultCropOrientedFiniteAndExrExact() throws {
        let d = try RawFile(path: try sample("A7306884.ARW")).decodeLinearDWG()
        XCTAssertEqual(d.report.appliedCrop, PixelRect(x: 12, y: 12, w: 6000, h: 4000))
        XCTAssertEqual(d.report.orientationFlip, 5)
        XCTAssertEqual(d.image.width, 4000); XCTAssertEqual(d.image.height, 6000)             // 90° față de zona decupată
        XCTAssertTrue(d.image.rgb.allSatisfy { $0.isFinite })
        XCTAssertGreaterThan(d.report.fracNegative, 0)                                          // zgomotul sub negru nu e tăiat
        XCTAssertEqual(d.report.whitePlan.black, 512); XCTAssertEqual(d.report.whitePlan.white, 16380)
        XCTAssertEqual(d.report.highlight, .clipSaturated); XCTAssertLessThan(d.image.rgb.max() ?? 99, 8)   // politica implicită păstrează valorile legitime > 1.0 (WB), taie doar saturația
        let base = ProcessInfo.processInfo.environment["GDC_PA_SCRATCH"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = base.appendingPathComponent("gdc_pa_dec_\(UUID().uuidString).exr"); defer { try? FileManager.default.removeItem(at: url) }
        let enc = d.image.diEncoded(); try FloatImageIO.writeEXR(enc, to: url)
        let back = try FloatImageIO.readEXR(url)
        XCTAssertEqual(back.width, enc.width); XCTAssertEqual(back.height, enc.height); XCTAssertEqual(back.rgb, enc.rgb)
    }

    /// Canon: nivelul de negru depinde de fișier (512 / 2048) și se citește DUPĂ unpack; albul = valoarea producătorului (nu maximul ADC).
    func testCanonBlackPerFileAndVendorWhite() throws {
        let a = try RawFile(path: try sample("IMG_0042.CR2")).decodeLinearDWG(DecodeOptions.activeAreaOnly).report
        XCTAssertEqual(a.whitePlan.black, 512); XCTAssertEqual(a.whitePlan.white, 14558); XCTAssertEqual(a.whitePlan.adcMax, 16383)
    }
    /// Fuji GFX100 II (negru pe model de pixeli, cblack[0…3] = 0): negrul trebuie să fie 4095 (nu 0), imaginea 4:3 întreagă, iar umbrele nu se pierd (înainte: piedestalul de 512 se scădea a doua oară și ~57% din pixeli aveau luminanță ≤ 0).
    /// Fișierul vine din GDC_PA_FUJI_RAF (fotografie privată, numai citire); fără variabilă testul se sare.
    func testFujiPatternBlackKeepsShadowsAndFullFourThirdsFrame() throws {
        guard let f = ProcessInfo.processInfo.environment["GDC_PA_FUJI_RAF"] else { throw XCTSkip("fără GDC_PA_FUJI_RAF") }
        var o = DecodeOptions(); o.halfSize = true
        let d = try RawFile(path: f).decodeLinearDWG(o)
        XCTAssertEqual(d.report.whitePlan.black, 4095); XCTAssertEqual(d.report.appliedCrop.w, 11648); XCTAssertEqual(d.report.appliedCrop.h, 8735)
        XCTAssertLessThan(d.report.fracNegative, 0.02)                      // doar zgomot sub negru, nu majoritatea cadrului
        let ys = sampledLuma(d.image.rgb)
        XCTAssertGreaterThan(ys[ys.count / 2], 0.003)                       // mediana luminanței rămâne pozitivă (≈ 0.006 măsurat independent cu rawpy/LibRaw)
    }
    /// Compensarea dezvoltării: valoarea camerei se citește (−1.72), câștigul e liniar (2^EV pe mediană), iar dezvoltarea veche (revizia 1) își păstrează exact comportamentul (crop 3:2, ~57% sub zero).
    func testFujiBaselineGainAndLegacyRevisionAreExplicit() throws {
        guard let f = ProcessInfo.processInfo.environment["GDC_PA_FUJI_RAF"] else { throw XCTSkip("fără GDC_PA_FUJI_RAF") }
        XCTAssertEqual(try RawFile(path: f).cameraExposureShift ?? 0, -1.72, accuracy: 0.01)
        func medianY(_ d: DecodedLinear) -> Float { let ys = sampledLuma(d.image.rgb); return ys[ys.count / 2] }
        var o = DecodeOptions(); o.halfSize = true
        let base = try RawFile(path: f).decodeLinearDWG(o); var og = o; og.baselineEV = 1.72
        let gained = try RawFile(path: f).decodeLinearDWG(og)
        XCTAssertEqual(Double(medianY(gained) / medianY(base)), pow(2, 1.72), accuracy: 0.02 * pow(2, 1.72)); XCTAssertEqual(gained.report.appliedBaselineEV, 1.72, accuracy: 1e-9)
        var ol = o; ol.legacyV1 = true; let old = try RawFile(path: f).decodeLinearDWG(ol)
        XCTAssertEqual(old.report.appliedCrop.h, 7765); XCTAssertGreaterThan(old.report.fracNegative, 0.5)
    }
    func testOrientationHelperRotatesCorrectly() {
        let img = FloatImage(width: 3, height: 2, rgb: (0..<6).flatMap { [Float($0), 0, 0] })   // 0 1 2 / 3 4 5
        let cw = FloatImage.oriented(img, flip: 6); XCTAssertEqual(cw.width, 2); XCTAssertEqual(cw.height, 3)
        XCTAssertEqual(stride(from: 0, to: cw.rgb.count, by: 3).map { cw.rgb[$0] }, [3, 0, 4, 1, 5, 2])
        let ccw = FloatImage.oriented(img, flip: 5)
        XCTAssertEqual(stride(from: 0, to: ccw.rgb.count, by: 3).map { ccw.rgb[$0] }, [2, 5, 1, 4, 0, 3])
    }
}
extension DecodeOptions { static var activeAreaOnly: DecodeOptions { var o = DecodeOptions(); o.crop = .activeArea; return o } }

final class HighlightPolicyTests: XCTestCase {
    /// Pe un RAW real (A7 V, previzualizare half_size): valorile > 1.0 din WB pe pixeli NESATURAȚI există și sunt păstrate de `clipSaturated`, tăiate de `clipWhite`; saturația ADC rămâne tăiată neutru.
    func testPoliciesDifferExactlyWhereExpected() throws {
        guard let dir = ProcessInfo.processInfo.environment["GDC_PA_RAW_DIR"] else { throw XCTSkip("fără GDC_PA_RAW_DIR") }
        func run(_ p: HighlightPolicy) throws -> DecodedLinear { var o = DecodeOptions(); o.halfSize = true; o.highlight = p; return try RawFile(path: dir + "/BCE00435.ARW").decodeLinearDWG(o) }
        let keep = try run(.keep), white = try run(.clipWhite), sat = try run(.clipSaturated)
        XCTAssertGreaterThan(keep.report.causes.whiteBalanceOnly, 0.05)                      // supraunitare legitime (WB), nesaturate
        XCTAssertGreaterThan(keep.report.causes.adcSaturated, 0.05)
        XCTAssertGreaterThan(sat.report.linMax, white.report.linMax)                         // clipSaturated păstrează intervalul peste referință
        XCTAssertLessThanOrEqual(sat.report.linMax, keep.report.linMax)
        XCTAssertEqual(keep.report.causes, sat.report.causes); XCTAssertEqual(keep.report.causes, white.report.causes)   // cauzele se măsoară înainte de politică
        // pixelii complet saturați ies neutri sub clipSaturated (R≈G≈B), spre deosebire de keep (magenta)
        func neutralFrac(_ d: DecodedLinear) -> Double { var n = 0, t = 0; let v = d.image.rgb; for i in stride(from: 0, to: v.count, by: 3) where v[i + 1] > 0.9 { t += 1; if abs(v[i] - v[i + 1]) < 0.15 * v[i + 1] && abs(v[i + 2] - v[i + 1]) < 0.15 * v[i + 1] { n += 1 } }; return t == 0 ? 1 : Double(n) / Double(t) }
        XCTAssertGreaterThan(neutralFrac(sat), neutralFrac(keep))
    }
}

/// Luminanța unui pixel din 17, sortată crescător (pași expliciți: expresia compactă depășea timpul de verificare a tipurilor pe mașini lente).
private func sampledLuma(_ rgb: [Float]) -> [Float] {
    var ys: [Float] = []; ys.reserveCapacity(rgb.count / 51 + 1)
    var i = 0
    while i + 2 < rgb.count {
        let r: Float = rgb[i], g: Float = rgb[i + 1], b: Float = rgb[i + 2]
        let y: Float = 0.2949 * r + 0.6254 * g + 0.0797 * b
        ys.append(y); i += 51
    }
    ys.sort(); return ys
}
