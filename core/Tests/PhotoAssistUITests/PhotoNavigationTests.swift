import XCTest
import AppKit
@testable import PhotoAssistUI
import PhotoCore

@MainActor
final class PhotoNavigationTests: XCTestCase {
    func testStopsAtEdgesWithoutWrapAndPositionIsOneBased() {
        let ids: [Int64] = [10, 20, 30]
        XCTAssertNil(PhotoNav.target(ids: ids, current: 10, delta: -1)); XCTAssertEqual(PhotoNav.target(ids: ids, current: 10, delta: 1), 1)
        XCTAssertNil(PhotoNav.target(ids: ids, current: 30, delta: 1)); XCTAssertEqual(PhotoNav.target(ids: ids, current: 30, delta: -1), 1)
        XCTAssertNil(PhotoNav.target(ids: ids, current: 99, delta: 1), "fotografie din afara lotului ⇒ nimic"); XCTAssertEqual(PhotoNav.position(ids: ids, current: 20)?.index, 2); XCTAssertEqual(PhotoNav.position(ids: ids, current: 20)?.total, 3)
    }
    func testArrowMappingIgnoresModifiedKeys() {
        XCTAssertEqual(PhotoNav.delta(keyCode: 124, modifiers: []), 1); XCTAssertEqual(PhotoNav.delta(keyCode: 125, modifiers: []), 1)
        XCTAssertEqual(PhotoNav.delta(keyCode: 123, modifiers: []), -1); XCTAssertEqual(PhotoNav.delta(keyCode: 126, modifiers: []), -1)
        XCTAssertNil(PhotoNav.delta(keyCode: 124, modifiers: .command)); XCTAssertNil(PhotoNav.delta(keyCode: 124, modifiers: .option)); XCTAssertNil(PhotoNav.delta(keyCode: 36, modifiers: []))
    }
    func testNavigateUsesOnlyTheActiveBatchAndKeepsCurrentOnExit() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nav-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let cat = try Catalog(url: dir.appendingPathComponent("c.sqlite")); _ = try cat.importFiles((0..<5).map { ("/x/IMG_\($0).ARW", Int64(100 + $0), Int64(1), "Cam", Date(timeIntervalSince1970: Double(1_000 + $0))) })
        let all = try cat.photos(); let ed = EditingModel(catalog: cat, workDir: dir.appendingPathComponent("w"))
        let batch = [all[0], all[2], all[4]]                       // lot filtrat: 1., 3., 5.
        ed.open(batch[0]); XCTAssertFalse(ed.navigate(-1, in: batch), "prima: oprește")
        XCTAssertTrue(ed.navigate(1, in: batch)); XCTAssertEqual(ed.current?.id, all[2].id, "sare peste cadrele din afara lotului")
        XCTAssertTrue(ed.navigate(1, in: batch)); XCTAssertFalse(ed.navigate(1, in: batch), "ultima: oprește"); XCTAssertEqual(ed.current?.id, all[4].id)
        // valoarea ajunge pe fotografia de origine, nu pe următoarea
        ed.open(batch[0]); ed.adjustments.contrast = 1.4; ed.navigate(1, in: batch)
        XCTAssertEqual(ed.adjustments.contrast, 1, accuracy: 1e-9); ed.navigate(-1, in: batch); XCTAssertEqual(ed.adjustments.contrast, 1.4, accuracy: 1e-9)
    }

    func testNumericFieldIsCommittedBeforeThePhotoChangesAndZoomIsCarried() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nav2-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let cat = try Catalog(url: dir.appendingPathComponent("c.sqlite")); _ = try cat.importFiles((0..<3).map { ("/x/IMG_\($0).ARW", Int64(100 + $0), Int64(1), "Cam", Date(timeIntervalSince1970: Double(1_000 + $0))) })
        let all = try cat.photos(); let ed = EditingModel(catalog: cat, workDir: dir.appendingPathComponent("w")); ed.open(all[0])
        var seenOn: Int64?; let tok = NotificationCenter.default.addObserver(forName: .gdcCommitNumericFields, object: nil, queue: nil) { _ in seenOn = ed.current?.id }; defer { NotificationCenter.default.removeObserver(tok) }
        ed.viewer.canvasSize = CGSize(width: 800, height: 600); ed.viewer.fullSize = CGSize(width: 4000, height: 3000); ed.viewer.setScale(2)
        XCTAssertTrue(ed.navigate(1, in: all)); XCTAssertEqual(seenOn, all[0].id, "confirmarea se face cât fotografia de origine e încă curentă")
        XCTAssertEqual(ed.viewer.carriedZoom ?? 0, 2, accuracy: 1e-9); XCTAssertTrue(ed.viewer.isFit, "până se încarcă imaginea nouă: Potrivit")
        ed.viewer.fullSize = CGSize(width: 4000, height: 3000); ed.viewer.applyCarriedZoom(); XCTAssertFalse(ed.viewer.isFit); XCTAssertEqual(ed.viewer.scale, 2, accuracy: 1e-9); XCTAssertEqual(ed.viewer.offset, .zero)
        ed.viewer.setFit(); XCTAssertTrue(ed.navigate(1, in: all)); XCTAssertNil(ed.viewer.carriedZoom, "Potrivit rămâne Potrivit")
    }
}
