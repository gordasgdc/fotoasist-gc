import XCTest
@testable import PhotoCore

/// Schimb de profil între DOUĂ biblioteci de test: parametrii se reproduc exact; fișierul nu conține date private; fișiere alterate / incompatibile / duplicate sunt tratate clar; importul nu face profilul «evaluat».
final class ProfileExchangeTests: XCTestCase {
    let engine = "pc1|rev3|est1|set:a,b", params = ["exposureOffset", "contrast", "saturation", "shadows", "highlights", "temperature", "tint"]
    func source() throws -> (ProfileRegistry, PersonalProfile) {
        var reg = ProfileRegistry()
        var p = PersonalProfile(name: "Seara de nuntă", photographer: "Ana Popescu", setName: "Nunta Ionescu", version: 2, pairIDs: ["PAIR-A", "PAIR-B", "PAIR-C"], engineVersion: engine, parameters: ProfileParameters(technicalPolicy: "politica"))
        p.parameters.creative = ["contrast": ParameterEstimate(median: 0.12, spread: 0.03, count: 9), "saturation": ParameterEstimate(median: -0.05, spread: 0.02, count: 9)]
        p.parameters.adaptive = ["exposureOffset": ParameterEstimate(median: 0.4, spread: 0.1, count: 9)]
        p.status = .estimated; p.estimatorVersion = 1; p.heldOutPairIDs = ["PAIR-C"]; p.evalHeld = 5; p.evalImproved = 5; p.evalBaselineDE = 6.0; p.evalProfileDE = 4.0; p.evalConsistent = true
        reg.profiles.append(p); return (reg, p)
    }
    func testRoundTripBetweenTwoLibrariesReproducesTheParametersExactly() throws {
        let (_, p) = try source(); let data = try ProfileExchange.export(p, engineIdentity: engine, paramSet: params, trustLabel: "EVALUAT")
        var other = ProfileRegistry()   // a doua bibliotecă
        guard case .success(.added(let q)) = ProfileExchange.importProfile(data, into: &other, photographer: "Bogdan", setName: "Set B", engineIdentity: engine, paramSet: params, engineVersionLabel: "motor local") else { return XCTFail("import") }
        XCTAssertEqual(q.parameters, p.parameters, "parametrii identici"); XCTAssertEqual(other.profiles.count, 1); XCTAssertEqual(q.status, .estimated)
        XCTAssertEqual(q.photographer, "Bogdan"); XCTAssertEqual(q.setName, "Set B", "legat de fotograful/setul ALESE la import, nu de cele din sursă")
    }
    func testExportedFileHoldsNoPrivateDataOrTrainingMaterial() throws {
        let (_, p) = try source(); let text = String(data: try ProfileExchange.export(p, engineIdentity: engine, paramSet: params, trustLabel: "EXPERIMENTAL"), encoding: .utf8)!
        for forbidden in ["PAIR-A", "PAIR-B", "PAIR-C", "Ana Popescu", "Nunta Ionescu", "/Users", "/Volumes", ".ARW", "rawPath", "finalPath", "sha256\": \"PAIR", "heldOutPairIDs", "pairIDs"] { XCTAssertFalse(text.contains(forbidden), "fișierul nu trebuie să conțină «\(forbidden)»") }
        XCTAssertTrue(text.contains("gdc.personal-profile/1")); XCTAssertTrue(text.contains("\"pairCount\" : 3"), "doar numărul de perechi, nu perechile")
    }
    func testImportDoesNotUpgradeTheProfileToEvaluated() throws {
        let (_, p) = try source(); let data = try ProfileExchange.export(p, engineIdentity: engine, paramSet: params, trustLabel: "EVALUAT · 5 reținute")
        var reg = ProfileRegistry(); guard case .success(.added(let q)) = ProfileExchange.importProfile(data, into: &reg, photographer: "x", setName: "y", engineIdentity: engine, paramSet: params, engineVersionLabel: "m") else { return XCTFail() }
        XCTAssertNil(q.heldOutPairIDs); XCTAssertNil(q.evalHeld); XCTAssertNil(q.evalImproved); XCTAssertNil(q.evalProfileDE); XCTAssertNotNil(q.importedFrom); XCTAssertTrue(q.pairIDs.isEmpty)
        XCTAssertTrue(q.evaluation!.contains("NU se transferă"))
    }
    func testTamperedIncompatibleOversizedAndMalformedFilesAreRefusedWithClearErrors() throws {
        let (_, p) = try source(); let good = try ProfileExchange.export(p, engineIdentity: engine, paramSet: params, trustLabel: "t"); var reg = ProfileRegistry()
        func imp(_ d: Data, eng: String? = nil, ps: [String]? = nil) -> ProfileExchange.ImportError? { if case .failure(let e) = ProfileExchange.importProfile(d, into: &reg, photographer: "a", setName: "b", engineIdentity: eng ?? engine, paramSet: ps ?? params, engineVersionLabel: "m") { return e }; return nil }
        var s = String(data: good, encoding: .utf8)!; s = s.replacingOccurrences(of: "0.12", with: "0.99"); XCTAssertEqual(imp(Data(s.utf8)), .checksumMismatch, "valori modificate")
        XCTAssertEqual(imp(good, eng: "alt motor"), .incompatibleEngine(file: engine, current: "alt motor")); XCTAssertEqual(imp(good, ps: ["contrast"]), .incompatibleParameters)
        XCTAssertEqual(imp(Data("nu e json".utf8)), .notAProfile); XCTAssertEqual(imp(Data(repeating: 65, count: ProfileExchange.maxBytes + 1)), .tooLarge)
        let wrong = String(data: good, encoding: .utf8)!.replacingOccurrences(of: "gdc.personal-profile/1", with: "gdc.personal-profile/9"); XCTAssertEqual(imp(Data(wrong.utf8)), .wrongFormat("gdc.personal-profile/9"))
        XCTAssertTrue(reg.profiles.isEmpty, "nimic importat din fișiere refuzate")
        var bad = p; bad.parameters.creative["contrast"] = ParameterEstimate(median: 99, spread: 0, count: 1); let badData = try ProfileExchange.export(bad, engineIdentity: engine, paramSet: params, trustLabel: "t")
        if case .failure(.invalidValues) = ProfileExchange.inspect(badData, engineIdentity: engine, paramSet: params) {} else { XCTFail("valoare în afara intervalului refuzată") }
        var draft = p; draft.status = .draft; XCTAssertThrowsError(try ProfileExchange.export(draft, engineIdentity: engine, paramSet: params, trustLabel: "t"), "ciorna nu se exportă")
    }
    func testDuplicatesAreDetectedAndNameClashesGetANewName() throws {
        let (_, p) = try source(); let data = try ProfileExchange.export(p, engineIdentity: engine, paramSet: params, trustLabel: "t"); var reg = ProfileRegistry()
        func go(_ data: Data) -> ProfileExchange.ImportOutcome? { if case .success(let o) = ProfileExchange.importProfile(data, into: &reg, photographer: "a", setName: "b", engineIdentity: engine, paramSet: params, engineVersionLabel: "m") { return o }; return nil }
        guard case .added = go(data)! else { return XCTFail() }; guard case .duplicate(let ex) = go(data)! else { return XCTFail("duplicat") }; XCTAssertEqual(ex.name, "Seara de nuntă"); XCTAssertEqual(reg.profiles.count, 1)
        var changed = p; changed.parameters.creative["contrast"] = ParameterEstimate(median: 0.2, spread: 0.03, count: 9); let d2 = try ProfileExchange.export(changed, engineIdentity: engine, paramSet: params, trustLabel: "t")
        guard case .added(let q) = go(d2)! else { return XCTFail() }; XCTAssertEqual(q.name, "Seara de nuntă (importat)"); XCTAssertEqual(reg.profiles.count, 2, "nume identic, valori diferite ⇒ profil nou cu nume distinct")
    }
}
