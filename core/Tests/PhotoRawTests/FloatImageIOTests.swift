import XCTest
@testable import PhotoRaw

final class FloatImageIOTests: XCTestCase {
    /// EXR float32 păstrează valori negative, >1 și cele mici EXACT (bit cu bit) la scriere + recitire.
    func testEXRRoundTripKeepsNegativesAndOverRange() throws {
        let w = 17, h = 9; var v = [Float]()
        for i in 0..<(w * h * 3) { let t = Float(i) / Float(w * h * 3); v.append(i % 5 == 0 ? -0.8 * t - 0.0001 : (i % 7 == 0 ? 1 + 2.5 * t : t * 0.7311 + 0.00123)) }   // determinist (reproductibil din Python)
        let base = ProcessInfo.processInfo.environment["GDC_PA_SCRATCH"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = base.appendingPathComponent("gdc_pa_rt_\(UUID().uuidString).exr"); defer { if ProcessInfo.processInfo.environment["GDC_PA_KEEP"] == nil { try? FileManager.default.removeItem(at: url) } }
        try FloatImageIO.writeEXR(FloatImage(width: w, height: h, rgb: v), to: url)
        let back = try FloatImageIO.readEXR(url)
        XCTAssertEqual(back.width, w); XCTAssertEqual(back.height, h)
        let maxd = zip(v, back.rgb).map { abs($0 - $1) }.max() ?? 1
        print("EXR roundtrip max abs diff:", maxd)
        XCTAssertEqual(maxd, 0, accuracy: 0)
    }
}

/// Cazuri-limită ale scriitorului EXR propriu (dimensiuni care nu se împart la 16, 1×1, 1 rând, date incompresibile → revenire la blocuri necomprimate, valori speciale).
/// Scrie și fișierele de probă în GDC_PA_SCRATCH, pentru verificarea cu cititori independenți (`scripts/verify_exr_writer.py`).
final class EXRWriterEdgeTests: XCTestCase {
    static func pattern(_ w: Int, _ h: Int, noisy: Bool) -> [Float] {
        var v = [Float](repeating: 0, count: w * h * 3); var s: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<v.count {
            if noisy { s = s &* 6364136223846793005 &+ 1442695040888963407; v[i] = Float(bitPattern: UInt32(truncatingIfNeeded: s >> 33) & 0x7F7F_FFFF) / 1e38 }   // bit-aleator finit, practic incompresibil
            else { let t = Float(i) / Float(v.count); v[i] = i % 5 == 0 ? -0.8 * t - 1e-4 : (i % 7 == 0 ? 1 + 31 * t : t * 0.7311 + 0.00123) }
        }
        return v
    }
    func testEdgeSizesRoundTripExactAndWriteProbeFiles() throws {
        let base = ProcessInfo.processInfo.environment["GDC_PA_SCRATCH"].map { URL(fileURLWithPath: $0).appendingPathComponent("exr_edge") } ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exr_edge_\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let cases: [(Int, Int, Bool)] = [(1, 1, false), (7, 1, false), (1, 33, false), (17, 9, false), (64, 16, false), (65, 17, false), (300, 50, true), (33, 129, false)]
        for (w, h, noisy) in cases {
            let img = FloatImage(width: w, height: h, rgb: EXRWriterEdgeTests.pattern(w, h, noisy: noisy)); let u = base.appendingPathComponent("edge_\(w)x\(h)_\(noisy ? "noisy" : "smooth").exr")
            try FloatImageIO.writeEXR(img, to: u); let back = try FloatImageIO.readEXR(u)
            XCTAssertEqual(back.width, w); XCTAssertEqual(back.height, h); XCTAssertEqual(back.rgb, img.rgb, "\(w)x\(h) noisy=\(noisy)")
        }
    }
    func testRejectsInvalidSizes() {
        XCTAssertThrowsError(try FloatImageIO.writeEXR(FloatImage(width: 0, height: 4, rgb: []), to: URL(fileURLWithPath: "/tmp/x.exr")))
        XCTAssertThrowsError(try FloatImageIO.writeEXR(FloatImage(width: 2, height: 2, rgb: [0, 1]), to: URL(fileURLWithPath: "/tmp/x.exr")))
    }
}
