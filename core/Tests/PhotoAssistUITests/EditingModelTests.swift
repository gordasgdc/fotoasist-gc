import XCTest
@testable import PhotoAssistUI
import PhotoCore
import PhotoResolve

@MainActor
final class EditingModelTests: XCTestCase {
    var dir: URL!; var catalog: Catalog!; var ed: EditingModel!; var photos: [PhotoRecord] = []
    override func setUp() async throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("editing-tests-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        catalog = try Catalog(url: dir.appendingPathComponent("c.sqlite"))
        var e: [Inventory.Entry] = []; for i in 0..<4 { e.append(("/x/IMG_\(i).ARW", Int64(100 + i), Int64(1), "Cam", Date(timeIntervalSince1970: Double(1_000 + i)))) }
        _ = try catalog.importFiles(e); photos = try catalog.photos(); ed = EditingModel(catalog: catalog, workDir: dir.appendingPathComponent("work"))
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    func testOpeningAPhotoNeverAppliesExposureOrSuggestion() {
        ed.open(photos[0]); XCTAssertTrue(ed.adjustments.isNeutral); XCTAssertEqual(ed.adjustments.exposure, 0); XCTAssertFalse(ed.adjustments.exposureAuto)
    }
    /// Protecția editărilor vechi: actualizarea dezvoltării RAW (3:2 → 4:3) e refuzată cât există editări legate de pozițiile cadrului vechi; fără ele merge, păstrează compensarea aleasă și e un singur pas de anulare; «Resetează tot» NU o schimbă în tăcere.
    func testRawDevelopmentUpdateIsBlockedByFrameBoundEditsAndResetKeepsRevision() {
        ed.open(photos[0]); ed.adjustments.rawDev = .legacy
        var spot = RetouchSpot(); spot.mode = .clone; spot.x = 0.4; spot.y = 0.4; ed.adjustments.retouch = [spot]
        XCTAssertFalse(ed.rawUpdateBlockers().isEmpty); ed.updateRawDevelopment(); XCTAssertTrue(ed.adjustments.rawDev.isLegacyDecode)   // refuzat
        ed.adjustments.retouch = []; ed.adjustments.geometry.angle = 2; XCTAssertFalse(ed.rawUpdateBlockers().isEmpty)
        ed.adjustments.geometry = Geometry(); XCTAssertTrue(ed.rawUpdateBlockers().isEmpty)
        ed.adjustments.rawDev.baseline = .manual; ed.adjustments.rawDev.manualEV = 0.7
        ed.updateRawDevelopment(); XCTAssertFalse(ed.adjustments.rawDev.isLegacyDecode); XCTAssertEqual(ed.adjustments.rawDev.baseline, .manual); XCTAssertEqual(ed.adjustments.rawDev.manualEV, 0.7)
        ed.undoLastReset(); XCTAssertTrue(ed.adjustments.rawDev.isLegacyDecode)                                          // anulabil
        ed.resetAdjustments(); XCTAssertTrue(ed.adjustments.rawDev.isLegacyDecode)                                      // resetarea nu schimbă dezvoltarea în tăcere
    }
    func testApprovalIsInvalidatedWhenAdjustmentsChange() {
        ed.open(photos[0]); ed.toggleApproved(); XCTAssertTrue(ed.isApproved(photos[0].id)); XCTAssertEqual(ed.approvalState(photos[0].id), .approved)
        ed.adjustments.contrast = 1.2
        XCTAssertFalse(ed.isApproved(photos[0].id)); XCTAssertEqual(ed.approvalState(photos[0].id), .none); XCTAssertFalse(ed.approvalNote.isEmpty)
        ed.adjustments.contrast = 1                                                           // revenirea la valorile vechi NU reînvie aprobarea
        XCTAssertFalse(ed.isApproved(photos[0].id))
    }
    func testApprovalSurvivesReopenOnlyWithSameAdjustments() throws {
        ed.open(photos[0]); ed.adjustments.exposure = 1.5; ed.toggleApproved(); ed.flushSave()
        let e2 = EditingModel(catalog: catalog, workDir: dir.appendingPathComponent("work")); e2.open(photos[0])
        XCTAssertTrue(e2.isApproved(photos[0].id)); XCTAssertEqual(e2.adjustments.exposure, 1.5)
        // reglajele salvate se schimbă în afara căii UI (ex. alt proces): aprobarea devine „anulată” la verificare
        var a = e2.adjustments; a.exposure = 2.0; try catalog.setEdits(photoId: photos[0].id, json: String(data: JSONEncoder().encode(a), encoding: .utf8)!)
        let e3 = EditingModel(catalog: catalog, workDir: dir.appendingPathComponent("work")); XCTAssertEqual(e3.approvalState(photos[0].id), .invalidated); XCTAssertFalse(e3.isApproved(photos[0].id))
    }
    func testExportScopesNeverSubstituteOthers() {
        let q = photos
        ed.exportScope = .approved; XCTAssertTrue(ed.exportTargets(q).isEmpty)                  // niciun fallback pe toată coada
        ed.exportScope = .current; XCTAssertTrue(ed.exportTargets(q).isEmpty)                   // nicio fotografie deschisă
        ed.exportScope = .queue; XCTAssertEqual(ed.exportTargets(q).count, 4)
        ed.open(photos[1]); ed.toggleApproved(); ed.open(photos[2])
        ed.exportScope = .approved; XCTAssertEqual(ed.exportTargets(q).map { $0.id }, [photos[1].id])
        ed.exportScope = .current; XCTAssertEqual(ed.exportTargets(q).map { $0.id }, [photos[2].id])
    }
    func testAutoModeIsExplicitAndSeparatesEstimateFromCreativeOffset() {
        ed.open(photos[0]); ed.suggestion = ExposureSuggestionFixture.make(stops: 2.0)
        ed.setAutoMode(true); ed.adjustments.autoOffset = -0.5
        XCTAssertEqual(ed.adjustments.effectiveExposure(estimate: 2.0), 1.5); XCTAssertEqual(ed.adjustments.exposure, 0)   // alegerea manuală rămâne separată
        ed.applySuggestion(); XCTAssertFalse(ed.adjustments.exposureAuto); XCTAssertEqual(ed.adjustments.exposure, 2.0)    // „Aplică” = valoare manuală explicită
    }
    func testEditsAndApprovalsSavedUnderAnOlderEngineAreFlaggedAndInvalidatedButKeepTheirValues() throws {
        // simulează o sesiune dev.4: reglaje fără revizie (0) + aprobare cu amprenta veche (fără sufixul de revizie)
        var a = AdjustmentSet(); a.exposure = 1.0; a.shadows = 0.5
        var j = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]; j.removeValue(forKey: "engineRevision")
        try catalog.setEdits(photoId: photos[0].id, json: String(data: JSONSerialization.data(withJSONObject: j), encoding: .utf8)!)
        try catalog.setSession("approved_v2", String(data: JSONEncoder().encode([String(photos[0].id): a.fingerprint + "|gdcDRTNatural"]), encoding: .utf8)!)
        let e = EditingModel(catalog: catalog, workDir: dir.appendingPathComponent("work2"))
        XCTAssertEqual(e.approvalState(photos[0].id), .invalidated)                                  // aprobarea veche nu rămâne valabilă după schimbarea motorului
        e.open(photos[0]); XCTAssertEqual(e.adjustments.exposure, 1.0); XCTAssertEqual(e.adjustments.shadows, 0.5); XCTAssertFalse(e.legacyNotice.isEmpty)   // valorile se păstrează, notificarea apare
        e.flushSave(); let again = EditingModel(catalog: catalog, workDir: dir.appendingPathComponent("work3")); again.open(photos[0]); XCTAssertFalse(again.legacyNotice.isEmpty)   // simpla vizualizare NU stampilează revizia curentă
        e.adjustments.contrast = 1.1; XCTAssertTrue(e.legacyNotice.isEmpty)                         // o modificare nouă pornește din motorul curent
    }
    func testParameterResetIsUndoableAffectsOnlyThatParameterAndKeepsApprovalSemantics() {
        ed.open(photos[0]); ed.adjustments.contrast = 1.3; ed.adjustments.exposure = 0.7; ed.adjustments.saturation = 1.2; ed.toggleApproved(); XCTAssertTrue(ed.isApproved(photos[0].id))
        ed.registerReset("Contrast"); ed.adjustments.contrast = 1                                    // neutrul contrastului = 1 (nu 0), ca în rândul de slider
        XCTAssertEqual(ed.adjustments.contrast, 1); XCTAssertEqual(ed.adjustments.exposure, 0.7); XCTAssertEqual(ed.adjustments.saturation, 1.2)   // doar acel parametru
        XCTAssertNotNil(ed.lastReset); XCTAssertFalse(ed.isApproved(photos[0].id))                   // mecanismul existent: aprobarea se anulează la schimbare
        ed.undoLastReset(); XCTAssertEqual(ed.adjustments.contrast, 1.3); XCTAssertEqual(ed.adjustments.exposure, 0.7); XCTAssertNil(ed.lastReset)
        XCTAssertFalse(ed.isApproved(photos[0].id))                                                   // anularea resetării nu reînvie aprobarea (ca revenirea manuală)
    }
    func testSectionResetTouchesOnlyItsGroupAndResetAllIsUndoable() {
        ed.open(photos[0]); ed.adjustments.exposure = 0.5; ed.adjustments.shadows = 0.4; ed.adjustments.highlights = -0.3; ed.adjustments.contrast = 1.2; ed.adjustments.temperature = 20; ed.adjustments.saturation = 0.8
        ed.resetSection("Lumină și contrast") { $0.resetLightGroup() }
        XCTAssertEqual(ed.adjustments.shadows, 0); XCTAssertEqual(ed.adjustments.highlights, 0); XCTAssertEqual(ed.adjustments.contrast, 1)
        XCTAssertEqual(ed.adjustments.exposure, 0.5); XCTAssertEqual(ed.adjustments.temperature, 20); XCTAssertEqual(ed.adjustments.saturation, 0.8)   // celelalte secțiuni neatinse
        ed.undoLastReset(); XCTAssertEqual(ed.adjustments.shadows, 0.4); XCTAssertEqual(ed.adjustments.contrast, 1.2)
        ed.resetAdjustments(); XCTAssertTrue(ed.adjustments.isNeutral); ed.undoLastReset(); XCTAssertEqual(ed.adjustments.exposure, 0.5); XCTAssertEqual(ed.adjustments.temperature, 20)
        XCTAssertTrue(AdjustmentSet().colourGroupIsNeutral && AdjustmentSet().lightGroupIsNeutral && AdjustmentSet().exposureGroupIsNeutral)
    }
    func testLocalAdjustmentResetKeepsZoneAndGuidesAreIndependentFromTheCorrectionAndThePipeline() {
        ed.open(photos[0]); ed.addLocal(.ellipse); let id = ed.selectedLocal!; let i = ed.localIndex(id)!
        ed.adjustments.locals[i].exposure = -0.8; ed.adjustments.locals[i].contrast = 1.2; ed.adjustments.locals[i].x1 = 0.31; ed.adjustments.locals[i].invert = true
        let fp = ed.adjustments.fingerprint
        ed.guidesHidden = true; ed.showZone = false; ed.guidesHidden = false; ed.guidesHidden = true
        XCTAssertEqual(ed.adjustments.fingerprint, fp)                                                // ghidajele nu intră în procesare, cache sau export
        XCTAssertTrue(ed.adjustments.locals[i].enabled); XCTAssertEqual(ed.adjustments.locals.filter { $0.enabled && !$0.adjustmentIsNeutral }.count, 1)   // efectul rămâne aplicat cu ghidajele ascunse
        ed.resetLocalAdjustments(id)
        XCTAssertTrue(ed.adjustments.locals[i].adjustmentIsNeutral); XCTAssertEqual(ed.adjustments.locals[i].x1, 0.31); XCTAssertTrue(ed.adjustments.locals[i].invert)   // zona și inversarea rămân
        ed.undoLastReset(); XCTAssertEqual(ed.adjustments.locals[i].exposure, -0.8)
        ed.addLocal(.gradient); XCTAssertFalse(ed.guidesHidden)                                      // o corecție nouă se definește pe fotografie
    }
    // MARK: familii de lucru în model (selector, sesiune, aprobări, anulare)
    func testFamilyChangeIsUndoableInvalidatesApprovalAndSurvivesReopen() {
        ed.open(photos[0]); ed.adjustments.exposure = 0.7; ed.toggleApproved(); XCTAssertTrue(ed.isApproved(photos[0].id))
        ed.setFamily(.awg4); XCTAssertEqual(ed.adjustments.family, .awg4); XCTAssertEqual(ed.adjustments.exposure, 0.7, "valorile fotografului rămân"); XCTAssertFalse(ed.isApproved(photos[0].id), "aprobarea făcută în altă familie e anulată")
        XCTAssertNotNil(ed.lastReset); ed.undoLastReset(); XCTAssertEqual(ed.adjustments.family, .dwg); XCTAssertEqual(ed.adjustments.exposure, 0.7)
        ed.setFamily(.acesAP1); ed.flushSave()
        let e2 = EditingModel(catalog: catalog, workDir: dir.appendingPathComponent("work")); e2.open(photos[0]); XCTAssertEqual(e2.adjustments.family, .acesAP1, "familia se salvează cu sesiunea")
    }
    func testResetAllKeepsFamilyAndNewPhotosStartInTheSessionFamily() {
        ed.open(photos[0]); ed.setFamily(.awg3); ed.adjustments.contrast = 1.3; ed.resetAdjustments()
        XCTAssertEqual(ed.adjustments.family, .awg3, "„Resetează tot” nu schimbă familia"); XCTAssertTrue(ed.adjustments.isNeutral)
        ed.open(photos[2]); XCTAssertEqual(ed.adjustments.family, .awg3, "fotografie fără reglaje salvate pornește în familia aleasă în sesiune")
        ed.open(photos[0]); XCTAssertEqual(ed.adjustments.family, .awg3)
        XCTAssertEqual(ed.sessionFamily, .awg3)
    }
    // MARK: măști precise (construire, adaugă/scade, contur, pensulă, anulare/refacere, persistență)
    func testMaskBuildingPathBrushSubtractUndoRedoAndReopen() {
        ed.open(photos[0]); ed.addLocal(.path); XCTAssertEqual(ed.maskTool, .drawPath)
        ed.addPathPoint(0.2, 0.2); ed.addPathPoint(0.8, 0.2); XCTAssertFalse(ed.adjustments.locals[0].components[0].closed); ed.closePath(); XCTAssertFalse(ed.adjustments.locals[0].components[0].closed, "sub 3 puncte nu se poate închide")
        ed.addPathPoint(0.8, 0.8); ed.addPathPoint(0.2, 0.8); ed.closePath(); XCTAssertTrue(ed.adjustments.locals[0].components[0].closed); XCTAssertEqual(ed.maskTool, .select)
        ed.adjustments.locals[0].exposure = 0.5
        ed.addComponent(.ellipse, op: .subtract); XCTAssertEqual(ed.adjustments.locals[0].components.count, 2); XCTAssertEqual(ed.adjustments.locals[0].components[1].op, .subtract)
        ed.addComponent(.brush, op: .subtract); XCTAssertEqual(ed.maskTool, .brushErase); ed.addBrushStroke([(0.4, 0.4), (0.5, 0.5)], erase: true); XCTAssertEqual(ed.adjustments.locals[0].components.count, 3); XCTAssertEqual(ed.adjustments.locals[0].components[2].op, .subtract)
        let before = ed.adjustments.locals[0].components.count; ed.insertPathPoint(near: 0.5, 0.2, sx: 1000, sy: 800, maxDistance: 12); ed.selectComponent(ed.adjustments.locals[0].components[0].id)
        ed.insertPathPoint(near: 0.5, 0.2, sx: 1000, sy: 800, maxDistance: 12); XCTAssertEqual(ed.adjustments.locals[0].components[0].points.count, 5, "dublu-click pe segment adaugă un punct"); XCTAssertEqual(ed.selectedPoint, 1)
        ed.toggleSmooth(1); XCTAssertTrue(ed.adjustments.locals[0].components[0].points[1].smooth); ed.deleteSelectedPoint(); XCTAssertEqual(ed.adjustments.locals[0].components[0].points.count, 4)
        XCTAssertEqual(before, 3)
        // anulare / refacere pas cu pas
        ed.undoMaskEdit(); XCTAssertEqual(ed.adjustments.locals[0].components[0].points.count, 5); ed.undoMaskEdit(); XCTAssertFalse(ed.adjustments.locals[0].components[0].points[1].smooth)
        ed.redoMaskEdit(); XCTAssertTrue(ed.adjustments.locals[0].components[0].points[1].smooth); XCTAssertFalse(ed.maskRedo.isEmpty)
        ed.deleteComponent(ed.adjustments.locals[0].components[2].id); XCTAssertEqual(ed.adjustments.locals[0].components.count, 2); ed.undoMaskEdit(); XCTAssertEqual(ed.adjustments.locals[0].components.count, 3, "ștergerea unei componente se poate anula")
        // masca se salvează și se redeschide cu toate componentele
        ed.flushSave(); let e2 = EditingModel(catalog: catalog, workDir: dir.appendingPathComponent("work")); e2.open(photos[0])
        XCTAssertEqual(e2.adjustments.locals[0].components.count, 3); XCTAssertEqual(e2.adjustments.locals[0].components[0].points.count, 5); XCTAssertEqual(e2.adjustments.fingerprint, ed.adjustments.fingerprint)
    }
    func testBrushOnEmptyBaseFillsItAndEraseNeverStartsAMask() {
        ed.open(photos[0]); ed.addLocal(.brush); XCTAssertEqual(ed.maskTool, .brushAdd); ed.brushRadius = 0.07; ed.addBrushStroke([(0.3, 0.3), (0.4, 0.35)], erase: false)
        XCTAssertEqual(ed.adjustments.locals[0].components.count, 1); XCTAssertEqual(ed.adjustments.locals[0].components[0].points.count, 2); XCTAssertEqual(ed.adjustments.locals[0].components[0].radius, 0.07)
        ed.addBrushStroke([(0.6, 0.6)], erase: false); XCTAssertEqual(ed.adjustments.locals[0].components.count, 2, "a doua tușă = componentă nouă, adaugă"); ed.addBrushStroke([(0.6, 0.6)], erase: true); XCTAssertEqual(ed.adjustments.locals[0].components[2].op, .subtract)
    }
    func testMaskEditsInvalidateApprovalAndKeepCorrectionActiveWhenGuidesHidden() {
        ed.open(photos[0]); ed.addLocal(.ellipse); ed.adjustments.locals[0].exposure = 0.5; ed.toggleApproved(); XCTAssertTrue(ed.isApproved(photos[0].id))
        ed.addComponent(.ellipse, op: .subtract); XCTAssertFalse(ed.isApproved(photos[0].id), "masca face parte din aprobare")
        ed.guidesHidden = true; XCTAssertTrue(ed.adjustments.locals[0].isActiveLocal, "ghidajele ascunse nu opresc corecția"); XCTAssertEqual(ed.adjustments.locals[0].components.count, 2)
    }

    // MARK: încheierea uneltelor (Gata / Editează decuparea / ghidaje ascunse) — logica comună
    func testFinishKeepsResultsHidesOnlyToolGuidesAndGuidesVisibilityIsSeparate() {
        ed.open(photos[0]); ed.selectTool(.geometry); ed.geometryMode = .crop; ed.adjustments.geometry.angle = 3; ed.adjustments.geometry.crop = CropRect(x: 0.1, y: 0.1, w: 0.7, h: 0.8)
        var l = LocalCorrection.make(.ellipse, number: 1); l.exposure = 0.5; ed.adjustments.locals = [l]
        let before = ed.adjustments; ed.guidesHidden = true; XCTAssertEqual(ed.adjustments, before, "ascunderea ghidajelor nu schimbă rezultatul"); XCTAssertEqual(ed.geometryMode, .crop, "unealta rămâne în editare, ghidajele sunt doar ascunse"); ed.guidesHidden = false
        ed.finishEditing(); XCTAssertEqual(ed.geometryMode, .none); XCTAssertEqual(ed.adjustments, before, "Gata nu resetează crop-ul, rotația sau măștile")
        ed.editCrop(); XCTAssertEqual(ed.geometryMode, .crop); XCTAssertEqual(ed.adjustments.geometry.crop, CropRect(x: 0.1, y: 0.1, w: 0.7, h: 0.8), "cadrul se regăsește"); XCTAssertFalse(ed.guidesHidden)
        ed.panels.collapseAll(); XCTAssertEqual(ed.adjustments, before, "plierea panoului nu schimbă procesarea")
        ed.selectTool(.masks); XCTAssertEqual(ed.geometryMode, .none, "schimbarea uneltei încheie interacțiunea precedentă"); XCTAssertEqual(ed.adjustments.geometry.angle, 3)
    }
    func testUnfinishedPathIsClosedOrCancelledExplicitlyOnFinish() {
        ed.open(photos[0]); ed.addLocal(.ellipse); ed.adjustments.locals[0].exposure = 0.4; ed.selectTool(.masks); ed.addComponent(.path, op: .add)
        ed.addPathPoint(0.2, 0.2); ed.addPathPoint(0.8, 0.2); ed.addPathPoint(0.5, 0.8); XCTAssertEqual(ed.maskTool, .drawPath)
        let note = ed.finishEditing(); XCTAssertNotNil(note); XCTAssertTrue(note!.contains("închis")); XCTAssertTrue(ed.adjustments.locals[0].components[1].closed, "contur cu ≥ 3 puncte se închide")
        ed.addComponent(.path, op: .subtract); ed.addPathPoint(0.1, 0.1); ed.addPathPoint(0.2, 0.2); let n2 = ed.finishEditing(); XCTAssertTrue(n2?.contains("anulat") == true); XCTAssertEqual(ed.adjustments.locals[0].components.count, 2, "forma neterminată (<3 puncte) se anulează, cu mesaj"); XCTAssertNotNil(ed.lastReset, "anulabil")
    }

    func testTextScalePreferenceIsPersistentAndScalesFontAndControlSizes() {
        let saved = Theme.level; defer { Theme.level = saved }
        Theme.level = 0; XCTAssertEqual(Theme.px(54), 54); Theme.level = 2; XCTAssertGreaterThan(Theme.px(54), 54 * 1.3); XCTAssertEqual(Theme.level, 2, "persistent (UserDefaults)")
        XCTAssertEqual(Theme.scaleOptions.map { $0.label }, ["Normal", "Mărit", "Mare"])
    }
    func testCopyPasteToSeveralPhotosByCategoryWithUndoAndReopen() throws {
        ed.open(photos[0]); ed.adjustments.contrast = 1.3; ed.adjustments.saturation = 1.2; ed.adjustments.exposure = 0.7; ed.adjustments.geometry.angle = 5; ed.flushSave(); ed.copyAdjustments()
        ed.open(photos[3]); ed.adjustments.geometry.angle = -2; ed.flushSave()
        let r = ed.pasteAdjustments([.basic], to: [photos[1].id, photos[2].id, photos[3].id]); XCTAssertEqual(r.applied, 3); XCTAssertEqual(r.skipped, 0)
        XCTAssertEqual(ed.adjustments.contrast, 1.3, accuracy: 1e-9); XCTAssertEqual(ed.adjustments.saturation, 1.2, accuracy: 1e-9); XCTAssertEqual(ed.adjustments.geometry.angle, -2, accuracy: 1e-9, "geometria nu e în categoria lipită")
        let j = try XCTUnwrap(try catalog.edits(photoId: photos[1].id)); let a1 = try JSONDecoder().decode(AdjustmentSet.self, from: Data(j.utf8))
        XCTAssertEqual(a1.saturation, 1.2, accuracy: 1e-9); XCTAssertEqual(a1.contrast, 1.3, accuracy: 1e-9); XCTAssertEqual(a1.geometry.angle, 0, accuracy: 1e-9)
        XCTAssertTrue(ed.canUndoPaste); ed.undoLastPaste()
        XCTAssertEqual(ed.adjustments.saturation, 1, accuracy: 1e-9, "fotografia curentă revine la starea de dinainte"); XCTAssertEqual(ed.adjustments.geometry.angle, -2, accuracy: 1e-9)
        let j2 = try XCTUnwrap(try catalog.edits(photoId: photos[1].id)); XCTAssertEqual(try JSONDecoder().decode(AdjustmentSet.self, from: Data(j2.utf8)).saturation, 1, accuracy: 1e-9)
        XCTAssertFalse(ed.canUndoPaste)
    }
}
import PhotoRaw
enum ExposureSuggestionFixture { static func make(stops: Double) -> ExposureSuggestion { ExposureSuggestion(stops: stops, medianToGrey: stops, highlightAnchor: stops, median: 0.01, p99: 0.5, p995: 0.6, lowKeyWarning: false, sceneHint: "intermediar") } 
}
