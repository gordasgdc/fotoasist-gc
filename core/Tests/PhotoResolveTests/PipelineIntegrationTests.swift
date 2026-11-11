import XCTest
import ImageIO
import CoreGraphics
@testable import PhotoResolve
@testable import PhotoRaw

/// Integrare reală cu Resolve Studio pornit (GDC_PA_RESOLVE=1) și RAW-urile de probă (GDC_PA_RAW_DIR); scrie DOAR în GDC_PA_SCRATCH (extern).
final class PipelineIntegrationTests: XCTestCase {
    func testPreviewThenCacheThenExportWithICC() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["GDC_PA_RESOLVE"] == "1", let raw = env["GDC_PA_RAW_DIR"], let scratch = env["GDC_PA_SCRATCH"] else { throw XCTSkip("necesită GDC_PA_RESOLVE=1, GDC_PA_RAW_DIR, GDC_PA_SCRATCH") }
        let photo = raw + "/A7306884.ARW"; let origMtime = try FileManager.default.attributesOfItem(atPath: photo)[.modificationDate] as? Date
        let bridge = try ResolveBridge(); try bridge.start(); defer { bridge.stop() }
        XCTAssertTrue(bridge.info?.verified ?? false, "versiune Resolve neverificată: \(String(describing: bridge.info))")
        try bridge.ensureProject("GDC_PHOTO_ASSIST_WORK_0001", allowSwitch: true)
        let work = URL(fileURLWithPath: scratch).appendingPathComponent("pipeline_test_\(UUID().uuidString.prefix(6))"); try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let proc = try PhotoProcessor(bridge: bridge, workDir: work)
        var a = AdjustmentSet(); a.exposure = 1.0
        let r1 = try proc.process(photoPath: photo, quality: .preview, adjustments: a)
        XCTAssertEqual(r1.width, 2000); XCTAssertEqual(r1.height, 3000)       // 6000×4000 default crop, jumătate, rotit
        XCTAssertGreaterThan(r1.liveness, 0.01); XCTAssertFalse(r1.fromIntermediateCache); XCTAssertEqual(r1.readBack["exposure_balance.v3eExposure"], 1.0)
        print("PIPE preview: decode \(r1.decodeSeconds)s, resolve \(r1.resolveSeconds)s, liveness \(r1.liveness)")
        var b = a; b.exposure = 2.0                                              // alt reglaj, aceeași decodare: intermediarul vine din cache
        let r2 = try proc.process(photoPath: photo, quality: .preview, adjustments: b)
        XCTAssertTrue(r2.fromIntermediateCache); XCTAssertNotEqual(r1.url, r2.url)
        let r3 = try proc.process(photoPath: photo, quality: .preview, adjustments: b)
        XCTAssertTrue(r3.fromResultCache)
        let dest = work.appendingPathComponent("export")
        let out = try ExportService.export(result: r2.url, original: URL(fileURLWithPath: photo), to: dest, name: "A7306884_GDC", format: .tiff16)
        let src = CGImageSourceCreateWithURL(out as CFURL, nil)!; let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        XCTAssertEqual(img.bitsPerComponent, 16); XCTAssertEqual(img.width, 2000)
        XCTAssertTrue((img.colorSpace?.name as String?)?.lowercased().contains("srgb") ?? false, "profil: \(String(describing: img.colorSpace?.name))")
        let jpg = try ExportService.export(result: r2.url, original: URL(fileURLWithPath: photo), to: dest, name: "A7306884_GDC", format: .jpeg(quality: 0.95))
        XCTAssertTrue(FileManager.default.fileExists(atPath: jpg.path))
        XCTAssertThrowsError(try ExportService.export(result: r2.url, original: URL(fileURLWithPath: photo), to: URL(fileURLWithPath: raw), name: "x", format: .tiff16))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: photo)[.modificationDate] as? Date, origMtime)   // originalul neatins
    }
}
