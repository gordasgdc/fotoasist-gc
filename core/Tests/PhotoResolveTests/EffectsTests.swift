import XCTest
@testable import PhotoResolve

final class EffectsTests: XCTestCase {
    func testNeutralEffectsLeaveFingerprintAndNeutralityUntouched() {
        let a = AdjustmentSet(); XCTAssertTrue(a.effects.isNeutral); XCTAssertFalse(a.fingerprint.contains("fx:")); XCTAssertTrue(a.isNeutral)
        var b = a; b.effects.grainAmount = 20; XCTAssertFalse(b.isNeutral); XCTAssertNotEqual(a.fingerprint, b.fingerprint); XCTAssertTrue(b.fingerprint.contains("fx:g:"))
        var c = a; c.effects.grainSeed = 5; XCTAssertEqual(c.fingerprint, a.fingerprint, "sămânța fără cantitate nu schimbă randarea")
    }
    func testLegacyJSONWithoutEffectsDecodesNeutralAndRoundTrips() throws {
        let legacy = #"{"exposure":0.5,"temperature":0,"tint":0,"shadows":0,"highlights":0,"contrast":1,"saturation":1}"#
        let a = try JSONDecoder().decode(AdjustmentSet.self, from: Data(legacy.utf8)); XCTAssertTrue(a.effects.isNeutral)
        var b = a; b.effects.distortion = 30; b.effects.filmAmount = 60; b.effects.grainAmount = 40; b.effects.grainSeed = 9
        let r = try JSONDecoder().decode(AdjustmentSet.self, from: JSONEncoder().encode(b)); XCTAssertEqual(r.effects, b.effects)
    }
    func testModuleDisableNeutralizesOnlyThatEffectAndKeepsValues() {
        var a = AdjustmentSet(); a.effects.distortion = 20; a.effects.vignette = -30; a.effects.filmAmount = 50; a.effects.grainAmount = 50
        a.disabledModules = ["film"]; XCTAssertEqual(a.effective.effects.filmAmount, 0); XCTAssertEqual(a.effective.effects.grainAmount, 50); XCTAssertEqual(a.effects.filmAmount, 50, "valorile se păstrează")
        a.disabledModules = ["optics"]; XCTAssertEqual(a.effective.effects.distortion, 0); XCTAssertEqual(a.effective.effects.vignette, 0); XCTAssertEqual(a.effective.effects.grainAmount, 50)
        a.disabledModules = ["grain"]; XCTAssertEqual(a.effective.effects.grainAmount, 0); XCTAssertEqual(a.effective.effects.filmAmount, 50)
    }
    func testCompareBaseKeepsFramingOpticsButDropsCreativeEffects() {
        var a = AdjustmentSet(); a.effects.distortion = 40; a.effects.caRed = 10; a.effects.filmAmount = 80; a.effects.grainAmount = 30; a.effects.vignette = -20; a.effects.lensVignette = 10
        let b = a.baseForCompare; XCTAssertEqual(b.effects.distortion, 40); XCTAssertEqual(b.effects.caRed, 10); XCTAssertEqual(b.effects.filmAmount, 0); XCTAssertEqual(b.effects.grainAmount, 0); XCTAssertEqual(b.effects.vignette, 0); XCTAssertEqual(b.effects.lensVignette, 0)
    }
    func testPostEffectsFlagDrivesResolveBakeChoiceNotOptics() {
        var e = Effects(); e.distortion = 30; e.lensVignette = 20; XCTAssertFalse(e.hasPostEffects, "optica intră în intermediar, nu cere bake"); e.vignette = -10; XCTAssertTrue(e.hasPostEffects)
        var g = Effects(); g.grainAmount = 1; XCTAssertTrue(g.hasPostEffects)
    }
    func testDistortUndistortRoundTripThroughSwiftWrapper() {
        var e = Effects(); e.distortion = 60
        for (x, y) in [(120.0, 80.0), (3000.0, 2000.0), (5900.0, 3900.0)] { let d = e.distort(x, y, srcW: 6000, srcH: 4000); let u = e.undistort(d.x, d.y, srcW: 6000, srcH: 4000); XCTAssertEqual(u.x, x, accuracy: 1e-6); XCTAssertEqual(u.y, y, accuracy: 1e-6) }
    }
}
