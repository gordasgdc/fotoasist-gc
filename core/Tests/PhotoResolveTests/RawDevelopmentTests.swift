import XCTest
@testable import PhotoResolve

final class RawDevelopmentTests: XCTestCase {
    func testNewPhotoUsesCorrectedDecodeWithCompensationOffUntilChosen() {
        var a = AdjustmentSet(); XCTAssertEqual(a.rawDev.baseline, .off); XCTAssertFalse(a.rawDev.isLegacyDecode)   // implicit 0 EV: semnificația metadatei nu e confirmată oficial
        XCTAssertEqual(a.rawDev.appliedEV(cameraShift: -1.72), 0)
        a.rawDev.baseline = .camera; XCTAssertEqual(a.rawDev.appliedEV(cameraShift: -1.72), 1.72, accuracy: 1e-12); XCTAssertEqual(a.rawDev.appliedEV(cameraShift: nil), 0)
    }
    /// Reglajele salvate de versiunile anterioare (fără cheia `rawDev`) NU se schimbă în tăcere: dezvoltare veche, compensare oprită, aceeași amprentă ca înainte.
    func testSavedAdjustmentsWithoutKeyStayOnLegacyDevelopment() throws {
        var a = AdjustmentSet(); a.exposure = 0.7
        var j = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]; j.removeValue(forKey: "rawDev")
        let old = try JSONDecoder().decode(AdjustmentSet.self, from: JSONSerialization.data(withJSONObject: j))
        XCTAssertEqual(old.rawDev, RawDevelopment.legacy); XCTAssertTrue(old.rawDev.isLegacyDecode); XCTAssertEqual(old.rawDev.appliedEV(cameraShift: -1.72), 0)
        XCTAssertNotEqual(old.fingerprint, a.fingerprint)   // randare diferită ⇒ cache diferit
    }
    func testRawDevelopmentIsNotACreativeEditAndRoundTrips() throws {
        var a = AdjustmentSet(); a.rawDev = .legacy; XCTAssertTrue(a.isNeutral)            // dezvoltarea nu e reglaj creativ
        var b = AdjustmentSet(); b.rawDev.baseline = .manual; b.rawDev.manualEV = 1.25
        let r = try JSONDecoder().decode(AdjustmentSet.self, from: JSONEncoder().encode(b))
        XCTAssertEqual(r.rawDev, b.rawDev); XCTAssertEqual(r.rawDev.appliedEV(cameraShift: -9), 1.25)
        XCTAssertEqual(AdjustmentSet().fingerprint, AdjustmentSet().fingerprint); XCTAssertNotEqual(b.fingerprint, AdjustmentSet().fingerprint)
        XCTAssertEqual(b.baseForCompare.rawDev, b.rawDev)    // «Bază» = aceeași dezvoltare RAW, fără reglaje creative
    }
}
