import XCTest
import CPhotoCore
@testable import PhotoResolve

/// Măști manuale precise: elipsă rotită, contur (poligon/spline), pensulă Adaugă/Șterge, adunare/scădere în aceeași mască, definiție vectorială independentă de rezoluție.
final class MaskTests: XCTestCase {
    func local(_ comps: [MaskComponent], invert: Bool = false) -> LocalCorrection { var l = LocalCorrection(); l.components = comps; l.invert = invert; l.exposure = 1; return l }
    func ell(x: Double, y: Double, rx: Double, ry: Double, rot: Double = 0, feather: Double = 0, op: MaskOp = .add) -> MaskComponent { var c = MaskComponent(kind: .ellipse); c.x1 = x; c.y1 = y; c.x2 = rx; c.y2 = ry; c.rotation = rot; c.feather = feather; c.op = op; return c }
    func poly(_ pts: [(Double, Double)], smooth: Bool = false, feather: Double = 0, op: MaskOp = .add, closed: Bool = true) -> MaskComponent { var c = MaskComponent(kind: .path); c.points = pts.map { MaskPoint(x: $0.0, y: $0.1, smooth: smooth) }; c.closed = closed; c.feather = feather; c.op = op; return c }
    func stroke(_ pts: [(Double, Double)], radius: Double, soft: Double = 0, op: MaskOp = .add) -> MaskComponent { var c = MaskComponent(kind: .brush); c.points = pts.map { MaskPoint(x: $0.0, y: $0.1) }; c.radius = radius; c.softness = soft; c.op = op; return c }
    func mask(_ l: LocalCorrection, _ w: Int = 300, _ h: Int = 200) -> [Float] { l.maskValues(width: w, height: h) }
    func at(_ m: [Float], _ w: Int, _ nx: Double, _ ny: Double, _ h: Int = 200) -> Float { m[min(h - 1, Int(ny * Double(h))) * w + min(w - 1, Int(nx * Double(w)))] }

    func testOldFormatDecodesAsBaseZoneAndKeepsFingerprintAndMaskBitExact() throws {
        let old = #"{"id":"a","name":"Elipsă 1","enabled":true,"kind":"ellipse","x1":0.4,"y1":0.5,"x2":0.2,"y2":0.3,"feather":0.35,"invert":false,"exposure":-0.5,"shadows":0,"highlights":0,"contrast":1,"temperature":0,"tint":0,"saturation":1}"#
        let l = try JSONDecoder().decode(LocalCorrection.self, from: Data(old.utf8)); XCTAssertEqual(l.components.count, 1); XCTAssertEqual(l.kind, .ellipse); XCTAssertEqual(l.x1, 0.4); XCTAssertEqual(l.rotation, 0); XCTAssertTrue(l.isSimpleMask)
        XCTAssertEqual(l.fingerprint, "1,ellipse,n,0.4000,0.5000,0.2000,0.3000,0.3500,-0.5000,0.0000,0.0000,1.0000,0.0000,0.0000,1.0000", "amprenta formatului vechi neschimbată (aprobările/cache-ul rămân valabile)")
        // simplă: masca prin calea compusă = masca prin zona simplă (bit cu bit)
        var z = pc_zone(kind: 0, x1: 0.4, y1: 0.5, x2: 0.2, y2: 0.3, feather: 0.35, invert: 0); var ref = [Float](repeating: 0, count: 300 * 200); ref.withUnsafeMutableBufferPointer { pc_mask_image(&z, $0.baseAddress, 300, 200) }
        XCTAssertEqual(mask(l), ref)
    }
    func testNewFormatKeepsOldFieldsSoOlderAppsStillOpenTheFile() throws {
        var l = LocalCorrection.make(.gradient, number: 1); l.components.append(ell(x: 0.5, y: 0.5, rx: 0.1, ry: 0.1, op: .subtract))
        let j = try JSONSerialization.jsonObject(with: JSONEncoder().encode(l)) as! [String: Any]; XCTAssertEqual(j["kind"] as? String, "gradient"); XCTAssertNotNil(j["x1"]); XCTAssertNotNil(j["components"])
        var p = LocalCorrection(); p.components = [poly([(0.2, 0.2), (0.8, 0.2), (0.5, 0.8)])]; let jp = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]; XCTAssertEqual(jp["kind"] as? String, "ellipse", "un contur apare în câmpurile vechi ca elipsă simplă, nu ca valoare necunoscută")
    }
    func testRotationIsPixelIsotropicAndMatchesSwappedAxesOnNonSquarePhoto() {
        let w = 300, h = 200                       // rx = 60 px, ry = 20 px; rotit 90° ≡ axe schimbate în PIXELI (20 px pe orizontală, 60 px pe verticală)
        let a = mask(local([ell(x: 0.5, y: 0.5, rx: 60.0 / 300, ry: 20.0 / 200, rot: 90, feather: 0.3)]), w, h)
        let b = mask(local([ell(x: 0.5, y: 0.5, rx: 20.0 / 300, ry: 60.0 / 200, rot: 0, feather: 0.3)]), w, h)
        XCTAssertEqual(zip(a, b).map { abs($0 - $1) }.max()!, 0, accuracy: 2e-5)
        let r = mask(local([ell(x: 0.5, y: 0.5, rx: 0.25, ry: 0.04, rot: 45)]), w, h); let u = mask(local([ell(x: 0.5, y: 0.5, rx: 0.25, ry: 0.04, rot: 0)]), w, h)
        let dx = 45.0 / 300, dy = 45.0 / 200   // punct pe diagonala de 45° (în pixeli: 45,45 ⇒ 63,6 px pe axa mare rotită, a = 75 px)
        XCTAssertEqual(at(r, w, 0.5 + dx, 0.5 + dy), 1); XCTAssertEqual(at(u, w, 0.5 + dx, 0.5 + dy), 0)
    }
    func testPolygonSplineAndOpenPath() {
        let sq = mask(local([poly([(0.3, 0.3), (0.7, 0.3), (0.7, 0.7), (0.3, 0.7)])])); XCTAssertEqual(at(sq, 300, 0.5, 0.5), 1); XCTAssertEqual(at(sq, 300, 0.1, 0.1), 0); XCTAssertEqual(at(sq, 300, 0.5, 0.9), 0)
        var circle: [(Double, Double)] = []; for k in 0..<8 { let t: Double = Double(k) * Double.pi / 4; let px: Double = 0.5 + 0.2 * cos(t); let py: Double = 0.5 + 0.3 * sin(t); circle.append((px, py)) }
        let sp = mask(local([poly(circle, smooth: true)])); let pl = mask(local([poly(circle, smooth: false)]))
        let area = { (m: [Float]) in Double(m.reduce(0, +)) / Double(m.count) }; let ideal = Double.pi * 0.2 * 0.3
        XCTAssertEqual(area(sp), ideal, accuracy: ideal * 0.03, "puncte netede ⇒ curbă apropiată de elipsa ideală"); XCTAssertLessThan(area(pl), area(sp), "poligonul (colțuri) înscris e mai mic decât spline-ul")
        XCTAssertEqual(mask(local([poly([(0.3, 0.3), (0.7, 0.3), (0.7, 0.7), (0.3, 0.7)], closed: false)])).max()!, 0, "contur deschis: fără efect încă")
        XCTAssertEqual(mask(local([poly([(0.3, 0.3), (0.7, 0.3)])])).max()!, 0, "mai puțin de 3 puncte: fără efect")
        let feathered = mask(local([poly([(0.3, 0.3), (0.7, 0.3), (0.7, 0.7), (0.3, 0.7)], feather: 0.5)])); XCTAssertEqual(at(feathered, 300, 0.5, 0.5), 1, accuracy: 1e-6)
        let edge = at(feathered, 300, 0.7, 0.5); XCTAssertEqual(edge, 0.5, accuracy: 0.12, "pe margine ≈ 0,5 (estompare simetrică)"); XCTAssertGreaterThan(at(feathered, 300, 0.69, 0.5), at(feathered, 300, 0.72, 0.5))
    }
    func testAddAndSubtractInOneMaskAndOrderMatters() {
        let sky = poly([(0, 0), (1, 0), (1, 0.6), (0, 0.6)]); let person = ell(x: 0.5, y: 0.45, rx: 0.12, ry: 0.2, op: .subtract)
        let m = mask(local([sky, person])); XCTAssertEqual(at(m, 300, 0.5, 0.45), 0, "persoana exclusă din cer"); XCTAssertEqual(at(m, 300, 0.1, 0.2), 1); XCTAssertEqual(at(m, 300, 0.5, 0.9), 0)
        let rev = mask(local([person, sky])); XCTAssertEqual(at(rev, 300, 0.5, 0.45), 1, "ordinea contează: scăderea înainte de adăugare nu exclude nimic")
        let inv = mask(local([sky, person], invert: true)); XCTAssertEqual(at(inv, 300, 0.5, 0.45), 1); XCTAssertEqual(at(inv, 300, 0.1, 0.2), 0, "inversarea se aplică întregii măști compuse")
    }
    func testBrushAddEraseSizeAndSoftEdge() {
        let line = [(0.2, 0.5), (0.8, 0.5)]; let add = mask(local([stroke(line, radius: 0.05)]))      // rază = 0,05·200 = 10 px
        XCTAssertEqual(at(add, 300, 0.5, 0.5), 1); XCTAssertEqual(at(add, 300, 0.5, 0.5 + 8.0 / 200), 1); XCTAssertEqual(at(add, 300, 0.5, 0.5 + 14.0 / 200), 0); XCTAssertEqual(at(add, 300, 0.1, 0.5), 0)
        let soft = mask(local([stroke(line, radius: 0.05, soft: 1)])); XCTAssertGreaterThan(at(soft, 300, 0.5, 0.5 + 5.0 / 200), 0.4); XCTAssertLessThan(at(soft, 300, 0.5, 0.5 + 5.0 / 200), 0.99); XCTAssertEqual(at(soft, 300, 0.5, 0.5), 1, accuracy: 0.02)
        let big = mask(local([stroke(line, radius: 0.12)])); XCTAssertGreaterThan(big.reduce(0, +), add.reduce(0, +) * 2, "pensulă mai mare ⇒ zonă mai mare")
        let erased = mask(local([ell(x: 0.5, y: 0.5, rx: 0.3, ry: 0.3), stroke([(0.5, 0.3), (0.5, 0.7)], radius: 0.06, op: .subtract)])); XCTAssertEqual(at(erased, 300, 0.5, 0.5), 0, "Șterge scoate din zonă"); XCTAssertEqual(at(erased, 300, 0.3, 0.5), 1)
        XCTAssertEqual(mask(local([stroke([(0.5, 0.5)], radius: 0.1)])).max()!, 1, "un singur punct = disc")
    }
    func testMasksAreResolutionIndependentAcrossAspectsAndFeathers() {
        let comps: [[MaskComponent]] = [[ell(x: 0.45, y: 0.55, rx: 0.3, ry: 0.1, rot: 33, feather: 0.4)], [poly([(0.2, 0.2), (0.8, 0.25), (0.7, 0.8), (0.3, 0.7)], smooth: true, feather: 0.3)], [stroke([(0.2, 0.3), (0.6, 0.6), (0.85, 0.4)], radius: 0.06, soft: 0.6)]]
        for (w, h) in [(160, 120), (120, 160), (200, 200)] { for c in comps {
            let small = mask(local(c), w, h), big = mask(local(c), w * 4, h * 4); var worst: Float = 0
            for y in 0..<h { for x in 0..<w { var s: Float = 0; for yy in 0..<4 { for xx in 0..<4 { s += big[(y * 4 + yy) * (w * 4) + x * 4 + xx] } }; worst = max(worst, abs(small[y * w + x] - s / 16)) } }
            XCTAssertLessThan(worst, 0.12, "aceeași definiție la 4× rezoluție (\(w)×\(h)): marja = cuantizarea marginii pe pixelul mic")
        } }
    }
    func testProcessingUsesTheSameMaskAtAnyResolution() {
        var l = local([poly([(0.25, 0.25), (0.75, 0.3), (0.7, 0.8), (0.3, 0.75)], smooth: true, feather: 0.3), ell(x: 0.5, y: 0.5, rx: 0.1, ry: 0.15, rot: 20, op: .subtract)]); l.exposure = -1
        func render(_ w: Int, _ h: Int) -> [Float] {
            var g = pc_params(); pc_default_params(&g); g.drt = 0; g.inputIsLinear = 0; var img = [Float](repeating: 0, count: w * h * 3); for i in 0..<(w * h) { img[3 * i] = 0.5; img[3 * i + 1] = 0.5; img[3 * i + 2] = 0.5 }
            let cm = LocalCorrection.coreMasks([l]); var out = [Float](repeating: 0, count: img.count); XCTAssertEqual(img.withUnsafeBufferPointer { i in out.withUnsafeMutableBufferPointer { o in runCoreMasks(&g, cm, input: i.baseAddress!, output: o.baseAddress!, width: w, height: h) } }, 0); return out
        }
        let a = render(120, 90), b = render(480, 360); var worst: Float = 0
        for y in 0..<90 { for x in 0..<120 { var s: Float = 0; for yy in 0..<4 { for xx in 0..<4 { s += b[((y * 4 + yy) * 480 + x * 4 + xx) * 3] } }; worst = max(worst, abs(a[(y * 120 + x) * 3] - s / 16)) } }
        XCTAssertLessThan(worst, 0.05, "previzualizare vs export: același rezultat (în marja marginii)"); XCTAssertNotEqual(a.min(), a.max(), "corecția chiar modifică imaginea în mască")
    }
    func testComponentsPersistThroughAdjustmentSetJSON() throws {
        var a = AdjustmentSet(); var l = LocalCorrection.make(.path, number: 1); l.components[0].points = [MaskPoint(x: 0.2, y: 0.2, smooth: true), MaskPoint(x: 0.8, y: 0.2), MaskPoint(x: 0.5, y: 0.9, smooth: true)]; l.components[0].closed = true
        l.components.append(stroke([(0.5, 0.5), (0.55, 0.52)], radius: 0.04, soft: 0.7, op: .subtract)); l.components.append(ell(x: 0.3, y: 0.3, rx: 0.1, ry: 0.05, rot: 40, feather: 0.2)); l.exposure = 0.7; l.invert = true; a.locals = [l]
        let rt = try JSONDecoder().decode(AdjustmentSet.self, from: JSONEncoder().encode(a)); XCTAssertEqual(rt, a); XCTAssertEqual(rt.fingerprint, a.fingerprint); XCTAssertEqual(rt.locals[0].components.count, 3); XCTAssertEqual(rt.locals[0].components[0].points[0].smooth, true)
        var b = a; b.locals[0].components[1].radius = 0.05; XCTAssertNotEqual(b.fingerprint, a.fingerprint, "orice componentă a măștii schimbă amprenta (cache/aprobări)")
        var c = a; c.locals[0].components[2].rotation = 41; XCTAssertNotEqual(c.fingerprint, a.fingerprint)
    }
    func testBuildingTheMaskIsSeparateFromAdjustmentsAndResetKeepsIt() {
        var l = local([ell(x: 0.5, y: 0.5, rx: 0.2, ry: 0.1, rot: 25), stroke([(0.5, 0.5)], radius: 0.05, op: .subtract)]); let before = l.components; l.resetAdjustments(); XCTAssertEqual(l.components, before); XCTAssertTrue(l.adjustmentIsNeutral)
    }
}
