import XCTest
@testable import PhotoRaw

final class ExposureSuggestionTests: XCTestCase {
    private func img(_ w: Int, _ h: Int, _ f: (Int, Int) -> Float) -> FloatImage {
        var v = [Float](); v.reserveCapacity(w * h * 3); for y in 0..<h { for x in 0..<w { let a = f(x, y); v += [a, a, a] } }; return FloatImage(width: w, height: h, rgb: v) }
    func testLowKeySceneIsNotRaisedToMidGrey() {
        // 95% cadru foarte întunecat (0.001), 5% luminat (0.5): median→gri 18% ar cere ~7.5 st, ancora luminilor ~1
        let i = img(120, 120) { x, y in (x + y * 120) % 20 == 0 ? 0.5 : 0.001 }
        let s = ExposureSuggestion.compute(from: i, step: 1)
        XCTAssertGreaterThan(s.medianToGrey, 7); XCTAssertEqual(s.stops, s.highlightAnchor, accuracy: 1e-9); XCTAssertLessThan(s.stops, 2)
        XCTAssertTrue(s.lowKeyWarning); XCTAssertEqual(s.sceneHint, "low-key")
    }
    func testClippedHighlightsGiveAboutZeroSuggestion() {
        let i = img(100, 100) { x, _ in x < 90 ? 0.3 : 1.0 }
        let s = ExposureSuggestion.compute(from: i, step: 1); XCTAssertEqual(s.highlightAnchor, 0, accuracy: 0.05); XCTAssertLessThanOrEqual(s.stops, 0.05)
    }
    func testBalancedSceneUsesMedianWhenItIsTheSmaller() {
        let i = img(100, 100) { x, _ in Float(x) / 100 * 0.18 + 0.09 }      // mediană ≈0.18, p99 ≈ 0.27 → median→gri ≈ 0, ancoră ≈ +1.9
        let s = ExposureSuggestion.compute(from: i, step: 1); XCTAssertEqual(s.stops, s.medianToGrey, accuracy: 1e-9); XCTAssertEqual(s.medianToGrey, 0, accuracy: 0.1); XCTAssertFalse(s.lowKeyWarning)
    }
}
