import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoCore

struct TestProvider: PreviewProvider {   // ImageIO-ul real cere miniatură încorporată; pentru test: GOOD → imagine, THROW → eroare, restul → nil (ca un fișier invalid)
    func preview(for url: URL, maxPixel: Int) throws -> PreviewImage? {
        let n = url.lastPathComponent; if n.hasPrefix("THROW") { throw NSError(domain: "t", code: 1) }
        guard n.hasPrefix("GOOD"), let s = CGImageSourceCreateWithURL(url as CFURL, nil), let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { return nil }
        return PreviewImage(image: i, source: "test", seconds: 0)
    }
}
final class InvalidRawTests: XCTestCase {
    func jpeg(at url: URL) throws {
        let ctx = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!; CGImageDestinationAddImage(d, ctx.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(d))
    }
    func testInvalidRawIsReportedAndSkippedWithoutStoppingImportOrTouchingOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("badraw-\(UUID().uuidString)"); let src = root.appendingPathComponent("src"), lib = root.appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        try jpeg(at: src.appendingPathComponent("GOOD_1.ARW")); try jpeg(at: src.appendingPathComponent("GOOD_2.ARW"))
        try Data(repeating: 1, count: 100).write(to: src.appendingPathComponent("THROW_1.ARW")); let stub = src.appendingPathComponent("_IMG_9450.CR2"); try Data(repeating: 0x5A, count: 4096).write(to: stub)       // ciot invalid (ca în setul real)
        let before = try Data(contentsOf: stub); let mt = try FileManager.default.attributesOfItem(atPath: stub.path)[.modificationDate] as? Date
        let cat = try Catalog(url: root.appendingPathComponent("c.sqlite")); let cache = try PreviewCache(catalog: cat, directory: lib.appendingPathComponent("cache"), provider: TestProvider())
        let sum = try LibraryImporter.run(directory: src, catalog: cat, cache: cache, recursive: true)
        XCTAssertEqual(sum.added, 4); XCTAssertEqual(sum.withPreview, 2, "restul lotului a continuat"); XCTAssertEqual(sum.withoutPreview, 2)
        XCTAssertEqual(Set(sum.skipped.map { ($0.path as NSString).lastPathComponent }), ["_IMG_9450.CR2", "THROW_1.ARW"], "invalidul (nil) și cel care aruncă eroare sunt raportate cu motiv"); XCTAssertTrue(sum.skipped.allSatisfy { !$0.reason.isEmpty })
        XCTAssertEqual(try Data(contentsOf: stub), before, "originalul neatins"); XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: stub.path)[.modificationDate] as? Date, mt)
        let again = try LibraryImporter.run(directory: src, catalog: cat, cache: cache, recursive: true); XCTAssertEqual(again.unchanged, 4); XCTAssertEqual(again.skipped.count, 2, "se raportează și la reimport, fără a bloca")
    }
}
