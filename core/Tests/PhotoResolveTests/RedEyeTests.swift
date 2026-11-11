import XCTest
@testable import PhotoResolve

/// Ochi roșii manual: ochi sintetic (piele + iris + pupilă roșie + reflex alb) în liniar.
final class RedEyeTests: XCTestCase {
    let w = 200, h = 200
    func eye() -> [Float] {
        var a = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h { for x in 0..<w { let i = (y * w + x) * 3; let d = hypot(Double(x) - 100, Double(y) - 100)
            var p: [Float] = [0.60, 0.42, 0.34]                                  // piele: roșeață ≈ 0,12
            if d < 40 { p = [0.30, 0.22, 0.12] }                                 // iris maro
            if d < 18 { p = [0.80, 0.06, 0.05] }                                 // pupilă roșie (roșeață ≈ 0,76)
            if hypot(Double(x) - 94, Double(y) - 94) < 3 { p = [0.9, 0.9, 0.9] } // reflex alb
            a[i] = p[0]; a[i + 1] = p[1]; a[i + 2] = p[2] } }
        return a
    }
    func spot(_ r: Double = 0.2, strength: Double? = nil) -> RetouchSpot { var s = RetouchSpot(); s.mode = .redEye; s.x = 0.5; s.y = 0.5; s.radius = r; s.feather = 0.3; s.strength = strength; return s }
    func px(_ a: [Float], _ x: Int, _ y: Int) -> [Float] { let i = (y * w + x) * 3; return [a[i], a[i + 1], a[i + 2]] }
    func testPupilNeutralisedSkinIrisAndCatchlightUntouched() {
        let src = eye(), out = Retouch.apply([spot()], to: src, width: w, height: h)
        let p = px(out, 106, 106); XCTAssertLessThan(p[0], 0.2); XCTAssertLessThan(p[0] / max(p[1], 1e-6), 1.6, "roșul neutralizat")
        for (x, y) in [(100, 135), (60, 100), (96, 94)] { XCTAssertEqual(px(out, x, y), px(src, x, y), "iris/piele neatinse \(x),\(y)") }
        XCTAssertEqual(px(out, 94, 94), px(src, 94, 94), "reflexul alb rămâne")
    }
    func testOutsideCircleAndZeroStrengthAreIdentity() {
        let src = eye()
        XCTAssertEqual(Retouch.apply([spot(0.05)], to: src, width: w, height: h)[(100 * w + 120) * 3], src[(100 * w + 120) * 3])  // pupila la 20 px, cerc de 10 px
        XCTAssertEqual(Retouch.apply([spot(strength: 0)], to: src, width: w, height: h), src)
        var off = spot(); off.enabled = false; XCTAssertEqual(Retouch.apply([off], to: src, width: w, height: h), src)
    }
    func testStrengthScalesAndIsReversibleByRemovingSpot() {
        let src = eye(), half = Retouch.apply([spot(strength: 0.5)], to: src, width: w, height: h), full = Retouch.apply([spot()], to: src, width: w, height: h)
        XCTAssertGreaterThan(px(half, 106, 106)[0], px(full, 106, 106)[0]); XCTAssertLessThan(px(half, 106, 106)[0], px(src, 106, 106)[0])
        XCTAssertEqual(Retouch.apply([], to: src, width: w, height: h), src)
    }
    func testOldSavedSpotWithoutStrengthDecodesAndFingerprintChanges() throws {
        let json = #"{"id":"a","enabled":true,"mode":1,"x":0.5,"y":0.5,"sx":0.55,"sy":0.5,"radius":0.02,"feather":0.5}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(RetouchSpot.self, from: json); XCTAssertNil(s.strength)
        var a = spot(), b = spot(); a.id = "q"; b.id = "q"; b.strength = 0.4; XCTAssertNotEqual(a.fingerprint, b.fingerprint)
    }
}
