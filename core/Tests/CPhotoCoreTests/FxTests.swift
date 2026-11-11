import XCTest
import CPhotoCore

/// Efecte proprii: Optică (distorsiune, aberație cromatică, vinietă de obiectiv), Peliculă, Grain. Contract: identitate exactă la neutru, independență de rezoluție, măști ancorate sub distorsiune.
final class FxTests: XCTestCase {
    func params() -> pc_params { var p = pc_params(); pc_default_params(&p); p.drt = 0; p.inputIsLinear = 2; return p }   // intrare liniară DWG → ieșire cod DI (fără DRT)
    func geo(_ w: Int, _ h: Int) -> pc_geom { pc_geom(h: (1, 0, 0, 0, 1, 0, 0, 0, 1), srcW: Int32(w), srcH: Int32(h), outW: Int32(w), outH: Int32(h)) }
    func flat(_ w: Int, _ h: Int, _ v: Float) -> [Float] { [Float](repeating: v, count: w * h * 3) }
    func fxd() -> pc_fx { var f = pc_fx(); pc_default_fx(&f); return f }
    func run(_ p: pc_params, _ g: pc_geom, _ fx: pc_fx?, _ i: [Float], locals: [pc_local] = [], mask: [Double] = [], offs: [Int] = []) -> [Float] {
        var o = [Float](repeating: 0, count: Int(g.outW) * Int(g.outH) * 3); var pp = p, gg = g; var ff = fx ?? fxd()
        let r: Int32 = i.withUnsafeBufferPointer { a in o.withUnsafeMutableBufferPointer { b in locals.withUnsafeBufferPointer { l in
            if fx == nil { return pc_process_image_fx(&pp, l.baseAddress, Int32(locals.count), nil, nil, &gg, nil, a.baseAddress, b.baseAddress, 0) }
            return pc_process_image_fx(&pp, l.baseAddress, Int32(locals.count), nil, nil, &gg, &ff, a.baseAddress, b.baseAddress, 0) } } }
        XCTAssertEqual(r, 0); return o
    }
    func decode(_ code: Float) -> Double { pc_di_decode(Double(code)) }

    func testDefaultFxIsBitIdenticalToNoFx() {
        let w = 96, h = 64; var a = [Float](repeating: 0, count: w * h * 3); var s: UInt32 = 7; for i in a.indices { s = s &* 1664525 &+ 1013904223; a[i] = Float(s >> 8) / 16777216 * 2 }
        var g = geo(w, h); g.h = (0.93, 0.05, 2.1, -0.04, 0.97, 1.7, 0.00002, 0.00001, 1)   // omografie reală
        var p = params(); p.exposure = 0.3; p.saturation = 1.2
        let base = run(p, g, nil, a); let neutral = run(p, g, fxd(), a); XCTAssertEqual(base, neutral, "fx implicit = identic bit")
        var o = [Float](repeating: 0, count: base.count); var gg = g, pp = p; _ = a.withUnsafeBufferPointer { i in o.withUnsafeMutableBufferPointer { b in pc_process_image_geom(&pp, nil, 0, nil, nil, &gg, i.baseAddress, b.baseAddress, 0) } }; XCTAssertEqual(base, o, "identic cu API-ul anterior")
    }
    func testDistortRoundTripAndDirection() {
        var f = fxd(); let W = 6000, H = 4000
        for d in [-100.0, -30, 40, 100] { f.distortion = d
            for (x, y) in [(10.0, 20.0), (3000, 2000), (5990, 3990), (1234, 3456), (4500, 300)] {
                var dx = 0.0, dy = 0.0, ux = 0.0, uy = 0.0; pc_fx_distort(&f, Int32(W), Int32(H), x, y, &dx, &dy); pc_fx_undistort(&f, Int32(W), Int32(H), dx, dy, &ux, &uy)
                XCTAssertEqual(ux, x, accuracy: 1e-6); XCTAssertEqual(uy, y, accuracy: 1e-6) } }
        f.distortion = 50; var dx = 0.0, dy = 0.0; pc_fx_distort(&f, Int32(W), Int32(H), 6000, 4000, &dx, &dy)
        XCTAssertLessThan(hypot(dx - 3000, dy - 2000), hypot(3000.0, 2000), "+ corectează butoi: eșantionează mai aproape de centru la margini"); pc_fx_distort(&f, Int32(W), Int32(H), 3000, 2000, &dx, &dy); XCTAssertEqual(dx, 3000, accuracy: 1e-9)
    }
    func testChromaticAberrationShiftsOnlyRedBlueAwayFromCentre() {
        let w = 400, h = 100; var a = flat(w, h, 0.05); for y in 0..<h { for x in 380..<400 { for k in 0..<3 { a[(y * w + x) * 3 + k] = 0.8 } } }   // muchie lângă marginea dreaptă
        var f = fxd(); f.caRed = 100; f.caBlue = -100
        let o = run(params(), geo(w, h), f, a), n = run(params(), geo(w, h), nil, a)
        let row = 50; func edge(_ b: [Float], _ k: Int) -> Int { (0..<w).first { decode(b[(row * w + $0) * 3 + k]) > 0.4 } ?? -1 }
        XCTAssertEqual(edge(o, 1), edge(n, 1), "verdele neatins"); XCTAssertNotEqual(edge(o, 0), edge(n, 0), "roșul deplasat"); XCTAssertNotEqual(edge(o, 2), edge(n, 2), "albastrul deplasat")
        XCTAssertEqual(edge(o, 0) - edge(n, 0), -(edge(o, 2) - edge(n, 2)), "direcții opuse")
        XCTAssertEqual(o[(row * w + 5) * 3], n[(row * w + 5) * 3], accuracy: 1e-3)   // zona plată din stânga: neschimbată
    }
    func testLensVignetteGainFollowsRadiusSquared() {
        let w = 200, h = 100; var f = fxd(); f.lensVignette = 50
        let o = run(params(), geo(w, h), f, flat(w, h, 0.18)); let c = decode(o[(50 * w + 100) * 3]), e = decode(o[(0 * w + 0) * 3])
        XCTAssertEqual(c, 0.18, accuracy: 0.18 * 0.01, "centrul neschimbat"); XCTAssertEqual(e / 0.18, pow(2, 1.0), accuracy: 0.05, "colț ≈ +1 stop la 50")
    }
    func testFilmCurveProperties() {
        var f = fxd(); f.filmAmount = 100; f.filmToe = 0.6; f.filmShoulder = 0.7; f.filmContrast = 0.2
        let w = 512, h = 1; var a = [Float](repeating: 0, count: w * 3); for x in 0..<w { let v = Float(0.18 * pow(2.0, -10 + 20 * Double(x) / Double(w - 1))); for k in 0..<3 { a[x * 3 + k] = v } }
        let o = run(params(), geo(w, h), f, a); var prev = -1.0
        for x in 0..<w { let v = decode(o[x * 3]); XCTAssertGreaterThanOrEqual(v, prev - 1e-6, "monotonă"); XCTAssertTrue(v.isFinite); prev = v; XCTAssertEqual(o[x * 3], o[x * 3 + 1]); XCTAssertEqual(o[x * 3], o[x * 3 + 2], "neutrul rămâne neutru") }
        let mid = Int(round(10.0 / 20 * Double(w - 1))); XCTAssertEqual(decode(o[mid * 3]) / Double(a[mid * 3]), 1, accuracy: 0.03, "gri 18% păstrat")
        XCTAssertLessThan(decode(o[(w - 1) * 3]), 0.18 * pow(2, 8.0 - 5.5 * 0.7) * 1.05, "shoulder: asimptotă finită"); XCTAssertGreaterThan(decode(o[0]), -1e-9)
        var f0 = fxd(); f0.filmAmount = 0; f0.filmToe = 0.6; XCTAssertEqual(run(params(), geo(w, h), f0, a), run(params(), geo(w, h), nil, a), "amount 0 = identitate")
    }
    func testFilmSaturationLeavesGreyAndCrosstalkKeepsNeutral() {
        var f = fxd(); f.filmAmount = 100; f.filmSat = 0.5; f.filmCrosstalk = 0.2; f.filmToe = 0; f.filmShoulder = 0
        let o = run(params(), geo(1, 1), f, [0.18, 0.18, 0.18]); XCTAssertEqual(o[0], o[1], accuracy: 1e-6); XCTAssertEqual(o[1], o[2], accuracy: 1e-6)
        let c = run(params(), geo(1, 1), f, [0.4, 0.1, 0.05]); let cn = run(params(), geo(1, 1), nil, [0.4, 0.1, 0.05]); XCTAssertLessThan(abs(decode(c[0]) - decode(c[2])), abs(decode(cn[0]) - decode(cn[2])), "saturația/diafonia reduc distanța dintre canale")
    }
    func grainStats(h: Int, _ f: pc_fx) -> (mean: Double, std: Double, grad: Double, lin: Double) {
        let w = h * 2; let o = run(params(), geo(w, h), f, flat(w, h, 0.18)); var s = 0.0, s2 = 0.0, gs = 0.0, n = 0.0, gn = 0.0, sl = 0.0
        for y in 0..<h { for x in 0..<w { let v = log2(decode(o[(y * w + x) * 3]) / 0.18); sl += pow(2, v); s += v; s2 += v * v; n += 1; if x + 1 < w { let u = log2(decode(o[(y * w + x + 1) * 3]) / 0.18); gs += (u - v) * (u - v); gn += 1 } } }
        let m = s / n; return (m, (s2 / n - m * m).squareRoot(), (gs / gn).squareRoot(), sl / n)
    }
    func testGrainStatisticsDeterminismAndResolutionIndependence() {
        var f = fxd(); f.grainAmount = 100; f.grainChroma = 0; f.grainRough = 0; f.grainSize = 12
        let a = grainStats(h: 540, f), b = grainStats(h: 1080, f)
        XCTAssertEqual(a.std, 0.45, accuracy: 0.45 * 0.12, "σ în stopuri ≈ 0.45·amount"); XCTAssertEqual(b.std, 0.45, accuracy: 0.45 * 0.12)
        XCTAssertEqual(a.lin, 1, accuracy: 0.02, "media în LINIAR se păstrează (corecția de medie)")
        XCTAssertEqual((a.grad / a.std) / (b.grad / b.std), 2, accuracy: 0.5, "mărimea boabelor ∝ înălțimea livrabilului (gradient/σ ∝ 1/înălțime)")
        let w = 64, h = 64; let x1 = run(params(), geo(w, h), f, flat(w, h, 0.18)), x2 = run(params(), geo(w, h), f, flat(w, h, 0.18)); XCTAssertEqual(x1, x2, "determinist")
        var g = f; g.grainSeed = 2; XCTAssertNotEqual(x1, run(params(), geo(w, h), g, flat(w, h, 0.18)), "altă sămânță")
        var z = f; z.grainAmount = 0; XCTAssertEqual(run(params(), geo(w, h), z, flat(w, h, 0.18)), run(params(), geo(w, h), nil, flat(w, h, 0.18)), "amount 0 = identitate")
        let blk = run(params(), geo(w, h), f, flat(w, h, 0.0002)); XCTAssertEqual(blk, run(params(), geo(w, h), nil, flat(w, h, 0.0002)), "negrul adânc rămâne curat")
    }
    func testGrainChromaControlsChannelCorrelation() {
        let w = 128, h = 128; var f = fxd(); f.grainAmount = 100; f.grainSize = 1
        func corr(_ ch: Double) -> Double { var q = f; q.grainChroma = ch; let o = run(params(), geo(w, h), q, flat(w, h, 0.18)); var sr = 0.0, sg = 0.0, srg = 0.0, srr = 0.0, sgg = 0.0; let n = Double(w * h)
            for i in 0..<(w * h) { let r = log2(decode(o[i * 3])), g = log2(decode(o[i * 3 + 1])); sr += r; sg += g; srg += r * g; srr += r * r; sgg += g * g }
            let cov = srg / n - sr * sg / (n * n), vr = srr / n - pow(sr / n, 2), vg = sgg / n - pow(sg / n, 2); return cov / (vr * vg).squareRoot() }
        XCTAssertGreaterThan(corr(0), 0.95, "monocrom"); XCTAssertLessThan(abs(corr(1)), 0.1, "independent pe canale")
    }
    func testMaskStaysAnchoredToSourceUnderDistortion() {
        let w = 160, h = 100; var f = fxd(); f.distortion = 90
        var z = pc_zone(); pc_default_zone(&z); z.kind = 0; z.x1 = 0.85; z.y1 = 0.5; z.x2 = 0.08; z.y2 = 0.12; z.feather = 0.2
        var l = pc_local(); l.enabled = 1; l.zone = z; pc_default_params(&l.adj); l.adj.drt = 0; l.adj.exposure = 2
        let img = flat(w, h, 0.18), p = params(); let g = geo(w, h)
        let withFx = run(p, g, f, img, locals: [l]), globalOnly = run(p, g, f, img)
        var m = [Float](repeating: 0, count: w * h); var gg = g, zz = z, ff = f; m.withUnsafeMutableBufferPointer { pc_mask_image_geom_fx(&zz, nil, 0, &gg, &ff, $0.baseAddress, Int32(w), Int32(h)) }
        var agree = 0, n = 0; for i in 0..<(w * h) { let lit = decode(withFx[i * 3]) > decode(globalOnly[i * 3]) * 1.5; if m[i] > 0.98 || m[i] < 0.02 { n += 1; if lit == (m[i] > 0.5) { agree += 1 } } }
        XCTAssertGreaterThan(n, 1000); XCTAssertEqual(Double(agree) / Double(n), 1, accuracy: 0.001, "masca desenată = zona procesată")
        var z0 = m; var f0 = fxd(); z0.withUnsafeMutableBufferPointer { pc_mask_image_geom_fx(&zz, nil, 0, &gg, &f0, $0.baseAddress, Int32(w), Int32(h)) }
        XCTAssertNotEqual(m, z0, "distorsiunea mută zona față de fără optică")
    }

    /// Informativ (nu poartă): timpul la 24 MP cu toate efectele active vs fără efecte; verifică doar că rezultatul e finit și că costul e de ordinul secundelor.
    func testPerformanceAtFullResolutionIsReasonableAndFinite() {
        let w = 6000, h = 4000; var a = [Float](repeating: 0, count: w * h * 3); var s: UInt32 = 3; for i in stride(from: 0, to: a.count, by: 7) { s = s &* 1664525 &+ 1013904223; a[i] = Float(s >> 8) / 16777216 }
        var f = fxd(); f.distortion = 30; f.caRed = 20; f.caBlue = -20; f.lensVignette = 20; f.vignette = -30; f.filmAmount = 100; f.filmContrast = 0.1; f.grainAmount = 50
        let t0 = Date(); let base = run(params(), geo(w, h), nil, a); let t1 = Date(); let o = run(params(), geo(w, h), f, a); let t2 = Date()
        print(String(format: "FXPERF 24MP: fără efecte %.2fs · cu optică+peliculă+grain %.2fs", t1.timeIntervalSince(t0), t2.timeIntervalSince(t1)))
        XCTAssertTrue(o.allSatisfy { $0.isFinite }); XCTAssertEqual(base.count, o.count); XCTAssertLessThan(t2.timeIntervalSince(t1), 30)
    }

    func haloImage(_ h: Int) -> (w: Int, a: [Float]) {   // pătrat luminos (6 stopuri peste gri) pe fundal întunecat, scalat cu înălțimea
        let w = h * 2; var a = flat(w, h, 0.02); let s0 = h / 10; for y in (h / 2 - s0)..<(h / 2 + s0) { for x in (w / 2 - s0)..<(w / 2 + s0) { for k in 0..<3 { a[(y * w + x) * 3 + k] = 11 } } }; return (w, a)
    }
    func testHalationAddsWarmGlowOutsideBrightAreaAndScalesWithHeight() {
        var f = fxd(); f.halAmount = 100; f.halRadius = 5; f.halThreshold = 1.5; f.halWarm = 1
        func halfDistance(_ h: Int) -> Double {   // distanța (în fracții de înălțime) de la marginea sursei până unde glow-ul scade la jumătate din valoarea de lângă margine
            let (w, a) = haloImage(h); let o = run(params(), geo(w, h), f, a), n = run(params(), geo(w, h), nil, a); let s0 = h / 10, row = h / 2
            func glow(_ x: Int) -> Double { decode(o[(row * w + x) * 3]) - decode(n[(row * w + x) * 3]) }
            let edge = w / 2 + s0 + 1; let g0 = glow(edge); XCTAssertGreaterThan(g0, 0.0005, "glow vizibil lângă margine"); var d = 0; while edge + d < w - 1 && glow(edge + d) > g0 / 2 { d += 1 }; return Double(d) / Double(h) }
        let a = halfDistance(300), b = halfDistance(600); XCTAssertEqual(a, b, accuracy: max(0.01, a * 0.35), "raza e relativă la înălțime: \(a) vs \(b)")
        let (w, img) = haloImage(300); let o = run(params(), geo(w, 300), f, img), n = run(params(), geo(w, 300), nil, img); let x = w / 2 + 300 / 10 + 6, i = (150 * w + x) * 3
        let dr = decode(o[i]) - decode(n[i]), dg = decode(o[i + 1]) - decode(n[i + 1]), db = decode(o[i + 2]) - decode(n[i + 2]); XCTAssertGreaterThan(dr, dg * 2, "roșu domină la căldură 1"); XCTAssertGreaterThan(dg, db)
        let far = (10 * w + 10) * 3; XCTAssertEqual(decode(o[far]), decode(n[far]), accuracy: 1e-4, "departe de sursă: neschimbat")
    }
    func testHalationConservesEnergyAndIsOffBelowThreshold() {
        var f = fxd(); f.halAmount = 100; f.halWarm = 0
        let (w, a) = haloImage(300); let o = run(params(), geo(w, 300), f, a), n = run(params(), geo(w, 300), nil, a)
        var added = 0.0; for i in 0..<(w * 300) { added += (decode(o[i * 3]) - decode(n[i * 3])) }
        let s0 = 30, area = Double((2 * s0) * (2 * s0)), Y = 11.0, gate = 1.0; let expected = 0.5 * Y * gate * area       // amount·∫gate·Y (blur conservă integrala); roșu, w=1
        XCTAssertEqual(added, expected, accuracy: expected * 0.10, "energie adăugată ≈ cantitate·integrala sursei")
        let dim = flat(w, 300, 0.3); XCTAssertEqual(run(params(), geo(w, 300), f, dim).map { Float(decode($0)) }.prefix(3), run(params(), geo(w, 300), nil, dim).map { Float(decode($0)) }.prefix(3), "sub prag: neschimbat")
        var z = f; z.halAmount = 0; XCTAssertEqual(run(params(), geo(w, 300), z, a), n, "cantitate 0 = identitate exactă")
    }

    func testOpticsStageRunsInFullPipelineAfterLinearToolsAndOnlyWhenActive() throws {
        try XCTSkipIf(pc_edition_full() == 0, "Optics (difuzie + bloom) nu face parte din ediția cu sursă deschisă")
        let w = 120, h = 80; var a = flat(w, h, 0.05); for y in 30..<50 { for x in 50..<70 { for k in 0..<3 { a[(y * w + x) * 3 + k] = 12 } } }
        var p = params(); p.exposure = 0.2
        let off = run(p, geo(w, h), nil, a); var q = p; q.opDiffusion = 1; q.opFilter = 1; q.opStrength = 3
        let diff = run(q, geo(w, h), nil, a); XCTAssertNotEqual(off, diff, "difuzia schimbă imaginea prin calea completă")
        var bl = p; bl.opBloom = 1; bl.opThreshold = 1.5; let bloom = run(bl, geo(w, h), nil, a)
        let near = (40 * w + 74) * 3, far = (5 * w + 5) * 3; XCTAssertGreaterThan(decode(bloom[near]), decode(off[near]) * 1.02, "bloom adaugă lumină lângă zona luminoasă"); XCTAssertEqual(decode(bloom[far]), decode(off[far]), accuracy: 2e-3, "departe: neschimbat")
        var z = p; z.opDiffusion = 0; z.opBloom = 0; z.opMix = 0.3; XCTAssertEqual(run(z, geo(w, h), nil, a), off, "cantități 0 = identitate exactă")
        var m = bl; m.opMix = 0; XCTAssertEqual(run(m, geo(w, h), nil, a), off, "Mix 0 = identitate exactă")
    }
}
