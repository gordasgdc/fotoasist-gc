import XCTest
@testable import PhotoResolve

/// Vectorscop: matematica pe culori și neutre CUNOSCUTE (Rec.709 YCbCr), separată de desen. Valorile de referință sunt derivate independent din coeficienții Rec.709 (Kr = 0,2126, Kb = 0,0722).
final class VectorscopeMathTests: XCTestCase {
    func uniform(_ r: Float, _ g: Float, _ b: Float, count: Int = 64) -> [Float] { (0..<count).flatMap { _ in [r, g, b] } }
    func testNeutralsLandOnTheCentreCell() {
        let n = 256
        for v: Float in [0, 0.18, 0.5, 0.73, 1] {
            let d = PhotoAnalysis.vectorscopeDensity(finalRGB: uniform(v, v, v), size: n); XCTAssertEqual(d.total, 64)
            let c = PhotoAnalysis.vectorscopeCell(cb: 0, cr: 0, size: n); XCTAssertEqual(c.x, n / 2); XCTAssertEqual(c.y, n / 2)
            XCTAssertEqual(d.counts[c.y * n + c.x], 64, "gri \(v): toți pixelii în celula centrală")
        }
    }
    func testKnownColoursMatchRec709Chroma() {
        // 100% și 75%: Cb = (B−Y)/1,8556, Cr = (R−Y)/1,5748, cu Y = 0,2126R + 0,7152G + 0,0722B (calculat de mână)
        let cases: [(String, Float, Float, Float, Float, Float)] = [   // nume, R, G, B, Cb așteptat, Cr așteptat
            ("roșu 100%", 1, 0, 0, -0.114572, 0.5), ("albastru 100%", 0, 0, 1, 0.5, -0.045847), ("verde 100%", 0, 1, 0, -0.385428, -0.454153),
            ("roșu 75%", 0.75, 0, 0, -0.085929, 0.375), ("galben 75%", 0.75, 0.75, 0, -0.404, 0.0)]
        for (name, r, g, b, cb, cr) in cases where name != "galben 75%" {
            let (gcb, gcr) = PhotoAnalysis.cbcr(r, g, b); XCTAssertEqual(gcb, cb, accuracy: 2e-5, name); XCTAssertEqual(gcr, cr, accuracy: 2e-5, name)
        }
        let (ycb, ycr) = PhotoAnalysis.cbcr(0.75, 0.75, 0); let y = 0.2126 * 0.75 + 0.7152 * 0.75; XCTAssertEqual(ycb, (0 - Float(y)) / 1.8556, accuracy: 1e-6); XCTAssertEqual(ycr, (0.75 - Float(y)) / 1.5748, accuracy: 1e-6)
    }
    func testDensityCellAndDrawnTargetUseTheSameMapping() {
        let n = 256
        for t in PhotoAnalysis.vectorscopeTargets {
            let d = PhotoAnalysis.vectorscopeDensity(finalRGB: uniform(t.r, t.g, t.b), size: n)
            let pos = PhotoAnalysis.vectorscopePosition(r: t.r, g: t.g, b: t.b)
            let x = Int(pos.x * Float(n)), y = Int(pos.y * Float(n))
            XCTAssertEqual(d.counts[y * n + x], 64, "ținta \(t.name): celula densității = poziția desenată")
        }
    }
    func testBothAxesAreOrientedLikeAVideoVectorscope() {
        let n = 256; let red = PhotoAnalysis.vectorscopePosition(r: 1, g: 0, b: 0), blue = PhotoAnalysis.vectorscopePosition(r: 0, g: 0, b: 1)
        XCTAssertLessThan(red.y, 0.5, "roșul (Cr+) e în partea de sus"); XCTAssertGreaterThan(blue.x, 0.5, "albastrul (Cb+) e în dreapta")
        let skin = PhotoAnalysis.vectorscopePosition(r: 0.85, g: 0.6, b: 0.5); XCTAssertGreaterThan(skin.y, 0) ; XCTAssertLessThan(skin.y, 0.5, "tonurile de piele sunt în semiplanul Cr+")
        XCTAssertEqual(PhotoAnalysis.vectorscopeSize, n)
    }
    func testNonFinitePixelsAreIgnoredAndRasterIsDensityOnly() {
        let d = PhotoAnalysis.vectorscopeDensity(finalRGB: [Float.nan, 0.5, 0.5, 0.5, 0.5, 0.5, 2, -1, 0.5]); XCTAssertEqual(d.total, 2, "NaN ignorat; valorile din afara 0…1 se limitează")
        let r = PhotoAnalysis.vectorscopeRaster(d); XCTAssertEqual(r.count, 256 * 256 * 4)
        let opaque = stride(from: 3, to: r.count, by: 4).filter { r[$0] > 0 }.count; XCTAssertLessThanOrEqual(opaque, 2, "fundal transparent: grila nu e în raster (desen separat)")
    }
}
