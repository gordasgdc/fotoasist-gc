import XCTest
import CoreGraphics
@testable import PhotoCore

final class FaceQualityCompareTests: XCTestCase {
    func face(h: Double, q: Float?) -> FaceObservation { FaceObservation(box: CGRect(x: 0.4, y: 0.4, width: h, height: h), confidence: 1, roll: nil, yaw: nil, captureQuality: q, left: nil, right: nil) }
    func testSmallOrMissingQualityIsNotEvaluable() {
        XCTAssertNil(FaceQualityCompare.representative([])); XCTAssertNil(FaceQualityCompare.representative([face(h: 0.02, q: 0.9)]), "față prea mică"); XCTAssertNil(FaceQualityCompare.representative([face(h: 0.2, q: nil)]))
        XCTAssertEqual(FaceQualityCompare.representative([face(h: 0.05, q: 0.2), face(h: 0.2, q: 0.5)]), 0.5, "cea mai mare față")
    }
    func testPromisingNeedsTwoEvaluableAndClearMargin() {
        XCTAssertNil(FaceQualityCompare.promising([1: 0.5])); XCTAssertNil(FaceQualityCompare.promising([1: 0.50, 2: 0.45]), "diferență mică ⇒ incert")
        let p = FaceQualityCompare.promising([1: 0.2, 2: 0.55, 3: 0.3]); XCTAssertEqual(p?.id, 2); XCTAssertEqual(p?.lead ?? 0, 0.25, accuracy: 1e-6)
    }
}
