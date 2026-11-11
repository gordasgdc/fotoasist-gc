import XCTest
@testable import PhotoResolve

/// Diferența NR (pornit − oprit) și RGB Parade: matematică pe valori cunoscute, separată de desen.
final class NRDifferenceParadeTests: XCTestCase {
    func testIdenticalImagesGiveUniformGrey() {
        let img = (0..<64).flatMap { i -> [Float] in let v = Float(i) / 63; return [v, 1 - v, 0.5] }
        let r = PhotoAnalysis.nrDifference(on: img, off: img, width: 8, height: 8, gain: 16)
        XCTAssertTrue(r.rgb8.allSatisfy { $0 == 128 }, "NR fără efect ⇒ gri uniform exact")
        XCTAssertEqual(r.stats.maxAbs, 0); XCTAssertEqual(r.stats.changedFraction, 0)
    }
    func testSignedDifferenceIsCentredAndScaledByExplicitGain() {
        let off = [Float](repeating: 0.5, count: 12), on = [Float](repeating: 0.5, count: 12).enumerated().map { $0.offset < 6 ? Float(0.52) : Float(0.48) }
        let g4 = PhotoAnalysis.nrDifference(on: on, off: off, width: 2, height: 2, gain: 4), g8 = PhotoAnalysis.nrDifference(on: on, off: off, width: 2, height: 2, gain: 8)
        XCTAssertGreaterThan(g4.rgb8[0], 128); XCTAssertLessThan(g4.rgb8[11], 128)                    // semn păstrat
        XCTAssertEqual(Int(g4.rgb8[0]) - 128, Int((0.5 + 4 * 0.02) * 255 + 0.5) - 128)               // 0.02·4 = 0.08 ⇒ ≈ +20
        XCTAssertGreaterThan(Int(g8.rgb8[0]) - 128, Int(g4.rgb8[0]) - 128)                           // amplificare mai mare ⇒ abatere mai mare
        XCTAssertEqual(g4.stats.meanSigned, 0, accuracy: 1e-6)                                       // +0.02 și −0.02 se anulează
        XCTAssertEqual(g4.stats.meanAbs, 0.02, accuracy: 1e-6)
    }
    func testParadeKeepsColumnsAndChannelsSeparate() {
        // jumătatea stângă: R=1,G=0,B=0.5; dreapta: R=0,G=1,B=0.5
        let w = 16, h = 4; var rgb = [Float](); for _ in 0..<h { for x in 0..<w { rgb += x < w / 2 ? [1, 0, 0.5] : [0, 1, 0.5] } }
        let d = PhotoAnalysis.parade(finalRGB: rgb, width: w, height: h, columns: 16, rows: 11)
        func has(_ ch: Int, col: Int, row: Int) -> Bool { d.counts[ch][row * d.columns + col] > 0 }
        XCTAssertTrue(has(0, col: 2, row: 0)); XCTAssertFalse(has(0, col: 12, row: 0)); XCTAssertTrue(has(0, col: 12, row: 10))     // R: sus stânga, jos dreapta
        XCTAssertTrue(has(1, col: 12, row: 0)); XCTAssertTrue(has(1, col: 2, row: 10))
        XCTAssertTrue(has(2, col: 2, row: 5)); XCTAssertTrue(has(2, col: 12, row: 5))                                              // B = 0.5 ⇒ rândul de mijloc
        XCTAssertEqual(d.counts[0].reduce(0, +), Float(w * h))                                                                     // fiecare pixel o dată pe canal
    }
}
