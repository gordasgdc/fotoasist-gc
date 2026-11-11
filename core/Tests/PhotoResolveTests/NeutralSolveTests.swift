import XCTest
@testable import PhotoResolve

final class NeutralSolveTests: XCTestCase {
    func testGrayNeedsNoCorrection() throws {
        let r = try XCTUnwrap(NeutralSolve.solve(rgb: [0.18, 0.18, 0.18])); XCTAssertEqual(r.temperature, 0, accuracy: 1e-6); XCTAssertEqual(r.tint, 0, accuracy: 1e-6); XCTAssertTrue(r.warnings.isEmpty)
    }
    func testCastIsRemovedAndOutputIsNeutral() throws {
        for (t, s) in [(40.0, 0.01), (-60.0, -0.015), (25.0, -0.02)] {
            let cast = NeutralSolve.apply(t, s, [0.18, 0.18, 0.18])
            let r = try XCTUnwrap(NeutralSolve.solve(rgb: cast)); let y = NeutralSolve.apply(r.temperature, r.tint, cast)
            XCTAssertEqual(y[0] / y[1], 1, accuracy: 1e-5); XCTAssertEqual(y[2] / y[1], 1, accuracy: 1e-5); XCTAssertLessThan(r.residual, 1e-5)
            XCTAssertTrue(r.temperature * t < 0, "semnul corect: o dominantă caldă cere răcire (mărimea diferă: matricea nu e o simplă inversă a celei care a produs dominanta)"); XCTAssertFalse(r.atBounds)
        }
    }
    func testNonNeutralSampleIsFlaggedNotHidden() throws {
        let r = try XCTUnwrap(NeutralSolve.solve(rgb: [0.5, 0.1, 0.02])); XCTAssertFalse(r.warnings.isEmpty)
        XCTAssertNil(NeutralSolve.solve(rgb: [0.0, 0.0, 0.0]))
    }
}

final class VectorscopeTests: XCTestCase {
    func testNeutralGrayLandsAtCenterAndRedAtCrAxis() {
        let (cb, cr) = PhotoAnalysis.cbcr(0.5, 0.5, 0.5); XCTAssertEqual(cb, 0, accuracy: 1e-6); XCTAssertEqual(cr, 0, accuracy: 1e-6)
        let red = PhotoAnalysis.cbcr(1, 0, 0); XCTAssertEqual(red.cr, 0.5, accuracy: 1e-3, "roșu pur = Cr maxim"); XCTAssertLessThan(red.cb, 0)
        let blue = PhotoAnalysis.cbcr(0, 0, 1); XCTAssertEqual(blue.cb, 0.5, accuracy: 1e-3)
        let img = PhotoAnalysis.vectorscope(finalRGB: [Float](repeating: 0.5, count: 3 * 1000)); XCTAssertEqual(img.count, PhotoAnalysis.vectorscopeSize * PhotoAnalysis.vectorscopeSize * 4)
        let n = PhotoAnalysis.vectorscopeSize, c = n / 2; let k = (c * n + c) * 4; XCTAssertGreaterThan(img[k + 1], 150, "densitate la centru pentru gri")
    }
}
