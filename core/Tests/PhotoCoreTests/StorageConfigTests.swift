import XCTest
@testable import PhotoCore

final class StorageConfigTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fa-storage-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }
    func write(_ rel: String, _ n: Int, in lib: URL) throws { let u = lib.appendingPathComponent(rel); try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(count: n).write(to: u) }

    func testLocationRoundTripAndHealthOK() throws {
        let root = tmp.appendingPathComponent("Work"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let loc = StorageConfig.make(root: root)
        XCTAssertNotNil(loc.volumeUUID, "volumul trebuie identificat prin UUID, nu doar prin nume")
        let store = StorageConfigStore(defaults: UserDefaults(suiteName: "fa-test-\(UUID().uuidString)")!); XCTAssertNil(store.location); store.location = loc; XCTAssertEqual(store.location, loc)
        let h = StorageConfig.health(loc, minFreeBytes: 1024); XCTAssertTrue(h.health.isOK, "\(h.health)"); XCTAssertEqual(h.url?.standardizedFileURL.path, root.standardizedFileURL.path)
    }
    func testMissingVolumeAndChangedVolumeAndLowSpace() throws {
        let root = tmp.appendingPathComponent("W"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var loc = StorageConfig.make(root: root)
        loc.volumeUUID = "00000000-0000-0000-0000-000000000000"; loc.volumeName = "DiscLipsa"                  // volum cu alt UUID, nemontat → indisponibil, NU se ghicește după nume/cale
        guard case .missing(let n, _) = StorageConfig.health(loc).health else { return XCTFail("așteptat missing") }; XCTAssertEqual(n, "DiscLipsa")
        XCTAssertNil(StorageConfig.health(loc).url, "fără cale de rezervă pe alt disc")
        let ok = StorageConfig.make(root: root)
        guard case .lowSpace = StorageConfig.health(ok, minFreeBytes: Int64.max / 2).health else { return XCTFail("așteptat lowSpace") }
        XCTAssertTrue(StorageConfig.health(ok, minFreeBytes: 1).health.message.contains("Disponibil"))
    }
    func testNotWritableAndExportDestination() throws {
        let ro = tmp.appendingPathComponent("RO"); try FileManager.default.createDirectory(at: ro, withIntermediateDirectories: true); try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ro.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ro.path) }
        if getuid() != 0 { guard case .notWritable = StorageConfig.checkExportDestination(ro, needed: 1) else { return XCTFail("așteptat notWritable") } }
        guard case .missing = StorageConfig.checkExportDestination(tmp.appendingPathComponent("nu-exista"), needed: 1) else { return XCTFail("așteptat missing") }
        guard case .lowSpace = StorageConfig.checkExportDestination(tmp, needed: Int64.max / 2) else { return XCTFail("așteptat lowSpace") }
        XCTAssertTrue(StorageConfig.checkExportDestination(tmp, needed: 1).isOK)
    }
    func testUsageByCategoryAndCleanOnlyRegenerable() throws {
        let lib = StorageLayout.library(in: tmp)
        try write("catalog.sqlite", 1000, in: lib); try write("cache/1_thumb.jpg", 200, in: lib); try write("cache/1_view.jpg", 300, in: lib)
        try write("work/handoff/a.exr", 5000, in: lib); try write("work/own/results/r.tif", 700, in: lib); try write("work/resolve/results/x.tif", 50, in: lib); try write("misc/note.txt", 10, in: lib)
        let u = Dictionary(uniqueKeysWithValues: StorageConfig.usage(library: lib, analysis: (3, 123)).map { ($0.category, $0) })
        XCTAssertEqual(u[.catalog]?.bytes, 1000); XCTAssertEqual(u[.previews]?.bytes, 500); XCTAssertEqual(u[.intermediates]?.bytes, 5000); XCTAssertEqual(u[.results]?.bytes, 750); XCTAssertEqual(u[.other]?.bytes, 10); XCTAssertEqual(u[.analysis]?.bytes, 123)
        XCTAssertEqual(try StorageConfig.clean(.catalog, library: lib), 0, "catalogul nu e cache"); XCTAssertEqual(try StorageConfig.clean(.other, library: lib), 0)
        XCTAssertEqual(try StorageConfig.clean(.previews, library: lib), 500); XCTAssertEqual(try StorageConfig.clean(.intermediates, library: lib), 5000); XCTAssertEqual(try StorageConfig.clean(.results, library: lib), 750)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.appendingPathComponent("catalog.sqlite").path)); XCTAssertTrue(FileManager.default.fileExists(atPath: lib.appendingPathComponent("misc/note.txt").path))
    }
    func makeSource() throws -> (lib: URL, cat: Catalog) {
        let lib = StorageLayout.library(in: tmp.appendingPathComponent("Old")); try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        let cat = try Catalog(url: lib.appendingPathComponent("catalog.sqlite")); _ = try cat.importFiles([(path: "/orig/a.ARW", size: 1, mtimeNs: 1, camera: nil, capturedAt: nil)]); let pid = try cat.photos().first!.id; try cat.setSession("faces:1", "{}"); try cat.setSession("step", "2"); try cat.setEdits(photoId: pid, json: "{\"x\":1}")
        try write("cache/1_thumb.jpg", 400, in: lib); try write("work/handoff/e.exr", 9000, in: lib); try write("work/own/results/r.tif", 300, in: lib); return (lib, cat)
    }
    func testMigrationCopyVerifySourceUntouched() throws {
        let (lib, cat) = try makeSource(); let newRoot = tmp.appendingPathComponent("New")
        var steps = 0
        let rep = try StorageMigration.run(from: lib, toRoot: newRoot, snapshotCatalog: { try cat.snapshot(to: $0) }, verifyCatalog: { u in let c = try Catalog(url: u); let a = try c.session("step"), b = try c.edits(photoId: c.photos().first!.id), f = try c.session("faces:1"); return a == "2" && b == "{\"x\":1}" && f == "{}" }, progress: { _, _ in steps += 1 })
        let dst = StorageLayout.library(in: newRoot); XCTAssertEqual(rep.destination.standardizedFileURL, dst.standardizedFileURL); XCTAssertGreaterThan(steps, 0)
        XCTAssertEqual((try Data(contentsOf: dst.appendingPathComponent("work/handoff/e.exr"))).count, 9000)
        let c2 = try Catalog(url: dst.appendingPathComponent("catalog.sqlite")); let e2 = try c2.edits(photoId: c2.photos().first!.id); XCTAssertEqual(e2, "{\"x\":1}", "reglajele/măștile se păstrează")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.appendingPathComponent("work/handoff/e.exr").path), "sursa nu se șterge"); XCTAssertEqual(try cat.session("step"), "2")
        XCTAssertFalse((try FileManager.default.contentsOfDirectory(atPath: newRoot.path)).contains { $0.hasPrefix(".fa-migrate") }, "fără rest temporar")
        XCTAssertThrowsError(try StorageMigration.run(from: lib, toRoot: newRoot, snapshotCatalog: { try cat.snapshot(to: $0) }, verifyCatalog: { _ in true })) { XCTAssertTrue("\($0)".contains("conține deja")) }
    }
    func testMigrationFailureAndCancelLeaveNoPartialAndKeepSource() throws {
        let (lib, cat) = try makeSource(); let r1 = tmp.appendingPathComponent("N1"), r2 = tmp.appendingPathComponent("N2")
        XCTAssertThrowsError(try StorageMigration.run(from: lib, toRoot: r1, snapshotCatalog: { try cat.snapshot(to: $0) }, verifyCatalog: { _ in false })) { XCTAssertTrue("\($0)".contains("Verificarea")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: StorageLayout.library(in: r1).path)); XCTAssertEqual((try FileManager.default.contentsOfDirectory(atPath: r1.path)).count, 0)
        var n = 0; XCTAssertThrowsError(try StorageMigration.run(from: lib, toRoot: r2, snapshotCatalog: { try cat.snapshot(to: $0) }, verifyCatalog: { _ in true }, isCancelled: { n += 1; return n > 2 })) { XCTAssertTrue("\($0)".contains("anulată")) }
        XCTAssertEqual((try FileManager.default.contentsOfDirectory(atPath: r2.path)).count, 0); XCTAssertTrue(FileManager.default.fileExists(atPath: lib.appendingPathComponent("cache/1_thumb.jpg").path))
    }
    func testCatalogSessionPrefixStatsAndRemove() throws {
        let (_, cat) = try makeSource(); try cat.setSession("faces:2", "{\"a\":1}")
        XCTAssertEqual(try cat.sessionStats(prefix: "faces:").count, 2); try cat.removeSession(prefix: "faces:"); XCTAssertEqual(try cat.sessionStats(prefix: "faces:").count, 0); XCTAssertEqual(try cat.session("step"), "2", "doar prefixul curățat")
    }

    /// Disc extern real (dezvoltare): identitate prin UUID ≠ discul intern, calea relativă la punctul de montare, migrare interior → extern. Omis EXPLICIT când GDC_PA_ROOT lipsește (nu e o relaxare a testului).
    func testRealExternalVolumeIdentityAndMigration() throws {
        guard let r = ProcessInfo.processInfo.environment["GDC_PA_ROOT"], FileManager.default.fileExists(atPath: r) else { throw XCTSkip("GDC_PA_ROOT lipsește: test pe disc extern real omis") }
        let ext = URL(fileURLWithPath: r).appendingPathComponent("scratch/storage_unit_\(UUID().uuidString)"); try FileManager.default.createDirectory(at: ext, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: ext) }
        let le = StorageConfig.make(root: ext), li = StorageConfig.make(root: tmp)
        XCTAssertNotNil(le.volumeUUID); XCTAssertNotEqual(le.volumeUUID, li.volumeUUID, "două volume diferite au UUID diferit")
        XCTAssertFalse(le.relativePath.hasPrefix("/Volumes"), "calea e relativă la punctul de montare: \(le.relativePath)")
        XCTAssertEqual(StorageConfig.resolve(le)?.standardizedFileURL.path, ext.standardizedFileURL.path)
        XCTAssertTrue(StorageConfig.health(le, minFreeBytes: 1024).health.isOK)
        let (lib, cat) = try makeSource()
        let rep = try StorageMigration.run(from: lib, toRoot: ext, snapshotCatalog: { try cat.snapshot(to: $0) }, verifyCatalog: { u in try Catalog(url: u).photos().count == 1 })
        XCTAssertEqual(StorageConfig.volumeInfo(for: rep.destination).uuid, le.volumeUUID); XCTAssertTrue(FileManager.default.fileExists(atPath: lib.appendingPathComponent("catalog.sqlite").path))
    }

    func testContentDigestDetectsAnyDataChange() throws {
        let (_, cat) = try makeSource(); let d0 = try cat.contentDigest(); XCTAssertEqual(d0, try cat.contentDigest())
        let pid = try cat.photos().first!.id
        try cat.setEdits(photoId: pid, json: "{\"x\":2}"); let d1 = try cat.contentDigest(); XCTAssertNotEqual(d0, d1, "masca/reglajul schimbat")
        try cat.setDecision(.keep, photoId: pid); XCTAssertNotEqual(d1, try cat.contentDigest(), "decizia schimbată")
    }
}
