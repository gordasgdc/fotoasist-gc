import XCTest
@testable import PhotoAssistUI
import PhotoResolve

final class GeoMapFxTests: XCTestCase {
    func testGuidesRoundTripUnderDistortionAndGeometry() {
        var e = Effects(); e.distortion = 70; var g = Geometry(); g.angle = 4; g.keystoneV = 20
        let m = GeoMap(r: CGRect(x: 10, y: 20, width: 900, height: 600), geo: g, source: CGSize(width: 6000, height: 4000), effects: e)
        XCTAssertFalse(m.identity)
        for (x, y) in [(0.5, 0.5), (0.2, 0.3), (0.85, 0.7), (0.05, 0.9)] { let p = m.fwd(x, y); let b = m.inv(p); XCTAssertEqual(b.x, x, accuracy: 1e-6); XCTAssertEqual(b.y, y, accuracy: 1e-6) }
        let plain = GeoMap(r: CGRect(x: 10, y: 20, width: 900, height: 600), geo: g, source: CGSize(width: 6000, height: 4000)); XCTAssertNotEqual(m.fwd(0.1, 0.1), plain.fwd(0.1, 0.1), "distorsiunea mută ghidajul")
        let neutral = GeoMap(r: CGRect(x: 0, y: 0, width: 100, height: 100), geo: Geometry(), source: CGSize(width: 600, height: 400), effects: Effects()); XCTAssertTrue(neutral.identity)
    }
}
