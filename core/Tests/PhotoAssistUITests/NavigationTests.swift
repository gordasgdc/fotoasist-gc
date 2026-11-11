import XCTest
import PhotoAccess
@testable import PhotoAssistUI
import PhotoCore
import PhotoResolve

@MainActor
final class NavigationTests: XCTestCase {
    func testStagesAreReachableWithoutLosingStateAndEditScopeIsExplicitAndPersistent() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nav-\(UUID().uuidString)"); defer { try? FileManager.default.removeItem(at: dir) }
        let m = try AppModel(libraryDir: dir, policy: DevOpenPolicy()); XCTAssertTrue(m.canOpen(.imp)); XCTAssertFalse(m.canOpen(.selection), "fără fotografii nu există selecție"); XCTAssertFalse(m.canOpen(.style))
        var e: [Inventory.Entry] = []; for i in 0..<4 { e.append(("/x/IMG_\(i).ARW", Int64(100 + i), Int64(1), "Cam", Date(timeIntervalSince1970: Double(1000 + i)))) }
        _ = try m.catalog.importFiles(e); try m.session.reload(); XCTAssertTrue(m.canOpen(.selection)); XCTAssertFalse(m.canOpen(.style), "fără coadă de editare nu se intră în editare")
        let ids = m.session.photos.map { $0.id }; m.session.filter = .check; m.session.select(ids[2])
        m.proceedToEditing(ids: [ids[2], ids[3]], label: "selecția (2)"); XCTAssertEqual(m.step, .style); XCTAssertEqual(m.editQueue.map { $0.id }, [ids[2], ids[3]])
        m.editing.open(m.editQueue[0]); m.editing.adjustments.exposure = 0.7; var l = LocalCorrection.make(.ellipse, number: 1); l.exposure = 0.5; m.editing.adjustments.locals = [l]
        m.navigate(to: .selection); XCTAssertEqual(m.step, .selection); XCTAssertEqual(m.session.filter, .check, "filtrul se păstrează"); XCTAssertEqual(m.session.currentId, ids[2], "poziția se păstrează")
        m.navigate(to: .imp); XCTAssertEqual(m.step, .imp); m.navigate(to: .style); XCTAssertEqual(m.step, .style)
        XCTAssertEqual(m.editing.adjustments.exposure, 0.7, "reglajul rămâne"); XCTAssertEqual(m.editing.adjustments.locals.count, 1, "masca rămâne"); XCTAssertEqual(m.editQueue.count, 2, "coada nu se înlocuiește în tăcere")
        XCTAssertEqual(m.editing.current?.id, ids[2])
        let again = try AppModel(libraryDir: dir, policy: DevOpenPolicy()); XCTAssertEqual(again.editQueue.map { $0.id }, [ids[2], ids[3]], "coada explicită supraviețuiește redeschiderii"); XCTAssertEqual(again.step, .style)
        let saved = try again.catalog.edits(photoId: ids[2]); XCTAssertNotNil(saved, "reglajele și masca s-au salvat la navigare")
    }
}
