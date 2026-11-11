import XCTest
import CoreGraphics
@testable import PhotoAssistUI
import PhotoResolve

final class FaceFrameContractTests: XCTestCase {
    /// Imagine sintetică asimetrică (gradient + blocuri) pe side×side.
    func scene() -> [Double] {
        let n = FaceFrameContract.side; var l = [Double](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n { l[y * n + x] = Double(x * 3 + y) + (x < 8 && y < 6 ? 120 : 0) + (x > 15 && y > 17 ? 60 : 0) } }
        return l
    }
    func testIdentityPassesAndEveryOtherDihedralTransformIsDetected() {
        let s = scene(); let size = CGSize(width: 300, height: 300)
        XCTAssertEqual(FaceFrameContract.check(previewLuma: s, sourceLuma: s, previewSize: size, sourceSize: size).isOK, true)
        for t in 1..<8 {
            let v = FaceFrameContract.check(previewLuma: FaceFrameContract.transform(s, t), sourceLuma: s, previewSize: size, sourceSize: size)
            guard case .orientationMismatch = v else { return XCTFail("transformarea \(t) nu a fost detectată: \(v)") }
        }
    }
    func testAspectMismatchAndFlatContentAreRefused() {
        let s = scene()
        guard case .aspectMismatch = FaceFrameContract.check(previewLuma: s, sourceLuma: s, previewSize: CGSize(width: 3000, height: 2000), sourceSize: CGSize(width: 2000, height: 3000)) else { return XCTFail() }
        guard case .aspectMismatch = FaceFrameContract.check(previewLuma: s, sourceLuma: s, previewSize: CGSize(width: 3000, height: 2000), sourceSize: CGSize(width: 4000, height: 3000)) else { return XCTFail("3:2 vs 4:3") }
        let flat = [Double](repeating: 100, count: s.count)
        XCTAssertFalse(FaceFrameContract.check(previewLuma: flat, sourceLuma: flat, previewSize: CGSize(width: 10, height: 10), sourceSize: CGSize(width: 10, height: 10)).isOK)
    }
    func testLumaOfRenderedImageMatchesScene() {
        let n = 96; var px = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n { for x in 0..<n { let v = UInt8(min(255, x * 2 + (y < 30 ? 40 : 0))); let i = 4 * (y * n + x); px[i] = v; px[i + 1] = v; px[i + 2] = v } }
        let cg = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let l = FaceFrameContract.luma(cg); XCTAssertEqual(l.count, FaceFrameContract.side * FaceFrameContract.side)
        XCTAssertGreaterThan(l[FaceFrameContract.side * FaceFrameContract.side - 1], l[FaceFrameContract.side * 20])    // gradient crescător spre dreapta
    }

    // Maparea sursă→ieșire (GeoMap pe dreptunghi unitate) pentru orientare, crop, rotație, perspectivă
    let src = CGSize(width: 6000, height: 4000)
    func map(_ g: Geometry) -> GeoMap { GeoMap(r: CGRect(x: 0, y: 0, width: 1, height: 1), geo: g, source: src) }
    func testRotate90AndFlipsFollowDocumentedSemantics() {
        var g = Geometry(); g.rotate90 = 1                              // sens orar: stânga-sus → dreapta-sus
        var p = map(g).fwd(0, 0); XCTAssertEqual(p.x, 1, accuracy: 1e-9); XCTAssertEqual(p.y, 0, accuracy: 1e-9)
        p = map(g).fwd(1, 0); XCTAssertEqual(p.x, 1, accuracy: 1e-9); XCTAssertEqual(p.y, 1, accuracy: 1e-9)
        g = Geometry(); g.flipH = true; p = map(g).fwd(0.2, 0.3); XCTAssertEqual(p.x, 0.8, accuracy: 1e-9); XCTAssertEqual(p.y, 0.3, accuracy: 1e-9)
        g = Geometry(); g.flipV = true; p = map(g).fwd(0.2, 0.3); XCTAssertEqual(p.x, 0.2, accuracy: 1e-9); XCTAssertEqual(p.y, 0.7, accuracy: 1e-9)
        g = Geometry(); g.rotate90 = 2; p = map(g).fwd(0.2, 0.3); XCTAssertEqual(p.x, 0.8, accuracy: 1e-9); XCTAssertEqual(p.y, 0.7, accuracy: 1e-9)
    }
    func testCropRemapsAndPointsOutsideCropFallOutside() {
        var g = Geometry(); g.crop = CropRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5)
        var p = map(g).fwd(0.25, 0.25); XCTAssertEqual(p.x, 0, accuracy: 1e-9); XCTAssertEqual(p.y, 0, accuracy: 1e-9)
        p = map(g).fwd(0.75, 0.5); XCTAssertEqual(p.x, 1, accuracy: 1e-9); XCTAssertEqual(p.y, 0.5, accuracy: 1e-9)
        p = map(g).fwd(0.1, 0.1); XCTAssertLessThan(p.x, 0)                                // în afara cadrului: lupa îl limitează, nu îl inventează
    }
    func testFineRotationAndPerspectiveRoundTripAndAgreeWithGeometryPlan() {
        var g = Geometry(); g.rotate90 = 3; g.flipH = true; g.angle = 7.5; g.keystoneV = 0.2; g.keystoneH = -0.1; g.scale = 1.1
        let m = map(g)
        for pt in [(0.5, 0.5), (0.3, 0.6), (0.7, 0.4)] {
            let f = m.fwd(pt.0, pt.1); let b = m.inv(f)
            XCTAssertEqual(b.x, pt.0, accuracy: 1e-6); XCTAssertEqual(b.y, pt.1, accuracy: 1e-6)
            let o = g.sourceToOutput(pt.0 * 6000, pt.1 * 4000, srcW: 6000, srcH: 4000)!                // cale independentă: planul de geometrie
            let plan = g.plan(srcW: 6000, srcH: 4000)
            XCTAssertEqual(f.x, o.x / Double(plan.outW), accuracy: 1e-9); XCTAssertEqual(f.y, o.y / Double(plan.outH), accuracy: 1e-9)
        }
    }
}
