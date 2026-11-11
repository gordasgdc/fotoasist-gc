import XCTest
@testable import PhotoCore

final class ProfileRegistryTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws { dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pr_\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }
    func file(_ n: String, _ s: String) throws -> String { let u = dir.appendingPathComponent(n); try Data(s.utf8).write(to: u); return u.path }

    func testPairsAreProposedUntilExplicitlyConfirmedAndDedupByHash() throws {
        var r = ProfileRegistry(); let raw = try file("a.ARW", "raw-A"), fin = try file("a.jpg", "final-A")
        let p = try r.addPair(raw: raw, final: fin, photographer: "F1", setName: "S1"); XCTAssertEqual(p.state, .proposed); XCTAssertFalse(p.learningApproved)
        XCTAssertEqual(try r.addPair(raw: raw, final: fin, photographer: "F1", setName: "S1").id, p.id); XCTAssertEqual(r.pairs.count, 1)      // aceeași pereche nu se dublează
        XCTAssertThrowsError(try r.confirm(p.id, statement: "da")) { XCTAssertEqual($0 as? ProfileRegistryError, .notConfirmedStatementMissing) }   // fără declarația exactă nu se confirmă
        XCTAssertFalse(r.pairs[0].learningApproved)
        try r.confirm(p.id, statement: ProfileRegistry.confirmationText); XCTAssertTrue(r.pairs[0].learningApproved); XCTAssertNotNil(r.pairs[0].confirmedAt)
        try r.reject(p.id); XCTAssertFalse(r.pairs[0].learningApproved); XCTAssertEqual(r.pairs[0].confirmationStatement, "")
        XCTAssertThrowsError(try r.addPair(raw: raw, final: raw, photographer: "F1", setName: "S1")) { XCTAssertEqual($0 as? ProfileRegistryError, .sameFile) }
    }
    func testDraftProfileNeedsConfirmedPairsOfOnePhotographerAndSetAndVersionsIncrease() throws {
        var r = ProfileRegistry(); let a = try r.addPair(raw: try file("a.ARW", "ra"), final: try file("a.jpg", "fa"), photographer: "F1", setName: "S1"), b = try r.addPair(raw: try file("b.ARW", "rb"), final: try file("b.jpg", "fb"), photographer: "F2", setName: "S1")
        XCTAssertThrowsError(try r.makeDraftProfile(name: "P", pairIDs: [a.id], engineVersion: "e1", technicalPolicy: "t")) { XCTAssertEqual($0 as? ProfileRegistryError, .noConfirmedPairs) }   // neconfirmată ⇒ nu
        try r.confirm(a.id, statement: ProfileRegistry.confirmationText); try r.confirm(b.id, statement: ProfileRegistry.confirmationText)
        XCTAssertThrowsError(try r.makeDraftProfile(name: "P", pairIDs: [a.id, b.id], engineVersion: "e1", technicalPolicy: "t")) { XCTAssertEqual($0 as? ProfileRegistryError, .mixedPhotographers) }   // fotografii nu se amestecă
        let p1 = try r.makeDraftProfile(name: "P", pairIDs: [a.id], engineVersion: "e1", technicalPolicy: "t"), p2 = try r.makeDraftProfile(name: "P", pairIDs: [a.id], engineVersion: "e2", technicalPolicy: "t")
        XCTAssertEqual(p1.version, 1); XCTAssertEqual(p2.version, 2); XCTAssertEqual(p1.status, .draft); XCTAssertEqual(p1.source, .learnedFromExamples)
        XCTAssertTrue(p1.parameters.adaptive.isEmpty && p1.parameters.creative.isEmpty)                    // nicio estimare
        XCTAssertTrue(ProfileParameters.notRepresentable.contains("corecții locale (măști)"))              // corecțiile locale nu intră în profil
    }
    func testEstimationIsBlockedWithExactReasonsAndRegistrySurvivesReopen() throws {
        var r = ProfileRegistry(); let a = try r.addPair(raw: try file("a.ARW", "ra"), final: try file("a.jpg", "fa"), photographer: "F1", setName: "S1"); try r.confirm(a.id, statement: ProfileRegistry.confirmationText)
        let p = try r.makeDraftProfile(name: "P", pairIDs: [a.id], engineVersion: "e", technicalPolicy: "t")
        XCTAssertTrue(r.estimationBlocker(for: p)!.contains("1 din 4")); r.minConfirmedPairs = 5; XCTAssertTrue(r.estimationBlocker(for: p)!.contains("1 din 5")); r.minConfirmedPairs = 1; XCTAssertNil(r.estimationBlocker(for: p), "prag atins ⇒ estimarea poate rula")
        var P = ProfileParameters(technicalPolicy: "t"); P.creative["contrast"] = .init(median: 1.2, spread: 0.01, count: 1); r.storeEstimate(profileID: p.id, parameters: P, estimatorVersion: 1, paramSet: ["contrast"], evaluation: "ev", heldOut: [], excluded: ["x"], engineIdentity: "E2")
        XCTAssertEqual(r.profiles[0].status, .estimated); XCTAssertEqual(r.profiles[0].engineVersion, "E2"); XCTAssertEqual(r.profiles[0].paramSet, ["contrast"]); XCTAssertEqual(r.profiles[0].notEstimated, ProfileParameters.notRepresentable)
        let legacyJSON = #"{"id":"x","name":"n","photographer":"f","setName":"s","version":1,"status":"draft","source":"learnedFromExamples","createdAt":0,"pairIDs":[],"engineVersion":"e","parameters":{"technicalPolicy":"t","adaptive":{},"creative":{}}}"#
        XCTAssertNoThrow(try JSONDecoder().decode(PersonalProfile.self, from: Data(legacyJSON.utf8)), "profilurile vechi (fără câmpurile noi) se citesc neschimbate")
        XCTAssertEqual(ProfileRegistry.experimentalMinPairs, 11); XCTAssertEqual(ProfileRegistry.evaluatedMinPairs, 24)
        let url = dir.appendingPathComponent("c.sqlite"); var c: Catalog? = try Catalog(url: url); try r.save(to: c!); c = nil
        let back = ProfileRegistry.load(from: try Catalog(url: url)); XCTAssertEqual(back.pairs.count, 1); XCTAssertTrue(back.pairs[0].learningApproved); XCTAssertEqual(back.profiles.first?.version, 1); XCTAssertEqual(back.minConfirmedPairs, 1)
        r.remove(a.id); XCTAssertTrue(r.pairs.isEmpty); XCTAssertTrue(r.profiles[0].pairIDs.isEmpty)
    }
    func testHeldOutSplitIsDeterministicDisjointAndAboutAQuarter() throws {
        var r = ProfileRegistry(); for i in 0..<20 { try r.addPair(raw: try file("r\(i).ARW", "raw\(i)"), final: try file("f\(i).jpg", "fin\(i)"), photographer: "F", setName: "S") }
        let a = ProfileRegistry.split(r.pairs), b = ProfileRegistry.split(r.pairs.reversed())
        XCTAssertEqual(a.fit.map { $0.id }, b.fit.map { $0.id }); XCTAssertEqual(a.heldOut.map { $0.id }, b.heldOut.map { $0.id })        // independent de ordinea de intrare
        XCTAssertEqual(Set(a.fit.map { $0.id }).intersection(a.heldOut.map { $0.id }).count, 0); XCTAssertEqual(a.fit.count + a.heldOut.count, 20); XCTAssertEqual(a.heldOut.count, 5)
    }
}
