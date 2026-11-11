import XCTest
import CPhotoCore
import PhotoCore
import PhotoRaw
@testable import PhotoResolve

/// Verificarea INFRASTRUCTURII estimatorului pe imagini SINTETICE cu parametri cunoscuți. NU e un profil învățat și nu probează generalizarea pe fotografii reale (cer perechi aprobate).
final class ProfileEstimatorTests: XCTestCase {
    let truth: [Double] = [0.5, 1.25, 1.15, 0.3, -0.25, 18, 0.008]
    func scene(_ seed: UInt32, w: Int = 240, h: Int = 160) -> FloatImage {   // gradient + pete colorate + textură deterministă (liniar DWG)
        var s = seed; func r() -> Float { s = s &* 1664525 &+ 1013904223; return Float(s >> 8) / 16777216 }
        var a = [Float](repeating: 0, count: w * h * 3); let cr = r(), cg = r(), cb = r()
        for y in 0..<h { for x in 0..<w { let g = 0.02 + 0.9 * Float(x) / Float(w) * (0.5 + 0.5 * Float(y) / Float(h)); let patch = ((x / 40) + (y / 40)) % 3
            let tint: [Float] = patch == 0 ? [1, 0.7, 0.5] : (patch == 1 ? [0.6, 1, 0.7] : [0.7, 0.7, 1]); for k in 0..<3 { a[(y * w + x) * 3 + k] = max(0.001, g * tint[k] * (0.6 + 0.4 * [cr, cg, cb][k]) + 0.01 * r()) } } }
        return FloatImage(width: w, height: h, rgb: a)
    }
    func natural() -> Bool { if case .loaded = GDCDRTData.status { return true }; GDCDRTData.load(); if case .loaded = GDCDRTData.status { return true }; return false }
    /// „Finalul” sintetic = randarea nucleului cu parametrii cunoscuți (cuantizat 8 biți, ca un JPEG).
    func makeFinal(_ img: FloatImage, est: Double, v: [Double], nat: Bool) -> (rgb: [Float], w: Int, h: Int) {
        let pr = ProfileEstimator.Prepared(w: img.width, h: img.height, linear: img.rgb, finalRGB: [], estimate: est); var o = ProfileEstimator.render(pr, v, drtNatural: nat)!
        for i in o.indices { o[i] = (min(1, max(0, o[i])) * 255).rounded() / 255 }; return (o, img.width, img.height)
    }
    func testRecoversKnownParametersAndImprovesOnHeldOutScenes() throws {
        let nat = natural(); var fits: [ProfileEstimator.PairFit] = []; var heldPrep: [ProfileEstimator.Prepared] = []
        for (k, seed) in [11, 22, 33, 44, 55].enumerated() {
            let img = scene(UInt32(seed)); let est = [0.0, 0.3, -0.2, 0.1, 0.4][k]
            let fin = makeFinal(img, est: est, v: truth, nat: nat); let pr = try ProfileEstimator.prepare(raw: img, final: fin, estimate: est, maxSide: 90)
            if k % 4 == 3 { heldPrep.append(pr) } else { fits.append(ProfileEstimator.fit(pairID: "p\(k)", prepared: pr, drtNatural: nat)) }
        }
        for f in fits { XCTAssertLessThan(f.residual, f.baseline * 0.25, "potrivirea scade reziduul: \(f.residual) vs \(f.baseline) (\(f.atBounds))") }
        let agg = ProfileEstimator.aggregate(fits, technicalPolicy: "test"); XCTAssertGreaterThanOrEqual(agg.used.count, 3)
        func med(_ n: String) -> Double { agg.parameters.creative[n]?.median ?? agg.parameters.adaptive[n]?.median ?? .nan }
        XCTAssertEqual(med("exposureOffset"), truth[0], accuracy: 0.25); XCTAssertEqual(med("contrast"), truth[1], accuracy: 0.12); XCTAssertEqual(med("saturation"), truth[2], accuracy: 0.15)
        let ev = ProfileEstimator.evaluate(agg.parameters, held: heldPrep, drtNatural: nat); XCTAssertEqual(ev.heldOut, 1); XCTAssertLessThan(ev.meanProfileDE, ev.meanBaselineDE * 0.5, ev.summary)
        print("PROFILE-SYN", nat ? "DRT Natural" : "DRT p1", String(format: "exp %.2f con %.2f sat %.2f sh %.2f hi %.2f temp %.1f tint %.3f", med("exposureOffset"), med("contrast"), med("saturation"), med("shadows"), med("highlights"), med("temperature"), med("tint")), ev.summary)
    }
    func testUnrelatedFinalIsExcludedGeometryMismatchRejectedAndProfileDoesNotTouchOtherModules() throws {
        let nat = natural(); let img = scene(5)
        let junkRGB: [Float] = (0..<(240 * 160 * 3)).map { (i: Int) -> Float in Float((i * 7919) % 255) / 255 }; let junk = (rgb: junkRGB, w: 240, h: 160)
        let f = ProfileEstimator.fit(pairID: "junk", prepared: try ProfileEstimator.prepare(raw: img, final: junk, estimate: 0, maxSide: 100), drtNatural: nat, maxEvaluations: 200)
        let agg = ProfileEstimator.aggregate([f], technicalPolicy: "t"); XCTAssertTrue(agg.used.isEmpty || f.improvement > 0)
        XCTAssertThrowsError(try ProfileEstimator.prepare(raw: img, final: (rgb: [Float](repeating: 0.5, count: 100 * 100 * 3), w: 100, h: 100), estimate: 0)) { XCTAssertTrue("\($0)".contains("Geometrie")) }
        var P = ProfileParameters(technicalPolicy: "t"); P.creative["contrast"] = .init(median: 1.2, spread: 0.02, count: 5); P.adaptive["exposureOffset"] = .init(median: 0.3, spread: 0.1, count: 5)
        let prof = PersonalProfile(name: "n", photographer: "f", setName: "s", pairIDs: [], engineVersion: ProfileEstimator.engineIdentity, parameters: P)
        let a = ProfileEstimator.adjustments(from: prof, estimate: 0.1); XCTAssertEqual(a.contrast, 1.2); XCTAssertEqual(a.autoOffset, 0.3); XCTAssertTrue(a.effects.isNeutral); XCTAssertTrue(a.tools.isNeutral); XCTAssertTrue(a.locals.isEmpty); XCTAssertTrue(a.geometry.isNeutral, "modulele noi/geometria rămân neutre")
        XCTAssertTrue(ProfileEstimator.engineIdentity.contains("est1") && ProfileEstimator.engineIdentity.contains("exposureOffset"))
    }
}
