import Foundation
import PhotoCore

/// Copiere / lipire / sincronizare de reglaje pe CATEGORII, cu sursă explicită. Implicit NU se copiază geometria (crop/rotire), măștile/corecțiile locale, corecția de chart și corecțiile de lentilă (specifice cadrului/camerei/luminii).
public enum AdjustmentCategory: String, CaseIterable, Codable {
    case basic, toneColour, selective, look, effects, filmCinema, lens, geometry, locals, chart
    public var label: String { switch self {
        case .basic: return L("Bază: expunere, lumină, culoare, HSV"); case .toneColour: return L("Tonuri și culoare avansate (balans tonal, printer, mixer, roți/CDL, vectori de nuanță, lumini și gamă)")
        case .selective: return L("Culoare selectivă și Piele"); case .look: return L("Look (caracter)"); case .effects: return L("Efecte: difuzie, aspect pelicular simplu, grăunte simplu, vinietă creativă")
        case .filmCinema: return L("Film (fotochimic) și Stiluri cinema"); case .lens: return L("Corecții de lentilă (distorsiune, aberație, vinietă de obiectiv) — specifice camerei")
        case .geometry: return L("Geometrie și decupare — specifice cadrului"); case .locals: return L("Corecții locale / măști — specifice cadrului"); case .chart: return L("Corecție după chart — specifică camerei și luminii") } }
    public var defaultOn: Bool { switch self { case .lens, .geometry, .locals, .chart: return false; default: return true } }
    static let toolKeys: [ToolSet.Group: [String]] = [
        .black: ["black"], .midtones: ["midtones"], .pivot: ["pivot"], .hue: ["hueRotate", "hsvSat", "hsvVal", "shMix"],
        .tonalBalance: ["shadowsTemp", "shadowsTint", "highlightsTemp", "highlightsTint"], .printer: ["printerMaster", "printerR", "printerG", "printerB"], .channelMix: ["cm", "cmKeep", "ebMix"],
        .wheels: ["lift", "gamma", "gain", "shadowLimit", "highlightStart", "wheels", "slope", "offset", "power", "cdlSat", "toneMix"], .hueVectors: ["hvWidth", "hv", "hvMix"],
        .highlights: ["hgPathAmount", "hgPathOnset", "hgGamutAmount", "hgGamutThreshold", "hgHlAmount", "hgHlKnee", "hgMix"],
        .color: ["colorOn", "colorHue", "colorC", "colorL", "colorRange", "colorSoft", "colorSatRange", "colorLumRange", "cHue", "cSat", "cDensity", "cLum", "cWarm", "cSkinProt", "cNeutralProt", "cAmount"],
        .skin: ["skRange", "skShadows", "skEdge", "skEven", "skHue", "skWarm", "skTint", "skVivid", "skRich", "skBright", "skAmount"], .diffusion: ["opFilter", "opStrength", "opDiffusion", "opThreshold", "opSize", "opBloom", "opMix"]]
    static func groups(_ c: AdjustmentCategory) -> [ToolSet.Group] { switch c {
        case .basic: return [.black, .midtones, .pivot, .hue]; case .toneColour: return [.tonalBalance, .printer, .channelMix, .wheels, .hueVectors, .highlights]
        case .selective: return [.color, .skin]; case .effects: return [.diffusion]; default: return [] } }
}

public extension AdjustmentSet {
    /// Rezultatul lipirii: `base` (reglajele țintei) cu categoriile alese înlocuite din `self` (sursa). Restul (inclusiv geometria, măștile, chart-ul, familia, DRT, modulele dezactivate ale țintei) rămân ale țintei.
    func pasting(_ cats: Set<AdjustmentCategory>, onto base: AdjustmentSet) -> AdjustmentSet {
        var r = base
        if cats.contains(.basic) { r.exposure = exposure; r.exposureAuto = exposureAuto; r.autoOffset = autoOffset; r.temperature = temperature; r.tint = tint; r.shadows = shadows; r.highlights = highlights; r.contrast = contrast; r.saturation = saturation }
        var keys = Set<String>(); for c in cats { for g in AdjustmentCategory.groups(c) { keys.formUnion(AdjustmentCategory.toolKeys[g] ?? []) } }
        if !keys.isEmpty, let s = (try? JSONEncoder().encode(tools)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
           var t = (try? JSONEncoder().encode(r.tools)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) {
            for k in keys { if let v = s[k] { t[k] = v } else { t.removeValue(forKey: k) } }
            if let d = try? JSONSerialization.data(withJSONObject: t), let nt = try? JSONDecoder().decode(ToolSet.self, from: d) { r.tools = nt } }
        if cats.contains(.look) { r.look = look }
        if cats.contains(.effects) { r.detail = detail }
        if cats.contains(.effects) { let f = r.effects.film3, c = r.effects.cinema; var e = effects; e.film3 = f; e.cinema = c; e.distortion = r.effects.distortion; e.caRed = r.effects.caRed; e.caBlue = r.effects.caBlue; e.lensVignette = r.effects.lensVignette; r.effects = e }
        if cats.contains(.filmCinema) { r.effects.film3 = effects.film3; r.effects.cinema = effects.cinema }
        if cats.contains(.lens) { r.effects.distortion = effects.distortion; r.effects.caRed = effects.caRed; r.effects.caBlue = effects.caBlue; r.effects.lensVignette = effects.lensVignette }
        if cats.contains(.geometry) { r.geometry = geometry }
        if cats.contains(.locals) { r.locals = locals; r.retouch = retouch }
        if cats.contains(.chart) { r.chart = chart }
        return r
    }
}
