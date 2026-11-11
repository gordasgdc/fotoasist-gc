import Foundation
import CPhotoCore
import PhotoCore
import PhotoRaw

/// Instrumente de ANALIZĂ vizuală (nu efecte): se afișează în loc de fotografie, doar în aplicație, NICIODATĂ în export. Fiecare declară pe ce măsoară:
///  · culoare falsă  → SCENE-LINIAR, înainte de GDC DRT (după toate reglajele, inclusiv corecțiile locale): luminanța în stopuri față de gri 18%;
///  · tăieri, saturație, ton piele, histogramă → IMAGINEA FINALĂ (sRGB după GDC DRT), exact ce se exportă.
/// Calculele rulează pe o previzualizare redusă (≤ ~1400 px latura mare); procentele sunt estimări statistice ale cadrului, nu numărători pe pixelii exportului.
public enum AnalysisMode: String, CaseIterable, Codable {
    case off, falseColour, clipping, saturation, saturationHSV, chromaRel, skin, nrDifference
    public var label: String { switch self { case .nrDifference: return L("Diferență NR"); case .off: return L("Oprit"); case .falseColour: return L("Culoare falsă"); case .clipping: return L("Tăieri"); case .saturation: return L("Croma Oklab (absolută)"); case .saturationHSV: return L("Saturație HSV"); case .chromaRel: return L("Croma relativă (C/L)"); case .skin: return L("Ton piele") } }
    /// Domeniul în care se măsoară (afișat în interfață lângă fiecare instrument).
    public var domain: String {
        switch self {
        case .off: return ""
        case .nrDifference: return L("Imaginea finală (sRGB după GDC DRT), aceleași reglaje de două ori: singura diferență e reducerea de zgomot (pornită − oprită), pe canal, centrată pe gri 50%.")
        case .falseColour: return L("Scene-liniar, înainte de GDC DRT (după toate reglajele, cu corecțiile locale): stopuri față de gri 18%.")
        case .clipping: return L("Imaginea finală (sRGB după GDC DRT), exact ce se exportă: canal ≥ 254/255 sau toate canalele ≤ 2/255.")
        case .saturation: return L("Imaginea finală (sRGB după GDC DRT): croma Oklab ABSOLUTĂ C = √(a²+b²) a pixelului exportat (scală 0…≈0,4).")
        case .saturationHSV: return L("Imaginea finală (sRGB după GDC DRT, valori codate): saturație HSV S = (max−min)/max a pixelului exportat (scală 0…1).")
        case .chromaRel: return L("Imaginea finală (sRGB după GDC DRT): croma relativă la luminozitate, ρ = C/L în Oklab (scală 0…≈0,6); pixelurile aproape negre (L < 0,05) sunt excluse.")
        case .skin: return L("Imaginea finală (sRGB după GDC DRT): selecție după CULOARE (YCbCr), nu detecție de piele.")
        }
    }
    public var explanation: String {
        switch self {
        case .off: return ""
        case .nrDifference: return L("Gri uniform = reducerea de zgomot nu a schimbat nimic. Mai deschis/mai închis = cât a modificat NR pixelul, cu amplificare explicită. Diferența conține zgomot ȘI textură fină eliminată; nu le separă și nu e o măsură a zgomotului.")
        case .falseColour: return L("Fiecare culoare = o plajă de luminanță în stopuri față de gri 18%. Praguri orientative pentru judecarea expunerii; nu arată tăierea finală (vezi «Tăieri»).")
        case .clipping: return L("Roșu = lumini tăiate (un canal la capăt). Albastru = umbre la zero. Restul = imaginea redusă în luminozitate, pentru context.")
        case .saturation: return L("Cât de colorat e pixelul în valoare absolută: zonele întunecate au croma mică chiar dacă sunt «saturate» ca raport. Gri/albastru = puțină culoare, galben/roșu = foarte colorat. Nu schimbă imaginea.")
        case .saturationHSV: return L("Cât de departe e pixelul de gri ca raport între canale (modelul HSV, ca slider-ul «Saturație HSV»): o culoare întunecată poate avea S mare. Nu ține cont de luminanță.")
        case .chromaRel: return L("Culoare raportată la luminozitate (C/L): arată «cât de saturat pare» pixelul independent de cât de luminos e; zonele întunecate colorate ies mai vizibile decât în croma absolută.")
        case .skin: return L("Evidențiază pixelii cu culoare apropiată de tonurile de piele (interval YCbCr publicat). NU e o mască manuală, NU e analiză de conținut și nu folosește ML: poate prinde lemn, nisip sau cărămidă și poate rata piele în culori extreme.")
        }
    }
}

public struct AnalysisLegendItem: Equatable { public var r: UInt8, g: UInt8, b: UInt8; public var text: String; public var fraction: Double }
public struct AnalysisHistogram: Equatable { public var bins: Int; public var r: [Float], g: [Float], b: [Float], luma: [Float] }
public struct AnalysisResult {
    public var mode: AnalysisMode; public var width: Int, height: Int
    /// RGB 8 biți intercalat (imaginea de analiză; NU e fotografia).
    public var rgb8: [UInt8]; public var legend: [AnalysisLegendItem]; public var notes: [String]; public var histogram: AnalysisHistogram
    public var domain: String; public var sampled: String
    /// Vectorscop (RGBA 8 biți, `PhotoAnalysis.vectorscopeSize` px pătrați); gol dacă nu a fost cerut.
    public var vectorscope: [UInt8] = []
    /// RGB Parade (imaginea finală); gol dacă nu a fost cerută.
    public var parade: PhotoAnalysis.ParadeDensity? = nil
    /// Doar pentru `.nrDifference`: amplificarea folosită și statistica diferenței.
    public var nrGain: Float = 0; public var nrStats: PhotoAnalysis.NRDifferenceStats? = nil
}

public enum PhotoAnalysis {
    public static let vectorscopeSize = 256
    /// Cb/Cr Rec.709 ale unui sRGB codat (0…1): Y = 0,2126R + 0,7152G + 0,0722B; Cb = (B−Y)/1,8556; Cr = (R−Y)/1,5748 (intervale −0,5…0,5).
    public static func cbcr(_ r: Float, _ g: Float, _ b: Float) -> (cb: Float, cr: Float) { let y = 0.2126 * r + 0.7152 * g + 0.0722 * b; return ((b - y) / 1.8556, (r - y) / 1.5748) }
    // MARK: vectorscop — MATEMATICĂ separată de DESEN
    /// Densitatea pixelilor în planul Cb/Cr Rec.709 al imaginii FINALE (sRGB după GDC DRT, valori codate — exact ce se exportă). Planul acoperă Cb, Cr ∈ [−0,5; 0,5] pe `size`×`size` celule; Cr în sus (rândul 0 = Cr +0,5).
    /// Fără desen: doar numărătoare. Aceeași imagine de analiză ca histograma (rezultatul `preview` al aceleiași fotografii/reglaje).
    public struct VectorscopeDensity: Equatable { public var size: Int; public var counts: [Float]; public var total: Int; public var peak: Float }
    public static func vectorscopeDensity(finalRGB rgb: [Float], size n: Int = vectorscopeSize) -> VectorscopeDensity {
        var dens = [Float](repeating: 0, count: n * n); var total = 0
        for i in stride(from: 0, to: rgb.count - 2, by: 3) {
            let r = rgb[i], g = rgb[i + 1], b = rgb[i + 2]; guard r.isFinite, g.isFinite, b.isFinite else { continue }
            let (cb, cr) = cbcr(min(1, max(0, r)), min(1, max(0, g)), min(1, max(0, b)))
            let (x, y) = vectorscopeCell(cb: cb, cr: cr, size: n); if x >= 0, x < n, y >= 0, y < n { dens[y * n + x] += 1; total += 1 } }
        return VectorscopeDensity(size: n, counts: dens, total: total, peak: dens.max() ?? 0)
    }
    /// Celula (coloană, rând) a unei perechi Cb/Cr; originea (0,0) cade pe celula centrală.
    public static func vectorscopeCell(cb: Float, cr: Float, size n: Int) -> (x: Int, y: Int) { (Int((0.5 + cb) * Float(n)), Int((0.5 - cr) * Float(n))) }
    /// Poziția normalizată (0…1, Cr în sus ⇒ y în jos) a unei culori în planul vectorscopului — folosită de desen pentru ținte, la aceeași scară ca densitatea.
    public static func vectorscopePosition(r: Float, g: Float, b: Float) -> (x: Float, y: Float) { let (cb, cr) = cbcr(r, g, b); return (0.5 + cb, 0.5 - cr) }
    /// Ținte cromatice: bare de culoare 75% (R, Yl, G, Cy, B, Mg), aceleași valori codate pentru orice imagine; poziția lor se calculează cu aceeași funcție ca densitatea.
    public static let vectorscopeTargets: [(name: String, r: Float, g: Float, b: Float)] = [("R", 0.75, 0, 0), ("Yl", 0.75, 0.75, 0), ("G", 0, 0.75, 0), ("Cy", 0, 0.75, 0.75), ("B", 0, 0, 0.75), ("Mg", 0.75, 0, 0.75)]
    /// Unghiul liniei pielii (referință ORIENTATIVĂ de la vectorscopul video, ≈123° față de axa Cb, Cr în sus): nu e o țintă de culoare a pielii și nu garantează un ton corect.
    public static let vectorscopeSkinAngleDegrees: Float = 123
    public static let vectorscopeDomain = L("Imagine finală · sRGB codat (după GDC DRT) · plan Cb/Cr Rec.709 · eșantion ≤ 1400 px")
    /// Raster RGBA (alfa din densitate, fundal transparent): scară logaritmică cu rampă perceptuală (albastru → cian → alb); desenul grilei se face SEPARAT, vectorial. Compatibil cu apelurile vechi (`vectorscope(finalRGB:)`).
    public static func vectorscopeRaster(_ d: VectorscopeDensity) -> [UInt8] {
        let n = d.size; var out = [UInt8](repeating: 0, count: n * n * 4); let peak = max(1, d.peak)
        for k in 0..<(n * n) where d.counts[k] > 0 {
            let v = min(1, log1p(d.counts[k]) / log1p(peak))                      // 0…1, log
            let t = pow(v, 0.8); let r = 40 + 215 * t * t, g = 110 + 140 * t, bl = 190 + 60 * t
            out[k * 4] = UInt8(min(255, r)); out[k * 4 + 1] = UInt8(min(255, g)); out[k * 4 + 2] = UInt8(min(255, bl)); out[k * 4 + 3] = UInt8(60 + 195 * v) }
        return out
    }
    public static func vectorscope(finalRGB rgb: [Float], size n: Int = vectorscopeSize) -> [UInt8] { vectorscopeRaster(vectorscopeDensity(finalRGB: rgb, size: n)) }

    // MARK: RGB Parade (imaginea finală)
    public static let paradeColumns = 256, paradeRows = 128
    /// Densitate pe coloană de imagine: `counts[canal][rând * paradeColumns + coloană]`; rândul 0 = valoare codată 1,0 (sus), ultimul = 0. Scală liniară a valorilor codate sRGB 0…1; fără filtru high-pass.
    public struct ParadeDensity: Equatable { public var columns: Int; public var rows: Int; public var counts: [[Float]]; public var peak: Float; public var sourceWidth: Int, sourceHeight: Int }
    public static func parade(finalRGB rgb: [Float], width w: Int, height h: Int, columns: Int = paradeColumns, rows: Int = paradeRows) -> ParadeDensity {
        var c = [[Float]](repeating: [Float](repeating: 0, count: columns * rows), count: 3); guard w > 0, h > 0, rgb.count >= w * h * 3 else { return ParadeDensity(columns: columns, rows: rows, counts: c, peak: 0, sourceWidth: w, sourceHeight: h) }
        for y in 0..<h { for x in 0..<w { let col = min(columns - 1, x * columns / w); let i = (y * w + x) * 3
            for ch in 0..<3 { let v = rgb[i + ch]; guard v.isFinite else { continue }; let row = rows - 1 - min(rows - 1, max(0, Int(min(1, max(0, v)) * Float(rows - 1) + 0.5))); c[ch][row * columns + col] += 1 } } }
        let pk = c.map { $0.max() ?? 0 }.max() ?? 0
        return ParadeDensity(columns: columns, rows: rows, counts: c, peak: pk, sourceWidth: w, sourceHeight: h)
    }
    /// Raster RGBA al unui canal al parade-ului (log, ca vectorscopul); culoarea = canalul.
    public static func paradeRaster(_ d: ParadeDensity, channel ch: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: d.columns * d.rows * 4); let pk = max(1, d.peak)
        for k in 0..<(d.columns * d.rows) where d.counts[ch][k] > 0 { let v = min(1, log1p(d.counts[ch][k]) / log1p(pk)); let a = UInt8(70 + 185 * v)
            out[k * 4] = ch == 0 ? 255 : 90; out[k * 4 + 1] = ch == 1 ? 255 : 90; out[k * 4 + 2] = ch == 2 ? 255 : 90; out[k * 4 + 3] = a }
        return out
    }

    // MARK: diferență NR (pornit − oprit)
    public struct NRDifferenceStats: Equatable { public var meanAbs: Float; public var maxAbs: Float; public var changedFraction: Float; public var meanSigned: Float }
    /// `on`/`off`: aceeași imagine finală (sRGB codat 0…1), același cadru; rezultat gri 128 + gain·(on − off) pe canal. Identice ⇒ gri uniform exact. Fără normalizare automată.
    public static func nrDifference(on: [Float], off: [Float], width w: Int, height h: Int, gain: Float) -> (rgb8: [UInt8], stats: NRDifferenceStats) {
        let n = w * h * 3; var out = [UInt8](repeating: 128, count: n); guard on.count >= n, off.count >= n else { return (out, NRDifferenceStats(meanAbs: 0, maxAbs: 0, changedFraction: 0, meanSigned: 0)) }
        var sa: Double = 0, ss: Double = 0, mx: Float = 0, ch = 0
        for i in 0..<n { let d = on[i] - off[i]; guard d.isFinite else { continue }; sa += Double(abs(d)); ss += Double(d); mx = max(mx, abs(d)); if abs(d) > 0.5 / 255 { ch += 1 }
            out[i] = UInt8(max(0, min(255, (0.5 + gain * d) * 255 + 0.5))) }
        return (out, NRDifferenceStats(meanAbs: Float(sa / Double(max(1, n))), maxAbs: mx, changedFraction: Float(ch) / Float(max(1, n)), meanSigned: Float(ss / Double(max(1, n)))))
    }
    // MARK: eșantionare
    /// Reducere prin medii pe blocuri (valorile liniare se pot mediază; pentru imaginea finală e doar o eșantionare statistică).
    public static func downsample(_ rgb: [Float], width w: Int, height h: Int, maxSide: Int = 1400) -> (rgb: [Float], width: Int, height: Int) {
        let f = max(1, (max(w, h) + maxSide - 1) / maxSide); if f == 1 { return (rgb, w, h) }
        let nw = w / f, nh = h / f; var o = [Float](repeating: 0, count: nw * nh * 3); let inv = 1 / Float(f * f)
        for y in 0..<nh { for x in 0..<nw { var a: (Float, Float, Float) = (0, 0, 0)
            for yy in 0..<f { let row = ((y * f + yy) * w + x * f) * 3; for xx in 0..<f { a.0 += rgb[row + 3 * xx]; a.1 += rgb[row + 3 * xx + 1]; a.2 += rgb[row + 3 * xx + 2] } }
            let d = (y * nw + x) * 3; o[d] = a.0 * inv; o[d + 1] = a.1 * inv; o[d + 2] = a.2 * inv } }
        return (o, nw, nh)
    }

    // MARK: histogramă (imaginea finală, cod sRGB 0…1)
    public static func histogram(finalRGB rgb: [Float], bins: Int = 64) -> AnalysisHistogram {
        var r = [Float](repeating: 0, count: bins), g = r, b = r, l = r; let n = rgb.count / 3; guard n > 0 else { return AnalysisHistogram(bins: bins, r: r, g: g, b: b, luma: l) }
        func bin(_ v: Float) -> Int { min(bins - 1, max(0, Int(v.isFinite ? v * Float(bins) : 0))) }
        for i in 0..<n { let R = rgb[3 * i], G = rgb[3 * i + 1], B = rgb[3 * i + 2]; r[bin(R)] += 1; g[bin(G)] += 1; b[bin(B)] += 1; l[bin(0.2126 * R + 0.7152 * G + 0.0722 * B)] += 1 }
        let s = 1 / Float(n); for k in 0..<bins { r[k] *= s; g[k] *= s; b[k] *= s; l[k] *= s }
        return AnalysisHistogram(bins: bins, r: r, g: g, b: b, luma: l)
    }

    // MARK: culoare falsă (scene-liniar)
    /// Plaje în stopuri față de gri 18% (limita superioară exclusivă); ultima nu are limită. Praguri ORIENTATIVE, documentate în legendă.
    public static let falseColourBands: [(upper: Double, rgb: (UInt8, UInt8, UInt8), text: String)] = [
        (-6, (60, 0, 100), L("< −6 st · negru, fără detaliu")), (-4, (20, 50, 190), L("−6…−4 st · umbre adânci")), (-2, (0, 140, 170), "−4…−2 st · umbre"),
        (-0.5, (70, 160, 70), "−2…−0,5 st · tonuri medii-joase"), (0.5, (150, 150, 150), L("±0,5 st · în jurul gri 18%")), (2, (235, 220, 60), L("+0,5…+2 st · tonuri medii-înalte")),
        (3.5, (240, 140, 30), "+2…+3,5 st · lumini"), (4.5, (230, 60, 40), L("+3,5…+4,5 st · lumini aproape de tăiere")), (Double.infinity, (255, 0, 255), L("> +4,5 st · foarte sus (posibil tăiat)"))]
    public static func falseColourBand(stops s: Double) -> Int { if s.isNaN { return 0 }; for (i, b) in falseColourBands.enumerated() where s < b.upper { return i }; return falseColourBands.count - 1 }
    /// `lumaLinear` = luminanța scene-liniară per pixel (≤ 0 ⇒ plaja cea mai de jos).
    public static func falseColour(lumaLinear y: [Float], width w: Int, height h: Int) -> (rgb8: [UInt8], legend: [AnalysisLegendItem]) {
        var out = [UInt8](repeating: 0, count: w * h * 3); var counts = [Double](repeating: 0, count: falseColourBands.count)
        for i in 0..<(w * h) { let v = Double(y[i]); let s = v > 0 && v.isFinite ? log2(v / 0.18) : -99; let k = falseColourBand(stops: s); counts[k] += 1
            let c = falseColourBands[k].rgb; out[3 * i] = c.0; out[3 * i + 1] = c.1; out[3 * i + 2] = c.2 }
        let n = Double(max(1, w * h)); return (out, falseColourBands.enumerated().map { AnalysisLegendItem(r: $1.rgb.0, g: $1.rgb.1, b: $1.rgb.2, text: $1.text, fraction: counts[$0] / n) })
    }

    // MARK: tăieri (imaginea finală)
    public static func clipping(finalRGB rgb: [Float], width w: Int, height h: Int) -> (rgb8: [UInt8], legend: [AnalysisLegendItem], channelHigh: [Double]) {
        var out = [UInt8](repeating: 0, count: w * h * 3); var hi = 0.0, lo = 0.0; var ch = [0.0, 0.0, 0.0]; let hiT: Float = 253.5 / 255, loT: Float = 2.5 / 255
        for i in 0..<(w * h) { let R = rgb[3 * i], G = rgb[3 * i + 1], B = rgb[3 * i + 2]; let m = max(R, G, B)
            if R >= hiT { ch[0] += 1 }; if G >= hiT { ch[1] += 1 }; if B >= hiT { ch[2] += 1 }
            if m >= hiT { hi += 1; out[3 * i] = 255; out[3 * i + 1] = 40; out[3 * i + 2] = 40 }
            else if m <= loT { lo += 1; out[3 * i] = 40; out[3 * i + 1] = 90; out[3 * i + 2] = 255 }
            else { let l = UInt8(max(0, min(255, (0.2126 * R + 0.7152 * G + 0.0722 * B) * 0.45 * 255))); out[3 * i] = l; out[3 * i + 1] = l; out[3 * i + 2] = l } }
        let n = Double(max(1, w * h))
        return (out, [AnalysisLegendItem(r: 255, g: 40, b: 40, text: L("lumini tăiate (un canal ≥ 254/255)"), fraction: hi / n), AnalysisLegendItem(r: 40, g: 90, b: 255, text: "umbre la zero (toate canalele ≤ 2/255)", fraction: lo / n)], ch.map { $0 / n })
    }

    // MARK: saturație (croma Oklab a imaginii finale)
    static func srgbToLinear(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4) }
    /// Croma Oklab (Ottosson, domeniu public) a unui pixel sRGB codat.
    public static func oklabChroma(r: Float, g: Float, b: Float) -> Float {
        let R = srgbToLinear(max(0, r)), G = srgbToLinear(max(0, g)), B = srgbToLinear(max(0, b))
        let l = cbrtf(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B), m = cbrtf(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B), s = cbrtf(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B)
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s, bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return sqrtf(a * a + bb * bb)
    }
    public static let saturationBands: [(upper: Float, rgb: (UInt8, UInt8, UInt8), text: String)] = [
        (0.04, (60, 70, 90), "croma < 0,04 · aproape neutru"), (0.10, (40, 130, 200), "0,04…0,10 · slab saturat"), (0.20, (70, 190, 120), "0,10…0,20 · moderat"),
        (0.30, (235, 200, 60), "0,20…0,30 · intens"), (Float.infinity, (230, 60, 50), "≥ 0,30 · foarte intens")]
    public static func saturation(finalRGB rgb: [Float], width w: Int, height h: Int) -> (rgb8: [UInt8], legend: [AnalysisLegendItem]) {
        var out = [UInt8](repeating: 0, count: w * h * 3); var counts = [Double](repeating: 0, count: saturationBands.count)
        for i in 0..<(w * h) { let c = oklabChroma(r: rgb[3 * i], g: rgb[3 * i + 1], b: rgb[3 * i + 2]); var k = saturationBands.count - 1; for (j, b) in saturationBands.enumerated() where c < b.upper { k = j; break }
            counts[k] += 1; let col = saturationBands[k].rgb; out[3 * i] = col.0; out[3 * i + 1] = col.1; out[3 * i + 2] = col.2 }
        let n = Double(max(1, w * h)); return (out, saturationBands.enumerated().map { AnalysisLegendItem(r: $1.rgb.0, g: $1.rgb.1, b: $1.rgb.2, text: $1.text, fraction: counts[$0] / n) })
    }

    static let satBandsHSV: [(upper: Float, rgb: (UInt8, UInt8, UInt8), text: String)] = [
        (0.08, (60, 70, 90), "S < 0,08 · aproape neutru"), (0.25, (40, 130, 200), "0,08…0,25 · slab"), (0.50, (70, 190, 120), "0,25…0,50 · moderat"), (0.75, (235, 200, 60), "0,50…0,75 · intens"), (Float.infinity, (230, 60, 50), "≥ 0,75 · foarte intens")]
    static let relBands: [(upper: Float, rgb: (UInt8, UInt8, UInt8), text: String)] = [
        (0.06, (60, 70, 90), "ρ < 0,06 · aproape neutru"), (0.15, (40, 130, 200), "0,06…0,15 · slab"), (0.28, (70, 190, 120), "0,15…0,28 · moderat"), (0.42, (235, 200, 60), "0,28…0,42 · intens"), (Float.infinity, (230, 60, 50), "≥ 0,42 · foarte intens")]
    /// Hartă generică pe benzi: `metric` primește pixelul sRGB codat și întoarce valoarea sau nil (exclus → gri închis).
    static func banded(finalRGB rgb: [Float], width w: Int, height h: Int, bands: [(upper: Float, rgb: (UInt8, UInt8, UInt8), text: String)], metric: (Float, Float, Float) -> Float?) -> (rgb8: [UInt8], legend: [AnalysisLegendItem]) {
        var out = [UInt8](repeating: 0, count: w * h * 3); var counts = [Double](repeating: 0, count: bands.count); var used = 0.0
        for i in 0..<(w * h) { guard let c = metric(rgb[3 * i], rgb[3 * i + 1], rgb[3 * i + 2]) else { out[3 * i] = 25; out[3 * i + 1] = 25; out[3 * i + 2] = 25; continue }
            var k = bands.count - 1; for (j, b) in bands.enumerated() where c < b.upper { k = j; break }; counts[k] += 1; used += 1; let col = bands[k].rgb; out[3 * i] = col.0; out[3 * i + 1] = col.1; out[3 * i + 2] = col.2 }
        let n = max(1, used); return (out, bands.enumerated().map { AnalysisLegendItem(r: $1.rgb.0, g: $1.rgb.1, b: $1.rgb.2, text: $1.text, fraction: counts[$0] / n) })
    }
    public static func saturationHSV(finalRGB rgb: [Float], width w: Int, height h: Int) -> (rgb8: [UInt8], legend: [AnalysisLegendItem]) {
        banded(finalRGB: rgb, width: w, height: h, bands: satBandsHSV) { r, g, b in let mx = max(r, max(g, b)), mn = min(r, min(g, b)); return mx > 0 ? (mx - mn) / mx : 0 } }
    public static func chromaRelative(finalRGB rgb: [Float], width w: Int, height h: Int) -> (rgb8: [UInt8], legend: [AnalysisLegendItem]) {
        banded(finalRGB: rgb, width: w, height: h, bands: relBands) { r, g, b in
            let R = srgbToLinear(max(0, r)), G = srgbToLinear(max(0, g)), B = srgbToLinear(max(0, b))
            let l = cbrtf(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B), m = cbrtf(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B), s = cbrtf(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B)
            let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s; guard L >= 0.05 else { return nil }
            let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s, bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s; return sqrtf(a * a + bb * bb) / L } }

    // MARK: ajutor de ton piele (selecție după culoare)
    /// Interval YCbCr (BT.601, cod 0…255) din literatura de detecție a pielii după culoare (Chai & Ngan, 1999): Cb 77…127, Cr 133…173, plus Y > 40. Euristică, nu detecție.
    public static func isSkinColour(r: Float, g: Float, b: Float) -> Bool {
        let R = r * 255, G = g * 255, B = b * 255
        let y = 0.299 * R + 0.587 * G + 0.114 * B, cb = 128 - 0.168736 * R - 0.331264 * G + 0.5 * B, cr = 128 + 0.5 * R - 0.418688 * G - 0.081312 * B
        return y > 40 && cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173
    }
    public static func skin(finalRGB rgb: [Float], width w: Int, height h: Int) -> (rgb8: [UInt8], legend: [AnalysisLegendItem]) {
        var out = [UInt8](repeating: 0, count: w * h * 3); var hit = 0.0
        for i in 0..<(w * h) { let R = rgb[3 * i], G = rgb[3 * i + 1], B = rgb[3 * i + 2]
            if isSkinColour(r: R, g: G, b: B) { hit += 1; out[3 * i] = UInt8(max(0, min(255, R * 255 * 0.45 + 120))); out[3 * i + 1] = UInt8(max(0, min(255, G * 255 * 0.45 + 130))); out[3 * i + 2] = UInt8(max(0, min(255, B * 255 * 0.45 + 20))) }
            else { let l = UInt8(max(0, min(255, (0.2126 * R + 0.7152 * G + 0.0722 * B) * 0.4 * 255))); out[3 * i] = l; out[3 * i + 1] = l; out[3 * i + 2] = l } }
        let n = Double(max(1, w * h)); return (out, [AnalysisLegendItem(r: 200, g: 210, b: 90, text: L("culoare în intervalul de piele (selecție după culoare)"), fraction: hit / n)])
    }
}

/// Citire minimă a TIFF-urilor 16 biți scrise de `TIFF16.write` (necomprimat, RGB intercalat, little-endian) → valori 0…1.
extension TIFF16 {
    public static func read(_ url: URL) throws -> (rgb: [Float], width: Int, height: Int) {
        let d = try Data(contentsOf: url); guard d.count > 16, d[0] == 0x49, d[1] == 0x49 else { throw PipelineError.badOutput("TIFF nerecunoscut") }
        func u16(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 }; func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        let ifd = u32(4); let n = u16(ifd); var w = 0, h = 0, off = 0
        for e in 0..<n { let o = ifd + 2 + 12 * e; let tag = u16(o), type = u16(o + 2); let v = type == 3 ? u16(o + 8) : u32(o + 8); if tag == 256 { w = v } else if tag == 257 { h = v } else if tag == 273 { off = v } }
        guard w > 0, h > 0, off > 0, d.count >= off + w * h * 6 else { throw PipelineError.badOutput("TIFF incomplet") }
        var rgb = [Float](repeating: 0, count: w * h * 3); d.withUnsafeBytes { p in for i in 0..<(w * h * 3) { let o = off + 2 * i; rgb[i] = Float(UInt16(p[o]) | UInt16(p[o + 1]) << 8) / 65535 } }
        return (rgb, w, h)
    }
}

extension OwnCoreProcessor {
    /// Analiza cerută pentru fotografia + reglajele date. NU scrie nimic în folderul de rezultate/export și nu schimbă rezultatul procesării (folosește rezultatul în cache și o copie redusă a datelor).
    public func analyze(photoPath: String, adjustments adjIn: AdjustmentSet, mode: AnalysisMode, vectorscope: Bool = false, parade: Bool = false, nrGain: Float = 4, decode: DecodeOptions = DecodeOptions()) throws -> AnalysisResult {
        let adjustments = adjIn.effective
        let processed = try process(photoPath: photoPath, quality: .preview, adjustments: adjustments, decode: decode)
        let fin = try TIFF16.read(processed.url); let small = PhotoAnalysis.downsample(fin.rgb, width: fin.width, height: fin.height)
        let hist = PhotoAnalysis.histogram(finalRGB: small.rgb); var notes: [String] = []; var legend: [AnalysisLegendItem] = []; var rgb8: [UInt8] = []; var nrStatsOut: PhotoAnalysis.NRDifferenceStats? = nil; var w = small.width, h = small.height
        switch mode {
        case .off: rgb8 = []
        case .falseColour:
            let dec = try decodedPreview(photoPath, decodeOptions(photoPath: photoPath, adjustments: adjustments, base: decode)); var ds = PhotoAnalysis.downsample(dec.image.rgb, width: dec.image.width, height: dec.image.height)
            if adjustments.retouch.contains(where: { $0.enabled }) { ds = (Retouch.apply(adjustments.retouch, to: ds.rgb, width: ds.width, height: ds.height), ds.width, ds.height) }
            var p = adjustments.coreParams(estimate: dec.suggestion.stops, inputIsLinear: true, output: outputTransform); p.drt = 0       // înainte de DRT: cod log al familiei, după toate reglajele
            var code = [Float](repeating: 0, count: ds.rgb.count); let cm = LocalCorrection.coreMasks(adjustments.locals, family: adjustments.family)
            let gp = adjustments.geometry.plan(srcW: ds.width, srcH: ds.height); let geoOn = !adjustments.geometry.isNeutral; if geoOn { code = [Float](repeating: 0, count: gp.outW * gp.outH * 3) }
            var rc: Int32 = 0
            if !geoOn { ds.rgb.withUnsafeBufferPointer { i in code.withUnsafeMutableBufferPointer { o in rc = runCoreMasks(&p, cm, input: i.baseAddress!, output: o.baseAddress!, width: ds.width, height: ds.height) } } }
            else { var geo = makeGeom(gp, srcW: ds.width, srcH: ds.height); var offs = cm.offsets; ds.rgb.withUnsafeBufferPointer { i in code.withUnsafeMutableBufferPointer { o in cm.data.withUnsafeBufferPointer { md in offs.withUnsafeMutableBufferPointer { op in rc = pc_process_image_geom(&p, cm.locals, Int32(cm.locals.count), md.baseAddress, op.baseAddress, &geo, i.baseAddress!, o.baseAddress!, 0) } } } } }
            guard rc == 0 else { throw PipelineError.drtData("Analiza a refuzat (cod \(rc))") }
            var lu = [Double](repeating: 0, count: 3); pc_family_luma(p.family, &lu); let ow = geoOn ? gp.outW : ds.width, oh = geoOn ? gp.outH : ds.height; var y = [Float](repeating: 0, count: ow * oh)
            for k in 0..<y.count { var s = 0.0; for c in 0..<3 { s += lu[c] * pc_family_decode(p.family, Double(code[3 * k + c])) }; y[k] = Float(s) }
            let r = PhotoAnalysis.falseColour(lumaLinear: y, width: ow, height: oh); rgb8 = r.rgb8; legend = r.legend; w = ow; h = oh
            notes = [LF("Luminanța = rândul Y al familiei %@, pe codul înainte de DRT decodat în liniar; gri 18% = 0 st.", adjustments.family.shortLabel)]
        case .clipping: let r = PhotoAnalysis.clipping(finalRGB: small.rgb, width: w, height: h); rgb8 = r.rgb8; legend = r.legend; notes = ["Canale ≥ 254/255: R \(pct(r.channelHigh[0])) · G \(pct(r.channelHigh[1])) · B \(pct(r.channelHigh[2]))"]
        case .saturation: let r = PhotoAnalysis.saturation(finalRGB: small.rgb, width: w, height: h); rgb8 = r.rgb8; legend = r.legend; notes = [L("Metrica: croma Oklab absolută C = √(a²+b²) pe imaginea finală (nu HSV, nu relativă la luminozitate).")]
        case .saturationHSV: let r = PhotoAnalysis.saturationHSV(finalRGB: small.rgb, width: w, height: h); rgb8 = r.rgb8; legend = r.legend; notes = ["Metrica: S = (max−min)/max pe valorile sRGB codate ale imaginii finale. Nu e croma Oklab."]
        case .chromaRel: let r = PhotoAnalysis.chromaRelative(finalRGB: small.rgb, width: w, height: h); rgb8 = r.rgb8; legend = r.legend; notes = [L("Metrica: ρ = C/L (Oklab) pe imaginea finală; pixelii cu L < 0,05 sunt excluși (gri închis, nu intră în procente).")]
        case .skin: let r = PhotoAnalysis.skin(finalRGB: small.rgb, width: w, height: h); rgb8 = r.rgb8; legend = r.legend
        case .nrDifference:
            var offAdj = adjustments; offAdj.detail.nrLuma = 0; offAdj.detail.nrChroma = 0       // singura diferență: NR oprit
            if adjustments.detail.nrLuma == 0 && adjustments.detail.nrChroma == 0 { notes = [L("Reducerea de zgomot e la zero: nu are ce să difere (gri uniform).")] }
            let po = try process(photoPath: photoPath, quality: .preview, adjustments: offAdj, decode: decode); let fo = try TIFF16.read(po.url); let so = PhotoAnalysis.downsample(fo.rgb, width: fo.width, height: fo.height)
            guard so.width == small.width, so.height == small.height else { throw PipelineError.drtData("Diferența NR: dimensiuni diferite între cele două procesări") }
            let r = PhotoAnalysis.nrDifference(on: small.rgb, off: so.rgb, width: w, height: h, gain: nrGain); rgb8 = r.rgb8; nrStatsOut = r.stats
            legend = [AnalysisLegendItem(r: 128, g: 128, b: 128, text: LF("gri 50% = nicio diferență · amplificare ×%@", String(format: "%g", nrGain)), fraction: Double(1 - r.stats.changedFraction)),
                      AnalysisLegendItem(r: 230, g: 230, b: 230, text: L("mai deschis = NR a făcut pixelul mai luminos (semn pozitiv)"), fraction: 0), AnalysisLegendItem(r: 40, g: 40, b: 40, text: L("mai închis = NR a făcut pixelul mai întunecat (semn negativ)"), fraction: 0)]
            notes += [LF("|diferență| medie %@ · maximă %@ (din 1,0) · pixeli modificați %@", String(format: "%.5f", r.stats.meanAbs), String(format: "%.4f", r.stats.maxAbs), pct(Double(r.stats.changedFraction)))]
        }
        var res = AnalysisResult(mode: mode, width: w, height: h, rgb8: rgb8, legend: legend, notes: notes, histogram: hist, domain: mode.domain, sampled: LF("măsurat pe %@×%@ px (previzualizare redusă)", small.width, small.height))
        if vectorscope { res.vectorscope = PhotoAnalysis.vectorscope(finalRGB: small.rgb) }
        if parade { res.parade = PhotoAnalysis.parade(finalRGB: small.rgb, width: small.width, height: small.height) }
        if mode == .nrDifference { res.nrGain = nrGain; res.nrStats = nrStatsOut }
        return res
    }
    private func pct(_ f: Double) -> String { String(format: "%.2f%%", f * 100) }
}
