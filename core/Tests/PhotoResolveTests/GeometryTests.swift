import XCTest
import CPhotoCore
@testable import PhotoResolve

final class GeometryTests: XCTestCase {
    func map(_ g: Geometry, _ x: Double, _ y: Double, _ w: Int, _ h: Int) -> (Double, Double) { let p = g.plan(srcW: w, srcH: h); let hh = p.h; let ww = hh[6] * x + hh[7] * y + hh[8]; return ((hh[0] * x + hh[1] * y + hh[2]) / ww, (hh[3] * x + hh[4] * y + hh[5]) / ww) }

    func testNeutralPlanIsIdentityAndKeepsFingerprintEmpty() {
        let g = Geometry(); XCTAssertTrue(g.isNeutral); XCTAssertEqual(g.fingerprint, ""); let p = g.plan(srcW: 600, srcH: 400); XCTAssertEqual(p.outW, 600); XCTAssertEqual(p.outH, 400)
        let (sx, sy) = map(g, 10.5, 20.5, 600, 400); XCTAssertEqual(sx, 10.5, accuracy: 1e-9); XCTAssertEqual(sy, 20.5, accuracy: 1e-9)
        var a = AdjustmentSet(); a.exposure = 1; let f = a.fingerprint; a.geometry.angle = 2; XCTAssertNotEqual(a.fingerprint, f); XCTAssertTrue(a.isNeutral == false || a.exposure != 0)
    }
    func testRotate90FlipsAndOutputSizes() {
        var g = Geometry(); g.rotate90 = 1; var p = g.plan(srcW: 200, srcH: 100); XCTAssertEqual(p.outW, 100); XCTAssertEqual(p.outH, 200)
        // sursă (60,40) → 90° orar → (srcH − y, x) = (60, 60) în ieșire: harta ieșire→sursă o inversează
        let (sx, sy) = map(g, 60.0, 60.0, 200, 100); XCTAssertEqual(sx, 60, accuracy: 1e-9); XCTAssertEqual(sy, 40, accuracy: 1e-9)
        for k in 0...3 { var q = Geometry(); q.rotate90 = k; let back = q.sourceToOutput(60, 40, srcW: 200, srcH: 100)!; let fwd = map(q, back.x, back.y, 200, 100); XCTAssertEqual(fwd.0, 60, accuracy: 1e-6); XCTAssertEqual(fwd.1, 40, accuracy: 1e-6) }
        g = Geometry(); g.flipH = true; let o = g.sourceToOutput(10, 10, srcW: 200, srcH: 100)!; XCTAssertEqual(o.x, 190, accuracy: 1e-9); XCTAssertEqual(o.y, 10, accuracy: 1e-9)
        g = Geometry(); g.flipV = true; let v = g.sourceToOutput(10, 10, srcW: 200, srcH: 100)!; XCTAssertEqual(v.y, 90, accuracy: 1e-9)
        p = Geometry().plan(srcW: 200, srcH: 100); XCTAssertEqual(p.orientedW, 200)
    }
    func testFineRotationIsClockwiseAboutCentreAndCropSetsPixelSize() {
        var g = Geometry(); g.angle = 90       // 90° orar în jurul centrului: punctul din dreapta-centru ajunge jos-centru
        let o = g.sourceToOutput(300, 200, srcW: 400, srcH: 400)!; XCTAssertEqual(o.x, 200, accuracy: 1e-6); XCTAssertEqual(o.y, 300, accuracy: 1e-6)
        g = Geometry(); g.crop = CropRect(x: 0.25, y: 0.1, w: 0.5, h: 0.6); let p = g.plan(srcW: 1000, srcH: 500); XCTAssertEqual(p.outW, 500); XCTAssertEqual(p.outH, 300)
        let (sx, sy) = map(g, 0.5, 0.5, 1000, 500); XCTAssertEqual(sx, 250.5, accuracy: 1e-9); XCTAssertEqual(sy, 50.5, accuracy: 1e-9)
        // aceeași definiție la altă rezoluție (previzualizare vs export)
        let p2 = g.plan(srcW: 2000, srcH: 1000); XCTAssertEqual(p2.outW, 1000); XCTAssertEqual(p2.outH, 600)
    }
    func testAutoCropRemovesEmptyEdgesWithoutHiddenLoss() {
        var g = Geometry(); g.angle = 7; XCTAssertGreaterThan(g.emptyFraction(srcW: 900, srcH: 600), 0.03, "rotirea lasă margini goale")
        let c = Geometry.autoCrop(angle: 7, orientedW: 900, orientedH: 600); g.crop = c
        XCTAssertEqual(g.emptyFraction(srcW: 900, srcH: 600), 0, accuracy: 1e-9); XCTAssertEqual(c.w * 900 / (c.h * 600), 900.0 / 600, accuracy: 1e-6, "aceeași proporție"); XCTAssertLessThan(c.w, 1); XCTAssertGreaterThan(c.w, 0.7)
        let wide = Geometry.autoCrop(angle: 7, orientedW: 900, orientedH: 600, aspect: 1); g.crop = wide; XCTAssertEqual(g.emptyFraction(srcW: 900, srcH: 600), 0, accuracy: 1e-9); XCTAssertEqual(wide.w * 900, wide.h * 600, accuracy: 1e-6)
        XCTAssertEqual(Geometry.autoCrop(angle: 0, orientedW: 900, orientedH: 600).w, 1, accuracy: 1e-9)
        let cc = Geometry.centeredCrop(aspect: 1, orientedW: 900, orientedH: 600); XCTAssertEqual(cc.w * 900, 600, accuracy: 1e-9); XCTAssertEqual(cc.h, 1, accuracy: 1e-9)
    }
    /// Masca rămâne pe aceeași zonă a fotografiei după rotire 90°, rotire fină și decupare (centroidul zonei modificate urmează punctul sursă).
    func testMaskStaysOnTheSamePhotoAreaAfterGeometry() {
        let W = 200, H = 100; var img = [Float](repeating: 0.18, count: W * H * 3)
        var l = LocalCorrection(); l.components[0].x1 = 0.3; l.components[0].y1 = 0.4; l.components[0].x2 = 0.06; l.components[0].y2 = 0.12; l.components[0].feather = 0.2; l.exposure = 2
        let sxp = 0.3 * Double(W), syp = 0.4 * Double(H)
        var g1 = Geometry(); g1.rotate90 = 1; var g2 = Geometry(); g2.angle = 12; g2.crop = Geometry.autoCrop(angle: 12, orientedW: 200, orientedH: 100); var g3 = Geometry(); g3.flipH = true; g3.rotate90 = 3; g3.crop = CropRect(x: 0.05, y: 0.1, w: 0.8, h: 0.8)
        let geos: [Geometry] = [g1, g2, g3]
        for geo in geos {
            func render(_ locals: [LocalCorrection]) -> ([Float], Int, Int) {
                var p = pc_params(); pc_default_params(&p); p.drt = 0; p.inputIsLinear = 1; let plan = geo.plan(srcW: W, srcH: H); var g = makeGeom(plan, srcW: W, srcH: H); let cm = LocalCorrection.coreMasks(locals); var offs = cm.offsets
                var out = [Float](repeating: 0, count: plan.outW * plan.outH * 3)
                let rc = img.withUnsafeBufferPointer { i in out.withUnsafeMutableBufferPointer { o in cm.data.withUnsafeBufferPointer { md in offs.withUnsafeMutableBufferPointer { op in pc_process_image_geom(&p, cm.locals, Int32(cm.locals.count), md.baseAddress, op.baseAddress, &g, i.baseAddress!, o.baseAddress!, 1) } } } }; XCTAssertEqual(rc, 0); return (out, plan.outW, plan.outH) }
            let on = render([l]), off = render([]); var sx = 0.0, sy = 0.0, n = 0.0
            for y in 0..<on.2 { for x in 0..<on.1 { let i = (y * on.1 + x) * 3; let d = Double(on.0[i] - off.0[i]); if d > 0.05 { sx += Double(x) + 0.5; sy += Double(y) + 0.5; n += 1 } } }
            XCTAssertGreaterThan(n, 20); let expect = geo.sourceToOutput(sxp, syp, srcW: W, srcH: H)!
            XCTAssertEqual(sx / n, expect.x, accuracy: 1.5, "centroid x"); XCTAssertEqual(sy / n, expect.y, accuracy: 1.5, "centroid y")
        }
    }
    func testNoContentIsInventedOutsideTheSource() {
        let W = 60, H = 40; let img = [Float](repeating: 0.5, count: W * H * 3); var g0 = Geometry(); g0.angle = 15; var p = pc_params(); pc_default_params(&p); p.drt = 0; p.inputIsLinear = 1
        let plan = g0.plan(srcW: W, srcH: H); var g = makeGeom(plan, srcW: W, srcH: H); var out = [Float](repeating: 9, count: plan.outW * plan.outH * 3)
        _ = img.withUnsafeBufferPointer { i in out.withUnsafeMutableBufferPointer { o in pc_process_image_geom(&p, nil, 0, nil, nil, &g, i.baseAddress!, o.baseAddress!, 1) } }
        XCTAssertEqual(out[0], 0, accuracy: 1e-6, "colț gol = negru, nu umplere"); XCTAssertTrue(out.contains { $0 > 0.2 }, "interiorul are conținut"); XCTAssertTrue(out.allSatisfy { $0.isFinite })
    }
    func testGeometryPersistsInAdjustmentJSON() throws {
        var a = AdjustmentSet(); a.geometry.angle = -3.25; a.geometry.rotate90 = 2; a.geometry.crop = CropRect(x: 0.1, y: 0.1, w: 0.7, h: 0.8); a.geometry.aspect = "4:5"; a.geometry.flipV = true
        let rt = try JSONDecoder().decode(AdjustmentSet.self, from: JSONEncoder().encode(a)); XCTAssertEqual(rt.geometry, a.geometry); XCTAssertEqual(rt.fingerprint, a.fingerprint)
        let old = try JSONDecoder().decode(AdjustmentSet.self, from: Data(#"{"exposure":1}"#.utf8)); XCTAssertTrue(old.geometry.isNeutral)
        var b = a; b.geometry.angle = 0; XCTAssertNotEqual(b.fingerprint, a.fingerprint)
    }

    func testPerspectiveScaleShiftAreCentreSafeInvertibleAndKeepProportions() {
        var g = Geometry(); g.keystoneV = 40; var (cx, cy) = map(g, 300, 200, 600, 400); XCTAssertEqual(cx, 300, accuracy: 1e-6); XCTAssertEqual(cy, 200, accuracy: 1e-6, "centrul rămâne fix")
        // jacobian în centru ≈ identitate (fără întindere accidentală a proporțiilor)
        let a = map(g, 301, 200, 600, 400), b = map(g, 300, 201, 600, 400); XCTAssertEqual(a.0 - 300, 1, accuracy: 0.02); XCTAssertEqual(b.1 - 200, 1, accuracy: 0.02)
        // simetrie stânga-dreapta pentru corecția verticală
        let l = map(g, 100, 100, 600, 400), r = map(g, 500, 100, 600, 400); XCTAssertEqual(l.1, r.1, accuracy: 1e-6); XCTAssertEqual(300 - l.0, r.0 - 300, accuracy: 1e-6)
        // sus și jos se comportă diferit (proiecție), nu un simplu zoom
        let top = map(g, 500, 50, 600, 400), bot = map(g, 500, 350, 600, 400); XCTAssertNotEqual(abs(top.0 - 300), abs(bot.0 - 300), accuracy: 1.0)
        g = Geometry(); g.scale = 2; (cx, cy) = map(g, 400, 200, 800, 400); XCTAssertEqual(cx, 400 + (400 - 400) / 2, accuracy: 1e-9); let m = map(g, 500, 200, 800, 400); XCTAssertEqual(m.0, 450, accuracy: 1e-9, "scară 2 ⇒ ±100 px în ieșire = ±50 px în sursă")
        g = Geometry(); g.shiftX = 0.1; let sh = map(g, 400, 200, 800, 400); XCTAssertEqual(sh.0, 400 - 80, accuracy: 1e-9)
        g = Geometry(); g.keystoneV = 35; g.keystoneH = -20; g.scale = 1.3; g.shiftY = 0.05; g.angle = 3; g.rotate90 = 1; g.flipH = true
        for (x, y) in [(120.0, 80.0), (300.0, 410.0), (50.0, 590.0)] { let o = g.sourceToOutput(x, y, srcW: 400, srcH: 600)!; let back = map(g, o.x, o.y, 400, 600); XCTAssertEqual(back.0, x, accuracy: 1e-6); XCTAssertEqual(back.1, y, accuracy: 1e-6) }
        var p = Geometry(); XCTAssertTrue(p.isPerspectiveNeutral); p.keystoneH = 1; XCTAssertFalse(p.isNeutral); XCTAssertTrue(p.fingerprint.contains(",p"))
        let rt = try? JSONDecoder().decode(Geometry.self, from: JSONEncoder().encode(g)); XCTAssertEqual(rt, g)
    }
}
