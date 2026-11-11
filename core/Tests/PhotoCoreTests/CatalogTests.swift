import XCTest
import SQLite3
@testable import PhotoCore

final class CatalogTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        dir = URL(fileURLWithPath: base).appendingPathComponent("photocore-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func entries(_ n: Int, mtime: Int64 = 1) -> [Inventory.Entry] { (0..<n).map { ("/x/IMG_\($0).ARW", 100 + Int64($0), mtime, "Cam", Date(timeIntervalSince1970: 1_000 + Double($0))) } }

    func testDefaultStateIsCheckAndCountsMatch() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite"))
        XCTAssertEqual(try c.importFiles(entries(5)).added, 5)
        let k = try c.counts(); XCTAssertEqual(k.total, 5); XCTAssertEqual(k.check, 5); XCTAssertEqual(k.keep, 0); XCTAssertEqual(k.reject, 0)
    }

    func testDecisionsPersistAcrossReopen() throws {
        let u = dir.appendingPathComponent("c.sqlite"); var c: Catalog? = try Catalog(url: u); try c!.importFiles(entries(3))
        let ps = try c!.photos(); try c!.setDecision(.keep, photoId: ps[0].id); try c!.setDecision(.reject, photoIds: [ps[1].id]); try c!.setRating(4, photoId: ps[0].id); try c!.setFavorite(true, photoId: ps[0].id)
        c = nil
        let r = try Catalog(url: u); let q = try r.photos()
        XCTAssertEqual(q[0].decision, .keep); XCTAssertEqual(q[0].rating, 4); XCTAssertTrue(q[0].favorite); XCTAssertEqual(q[1].decision, .reject); XCTAssertEqual(q[2].decision, .check)
    }

    func testRejectIsReversibleByBatchUndo() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(4)); let ids = try c.photos().map { $0.id }
        try c.setDecision(.keep, photoIds: ids)               // lot 1
        try c.setDecision(.reject, photoIds: [ids[1], ids[2]]) // lot 2
        XCTAssertEqual(try c.counts().reject, 2)
        XCTAssertEqual(try c.undoLastDecisionBatch(), 2)
        let k = try c.counts(); XCTAssertEqual(k.reject, 0); XCTAssertEqual(k.keep, 4)
        XCTAssertEqual(try c.undoLastDecisionBatch(), 4)        // lotul 1
        XCTAssertEqual(try c.counts().check, 4)
        XCTAssertEqual(try c.undoLastDecisionBatch(), 0)         // nimic de anulat
    }

    func testIncrementalImportSkipsUnchangedAndKeepsDecisionWhenFileChanges() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(3))
        let first = try c.photos()[0]; try c.setDecision(.keep, photoId: first.id)
        var r = try c.importFiles(entries(3)); XCTAssertEqual(r, Catalog.ImportResult(added: 0, updated: 0, unchanged: 3, missing: 0))
        r = try c.importFiles(entries(3, mtime: 2)); XCTAssertEqual(r.updated, 3); XCTAssertEqual(r.added, 0)
        XCTAssertEqual(try c.photos()[0].decision, .keep, "decizia nu se pierde când fișierul se schimbă")
        r = try c.importFiles(Array(entries(3, mtime: 2).prefix(2))); XCTAssertEqual(r.missing, 1)
        XCTAssertEqual(try c.counts().total, 3, "fișierele dispărute NU se șterg din catalog")
    }

    func testRatingBoundsAndInvalidPhoto() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(1)); let id = try c.photos()[0].id
        XCTAssertThrowsError(try c.setRating(6, photoId: id)); XCTAssertThrowsError(try c.setRating(-1, photoId: id))
        XCTAssertThrowsError(try c.setDecision(.keep, photoId: 9999))
    }

    func testForEditingKeepOnlyOrAll() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(4)); let ids = try c.photos().map { $0.id }
        try c.setDecision(.keep, photoIds: [ids[0], ids[3]]); try c.setDecision(.reject, photoId: ids[1])
        XCTAssertEqual(try c.forEditing(allPhotos: false).count, 2); XCTAssertEqual(try c.forEditing(allPhotos: true).count, 4, "selecția poate fi sărită: continuă cu toate")
    }

    func testCatalogRefusesNewerSchema() throws {
        let u = dir.appendingPathComponent("c.sqlite"); _ = try Catalog(url: u)
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(u.path, &db), SQLITE_OK); sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil); sqlite3_close(db)
        XCTAssertThrowsError(try Catalog(url: u))
    }

    /// Integritate: importul + decizii NU creează fișiere lângă originale și nu le modifică (octeți, listă de fișiere).
    func testNothingIsWrittenBesideOriginals() throws {
        let src = dir.appendingPathComponent("originals"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        for n in ["A.ARW", "B.CR3"] { try Data(repeating: 7, count: 1000).write(to: src.appendingPathComponent(n)) }
        let before = try FileManager.default.contentsOfDirectory(atPath: src.path).sorted(); let bytes = try Data(contentsOf: src.appendingPathComponent("A.ARW"))
        let c = try Catalog(url: dir.appendingPathComponent("lib/c.sqlite".replacingOccurrences(of: "lib/", with: "")))
        try c.importFiles(try Inventory.scan(directory: src, readMetadata: false)); let ids = try c.photos().map { $0.id }
        try c.setDecision(.reject, photoIds: ids); try c.setRating(3, photoId: ids[0]); try c.setFavorite(true, photoId: ids[1])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: src.path).sorted(), before)
        XCTAssertEqual(try Data(contentsOf: src.appendingPathComponent("A.ARW")), bytes)
        XCTAssertEqual(try c.counts().reject, 2)
    }

    /// Informativ, pe fotografii reale (se sare dacă folderul lipsește): metadate + previzualizare încorporată, fără a developa RAW-ul.
    func testRealRawFolderIfAvailable() throws {
        guard let p = ProcessInfo.processInfo.environment["GDC_PA_RAW_DIR"], FileManager.default.fileExists(atPath: p) else { throw XCTSkip("GDC_PA_RAW_DIR nesetat") }
        let es = try Inventory.scan(directory: URL(fileURLWithPath: p)); XCTAssertGreaterThan(es.count, 0)
        XCTAssertTrue(es.contains { $0.camera != nil }, "metadate de aparat citite")
        var got = 0; var worst = 0.0
        for e in es { if let pv = try EmbeddedPreviewProvider().preview(for: URL(fileURLWithPath: e.path), maxPixel: 1400) { got += 1; worst = max(worst, pv.seconds); XCTAssertEqual(pv.source, "embedded-camera") } }
        print("PREVIEW embedded via ImageIO: \(got)/\(es.count) fișiere, cel mai lent \(String(format: "%.0f", worst * 1000)) ms")
    }
}

final class CatalogV3Tests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws { dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("photocore-v3-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }
    func entries(_ n: Int) -> [Inventory.Entry] { var out: [Inventory.Entry] = []; for i in 0..<n { out.append(("/x/IMG_\(i).ARW", Int64(100 + i), Int64(1), "Cam", Date(timeIntervalSince1970: Double(1_000 + i)))) }; return out }

    func testEditsSessionAndExportLogPersistAcrossReopen() throws {
        let u = dir.appendingPathComponent("c.sqlite"); var c: Catalog? = try Catalog(url: u)
        _ = try c!.importFiles(entries(3))
        let ids = try c!.photos().map { $0.id }
        try c!.setEdits(photoId: ids[0], json: #"{"exposure":1.5}"#); try c!.setEdits(photoId: ids[0], json: #"{"exposure":2}"#); try c!.setSession("screen", "style"); try c!.setSession("selected", "\(ids[1])")
        try c!.logExport(photoId: ids[0], path: "/out/a.tif", format: "tiff16")
        c = nil
        let r = try Catalog(url: u)
        XCTAssertEqual(try r.edits(photoId: ids[0]), #"{"exposure":2}"#); XCTAssertNil(try r.edits(photoId: ids[1]))
        XCTAssertEqual(try r.editedPhotoIds(), [ids[0]]); XCTAssertEqual(try r.session("screen"), "style"); XCTAssertEqual(try r.session("selected"), "\(ids[1])"); XCTAssertNil(try r.session("none"))
        XCTAssertEqual(try r.exports(photoId: ids[0]).map { $0.path }, ["/out/a.tif"])
        try r.clearEdits(photoId: ids[0]); XCTAssertNil(try r.edits(photoId: ids[0]))
    }
    func testMigrationFromV2KeepsDecisions() throws {
        // baza creată de v2 (fără tabelele noi) se migrează fără pierderi
        let u = dir.appendingPathComponent("old.sqlite")
        do { let c = try Catalog(url: u); _ = try c.importFiles(entries(1)); try c.setDecision(.keep, photoId: try c.photos()[0].id) }
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(u.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "DROP TABLE edits; DROP TABLE session_kv; DROP TABLE export_log; DROP TABLE album_photos; DROP TABLE albums; PRAGMA user_version=2;", nil, nil, nil), SQLITE_OK); sqlite3_close(db)
        let c = try Catalog(url: u); XCTAssertEqual(try c.photos()[0].decision, .keep); try c.setSession("k", "v"); XCTAssertEqual(try c.session("k"), "v")
    }
}

final class DiagnosticLogTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws { dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("diag-tests-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }
    func lines(_ l: DiagnosticLog) -> [[String: Any]] { l.flush(); return ([l.activeFile] + l.archives).flatMap { f -> [[String: Any]] in ((try? String(contentsOf: f)) ?? "").split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } } }

    func testRedactorHidesPathsEmailsAndSecretsButKeepsCorrelation() {
        let s = Redactor.redact("export /Volumes/Ext/Clienti/Nunta/IMG_0042.CR2 pentru ana.popescu@example.com token=abcd1234efgh serial: XYZ-123 cheie 0123456789abcdef0123456789abcdef0123")
        XCTAssertFalse(s.contains("Nunta")); XCTAssertFalse(s.contains("IMG_0042")); XCTAssertFalse(s.contains("example.com")); XCTAssertFalse(s.contains("abcd1234")); XCTAssertFalse(s.contains("XYZ-123")); XCTAssertFalse(s.contains("0123456789abcdef"))
        XCTAssertTrue(s.contains("media#") && s.contains(".cr2"))
        XCTAssertEqual(Redactor.redact("/Users/a/b/IMG_1.ARW"), Redactor.redact("/Users/a/b/IMG_1.ARW"))    // hash stabil
        XCTAssertNotEqual(Redactor.redact("/Users/a/b/IMG_1.ARW"), Redactor.redact("/Users/a/b/IMG_2.ARW"))
    }
    func testStructuredEntriesCarryRequiredFieldsAndLevelsFilter() throws {
        let l = DiagnosticLog(directory: dir, version: "0.2.0-dev", build: "abc123"); l.log(.debug, "t", "dbg"); l.log(.info, "decode", "job.start", "ok", job: "j1"); l.log(.error, "export", "fail", error: NSError(domain: "x", code: 7))
        let r = lines(l); XCTAssertEqual(r.count, 2)                                         // debug filtrat la nivelul implicit info
        for e in r { for k in ["ts", "level", "ver", "build", "platform", "sub", "event", "session"] { XCTAssertNotNil(e[k], k) } }
        XCTAssertTrue((r[0]["ts"] as! String).contains("+") || (r[0]["ts"] as! String).hasSuffix("Z")); XCTAssertEqual(r[1]["error_code"] as? Int, 7)
        l.enableDebug(minutes: 1); XCTAssertTrue(l.debugActive); l.log(.debug, "t", "dbg2"); XCTAssertEqual(lines(l).count, 3)
    }
    func testRotationHonorsSizeAndCount() {
        var c = DiagnosticLog.Config(); c.maxFileBytes = 2000; c.maxFiles = 3; let l = DiagnosticLog(directory: dir, config: c, version: "v", build: "b")
        for i in 0..<200 { l.log(.info, "s", "e\(i)", String(repeating: "x", count: 60)) }
        l.flush(); let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertLessThanOrEqual(files.filter { $0.hasPrefix("photoassist") }.count, 3)
        for f in files { let sz = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(f).path)[.size] as? NSNumber)?.intValue ?? 0; XCTAssertLessThan(sz, 2600) }
    }
    func testBrokenLoggerNeverBlocksOrChangesTheOperation() throws {
        let l = DiagnosticLog(directory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/x"), version: "v", build: "b")
        let r = l.timed("s", "op") { 42 }; XCTAssertEqual(r, 42)
        struct E: Error {}; XCTAssertThrowsError(try l.timed("s", "op2") { throw E() })      // eroarea operației se propagă neschimbată
    }
    func testConcurrentJobsAreCorrelatedByJobID() {
        let l = DiagnosticLog(directory: dir, version: "v", build: "b")
        DispatchQueue.concurrentPerform(iterations: 8) { i in let job = "job\(i)"; l.log(.info, "p", "start", job: job); l.log(.info, "p", "end", job: job, durationMs: Double(i)) }
        let r = lines(l); for i in 0..<8 { XCTAssertEqual(r.filter { ($0["job"] as? String) == "job\(i)" }.map { $0["event"] as! String }.sorted(), ["end", "start"]) }
    }
    func testDiagnosticExportContainsOnlyLogsAndManifestNoMedia() throws {
        let l = DiagnosticLog(directory: dir.appendingPathComponent("logs"), version: "0.2.0-dev", build: "abc"); l.log(.info, "x", "e", "/Volumes/E/IMG_9.CR2")
        let media = dir.appendingPathComponent("logs/IMG_9.CR2"); try Data([1, 2, 3]).write(to: media)      // un fișier media în folder NU trebuie să intre în pachet
        let z = try l.exportDiagnostics(to: dir.appendingPathComponent("diag.zip"), settings: ["engine": "own"], lastJobReport: "job a citit /Users/x/IMG_9.CR2")
        let u = dir.appendingPathComponent("unz"); let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); p.arguments = ["-x", "-k", z.path, u.path]; try p.run(); p.waitUntilExit()
        let all = (FileManager.default.enumerator(atPath: u.path)?.allObjects as? [String]) ?? []
        XCTAssertTrue(all.contains { $0.hasSuffix("manifest.json") }); XCTAssertTrue(all.contains { $0.hasSuffix("photoassist.log") }); XCTAssertFalse(all.contains { $0.hasSuffix("IMG_9.CR2") })
        let rep = all.first { $0.hasSuffix("last_job_report.txt") }.flatMap { try? String(contentsOf: u.appendingPathComponent($0)) } ?? ""; XCTAssertFalse(rep.contains("IMG_9"))
    }
}
