import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import PhotoCore
@testable import PhotoResolve

/// Calea EXPLICITĂ de intrare display-referred (PNG/JPEG/TIFF): identificare, ICC respectat, sRGB asumat înregistrat, stare neutră = pixelii sursei, geometrie, fără metadate inventate.
final class RenderedInputTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rendered-\(UUID().uuidString)"); try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makePNG(_ name: String, w: Int, h: Int, space: CGColorSpace, px: (Int, Int) -> [UInt8]) -> URL {
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w { let c = px(x, y); data[(y * w + x) * 4] = c[0]; data[(y * w + x) * 4 + 1] = c[1]; data[(y * w + x) * 4 + 2] = c[2] } }
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let url = dir.appendingPathComponent(name); let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(d)); return url
    }
    func readTIFF(_ url: URL) -> (w: Int, h: Int, px: [UInt16]) {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!; let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!; let w = img.width, h = img.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 16, bytesPerRow: w * 8, space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); let p = ctx.data!.bindMemory(to: UInt16.self, capacity: w * h * 4)
        return (w, h, (0..<(w * h * 4)).map { p[$0] })
    }

    func testInventoryIsSeparateFromRawAndInventsNoCamera() throws {
        _ = makePNG("a.png", w: 4, h: 4, space: CGColorSpaceCreateDeviceRGB()) { _, _ in [10, 20, 30] }
        XCTAssertEqual(try Inventory.scan(directory: dir).count, 0, "calea RAW nu vede PNG-uri")
        let e = try Inventory.scan(directory: dir, rendered: true); XCTAssertEqual(e.count, 1); XCTAssertNil(e[0].camera, "fără metadate de cameră inventate")
        XCTAssertTrue(RenderedImage.isRendered(path: "/x/a.PNG")); XCTAssertFalse(RenderedImage.isRendered(path: "/x/a.ARW"))
    }
    func testUntaggedFileRecordsAssumedSRGBAsDemoChoice() throws {
        let u = dir.appendingPathComponent("u.tif"); try TIFF16.write(rgb: [Float](repeating: 0.3, count: 4 * 4 * 3), width: 4, height: 4, to: u)   // TIFF 16 biți fără profil ICC (scriitorul propriu)
        let (_, info) = try RenderedImage.load(url: u)
        XCTAssertFalse(info.profileDetected); XCTAssertNotNil(info.assumption); XCTAssertTrue(info.summary.contains("asumat"))
    }
    func testEmbeddedProfileIsDetectedAndRespected() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let u = makePNG("p3.png", w: 4, h: 4, space: p3) { _, _ in [128, 51, 51] }
        let (img, info) = try RenderedImage.load(url: u); XCTAssertTrue(info.profileDetected, "profil ICC citit din fișier"); XCTAssertNil(info.assumption)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let exp = CGColor(colorSpace: p3, components: [128.0 / 255, 51.0 / 255, 51.0 / 255, 1])!.converted(to: srgb, intent: .defaultIntent, options: nil)!.components!
        let rgb = try RenderedImage.floatRGB(url: u).rgb
        for c in 0..<3 { XCTAssertEqual(Double(rgb[c]), Double(exp[c]), accuracy: 0.01, "canal \(c): conversie ICC → sRGB") }
        XCTAssertEqual(img.width, 4)
    }
    func testNeutralProcessingKeepsSourcePixelsAndNeverUsesDRT() throws {
        let u = makePNG("g.png", w: 16, h: 8, space: CGColorSpaceCreateDeviceRGB()) { x, y in [UInt8(x * 16), UInt8(y * 30), UInt8(200 - x * 5)] }
        let proc = try OwnCoreProcessor(workDir: dir.appendingPathComponent("work"))
        let r = try proc.process(photoPath: u.path, quality: .full, adjustments: AdjustmentSet())
        XCTAssertNil(r.decode, "fără raport de decodare RAW"); XCTAssertNotNil(r.rendered); XCTAssertEqual(r.width, 16); XCTAssertEqual(r.height, 8)
        let t = readTIFF(r.url)
        for y in 0..<8 { for x in 0..<16 { let i = (y * 16 + x) * 4
            XCTAssertEqual(Int(t.px[i]), Int(UInt8(x * 16)) * 257, accuracy: 1); XCTAssertEqual(Int(t.px[i + 1]), Int(UInt8(y * 30)) * 257, accuracy: 1); XCTAssertEqual(Int(t.px[i + 2]), Int(UInt8(200 - x * 5)) * 257, accuracy: 1) } }
    }
    func testOnlyGeometryIsApplied() throws {
        let u = makePNG("c.png", w: 16, h: 8, space: CGColorSpaceCreateDeviceRGB()) { x, _ in x < 8 ? [255, 0, 0] : [0, 0, 255] }
        let proc = try OwnCoreProcessor(workDir: dir.appendingPathComponent("work"))
        var a = AdjustmentSet(); a.contrast = 2; a.saturation = 0; a.exposure = 3        // reglaje de ton/culoare: ignorate pe o imagine redată
        a.geometry.crop = CropRect(x: 0.5, y: 0, w: 0.5, h: 1)
        let r = try proc.process(photoPath: u.path, quality: .full, adjustments: a)
        XCTAssertEqual(r.width, 8); XCTAssertEqual(r.height, 8)
        let t = readTIFF(r.url); XCTAssertEqual(Int(t.px[0]), 0, accuracy: 300); XCTAssertEqual(Int(t.px[2]), 65535, accuracy: 300, "jumătatea dreaptă (albastru), culoarea nemodificată de contrast/saturație")
    }
    func testPreviewIsLabelledRenderedSourceNotCamera() throws {
        let u = makePNG("v.png", w: 64, h: 32, space: CGColorSpaceCreateDeviceRGB()) { _, _ in [90, 90, 90] }
        let p = try RenderedPreviewProvider().preview(for: u, maxPixel: 32); XCTAssertEqual(p?.source, "rendered-source"); XCTAssertEqual(max(p!.image.width, p!.image.height), 32)
    }
}
