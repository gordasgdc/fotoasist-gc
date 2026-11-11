import XCTest
@testable import PhotoCore

final class ExposureCuesTests: XCTestCase {
    func sig(sharp: Double = 100, hi: Double = 0, lo: Double = 0, med: Double = 120) -> Signals { Signals(sharpness: sharp, clipHighPct: hi, clipLowPct: lo, medianLuma: med, dhash: 0, histogram: []) }
    func testMissingSignalsIsAnalysisNotDoneNotAPhotoVerdict() {
        let c = ExposureCues.exposure(nil); XCTAssertEqual(c.count, 1); XCTAssertEqual(c[0].kind, .analysisMissing)
    }
    func testNormalFrameHasNoCues() { XCTAssertTrue(ExposureCues.exposure(sig()).isEmpty) }
    func testClipAndToneCuesAreUncertainAndSayPreviewNotRAW() {
        let c = ExposureCues.exposure(sig(hi: 7, lo: 6, med: 30)); XCTAssertEqual(c.count, 3); XCTAssertTrue(c.allSatisfy { $0.certainty == .uncertain })
        XCTAssertTrue(c.contains { $0.why.contains("RAW") })
    }
    func testSharpnessOnlyComparedInsideGroupAndOnlyWhenClearlyLower() {
        let best = sig(sharp: 400), soft = sig(sharp: 100), near = sig(sharp: 300)
        XCTAssertNil(ExposureCues.sharpness(own: soft, groupSignals: [soft]), "fără rafală nu se compară")
        XCTAssertNotNil(ExposureCues.sharpness(own: soft, groupSignals: [best, soft])); XCTAssertNil(ExposureCues.sharpness(own: near, groupSignals: [best, near])); XCTAssertNil(ExposureCues.sharpness(own: best, groupSignals: [best, soft]))
    }
}
