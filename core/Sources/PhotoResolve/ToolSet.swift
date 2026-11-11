import Foundation
import CPhotoCore

/// Instrumentele de ton și culoare adaptate din GDC STYLE V3 (referințe: ComposedToolsV3, ExposureZoneModelV3; paritate verificată cu 1056 de vectori de aur pe 4 profile — StyleParityV2Tests). Neutre implicit; în amprentă doar când ≠ neutru.
/// Domenii (păstrate din algoritmul autoritar): Negru, Mijloc, Tonal Balance, Printer Lights, Channel Mix = liniar în gamutul familiei; LGG, Roți, CDL, Contrast/Pivot, Hue/HSV = cod log al familiei.
public struct ToolSet: Equatable, Codable {
    // Expunere + balans (liniar)
    public var black = 0.0, midtones = 0.0                                                     // negru ±0.5 · mijloc ±1 st
    public var shadowsTemp = 0.0, shadowsTint = 0.0, highlightsTemp = 0.0, highlightsTint = 0.0   // Tonal Balance: mired ±60 · Duv ±0.02
    public var printerMaster = 0.0, printerR = 0.0, printerG = 0.0, printerB = 0.0              // puncte ±50 (1 punct = 1/8 stop)
    public var cm: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]; public var cmKeep = false           // Channel Mix 3×3
    public var ebMix = 1.0
    // Ton (log)
    public var pivot = 0.0                                                                      // pivot contrast, stopuri față de gri 18% (±3)
    public var lift = 0.0, gamma = 1.0, gain = 1.0, shadowLimit = 0.0, highlightStart = 3.5
    public var wheels: [Double] = Array(repeating: 0, count: 12)                                // [umbre, mijloc, lumini] × [R, G, B, Master]
    public var slope: [Double] = [1, 1, 1], offset: [Double] = [0, 0, 0], power: [Double] = [1, 1, 1]; public var cdlSat = 1.0
    public var toneMix = 1.0
    // Hue / HSV (log)
    public var hueRotate = 0.0, hsvSat = 1.0, hsvVal = 1.0, shMix = 1.0
    // Hue Vectors (230): lățime ° + [roșu, galben, verde, cyan, albastru, magenta] × (nuanță °, saturație ×, luminanță ×) + Mix
    public var hvWidth = 60.0, hv: [Double] = [0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1], hvMix = 1.0
    // Color (selecție din culoare, OKLab/LogViaLinear) și Skin (aspect al pielii după culoare)
    public var colorOn = false
    public var colorHue = 250.0, colorC = 0.5, colorL = 0.0, colorRange = 0.25, colorSoft = 0.5, colorSatRange = 0.5, colorLumRange = 0.4, cHue = 0.0, cSat = 0.0, cDensity = 0.0, cLum = 0.0, cWarm = 0.0, cSkinProt = 0.0, cNeutralProt = 0.5, cAmount = 1.0
    public var skRange = 0.5, skShadows = 0.5, skEdge = 0.5, skEven = 0.0, skHue = 0.0, skWarm = 0.0, skTint = 0.0, skVivid = 0.0, skRich = 0.0, skBright = 0.0, skAmount = 1.0
    // Optics V3: difuzie (filtru, treaptă, cantitate) + bloom (prag, mărime, cantitate), liniar
    public var opFilter = 0.0, opStrength = 2.0, opDiffusion = 0.0, opThreshold = 2.5, opSize = 0.5, opBloom = 0.0, opMix = 1.0
    // Highlights + Gamut (log → liniar real → log; înaintea efectelor și a DRT-ului)
    public var hgPathAmount = 0.0, hgPathOnset = 3.0, hgGamutAmount = 0.0, hgGamutThreshold = 0.85, hgHlAmount = 0.0, hgHlKnee = 2.5, hgMix = 1.0
    public init() {}
    enum CodingKeys: String, CodingKey { case black, midtones, shadowsTemp, shadowsTint, highlightsTemp, highlightsTint, printerMaster, printerR, printerG, printerB, cm, cmKeep, ebMix, pivot, lift, gamma, gain, shadowLimit, highlightStart, wheels, slope, offset, power, cdlSat, toneMix, hueRotate, hsvSat, hsvVal, shMix, hvWidth, hv, hvMix, hgPathAmount, hgPathOnset, hgGamutAmount, hgGamutThreshold, hgHlAmount, hgHlKnee, hgMix, opFilter, opStrength, opDiffusion, opThreshold, opSize, opBloom, opMix, colorOn, colorHue, colorC, colorL, colorRange, colorSoft, colorSatRange, colorLumRange, cHue, cSat, cDensity, cLum, cWarm, cSkinProt, cNeutralProt, cAmount, skRange, skShadows, skEdge, skEven, skHue, skWarm, skTint, skVivid, skRich, skBright, skAmount }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self); var t = ToolSet()
        func v(_ k: CodingKeys, _ def: Double) -> Double { (try? c.decodeIfPresent(Double.self, forKey: k)) ?? def }
        func a(_ k: CodingKeys, _ def: [Double]) -> [Double] { if let x = try? c.decodeIfPresent([Double].self, forKey: k), x.count == def.count { return x }; return def }
        t.black = v(.black, 0); t.midtones = v(.midtones, 0); t.shadowsTemp = v(.shadowsTemp, 0); t.shadowsTint = v(.shadowsTint, 0); t.highlightsTemp = v(.highlightsTemp, 0); t.highlightsTint = v(.highlightsTint, 0)
        t.printerMaster = v(.printerMaster, 0); t.printerR = v(.printerR, 0); t.printerG = v(.printerG, 0); t.printerB = v(.printerB, 0); t.cm = a(.cm, t.cm); t.cmKeep = (try? c.decodeIfPresent(Bool.self, forKey: .cmKeep)) ?? false; t.ebMix = v(.ebMix, 1)
        t.pivot = v(.pivot, 0); t.lift = v(.lift, 0); t.gamma = v(.gamma, 1); t.gain = v(.gain, 1); t.shadowLimit = v(.shadowLimit, 0); t.highlightStart = v(.highlightStart, 3.5)
        t.wheels = a(.wheels, t.wheels); t.slope = a(.slope, t.slope); t.offset = a(.offset, t.offset); t.power = a(.power, t.power); t.cdlSat = v(.cdlSat, 1); t.toneMix = v(.toneMix, 1)
        t.hueRotate = v(.hueRotate, 0); t.hsvSat = v(.hsvSat, 1); t.hsvVal = v(.hsvVal, 1); t.shMix = v(.shMix, 1); t.hvWidth = v(.hvWidth, 60); t.hv = a(.hv, t.hv); t.hvMix = v(.hvMix, 1)
        t.opFilter = v(.opFilter, 0.0); t.opStrength = v(.opStrength, 2.0); t.opDiffusion = v(.opDiffusion, 0.0); t.opThreshold = v(.opThreshold, 2.5); t.opSize = v(.opSize, 0.5); t.opBloom = v(.opBloom, 0.0); t.opMix = v(.opMix, 1.0);
        t.colorOn = (try? c.decodeIfPresent(Bool.self, forKey: .colorOn)) ?? false; t.colorHue = v(.colorHue, 250.0); t.colorC = v(.colorC, 0.5); t.colorL = v(.colorL, 0.0); t.colorRange = v(.colorRange, 0.25); t.colorSoft = v(.colorSoft, 0.5); t.colorSatRange = v(.colorSatRange, 0.5); t.colorLumRange = v(.colorLumRange, 0.4); t.cHue = v(.cHue, 0.0); t.cSat = v(.cSat, 0.0); t.cDensity = v(.cDensity, 0.0); t.cLum = v(.cLum, 0.0); t.cWarm = v(.cWarm, 0.0); t.cSkinProt = v(.cSkinProt, 0.0); t.cNeutralProt = v(.cNeutralProt, 0.5); t.cAmount = v(.cAmount, 1.0); t.skRange = v(.skRange, 0.5); t.skShadows = v(.skShadows, 0.5); t.skEdge = v(.skEdge, 0.5); t.skEven = v(.skEven, 0.0); t.skHue = v(.skHue, 0.0); t.skWarm = v(.skWarm, 0.0); t.skTint = v(.skTint, 0.0); t.skVivid = v(.skVivid, 0.0); t.skRich = v(.skRich, 0.0); t.skBright = v(.skBright, 0.0); t.skAmount = v(.skAmount, 1.0);
        t.hgPathAmount = v(.hgPathAmount, 0); t.hgPathOnset = v(.hgPathOnset, 3); t.hgGamutAmount = v(.hgGamutAmount, 0); t.hgGamutThreshold = v(.hgGamutThreshold, 0.85); t.hgHlAmount = v(.hgHlAmount, 0); t.hgHlKnee = v(.hgHlKnee, 2.5); t.hgMix = v(.hgMix, 1); self = t
    }
    /// Grupuri = module activabile / secțiuni cu reset (valorile se păstrează când modulul e oprit).
    public enum Group: String, CaseIterable { case black, midtones, tonalBalance, printer, channelMix, wheels, pivot, hue, hueVectors, highlights, color, skin, diffusion
        public var module: String { switch self { case .black: return "exposure"; case .midtones, .pivot: return "light"; case .tonalBalance: return "tonalbalance"; case .printer: return "printer"; case .channelMix: return "channelmix"; case .wheels: return "wheels"; case .hue: return "colour"; case .hueVectors: return "huevectors"; case .highlights: return "highlights"; case .color: return "color"; case .skin: return "skin"; case .diffusion: return "diffusion" } } }
    public func isNeutral(_ g: Group) -> Bool { let n = ToolSet()
        switch g {
        case .black: return black == 0
        case .midtones: return midtones == 0
        case .tonalBalance: return shadowsTemp == 0 && shadowsTint == 0 && highlightsTemp == 0 && highlightsTint == 0
        case .printer: return printerMaster == 0 && printerR == 0 && printerG == 0 && printerB == 0
        case .channelMix: return cm == n.cm && !cmKeep
        case .wheels: return lift == 0 && gamma == 1 && gain == 1 && shadowLimit == 0 && highlightStart == 3.5 && wheels == n.wheels && slope == n.slope && offset == n.offset && power == n.power && cdlSat == 1 && toneMix == 1
        case .pivot: return pivot == 0
        case .hue: return hueRotate == 0 && hsvSat == 1 && hsvVal == 1 && shMix == 1
        case .hueVectors: return hv == n.hv && hvWidth == 60 && hvMix == 1
        case .color: return !colorOn && colorHue == 250.0 && colorC == 0.5 && colorL == 0.0 && colorRange == 0.25 && colorSoft == 0.5 && colorSatRange == 0.5 && colorLumRange == 0.4 && cHue == 0.0 && cSat == 0.0 && cDensity == 0.0 && cLum == 0.0 && cWarm == 0.0 && cSkinProt == 0.0 && cNeutralProt == 0.5 && cAmount == 1.0
        case .diffusion: return opFilter == 0.0 && opStrength == 2.0 && opDiffusion == 0.0 && opThreshold == 2.5 && opSize == 0.5 && opBloom == 0.0 && opMix == 1.0
        case .skin: return skRange == 0.5 && skShadows == 0.5 && skEdge == 0.5 && skEven == 0.0 && skHue == 0.0 && skWarm == 0.0 && skTint == 0.0 && skVivid == 0.0 && skRich == 0.0 && skBright == 0.0 && skAmount == 1.0
        case .highlights: return hgPathAmount == 0 && hgPathOnset == 3 && hgGamutAmount == 0 && hgGamutThreshold == 0.85 && hgHlAmount == 0 && hgHlKnee == 2.5 && hgMix == 1 } }
    public mutating func reset(_ g: Group) { let n = ToolSet()
        switch g {
        case .black: black = 0
        case .midtones: midtones = 0
        case .tonalBalance: shadowsTemp = 0; shadowsTint = 0; highlightsTemp = 0; highlightsTint = 0
        case .printer: printerMaster = 0; printerR = 0; printerG = 0; printerB = 0
        case .channelMix: cm = n.cm; cmKeep = false
        case .wheels: lift = 0; gamma = 1; gain = 1; shadowLimit = 0; highlightStart = 3.5; wheels = n.wheels; slope = n.slope; offset = n.offset; power = n.power; cdlSat = 1; toneMix = 1
        case .pivot: pivot = 0
        case .hue: hueRotate = 0; hsvSat = 1; hsvVal = 1; shMix = 1
        case .hueVectors: hv = n.hv; hvWidth = 60; hvMix = 1
        case .color: colorOn = false; colorHue = 250.0; colorC = 0.5; colorL = 0.0; colorRange = 0.25; colorSoft = 0.5; colorSatRange = 0.5; colorLumRange = 0.4; cHue = 0.0; cSat = 0.0; cDensity = 0.0; cLum = 0.0; cWarm = 0.0; cSkinProt = 0.0; cNeutralProt = 0.5; cAmount = 1.0
        case .diffusion: opFilter = 0.0; opStrength = 2.0; opDiffusion = 0.0; opThreshold = 2.5; opSize = 0.5; opBloom = 0.0; opMix = 1.0
        case .skin: skRange = 0.5; skShadows = 0.5; skEdge = 0.5; skEven = 0.0; skHue = 0.0; skWarm = 0.0; skTint = 0.0; skVivid = 0.0; skRich = 0.0; skBright = 0.0; skAmount = 1.0
        case .highlights: hgPathAmount = 0; hgPathOnset = 3; hgGamutAmount = 0; hgGamutThreshold = 0.85; hgHlAmount = 0; hgHlKnee = 2.5; hgMix = 1 } }
    public var isNeutral: Bool { self == ToolSet() }
    public var fingerprint: String {
        func f(_ v: Double) -> String { String(format: "%.5f", v) }
        var p: [String] = []
        for g in Group.allCases where !isNeutral(g) {
            switch g {
            case .black: p.append("bk:" + f(black)); case .midtones: p.append("mi:" + f(midtones)); case .pivot: p.append("pv:" + f(pivot))
            case .tonalBalance: p.append("tb:" + [shadowsTemp, shadowsTint, highlightsTemp, highlightsTint].map(f).joined(separator: ","))
            case .printer: p.append("pr:" + [printerMaster, printerR, printerG, printerB].map(f).joined(separator: ","))
            case .channelMix: p.append("cm:" + cm.map(f).joined(separator: ",") + (cmKeep ? "k" : ""))
            case .wheels: p.append("wh:" + ([lift, gamma, gain, shadowLimit, highlightStart, cdlSat, toneMix] + wheels + slope + offset + power).map(f).joined(separator: ","))
            case .hue: p.append("hu:" + [hueRotate, hsvSat, hsvVal, shMix].map(f).joined(separator: ","))
            case .hueVectors: p.append("hv:" + ([hvWidth, hvMix] + hv).map(f).joined(separator: ","))
            case .color: p.append("co:\(colorOn)," + [colorHue, colorC, colorL, colorRange, colorSoft, colorSatRange, colorLumRange, cHue, cSat, cDensity, cLum, cWarm, cSkinProt, cNeutralProt, cAmount].map(f).joined(separator: ","))
            case .diffusion: p.append("op:" + [opFilter, opStrength, opDiffusion, opThreshold, opSize, opBloom, opMix].map(f).joined(separator: ","))
            case .skin: p.append("sk:" + [skRange, skShadows, skEdge, skEven, skHue, skWarm, skTint, skVivid, skRich, skBright, skAmount].map(f).joined(separator: ","))
            case .highlights: p.append("hg:" + [hgPathAmount, hgPathOnset, hgGamutAmount, hgGamutThreshold, hgHlAmount, hgHlKnee, hgMix].map(f).joined(separator: ",")) } }
        if ebMix != 1 { p.append("em:" + f(ebMix)) }
        return p.joined(separator: ";")
    }
    public func apply(to p: inout pc_params) {
        p.black = black; p.midtones = midtones; p.shadowsTemp = shadowsTemp; p.shadowsTint = shadowsTint; p.highlightsTemp = highlightsTemp; p.highlightsTint = highlightsTint
        p.printerMaster = printerMaster; p.printerR = printerR; p.printerG = printerG; p.printerB = printerB; p.cmKeepNeutrals = cmKeep ? 1 : 0; p.ebMix = ebMix; p.pivot = pivot
        p.lift = lift; p.gamma = gamma; p.gain = gain; p.shadowLimit = shadowLimit; p.highlightStart = highlightStart; p.cdlSat = cdlSat; p.toneMix = toneMix
        p.hueRotate = hueRotate; p.hsvSat = hsvSat; p.hsvVal = hsvVal; p.shMix = shMix; p.hvWidth = hvWidth; p.hvMix = hvMix
        p.opFilter = opFilter; p.opStrength = opStrength; p.opDiffusion = opDiffusion; p.opThreshold = opThreshold; p.opSize = opSize; p.opBloom = opBloom; p.opMix = opMix
        p.colorActive = colorOn ? 1 : 0; p.colorHue = colorHue; p.colorC = colorC; p.colorL = colorL; p.colorRange = colorRange; p.colorSoft = colorSoft; p.colorSatRange = colorSatRange; p.colorLumRange = colorLumRange; p.cHue = cHue; p.cSat = cSat; p.cDensity = cDensity; p.cLum = cLum; p.cWarm = cWarm; p.cSkinProt = cSkinProt; p.cNeutralProt = cNeutralProt; p.cAmount = cAmount; p.skRange = skRange; p.skShadows = skShadows; p.skEdge = skEdge; p.skEven = skEven; p.skHue = skHue; p.skWarm = skWarm; p.skTint = skTint; p.skVivid = skVivid; p.skRich = skRich; p.skBright = skBright; p.skAmount = skAmount;
        p.hgPathAmount = hgPathAmount; p.hgPathOnset = hgPathOnset; p.hgGamutAmount = hgGamutAmount; p.hgGamutThreshold = hgGamutThreshold; p.hgHlAmount = hgHlAmount; p.hgHlKnee = hgHlKnee; p.hgMix = hgMix
        func put(_ raw: UnsafeMutableRawBufferPointer, _ a: [Double]) { for i in 0..<a.count { raw.storeBytes(of: a[i], toByteOffset: i * 8, as: Double.self) } }
        withUnsafeMutableBytes(of: &p.cm) { put($0, cm) }; withUnsafeMutableBytes(of: &p.hv) { put($0, hv) }; withUnsafeMutableBytes(of: &p.wheels) { put($0, wheels) }
        withUnsafeMutableBytes(of: &p.slope) { put($0, slope) }; withUnsafeMutableBytes(of: &p.offset) { put($0, offset) }; withUnsafeMutableBytes(of: &p.power) { put($0, power) }
    }
}
