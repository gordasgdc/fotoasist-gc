import XCTest
import AppKit
import PhotoResolve
@testable import PhotoAssistUI

/// Cursorul uneltelor: hotspot-ul = centrul reticulului (punctul de prelevare), la Potrivit / zoom / deplasare și la factori Retina 1×/2×; reticulul se vede (centrul desenat, brațe cu gol central).
final class ToolCursorTests: XCTestCase {
    func render(_ img: NSImage, scale: Int) -> NSBitmapImageRep {
        let w = Int(img.size.width) * scale, h = Int(img.size.height) * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = img.size; NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: img.size)); NSGraphicsContext.restoreGraphicsState(); return rep
    }
    func alpha(_ r: NSBitmapImageRep, _ xPt: CGFloat, _ yPtFromBottom: CGFloat, scale: Int) -> CGFloat {
        let px = Int(xPt * CGFloat(scale)), py = r.pixelsHigh - 1 - Int(yPtFromBottom * CGFloat(scale)); return r.colorAt(x: px, y: py)?.alphaComponent ?? 0
    }
    func testHotSpotIsTheCrosshairCentreAtRetinaAndStandardScale() {
        for kind in [ToolCursor.sample, .draw] {
            XCTAssertEqual(kind.cursor.hotSpot, ToolCursor.hotSpot, "hotspot = centrul reticulului")
            for scale in [1, 2] {
                let r = render(ToolCursor.image(withGlyph: kind == .sample), scale: scale); let c = ToolCursor.hotSpot
                XCTAssertGreaterThan(alpha(r, c.x, c.y, scale: scale), 0.5, "centrul reticulului e desenat (\(kind), \(scale)×)")
                XCTAssertEqual(alpha(r, c.x + 2.2, c.y, scale: scale), 0, accuracy: 0.05, "gol central: se vede punctul exact (\(scale)×)")
                XCTAssertGreaterThan(alpha(r, c.x + 7, c.y, scale: scale), 0.5, "braț dreapta"); XCTAssertGreaterThan(alpha(r, c.x, c.y - 7, scale: scale), 0.5, "braț jos")
            }
        }
        XCTAssertEqual(ToolCursor.size.width, 32); XCTAssertTrue(ToolCursor.size.width / 2 == ToolCursor.hotSpot.x && ToolCursor.size.height / 2 == ToolCursor.hotSpot.y)
    }
    /// Punctul prelevat = poziția mouse-ului mapată prin dreptunghiul imaginii: la Potrivit, cu zoom și cu deplasare dă aceeași coordonată de imagine; aceeași matematică pe ecran Retina (puncte, nu pixeli).
    func testSamplePointMapsBackExactlyForFitZoomAndPan() {
        let src = CGSize(width: 6000, height: 4000)
        let rects = [CGRect(x: 0, y: 0, width: 900, height: 600), CGRect(x: -300, y: -200, width: 2700, height: 1800), CGRect(x: 120, y: -640, width: 1800, height: 1200)]
        for r in rects {
            let m = GeoMap(r: r, geo: Geometry(), source: src)
            for (x, y) in [(0.1, 0.2), (0.5, 0.5), (0.93, 0.77)] {
                let screen = m.fwd(x, y); let back = m.inv(screen)
                XCTAssertEqual(Double(back.x), x, accuracy: 1e-9); XCTAssertEqual(Double(back.y), y, accuracy: 1e-9)
                XCTAssertEqual(screen.x, r.minX + CGFloat(x) * r.width, accuracy: 1e-6, "mapare liniară în dreptunghiul afișat"); XCTAssertEqual(screen.y, r.minY + CGFloat(y) * r.height, accuracy: 1e-6)
            }
        }
    }
}
