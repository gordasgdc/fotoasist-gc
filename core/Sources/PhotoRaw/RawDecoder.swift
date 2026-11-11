import Foundation
import CLibRaw

/// Decodare RAW → DWG liniar (float32, fără tăiere la negru, fără expunere) → intermediar codat DaVinci Intermediate. Aceeași matematică ca `scripts/decode_float.py` (paritate verificată),
/// cu politicile de alb și decupare din `RawPolicy.swift`. Nu face autoexpunere și nu modifică originalul.
/// Politica de lumini, SEPARATĂ de scara „1.0 = alb de referință”:
/// - `clipWhite`: fiecare canal tăiat la 1.0 după WB (vechea politică; pierde și valorile legitime peste referință);
/// - `keep`: nicio tăiere (intermediar float complet; pixelii saturați rămân cu dominantă magenta după WB);
/// - `clipSaturated`: se taie DOAR pixelii cu saturație ADC detectată (plus 2 px de margine pentru demosaic), la plafonul neutru al canalului cel mai limitat; valorile peste 1.0 provenite din
///   WB, din domeniul peste albul de referință sau din matrice rămân. Comparația politicilor: docs/COLOR_AND_OUTPUT_CONTRACT.md.
public enum HighlightPolicy: String, Codable { case clipWhite, keep, clipSaturated }

/// De unde vin valorile > 1.0 (fracții de pixeli; categoriile NU sunt exclusive între ele). Măsurat înainte de aplicarea politicii.
public struct HighlightCauses: Equatable, Codable {
    public var rawAboveReference = 0.0      // NESATURAT, un canal brut peste albul de referință (domeniul dintre alb și saturație): informație reală, neverificată ca liniaritate
    public var whiteBalanceOnly = 0.0       // NESATURAT, canale brute ≤ referință, dar ≥1 canal > 1.0 doar prin înmulțirea WB: valoare legitimă (nu artefact)
    public var adcSaturated = 0.0           // saturație ADC detectată (cu margine de demosaic): valori nesigure, indiferent de WB (exclusiv față de celelalte două)
    public var matrixOnly = 0.0             // după WB toate ≤ 1.0, dar matricea cameră→DWG produce > 1.0
    public init() {}
}
public enum WhiteBalanceMode: String, Codable { case camera, neutral }
public enum CropChoice: Equatable { case defaultCrop, activeArea, explicit(PixelRect) }

public struct DecodeOptions: Equatable {
    public var white: WhiteLevelSource = .vendorViaLibRaw
    public var highlight: HighlightPolicy = .clipSaturated   // implicit ales după comparația politicilor (COLOR_AND_OUTPUT_CONTRACT); `.clipWhite` = paritatea cu oracolul Python
    public var wb: WhiteBalanceMode = .camera
    public var crop: CropChoice = .defaultCrop
    public var applyOrientation = true
    /// Previzualizare rapidă: LibRaw `half_size` (fără demosaic, 1/4 din pixeli). Rezultatul e etichetat ca previzualizare de către apelant; exportul final folosește mereu rezoluția plină.
    public var halfSize = false
    /// Compensarea dezvoltării (EV, câștig liniar 2^EV aplicat după balansul de alb și plafonul de saturație, înaintea oricărui reglaj): 0 = nimic. Valoarea o alege apelantul din reglajele fotografiei (vezi `RawBaseline`), niciodată decodorul singur.
    public var baselineEV = 0.0
    /// Dezvoltarea RAW veche (revizia 1): negrul pe model de pixeli ignorat și crop-ul forțat 3:2, ca înainte de 2026-10-23. Doar pentru reglajele salvate sub acea revizie (vezi `RawDevelopment`); fotografiile noi nu o folosesc niciodată.
    public var legacyV1 = false
    public init() {}
}

public struct DecodeReport: Equatable {
    public var make: String, model: String, libRawVersion: String
    public var whitePlan: WhiteLevelPlan
    public var cropPlan: CropPlan
    public var appliedCrop: PixelRect          // în coordonatele bufferului RAW complet
    public var orientationFlip: Int
    public var wbMultipliers: [Float]          // normalizați pe G
    public var fracChannelOverWhiteAfterWB: Double
    public var highlight: HighlightPolicy
    public var pedestal: Int
    public var linMin: Float, linMax: Float
    public var fracNegative: Double
    public var causes = HighlightCauses()
    public var blackSpread = 0.0               // max − min al negrului pe canale și model (ADU); > 0.1% din domeniu ⇒ scădere nativă LibRaw, fără piedestal
    public var cameraExposureShift: Double?    // compensarea de expunere a RAW declarată de cameră (Fuji: RawExposureBias/ExpoMidPointShift, EV; negativ = RAW mai întunecat decât redarea camerei); nil = necunoscută
    public var appliedBaselineEV = 0.0         // câștigul (EV) aplicat de decodor din `DecodeOptions.baselineEV`
    public init(make: String, model: String, libRawVersion: String, whitePlan: WhiteLevelPlan, cropPlan: CropPlan, appliedCrop: PixelRect, orientationFlip: Int, wbMultipliers: [Float], fracChannelOverWhiteAfterWB: Double, highlight: HighlightPolicy, pedestal: Int, linMin: Float, linMax: Float, fracNegative: Double) {
        self.make = make; self.model = model; self.libRawVersion = libRawVersion; self.whitePlan = whitePlan; self.cropPlan = cropPlan; self.appliedCrop = appliedCrop; self.orientationFlip = orientationFlip; self.wbMultipliers = wbMultipliers
        self.fracChannelOverWhiteAfterWB = fracChannelOverWhiteAfterWB; self.highlight = highlight; self.pedestal = pedestal; self.linMin = linMin; self.linMax = linMax; self.fracNegative = fracNegative }
}

public struct DecodedLinear { public var image: FloatImage; public var report: DecodeReport }

public enum DIEncoding {
    public static let A = 0.0075, B = 7.0, C = 0.07329248, M = 10.44426855, linCut = 0.00262409
    public static func encode(_ x: Float) -> Float {
        let d = Double(x); if d <= linCut { return Float(d * M) }
        return Float((log2(max(d, 0) + A) + B) * C)
    }
}

struct Mat3 { var m: [Double]   // rând-major
    static func mul(_ a: Mat3, _ b: Mat3) -> Mat3 { var r = [Double](repeating: 0, count: 9); for i in 0..<3 { for j in 0..<3 { for k in 0..<3 { r[3 * i + j] += a.m[3 * i + k] * b.m[3 * k + j] } } }; return Mat3(m: r) }
    func inverse() -> Mat3 {
        let a = m; let det = a[0] * (a[4] * a[8] - a[5] * a[7]) - a[1] * (a[3] * a[8] - a[5] * a[6]) + a[2] * (a[3] * a[7] - a[4] * a[6])
        return Mat3(m: [(a[4] * a[8] - a[5] * a[7]) / det, (a[2] * a[7] - a[1] * a[8]) / det, (a[1] * a[5] - a[2] * a[4]) / det,
                        (a[5] * a[6] - a[3] * a[8]) / det, (a[0] * a[8] - a[2] * a[6]) / det, (a[2] * a[3] - a[0] * a[5]) / det,
                        (a[3] * a[7] - a[4] * a[6]) / det, (a[1] * a[6] - a[0] * a[7]) / det, (a[0] * a[4] - a[1] * a[3]) / det])
    }
    /// Matricea RGB→XYZ pentru primare xy și punct alb (coloane = primare scalate).
    static func rgbToXYZ(_ p: [(Double, Double)], white w: (Double, Double)) -> Mat3 {
        func xyz(_ x: Double, _ y: Double) -> [Double] { [x / y, 1, (1 - x - y) / y] }
        let cols = p.map { xyz($0.0, $0.1) }; let P = Mat3(m: [cols[0][0], cols[1][0], cols[2][0], cols[0][1], cols[1][1], cols[2][1], cols[0][2], cols[1][2], cols[2][2]])
        let wx = xyz(w.0, w.1); let s = P.inverse(); let S = [0, 1, 2].map { i in s.m[3 * i] * wx[0] + s.m[3 * i + 1] * wx[1] + s.m[3 * i + 2] * wx[2] }
        return Mat3(m: [P.m[0] * S[0], P.m[1] * S[1], P.m[2] * S[2], P.m[3] * S[0], P.m[4] * S[1], P.m[5] * S[2], P.m[6] * S[0], P.m[7] * S[1], P.m[8] * S[2]])
    }
    static let xyzToDWG = rgbToXYZ([(0.8000, 0.3130), (0.1682, 0.9877), (0.0790, -0.1155)], white: (0.3127, 0.3290)).inverse()
}

extension RawFile {
    public static let outputPedestal = 512

    /// Decodează în DWG liniar (1.0 = nivelul alb ales; fără expunere). Decuparea și orientarea se aplică la sfârșit, pe bufferul float (originalul rămâne neatins).
    /// Diagnostic: secundele ultimei decodări pe etape (unpack/process/mem/loop/orient). Nu influențează rezultatul.
    nonisolated(unsafe) public static var lastTimings: [String: Double] = [:]
    public func decodeLinearDWG(_ opt: DecodeOptions = DecodeOptions()) throws -> DecodedLinear {
        let ped0 = RawFile.outputPedestal
        let info = self.info, geom = self.geometry
        var tm: [String: Double] = [:]; var tk = Date(); func lap(_ k: String) { tm[k] = Date().timeIntervalSince(tk); tk = Date() }
        try unpackForDecode(); lap("unpack")
        let (black, blackInt, vendorWhite, adcMax, camMul, camXYZ, blackSpread) = lrParams(legacy: opt.legacyV1)
        let wplan = WhiteLevelPlan.plan(black: blackInt, vendorWhite: vendorWhite, adcMax: adcMax, source: opt.white)
        let cplan = CropPlan.resolve(geom, legacyAspect: opt.legacyV1)
        let fullCrop: PixelRect = { switch opt.crop { case .defaultCrop: return cplan.defaultCrop; case .activeArea: return cplan.activeArea; case .explicit(let r): return r } }()
        let crop = fullCrop
        guard crop.w > 0, crop.h > 0, crop.x >= cplan.activeArea.x, crop.y >= cplan.activeArea.y, crop.x + crop.w <= cplan.activeArea.x + cplan.activeArea.w, crop.y + crop.h <= cplan.activeArea.y + cplan.activeArea.h else { throw RawError.process(-4) }

        // Piedestalul (păstrează zgomotul sub negru) cere un negru MEDIU reprezentativ: `user_black` înlocuiește TOT negrul LibRaw (și modelul pe pixeli). Dacă negrul e < piedestal (user_black ar fi negativ = ignorat de LibRaw)
        // sau variază între canale/poziții peste 0.1% din domeniu, folosim scăderea nativă LibRaw (exactă pe poziție, fără piedestal): zgomotul exact la negru se taie la 0, dar nu apar dominante în umbre.
        let nativeBlack = !opt.legacyV1 && (Int(black.rounded()) < ped0 || blackSpread > 0.001 * (Double(wplan.white) - black))
        let ped = nativeBlack ? 0 : ped0
        try processForDecode(userBlack: nativeBlack ? -1 : Int(black) - ped, halfSize: opt.halfSize); lap("process")
        let (w, h, buf) = try makeMem16(); lap("mem")      // zona activă, RGB 16 biți, fără rotație (la half_size: dimensiuni înjumătățite)
        let hs = opt.halfSize ? 2 : 1
        let wbRaw: [Float] = opt.wb == .camera ? [camMul[0] / camMul[1], 1, camMul[2] / camMul[1]] : [1, 1, 1]
        let scale = 1.0 / Double(wplan.white) // intermediar în Double ca să fie identic cu referința numpy (float64 apoi float32)
        _ = scale
        let range = Double(wplan.white) - black
        let rows: [Double] = [Double](camXYZ)   // 3×3 XYZ→cameră (primele 3 rânduri), normalizate mai jos
        let d65 = [0.95047, 1.0, 1.08883]
        var norm = rows; for r in 0..<3 { let s = rows[3 * r] * d65[0] + rows[3 * r + 1] * d65[1] + rows[3 * r + 2] * d65[2]; for c in 0..<3 { norm[3 * r + c] = rows[3 * r + c] / s } }
        let toXYZ = Mat3(m: norm).inverse(); let toDWG = Mat3.mul(Mat3.xyzToDWG, toXYZ)
        let m: [Float] = toDWG.m.map { Float($0) }
        let ax = (crop.x - cplan.activeArea.x) / hs, ay = (crop.y - cplan.activeArea.y) / hs
        let cw = min(crop.w / hs, w - ax), ch = min(crop.h / hs, h - ay)
        precondition(cw > 0 && ch > 0, "buffer LibRaw mai mic decât zona activă")
        var out = [Float](repeating: 0, count: cw * ch * 3)
        var over = 0, neg = 0; var mn = Float.infinity, mx = -Float.infinity
        var cRaw = 0, cWB = 0, cMat = 0, cSat = 0
        let baseline = max(-8, min(8, opt.baselineEV)); let gainF = Float(exp2(baseline)); let cameraShift = self.cameraExposureShift
        let pedF = Float(ped), rangeF = Float(range)
        let satNorm = Float((Double(wplan.adcMax) - black) / range), ceiling = satNorm * min(wbRaw[0], wbRaw[1], wbRaw[2])
        // mască de saturație ADC (+ margine de 2 px pentru demosaic): un canal ≥ 99.5% din domeniul ADC
        var sat = [UInt8](repeating: 0, count: cw * ch)
        // Buclele pe pixeli rulează pe rânduri, în paralel (aceeași aritmetică pe pixel; contoarele se adună exact, min/max nu depind de ordine). Rezultatul e identic bit cu bit cu varianta secvențială (verificat prin amprentă SHA-256).
        let nChunks = max(1, min(ch, ProcessInfo.processInfo.activeProcessorCount * 2)); let rowsPer = (ch + nChunks - 1) / nChunks
        buf.withUnsafeBufferPointer { src in
            let thr = 0.995 * satNorm * rangeF + pedF
            sat.withUnsafeMutableBufferPointer { sp in
                DispatchQueue.concurrentPerform(iterations: nChunks) { k in
                    let y0 = k * rowsPer, y1 = min(ch, y0 + rowsPer)
                    for y in y0..<y1 { for x in 0..<cw { let si = 3 * ((ay + y) * w + ax + x); if Float(src[si]) >= thr || Float(src[si + 1]) >= thr || Float(src[si + 2]) >= thr { sp[y * cw + x] = 1 } } }
                }
            }
        }
        if sat.contains(1) {
            var tmp = [UInt8](repeating: 0, count: cw * ch)
            sat.withUnsafeBufferPointer { sp in tmp.withUnsafeMutableBufferPointer { tp in
                DispatchQueue.concurrentPerform(iterations: nChunks) { k in
                    let y0 = k * rowsPer, y1 = min(ch, y0 + rowsPer)
                    for y in y0..<y1 { for x in 0..<cw where sp[y * cw + x] == 1 { for dx in -2...2 { let xx = x + dx; if xx >= 0 && xx < cw { tp[y * cw + xx] = 1 } } } }
                } } }
            var sat2 = [UInt8](repeating: 0, count: cw * ch)
            tmp.withUnsafeBufferPointer { tp in sat2.withUnsafeMutableBufferPointer { sp in
                DispatchQueue.concurrentPerform(iterations: nChunks) { k in      // vertical: sat2[y,x] = există tmp[yy,x] cu |yy−y| ≤ 2 (echivalent cu propagarea din varianta secvențială)
                    let y0 = k * rowsPer, y1 = min(ch, y0 + rowsPer)
                    for y in y0..<y1 { for x in 0..<cw { var f: UInt8 = 0; for yy in max(0, y - 2)...min(ch - 1, y + 2) where tp[yy * cw + x] == 1 { f = 1; break }; sp[y * cw + x] = f } }
                } } }
            sat = sat2
        }
        struct Acc { var over = 0, neg = 0, cRaw = 0, cWB = 0, cMat = 0, cSat = 0; var mn = Float.infinity, mx = -Float.infinity }
        var accs = [Acc](repeating: Acc(), count: nChunks)
        let hl = opt.highlight
        buf.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                sat.withUnsafeBufferPointer { sp in
                    accs.withUnsafeMutableBufferPointer { ap in
                        DispatchQueue.concurrentPerform(iterations: nChunks) { k in
                            var a = Acc(); let y0 = k * rowsPer, y1 = min(ch, y0 + rowsPer)
                            for y in y0..<y1 { for x in 0..<cw {
                                let si = 3 * ((ay + y) * w + ax + x), di = 3 * (y * cw + x)
                                let rn = (Float(src[si]) - pedF) / rangeF, gn = (Float(src[si + 1]) - pedF) / rangeF, bn = (Float(src[si + 2]) - pedF) / rangeF
                                var r = rn * wbRaw[0], g = gn * wbRaw[1], b = bn * wbRaw[2]
                                let rawAbove = rn > 1 || gn > 1 || bn > 1, anyOver = r > 1 || g > 1 || b > 1, isSat = sp[y * cw + x] == 1
                                if anyOver { a.over += 1 }; if isSat { a.cSat += 1 } else if rawAbove { a.cRaw += 1 } else if anyOver { a.cWB += 1 }
                                switch hl {
                                case .clipWhite: r = min(r, 1); g = min(g, 1); b = min(b, 1)
                                case .keep: break
                                case .clipSaturated: if isSat { r = min(r, ceiling); g = min(g, ceiling); b = min(b, ceiling) }
                                }
                                r *= gainF; g *= gainF; b *= gainF   // compensarea dezvoltării: după plafonul de saturație (care rămâne la același nivel de senzor), înaintea matricei
                                let R = m[0] * r + m[1] * g + m[2] * b, G = m[3] * r + m[4] * g + m[5] * b, B = m[6] * r + m[7] * g + m[8] * b
                                if !anyOver && (R > 1.0001 * gainF || G > 1.0001 * gainF || B > 1.0001 * gainF) { a.cMat += 1 }
                                dst[di] = R; dst[di + 1] = G; dst[di + 2] = B
                                if R < 0 || G < 0 || B < 0 { a.neg += 1 }
                                a.mn = min(a.mn, R, G, B); a.mx = max(a.mx, R, G, B)
                            } }
                            ap[k] = a
                        }
                    }
                }
            }
        }
        for a in accs { over += a.over; neg += a.neg; cRaw += a.cRaw; cWB += a.cWB; cMat += a.cMat; cSat += a.cSat; mn = min(mn, a.mn); mx = max(mx, a.mx) }
        lap("loop")
        var img = FloatImage(width: cw, height: ch, rgb: out)
        let flip = info.flip
        if opt.applyOrientation { img = FloatImage.oriented(img, flip: flip) }
        lap("orient"); RawFile.lastTimings = tm
        let n = Double(cw * ch)
        let rep = DecodeReport(make: info.make, model: info.model, libRawVersion: RawFile.libraryVersion, whitePlan: wplan, cropPlan: cplan, appliedCrop: crop, orientationFlip: opt.applyOrientation ? flip : 0,
                               wbMultipliers: wbRaw, fracChannelOverWhiteAfterWB: Double(over) / n, highlight: opt.highlight, pedestal: ped, linMin: mn, linMax: mx, fracNegative: Double(neg) / n)
        var rep2 = rep; rep2.blackSpread = blackSpread; rep2.cameraExposureShift = cameraShift; rep2.appliedBaselineEV = baseline; rep2.causes.rawAboveReference = Double(cRaw) / n; rep2.causes.whiteBalanceOnly = Double(cWB) / n; rep2.causes.adcSaturated = Double(cSat) / n; rep2.causes.matrixOnly = Double(cMat) / n
        return DecodedLinear(image: img, report: rep2)
    }
}

extension FloatImage {
    /// Orientare LibRaw `flip`: 0 nimic, 3 = 180°, 5 = 90° în sens antiorar, 6 = 90° în sens orar (ca la dcraw).
    public static func oriented(_ s: FloatImage, flip: Int) -> FloatImage {
        guard [3, 5, 6].contains(flip) else { return s }
        let w = s.width, h = s.height; let nw = (flip == 3) ? w : h, nh = (flip == 3) ? h : w
        var d = [Float](repeating: 0, count: s.rgb.count)
        for y in 0..<h { for x in 0..<w {
            let (nx, ny): (Int, Int) = flip == 3 ? (w - 1 - x, h - 1 - y) : (flip == 6 ? (h - 1 - y, x) : (y, w - 1 - x))
            let si = 3 * (y * w + x), di = 3 * (ny * nw + nx); d[di] = s.rgb[si]; d[di + 1] = s.rgb[si + 1]; d[di + 2] = s.rgb[si + 2]
        } }
        return FloatImage(width: nw, height: nh, rgb: d)
    }
    /// Intermediar codat DaVinci Intermediate (A,B,C,M ai Blackmagic); negativele sub tăietura liniară se mențin (ramura liniară e definită și sub 0).
    public func diEncoded() -> FloatImage {
        var o = rgb; for i in 0..<o.count { o[i] = DIEncoding.encode(o[i]) }; return FloatImage(width: width, height: height, rgb: o)
    }
}

extension FloatImage {
    /// Miniatură mică (medii pe blocuri) în valori NEMODIFICATE, pentru verificarea „liveness” fără a recitit EXR-ul plin.
    public func thumbnail(maxSide: Int = 64) -> FloatImage {
        let f = max(1, max(width, height) / maxSide); let tw = max(1, width / f), th = max(1, height / f)
        var o = [Float](repeating: 0, count: tw * th * 3)
        for ty in 0..<th { for tx in 0..<tw {
            var acc: (Double, Double, Double) = (0, 0, 0); var n = 0.0
            for y in (ty * f)..<min(height, ty * f + f) { for x in (tx * f)..<min(width, tx * f + f) { let i = 3 * (y * width + x); acc.0 += Double(rgb[i]); acc.1 += Double(rgb[i + 1]); acc.2 += Double(rgb[i + 2]); n += 1 } }
            let d = 3 * (ty * tw + tx); o[d] = Float(acc.0 / n); o[d + 1] = Float(acc.1 / n); o[d + 2] = Float(acc.2 / n)
        } }
        return FloatImage(width: tw, height: th, rgb: o)
    }
}
