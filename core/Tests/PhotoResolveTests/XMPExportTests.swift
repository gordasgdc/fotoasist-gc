import XCTest
import ImageIO
@testable import PhotoResolve

final class XMPExportTests: XCTestCase {
    func testExportedJPEGCarriesRatingReadableByImageIOAndExiftool() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("xe-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let res = d.appendingPathComponent("r.tif"); try TIFF16.write(rgb: [Float](repeating: 0.5, count: 16 * 16 * 3), width: 16, height: 16, to: res)
        let orig = d.appendingPathComponent("orig/IMG.ARW"); try FileManager.default.createDirectory(at: orig.deletingLastPathComponent(), withIntermediateDirectories: true); try Data([1]).write(to: orig)
        for (rating, expect) in [(4, "4"), (-1, "-1")] {
            let out = try ExportService.export(result: res, original: orig, to: d.appendingPathComponent("out\(rating)"), name: "t", format: .jpeg(quality: 0.9), rating: rating)
            let src = CGImageSourceCreateWithURL(out as CFURL, nil)!; let md = CGImageSourceCopyMetadataAtIndex(src, 0, nil)!
            let tag = CGImageMetadataCopyTagWithPath(md, nil, "xmp:Rating" as CFString); XCTAssertNotNil(tag, "xmp:Rating prezent (ImageIO)")
            XCTAssertEqual(CGImageMetadataTagCopyValue(tag!) as? String, expect)
            if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/exiftool") {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/exiftool"); p.arguments = ["-s3", "-XMP:Rating", out.path]; let pipe = Pipe(); p.standardOutput = pipe; try p.run(); p.waitUntilExit()
                XCTAssertEqual(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), expect, "exiftool citește același xmp:Rating")
            }
        }
        let plain = try ExportService.export(result: res, original: orig, to: d.appendingPathComponent("plain"), name: "p", format: .jpeg(quality: 0.9))
        let src = CGImageSourceCreateWithURL(plain as CFURL, nil)!; XCTAssertNil(CGImageSourceCopyMetadataAtIndex(src, 0, nil).flatMap { CGImageMetadataCopyTagWithPath($0, nil, "xmp:Rating" as CFString) }, "fără rating cerut, nu se scrie nimic")
    }
}
