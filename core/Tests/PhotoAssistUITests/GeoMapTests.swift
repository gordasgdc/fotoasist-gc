import XCTest
@testable import PhotoAssistUI
import PhotoResolve

/// Eroarea aproximării ghidajelor sub perspectivă: conturul elipsei desenat ca elipsă (centru + vectori de axă locali) vs conturul EXACT al zonei procesate (marginea elipsei din sursă trecută prin harta exactă).
final class GeoMapTests: XCTestCase {
    func deviation(_ g: Geometry, rx: Double, ry: Double, rot: Double, cx: Double = 0.5, cy: Double = 0.5) -> Double {
        let src = CGSize(width: 6000, height: 4000); let m = GeoMap(r: CGRect(x: 0, y: 0, width: 1000, height: 700), geo: g, source: src)
        var c = MaskComponent(kind: .ellipse); c.x1 = cx; c.y1 = cy; c.x2 = rx; c.y2 = ry; c.rotation = rot
        let a = c.x2 * m.srcW, b = c.y2 * m.srcH, ph = rot * .pi / 180; let ctr = m.fwd(c.x1, c.y1)
        let u = m.vec(from: c.x1, c.y1, dxPx: a * cos(ph), dyPx: a * sin(ph)), v = m.vec(from: c.x1, c.y1, dxPx: -b * sin(ph), dyPx: b * cos(ph))
        var worst = 0.0
        for k in 0..<72 { let t = Double(k) / 72 * 2 * .pi
            let ex = c.x1 + (a * cos(t) * cos(ph) - b * sin(t) * sin(ph)) / m.srcW, ey = c.y1 + (a * cos(t) * sin(ph) + b * sin(t) * cos(ph)) / m.srcH   // punct de pe margine (sursă)
            let exact = m.fwd(ex, ey); let approx = CGPoint(x: ctr.x + cos(t) * u.dx + sin(t) * v.dx, y: ctr.y + cos(t) * u.dy + sin(t) * v.dy)
            worst = max(worst, hypot(Double(exact.x - approx.x), Double(exact.y - approx.y))) }
        return worst
    }
    func testSimilarityGeometryHasNoOverlayError() {
        var g = Geometry(); g.angle = 7; g.rotate90 = 1; g.flipH = true; g.crop = CropRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8)
        XCTAssertLessThan(deviation(g, rx: 0.2, ry: 0.1, rot: 20), 0.05, "rotire/oglindire/decupare: elipsa desenată = zona procesată")
    }
    func testPerspectiveErrorIsMeasuredAndTheSampledOutlineIsExact() {
        var g = Geometry(); g.keystoneV = 60
        let e = deviation(g, rx: 0.25, ry: 0.2, rot: 0); print("EROARE aproximării elipsei sub perspectivă (60): \(e) px de vedere")
        XCTAssertGreaterThan(e, 0.5, "aproximarea afină NU urmărește fidel sub perspectivă (de aceea conturul se desenează din puncte exacte)")
    }
}
