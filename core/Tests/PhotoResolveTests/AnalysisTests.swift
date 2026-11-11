import XCTest
import CryptoKit
@testable import PhotoResolve
import PhotoRaw

/// Instrumentele de analiză: praguri documentate, domeniu declarat, mapări corecte, și NICIUN efect asupra rezultatului sau exportului.
final class AnalysisTests: XCTestCase {
    func testFalseColourBandsFollowStopsAroundMiddleGreyAndAreComplete() {
        let g = Float(0.18); let ys: [Float] = [0, 0.18 * 0.001, g * powf(2, -5), g * powf(2, -3), g * powf(2, -1), g, g * powf(2, 1.5), g * powf(2, 3), g * powf(2, 4), g * powf(2, 6)]
        let r = PhotoAnalysis.falseColour(lumaLinear: ys, width: ys.count, height: 1)
        let idx = ys.map { PhotoAnalysis.falseColourBand(stops: $0 > 0 ? log2(Double($0) / 0.18) : -99) }
        XCTAssertEqual(idx, [0, 0, 1, 2, 3, 4, 5, 6, 7, 8]); XCTAssertEqual(r.legend.map { $0.fraction }.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(PhotoAnalysis.falseColourBands.count, 9); XCTAssertTrue(PhotoAnalysis.falseColourBands.last!.upper.isInfinite)
        XCTAssertEqual(Array(r.rgb8[15..<18]), [150, 150, 150], "gri 18% = plaja neutră"); XCTAssertEqual(PhotoAnalysis.falseColourBand(stops: .nan), 0, "NaN nu produce plajă înaltă")
    }
    func testClippingMarksOnlyRealClipsAndCountsChannels() {
        let px: [Float] = [1, 1, 1, 1, 0.5, 0.5, 0, 0, 0, 0.5, 0.5, 0.5, 0.2, 0.2, 0.2, 0.998, 0.3, 0.3]
        let r = PhotoAnalysis.clipping(finalRGB: px, width: 6, height: 1)
        XCTAssertEqual(Array(r.rgb8[0..<3]), [255, 40, 40]); XCTAssertEqual(Array(r.rgb8[3..<6]), [255, 40, 40], "un singur canal la capăt = lumină tăiată"); XCTAssertEqual(Array(r.rgb8[6..<9]), [40, 90, 255])
        XCTAssertEqual(r.rgb8[9], r.rgb8[10]); XCTAssertLessThan(r.rgb8[9], 130, "restul: imaginea redusă în luminozitate, nu originalul")
        XCTAssertEqual(r.legend[0].fraction, 3.0 / 6, accuracy: 1e-9); XCTAssertEqual(r.legend[1].fraction, 1.0 / 6, accuracy: 1e-9); XCTAssertEqual(r.channelHigh[0], 3.0 / 6, accuracy: 1e-9)
    }
    func testSaturationUsesOklabChromaWithKnownReferences() {
        XCTAssertEqual(PhotoAnalysis.oklabChroma(r: 0.5, g: 0.5, b: 0.5), 0, accuracy: 1e-4, "gri = croma 0"); XCTAssertEqual(PhotoAnalysis.oklabChroma(r: 1, g: 0, b: 0), 0.2577, accuracy: 0.003, "roșu sRGB: C ≈ 0,258 (referința Oklab)")
        XCTAssertEqual(PhotoAnalysis.oklabChroma(r: 0, g: 1, b: 0), 0.2948, accuracy: 0.003); XCTAssertEqual(PhotoAnalysis.oklabChroma(r: 0, g: 0, b: 1), 0.3132, accuracy: 0.003)
        let r = PhotoAnalysis.saturation(finalRGB: [0.5, 0.5, 0.5, 1, 0, 0, 0, 0, 1], width: 3, height: 1); XCTAssertEqual(Array(r.rgb8[0..<3]), [60, 70, 90]); XCTAssertEqual(Array(r.rgb8[6..<9]), [230, 60, 50], "albastru saturat ≥ 0,30")
    }
    func testSkinAidIsAColourRangeNotAMask() {
        XCTAssertTrue(PhotoAnalysis.isSkinColour(r: 0.78, g: 0.58, b: 0.47)); XCTAssertTrue(PhotoAnalysis.isSkinColour(r: 0.9, g: 0.72, b: 0.6))
        XCTAssertFalse(PhotoAnalysis.isSkinColour(r: 0.4, g: 0.6, b: 0.9), "cer"); XCTAssertFalse(PhotoAnalysis.isSkinColour(r: 0.2, g: 0.5, b: 0.2), "vegetație"); XCTAssertFalse(PhotoAnalysis.isSkinColour(r: 0.05, g: 0.03, b: 0.02), "prea întunecat")
        XCTAssertTrue(AnalysisMode.skin.explanation.contains("NU e o mască manuală") && AnalysisMode.skin.explanation.contains("ML"), "limitele sunt spuse în interfață")
    }
    func testHistogramNormalisedAndDomainsAreDeclaredForEveryTool() {
        let px: [Float] = [0, 0, 0, 1, 1, 1, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]; let h = PhotoAnalysis.histogram(finalRGB: px, bins: 64)
        XCTAssertEqual(h.luma.reduce(0, +), 1, accuracy: 1e-6); XCTAssertEqual(h.r[0], 0.25, accuracy: 1e-6); XCTAssertEqual(h.r[63], 0.25, accuracy: 1e-6); XCTAssertEqual(h.r[32], 0.5, accuracy: 1e-6)
        for m in AnalysisMode.allCases where m != .off { XCTAssertFalse(m.domain.isEmpty); XCTAssertFalse(m.explanation.isEmpty) }
        XCTAssertTrue(AnalysisMode.falseColour.domain.contains("Scene-liniar") && AnalysisMode.clipping.domain.contains("finală"))
    }
    func testDownsampleKeepsAspectAndMeans() {
        let w = 40, h = 20; var rgb = [Float](repeating: 0, count: w * h * 3); for i in 0..<(w * h) { rgb[3 * i] = Float(i % 2) }
        let d = PhotoAnalysis.downsample(rgb, width: w, height: h, maxSide: 20); XCTAssertEqual(d.width, 20); XCTAssertEqual(d.height, 10); XCTAssertEqual(d.rgb[0], 0.5, accuracy: 1e-6)
    }
    func testTIFF16ReadBackMatchesWriter() throws {
        let w = 7, h = 5; var rgb = [Float](); for i in 0..<(w * h * 3) { rgb.append(Float(i % 97) / 96) }
        let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("an_\(UUID().uuidString).tif"); defer { try? FileManager.default.removeItem(at: u) }
        try TIFF16.write(rgb: rgb, width: w, height: h, to: u); let r = try TIFF16.read(u); XCTAssertEqual(r.width, w); XCTAssertEqual(r.height, h); for i in 0..<rgb.count { XCTAssertEqual(r.rgb[i], rgb[i], accuracy: 1.0 / 65535 + 1e-6) }
    }
    /// Pe un RAW real: toate modurile produc rezultate finite; analiza NU schimbă rezultatul procesat și nici exportul (octeți identici).
    func testAnalysisNeverChangesProcessedResultOrExport() throws {
        guard let dir = ProcessInfo.processInfo.environment["GDC_PA_RAW_DIR"], let scratch = ProcessInfo.processInfo.environment["GDC_PA_SCRATCH"] else { throw XCTSkip("fără GDC_PA_RAW_DIR / GDC_PA_SCRATCH") }
        guard let first = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.sorted().first(where: { $0.lowercased().hasSuffix(".arw") || $0.lowercased().hasSuffix(".cr2") }) else { throw XCTSkip("niciun RAW în GDC_PA_RAW_DIR") }
        let photo = dir + "/" + first; let work = URL(fileURLWithPath: scratch).appendingPathComponent("analysis_\(UUID().uuidString.prefix(6))"); defer { try? FileManager.default.removeItem(at: work) }
        let proc = try OwnCoreProcessor(workDir: work); var a = AdjustmentSet(); a.exposure = 0.5; a.contrast = 1.2; var l = LocalCorrection.make(.ellipse, number: 1); l.exposure = -0.5; a.locals = [l]
        let r0 = try proc.process(photoPath: photo, quality: .full, adjustments: a); let e0 = try ExportService.export(result: r0.url, original: URL(fileURLWithPath: photo), to: work.appendingPathComponent("out0"), name: "t", format: .tiff16)
        let h0 = SHA256.hash(data: try Data(contentsOf: e0)); let before = try FileManager.default.contentsOfDirectory(atPath: work.appendingPathComponent("results").path).sorted()
        for m in AnalysisMode.allCases { let r = try proc.analyze(photoPath: photo, adjustments: a, mode: m); XCTAssertEqual(r.mode, m); if m != .off { XCTAssertEqual(r.rgb8.count, r.width * r.height * 3); XCTAssertFalse(r.legend.isEmpty) }; XCTAssertEqual(r.histogram.luma.reduce(0, +), 1, accuracy: 1e-4) }
        let r1 = try proc.process(photoPath: photo, quality: .full, adjustments: a); XCTAssertEqual(r1.url, r0.url); XCTAssertTrue(r1.fromResultCache)
        let e1 = try ExportService.export(result: r1.url, original: URL(fileURLWithPath: photo), to: work.appendingPathComponent("out1"), name: "t", format: .tiff16); XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: e1)), h0, "exportul e identic după analiză")
        let after = try FileManager.default.contentsOfDirectory(atPath: work.appendingPathComponent("results").path).sorted(); XCTAssertTrue(Set(before).isSubset(of: Set(after)))
    }
}
