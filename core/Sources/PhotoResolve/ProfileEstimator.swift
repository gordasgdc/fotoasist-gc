import Foundation
import ImageIO
import CoreGraphics
import CPhotoCore
import PhotoCore
import PhotoRaw

/// Estimatorul profilului personal (SET INIȚIAL de 7 parametri globali; metoda autorizată: local, determinist, fără ML — docs/PROFILE_FROM_EXAMPLES.md).
/// Potrivește randarea nucleului propriu pe RAW cu finalul aprobat al aceleiași fotografii (căutare numerică Nelder–Mead pe imagini reduse, metrică robustă ΔE76 tăiată 10%).
/// NU deduce: corecții locale, măști, efecte, module în afara setului inițial, geometrie. Dacă potrivirea e slabă, se raportează (reziduu mare ⇒ pereche NEreprezentabilă prin cei 7 parametri), nu se ascunde.
public enum ProfileEstimator {
    public static let version = 1
    /// Setul INIȚIAL (ordinea e contractul): exposureOffset (față de estimarea automată; ADAPTIV), apoi parametrii creativi stabili.
    public static let parameterNames = ["exposureOffset", "contrast", "saturation", "shadows", "highlights", "temperature", "tint"]
    static let lo: [Double] = [-3, 0.6, 0.3, -1.5, -1.5, -80, -0.03], hi: [Double] = [3, 1.8, 1.8, 1.5, 1.5, 80, 0.03], neutral: [Double] = [0, 1, 1, 0, 0, 0, 0]
    public enum EstimatorError: Error, CustomStringConvertible { case geometryMismatch(String), unreadableFinal(String), drtUnavailable
        public var description: String { switch self { case .geometryMismatch(let m): return LF("Geometrie diferită între RAW și final: %@. Perechea nu se folosește.", m); case .unreadableFinal(let p): return "Finalul nu poate fi citit: \(p)"; case .drtUnavailable: return L("Datele GDC DRT nu sunt disponibile; estimarea cere randarea reală a produsului.") } } }

    public struct PairFit: Codable, Equatable { public var pairID: String; public var values: [Double]; public var residual: Double; public var baseline: Double; public var atBounds: [String]; public var evaluations: Int; public var width: Int; public var height: Int; public var drtNatural: Bool
        public var improvement: Double { baseline - residual } }

    /// Imagine redusă (liniar DWG) și finalul (sRGB 0…1) la aceeași dimensiune.
    public struct Prepared { public var w: Int, h: Int, linear: [Float], finalRGB: [Float]; public var estimate: Double }

    // MARK: pregătire
    public static func downscale(_ a: [Float], _ w: Int, _ h: Int, to maxSide: Int) -> ([Float], Int, Int) {
        let s = max(1, Int((Double(max(w, h)) / Double(maxSide)).rounded(.up))); let nw = max(1, w / s), nh = max(1, h / s); var o = [Float](repeating: 0, count: nw * nh * 3)
        for y in 0..<nh { for x in 0..<nw { var acc = [Double](repeating: 0, count: 3); var n = 0.0
            for yy in (y * s)..<min(h, (y + 1) * s) { for xx in (x * s)..<min(w, (x + 1) * s) { for k in 0..<3 { acc[k] += Double(a[(yy * w + xx) * 3 + k]) }; n += 1 } }
            for k in 0..<3 { o[(y * nw + x) * 3 + k] = Float(acc[k] / max(n, 1)) } } }
        return (o, nw, nh)
    }
    public static func readFinal(_ path: String) throws -> (rgb: [Float], w: Int, h: Int) {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw EstimatorError.unreadableFinal(path) }
        let w = cg.width, h = cg.height; var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok = px.withUnsafeMutableBytes { b -> Bool in guard let ctx = CGContext(data: b.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }; ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h)); return true }
        guard ok else { throw EstimatorError.unreadableFinal(path) }
        var rgb = [Float](repeating: 0, count: w * h * 3); for i in 0..<(w * h) { for k in 0..<3 { rgb[i * 3 + k] = Float(px[i * 4 + k]) / 255 } }; return (rgb, w, h)
    }
    /// Verifică alinierea geometrică (raport de aspect) și întoarce imaginile reduse la aceeași dimensiune. Decupările nu se deduc: o pereche cu alt cadru e respinsă.
    public static func prepare(raw: FloatImage, final f: (rgb: [Float], w: Int, h: Int), estimate: Double, maxSide: Int = 160) throws -> Prepared {
        let ra = Double(raw.width) / Double(raw.height), fa = Double(f.w) / Double(f.h)
        guard abs(ra - fa) / ra < 0.01 else { throw EstimatorError.geometryMismatch(String(format: "raport %.4f vs %.4f", ra, fa)) }
        let (lr, w, h) = downscale(raw.rgb, raw.width, raw.height, to: maxSide)
        // finalul reeșantionat pe aceeași grilă (medie pe celule, proporțional)
        var fr = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h { let y0 = y * f.h / h, y1 = max(y0 + 1, (y + 1) * f.h / h); for x in 0..<w { let x0 = x * f.w / w, x1 = max(x0 + 1, (x + 1) * f.w / w); var acc = [Double](repeating: 0, count: 3); var n = 0.0
            for yy in y0..<min(y1, f.h) { for xx in x0..<min(x1, f.w) { for k in 0..<3 { acc[k] += Double(f.rgb[(yy * f.w + xx) * 3 + k]) }; n += 1 } }; for k in 0..<3 { fr[(y * w + x) * 3 + k] = Float(acc[k] / max(n, 1)) } } }
        return Prepared(w: w, h: h, linear: lr, finalRGB: fr, estimate: estimate)
    }

    // MARK: randare + metrică
    static func params(_ v: [Double], estimate: Double, drtNatural: Bool) -> pc_params {
        var p = pc_params(); pc_default_params(&p); p.exposure = estimate + v[0]; p.contrast = v[1]; p.saturation = v[2]; p.shadows = v[3]; p.highlights = v[4]; p.temperature = v[5]; p.tint = v[6]
        p.family = 0; p.inputIsLinear = 2; if drtNatural && Edition.full { p.drt = 2; p.drtProfile = 0; p.drtOutput = 2 } else { p.drt = 1 }; return p
    }
    static func lab(_ r: Float, _ g: Float, _ b: Float) -> (Double, Double, Double) {
        func lin(_ c: Float) -> Double { let v = Double(c); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let R = lin(r), G = lin(g), B = lin(b); let X = 0.4124564 * R + 0.3575761 * G + 0.1804375 * B, Y = 0.2126729 * R + 0.7151522 * G + 0.0721750 * B, Z = 0.0193339 * R + 0.1191920 * G + 0.9503041 * B
        func f(_ t: Double) -> Double { t > 216.0 / 24389.0 ? cbrt(t) : (24389.0 / 27.0 * t + 16) / 116 }
        let fx = f(X / 0.95047), fy = f(Y), fz = f(Z / 1.08883); return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
    static func render(_ pr: Prepared, _ v: [Double], drtNatural: Bool) -> [Float]? {
        var p = params(v, estimate: pr.estimate, drtNatural: drtNatural); var out = [Float](repeating: 0, count: pr.linear.count)
        let rc = pr.linear.withUnsafeBufferPointer { i in out.withUnsafeMutableBufferPointer { o in pc_process_image(&p, i.baseAddress, o.baseAddress, Int32(pr.w), Int32(pr.h), 1) } }
        return rc == 0 ? out : nil
    }
    /// ΔE76 tăiată (media celor mai bune 90% dintre pixeli): robustă la zone pe care parametrii globali nu le pot reproduce (ex. retușuri locale).
    public static func loss(_ pr: Prepared, _ v: [Double], drtNatural: Bool) -> Double {
        guard let out = render(pr, v, drtNatural: drtNatural) else { return 1e9 }
        var d = [Double](); d.reserveCapacity(pr.w * pr.h)
        for i in 0..<(pr.w * pr.h) { let a = lab(out[i * 3], out[i * 3 + 1], out[i * 3 + 2]), b = lab(pr.finalRGB[i * 3], pr.finalRGB[i * 3 + 1], pr.finalRGB[i * 3 + 2]); d.append(((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()) }
        d.sort(); let keep = max(1, Int(Double(d.count) * 0.9)); return d.prefix(keep).reduce(0, +) / Double(keep)
    }

    // MARK: Nelder–Mead pe parametri normalizați [0,1]
    static func denorm(_ x: [Double]) -> [Double] { (0..<x.count).map { lo[$0] + min(1, max(0, x[$0])) * (hi[$0] - lo[$0]) } }
    static func norm(_ v: [Double]) -> [Double] { (0..<v.count).map { (v[$0] - lo[$0]) / (hi[$0] - lo[$0]) } }
    public static func fit(pairID: String, prepared pr: Prepared, drtNatural: Bool, maxEvaluations: Int = 700) -> PairFit {
        let n = parameterNames.count; var evals = 0
        func f(_ x: [Double]) -> Double { evals += 1; return loss(pr, denorm(x), drtNatural: drtNatural) }
        let baseline = loss(pr, neutral, drtNatural: drtNatural)
        var best: ([Double], Double) = (norm(neutral), baseline)
        for restart in 0..<2 {
            var simplex: [[Double]] = [best.0]; for i in 0..<n { var x = best.0; x[i] = min(1, max(0, x[i] + (restart == 0 ? 0.12 : 0.06) * (i % 2 == 0 ? 1 : -1))); simplex.append(x) }
            var fv = simplex.map { f($0) }
            while evals < maxEvaluations * (restart + 1) / 2 {
                let idx = (0..<(n + 1)).sorted { fv[$0] < fv[$1] }; simplex = idx.map { simplex[$0] }; fv = idx.map { fv[$0] }
                if fv[n] - fv[0] < 1e-5 { break }
                var c = [Double](repeating: 0, count: n); for i in 0..<n { for k in 0..<n { c[k] += simplex[i][k] / Double(n) } }
                func pt(_ t: Double) -> [Double] { (0..<n).map { min(1, max(0, c[$0] + t * (simplex[n][$0] - c[$0]))) } }
                let xr = pt(-1), fr = f(xr)
                if fr < fv[0] { let xe = pt(-2), fe = f(xe); if fe < fr { simplex[n] = xe; fv[n] = fe } else { simplex[n] = xr; fv[n] = fr } }
                else if fr < fv[n - 1] { simplex[n] = xr; fv[n] = fr }
                else { let xc = pt(fr < fv[n] ? -0.5 : 0.5), fc = f(xc)
                    if fc < min(fr, fv[n]) { simplex[n] = xc; fv[n] = fc } else { for i in 1...n { for k in 0..<n { simplex[i][k] = simplex[0][k] + 0.5 * (simplex[i][k] - simplex[0][k]) }; fv[i] = f(simplex[i]) } } }
            }
            let bi = fv.indices.min { fv[$0] < fv[$1] }!; if fv[bi] < best.1 { best = (simplex[bi], fv[bi]) }
        }
        let v = denorm(best.0); var atB: [String] = []; for i in 0..<n { if best.0[i] < 0.01 || best.0[i] > 0.99 { atB.append(parameterNames[i]) } }
        return PairFit(pairID: pairID, values: v, residual: best.1, baseline: baseline, atBounds: atB, evaluations: evals, width: pr.w, height: pr.h, drtNatural: drtNatural)
    }

    // MARK: agregare + evaluare
    /// Mediană + dispersie (MAD scalat) pe perechile de AJUSTARE; exposureOffset = ADAPTIV (față de estimare), restul = CREATIV stabil. Pereche cu reziduu ≥ baseline (nu s-a îmbunătățit) sau cu parametri la limită NU intră.
    public static func aggregate(_ fits: [PairFit], technicalPolicy: String) -> (parameters: ProfileParameters, used: [String], excluded: [(String, String)]) {
        var used: [PairFit] = [], excluded: [(String, String)] = []
        for f in fits { if f.improvement <= 0 { excluded.append((f.pairID, L("potrivirea nu îmbunătățește față de neutru"))) } else if f.atBounds.count > 2 { excluded.append((f.pairID, LF("parametri la limită: %@", f.atBounds.joined(separator: ", ")))) } else { used.append(f) } }
        func est(_ i: Int) -> ParameterEstimate? { let xs = used.map { $0.values[i] }.sorted(); guard !xs.isEmpty else { return nil }; let m = median(xs); let mad = median(xs.map { abs($0 - m) }.sorted()) * 1.4826; return ParameterEstimate(median: m, spread: mad, count: xs.count) }
        var P = ProfileParameters(technicalPolicy: technicalPolicy)
        if let e = est(0) { P.adaptive["exposureOffset"] = e }
        for (i, n) in parameterNames.enumerated() where i > 0 { if let e = est(i) { P.creative[n] = e } }
        return (P, used.map { $0.pairID }, excluded)
    }
    static func median(_ s: [Double]) -> Double { s.isEmpty ? 0 : (s.count % 2 == 1 ? s[s.count / 2] : 0.5 * (s[s.count / 2 - 1] + s[s.count / 2])) }
    public struct Evaluation: Equatable { public var heldOut: Int; public var meanBaselineDE: Double; public var meanProfileDE: Double; public var improvedCount: Int; public var consistent: Bool
        public var summary: String { String(format: L("%d perechi reținute: ΔE medie %.2f cu profil vs %.2f fără (%d din %d îmbunătățite)%@"), heldOut, meanProfileDE, meanBaselineDE, improvedCount, heldOut, consistent ? "" : " — profil NECONSISTENT (dispersie mare)") } }
    /// Evaluarea pe perechi REȚINUTE (nefolosite la ajustare): aplică mediana profilului și compară cu neutrul.
    public static func evaluate(_ profile: ProfileParameters, held: [Prepared], drtNatural: Bool) -> Evaluation {
        var v = neutral; v[0] = profile.adaptive["exposureOffset"]?.median ?? 0; for (i, n) in parameterNames.enumerated() where i > 0 { v[i] = profile.creative[n]?.median ?? neutral[i] }
        var b = 0.0, p = 0.0, imp = 0; for h in held { let bl = loss(h, neutral, drtNatural: drtNatural), pl = loss(h, v, drtNatural: drtNatural); b += bl; p += pl; if pl < bl { imp += 1 } }
        let n = Double(max(held.count, 1)); let spreadHigh = profile.creative.values.contains { $0.spread > 0.35 * max(abs($0.median), 0.5) + 0.2 }
        return Evaluation(heldOut: held.count, meanBaselineDE: b / n, meanProfileDE: p / n, improvedCount: imp, consistent: !spreadHigh && imp * 2 >= held.count)
    }
    /// Reglajele fotografiei curente din profil: DOAR cei 7 parametri; orice alt modul rămâne neutru (modulele noi nu schimbă tăcut profilurile existente). `estimate` = estimarea automată a fotografiei.
    public static func adjustments(from profile: PersonalProfile, estimate: Double?, family: WorkingFamily = .dwg) -> AdjustmentSet {
        var a = AdjustmentSet.neutral(family); let P = profile.parameters
        a.exposureAuto = true; a.autoOffset = P.adaptive["exposureOffset"]?.median ?? 0
        a.contrast = P.creative["contrast"]?.median ?? 1; a.saturation = P.creative["saturation"]?.median ?? 1; a.shadows = P.creative["shadows"]?.median ?? 0; a.highlights = P.creative["highlights"]?.median ?? 0
        a.temperature = P.creative["temperature"]?.median ?? 0; a.tint = P.creative["tint"]?.median ?? 0; a.engineRevision = AdjustmentSet.currentEngineRevision; return a
    }
    /// Identitatea motorului + estimatorului + setului de parametri: stocată în profil; o schimbare ⇒ re-evaluare, nu modificare tăcută.
    public static var engineIdentity: String { "\(String(cString: pc_version()))|rev\(AdjustmentSet.currentEngineRevision)|est\(version)|set:\(parameterNames.joined(separator: ","))" }
}
