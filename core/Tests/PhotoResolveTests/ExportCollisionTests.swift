import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import PhotoResolve

/// Politica pentru nume existente: niciodată suprascriere tăcută; planul din rezumat = regulile de scriere.
final class ExportCollisionTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws { dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exp-coll-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }
    func touch(_ n: String, _ bytes: String = "x") throws { try bytes.data(using: .utf8)!.write(to: dir.appendingPathComponent(n)) }

    func testUniqueNeverOverwritesAndNumbersWithinTheBatch() throws {
        try touch("a_GDC.tif"); try touch("a_GDC-2.tif")
        let p = ExportService.plan(dir: dir, names: ["a_GDC", "b_GDC", "b_GDC", "A_GDC"], ext: "tif", policy: .unique)
        XCTAssertEqual(p.map { $0.url.lastPathComponent }, ["a_GDC-3.tif", "b_GDC.tif", "b_GDC-2.tif", "A_GDC-4.tif"])
        XCTAssertEqual(p.map { $0.exists }, [true, false, true, true]); XCTAssertTrue(p.allSatisfy { !$0.skipped })
    }
    func testSkipAndOverwriteReportTheExistingFiles() throws {
        try touch("a_GDC.tif")
        let s = ExportService.plan(dir: dir, names: ["a_GDC", "c_GDC"], ext: "tif", policy: .skip)
        XCTAssertEqual(s.map { $0.skipped }, [true, false])
        let o = ExportService.plan(dir: dir, names: ["a_GDC", "c_GDC"], ext: "tif", policy: .overwrite)
        XCTAssertEqual(o.map { $0.url.lastPathComponent }, ["a_GDC.tif", "c_GDC.tif"]); XCTAssertEqual(o.map { $0.exists }, [true, false])
    }
    func tinyTIFF() throws -> URL {
        let cs = CGColorSpaceCreateDeviceRGB(); let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let u = dir.appendingPathComponent("src.tif"); let d = CGImageDestinationCreateWithURL(u as CFURL, UTType.tiff.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(d)); return u
    }
    func testExportWritesBesideNotOverExistingByDefaultAndSkipLeavesFileUntouched() throws {
        let src = try tinyTIFF(); let out = dir.appendingPathComponent("out"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let orig = URL(fileURLWithPath: "/nonexistent/folder/IMG_1.ARW")
        try "KEEP".data(using: .utf8)!.write(to: out.appendingPathComponent("IMG_1_GDC.tif"))
        let r1 = try ExportService.export(result: src, original: orig, to: out, name: "IMG_1_GDC", format: .tiff16)
        XCTAssertEqual(r1.lastPathComponent, "IMG_1_GDC-2.tif"); XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("IMG_1_GDC.tif")), "KEEP")
        XCTAssertThrowsError(try ExportService.export(result: src, original: orig, to: out, name: "IMG_1_GDC", format: .tiff16, collision: .skip)) { e in if case PipelineError.outputExists = e {} else { XCTFail("\(e)") } }
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("IMG_1_GDC.tif")), "KEEP")
        _ = try ExportService.export(result: src, original: orig, to: out, name: "IMG_1_GDC", format: .tiff16, collision: .overwrite)
        XCTAssertNotEqual(try Data(contentsOf: out.appendingPathComponent("IMG_1_GDC.tif")), "KEEP".data(using: .utf8)!, "doar «overwrite» înlocuiește")
    }
}
