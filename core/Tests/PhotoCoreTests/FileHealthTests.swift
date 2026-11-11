import XCTest
@testable import PhotoCore

final class FileHealthTests: XCTestCase {
    func tmp(_ name: String, _ bytes: [UInt8]) -> String { let d = FileManager.default.temporaryDirectory.appendingPathComponent("fh-\(UUID().uuidString)"); try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); let u = d.appendingPathComponent(name); try! Data(bytes).write(to: u); return u.path }
    func testClassesAreSeparatedByEvidenceNotByNameOrSize() {
        XCTAssertEqual(FileHealth.inspect(path: tmp("_IV1.ARW", []), recordedSize: 0, stabilityDelay: 0.05).kind, .empty)
        XCTAssertEqual(FileHealth.inspect(path: tmp("_IMG.CR2", [0, 5, 0x16, 7, 0, 2, 0, 0]), stabilityDelay: 0.05).kind, .appleDouble)
        XCTAssertEqual(FileHealth.inspect(path: tmp("_ok.ARW", [0x49, 0x49, 0x2A, 0, 8, 0, 0, 0] + [UInt8](repeating: 1, count: 100)), stabilityDelay: 0.05).kind, .ok, "prefixul «_» și dimensiunea mică nu fac un fișier corupt/AppleDouble")
        XCTAssertEqual(FileHealth.inspect(path: tmp("x.ARW", [UInt8](repeating: 7, count: 50)), stabilityDelay: 0.05).kind, .truncatedSuspect)
        XCTAssertEqual(FileHealth.inspect(path: "/nu/exista/x.ARW", stabilityDelay: 0).kind, .missing)
        XCTAssertEqual(FileHealth.inspect(path: "/Volumes/__volum_inexistent__/x.ARW", stabilityDelay: 0).kind, .volumeUnavailable)
    }
    func testUnstableFileIsNotCalledCorrupt() {
        let p = tmp("grow.ARW", [0x49, 0x49, 0x2A, 0] + [UInt8](repeating: 1, count: 10)); let h = FileHandle(forWritingAtPath: p)!; h.seekToEndOfFile()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { h.write(Data(repeating: 2, count: 1000)); try? h.close() }
        XCTAssertEqual(FileHealth.inspect(path: p, stabilityDelay: 0.4).kind, .unstable)
    }
}
