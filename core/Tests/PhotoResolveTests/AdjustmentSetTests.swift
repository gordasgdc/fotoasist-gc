import XCTest
import CPhotoCore
@testable import PhotoResolve
@testable import PhotoCore
import PhotoRaw

final class AdjustmentSetTests: XCTestCase {
    func testNeutralChainIsITL2LDRT() {
        let c = AdjustmentSet().chain()
        XCTAssertEqual(c.map { $0.stage }, ["input_transform", "linear_to_log", "drt"])
        XCTAssertEqual(c.first?.params["v3itCamera"], 9); XCTAssertEqual(c.last?.params["v3dOutput"], 2)
    }
    func testOnlyChangedControlsAppearInOrder() {
        var a = AdjustmentSet(); a.exposure = 0.7; a.contrast = 1.2; a.saturation = 0.9; a.temperature = -20
        let c = a.chain()
        XCTAssertEqual(c.map { $0.stage }, ["input_transform", "exposure_balance", "linear_to_log", "tone", "saturation_hue", "drt"])   // ordine = lanț: liniar → log → DRT
        XCTAssertEqual(c[1].params, ["v3eExposure": 0.7, "v3eTemp": -20])
    }
    func testPresetsAreExplicitParameterSets() {
        let a = StylePreset.all.first { $0.id == "intens" }!.applied(to: AdjustmentSet())
        XCTAssertEqual(a.contrast, 1.25); XCTAssertEqual(a.saturation, 1.20); XCTAssertEqual(a.styleID, "intens")
        XCTAssertTrue(StylePreset.all.first { $0.id == "natural" }!.applied(to: AdjustmentSet()).isNeutral)
    }
    func testFingerprintIgnoresStyleLabelButNotValues() {
        var a = AdjustmentSet(); var b = a; b.styleID = "x"; XCTAssertEqual(a.fingerprint, b.fingerprint); a.exposure = 0.001; XCTAssertNotEqual(a.fingerprint, b.fingerprint)
    }
    func testCodableRoundTrip() throws {
        var a = AdjustmentSet(); a.exposure = 1.25; a.styleID = "natural"
        XCTAssertEqual(try JSONDecoder().decode(AdjustmentSet.self, from: JSONEncoder().encode(a)), a)
    }
}

final class AdjustmentAutoTests: XCTestCase {
    func testAutoModeUsesEstimatePlusOffsetInChain() {
        var a = AdjustmentSet(); a.exposureAuto = true; a.autoOffset = 0.5; a.exposure = 9      // exposure manual ignorat în modul automat
        XCTAssertEqual(a.effectiveExposure(estimate: 2.0), 2.5)
        XCTAssertEqual(a.chain(estimate: 2.0).first { $0.stage == "exposure_balance" }?.params["v3eExposure"], 2.5)
        XCTAssertFalse(a.isNeutral)
    }
    func testAutoFingerprintCarriesEstimatorVersionAndNotTheManualValue() {
        var a = AdjustmentSet(); a.exposureAuto = true; var b = a; b.exposure = 3
        XCTAssertEqual(a.fingerprint, b.fingerprint); XCTAssertTrue(a.fingerprint.contains("auto("))
        var c = AdjustmentSet(); c.exposure = 0; XCTAssertNotEqual(a.fingerprint, c.fingerprint)
    }
    func testOldJSONWithoutNewKeysDecodesToDefaults() throws {
        let a = try JSONDecoder().decode(AdjustmentSet.self, from: Data(#"{"exposure":1.5,"contrast":1.2}"#.utf8))
        XCTAssertEqual(a.exposure, 1.5); XCTAssertEqual(a.contrast, 1.2); XCTAssertFalse(a.exposureAuto); XCTAssertEqual(a.saturation, 1)
    }

    func testLocalCorrectionsRoundTripFingerprintAndOldJSONCompatibility() throws {
        var a = AdjustmentSet(); a.exposure = 0.5
        XCTAssertEqual(try JSONDecoder().decode(AdjustmentSet.self, from: Data(#"{"exposure":0.5}"#.utf8)).locals, [])   // JSON salvat de versiuni vechi → fără corecții
        let fp0 = a.fingerprint; var l = LocalCorrection.make(.gradient, number: 1); l.exposure = -0.8; a.locals = [l]
        XCTAssertNotEqual(a.fingerprint, fp0)                                                                                  // o corecție schimbă amprenta (cache, aprobări)
        let b = try JSONDecoder().decode(AdjustmentSet.self, from: try JSONEncoder().encode(a)); XCTAssertEqual(b, a); XCTAssertEqual(b.fingerprint, a.fingerprint)
        a.locals[0].enabled = false; XCTAssertEqual(LocalCorrection.coreLocals(a.locals).count, 0)                           // oprită ⇒ nu intră în calcul
        a.locals[0].enabled = true; a.locals[0].exposure = 0; XCTAssertEqual(LocalCorrection.coreLocals(a.locals).count, 0)  // neutră ⇒ nu intră în calcul
        a.locals[0].exposure = -0.8; XCTAssertEqual(LocalCorrection.coreLocals(a.locals).count, 1)
        let m = a.locals[0].maskValues(width: 8, height: 8); XCTAssertEqual(m.count, 64); XCTAssertGreaterThan(m[0 * 8 + 4], m[7 * 8 + 4])   // degrade: sus = efect complet
    }
    func testLocalCorrectionsSurviveSaveAndReopenOfTheCatalog() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lc_\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("c.sqlite"); var c: Catalog? = try Catalog(url: url)
        _ = try c!.importFiles([("/x/IMG_0.ARW", 100, 1, "Cam", Date(timeIntervalSince1970: 1000))]); let id = try c!.photos()[0].id
        var a = AdjustmentSet(); a.exposure = 0.7; var e = LocalCorrection.make(.ellipse, number: 1); e.x1 = 0.31; e.exposure = -0.8; e.invert = true; e.feather = 0.22; var g = LocalCorrection.make(.gradient, number: 1); g.temperature = -25; g.enabled = false; g.name = "Cer"
        a.locals = [e, g]; try c!.setEdits(photoId: id, json: String(data: try JSONEncoder().encode(a), encoding: .utf8)!); c = nil
        let r = try Catalog(url: url); let back = try JSONDecoder().decode(AdjustmentSet.self, from: Data(try r.edits(photoId: id)!.utf8))
        XCTAssertEqual(back, a); XCTAssertEqual(back.fingerprint, a.fingerprint); XCTAssertEqual(back.locals.map { $0.id }, [e.id, g.id]); XCTAssertEqual(back.locals[0].invert, true); XCTAssertEqual(back.locals[1].enabled, false)   // ordine, id-uri, inversare, oprire păstrate
    }
    func testSavedEditsFromAnOlderEngineAreFlaggedAndNeutralOnesAreNot() throws {
        let old = try JSONDecoder().decode(AdjustmentSet.self, from: Data(#"{"exposure":1.0,"shadows":0.5}"#.utf8)); XCTAssertEqual(old.engineRevision, 0); XCTAssertTrue(old.isFromOlderEngine)
        let neutralOld = try JSONDecoder().decode(AdjustmentSet.self, from: Data("{}".utf8)); XCTAssertFalse(neutralOld.isFromOlderEngine); XCTAssertTrue(neutralOld.isNeutral)
        var cur = old; cur.engineRevision = AdjustmentSet.currentEngineRevision; XCTAssertFalse(cur.isFromOlderEngine); XCTAssertEqual(cur.fingerprint, old.fingerprint)   // valorile rămân, doar revizia diferă
        XCTAssertTrue(String(cString: pc_version()).contains("rev3"))                                                                                 // cache-ul rezultatelor (cheie cu pc_version) se invalidează
    }

    // MARK: module dezactivabile
    func testDisabledModulesAreNeutralInProcessingButKeepTheirValuesAndRecoverExactly() throws {
        var a = AdjustmentSet(); a.exposure = 1.2; a.shadows = 0.5; a.contrast = 1.3; a.temperature = 20; a.saturation = 1.1; a.geometry.angle = 2; a.family = .awg3
        let on = a.fingerprint; a.disabledModules = ["light", "geometry"]
        XCTAssertNotEqual(a.fingerprint, on, "dezactivarea schimbă amprenta (cache/aprobări)"); let e = a.effective
        XCTAssertEqual(e.shadows, 0); XCTAssertEqual(e.contrast, 1); XCTAssertTrue(e.geometry.isNeutral); XCTAssertEqual(e.exposure, 1.2); XCTAssertEqual(e.temperature, 20); XCTAssertEqual(e.family, .awg3, "familia/DRT nu au bypass")
        XCTAssertEqual(a.shadows, 0.5); XCTAssertEqual(a.contrast, 1.3); XCTAssertEqual(a.geometry.angle, 2, "valorile se păstrează")
        let rt = try JSONDecoder().decode(AdjustmentSet.self, from: JSONEncoder().encode(a)); XCTAssertEqual(rt.disabledModules, ["light", "geometry"]); XCTAssertEqual(rt, a)
        a.disabledModules = []; XCTAssertEqual(a.fingerprint, on, "reactivarea recuperează exact reglajele (aceeași amprentă)")
        var b = AdjustmentSet(); b.disabledModules = ["colour"]; XCTAssertTrue(b.isNeutral, "un modul oprit fără valori nu face fotografia «editată»"); XCTAssertTrue(b.isModuleEnabled("light")); XCTAssertFalse(b.isModuleEnabled("colour"))
    }

    // MARK: familii de lucru
    func testFamilyDefaultsToDWGAndDoesNotChangeExistingFingerprintOrDecoding() throws {
        var a = AdjustmentSet(); a.exposure = 1; a.contrast = 1.1; XCTAssertEqual(a.family, .dwg)
        let before = a.fingerprint; XCTAssertFalse(before.contains("fam:"), "reglajele existente (DWG) își păstrează amprenta și aprobările")
        a.family = .awg3; XCTAssertNotEqual(a.fingerprint, before); XCTAssertTrue(a.fingerprint.contains("awg3-logc3-ei800"))
        XCTAssertEqual(Set(WorkingFamily.allCases.map { var b = a; b.family = $0; return b.fingerprint }).count, 4, "amprentă distinctă pe familie (cache + aprobări)")
        let legacy = try JSONDecoder().decode(AdjustmentSet.self, from: Data(#"{"exposure":1,"contrast":1.1}"#.utf8)); XCTAssertEqual(legacy.family, .dwg)   // JSON salvat înainte de familii
        let unknown = try JSONDecoder().decode(AdjustmentSet.self, from: Data(#"{"exposure":1,"family":99}"#.utf8)); XCTAssertEqual(unknown.family, .dwg, "familie necunoscută → DWG (rezerva declarată), nu eroare")
        let rt = try JSONDecoder().decode(AdjustmentSet.self, from: JSONEncoder().encode(a)); XCTAssertEqual(rt.family, .awg3); XCTAssertEqual(rt, a)
    }
    func testFamilyIsNotACreativeAdjustment() {
        var a = AdjustmentSet.neutral(.acesAP1); XCTAssertTrue(a.isNeutral, "valori neutre într-o altă familie = tot neutru (familia nu e o reglare)"); XCTAssertEqual(a.family, .acesAP1)
        a.exposure = 0.5; XCTAssertFalse(a.isNeutral)
    }
    func testWorkingFamilyInventoryMatchesStyleProfiles() {
        XCTAssertEqual(WorkingFamily.allCases.map { $0.id }, ["dwg-davinci-intermediate", "ap1-acescct", "awg3-logc3-ei800", "awg4-logc4"])
        XCTAssertTrue(WorkingFamily.allCases.allSatisfy { !$0.label.isEmpty && !$0.explanation.isEmpty && !$0.shortLabel.isEmpty })
    }
    func testHandoffRefusesFamiliesOnOlderOFXInsteadOfWrongChain() {
        XCTAssertFalse(ResolveHandoff.supportsFamilies("0.3.0")); XCTAssertTrue(ResolveHandoff.supportsFamilies("0.4.0")); XCTAssertTrue(ResolveHandoff.supportsFamilies("0.10.0")); XCTAssertFalse(ResolveHandoff.supportsFamilies(nil))
        XCTAssertTrue(HandoffError.familiesUnavailable("0.3.0", "ACES").description.contains("0.4.0"))
    }
    func testFamilyIntermediateEXRIsCodedInTheFamilyLog() {
        var img = FloatImage(width: 2, height: 1, rgb: [0.18, 0.18, 0.18, 1.0, 0.5, 0.1])
        XCTAssertEqual(img.familyEncoded(.dwg).rgb, img.diEncoded().rgb, "DWG = DaVinci Intermediate, neschimbat")
        for f in [WorkingFamily.acesAP1, .awg3, .awg4] {
            let e = img.familyEncoded(f)
            // gri neutru: gamutul nu schimbă neutrul; codul = curba familiei
            XCTAssertEqual(Double(e.rgb[1]), pc_family_encode(f.coreIndex, 0.18), accuracy: 2e-5, f.id); XCTAssertEqual(e.rgb[0], e.rgb[2], accuracy: 1e-5)
            XCTAssertTrue(e.rgb.allSatisfy { $0.isFinite })
        }
        img.rgb[0] = 0
    }
}
