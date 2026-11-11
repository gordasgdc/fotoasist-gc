import XCTest
@testable import PhotoAssistUI
import PhotoCore

@MainActor
final class StorageHostTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("host-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }
    func store() -> StorageConfigStore { StorageConfigStore(defaults: UserDefaults(suiteName: "fa-host-\(UUID().uuidString)")!) }
    func model(_ h: AppHost) -> AppModel? { if case .ready(let m) = h.state { return m }; return nil }

    func testFirstRunChooseReopenMissingRecoverAndMigrate() async throws {
        let st = store(); let a = tmp.appendingPathComponent("A"), b = tmp.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        // 1. primul start: fără locație → alegere
        let h = AppHost(store: st, forceClient: true); guard case .needsSetup = h.state else { return XCTFail("așteptat needsSetup") }
        // 2. alegere → bibliotecă organizată în folderul ales
        h.choose(root: a); let m = try XCTUnwrap(model(h)); XCTAssertEqual(m.libraryDir.standardizedFileURL.path, StorageLayout.library(in: a).standardizedFileURL.path)
        XCTAssertEqual(st.location?.root, a.standardizedFileURL.path)
        _ = try m.catalog.importFiles([("/orig/x/IMG_1.ARW", 10, 1, "Cam", Date(timeIntervalSince1970: 1)), ("/orig/y/IMG_2.ARW", 11, 1, "Cam", Date(timeIntervalSince1970: 2))])
        let pid = try m.catalog.photos().first!.id; try m.catalog.setEdits(photoId: pid, json: "{\"x\":1}"); try m.catalog.setSession("export_folder", "/Volumes/Out/Lot1"); try m.catalog.setDecision(.keep, photoId: pid); try m.catalog.setSession("profile_registry", "{\"p\":1}"); let aid = try m.catalog.createAlbum("Lot"); try m.catalog.addToAlbum(aid, photoIds: [pid])
        // 3. redeschidere: aceeași locație, aceleași date
        let h2 = AppHost(store: st, forceClient: true); let m2 = try XCTUnwrap(model(h2)); XCTAssertEqual(try m2.catalog.photos().count, 2); XCTAssertEqual(try m2.catalog.edits(photoId: pid), "{\"x\":1}")
        // 4. disc dispărut în timpul lucrului: pauză controlată, fără scriere în altă parte
        let good = try XCTUnwrap(m2.storageLocation); var bad = good; bad.volumeUUID = "00000000-0000-0000-0000-00000000DEAD"; bad.volumeName = "DiscExtern"; m2.storageLocation = bad
        h2.check(); guard case .missing(let n, _) = try XCTUnwrap(m2.storageIssue) else { return XCTFail("așteptat missing") }; XCTAssertEqual(n, "DiscExtern"); XCTAssertTrue(m2.editing.storageBlocked)
        await m2.importFolder(tmp); if case .failed(let msg) = m2.phase { XCTAssertTrue(msg.contains("DiscExtern")) } else { XCTFail("importul trebuia refuzat") }
        // 5. revenire: biblioteca se redeschide, datele terminate rămân
        m2.storageLocation = good; h2.check(); let m3 = try XCTUnwrap(model(h2)); XCTAssertTrue(m3 !== m2, "model redeschis după revenire"); XCTAssertNil(m3.storageIssue); XCTAssertEqual(try m3.catalog.edits(photoId: pid), "{\"x\":1}")
        // 6. disc lipsă la pornire: starea „indisponibil”, nicio bibliotecă nouă creată
        let st2 = store(); st2.location = bad; let before = try FileManager.default.contentsOfDirectory(atPath: tmp.path).sorted()
        let h3 = AppHost(store: st2, forceClient: true); guard case .unavailable(let hh, let loc) = h3.state else { return XCTFail("așteptat unavailable") }; XCTAssertEqual(loc.volumeName, "DiscExtern"); XCTAssertTrue(hh.blocks)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tmp.path).sorted(), before, "fără fallback silențios")
        h3.chooseOther(); guard case .needsSetup = h3.state else { return XCTFail("fără ecran fără ieșire") }
        // 7. migrare: copiere → verificare → comutare; vechea locație rămâne; datele (decizii/reglaje/destinație export) se păstrează
        let rep = try await h2.migrate(toRoot: b, cancel: AppHost.Cancel(), progress: { _, _ in })
        let m4 = try XCTUnwrap(model(h2)); XCTAssertEqual(m4.libraryDir.standardizedFileURL.path, StorageLayout.library(in: b).standardizedFileURL.path); XCTAssertEqual(rep.destination.standardizedFileURL.path, m4.libraryDir.standardizedFileURL.path)
        XCTAssertEqual(try m4.catalog.photos().count, 2); XCTAssertEqual(try m4.catalog.edits(photoId: pid), "{\"x\":1}"); XCTAssertEqual(try m4.catalog.session("export_folder"), "/Volumes/Out/Lot1")
        let c4 = m4.catalog; let ph = try c4.photos().first { $0.id == pid }!; XCTAssertEqual(ph.path, "/orig/x/IMG_1.ARW", "legătura către original"); XCTAssertEqual(ph.decision, .keep); XCTAssertEqual(try c4.session("profile_registry"), "{\"p\":1}"); XCTAssertEqual(try c4.albums().count, 1); XCTAssertEqual(try c4.albumPhotoIds(aid), [pid]); XCTAssertEqual(try c4.contentDigest(), try m3.catalog.contentDigest(), "toate datele identice")
        XCTAssertTrue(FileManager.default.fileExists(atPath: StorageLayout.library(in: a).appendingPathComponent("catalog.sqlite").path), "locația veche rămâne neatinsă"); XCTAssertEqual(st.location?.root, b.standardizedFileURL.path)
        XCTAssertEqual(h2.lastMigratedFrom?.standardizedFileURL.path, StorageLayout.library(in: a).standardizedFileURL.path)
        let h5 = AppHost(store: st, forceClient: true); XCTAssertEqual(model(h5)?.libraryDir.standardizedFileURL.path, m4.libraryDir.standardizedFileURL.path, "alegerea migrată persistă la redeschidere")
    }
}
