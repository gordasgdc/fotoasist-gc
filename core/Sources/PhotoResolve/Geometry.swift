import Foundation

/// Decupare și geometrie NEDISTRUCTIVE (salvate în reglaje, anulabile). Definiție de coordonate:
///  · sursa = fotografia orientată (LibRaw), necropată, în pixeli (x spre dreapta, y în jos);
///  · ordinea: rotire 90° (sens orar, ×k) → oglindire (H, apoi V) = cadrul orientat S′ (W′×H′) → rotire fină cu `angle` (sens orar, în jurul centrului lui S′) → decupare `crop` (fracții din S′, pe cadrul NEROTIT) → ieșire;
///  · harta ieșire→sursă (3×3, pixeli, centre de pixel) e UNICA transformare a imaginii: o singură reeșantionare bilineară pe liniarul DWG, înaintea instrumentelor de ton; măștile se evaluează în coordonatele SURSEI prin aceeași hartă (rămân pe aceeași zonă a fotografiei);
///  · fără conținut inventat: în afara sursei pixelii sunt negri și sunt raportați (`emptyFraction`); decuparea automată a marginilor e explicită.
public struct CropRect: Codable, Equatable { public var x = 0.0, y = 0.0, w = 1.0, h = 1.0; public init(x: Double = 0, y: Double = 0, w: Double = 1, h: Double = 1) { self.x = x; self.y = y; self.w = w; self.h = h } }
public struct Geometry: Codable, Equatable {
    public var rotate90 = 0                 // 0…3, sens orar
    public var flipH = false, flipV = false
    public var angle = 0.0                  // grade, sens orar (−45…45)
    public var crop = CropRect()            // fracții din cadrul orientat S′
    public var aspect = "free"              // free | original | 1:1 | 4:5 | 3:2 | 16:9 | custom (doar pentru interfață; decuparea reală e `crop`)
    public var customW = 3.0, customH = 2.0, portrait = false
    /// Perspectivă și cadrare: `keystoneV/H` −100…100 (corecție verticală/orizontală, proiecție în jurul centrului lui S′, pe valori normalizate), `scale` (1 = neschimbat; >1 mărește), `shiftX/Y` (fracții din S′). Aplicate DUPĂ rotirea fină și ÎNAINTEA decupării; fără întindere accidentală a proporțiilor (proiecția păstrează centrul și raportul pe axe).
    public var keystoneV = 0.0, keystoneH = 0.0, scale = 1.0, shiftX = 0.0, shiftY = 0.0
    public init() {}
    enum CodingKeys: String, CodingKey { case rotate90, flipH, flipV, angle, crop, aspect, customW, customH, portrait, keystoneV, keystoneH, scale, shiftX, shiftY }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        rotate90 = try c.decodeIfPresent(Int.self, forKey: .rotate90) ?? 0; flipH = try c.decodeIfPresent(Bool.self, forKey: .flipH) ?? false; flipV = try c.decodeIfPresent(Bool.self, forKey: .flipV) ?? false; angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? 0
        crop = try c.decodeIfPresent(CropRect.self, forKey: .crop) ?? CropRect(); aspect = try c.decodeIfPresent(String.self, forKey: .aspect) ?? "free"; customW = try c.decodeIfPresent(Double.self, forKey: .customW) ?? 3; customH = try c.decodeIfPresent(Double.self, forKey: .customH) ?? 2; portrait = try c.decodeIfPresent(Bool.self, forKey: .portrait) ?? false
        keystoneV = try c.decodeIfPresent(Double.self, forKey: .keystoneV) ?? 0; keystoneH = try c.decodeIfPresent(Double.self, forKey: .keystoneH) ?? 0; scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1; shiftX = try c.decodeIfPresent(Double.self, forKey: .shiftX) ?? 0; shiftY = try c.decodeIfPresent(Double.self, forKey: .shiftY) ?? 0
    }
    public var isPerspectiveNeutral: Bool { keystoneV == 0 && keystoneH == 0 && scale == 1 && shiftX == 0 && shiftY == 0 }
    public var isNeutral: Bool { rotate90 % 4 == 0 && !flipH && !flipV && angle == 0 && crop == CropRect() && isPerspectiveNeutral }
    public var fingerprint: String { isNeutral ? "" : String(format: "g:%d,%d%d,%.4f,%.5f,%.5f,%.5f,%.5f", rotate90 % 4, flipH ? 1 : 0, flipV ? 1 : 0, angle, crop.x, crop.y, crop.w, crop.h) + (isPerspectiveNeutral ? "" : String(format: ",p%.3f,%.3f,%.4f,%.4f,%.4f", keystoneV, keystoneH, scale, shiftX, shiftY)) }

    public struct Plan: Equatable { public var h: [Double]; public var outW: Int; public var outH: Int; public var orientedW: Int; public var orientedH: Int }
    private typealias M = [Double]
    private static func mul(_ a: M, _ b: M) -> M { var r = [Double](repeating: 0, count: 9); for i in 0..<3 { for j in 0..<3 { for k in 0..<3 { r[3 * i + j] += a[3 * i + k] * b[3 * k + j] } } }; return r }
    /// Planul pentru o sursă de srcW×srcH pixeli (aceeași definiție la orice rezoluție: previzualizare și export).
    public func plan(srcW: Int, srcH: Int) -> Plan {
        let k = ((rotate90 % 4) + 4) % 4; let ow = k % 2 == 0 ? srcW : srcH, oh = k % 2 == 0 ? srcH : srcW; let W = Double(ow), H = Double(oh)
        let c = CropRect(x: min(1, max(0, crop.x)), y: min(1, max(0, crop.y)), w: min(1, max(0.0005, crop.w)), h: min(1, max(0.0005, crop.h)))
        let outW = max(1, Int((c.w * W).rounded())), outH = max(1, Int((c.h * H).rounded()))
        let a1: M = [c.w * W / Double(outW), 0, c.x * W, 0, c.h * H / Double(outH), c.y * H, 0, 0, 1]                    // ieșire → S′ (pixeli)
        let th = -angle * .pi / 180, cs = cos(th), sn = sin(th), cx = W / 2, cy = H / 2
        let rot: M = [cs, -sn, cx - cs * cx + sn * cy, sn, cs, cy - sn * cx - cs * cy, 0, 0, 1]                           // R(−θ) în jurul centrului
        // perspectivă și cadrare (inversa, ieșire → S′ rotit): scară/deplasare, apoi proiecția inversă în jurul centrului (valori normalizate la W/2, H/2)
        let sc = max(0.1, scale); let unshift: M = [1 / sc, 0, cx - cx / sc - shiftX * W / sc, 0, 1 / sc, cy - cy / sc - shiftY * H / sc, 0, 0, 1]
        let kv = keystoneV * 0.006, kh = keystoneH * 0.006
        let nrm: M = [2 / W, 0, -1, 0, 2 / H, -1, 0, 0, 1], denrm: M = [W / 2, 0, W / 2, 0, H / 2, H / 2, 0, 0, 1]
        let persp: M = Geometry.mul(denrm, Geometry.mul([1, 0, 0, 0, 1, 0, -kh, -kv, 1], nrm))
        var unflip: M = [1, 0, 0, 0, 1, 0, 0, 0, 1]; if flipH { unflip = Geometry.mul([-1, 0, W, 0, 1, 0, 0, 0, 1], unflip) }; if flipV { unflip = Geometry.mul([1, 0, 0, 0, -1, H, 0, 0, 1], unflip) }
        let sW = Double(srcW), sH = Double(srcH)
        let unrot: M; switch k { case 1: unrot = [0, 1, 0, -1, 0, sH, 0, 0, 1]; case 2: unrot = [-1, 0, sW, 0, -1, sH, 0, 0, 1]; case 3: unrot = [0, -1, sW, 1, 0, 0, 0, 0, 1]; default: unrot = [1, 0, 0, 0, 1, 0, 0, 0, 1] }
        return Plan(h: Geometry.mul(unrot, Geometry.mul(unflip, Geometry.mul(rot, Geometry.mul(persp, Geometry.mul(unshift, a1))))), outW: outW, outH: outH, orientedW: ow, orientedH: oh)
    }
    /// Punct al sursei (pixeli) → punct al ieșirii (pixeli); pentru ghidaje/verificări (inversa hărții).
    public func sourceToOutput(_ sx: Double, _ sy: Double, srcW: Int, srcH: Int) -> (x: Double, y: Double)? {
        let p = plan(srcW: srcW, srcH: srcH); let h = p.h; let det = h[0] * (h[4] * h[8] - h[5] * h[7]) - h[1] * (h[3] * h[8] - h[5] * h[6]) + h[2] * (h[3] * h[7] - h[4] * h[6]); guard abs(det) > 1e-12 else { return nil }
        let inv: [Double] = [h[4] * h[8] - h[5] * h[7], h[2] * h[7] - h[1] * h[8], h[1] * h[5] - h[2] * h[4], h[5] * h[6] - h[3] * h[8], h[0] * h[8] - h[2] * h[6], h[2] * h[3] - h[0] * h[5], h[3] * h[7] - h[4] * h[6], h[1] * h[6] - h[0] * h[7], h[0] * h[4] - h[1] * h[3]].map { $0 / det }
        let w = inv[6] * sx + inv[7] * sy + inv[8]; return ((inv[0] * sx + inv[1] * sy + inv[2]) / w, (inv[3] * sx + inv[4] * sy + inv[5]) / w)
    }
    /// Fracția pixelilor ieșirii care cad în afara sursei (margini goale), evaluată pe un grilaj.
    public func emptyFraction(srcW: Int, srcH: Int) -> Double {
        let p = plan(srcW: srcW, srcH: srcH); var out = 0, n = 0; let gx = 48, gy = 48
        for iy in 0..<gy { for ix in 0..<gx { let x = (Double(ix) + 0.5) / Double(gx) * Double(p.outW), y = (Double(iy) + 0.5) / Double(gy) * Double(p.outH)
            let w = p.h[6] * x + p.h[7] * y + p.h[8], sx = (p.h[0] * x + p.h[1] * y + p.h[2]) / w, sy = (p.h[3] * x + p.h[4] * y + p.h[5]) / w; n += 1; if sx < 0 || sx > Double(srcW) || sy < 0 || sy > Double(srcH) { out += 1 } } }
        return Double(out) / Double(n)
    }
    /// Decupare automată EXPLICITĂ a marginilor goale la rotire fină: cel mai mare dreptunghi centrat, cu proporția cadrului orientat sau cu proporția cerută (pixeli a:b), complet în imaginea rotită.
    public static func autoCrop(angle: Double, orientedW W: Double, orientedH H: Double, aspect: Double? = nil) -> CropRect {
        let a = abs(angle) * .pi / 180, c = cos(a), s = sin(a); let ar = aspect ?? (W / H)
        // dreptunghi (w, h = w/ar) centrat; colțurile (±w/2, ±h/2) trebuie să respecte |x c + y s| ≤ W/2 și |−x s + y c| ≤ H/2
        let k1 = (c + s / ar) / W, k2 = (s + c / ar) / H, w = 1 / max(k1, k2) ; let hh = w / ar
        let fw = min(1, w / W), fh = min(1, hh / H); return CropRect(x: (1 - fw) / 2, y: (1 - fh) / 2, w: fw, h: fh)
    }
    /// Crop centrat cu proporția pixelilor a:b (cel mai mare care încape în S′), pentru raport fix.
    public static func centeredCrop(aspect ar: Double, orientedW W: Double, orientedH H: Double) -> CropRect {
        var w = W, h = W / ar; if h > H { h = H; w = H * ar }; return CropRect(x: (1 - w / W) / 2, y: (1 - h / H) / 2, w: w / W, h: h / H)
    }
}
