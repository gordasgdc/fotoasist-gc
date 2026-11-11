import XCTest
import CoreGraphics
@testable import PhotoCore

final class SubjectMaskTests: XCTestCase {
    func flat(_ w: Int, _ h: Int) -> CGImage {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        c.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h)); return c.makeImage()!
    }
    func testNoSubjectInFlatImageIsNilNotAFalseMask() {
        // fără subiect ⇒ nil (nu inventează o mască); pe macOS < 14 ⇒ tot nil
        XCTAssertNil(SubjectMask.generate(flat(256, 256)))
    }
    func testAvailabilityMatchesOSVersion() {
        XCTAssertEqual(SubjectMask.isAvailable, ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)))
    }

    func disc(_ w: Int, _ h: Int, cx: Double, cy: Double, r: Double) -> [Float] { (0..<(w * h)).map { i in hypot(Double(i % w) - cx, Double(i / w) - cy) < r ? 1 : 0 } }
    func testContourOfASyntheticSubjectIsClosedSimplifiedAndInNormalisedCoordinates() throws {
        let w = 400, h = 300; let a = disc(w, h, cx: 280, cy: 120, r: 70)
        let c = try XCTUnwrap(SubjectMask.contour(alpha: a, width: w, height: h)); XCTAssertGreaterThanOrEqual(c.count, 8); XCTAssertLessThan(c.count, 160, "simplificat")
        for p in c { XCTAssertEqual(hypot((p.x - 0.7) * 400, (p.y - 0.4) * 300), 70, accuracy: 6, "puncte pe cercul real (origine sus-stânga, 0…1)") }
        XCTAssertGreaterThan(c.map { $0.x }.min()!, 0.5); XCTAssertLessThan(c.map { $0.y }.max()!, 0.7)
    }
    func testContourPicksLargestAndRefusesTinyOrEmpty() {
        let w = 200, h = 200; var a = disc(w, h, cx: 60, cy: 60, r: 40); let small = disc(w, h, cx: 160, cy: 160, r: 10); for i in a.indices { a[i] = max(a[i], small[i]) }
        let c = SubjectMask.contour(alpha: a, width: w, height: h)!; XCTAssertLessThan(c.map { $0.x }.max()!, 0.6, "a ales cercul mare")
        XCTAssertNil(SubjectMask.contour(alpha: [Float](repeating: 0, count: w * h), width: w, height: h)); XCTAssertNil(SubjectMask.contour(alpha: disc(w, h, cx: 100, cy: 100, r: 3), width: w, height: h), "sub 0,2% din imagine ⇒ nu e subiect")
    }
    func testMatteIsAGrayPNGWithSubjectWhite() throws {
        let d = try XCTUnwrap(SubjectMask.mattePNG(alpha: disc(64, 48, cx: 32, cy: 24, r: 10), width: 64, height: 48)); XCTAssertEqual(Array(d.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }
}
