import XCTest
import AppKit
@testable import PhotoAssistUI
import PhotoCore
import PhotoResolve
import PhotoAccess

@MainActor
final class WorkspaceDefaultsTests: XCTestCase {
    var dir: URL!; var catalog: Catalog!; var ed: EditingModel!; var photos: [PhotoRecord] = []
    override func setUp() async throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ws-tests-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        catalog = try Catalog(url: dir.appendingPathComponent("c.sqlite"))
        _ = try catalog.importFiles((0..<2).map { ("/x/IMG_\($0).ARW", Int64(100 + $0), Int64(1), "Cam", Date(timeIntervalSince1970: Double(1_000 + $0))) }); photos = try catalog.photos()
        ed = EditingModel(catalog: catalog, workDir: dir.appendingPathComponent("work"))
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    /// Fotografie nouă: reglaje neutre, nimic automat, efecte/instrumente/chart/locale oprite, analiză oprită; traseul tehnic (familie, DRT) rămâne.
    func testFreshPhotoStartsNeutralWithOptionalModulesOff() {
        ed.open(photos[0]); let a = ed.adjustments
        XCTAssertTrue(a.isNeutral); XCTAssertFalse(a.exposureAuto); XCTAssertEqual(a.exposure, 0)
        XCTAssertEqual(a.disabledModules, Set(AdjustmentSet.optionalModules), "efectele opționale pornesc DEZACTIVATE (D-WS-2)")
        for t in ["exposure", "light", "colour", "geometry"] { XCTAssertTrue(a.isModuleEnabled(t), "modulul tehnic/de bază \(t) rămâne activ") }
        XCTAssertNil(a.chart); XCTAssertTrue(a.locals.isEmpty); XCTAssertTrue(a.effects.isNeutral); XCTAssertTrue(a.tools.isNeutral)
        XCTAssertEqual(ed.analysisMode, .off); XCTAssertFalse(ed.loupeOn); XCTAssertTrue(ed.floating.detached.isEmpty)
        XCTAssertEqual(a.family, .dwg); XCTAssertEqual(a.drtProfile, 0)
    }
    /// D-WS-2: modificarea deliberată activează modulul (cu mesaj + Anulează); deschiderea panoului/comutarea altor module nu; dezactivarea păstrează valorile; fotografia deja editată nu se resetează.
    func testOptionalModuleActivatesOnDeliberateEditOnly() {
        ed.open(photos[0])
        XCTAssertFalse(ed.adjustments.isModuleEnabled("grain")); XCTAssertEqual(ed.adjustments.effective.effects.grainAmount, 0)
        ed.adjustments.exposure = 0.5                                              // modul de bază: nu activează nimic opțional
        XCTAssertFalse(ed.adjustments.isModuleEnabled("grain")); XCTAssertFalse(ed.adjustments.isModuleEnabled("film"))
        ed.adjustments.effects.grainAmount = 30                                    // modificare deliberată
        XCTAssertTrue(ed.adjustments.isModuleEnabled("grain")); XCTAssertEqual(ed.adjustments.effective.effects.grainAmount, 30)
        XCTAssertFalse(ed.adjustments.isModuleEnabled("film"), "doar modulul atins se activează")
        XCTAssertNotNil(ed.lastReset)
        ed.adjustments.effects.grainAmount = 40                                    // încă o tragere: mesajul rămâne
        XCTAssertNotNil(ed.lastReset)
        ed.undoLastReset()                                                         // Anulează: starea dinainte (modul oprit, valoare neschimbată)
        XCTAssertFalse(ed.adjustments.isModuleEnabled("grain")); XCTAssertEqual(ed.adjustments.effects.grainAmount, 0); XCTAssertEqual(ed.adjustments.exposure, 0.5)
        ed.adjustments.effects.grainAmount = 25; XCTAssertTrue(ed.adjustments.isModuleEnabled("grain"))
        ed.adjustments.disabledModules.insert("grain")                             // dezactivare manuală: valorile rămân
        XCTAssertEqual(ed.adjustments.effects.grainAmount, 25); XCTAssertEqual(ed.adjustments.effective.effects.grainAmount, 0)
        ed.adjustments.disabledModules.remove("grain"); XCTAssertEqual(ed.adjustments.effective.effects.grainAmount, 25)
    }
    func testEveryOptionalModuleActivatesFromItsOwnValuesAndEditedPhotoIsNotReset() {
        ed.open(photos[0])
        ed.adjustments.look.on = true; ed.adjustments.detail.clarity = 20; ed.adjustments.effects.film3.on = true; ed.adjustments.effects.cinema.on = true
        ed.adjustments.tools.colorOn = true; ed.adjustments.effects.vignette = 20
        for m in ["look", "detail", "film3", "cinema", "color", "optics"] { XCTAssertTrue(ed.adjustments.isModuleEnabled(m), m) }
        XCTAssertFalse(ed.adjustments.isModuleEnabled("diffusion")); XCTAssertFalse(ed.adjustments.isModuleEnabled("retouch"))
        ed.flushSave(); ed.open(photos[1]); ed.open(photos[0])                     // fotografia editată își păstrează starea la redeschidere
        XCTAssertTrue(ed.adjustments.isModuleEnabled("look")); XCTAssertEqual(ed.adjustments.detail.clarity, 20)
        XCTAssertFalse(ed.adjustments.isModuleEnabled("diffusion"))
        ed.resetAdjustments(); XCTAssertEqual(ed.adjustments.disabledModules, Set(AdjustmentSet.optionalModules))   // resetarea revine la starea nouă
    }
    /// Retuș (cale distinctă): un punct plasat prin gest activează modulul; «Anulează» îl scoate și readuce modulul oprit; pornirea modului de plasare singură nu activează nimic.
    func testRetouchSpotActivatesModuleAndUndoRestores() {
        ed.open(photos[0]); XCTAssertFalse(ed.adjustments.isModuleEnabled("retouch")); ed.activeTool = .retouch
        XCTAssertFalse(ed.adjustments.isModuleEnabled("retouch"), "alegerea uneltei nu activează modulul")
        ed.addRetouch(nx: 0.3, ny: 0.4)
        XCTAssertTrue(ed.adjustments.isModuleEnabled("retouch")); XCTAssertEqual(ed.adjustments.retouch.count, 1)
        ed.undoLastReset()
        XCTAssertFalse(ed.adjustments.isModuleEnabled("retouch")); XCTAssertTrue(ed.adjustments.retouch.isEmpty)
    }
    /// Chart: ghidajul (grila) e stare de sesiune, nu corecție: poziționarea/rotirea/oglindirea nu schimbă reglajele; fără propunere validată, «Aplică» nu face nimic.
    func testChartGridIsGuideNotCorrection() {
        ed.open(photos[0]); let before = ed.adjustments; ed.activeTool = .chart
        ed.chartGrid.corners = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.1, y: 0.4)]; ed.chartRotate(); ed.chartMirror()
        XCTAssertEqual(ed.adjustments, before, "grila nu atinge reglajele"); XCTAssertNil(ed.adjustments.chart); XCTAssertFalse(ed.adjustments.isModuleEnabled("chart"))
        ed.chartApply(); XCTAssertNil(ed.adjustments.chart, "fără propunere validată nu se aplică nimic"); XCTAssertFalse(ed.adjustments.isModuleEnabled("chart"))
        ed.chartResetGrid(); XCTAssertEqual(ed.adjustments, before)
    }
    /// Cinema: alegerea modelului (slot/stil) activează modulul, se păstrează la dezactivare/reactivare și la redeschidere.
    func testCinemaChoiceSurvivesToggleAndReopen() {
        ed.open(photos[0]); XCTAssertFalse(ed.adjustments.isModuleEnabled("cinema"))
        ed.adjustments.effects.cinema.slots[1].style = 7                           // alegerea unui stil, cu modulul oprit
        XCTAssertTrue(ed.adjustments.isModuleEnabled("cinema"), "alegerea deliberată a unui model activează modulul")
        ed.adjustments.effects.cinema.on = true
        ed.adjustments.disabledModules.insert("cinema"); XCTAssertEqual(ed.adjustments.effects.cinema.slots[1].style, 7); XCTAssertFalse(ed.adjustments.effective.effects.cinema.on)
        ed.adjustments.disabledModules.remove("cinema"); XCTAssertTrue(ed.adjustments.effective.effects.cinema.on); XCTAssertEqual(ed.adjustments.effective.effects.cinema.slots[1].style, 7)
        ed.flushSave(); ed.open(photos[1]); ed.open(photos[0])
        XCTAssertEqual(ed.adjustments.effects.cinema.slots[1].style, 7); XCTAssertTrue(ed.adjustments.effects.cinema.on); XCTAssertTrue(ed.adjustments.isModuleEnabled("cinema"))
    }
    /// Revizuire: aprobarea se acordă doar pe un rezultat ACTUAL (aceeași amprentă) și se invalidează la schimbarea reglajelor; un rezultat depășit nu poate fi aprobat.
    func testApprovalRequiresFreshResultAndInvalidatesOnChange() {
        ed.open(photos[0]); let id = photos[0].id
        XCTAssertFalse(ed.thumbIsFresh(id)); XCTAssertFalse(ed.setApproval(id, true), "fără rezultat randat nu se aprobă"); XCTAssertEqual(ed.reviewStatus(id), .toCheck)
        ed.storeReviewResult(id, NSImage(size: NSSize(width: 4, height: 4)), fingerprint: ed.currentFingerprint(of: id))
        XCTAssertTrue(ed.thumbIsFresh(id)); XCTAssertTrue(ed.setApproval(id, true)); XCTAssertEqual(ed.reviewStatus(id), .approved)
        ed.adjustments.exposure = 0.7                                                   // reglaj nou: rezultatul afișat e depășit, aprobarea se anulează
        XCTAssertFalse(ed.thumbIsFresh(id)); XCTAssertNotEqual(ed.approvalState(id), .approved); XCTAssertFalse(ed.isApproved(id)); XCTAssertFalse(ed.setApproval(id, true))
        ed.storeReviewResult(id, NSImage(size: NSSize(width: 4, height: 4)), fingerprint: ed.currentFingerprint(of: id))
        XCTAssertFalse(ed.isApproved(id), "un rezultat nou nu reînvie aprobarea veche"); XCTAssertTrue(ed.setApproval(id, true)); XCTAssertTrue(ed.isApproved(id))
        _ = ed.setApproval(id, false); XCTAssertFalse(ed.isApproved(id))
    }
    func testExportDefaultsDoNotWidenTheScopeAndOverwriteNeedsConfirmation() {
        XCTAssertEqual(ed.exportScope, .approved); XCTAssertEqual(ed.exportCollision, .unique); XCTAssertTrue(ed.exportCanStart)
        ed.exportCollision = .overwrite; XCTAssertFalse(ed.exportCanStart, "suprascrierea cere confirmare explicită"); ed.exportOverwriteConfirmed = true; XCTAssertTrue(ed.exportCanStart)
        ed.exportCollision = .unique; XCTAssertFalse(ed.exportOverwriteConfirmed, "confirmarea nu supraviețuiește schimbării politicii")
    }
    /// Navigarea încheie gesturile pe pânză: Space/pan resetate, formă neterminată tratată explicit; unealta aleasă rămâne (e un mod, nu un gest).
    func testNavigationEndsCanvasGestures() {
        ed.open(photos[0]); ed.activeTool = .retouch; ed.viewer.spaceDown = true; ed.viewer.panning = true
        ed.endCanvasGestures()
        XCTAssertFalse(ed.viewer.spaceDown); XCTAssertFalse(ed.viewer.panning); XCTAssertTrue(ed.viewer.placementAllowed); XCTAssertEqual(ed.activeTool, .retouch)
    }
    /// Grila neconvexă: nu se eșantionează, nu se validează, se păstrează ultima grilă validă și se explică starea (fără recalibrarea probelor colorimetrice).
    func testNonConvexChartGridIsInvalidBlocksValidationAndKeepsLastValid() {
        ed.open(photos[0]); XCTAssertTrue(ed.chartGrid.isValid)
        let good = ed.chartGrid
        var g = good; g.corners = [good.corners[1], good.corners[0], good.corners[2], good.corners[3]]          // TL↔TR: încrucișat
        XCTAssertFalse(g.isValid); XCTAssertNotNil(g.invalidReason)
        var tiny = good; tiny.corners[1] = tiny.corners[0]; XCTAssertFalse(tiny.isValid, "colțuri suprapuse")
        var line = good; line.corners = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.3, y: 0.1)]; XCTAssertFalse(line.isValid, "colțuri pe o dreaptă")
        var concave = good; concave.corners = [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.2), CGPoint(x: 0.3, y: 0.4), CGPoint(x: 0.2, y: 0.8)]; XCTAssertFalse(concave.isValid, "concav")
        ed.chartGrid = g
        XCTAssertFalse(ed.chartGrid.isValid); XCTAssertEqual(ed.lastValidChartGrid, good, "ultima grilă validă se păstrează")
        ed.chartValidate(); XCTAssertTrue(ed.chartMessage.contains("nevalidă")); XCTAssertNil(ed.chartValidation); XCTAssertNil(ed.chartProposal); XCTAssertFalse(ed.chartBusy)
        ed.chartRestoreLastValid(); XCTAssertTrue(ed.chartGrid.isValid); XCTAssertEqual(ed.chartGrid, good)
        var rot = good; rot.rotation = 3; XCTAssertTrue(rot.isValid, "rotația/oglindirea nu schimbă validitatea geometriei")
    }
    func testNewWorkspaceStartsWithAllPanelsClosedButSavedPreferenceIsKept() {
        XCTAssertTrue(PanelState.defaultOpen.isEmpty)
        let d = UserDefaults.standard; let old = d.object(forKey: PanelState.openKey); defer { if let o = old { d.set(o, forKey: PanelState.openKey) } else { d.removeObject(forKey: PanelState.openKey) } }
        d.removeObject(forKey: PanelState.openKey); XCTAssertTrue(PanelState().open.isEmpty)
        d.set(["light"], forKey: PanelState.openKey); XCTAssertEqual(PanelState().open, ["light"])      // preferința salvată nu se resetează
    }
    func testEditedPhotoKeepsStateOnReopenAndDisabledModuleKeepsSettings() {
        ed.open(photos[0]); ed.adjustments.exposure = 1.2; ed.adjustments.disabledModules.insert("exposure"); ed.flushSave()
        ed.open(photos[1]); ed.open(photos[0])
        XCTAssertEqual(ed.adjustments.exposure, 1.2); XCTAssertTrue(ed.adjustments.disabledModules.contains("exposure")); XCTAssertEqual(ed.adjustments.effective.exposure, 0)
    }
    func testSplitFractionIsViewStateOnly() {
        let v = ViewerState(); XCTAssertEqual(v.splitFraction, 0.5); v.splitFraction = 0.9
        ed.open(photos[0]); XCTAssertTrue(ed.adjustments.isNeutral)                                      // separatorul nu atinge reglajele
        XCTAssertEqual(ed.adjustments.fingerprint, AdjustmentSet.neutral(.dwg).fingerprint)
    }
    func testLoupe100PercentIsOneImagePixelPerPhysicalPixel() {
        ed.viewer.fullSize = CGSize(width: 4000, height: 3000); ed.loupeViewPts = CGSize(width: 250, height: 250); ed.loupeMag = 1
        let back = ed.viewer.backing; let n = ed.loupeRectNorm
        XCTAssertEqual(n.width * 4000, 250 * back, accuracy: 1e-6); XCTAssertEqual(n.height * 3000, 250 * back, accuracy: 1e-6)
        ed.loupeMag = 2; XCTAssertEqual(ed.loupeRectNorm.width * 4000, 125 * back, accuracy: 1e-6)
        ed.loupeSetCenter(CGPoint(x: 0, y: 1)); let c = ed.loupeRectNorm; XCTAssertGreaterThanOrEqual(c.minX, 0); XCTAssertLessThanOrEqual(c.maxY, 1.0000001)   // rămâne în imagine
    }
    func testLoupeSelectionResetsWhenPhotoChanges() {
        ed.open(photos[0]); ed.loupeSetCenter(CGPoint(x: 0.2, y: 0.8)); ed.loupeTarget = "Față 1"; ed.open(photos[1])
        XCTAssertEqual(ed.loupeCenter, CGPoint(x: 0.5, y: 0.5)); XCTAssertEqual(ed.loupeTarget, "")
        XCTAssertTrue(ed.loupeTargets().isEmpty)                                                          // fără analiză: lupa manuală rămâne posibilă
    }
    func testFloatingPanelRecoversOntoVisibleScreen() {
        let p = NSPanel(contentRect: NSRect(x: -40_000, y: -40_000, width: 300, height: 200), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        FloatingPanels.recover(p)
        XCTAssertTrue(NSScreen.screens.isEmpty || NSScreen.screens.contains { $0.visibleFrame.intersects(p.frame) })
    }
}

@MainActor
final class NavigatorTests: XCTestCase {
    func testVisibleRectAndFocusRoundTrip() {
        let v = ViewerState(); v.backing = 2; v.canvasSize = CGSize(width: 800, height: 600); v.fullSize = CGSize(width: 6000, height: 4000)
        XCTAssertEqual(v.visibleNormalized, CGRect(x: 0, y: 0, width: 1, height: 1))                       // potrivit: tot cadrul
        v.setScale(1)                                                                                         // 100%: ecran 1600×1200 px fizici din 6000×4000
        let a = v.visibleNormalized; XCTAssertEqual(a.width, 1600.0 / 6000, accuracy: 1e-6); XCTAssertEqual(a.height, 1200.0 / 4000, accuracy: 1e-6)
        v.focus(on: CGPoint(x: 0.8, y: 0.2), scale: 1); let b = v.visibleNormalized
        XCTAssertEqual(b.midX, 0.8, accuracy: 0.01); XCTAssertEqual(b.midY, 0.2, accuracy: 0.03)
        v.focus(on: CGPoint(x: 1, y: 1), scale: 1); XCTAssertLessThanOrEqual(v.visibleNormalized.maxX, 1.0000001)   // nu iese din imagine
    }
}

/// Defectul dev.47: câmpul numeric focalizat păstra «+0.40» după Anulează și îl reaplica la ieșire (valoare veche + modul reactivat).
final class NumericFieldModelTests: XCTestCase {
    func testExternalChangeWhileFocusedUpdatesTextAndBlurDoesNotReapply() {
        var f = NumericFieldModel(fmt: "%+.2f", range: -1...1, value: 0)
        f.text = "0.4"; XCTAssertEqual(f.pendingValue(current: 0), 0.4)                    // tastarea intermediară rămâne netăiată
        f.text = "0.4"; var v = f.pendingValue(current: 0)!; f.finish(value: v); XCTAssertEqual(f.text, "+0.40")
        v = 0; f.externalChange(to: v)                                                     // Anulează / resetare cu focus pe câmp
        XCTAssertEqual(f.text, "+0.00", "textul urmează modelul"); XCTAssertNil(f.pendingValue(current: v), "ieșirea din câmp nu reaplică valoarea veche")
    }
    func testBlurWithoutEditDoesNotQuantiseAndTypingSurvivesUntilCommit() {
        var f = NumericFieldModel(fmt: "%+.2f", range: -1...1, value: 0.4137)
        XCTAssertNil(f.pendingValue(current: 0.4137), "ieșire fără editare: valoarea 0.4137 nu se rotunjește la 0.41")
        f.text = "-"; XCTAssertNil(f.pendingValue(current: 0.4137)); f.text = "-0"; XCTAssertEqual(f.pendingValue(current: 0.4137), 0)
        f.text = "9"; XCTAssertEqual(f.pendingValue(current: 0.4137), 1, "limitat la interval")
        f.text = "0,25"; XCTAssertEqual(f.pendingValue(current: 0.4137), 0.25)
        f.text = "abc"; XCTAssertNil(f.pendingValue(current: 0.4137)); f.finish(value: 0.4137); XCTAssertEqual(f.text, "+0.41")
    }
}

/// Defect dev.48 (găsit prin gest): la 100% stratul de retuș (mai mare decât pânza) prindea clicuri pe bara de file și adăuga puncte.
@MainActor
final class CanvasHitTests: XCTestCase {
    func testPointsOutsideVisibleCanvasAreRejected() {
        let v = ViewerState(); v.canvasSize = CGSize(width: 800, height: 600)
        let r = CGRect(x: -500, y: -300, width: 4000, height: 3000)          // imaginea la 100%, depășește pânza
        XCTAssertTrue(v.canvasContains(CGPoint(x: 900, y: 700), in: r))         // (400, 400) în pânză
        XCTAssertFalse(v.canvasContains(CGPoint(x: 100, y: 100), in: r), "(-400,-200): deasupra/în stânga pânzei (bara de file)")
        XCTAssertFalse(v.canvasContains(CGPoint(x: 1400, y: 700), in: r), "în dreapta pânzei (inspector)")
        let fit = CGRect(x: 20, y: 10, width: 760, height: 580)
        XCTAssertTrue(v.canvasContains(CGPoint(x: 0, y: 0), in: fit)); XCTAssertTrue(v.canvasContains(CGPoint(x: 760, y: 580), in: fit))
    }
}

/// Poarta unică a gesturilor pe fotografie (dev.50): în pânză, nu în timpul deplasării.
@MainActor
final class CanvasGateTests: XCTestCase {
    func testGateRejectsOutsideCanvasAndPanning() {
        let v = ViewerState(); v.canvasSize = CGSize(width: 800, height: 600)
        let r = CGRect(x: -500, y: -300, width: 4000, height: 3000)                 // 100%: imaginea depășește pânza
        XCTAssertTrue(v.accepts(CGPoint(x: 900, y: 700), in: r)); XCTAssertTrue(v.accepts(canvasPoint: CGPoint(x: 400, y: 300)))
        XCTAssertFalse(v.accepts(CGPoint(x: 100, y: 100), in: r)); XCTAssertFalse(v.accepts(canvasPoint: CGPoint(x: 400, y: -5)))
        v.spaceDown = true; XCTAssertFalse(v.accepts(CGPoint(x: 900, y: 700), in: r), "Space apăsat: se deplasează, nu se plasează")
        v.spaceDown = false; v.panning = true; XCTAssertFalse(v.accepts(canvasPoint: CGPoint(x: 400, y: 300)), "în timpul pan-ului")
        v.panning = false; XCTAssertTrue(v.accepts(canvasPoint: CGPoint(x: 400, y: 300)))
    }
    /// După pan/zoom, dreptunghiul imaginii se mută, pânza rămâne aceeași: aceeași poartă, alt punct local.
    func testGateFollowsPanAndZoom() {
        let v = ViewerState(); v.backing = 2; v.canvasSize = CGSize(width: 800, height: 600); v.fullSize = CGSize(width: 6000, height: 4000)
        v.setScale(1); v.focus(on: CGPoint(x: 0.5, y: 0.5), scale: 1); var r = v.imageRect()
        let inside = CGPoint(x: 400 - r.minX, y: 300 - r.minY)
        XCTAssertTrue(v.accepts(inside, in: r)); XCTAssertFalse(v.accepts(CGPoint(x: -r.minX - 5, y: 300 - r.minY), in: r))
        v.focus(on: CGPoint(x: 0.8, y: 0.2), scale: 1); r = v.imageRect()
        XCTAssertTrue(v.accepts(CGPoint(x: 400 - r.minX, y: 300 - r.minY), in: r)); XCTAssertFalse(v.accepts(CGPoint(x: 400 - r.minX, y: 700 - r.minY), in: r))
    }
}
