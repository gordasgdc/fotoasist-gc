import Foundation
import PhotoCore
import CoreGraphics
import CPhotoCore
import PhotoRaw

/// Corecție TEHNICĂ după un chart de culoare (ColorChecker Classic): eșantionare pe grila poziționată de utilizator (4 colțuri, perspectivă), validare a peticelor, potrivire a unei matrice 3×3 în DWG liniar scene-referred.
/// Distinctă de profilul artistic personal și de efectele creative; se aplică la intrarea lanțului (după decodare, înaintea instrumentelor liniare, a stilizării și a DRT-ului). Spec: SPEC §24.
/// Metrica de eroare: CIEDE2000 (Lab D50, 2°); reducerea pe peticele folosite la calcul NU măsoară acuratețea întregii fotografii ⇒ se raportează și eroarea leave-one-out (fiecare petic prezis fără el în potrivire).
public enum ChartModelID: String, Codable, CaseIterable, Identifiable {
    case classicAfter2014 = "after_nov2014", classicLegacy = "before_nov2014"
    public var id: String { rawValue }
    public var label: String { self == .classicAfter2014 ? L("X-Rite ColorChecker Classic (ediția după noiembrie 2014)") : L("X-Rite ColorChecker Classic - Legacy (înainte de noiembrie 2014)") }
}
public struct ChartPatch: Equatable { public let index: Int; public let name: String; public let lab: [Double]; public let dwg: [Double]; public var neutral: Bool { index >= 19 } }

public enum ChartReference {
    public struct Info { public let patches: [ChartPatch]; public let source: String; public let conditions: String; public let rights: String }
    public static func load(_ id: ChartModelID) -> Info? {
        guard let u = Bundle.main.url(forResource: "colorchecker_classic", withExtension: "json", subdirectory: "charts") ?? ModuleBundle.optional?.url(forResource: "colorchecker_classic", withExtension: "json", subdirectory: "charts") ?? ModuleBundle.optional?.url(forResource: "colorchecker_classic", withExtension: "json"),
              let d = try? Data(contentsOf: u), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let ed = (j["editions"] as? [String: Any])?[id.rawValue] as? [String: Any], let ps = ed["patches"] as? [[String: Any]] else { return nil }
        var out: [ChartPatch] = []
        for p in ps { guard let i = p["index"] as? Int, let n = p["name"] as? String, let lab = p["Lab_D50"] as? [Double] else { return nil }; var l = lab, o = [0.0, 0.0, 0.0]; pc_chart_reference_dwg(&l, &o); out.append(ChartPatch(index: i, name: n, lab: lab, dwg: o)) }
        guard out.count == 24 else { return nil }
        return Info(patches: out, source: (ed["source"] as? String) ?? "", conditions: (j["measurement_conditions"] as? String) ?? "", rights: (j["rights"] as? String) ?? "")
    }
}

// MARK: ΔE CIEDE2000
public enum DeltaE {
    public static func ciede2000(_ a: [Double], _ b: [Double]) -> Double {
        let (L1, a1, b1, L2, a2, b2) = (a[0], a[1], a[2], b[0], b[1], b[2]); let rad = Double.pi / 180
        let C1 = (a1 * a1 + b1 * b1).squareRoot(), C2 = (a2 * a2 + b2 * b2).squareRoot(), Cb = (C1 + C2) / 2
        let G = 0.5 * (1 - (pow(Cb, 7) / (pow(Cb, 7) + pow(25.0, 7))).squareRoot()); let a1p = (1 + G) * a1, a2p = (1 + G) * a2
        let C1p = (a1p * a1p + b1 * b1).squareRoot(), C2p = (a2p * a2p + b2 * b2).squareRoot()
        func hp(_ x: Double, _ y: Double) -> Double { if x == 0 && y == 0 { return 0 }; let h = atan2(y, x) / rad; return h >= 0 ? h : h + 360 }
        let h1p = hp(a1p, b1), h2p = hp(a2p, b2); let dLp = L2 - L1, dCp = C2p - C1p
        var dhp = 0.0; if C1p * C2p != 0 { dhp = h2p - h1p; if dhp > 180 { dhp -= 360 } else if dhp < -180 { dhp += 360 } }
        let dHp = 2 * (C1p * C2p).squareRoot() * sin(dhp / 2 * rad); let Lbp = (L1 + L2) / 2, Cbp = (C1p + C2p) / 2
        var hbp = h1p + h2p; if C1p * C2p == 0 { hbp = h1p + h2p } else if abs(h1p - h2p) <= 180 { hbp = (h1p + h2p) / 2 } else { hbp = (h1p + h2p + (h1p + h2p < 360 ? 360 : -360)) / 2 }
        let T = 1 - 0.17 * cos((hbp - 30) * rad) + 0.24 * cos(2 * hbp * rad) + 0.32 * cos((3 * hbp + 6) * rad) - 0.20 * cos((4 * hbp - 63) * rad)
        let dTheta = 30 * exp(-pow((hbp - 275) / 25, 2)); let Rc = 2 * (pow(Cbp, 7) / (pow(Cbp, 7) + pow(25.0, 7))).squareRoot()
        let Sl = 1 + 0.015 * pow(Lbp - 50, 2) / (20 + pow(Lbp - 50, 2)).squareRoot(), Sc = 1 + 0.045 * Cbp, Sh = 1 + 0.015 * Cbp * T, Rt = -sin(2 * dTheta * rad) * Rc
        return ((dLp / Sl) * (dLp / Sl) + (dCp / Sc) * (dCp / Sc) + (dHp / Sh) * (dHp / Sh) + Rt * (dCp / Sc) * (dHp / Sh)).squareRoot()
    }
}

// MARK: grila (geometrie)
/// Grila chartului: 4 colțuri ale CÂMPULUI DE PETICE (TL, TR, BR, BL, așa cum le vede utilizatorul în imagine) în coordonate normalizate ale SURSEI; orientarea = numărul de sferturi de tură ORARE cu care e rotit chartul în imagine + oglindire.
public struct ChartGrid: Codable, Equatable {
    public var corners: [CGPoint] = [CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.3), CGPoint(x: 0.7, y: 0.6), CGPoint(x: 0.3, y: 0.6)]
    public var rotation = 0                // 0…3 sferturi de tură orare ale chartului față de poziția „în picioare” (rândul neutru jos)
    public var mirrored = false            // oglindire a chartului (față de axa verticală proprie)
    public static let columns = 6, rows = 4
    public init() {}
    /// Pozițiile logice (col,rând) ale chartului → (u,v) în pătratul unitate al câmpului din imagine (aliniat cu cele 4 colțuri).
    func unit(logicalX lx: Double, logicalY ly: Double) -> (Double, Double) {
        var x = lx - Double(Self.columns) / 2, y = ly - Double(Self.rows) / 2; if mirrored { x = -x }
        for _ in 0..<(((rotation % 4) + 4) % 4) { let nx = -y, ny = x; x = nx; y = ny }   // rotație orară în coordonate de ecran (y în jos)
        let odd = (((rotation % 4) + 4) % 4) % 2 == 1; let W = Double(odd ? Self.rows : Self.columns), H = Double(odd ? Self.columns : Self.rows)
        return (x / W + 0.5, y / H + 0.5)
    }
    /// Omografia pătrat unitate → imagine (normalizat), din cele 4 colțuri; interpolare proiectivă (perspectivă corectă).
    func map(u: Double, v: Double) -> CGPoint {
        let p = corners; let (x0, y0, x1, y1, x2, y2, x3, y3) = (Double(p[0].x), Double(p[0].y), Double(p[1].x), Double(p[1].y), Double(p[2].x), Double(p[2].y), Double(p[3].x), Double(p[3].y))
        let sx = x0 - x1 + x2 - x3, sy = y0 - y1 + y2 - y3; var a = 0.0, b = 0.0
        if abs(sx) < 1e-12 && abs(sy) < 1e-12 { a = 0; b = 0 } else { let dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2; let det = dx1 * dy2 - dx2 * dy1
            if abs(det) < 1e-15 { a = 0; b = 0 } else { a = (sx * dy2 - dx2 * sy) / det; b = (dx1 * sy - sx * dy1) / det } }
        let h = [x1 - x0 + a * x1, x3 - x0 + b * x3, x0, y1 - y0 + a * y1, y3 - y0 + b * y3, y0, a, b, 1.0]
        let w = h[6] * u + h[7] * v + h[8]; return CGPoint(x: (h[0] * u + h[1] * v + h[2]) / w, y: (h[3] * u + h[4] * v + h[5]) / w)
    }
    /// Poziția în imagine (normalizat) a unui punct logic al chartului (coloană/rând fracționare).
    public func imagePoint(logicalX: Double, logicalY: Double) -> CGPoint { let (u, v) = unit(logicalX: logicalX, logicalY: logicalY); return map(u: u, v: v) }
    public func patchCenter(_ index: Int) -> CGPoint { let i = index - 1; return imagePoint(logicalX: Double(i % Self.columns) + 0.5, logicalY: Double(i / Self.columns) + 0.5) }
    public mutating func rotate() { rotation = (rotation + 1) % 4 }
    /// Geometrie VALIDĂ: patrulater CONVEX (colțurile TL, TR, BR, BL în aceeași orientare, fără încrucișări), cu laturi și arie nenule. O grilă nevalidă NU se eșantionează.
    public var isValid: Bool { invalidReason == nil }
    public var invalidReason: String? {
        guard corners.count == 4 else { return L("grila nu are 4 colțuri") }
        let p = corners; var sign = 0
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4]
            if hypot(Double(b.x - a.x), Double(b.y - a.y)) < 0.01 { return L("două colțuri sunt prea apropiate") }
            let cross = Double((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x))
            if abs(cross) < 1e-6 { return L("trei colțuri sunt aproape pe o dreaptă") }
            let sg = cross > 0 ? 1 : -1; if sign == 0 { sign = sg } else if sg != sign { return L("colțurile se încrucișează (patrulaterul nu e convex)") }
        }
        return nil
    }

}

// MARK: eșantionare + validare
public struct PatchSample: Equatable { public var index: Int; public var mean: [Double]; public var luma: Double; public var cv: Double; public var outsideFraction: Double; public var clippedFraction: Double; public var outlierFraction: Double; public var count: Int }
public enum PatchIssue: String, Codable, Equatable, CaseIterable { case cutOff = "tăiat / în afara cadrului", clipped = "saturat (canal tăiat)", tooDark = "prea întunecat", nonUniform = "neuniform", reflection = "reflexie / luminos față de celelalte"
    /* valorile brute sunt identificatori (Codable); textul afișat e localizat */
    public var label: String { L(rawValue) } }
public struct ChartValidation: Equatable {
    public var samples: [PatchSample]; public var issues: [Int: [PatchIssue]]; public var usable: [Int]; public var ok: Bool; public var message: String
    public var neutralLightingCV: Double
}
public enum ChartSampler {
    /// Nivelul de saturație al imaginii: dacă un platou de valori IDENTICE la maximul unui canal acoperă ≥ 0.05% din pixeli (semn de tăiere), nivelul = 99.9% din acel maxim; altfel +∞ (nicio tăiere detectată; un maxim izolat nu e tăiere).
    public static func clipLevel(_ img: FloatImage) -> Double {
        var best = Double.infinity; let n = img.width * img.height
        for k in 0..<3 { var mx: Float = -.infinity; var i = k; while i < img.rgb.count { if img.rgb[i] > mx { mx = img.rgb[i] }; i += 3 }
            var cnt = 0; i = k; while i < img.rgb.count { if img.rgb[i] >= mx { cnt += 1 }; i += 3 }; if Double(cnt) / Double(max(1, n)) >= 0.0005 { best = min(best, Double(mx) * 0.999) } }
        return best
    }
    public static let windowFraction = 0.5, gridN = 11
    static func bilinear(_ img: FloatImage, _ x: Double, _ y: Double) -> [Double]? {
        let fx = x * Double(img.width) - 0.5, fy = y * Double(img.height) - 0.5; if fx < 0 || fy < 0 || fx > Double(img.width - 1) || fy > Double(img.height - 1) { return nil }
        let x0 = Int(fx), y0 = Int(fy), x1 = min(x0 + 1, img.width - 1), y1 = min(y0 + 1, img.height - 1), ax = fx - Double(x0), ay = fy - Double(y0); var o = [0.0, 0.0, 0.0]
        for k in 0..<3 { let a = Double(img.rgb[(y0 * img.width + x0) * 3 + k]), b = Double(img.rgb[(y0 * img.width + x1) * 3 + k]), c = Double(img.rgb[(y1 * img.width + x0) * 3 + k]), d = Double(img.rgb[(y1 * img.width + x1) * 3 + k]); o[k] = (1 - ay) * ((1 - ax) * a + ax * b) + ay * ((1 - ax) * c + ax * d) }
        return o
    }
    /// Media (DWG liniar) pe fereastra centrală a fiecărui petic (11×11 puncte pe 50% din celulă), cu statistici pentru validare. `clipLevel` = nivelul de saturație al imaginii (o valoare ≥ el pe orice canal = canal tăiat).
    public static func sample(image: FloatImage, grid: ChartGrid, clipLevel: Double) -> [PatchSample] {
        var out: [PatchSample] = []
        for idx in 1...24 {
            let c = Double((idx - 1) % ChartGrid.columns) + 0.5, r = Double((idx - 1) / ChartGrid.columns) + 0.5; var vals: [[Double]] = []; var outside = 0, clipped = 0, total = 0
            for j in 0..<gridN { for i in 0..<gridN {
                let lx = c + ((Double(i) + 0.5) / Double(gridN) - 0.5) * windowFraction, ly = r + ((Double(j) + 0.5) / Double(gridN) - 0.5) * windowFraction; let p = grid.imagePoint(logicalX: lx, logicalY: ly); total += 1
                guard let v = bilinear(image, Double(p.x), Double(p.y)) else { outside += 1; continue }
                if v.contains(where: { $0 >= clipLevel }) { clipped += 1 }; vals.append(v) } }
            guard !vals.isEmpty else { out.append(PatchSample(index: idx, mean: [0, 0, 0], luma: 0, cv: 0, outsideFraction: 1, clippedFraction: 0, outlierFraction: 0, count: 0)); continue }
            var mean = [0.0, 0.0, 0.0]; for v in vals { for k in 0..<3 { mean[k] += v[k] / Double(vals.count) } }
            let ys = vals.map { 0.2627 * $0[0] + 0.678 * $0[1] + 0.0593 * $0[2] }; let ym = ys.reduce(0, +) / Double(ys.count); let sd = (ys.map { ($0 - ym) * ($0 - ym) }.reduce(0, +) / Double(ys.count)).squareRoot()
            let sorted = ys.sorted(); let med = sorted[sorted.count / 2]; let mad = sorted.map { abs($0 - med) }.sorted()[sorted.count / 2] * 1.4826
            let outl = mad > 0 ? Double(ys.filter { $0 - med > 5 * mad && $0 - med > 0.03 * max(med, 1e-6) }.count) / Double(ys.count) : 0
            out.append(PatchSample(index: idx, mean: mean, luma: ym, cv: ym > 1e-9 ? sd / ym : 0, outsideFraction: Double(outside) / Double(total), clippedFraction: Double(clipped) / Double(max(1, vals.count)), outlierFraction: outl, count: vals.count))
        }
        return out
    }
}
public enum ChartValidator {
    public struct Thresholds { public var maxOutside = 0.0, maxClipped = 0.02, minLuma = 0.004, minSNR = 3.0, maxCV = 0.08, maxOutlier = 0.03, reflectionRatio = 1.45, minUsable = 18, minNeutrals = 4, maxNeutralLightingCV = 0.15
        public init() {} }
    public static func validate(_ samples: [PatchSample], reference: [ChartPatch], thresholds t: Thresholds = Thresholds()) -> ChartValidation {
        var issues: [Int: [PatchIssue]] = [:]; func add(_ i: Int, _ k: PatchIssue) { if !(issues[i]?.contains(k) ?? false) { issues[i, default: []].append(k) } }
        let ratios: [Double] = samples.compactMap { s in s.count > 0 && s.luma > 0 ? s.luma / max(1e-9, 0.2627 * reference[s.index - 1].dwg[0] + 0.678 * reference[s.index - 1].dwg[1] + 0.0593 * reference[s.index - 1].dwg[2]) : nil }.sorted()
        let medRatio = ratios.isEmpty ? 1 : ratios[ratios.count / 2]
        for s in samples {
            if s.outsideFraction > t.maxOutside { add(s.index, .cutOff) }
            if s.count > 0 {
                if s.clippedFraction > t.maxClipped { add(s.index, .clipped) }
                if s.luma < t.minLuma || (s.cv > 0 && 1 / s.cv < t.minSNR && s.luma < 4 * t.minLuma) { add(s.index, .tooDark) }
                if s.cv > t.maxCV { add(s.index, .nonUniform) }
                let yref = 0.2627 * reference[s.index - 1].dwg[0] + 0.678 * reference[s.index - 1].dwg[1] + 0.0593 * reference[s.index - 1].dwg[2]
                if s.outlierFraction > t.maxOutlier || (yref > 0 && s.luma / yref > t.reflectionRatio * medRatio) { add(s.index, .reflection) }
            }
        }
        let usable = samples.map { $0.index }.filter { issues[$0] == nil }; let neutralsUsable = usable.filter { $0 >= 19 }
        let nr: [Double] = neutralsUsable.map { i in let s = samples[i - 1]; let yref = 0.2627 * reference[i - 1].dwg[0] + 0.678 * reference[i - 1].dwg[1] + 0.0593 * reference[i - 1].dwg[2]; return s.luma / yref }
        let nm = nr.isEmpty ? 0 : nr.reduce(0, +) / Double(nr.count); let ncv = nr.count > 1 && nm > 0 ? (nr.map { ($0 - nm) * ($0 - nm) }.reduce(0, +) / Double(nr.count)).squareRoot() / nm : 0
        var ok = true; var msg = ""
        if usable.count < t.minUsable { ok = false; msg = LF("Doar %@ din 24 de petice sunt utilizabile (minimum %@): corecția nu se calculează pentru a nu aplica ceva nesigur. Aliniază grila, evită zonele tăiate/saturate/cu reflexii sau folosește altă fotografie a chartului.", usable.count, t.minUsable) }
        else if neutralsUsable.count < t.minNeutrals { ok = false; msg = "Doar \(neutralsUsable.count) petice neutre utilizabile (minimum \(t.minNeutrals)): balansul nu poate fi estimat sigur." }
        else if ncv > t.maxNeutralLightingCV { ok = false; msg = String(format: L("Peticele neutre au luminanța neproporțională (variație %.0f%% față de referință): iluminare neuniformă sau expunere neliniară; corecția ar fi nesigură."), ncv * 100) }
        else { msg = "\(usable.count) din 24 de petice utilizabile." + (issues.isEmpty ? "" : " Excluse: " + issues.keys.sorted().map { "\($0)" }.joined(separator: ", ") + ".") }
        return ChartValidation(samples: samples, issues: issues, usable: usable, ok: ok, message: msg, neutralLightingCV: ncv)
    }
}

// MARK: potrivire
public struct ChartMetrics: Codable, Equatable { public var meanBefore: Double, maxBefore: Double, meanAfter: Double, maxAfter: Double, looMean: Double, looMax: Double, patches: Int }
/// Corecția: matrice C (3×3, rând-major) în DWG liniar. C = M·D: D = câștiguri pe canal estimate pe peticele neutre (luminanța neutrelor păstrată ⇒ expunerea NU se schimbă), M = matrice cu suma pe rând 1 (păstrează griurile neutre) potrivită pe peticele utilizabile, ponderate invers cu luminanța.
public struct ChartCorrection: Codable, Equatable, Identifiable {
    public var id = UUID().uuidString; public var model: ChartModelID; public var matrix: [Double]; public var exposureOffsetEV: Double;  /* EV de adăugat ca neutrele să atingă nivelul de referință; INFORMATIV, nu se aplică */ public var usedPatches: [Int]; public var excluded: [String]
    public var metrics: ChartMetrics; public var cameraKey: String?; public var sourcePhotoID: Int64?; public var grid: ChartGrid; public var createdAt = Date(); public var provenance: String
    public var isIdentity: Bool { matrix == [1, 0, 0, 0, 1, 0, 0, 0, 1] }
}
public enum ChartFit {
    static func luma(_ v: [Double]) -> Double { 0.2627 * v[0] + 0.678 * v[1] + 0.0593 * v[2] }
    static func solve3(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        var m = A.enumerated().map { $0.element + [b[$0.offset]] }
        for c in 0..<3 { var p = c; for r in (c + 1)..<3 where abs(m[r][c]) > abs(m[p][c]) { p = r }; if abs(m[p][c]) < 1e-14 { return nil }; m.swapAt(c, p); for r in 0..<3 where r != c { let f = m[r][c] / m[c][c]; for k in c...3 { m[r][k] -= f * m[c][k] } } }
        return (0..<3).map { m[$0][3] / m[$0][$0] }
    }
    /// Potrivește C pe peticele `use` (indici 1…24). nil dacă sistemul e degenerat.
    static func fit(samples: [PatchSample], reference: [ChartPatch], use: [Int]) -> (C: [Double], expo: Double)? {
        let neutrals = use.filter { $0 >= 19 }; guard neutrals.count >= 3 else { return nil }
        var s = [0.0, 0.0, 0.0]; for k in 0..<3 { var num = 0.0, den = 0.0; for i in neutrals { let m = samples[i - 1].mean[k], r = reference[i - 1].dwg[k]; num += r * m; den += m * m }; guard den > 0 else { return nil }; s[k] = num / den }
        let sRef = s[0] * 0.2627 + s[1] * 0.678 + s[2] * 0.0593; guard sRef > 0 else { return nil }; let d = s.map { $0 / sRef }
        // g' : scară de expunere între neutrele corectate WB și referință (nu se aplică; informativ)
        var num = 0.0, den = 0.0; for i in neutrals { let y = luma((0..<3).map { d[$0] * samples[i - 1].mean[$0] }); let r = luma(reference[i - 1].dwg); num += r * y; den += y * y }; guard den > 0, num > 0 else { return nil }; let g = num / den
        var rows = [[Double]]()
        for k in 0..<3 {
            var A = [[0.0, 0.0], [0.0, 0.0]], bb = [0.0, 0.0]
            for i in use { let m = (0..<3).map { d[$0] * samples[i - 1].mean[$0] }, t = reference[i - 1].dwg[k] / g, w = 1.0 / (0.05 + reference[i - 1].dwg.reduce(0, +) / 3 / g)
                let x1 = m[0] - m[2], x2 = m[1] - m[2], y = t - m[2]; A[0][0] += w * x1 * x1; A[0][1] += w * x1 * x2; A[1][1] += w * x2 * x2; bb[0] += w * x1 * y; bb[1] += w * x2 * y }
            A[1][0] = A[0][1]; let det = A[0][0] * A[1][1] - A[0][1] * A[1][0]; guard abs(det) > 1e-14 else { return nil }
            let a1 = (bb[0] * A[1][1] - bb[1] * A[0][1]) / det, a2 = (A[0][0] * bb[1] - A[1][0] * bb[0]) / det; rows.append([a1, a2, 1 - a1 - a2])
        }
        var C = [Double](repeating: 0, count: 9); for r in 0..<3 { for c in 0..<3 { C[r * 3 + c] = rows[r][0] * (c == 0 ? d[0] : 0) + rows[r][1] * (c == 1 ? d[1] : 0) + rows[r][2] * (c == 2 ? d[2] : 0) } }
        return (C, g)
    }
    static func apply(_ C: [Double], _ v: [Double]) -> [Double] { (0..<3).map { C[$0 * 3] * v[0] + C[$0 * 3 + 1] * v[1] + C[$0 * 3 + 2] * v[2] } }
    static func lab(_ dwg: [Double]) -> [Double] { var i = dwg, o = [0.0, 0.0, 0.0]; pc_dwg_to_lab_d50(&i, &o); return o }
    public static func correct(samples: [PatchSample], validation: ChartValidation, reference: [ChartPatch], model: ChartModelID, grid: ChartGrid, cameraKey: String?, sourcePhotoID: Int64?) -> ChartCorrection? {
        guard validation.ok, let f = fit(samples: samples, reference: reference, use: validation.usable) else { return nil }
        let use = validation.usable, scale = f.expo; func de(_ v: [Double], _ i: Int) -> Double { DeltaE.ciede2000(lab(v), reference[i - 1].lab) }
        let before = use.map { de(samples[$0 - 1].mean.map { $0 * scale }, $0) }, after = use.map { de(apply(f.C, samples[$0 - 1].mean).map { $0 * scale }, $0) }
        // leave-one-out: fiecare petic prezis dintr-o potrivire fără el
        var loo: [Double] = []; for i in use { let rest = use.filter { $0 != i }; if let g = fit(samples: samples, reference: reference, use: rest) { loo.append(de(apply(g.C, samples[i - 1].mean).map { $0 * g.expo }, i)) } }
        let m = ChartMetrics(meanBefore: before.reduce(0, +) / Double(before.count), maxBefore: before.max() ?? 0, meanAfter: after.reduce(0, +) / Double(after.count), maxAfter: after.max() ?? 0, looMean: loo.isEmpty ? 0 : loo.reduce(0, +) / Double(loo.count), looMax: loo.max() ?? 0, patches: use.count)
        let ex = validation.issues.keys.sorted().map { i in "\(i) (\(reference[i - 1].name)): " + (validation.issues[i] ?? []).map { $0.rawValue }.joined(separator: ", ") }
        return ChartCorrection(model: model, matrix: f.C, exposureOffsetEV: log2(max(1e-9, scale)), usedPatches: use, excluded: ex, metrics: m, cameraKey: cameraKey, sourcePhotoID: sourcePhotoID, grid: grid, provenance: LF("Referință NOMINALĂ (valori publicate, ediție presupusă): %@; matrice 3×3 în DWG liniar (WB pe neutre + matrice cu suma pe rând 1); metrică CIEDE2000 Lab D50 2°", model.label))
    }
}
