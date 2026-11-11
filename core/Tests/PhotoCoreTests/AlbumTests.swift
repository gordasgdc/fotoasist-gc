import XCTest
@testable import PhotoCore

final class AlbumTests: XCTestCase {
    func makeCatalog() throws -> (Catalog, URL, [PhotoRecord]) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("album-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); var e: [Inventory.Entry] = []; for i in 0..<5 { e.append(("/x/IMG_\(i).ARW", Int64(100 + i), Int64(1), "Cam", Date(timeIntervalSince1970: Double(1000 + i)))) }
        _ = try c.importFiles(e); return (c, dir, try c.photos())
    }
    func testAlbumLifecycleMultiMembershipAndPersistence() throws {
        let (c, dir, ph) = try makeCatalog(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = try c.createAlbum("Nuntă"), b = try c.createAlbum("Portrete"); XCTAssertThrowsError(try c.createAlbum("  "))
        try c.addToAlbum(a, photoIds: [ph[0].id, ph[1].id, ph[2].id]); try c.addToAlbum(b, photoIds: [ph[2].id, ph[3].id]); try c.addToAlbum(b, photoIds: [ph[2].id])   // duplicat ignorat
        XCTAssertEqual(try c.albums().map { "\($0.name):\($0.count)" }, ["Nuntă:3", "Portrete:2"]); XCTAssertEqual(Set(try c.albumIds(of: ph[2].id)), [a, b], "aceeași fotografie în mai multe albume")
        try c.renameAlbum(b, to: "Portrete 2026"); try c.removeFromAlbum(a, photoIds: [ph[1].id]); XCTAssertEqual(try c.albumPhotoIds(a), [ph[0].id, ph[2].id])
        let re = try Catalog(url: dir.appendingPathComponent("c.sqlite")); XCTAssertEqual(try re.albums().map { $0.name }, ["Nuntă", "Portrete 2026"], "persistă după redeschidere"); XCTAssertEqual(try re.albumPhotoIds(b), [ph[2].id, ph[3].id])
    }
    func testDeletingOrEmptyingAnAlbumNeverTouchesPhotosEditsOrDecisions() throws {
        let (c, dir, ph) = try makeCatalog(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = try c.createAlbum("Temp"); try c.addToAlbum(a, photoIds: [ph[0].id]); try c.setEdits(photoId: ph[0].id, json: "{\"exposure\":1}"); try c.setDecision(.keep, photoIds: [ph[0].id])
        try c.removeFromAlbum(a, photoIds: [ph[0].id]); XCTAssertEqual(try c.photos().count, 5); XCTAssertNotNil(try c.edits(photoId: ph[0].id))
        try c.addToAlbum(a, photoIds: [ph[0].id]); try c.deleteAlbum(a); XCTAssertEqual(try c.albums().count, 0); XCTAssertEqual(try c.photos().count, 5)
        XCTAssertEqual(try c.edits(photoId: ph[0].id), "{\"exposure\":1}", "editările rămân"); XCTAssertEqual(try c.photos().first { $0.id == ph[0].id }?.decision, .keep, "decizia rămâne")
    }
    func testSessionAlbumFilterAndTargets() throws {
        let (c, dir, ph) = try makeCatalog(); defer { try? FileManager.default.removeItem(at: dir) }; let s = try SelectionSession(catalog: c)
        let id = try s.createAlbum("A", addTargets: false); try c.addToAlbum(id, photoIds: [ph[1].id, ph[3].id]); try s.reload(); s.albumFilter = id
        XCTAssertEqual(s.visible.map { $0.id }, [ph[1].id, ph[3].id]); XCTAssertEqual(s.currentId.map { [ph[1].id, ph[3].id].contains($0) }, true)
        s.filter = .keep; XCTAssertTrue(s.visible.isEmpty, "filtrul de decizie se combină cu albumul"); s.filter = .all
        s.select(ph[3].id); let n = try s.createAlbum("B", addTargets: true); XCTAssertEqual(try c.albumPhotoIds(n), [ph[3].id], "ținta = cadrul curent")
        try s.deleteAlbum(id); XCTAssertNil(s.albumFilter, "albumul șters nu mai filtrează"); XCTAssertEqual(s.visible.count, 5)
    }
}

final class SelectionRestrictTests: XCTestCase {
    func testSelectionNeverKeepsHiddenPhotos() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("selr-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let cat = try Catalog(url: dir.appendingPathComponent("c.sqlite")); _ = try cat.importFiles([("/x/a.ARW", 1, 1, nil, nil), ("/x/b.ARW", 2, 1, nil, nil)])
        let s = try SelectionSession(catalog: cat); let ids = s.photos.map { $0.id }
        s.toggleSelected(ids[0]); s.toggleSelected(ids[1]); s.restrictSelection(to: [ids[1]])
        XCTAssertEqual(s.selectedIds, [ids[1]], "doar fotografiile vizibile rămân selectate")
    }
}

final class SelectionBatchTests: XCTestCase {
    func make() throws -> (Catalog, SelectionSession, [Int64], URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("selb-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); _ = try c.importFiles((0..<6).map { ("/x/IMG_\($0).ARW", Int64(10 + $0), Int64(1), nil, nil) })
        let s = try SelectionSession(catalog: c); return (c, s, s.photos.map { $0.id }, dir)
    }
    func testSelectAllVisibleRespectsFilterAndDeselect() throws {
        let (c, s, ids, dir) = try make(); defer { try? FileManager.default.removeItem(at: dir) }
        try c.setDecision(.keep, photoIds: [ids[0], ids[1]]); try s.reload()
        s.filter = .keep; s.selectAllVisible(); XCTAssertEqual(s.selectedIds, [ids[0], ids[1]], "doar vizibilele"); XCTAssertEqual(s.targetCount, 2)
        s.deselectAll(); XCTAssertTrue(s.selectedIds.isEmpty); XCTAssertEqual(s.targetCount, 1, "fără selecție ținta = cadrul curent")
    }
    func testFilterChangeDropsHiddenFromSelectionSoBatchActionsCannotHitThem() throws {
        let (c, s, ids, dir) = try make(); defer { try? FileManager.default.removeItem(at: dir) }
        try c.setDecision(.reject, photoIds: [ids[2]]); try s.reload()
        s.selectAllVisible(); XCTAssertEqual(s.selectedIds.count, 6); s.filter = .reject
        XCTAssertEqual(s.selectedIds, [ids[2]], "ce nu se vede iese din selecție"); try s.apply(.keep)
        XCTAssertEqual(try c.photos().filter { $0.decision == .keep }.map { $0.id }, [ids[2]], "doar fotografia vizibilă a fost schimbată")
        XCTAssertEqual(try c.photos().filter { $0.decision == .check }.count, 5, "cele ascunse n-au fost atinse")
    }
    func testMultiSelectModeNeedsNoModifierKeysAndCommandShiftStillWork() throws {
        let (_, s, ids, dir) = try make(); defer { try? FileManager.default.removeItem(at: dir) }
        s.tap(ids[1]); XCTAssertTrue(s.selectedIds.isEmpty, "clic simplu = fotografie curentă, nu selecție"); XCTAssertEqual(s.currentId, ids[1])
        s.multiSelect = true; s.tap(ids[2]); s.tap(ids[4]); XCTAssertEqual(s.selectedIds, [ids[2], ids[4]]); s.tap(ids[2]); XCTAssertEqual(s.selectedIds, [ids[4]], "al doilea clic scoate bifa")
        s.multiSelect = false; s.deselectAll(); s.tap(ids[3], command: true); s.tap(ids[5], command: true); XCTAssertEqual(s.selectedIds, [ids[3], ids[5]])
        s.select(ids[0]); s.tap(ids[2], shift: true); XCTAssertEqual(s.selectedIds, [ids[0], ids[1], ids[2]], "Shift = interval")
    }
    func testBatchDecisionMixAndAlbumRemovalNeverTouchDecisionsOrCatalog() throws {
        let (c, s, ids, dir) = try make(); defer { try? FileManager.default.removeItem(at: dir) }
        try c.setDecision(.keep, photoIds: [ids[0]]); try c.setDecision(.reject, photoIds: [ids[1]]); try s.reload()
        let a = try s.createAlbum("A", addTargets: false); try c.addToAlbum(a, photoIds: [ids[0], ids[1], ids[2]]); try s.reload()
        s.selectAllVisible(); let m = s.targetMix; XCTAssertEqual([m.keep, m.reject, m.check], [1, 1, 4])
        s.albumFilter = a; s.selectAllVisible(); XCTAssertEqual(s.targetCount, 3); try s.removeTargets(fromAlbum: a)
        XCTAssertEqual(try c.photos().count, 6, "«Scoate din album» nu scoate din catalog"); XCTAssertEqual(try c.photos().first { $0.id == ids[0] }?.decision, .keep, "decizia rămâne")
        XCTAssertEqual(try c.albumPhotoIds(a), [])
    }
}
