import XCTest
@testable import PhotoRaw

final class RawPolicyTests: XCTestCase {
    private func geo(raw: (Int, Int), active: PixelRect, insets: [PixelRect], maker: PixelRect? = nil) -> RawGeometry {
        RawGeometry(rawWidth: raw.0, rawHeight: raw.1, activeArea: active, insetCrops: insets, makerDefaultCrop: maker, makerRecommendedArea: nil, rawAspect: 0)
    }
    // Valori măsurate pe fișierele reale (2026-10-21), vezi COLOR_AND_OUTPUT_CONTRACT.md.
    func testCanon6DUsesMakerFieldAndExcludesInterpolationMargin() {
        let p = CropPlan.resolve(geo(raw: (6384, 4224), active: .init(x: 120, y: 44, w: 6264, h: 4180), insets: [.init(x: 132, y: 56, w: 6240, h: 4160)], maker: .init(x: 132, y: 56, w: 6240, h: 4160)))
        XCTAssertEqual(p.defaultCrop, PixelRect(x: 132, y: 56, w: 6240, h: 4160)); XCTAssertEqual(p.defaultCropSource, .makerDefaultField); XCTAssertNil(p.cameraAspectPreference)
    }
    func testSonyA7VKeepsMarginsOutEvenThoughActiveAreaIsLarger() {
        let p = CropPlan.resolve(geo(raw: (7168, 5120), active: .init(x: 0, y: 0, w: 7168, h: 5120), insets: [.init(x: 12, y: 8, w: 7008, h: 4672)]))
        XCTAssertEqual(p.defaultCrop, PixelRect(x: 12, y: 8, w: 7008, h: 4672)); XCTAssertEqual(p.defaultCropSource, .libRawInset)
    }
    func testSonyA7IIIAspectPreferenceIsReportedNotApplied() {
        let p = CropPlan.resolve(geo(raw: (6048, 4024), active: .init(x: 0, y: 0, w: 6024, h: 4024), insets: [.init(x: 12, y: 324, w: 6000, h: 3376)]))
        XCTAssertEqual(p.cameraAspectPreference, PixelRect(x: 12, y: 324, w: 6000, h: 3376))
        XCTAssertEqual(p.defaultCrop, PixelRect(x: 12, y: 12, w: 6000, h: 4000)); XCTAssertEqual(p.defaultCropSource, .derivedNativeAspect)   // = DefaultCrop din metadatele ARW
    }
    /// Fuji GFX100 II (măsurat pe un fișier de probă): inset 11648×8735 (4:3) în zona activă 11662×8746 (4:3). Înainte: tăiat la 3:2 (7765 linii în loc de 8735) — pierdere de câmp.
    func testNativeFourThirdsSensorKeepsFullInset() {
        let p = CropPlan.resolve(geo(raw: (11808, 8754), active: .init(x: 0, y: 2, w: 11662, h: 8746), insets: [.init(x: 8, y: 8, w: 11648, h: 8735)]))
        XCTAssertEqual(p.defaultCrop, PixelRect(x: 8, y: 8, w: 11648, h: 8735)); XCTAssertEqual(p.defaultCropSource, .libRawInset)
    }
    func testFallbackToActiveAreaWithoutInset() {
        let a = PixelRect(x: 0, y: 0, w: 4000, h: 3000)
        let p = CropPlan.resolve(geo(raw: (4000, 3000), active: a, insets: []))
        XCTAssertEqual(p.defaultCrop, a); XCTAssertEqual(p.defaultCropSource, .activeAreaFallback)
    }
    func testWhitePlanVendorDefaultAndHeadroom() {
        let p = WhiteLevelPlan.plan(black: 512, vendorWhite: 14558, adcMax: 16383)
        XCTAssertEqual(p.white, 14558); XCTAssertEqual(p.source, .vendorViaLibRaw)
        XCTAssertEqual(p.headroomStops, log2(Double(16383 - 512) / Double(14558 - 512)), accuracy: 1e-12)
        let hi = WhiteLevelPlan.plan(black: 2048, vendorWhite: 14558, adcMax: 16383)
        XCTAssertGreaterThan(hi.headroomStops, p.headroomStops)   // negrul de 2048 lasă mai puțin domeniu sub alb, deci mai mult headroom relativ
    }
    func testExplicitWhiteIsClampedAndNeverAutomatic() {
        XCTAssertEqual(WhiteLevelPlan.plan(black: 512, vendorWhite: 14558, adcMax: 16383, source: .explicit(20000)).white, 16383)
        XCTAssertEqual(WhiteLevelPlan.plan(black: 512, vendorWhite: 14558, adcMax: 16383, source: .explicit(100)).white, 513)
    }
}

final class RawPolicyRealFilesTests: XCTestCase {
    /// Decuparea implicită rezolvată din LibRaw = DefaultCrop/CroppedImage din metadatele fișierelor (citite cu exiftool la investigație), pe toate cele 12 RAW.
    func testDefaultCropMatchesFileMetadataOnAllSamples() throws {
        guard let dir = ProcessInfo.processInfo.environment["GDC_PA_RAW_DIR"] else { throw XCTSkip("fără GDC_PA_RAW_DIR") }
        let expected: [String: PixelRect] = ["A7306884.ARW": .init(x: 12, y: 12, w: 6000, h: 4000), "ARC03524.ARW": .init(x: 12, y: 8, w: 7008, h: 4672),
            "IMG_0042.CR2": .init(x: 132, y: 56, w: 6240, h: 4160), "IMG_3504.CR2": .init(x: 132, y: 56, w: 6240, h: 4160),
            "_Q1A7330.CR3": .init(x: 168, y: 108, w: 6000, h: 4000), "_Q1A8149.CR3": .init(x: 168, y: 108, w: 6000, h: 4000)]
        for f in try FileManager.default.contentsOfDirectory(atPath: dir).sorted() where ["arw", "cr2", "cr3"].contains((f as NSString).pathExtension.lowercased()) {
            let plan = CropPlan.resolve(try RawFile(path: dir + "/" + f).geometry)
            let want = expected[f] ?? (f.hasPrefix("BCE") ? PixelRect(x: 12, y: 8, w: 7008, h: 4672) : nil)
            XCTAssertEqual(plan.defaultCrop, want, f)
        }
    }
}
