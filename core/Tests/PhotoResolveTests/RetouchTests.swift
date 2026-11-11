import XCTest
@testable import PhotoResolve
import PhotoRaw

final class RetouchTests: XCTestCase {
    /// Gradient orizontal (0.2→0.6) cu «praf» întunecat la (0.30, 0.50) de rază 6 px la 200 px înălțime.
    func dusty(_ w: Int, _ h: Int) -> (dirty: [Float], clean: [Float]) {
        var clean = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h { for x in 0..<w { let v = 0.2 + 0.4 * Float(x) / Float(w); for c in 0..<3 { clean[(y * w + x) * 3 + c] = v } } }
        var dirty = clean; let cx = 0.30 * Double(w), cy = 0.5 * Double(h), r = 6.0 * Double(h) / 200
        for y in 0..<h { for x in 0..<w where hypot(Double(x) - cx, Double(y) - cy) < r { for c in 0..<3 { dirty[(y * w + x) * 3 + c] *= 0.4 } } }
        return (dirty, clean)
    }
    func maxErr(_ a: [Float], _ b: [Float], w: Int, h: Int) -> Float {
        let cx = 0.30 * Double(w), cy = 0.5 * Double(h), r = 6.0 * Double(h) / 200; var m: Float = 0
        for y in 0..<h { for x in 0..<w where hypot(Double(x) - cx, Double(y) - cy) < r { m = max(m, abs(a[(y * w + x) * 3 + 1] - b[(y * w + x) * 3 + 1])) } }
        return m
    }
    func testHealRemovesDustOnGradientAndCloneDoesNot() {
        let w = 600, h = 200; let (dirty, clean) = dusty(w, h)
        var s = RetouchSpot(); s.x = 0.30; s.y = 0.5; s.radius = 9.0 / 200; s.sx = 0.30; s.sy = 0.5 + 0.15; s.feather = 0.25   // sursă curată, mai jos pe același gradient
        s.mode = .heal; let healed = Retouch.apply([s], to: dirty, width: w, height: h)
        XCTAssertLessThan(maxErr(healed, clean, w: w, h: h), 0.02, "vindecarea restaurează gradientul sub 0,02")
        XCTAssertGreaterThan(maxErr(dirty, clean, w: w, h: h), 0.1, "praful era vizibil")
        XCTAssertEqual(dirty.count, healed.count); XCTAssertNotEqual(dirty, healed, "intrarea nu se modifică pe loc, rezultatul diferă")
    }
    func testNeutralDisabledAndOutsideUntouched() {
        let w = 300, h = 100; let (dirty, _) = dusty(w, h); var s = RetouchSpot(); s.enabled = false
        XCTAssertEqual(Retouch.apply([s], to: dirty, width: w, height: h), dirty, "dezactivat = identitate exactă")
        XCTAssertEqual(Retouch.apply([], to: dirty, width: w, height: h), dirty)
        var t = RetouchSpot(); t.x = 0.8; t.y = 0.2; t.sx = 0.7; t.sy = 0.2; t.radius = 0.03; let out = Retouch.apply([t], to: dirty, width: w, height: h)
        for y in 0..<h { for x in 0..<w where hypot(Double(x) - 0.8 * Double(w), Double(y) - 0.2 * Double(h)) > 0.03 * Double(h) * 1.05 { XCTAssertEqual(out[(y * w + x) * 3], dirty[(y * w + x) * 3]) } }
    }
    func testResolutionIndependentAndPartOfFingerprint() {
        var s = RetouchSpot(); s.x = 0.3; s.y = 0.5; s.sx = 0.3; s.sy = 0.65; s.radius = 0.04; s.mode = .clone
        let small = dusty(300, 100), big = dusty(600, 200)
        let a = Retouch.apply([s], to: small.dirty, width: 300, height: 100), b = Retouch.apply([s], to: big.dirty, width: 600, height: 200)
        XCTAssertEqual(a[(50 * 300 + 90) * 3 + 1], b[(100 * 600 + 180) * 3 + 1], accuracy: 0.02, "același rezultat relativ la două rezoluții")
        var adj = AdjustmentSet(); let f0 = adj.fingerprint; adj.retouch = [s]; XCTAssertNotEqual(adj.fingerprint, f0); XCTAssertFalse(adj.isNeutral)
        var off = adj; off.disabledModules.insert("retouch"); XCTAssertTrue(off.effective.retouch.isEmpty); XCTAssertEqual(off.retouch.count, 1)
        let j = try! JSONEncoder().encode(adj); XCTAssertEqual(try! JSONDecoder().decode(AdjustmentSet.self, from: j).retouch, [s])
        XCTAssertTrue(try! JSONDecoder().decode(AdjustmentSet.self, from: Data("{}".utf8)).retouch.isEmpty)
    }
    /// Fotografie reală (dacă există): retușul apare în intermediarul BAKED (aceeași destinație diferă, restul cadrului e identic bit cu bit).
    func testRetouchSurvivesBakedIntermediate() throws {
        guard let dir = ProcessInfo.processInfo.environment["GDC_PA_RAW_DIR"], let scratch = ProcessInfo.processInfo.environment["GDC_PA_SCRATCH"] else { throw XCTSkip("fără GDC_PA_RAW_DIR / GDC_PA_SCRATCH") }
        guard let first = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.sorted().first(where: { $0.lowercased().hasSuffix(".arw") }) else { throw XCTSkip("niciun RAW") }
        let photo = dir + "/" + first; let work = URL(fileURLWithPath: scratch).appendingPathComponent("retouch_\(UUID().uuidString.prefix(6))"); defer { try? FileManager.default.removeItem(at: work) }
        let proc = try OwnCoreProcessor(workDir: work)
        var clean = AdjustmentSet(); clean.exposure = 0.3
        var spot = RetouchSpot(); spot.mode = .clone; spot.x = 0.3; spot.y = 0.4; spot.sx = 0.7; spot.sy = 0.6; spot.radius = 0.05; spot.feather = 0.2
        var fixed = clean; fixed.retouch = [spot]
        let a = try proc.intermediateEXR(photoPath: photo, bake: clean), b = try proc.intermediateEXR(photoPath: photo, bake: fixed)
        XCTAssertTrue(a.baked && b.baked); XCTAssertNotEqual(a.url, b.url, "retușul trebuie să intre în identitatea intermediarului")
        let ia = try FloatImageIO.readEXR(a.url), ib = try FloatImageIO.readEXR(b.url); XCTAssertEqual(ia.width, ib.width)
        let w = ia.width, h = ia.height, cx = 0.3 * Double(w), cy = 0.4 * Double(h), R = 0.05 * Double(h)
        var inside = 0, changedInside = 0, changedOutside = 0
        for y in 0..<h { for x in 0..<w {
            let d = hypot(Double(x) - cx, Double(y) - cy); let i = 3 * (y * w + x); let diff = (0..<3).contains { abs(ia.rgb[i + $0] - ib.rgb[i + $0]) > 1e-6 }
            if d < R * 0.8 { inside += 1; if diff { changedInside += 1 } } else if d > R * 1.0001, diff { changedOutside += 1 } } }
        XCTAssertGreaterThan(Double(changedInside) / Double(max(1, inside)), 0.9, "destinația trebuie schimbată în BAKED")
        XCTAssertEqual(changedOutside, 0, "nimic în afara destinației nu se schimbă")
    }
}
