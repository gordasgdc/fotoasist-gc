import XCTest
@testable import PhotoAssistUI

/// Matematica vederii (zoom pe cursor, limite, 100% = un pixel al imaginii la un pixel fizic). Evenimentele de rotiță/Space/buton mijloc se verifică separat în aplicația reală.
final class ViewerStateTests: XCTestCase {
    func make() -> ViewerState { let v = ViewerState(); v.backing = 2; v.canvasSize = CGSize(width: 1000, height: 700); v.fullSize = CGSize(width: 6000, height: 4000); return v }

    func testFitScaleAndPercentAndFullResolutionThreshold() {
        let v = make(); XCTAssertTrue(v.isFit); XCTAssertEqual(v.scale, min(980.0 * 2 / 6000, 680.0 * 2 / 4000), accuracy: 1e-9); XCTAssertFalse(v.wantsFullResolution)
        let r = v.imageRect(); XCTAssertEqual(r.midX, 500, accuracy: 1e-6); XCTAssertEqual(r.midY, 350, accuracy: 1e-6); XCTAssertLessThanOrEqual(r.width, 980 + 1e-6); XCTAssertLessThanOrEqual(r.height, 680 + 1e-6)
        v.setScale(0.6); XCTAssertTrue(v.wantsFullResolution); v.setScale(0.4); XCTAssertFalse(v.wantsFullResolution)
    }
    func testHundredPercentIsOneImagePixelPerPhysicalPixel() {
        let v = make(); v.set100(); XCTAssertEqual(v.scale, 1); XCTAssertEqual(v.percent, 100)
        let r = v.imageRect(); XCTAssertEqual(r.width, 6000.0 / 2, accuracy: 1e-9, "6000 px de imagine = 3000 pt pe un ecran 2× (un pixel imagine = un pixel fizic)"); XCTAssertEqual(r.height, 4000.0 / 2, accuracy: 1e-9)
        XCTAssertEqual((r.minX * 2).rounded(), r.minX * 2, accuracy: 1e-9, "aliniat la pixelii fizici"); XCTAssertEqual((r.minY * 2).rounded(), r.minY * 2, accuracy: 1e-9)
    }
    func testZoomKeepsThePointUnderTheCursorFixed() {
        let v = make(); let cursor = CGPoint(x: 700, y: 250)
        let before = v.normalized(cursor); v.zoom(by: 1.5, around: cursor)
        for _ in 0..<12 { let a = v.normalized(cursor); v.zoom(by: 1.12, around: cursor); let b = v.normalized(cursor); XCTAssertEqual(a.x, b.x, accuracy: 1e-6); XCTAssertEqual(a.y, b.y, accuracy: 1e-6, "fără salturi: același punct al fotografiei rămâne sub cursor") }
        let after = v.normalized(cursor); XCTAssertEqual(before.x, after.x, accuracy: 0.0005); XCTAssertEqual(before.y, after.y, accuracy: 0.0005)
    }
    func testLimitsKeepTheImageInTheWorkArea() {
        let v = make(); v.set100(); v.pan(by: CGSize(width: 1e6, height: 1e6)); var r = v.imageRect()
        XCTAssertLessThanOrEqual(r.minX, ViewerState.margin + 1e-6); XCTAssertLessThanOrEqual(r.minY, ViewerState.margin + 1e-6); XCTAssertGreaterThanOrEqual(r.maxX, 1000 - ViewerState.margin - 1e-6, "marginea imaginii nu trece de marginea vederii")
        v.pan(by: CGSize(width: -1e6, height: -1e6)); r = v.imageRect(); XCTAssertGreaterThanOrEqual(r.maxX, 1000 - ViewerState.margin - 1e-6); XCTAssertGreaterThanOrEqual(r.maxY, 700 - ViewerState.margin - 1e-6); XCTAssertLessThanOrEqual(r.minX, ViewerState.margin + 1e-6)
        v.zoom(by: 100, around: CGPoint(x: 500, y: 350)); XCTAssertEqual(v.scale, ViewerState.maxScale, "maximum 400%")
        v.zoom(by: 1e-6, around: CGPoint(x: 500, y: 350)); XCTAssertTrue(v.isFit, "mai departe de Potrivit = Potrivit"); XCTAssertEqual(v.imageRect().midX, 500, accuracy: 1e-6)
        v.pan(by: CGSize(width: 50, height: 50)); XCTAssertEqual(v.offset, .zero, "în Potrivit nu se deplasează")
    }
    func testPanMovesTheViewByTheDragAndCanvasResizeRevalidates() {
        let v = make(); v.set100(); let o = v.offset; v.pan(by: CGSize(width: 30, height: -20)); XCTAssertEqual(v.offset.width, o.width + 30, accuracy: 1e-9); XCTAssertEqual(v.offset.height, o.height - 20, accuracy: 1e-9)
        v.canvasSize = CGSize(width: 5000, height: 4000); v.revalidate(); XCTAssertEqual(v.offset, .zero, "imaginea mai mică decât vederea rămâne centrată")
    }
    func testNormalizedMappingRoundTrips() {
        let v = make(); v.zoom(by: 3, around: CGPoint(x: 300, y: 200)); let r = v.imageRect()
        for (nx, ny) in [(0.1, 0.2), (0.5, 0.5), (0.9, 0.75)] { let p = CGPoint(x: r.minX + nx * r.width, y: r.minY + ny * r.height); let n = v.normalized(p); XCTAssertEqual(n.x, nx, accuracy: 1e-9); XCTAssertEqual(n.y, ny, accuracy: 1e-9) }
    }
}
