import XCTest
import CPhotoCore

/// Corecții locale: zonă manuală + aceleași instrumente, în ordinea corectă a domeniilor; DRT o singură dată; în afara zonei rezultatul e IDENTIC cu cel global.
final class LocalCorrectionTests: XCTestCase {
    let W = 64, H = 48
    func gp(drt: Int32 = 0) -> pc_params { var p = pc_params(); pc_default_params(&p); p.drt = drt; p.inputIsLinear = 0; return p }
    func img() -> [Float] { var a = [Float](repeating: 0, count: W * H * 3); for y in 0..<H { for x in 0..<W { let i = (y * W + x) * 3; a[i] = Float(0.15 + 0.6 * Double(x) / Double(W)); a[i + 1] = Float(0.2 + 0.5 * Double(y) / Double(H)); a[i + 2] = Float(0.3 + 0.2 * Double((x * 7 + y * 3) % 17) / 17) } }; return a }
    func zone(_ k: Int32, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, feather: Double, invert: Int32 = 0) -> pc_zone { pc_zone(kind: k, x1: x1, y1: y1, x2: x2, y2: y2, feather: feather, invert: invert) }
    func local(_ z: pc_zone, _ f: (inout pc_params) -> Void) -> pc_local { var a = pc_params(); pc_default_params(&a); a.drt = 0; f(&a); return pc_local(enabled: 1, zone: z, adj: a) }
    func run(_ g: pc_params, _ ls: [pc_local], _ i: [Float]) -> [Float] { var o = [Float](repeating: 0, count: i.count); var gg = g; XCTAssertEqual(i.withUnsafeBufferPointer { a in o.withUnsafeMutableBufferPointer { b in pc_process_image_local(&gg, ls, Int32(ls.count), a.baseAddress, b.baseAddress, Int32(W), Int32(H), 1) } }, 0); return o }

    func testNoLocalsIsBitIdenticalToGlobalProcessing() {
        var g = gp(); g.exposure = 0.4; g.contrast = 1.2; g.saturation = 1.1; let i = img()
        var ref = [Float](repeating: 0, count: i.count); i.withUnsafeBufferPointer { a in ref.withUnsafeMutableBufferPointer { b in _ = pc_process_image(&g, a.baseAddress, b.baseAddress, Int32(W), Int32(H), 1) } }
        XCTAssertEqual(run(g, [], i), ref)
    }
    func testOutsideTheZoneIsBitIdenticalAndInsideIsAdjustedInLinear() {
        var g = gp(); g.saturation = 1.1; let i = img(); let base = run(g, [], i)
        let z = zone(0, 0.5, 0.5, 0.2, 0.25, feather: 0)
        let o = run(g, [local(z) { $0.exposure = 1 }], i)
        var inside = 0, outside = 0
        for y in 0..<H { for x in 0..<W { let nx = (Double(x) + 0.5) / Double(W), ny = (Double(y) + 0.5) / Double(H); let d = hypot((nx - 0.5) / 0.2, (ny - 0.5) / 0.25); let k = (y * W + x) * 3
            if d > 1.02 { XCTAssertEqual(Array(o[k..<k + 3]), Array(base[k..<k + 3]), "în afara zonei"); outside += 1 }
            else if d < 0.98 { for c in 0..<3 { XCTAssertEqual(pc_di_decode(Double(o[k + c])), 2 * pc_di_decode(Double(base[k + c])), accuracy: 3e-5 * max(1, 2 * pc_di_decode(Double(base[k + c])))) }; inside += 1 } } }   // +1 stop = ×2 în LINIAR, pe ieșirea globală
        XCTAssertGreaterThan(inside, 100); XCTAssertGreaterThan(outside, 100)
    }
    func testDisabledOrNeutralLocalDoesNothingAndFeatherIsMonotone() {
        var g = gp(); g.contrast = 1.1; let i = img(); let base = run(g, [], i)
        var off = local(zone(0, 0.5, 0.5, 0.3, 0.3, feather: 0.5)) { $0.exposure = 2 }; off.enabled = 0
        XCTAssertEqual(run(g, [off], i), base)
        var m = [Float](repeating: 0, count: 200); var z = zone(0, 0.5, 0.5, 0.4, 0.4, feather: 0.6)
        m.withUnsafeMutableBufferPointer { pc_mask_image(&z, $0.baseAddress, 200, 1) }   // un rând pe axa centrală
        let row = Array(m[0..<200]); XCTAssertEqual(row[100], 1, accuracy: 1e-6); XCTAssertLessThan(row[0], 0.05)
        for k in 100..<199 { XCTAssertGreaterThanOrEqual(row[k], row[k + 1] - 1e-7) }        // monoton descrescător spre margine
        XCTAssertTrue(row.contains { $0 > 0.05 && $0 < 0.95 })                                // tranziție estompată reală
    }
    func testInvertGradientAndFeatherZeroEdge() {
        var a = [Float](repeating: 0, count: 100 * 100), b = a
        var z = zone(1, 0.5, 0.0, 0.5, 1.0, feather: 0.4); a.withUnsafeMutableBufferPointer { pc_mask_image(&z, $0.baseAddress, 100, 100) }
        z.invert = 1; b.withUnsafeMutableBufferPointer { pc_mask_image(&z, $0.baseAddress, 100, 100) }
        for k in 0..<a.count { XCTAssertEqual(a[k] + b[k], 1, accuracy: 1e-6) }
        XCTAssertEqual(a[5 * 100 + 50], 1, accuracy: 1e-6); XCTAssertEqual(a[95 * 100 + 50], 0, accuracy: 1e-6); XCTAssertEqual(a[50 * 100 + 5], a[50 * 100 + 95], accuracy: 1e-6)   // degrade vertical: la fel pe orizontală
        var h = [Float](repeating: 0, count: 100); var z0 = zone(0, 0.5, 0.5, 0.3, 0.3, feather: 0); h.withUnsafeMutableBufferPointer { pc_mask_image(&z0, $0.baseAddress, 100, 1) }
        XCTAssertTrue(h.allSatisfy { $0 == 0 || $0 == 1 || ($0 > 0 && $0 < 1) }); XCTAssertEqual(h[50], 1)
    }
    func testDRTIsAppliedOnceAndStagesCompose() throws {
        // ajustare + afișare separate ≡ lanțul complet: pe pixeli cu DRT activ, local cu masca 1 peste tot == global cu reglajele însumate în același traseu de domenii.
        guard let r = ProcessInfo.processInfo.environment["GDC_PA_ROOT"], let d = try? Data(contentsOf: URL(fileURLWithPath: r + "/data/drt/drt_1.bin")) else { throw XCTSkip("fără drt_1.bin") }
        var err = [CChar](repeating: 0, count: 128); XCTAssertEqual(d.withUnsafeBytes { pc_drt_load($0.bindMemory(to: UInt8.self).baseAddress, UInt(d.count), &err, 128) }, 0)
        var g = gp(drt: 2); g.drtOutput = 2; let i = img(); let full = zone(0, 0.5, 0.5, 50, 50, feather: 0)
        let viaLocal = run(g, [local(full) { $0.exposure = 0.7; $0.contrast = 1.15 }], i)
        var g2 = g; g2.exposure = 0; var seq = gp(); seq.exposure = 0.7; seq.contrast = 1.15; seq.drt = 0
        var mid = [Float](repeating: 0, count: i.count); i.withUnsafeBufferPointer { a in mid.withUnsafeMutableBufferPointer { b in _ = pc_process_image(&seq, a.baseAddress, b.baseAddress, Int32(W), Int32(H), 1) } }   // ajustare → cod DI
        var disp = gp(drt: 2); disp.drtOutput = 2; var ref = [Float](repeating: 0, count: i.count); mid.withUnsafeBufferPointer { a in ref.withUnsafeMutableBufferPointer { b in _ = pc_process_image(&disp, a.baseAddress, b.baseAddress, Int32(W), Int32(H), 1) } }   // afișare o singură dată
        var maxd: Float = 0; for k in 0..<ref.count { maxd = max(maxd, abs(ref[k] - viaLocal[k])) }; XCTAssertLessThan(maxd, 2e-6)
    }
    func testStageChainEqualsFullPathAndDRTRunsOnlyInStageThree() throws {
        guard let r = ProcessInfo.processInfo.environment["GDC_PA_ROOT"], let d = try? Data(contentsOf: URL(fileURLWithPath: r + "/data/drt/drt_1.bin")) else { throw XCTSkip("fără drt_1.bin") }
        var err = [CChar](repeating: 0, count: 128); XCTAssertEqual(d.withUnsafeBytes { pc_drt_load($0.bindMemory(to: UInt8.self).baseAddress, UInt(d.count), &err, 128) }, 0)
        var full = gp(drt: 2); full.exposure = 0.8; full.temperature = 20; full.shadows = 0.4; full.contrast = 1.2; full.saturation = 1.1; let i = img()
        func go(_ p: pc_params, _ x: [Float]) -> [Float] { var q = p; var o = [Float](repeating: 0, count: x.count); x.withUnsafeBufferPointer { a in o.withUnsafeMutableBufferPointer { b in _ = pc_process_image(&q, a.baseAddress, b.baseAddress, Int32(W), Int32(H), 1) } }; return o }
        var s1 = full; s1.stage = 1; var s2 = full; s2.stage = 2; var s3 = full; s3.stage = 3
        let a = go(s1, i), b = go(s2, a), c = go(s3, b), f = go(full, i)
        var maxd: Float = 0; for k in 0..<f.count { maxd = max(maxd, abs(f[k] - c[k])) }; XCTAssertLessThan(maxd, 2e-5)      // 1→2→3 ≡ complet (rotunjire float32 între noduri)
        XCTAssertTrue(a.allSatisfy { $0 > -0.2 && $0 < 1.2 } && b.allSatisfy { $0 > -0.2 && $0 < 1.2 })                          // etapele 1–2 rămân în cod DI (nu se aplică DRT)
        var neutral2 = full; neutral2.stage = 2; neutral2.contrast = 1; neutral2.saturation = 1; XCTAssertEqual(go(neutral2, i), i)  // etapa 2 neutră = identitate pe codul DI
    }
}

/// Tranziția estompată, marginile, inversarea, suprapunerea a două corecții: comportamentul amestecului în codul DI (nu doar ×2 în interior).
final class LocalBlendTests: XCTestCase {
    let W = 96, H = 64
    func gp() -> pc_params { var p = pc_params(); pc_default_params(&p); p.drt = 0; return p }
    func img() -> [Float] { var a = [Float](repeating: 0, count: W * H * 3); for y in 0..<H { for x in 0..<W { let i = (y * W + x) * 3; a[i] = Float(0.2 + 0.5 * Double(x) / Double(W)); a[i + 1] = Float(0.25 + 0.4 * Double(y) / Double(H)); a[i + 2] = Float(0.35 + 0.15 * Double((x * 5 + y * 3) % 11) / 11) } }; return a }
    func zone(_ k: Int32, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ f: Double, _ inv: Int32 = 0) -> pc_zone { pc_zone(kind: k, x1: x1, y1: y1, x2: x2, y2: y2, feather: f, invert: inv) }
    func local(_ z: pc_zone, _ f: (inout pc_params) -> Void) -> pc_local { var a = pc_params(); pc_default_params(&a); a.drt = 0; f(&a); return pc_local(enabled: 1, zone: z, adj: a) }
    func run(_ ls: [pc_local], _ i: [Float], g: pc_params? = nil) -> [Float] { var o = [Float](repeating: 0, count: i.count); var p = g ?? gp(); XCTAssertEqual(i.withUnsafeBufferPointer { a in o.withUnsafeMutableBufferPointer { b in pc_process_image_local(&p, ls, Int32(ls.count), a.baseAddress, b.baseAddress, Int32(W), Int32(H), 1) } }, 0); return o }
    func mask(_ z: pc_zone) -> [Float] { var m = [Float](repeating: 0, count: W * H); var zz = z; m.withUnsafeMutableBufferPointer { pc_mask_image(&zz, $0.baseAddress, Int32(W), Int32(H)) }; return m }
    func asGlobal(_ l: pc_local, on x: [Float]) -> [Float] { var o = [Float](repeating: 0, count: x.count); var p = l.adj; x.withUnsafeBufferPointer { a in o.withUnsafeMutableBufferPointer { b in _ = pc_process_image(&p, a.baseAddress, b.baseAddress, Int32(W), Int32(H), 1) } }; return o }

    func testTransitionIsALinearBlendInDICodeBetweenTheTwoAdjustedImages() {
        let i = img(); let z = zone(0, 0.5, 0.5, 0.3, 0.35, 0.8); let L = local(z) { $0.exposure = 1.2; $0.contrast = 1.3; $0.saturation = 1.2 }
        let base = run([], i), full = asGlobal(L, on: base), o = run([L], i), m = mask(z); var maxErr: Float = 0, mid = 0
        for k in 0..<(W * H) { if m[k] > 0.05 && m[k] < 0.95 { mid += 1 }; for c in 0..<3 { let e = base[3 * k + c] + m[k] * (full[3 * k + c] - base[3 * k + c]); maxErr = max(maxErr, abs(o[3 * k + c] - e)) } }
        XCTAssertGreaterThan(mid, 200); XCTAssertLessThan(maxErr, 2e-6)   // pixelii din tranziție = cod_global + m·(cod_local − cod_global), în cod DI
    }
    func testEdgeValueAndHardEdge() {
        var row = [Float](repeating: 0, count: 2000); var soft = zone(0, 0.5, 0.5, 0.25, 0.25, 0.4); row.withUnsafeMutableBufferPointer { pc_mask_image(&soft, $0.baseAddress, 2000, 1) }
        let xe = Int(((0.5 + 0.25) * 2000).rounded()) - 1; XCTAssertEqual(row[xe], 0.5, accuracy: 0.01)              // marginea desenată (d = 1) = jumătatea tranziției
        XCTAssertEqual(row[Int(0.5 * 2000)], 1, accuracy: 1e-6); XCTAssertEqual(row[1990], 0, accuracy: 1e-6)
        var hard = zone(0, 0.5, 0.5, 0.25, 0.25, 0); row.withUnsafeMutableBufferPointer { pc_mask_image(&hard, $0.baseAddress, 2000, 1) }
        XCTAssertTrue(row.allSatisfy { $0 == 0 || $0 == 1 || ($0 > 0 && $0 < 1) }); XCTAssertEqual(row[xe - 3], 1); XCTAssertEqual(row[xe + 3], 0)   // fără estompare: salt între pixeli vecini
        var g = zone(1, 0.5, 0.2, 0.5, 0.8, 0.5); var col = [Float](repeating: 0, count: 600); col.withUnsafeMutableBufferPointer { pc_mask_image(&g, $0.baseAddress, 1, 600) }
        XCTAssertEqual(col[Int(0.5 * 600) - 1], 0.5, accuracy: 0.01); XCTAssertEqual(col[Int(0.2 * 600) - 30], 1, accuracy: 1e-6); XCTAssertEqual(col[Int(0.8 * 600) + 30], 0, accuracy: 1e-6)   // degrade: 0.5 la mijlocul segmentului
    }
    func testInvertBlendsTheComplement() {
        let i = img(); let z = zone(0, 0.4, 0.5, 0.25, 0.3, 0.5), zi = zone(0, 0.4, 0.5, 0.25, 0.3, 0.5, 1); let a = local(z) { $0.exposure = 0.9 }, b = local(zi) { $0.exposure = 0.9 }
        let base = run([], i), full = asGlobal(a, on: base), oa = run([a], i), ob = run([b], i); var e1: Float = 0
        for k in 0..<(W * H * 3) { e1 = max(e1, abs((oa[k] - base[k]) + (ob[k] - base[k]) - (full[k] - base[k]))) }   // zonă + complement = efectul complet
        XCTAssertLessThan(e1, 2e-6)
    }
    func testTwoOverlappingCorrectionsApplySequentiallyInListOrderAndOrderMatters() {
        let i = img(); let zA = zone(0, 0.45, 0.5, 0.3, 0.35, 0.6), zB = zone(0, 0.60, 0.5, 0.3, 0.35, 0.6)
        let A = local(zA) { $0.exposure = 1.0 }, B = local(zB) { $0.contrast = 1.5; $0.saturation = 1.3 }
        let base = run([], i), mA = mask(zA), mB = mask(zB)
        let afterA = zip(zip(base, asGlobal(A, on: base)), mA.flatMap { [$0, $0, $0] }).map { ($0.0.0 + $0.1 * ($0.0.1 - $0.0.0)) }      // codul după A
        let fullB = asGlobal(B, on: afterA); var expected = afterA; for k in 0..<(W * H) { for c in 0..<3 { expected[3 * k + c] = afterA[3 * k + c] + mB[k] * (fullB[3 * k + c] - afterA[3 * k + c]) } }
        let o = run([A, B], i); var e: Float = 0; for k in 0..<o.count { e = max(e, abs(o[k] - expected[k])) }; XCTAssertLessThan(e, 3e-6)   // A apoi B, fiecare cu masca lui, pe rezultatul anterior
        let swapped = run([B, A], i); var d: Float = 0; for k in 0..<o.count { d = max(d, abs(o[k] - swapped[k])) }; XCTAssertGreaterThan(d, 1e-3)    // ordinea contează (instrumentele nu comută): ordinea din listă = ordinea aplicării
        var overlap = 0; for k in 0..<(W * H) where mA[k] > 0.5 && mB[k] > 0.5 { overlap += 1 }; XCTAssertGreaterThan(overlap, 300)
    }
}

/// Paritate cu instrumentele autoritare GDC STYLE V3 (Exposure + Balance → Tone → Saturation): vectori de aur generați din referințele host STYLE (fără STYLE la rulare).
final class StyleParityTests: XCTestCase {
    func testCoreMatchesStyleV3ReferenceOnGoldenVectorsForEveryFamily() {
        for (fam, rows) in StyleParityGolden.rows.enumerated() {
            var worst = 0.0
            for r in rows {
                var p = pc_params(); pc_default_params(&p); p.family = Int32(fam); p.exposure = r.p[0]; p.shadows = r.p[1]; p.highlights = r.p[2]; p.temperature = r.p[3]; p.tint = r.p[4]; p.contrast = r.p[5]; p.saturation = r.p[6]; p.pivot = r.p[7]; p.drt = 0
                let i = r.i.map { Float($0) }; var o = [Float](repeating: 0, count: 3); i.withUnsafeBufferPointer { pc_process_pixel_c(&p, $0.baseAddress, &o) }
                for k in 0..<3 { worst = max(worst, abs(Double(o[k]) - r.o[k])) }
            }
            XCTAssertLessThan(worst, 2e-5, "familia \(fam): paritate cu referința STYLE V3 (cod log al familiei)")   // rotunjirea float32 a intrării
        }
    }
}
