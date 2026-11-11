import XCTest
@testable import PhotoAssistUI

final class ColorWheelTests: XCTestCase {
    func testRoundTripAndLuminanceComponentKept() {
        for (r, g, b) in [(0.1, -0.05, 0.02), (0.0, 0.0, 0.0), (-0.2, 0.15, 0.3), (0.05, 0.05, 0.05)] {
            let d = WheelMath.decompose(r, g, b); let c = WheelMath.compose(s: d.s, u: d.u, v: d.v)
            XCTAssertEqual(c.r, r, accuracy: 1e-12); XCTAssertEqual(c.g, g, accuracy: 1e-12); XCTAssertEqual(c.b, b, accuracy: 1e-12)
        }
        let n = WheelMath.compose(s: 0.04, u: 0.1, v: -0.07); XCTAssertEqual((n.r + n.g + n.b) / 3, 0.04, accuracy: 1e-12, "mutarea butonului păstrează componenta de luminanță s")
    }
    func testPrimaryDirections() {
        let red = WheelMath.compose(s: 0, u: 0.2, v: 0); XCTAssertGreaterThan(red.r, 0); XCTAssertEqual(red.g, red.b, accuracy: 1e-12)
        let green = WheelMath.compose(s: 0, u: -0.1, v: 0.1 * 3.0.squareRoot()); XCTAssertEqual(green.r, green.b, accuracy: 1e-9); XCTAssertGreaterThan(green.g, green.r)
    }
}
