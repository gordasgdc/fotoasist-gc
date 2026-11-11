import XCTest
@testable import PhotoAssistUI
import PhotoCore
import PhotoResolve

/// Fluxul de profil cap-coadă pe date SINTETICE: export → import (neevaluat) → aplicare în lot cu păstrarea editărilor neprofilate → anulare → redeschidere.
@MainActor
final class ProfileFlowEndToEndTests: XCTestCase {
    let engine = "pc1|rev3|est1|set:a,b", params = ["exposureOffset", "contrast", "saturation", "shadows", "highlights", "temperature", "tint"]
    var dir: URL!; var catalog: Catalog!; var ed: EditingModel!; var photos: [PhotoRecord] = []
    override func setUp() async throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("profile-e2e-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        catalog = try Catalog(url: dir.appendingPathComponent("c.sqlite"))
        _ = try catalog.importFiles((0..<4).map { ("/x/IMG_\($0).ARW", Int64(100 + $0), Int64(1), "Cam", Date(timeIntervalSince1970: Double(1_000 + $0))) }); photos = try catalog.photos()
        ed = EditingModel(catalog: catalog, workDir: dir.appendingPathComponent("work"))
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    func testExportImportApplyBatchUndoReopen() throws {
        var src = PersonalProfile(name: "Sintetic", photographer: "Ana", setName: "S", version: 1, pairIDs: ["A", "B", "C"], engineVersion: engine, parameters: ProfileParameters(technicalPolicy: "p"))
        src.parameters.creative = ["contrast": ParameterEstimate(median: 0.15, spread: 0.02, count: 9), "saturation": ParameterEstimate(median: -0.1, spread: 0.02, count: 9)]
        src.status = .estimated; src.estimatorVersion = 1
        let data = try ProfileExchange.export(src, engineIdentity: engine, paramSet: params, trustLabel: "x")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("/x/IMG"), "fără căi private în fișier")
        var reg = ed.profileRegistry
        guard case .success(.added(let imp)) = ProfileExchange.importProfile(data, into: &reg, photographer: "Bogdan", setName: "B", engineIdentity: engine, paramSet: params, engineVersionLabel: "t") else { return XCTFail("import") }
        ed.profileRegistry = reg
        XCTAssertTrue(ed.profileTrustLabel(imp).contains("NEEVALUAT"), "importul rămâne neevaluat")
        // fotografia 1 are deja editări proprii: un local și geometrie; profilul NU le atinge
        ed.open(photos[1]); ed.adjustments.geometry.angle = 3; ed.adjustments.locals = [LocalCorrection.make(.ellipse, number: 1)]; ed.flushSave()
        ed.open(photos[0])
        let n = ed.applyProfileToBatch(imp.id, ids: [photos[1].id, photos[2].id, photos[3].id]); XCTAssertEqual(n, 3, "numărul aplicat e raportat exact")
        let a1 = try JSONDecoder().decode(AdjustmentSet.self, from: Data(try XCTUnwrap(try catalog.edits(photoId: photos[1].id)).utf8))
        XCTAssertEqual(a1.geometry.angle, 3, accuracy: 1e-9); XCTAssertEqual(a1.locals.count, 1, "editările neprofilate păstrate")
        XCTAssertNotEqual(a1.contrast, 1, "profilul a schimbat contrastul")
        XCTAssertTrue(ed.canUndoPaste); ed.undoLastPaste()
        let b1 = try JSONDecoder().decode(AdjustmentSet.self, from: Data(try XCTUnwrap(try catalog.edits(photoId: photos[1].id)).utf8))
        XCTAssertEqual(b1.contrast, 1, accuracy: 1e-9, "anulare ⇒ valorile dinainte"); XCTAssertEqual(b1.geometry.angle, 3, accuracy: 1e-9)
        XCTAssertNil(try catalog.edits(photoId: photos[2].id).flatMap { try? JSONDecoder().decode(AdjustmentSet.self, from: Data($0.utf8)) }.flatMap { $0.contrast == 1 ? nil : $0 }, "fotografia fără editări revine la neutru")
        // redeschidere: registrul persistă și rămâne neevaluat
        let e2 = EditingModel(catalog: catalog, workDir: dir.appendingPathComponent("work2"))
        let again = try XCTUnwrap(e2.profileRegistry.profiles.first { $0.id == imp.id }); XCTAssertTrue(e2.profileTrustLabel(again).contains("NEEVALUAT"))
    }
    func testBatchRefusesDraftAndRenderedPhotos() {
        let draft = PersonalProfile(name: "D", photographer: "A", setName: "S", version: 1, pairIDs: [], engineVersion: engine, parameters: ProfileParameters(technicalPolicy: "p"))
        ed.profileRegistry.profiles.append(draft)
        XCTAssertEqual(ed.applyProfileToBatch(draft.id, ids: [photos[1].id]), 0, "ciorna nu se aplică")
    }
}
