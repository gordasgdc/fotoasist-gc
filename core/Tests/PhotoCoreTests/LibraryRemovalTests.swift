import XCTest
@testable import PhotoCore

final class LibraryRemovalTests: XCTestCase {
    func testRemovalCountsImpactAndKeepsFilesAndOthers() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let original = dir.appendingPathComponent("A.ARW"); try Data([1, 2, 3]).write(to: original)
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite"))
        _ = try c.importFiles([(original.path, 3, 1, "Cam", Date(timeIntervalSince1970: 1)), ("/zz/other/B.ARW", 9, 1, "Cam", Date(timeIntervalSince1970: 2)), ("/zz/other/C.ARW", 9, 2, "Cam", Date(timeIntervalSince1970: 3))])
        let ph = try c.photos(); let a = ph[0].id, b = ph[1].id
        try c.setEdits(photoId: a, json: "{}"); let al = try c.createAlbum("X"); try c.addToAlbum(al, photoIds: [a, b]); try c.setDecision(.keep, photoId: a)
        let imp = try c.removalImpact(photoIds: [a])
        XCTAssertEqual(imp, Catalog.RemovalImpact(photos: 1, withEdits: 1, inAlbums: 1, exported: 0, decided: 1))
        let folders = try c.sourceFolders(); XCTAssertEqual(folders.map { $0.count }.sorted(), [1, 2])
        XCTAssertEqual(try c.removeFromCatalog(photoIds: [a]), 1)
        XCTAssertEqual(try c.photos().count, 2); XCTAssertNil(try c.edits(photoId: a)); XCTAssertEqual(try c.albums().first?.count, 1, "albumul rămâne cu fotografia nescoasă")
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "originalul nu se șterge niciodată")
    }
}

final class AppleDoubleTests: XCTestCase {
    func testAppleDoubleStubsAreRecognisedAndSkippedByScan() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ad-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stub = dir.appendingPathComponent("_IMG_1.CR2"); try Data([0x00, 0x05, 0x16, 0x07, 0, 2, 0, 0]).write(to: stub)
        let real = dir.appendingPathComponent("IMG_2.CR2"); try Data([0x49, 0x49, 0x2a, 0x00, 0x10, 0, 0, 0]).write(to: real)
        XCTAssertTrue(Inventory.isAppleDouble(path: stub.path)); XCTAssertFalse(Inventory.isAppleDouble(path: real.path))
        let found = try Inventory.scan(directory: dir, readMetadata: false); XCTAssertEqual(found.map { ($0.path as NSString).lastPathComponent }, ["IMG_2.CR2"])
    }
}
