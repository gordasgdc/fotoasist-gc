import XCTest
import CPhotoCore
@testable import PhotoResolve

final class DetailTests: XCTestCase {
    func edge(_ w: Int, _ h: Int, lo: Float = 0.3, hi: Float = 0.6) -> [Float] {
        var a = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h { for x in 0..<w { let v: Float = x < w / 2 ? lo : hi; let i = (y * w + x) * 3; a[i] = v + 0.05; a[i + 1] = v; a[i + 2] = v - 0.05 } }
        return a
    }
    func apply(_ rgb: inout [Float], _ w: Int, _ h: Int, _ s: DetailSettings) { var d = s.core; _ = rgb.withUnsafeMutableBufferPointer { pc_detail_apply(&d, $0.baseAddress, Int32(w), Int32(h), 0) } }

    func testNeutralAndFlatAreIdentity() {
        var a = edge(64, 48); let b = a; apply(&a, 64, 48, DetailSettings()); XCTAssertEqual(a, b, "neutru = identitate exactă")
        var flat = [Float](repeating: 0.4, count: 64 * 48 * 3); var s = DetailSettings(); s.sharpAmount = 1.5; s.clarity = 0.8; let f0 = flat; apply(&flat, 64, 48, s)
        for i in 0..<flat.count { XCTAssertEqual(flat[i], f0[i], accuracy: 1e-6) }
    }
    func testSharpenOvershootsAtEdgeAndKeepsChroma() {
        var a = edge(400, 1000); var s = DetailSettings(); s.sharpAmount = 1.0; s.sharpRadius = 2.0; apply(&a, 400, 1000, s)   // σ ≈ 2 px
        let hiSide = a[(500 * 400 + 201) * 3 + 1], loSide = a[(500 * 400 + 198) * 3 + 1]
        XCTAssertGreaterThan(hiSide, 0.6 + 0.01, "supra-accentuare pe partea luminoasă"); XCTAssertLessThan(loSide, 0.3 - 0.01, "sub-accentuare pe partea întunecată")
        let i = (500 * 400 + 201) * 3; XCTAssertEqual(a[i] - a[i + 1], 0.05, accuracy: 1e-5, "diferența R−G (croma) nu se schimbă (aceeași deltă pe canale)")
    }
    func testResolutionIndependentOvershoot() {
        var s = DetailSettings(); s.sharpAmount = 1.0; s.sharpRadius = 1.5
        s.sharpRadius = 2.0
        var a = edge(400, 500); apply(&a, 400, 500, s); var b = edge(800, 1000); apply(&b, 800, 1000, s)   // aceeași imagine, de două ori mai mare
        let oa = a[(250 * 400 + 200) * 3 + 1] - 0.6, ob = b[(500 * 800 + 400) * 3 + 1] - 0.6
        XCTAssertGreaterThan(ob, 0.005); XCTAssertGreaterThan(oa, 0.005)
        XCTAssertEqual(oa, ob, accuracy: max(0.35 * ob, 0.01), "aceeași imagine la două rezoluții: supra-accentuare comparabilă (raze relative la înălțime)")
    }
    func testThresholdSuppressesFineNoiseAndClarityIsMidtoneWeighted() {
        var n = [Float](repeating: 0.5, count: 128 * 128 * 3)
        for i in 0..<(128 * 128) { let v: Float = 0.5 + (i % 2 == 0 ? 0.004 : -0.004); n[3 * i] = v; n[3 * i + 1] = v; n[3 * i + 2] = v }
        let n0 = n; var s = DetailSettings(); s.sharpAmount = 2; s.sharpRadius = 0.5; s.sharpThreshold = 0.02; apply(&n, 128, 128, s)
        for i in 0..<n.count { XCTAssertEqual(n[i], n0[i], accuracy: 1e-6) }
        var dark = edge(400, 400, lo: 0.02, hi: 0.06); let d0 = dark; var c = DetailSettings(); c.clarity = 1; apply(&dark, 400, 400, c)
        var mid = edge(400, 400, lo: 0.4, hi: 0.6); let m0 = mid; apply(&mid, 400, 400, c)
        let k = (200 * 400 + 201) * 3 + 1; let dd = abs(dark[k] - d0[k]), dm = abs(mid[k] - m0[k]); XCTAssertGreaterThan(dm, 0.005)
        XCTAssertLessThan(dd, dm, "claritatea acționează mai puțin în umbrele foarte întunecate decât în tonurile medii")
    }
    func testDetailIsPartOfFingerprintAndNeutrality() {
        var a = AdjustmentSet(); let f0 = a.fingerprint; a.detail.clarity = 0.3
        XCTAssertNotEqual(a.fingerprint, f0); XCTAssertFalse(a.isNeutral)
        var b = a; b.disabledModules.insert("detail"); XCTAssertTrue(b.effective.detail.isNeutral, "modulul dezactivat = neutru în procesare, valorile rămân"); XCTAssertEqual(b.detail.clarity, 0.3)
        let json = try! JSONEncoder().encode(a); XCTAssertEqual(try! JSONDecoder().decode(AdjustmentSet.self, from: json).detail.clarity, 0.3)
        let old = try! JSONDecoder().decode(AdjustmentSet.self, from: Data("{}".utf8)); XCTAssertTrue(old.detail.isNeutral, "salvările vechi fără «detail» rămân neutre")
    }

    // MARK: reducere de zgomot
    func rng(_ seed: UInt64) -> () -> Float { var x = seed; return { x = x &* 6364136223846793005 &+ 1442695040888963407; return Float((x >> 33) & 0xFFFFFF) / Float(0xFFFFFF) - 0.5 } }
    func std(_ a: [Float], _ idx: [Int]) -> Double { let m = idx.map { Double(a[$0]) }.reduce(0, +) / Double(idx.count); return (idx.map { pow(Double(a[$0]) - m, 2) }.reduce(0, +) / Double(idx.count)).squareRoot() }
    func testLumaNoiseReductionKeepsEdgesAndNeutralIsIdentity() {
        let w = 400, h = 400; var r = rng(7); var a = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h { for x in 0..<w { let base: Float = x < w / 2 ? 0.30 : 0.60; let nz = r() * 0.10; for c in 0..<3 { a[(y * w + x) * 3 + c] = base + nz } } }
        let flat = (0..<h).flatMap { y in (20..<150).map { y * w + $0 } }; let before = std(a.enumerated().filter { $0.offset % 3 == 1 }.map { $0.element }, flat)
        var s = DetailSettings(); s.nrLuma = 0.8; var b = a; apply(&b, w, h, s)
        let g = b.enumerated().filter { $0.offset % 3 == 1 }.map { $0.element }; let after = std(g, flat)
        XCTAssertLessThan(after, before * 0.5, "zgomotul din zona plată scade cu peste 50%")
        let step = (0..<h).map { y in Double(g[y * w + 230]) - Double(g[y * w + 170]) }.reduce(0, +) / Double(h); XCTAssertGreaterThan(step, 0.30 * 0.85, "treapta (muchia) păstrată ≥ 85%")
        var z = a; apply(&z, w, h, DetailSettings()); XCTAssertEqual(z, a)
    }
    func testChromaNoiseReductionDoesNotTouchLuminance() {
        let w = 300, h = 300; var r = rng(11); var a = [Float](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) { let c = r() * 0.12; a[i * 3] = 0.5 + c; a[i * 3 + 2] = 0.5 - c; a[i * 3 + 1] = 0.5 }
        func lum(_ p: [Float], _ i: Int) -> Double { 0.2126 * Double(p[i * 3]) + 0.7152 * Double(p[i * 3 + 1]) + 0.0722 * Double(p[i * 3 + 2]) }
        func chromaStd(_ p: [Float]) -> Double { let xs = (0..<(w * h)).map { Double(p[$0 * 3]) - lum(p, $0) }; let m = xs.reduce(0, +) / Double(xs.count); return (xs.map { pow($0 - m, 2) }.reduce(0, +) / Double(xs.count)).squareRoot() }
        var s = DetailSettings(); s.nrChroma = 0.9; var b = a; apply(&b, w, h, s)
        XCTAssertLessThan(chromaStd(b), chromaStd(a) * 0.4, "zgomotul de culoare scade cu peste 60%")
        let dl = (0..<(w * h)).map { abs(lum(b, $0) - lum(a, $0)) }.max()!; XCTAssertLessThan(dl, 2e-3, "luminanța nu se schimbă prin reducerea zgomotului de culoare")
    }
}
