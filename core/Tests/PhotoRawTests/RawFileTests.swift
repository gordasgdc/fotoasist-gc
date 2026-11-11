import XCTest
import CoreGraphics
import PhotoCore
@testable import PhotoRaw

/// Testele cu RAW real se sar dacă GDC_PA_RAW_DIR lipsește (fotografiile autorizate nu sunt în repo).
final class RawFileTests: XCTestCase {
    func rawDir() throws -> String { guard let p = ProcessInfo.processInfo.environment["GDC_PA_RAW_DIR"], FileManager.default.fileExists(atPath: p) else { throw XCTSkip("GDC_PA_RAW_DIR nesetat") }; return p }

    func testLibraryVersionIsThePinnedOne() { XCTAssertEqual(RawFile.libraryVersion.prefix(6), "0.22.1", "dependența fixată (nu o instalare globală)") }
    func testOpeningMissingFileFailsCleanly() { XCTAssertThrowsError(try RawFile(path: "/nonexistent/x.ARW")) }

    func testInfoMatchesTheOracleOnRealFiles() throws {
        let d = try rawDir()
        let a = try RawFile(path: d + "/ARC03524.ARW").info          // Sony A7 IV: oracolul rawpy dă black 512, white 16380
        XCTAssertEqual(a.make, "Sony"); XCTAssertEqual(a.model, "ILCE-7M4"); XCTAssertEqual(a.blackLevel, 512); XCTAssertEqual(a.whiteLevel, 16380)
        let c = try RawFile(path: d + "/IMG_0042.CR2").info          // Canon 6D II: white 14558 (limita LibRaw), black 512
        XCTAssertEqual(c.model, "EOS 6D Mark II"); XCTAssertEqual(c.whiteLevel, 14558)
    }
    func testEmbeddedPreviewHasFullResolutionOnSonyA7V() throws {
        let f = try RawFile(path: try rawDir() + "/BCE00435.ARW"); let img = try f.embeddedPreview(); XCTAssertEqual(f.info.thumbnailFormat, "jpeg")
        XCTAssertGreaterThanOrEqual(max(img.width, img.height), 7000, "A7 V încorporează JPEG de rezoluție completă (spre deosebire de miniatura ImageIO)")
    }
    func testDevelopedPreviewIsHalfSizeAndLabelledAppDevelopment() throws {
        let f = try RawFile(path: try rawDir() + "/_Q1A7330.CR3"); let i = f.info
        let img = try f.developedPreview(halfSize: true)
        XCTAssertEqual(img.width, i.visibleWidth / 2, accuracy: 2); XCTAssertEqual(img.height, i.visibleHeight / 2, accuracy: 2)
    }
    func testSaturationSpikeRevealsTrueClipLevelOn6DMarkII() throws {
        let s = try RawFile(path: try rawDir() + "/IMG_0042.CR2").saturation()
        XCTAssertEqual(s.mostFrequentTop, 16383); XCTAssertTrue(s.spikeAboveReportedWhite, "spike la saturația ADC peste white_level raportat (14558)")
    }
}
extension RawFileTests {
    /// Regresie: `info` a copiat libraw_data_t pe stivă și a dat SIGBUS pe firele GCD (stivă mică). Rulăm pe un fir cu stivă de 512 KB.
    func testInfoAndDetailProviderWorkOnSmallStackThread() throws {
        let d = try rawDir(); let ex = expectation(description: "fir cu stivă mică"); var ok = false
        let th = Thread { let f = try? RawFile(path: d + "/ARC03524.ARW"); ok = (f?.info.model == "ILCE-7M4"); ex.fulfill() }; th.stackSize = 512 * 1024; th.start()
        wait(for: [ex], timeout: 30); XCTAssertTrue(ok)
    }
    func testDetailProviderPicksCameraFullOrAppDevelopmentAndLabelsIt() throws {
        let d = try rawDir(); let p = LibRawDetailProvider()
        let full = try XCTUnwrap(try p.preview(for: URL(fileURLWithPath: d + "/BCE00435.ARW"), maxPixel: .max))      // A7 V: JPEG de rezoluție completă în fișier
        XCTAssertEqual(full.source, "camera-full"); XCTAssertGreaterThanOrEqual(max(full.image.width, full.image.height), 7000)
        let dev = try XCTUnwrap(try p.preview(for: URL(fileURLWithPath: d + "/A7306884.ARW"), maxPixel: .max))      // A7 III: previzualizarea e 1080×1920 ⇒ developare
        XCTAssertEqual(dev.source, "app-developed-libraw"); XCTAssertGreaterThan(max(dev.image.width, dev.image.height), 5500)
    }
}
func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(abs(a - b) <= accuracy, "\(a) vs \(b)", file: file, line: line) }

final class RawGeometryProbeTests: XCTestCase {
    /// Sondă informativă: tipărește geometria raportată de LibRaw pentru toate RAW-urile (nu afirmă nimic despre decupare).
    func testGeometryDump() throws {
        guard let dir = ProcessInfo.processInfo.environment["GDC_PA_RAW_DIR"] else { throw XCTSkip("fără GDC_PA_RAW_DIR") }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { ["arw", "cr2", "cr3"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
        for f in files { let g = try RawFile(path: dir + "/" + f).geometry; print("GEOM \(f) raw=\(g.rawWidth)x\(g.rawHeight) active=\(g.activeArea) insets=\(g.insetCrops) makerDefault=\(String(describing: g.makerDefaultCrop)) recommended=\(String(describing: g.makerRecommendedArea)) aspect=\(g.rawAspect)") }
        XCTAssertFalse(files.isEmpty)
    }
}
