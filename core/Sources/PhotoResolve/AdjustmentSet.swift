import Foundation
import PhotoCore

/// Familia de lucru (inventar GDC STYLE `workingSpaceProfiles`): gamut + codificare log, coerente cap-coadă (RAW → liniar în gamutul familiei → instrumente liniare → cod log → instrumente creative → adaptor DRT → sRGB).
/// RAW-ul camerei, familia internă și ieșirea sRGB sunt trei lucruri distincte. DWG/DaVinci Intermediate = implicit și rezervă.
public enum WorkingFamily: Int, Codable, CaseIterable {
    case dwg = 0, acesAP1 = 1, awg3 = 2, awg4 = 3
    public var id: String { ["dwg-davinci-intermediate", "ap1-acescct", "awg3-logc3-ei800", "awg4-logc4"][rawValue] }
    public var label: String { ["DaVinci Wide Gamut · DaVinci Intermediate", "ACES AP1 · ACEScct", "ARRI Wide Gamut 3 · LogC3 (EI 800)", "ARRI Wide Gamut 4 · LogC4"][rawValue] }
    public var shortLabel: String { ["DaVinci", "ACES", "ARRI LogC3", "ARRI LogC4"][rawValue] }
    public var explanation: String {
        switch self {
        case .dwg: return L("Implicit și rezervă: gamut DaVinci Wide Gamut, codificare DaVinci Intermediate (lanțul verificat în Resolve).")
        case .acesAP1: return L("Gamut ACES AP1 (alb D60), codificare ACEScct. Aceleași instrumente, ancorate în familia ACES.")
        case .awg3: return L("Gamut ARRI Wide Gamut 3, codificare LogC3 la EI 800: contrastul și saturația lucrează pe codul LogC3.")
        case .awg4: return L("Gamut ARRI Wide Gamut 4, codificare LogC4: contrastul și saturația lucrează pe codul LogC4.")
        }
    }
    /// Numărul de ordine din nucleu (`pc_params.family`).
    public var coreIndex: Int32 { Int32(rawValue) }
}

/// Dezvoltarea RAW a fotografiei, SEPARATĂ de reglajele creative (nu intră în «neutru»; vezi `docs/RAW_DEVELOPMENT.md`).
/// `baseline`: compensarea dezvoltării în EV, aplicată de decodor ca câștig liniar înaintea oricărui reglaj. `off` = 0 (implicit, și pentru fotografii noi: semnificația metadatei nu e confirmată oficial), `camera` = valoarea declarată de cameră (Fuji: −RawExposureBias; fără valoare ⇒ 0), `manual` = `manualEV`.
/// `decodeRevision`: 1 = dezvoltare RAW veche (înainte de 2026-10-23: negru pe model de pixeli ignorat, crop forțat 3:2); 2 = corectată. Reglajele salvate fără această cheie sunt tratate ca revizia 1 cu `baseline = off`
/// (aspectul lor NU se schimbă în tăcere); fotografiile noi încep pe revizia 2 cu compensarea `off` (alegere explicită a fotografului). Trecerea 1 → 2 e o acțiune explicită și reversibilă a fotografului.
public struct RawDevelopment: Codable, Equatable {
    public enum Baseline: String, Codable { case camera, off, manual }
    public var baseline: Baseline = .off
    public var manualEV: Double = 0
    public var decodeRevision = 2
    public static let currentDecodeRevision = 2
    public static let manualRange: ClosedRange<Double> = -4...4
    public init() {}
    public init(baseline: Baseline, manualEV: Double, decodeRevision: Int) { self.baseline = baseline; self.manualEV = manualEV; self.decodeRevision = decodeRevision }
    public static var legacy: RawDevelopment { RawDevelopment(baseline: .off, manualEV: 0, decodeRevision: 1) }
    public var isLegacyDecode: Bool { decodeRevision < RawDevelopment.currentDecodeRevision }
    /// EV aplicat efectiv, din valoarea camerei (dacă există): `camera` ⇒ −shift (RAW mai întunecat cu |shift| EV decât redarea camerei ⇒ se ridică cu |shift|).
    public func appliedEV(cameraShift: Double?) -> Double {
        switch baseline { case .off: return 0; case .manual: return max(RawDevelopment.manualRange.lowerBound, min(RawDevelopment.manualRange.upperBound, manualEV)); case .camera: return -(cameraShift ?? 0) }
    }
    var fingerprintPart: String { self == RawDevelopment() ? "" : "|raw:\(baseline.rawValue),\(String(format: "%.3f", manualEV)),r\(decodeRevision)" }
}

/// Reglajele unei fotografii, ca parametri expliciți (nu LUT/CDL). Valorile implicite sunt neutre. Mapare provizorie pe modulele GDC STYLE instalate (stand-in de dezvoltare)
/// până la existența OFX-ului fotografic propriu; numele de control sunt cele din catalogul STYLE (`gdc-style-ai catalog`), intervalurile UI sunt mai înguste decât ale modulelor.
public struct AdjustmentSet: Codable, Equatable {
    public var exposure: Double = 0        // stopuri (v3eExposure, −10…10; UI −4…8) — alegerea creativă MANUALĂ
    /// Mod automat explicit: expunerea efectivă = estimarea statistică a fotografiei + `autoOffset` (corecția creativă). Implicit oprit; estimarea e orientativă și nevalidată.
    public var exposureAuto = false
    public var autoOffset: Double = 0      // stopuri, relativ la estimare (doar în modul automat)
    public var temperature: Double = 0     // mired (v3eTemp, −150…150)
    public var tint: Double = 0            // verde/magenta (v3eTint, −0.05…0.05)
    public var shadows: Double = 0         // stopuri (v3eShadows, −2…2)
    public var highlights: Double = 0      // stopuri (v3eHighlights, −2…2)
    public var contrast: Double = 1        // v3tContrast 0…3 (domeniul log, pivot 0)
    public var saturation: Double = 1      // v3hSat 0…2
    /// Corecții locale (zonă manuală + reglaje), doar pentru motorul propriu. Ordinea = ordinea aplicării.
    public var locals: [LocalCorrection] = []
    /// Revizia motorului de calcul sub care au fost SALVATE reglajele (0 = înainte de revizia 3: dev.4 și mai vechi). Valorile rămân ale fotografului; ASPECTUL lor s-a schimbat odată cu corectarea matematicii (revizia 3, 2026-10-21).
    public var engineRevision: Int = 0
    public static let currentEngineRevision = 3
    /// Familia de lucru (implicit DWG). Se salvează cu reglajele; intră în amprentă DOAR când ≠ DWG (reglajele existente rămân identice ca amprentă și ca aspect).
    public var family: WorkingFamily = .dwg
    /// Module de procesare scoase TEMPORAR din lanț (valorile se păstrează; reactivarea le recuperează exact). Doar instrumentele de reglaj: exposure, light, colour, geometry. DRT-ul, conversiile și familia NU au bypass (ar face lanțul incompatibil).
    public var disabledModules: Set<String> = []
    /// Decupare și geometrie nedistructive (neutru implicit; în amprentă doar când ≠ neutru).
    public var geometry = Geometry()
    /// Efecte fotografice (Optică, Peliculă, Grain): neutre implicit, în amprentă doar când ≠ neutru.
    public var effects = Effects()
    /// Instrumentele de ton/culoare adaptate din STYLE V3 (negru, mijloc, Tonal Balance, Printer Lights, Channel Mix, pivot, LGG/Roți/CDL, Hue/HSV).
    public var tools = ToolSet()
    /// Profilul GDC DRT (0 Natural · 1 Asiatic · 2 Cinema Print; paritate verificată pe cele 3 în GDCDRTTests). Alegere de REDARE a ieșirii (ca familia): nu intră în «neutru»; intră în amprentă doar când ≠ Natural.
    public var drtProfile = 0
    /// Corecție TEHNICĂ după chart (ColorChecker): matrice în DWG liniar la intrarea lanțului; distinctă de profilul personal și de efecte; nu e reglaj creativ (nu intră în «neutru»).
    public var chart: ChartCorrection?
    /// Look (FIELD): caracter artistic în cod log; oprit implicit.
    public var look = LookSettings()
    /// Detalii (claritate + accentuare) pe imaginea finală; neutru implicit.
    public var detail = DetailSettings()
    /// Retuș punctual (clone/heal), în coordonatele sursei; gol implicit.
    public var retouch: [RetouchSpot] = []
    /// Dezvoltarea RAW (compensare + revizia decodării); distinctă de reglajele creative.
    public var rawDev = RawDevelopment()
    public var styleID: String? = nil      // informativ: presetul din care a pornit (valorile de mai sus sunt cele reale)
    public init() {}
    enum CodingKeys: String, CodingKey { case rawDev, exposure, exposureAuto, autoOffset, temperature, tint, shadows, highlights, contrast, saturation, styleID, locals, engineRevision, family, geometry, effects, tools, drtProfile, chart, disabledModules, look, detail, retouch }
    public init(from d: Decoder) throws {   // chei lipsă (JSON salvat de versiuni mai vechi) → valori implicite neutre
        let c = try d.container(keyedBy: CodingKeys.self)
        rawDev = (try? c.decodeIfPresent(RawDevelopment.self, forKey: .rawDev)) ?? RawDevelopment.legacy   // lipsă ⇒ salvat înainte de revizia 2 a dezvoltării RAW: aspect neschimbat
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0; exposureAuto = try c.decodeIfPresent(Bool.self, forKey: .exposureAuto) ?? false; autoOffset = try c.decodeIfPresent(Double.self, forKey: .autoOffset) ?? 0
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0; tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0; highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 1; saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1; styleID = try c.decodeIfPresent(String.self, forKey: .styleID); locals = try c.decodeIfPresent([LocalCorrection].self, forKey: .locals) ?? []; engineRevision = try c.decodeIfPresent(Int.self, forKey: .engineRevision) ?? 0
        geometry = (try? c.decodeIfPresent(Geometry.self, forKey: .geometry)) ?? Geometry()
        effects = (try? c.decodeIfPresent(Effects.self, forKey: .effects)) ?? Effects()
        tools = (try? c.decodeIfPresent(ToolSet.self, forKey: .tools)) ?? ToolSet()
        chart = (try? c.decodeIfPresent(ChartCorrection.self, forKey: .chart)) ?? nil
        drtProfile = min(2, max(0, (try? c.decodeIfPresent(Int.self, forKey: .drtProfile)) ?? 0))
        disabledModules = (try? c.decodeIfPresent(Set<String>.self, forKey: .disabledModules)) ?? []
        look = (try? c.decodeIfPresent(LookSettings.self, forKey: .look)) ?? LookSettings()
        detail = (try? c.decodeIfPresent(DetailSettings.self, forKey: .detail)) ?? DetailSettings()
        retouch = (try? c.decodeIfPresent([RetouchSpot].self, forKey: .retouch)) ?? []
        family = (try? c.decodeIfPresent(WorkingFamily.self, forKey: .family)) ?? .dwg   // familie necunoscută/lipsă → DWG (rezerva declarată)
    }

    public static let ranges: [String: ClosedRange<Double>] = ["exposure": -4...8, "temperature": -150...150, "tint": -0.05...0.05, "shadows": -2...2, "highlights": -2...2, "contrast": 0.5...2, "saturation": 0...2]
    /// Expunerea trimisă lanțului: manuală, sau estimare + corecție în modul automat (fără estimare disponibilă, estimarea se ia 0 și lanțul NU pretinde automatizare).
    public func effectiveExposure(estimate: Double?) -> Double { exposureAuto ? (estimate ?? 0) + autoOffset : exposure }
    /// Reglaje salvate sub o revizie mai veche a motorului și care chiar modifică imaginea ⇒ aspectul diferă de cel văzut atunci.
    public var isFromOlderEngine: Bool { engineRevision < AdjustmentSet.currentEngineRevision && !isNeutral }
    /// Grupuri de reglaje pentru resetarea pe SECȚIUNE (aceleași grupuri ca în interfață).
    public var exposureGroupIsNeutral: Bool { exposure == 0 && !exposureAuto && autoOffset == 0 }
    public var lightGroupIsNeutral: Bool { shadows == 0 && highlights == 0 && contrast == 1 }
    public var colourGroupIsNeutral: Bool { temperature == 0 && tint == 0 && saturation == 1 }
    public mutating func resetExposureGroup() { exposure = 0; exposureAuto = false; autoOffset = 0 }
    public mutating func resetLightGroup() { shadows = 0; highlights = 0; contrast = 1 }
    public mutating func resetColourGroup() { temperature = 0; tint = 0; saturation = 1 }
    /// Neutru = nicio valoare creativă schimbată (familia de lucru NU e o reglare creativă: schimbă domeniul instrumentelor, nu imaginea cerută).
    public var isNeutral: Bool { var c = self.withoutStyle; c.geometry = Geometry(); c.drtProfile = 0; c.chart = nil; return c == AdjustmentSet.neutral(family) }   // valorile creative; geometria e separată (isGeometryNeutral)
    /// Reglajele EFECTIVE: modulele dezactivate sunt neutre (valorile rămân în `self`). Procesarea, amprenta de randare și predarea în Resolve folosesc această vedere.
    public var effective: AdjustmentSet {
        guard !disabledModules.isEmpty else { return self }; var a = self
        if disabledModules.contains("exposure") { a.exposure = 0; a.exposureAuto = false; a.autoOffset = 0 }
        if disabledModules.contains("light") { a.shadows = 0; a.highlights = 0; a.contrast = 1 }
        if disabledModules.contains("colour") { a.temperature = 0; a.tint = 0; a.saturation = 1 }
        if disabledModules.contains("geometry") { a.geometry = Geometry() }
        for g in ToolSet.Group.allCases where disabledModules.contains(g.module) { a.tools.reset(g) }
        if disabledModules.contains("chart") { a.chart = nil }
        if disabledModules.contains("look") { a.look.on = false }
        if disabledModules.contains("detail") { a.detail = DetailSettings() }
        if disabledModules.contains("retouch") { a.retouch = [] }
        if disabledModules.contains("optics") { a.effects.resetOptics() }
        if disabledModules.contains("film") { a.effects.resetFilm() }
        if disabledModules.contains("grain") { a.effects.resetGrain() }
        if disabledModules.contains("film3") { a.effects.film3.on = false }
        if disabledModules.contains("cinema") { a.effects.cinema.on = false }
        return a
    }
    public func isModuleEnabled(_ id: String) -> Bool { !disabledModules.contains(id) }
    /// Modulele OPȚIONALE (efecte, instrumente creative, retuș, detalii, look, chart): pornesc DEZACTIVATE pentru fotografiile noi (D-WS-2). Modulele tehnice/de bază (exposure, light, colour, geometry) rămân active.
    public static let optionalModules: [String] = ["tonalbalance", "printer", "channelmix", "wheels", "huevectors", "highlights", "color", "skin", "diffusion",
                                                   "look", "detail", "retouch", "optics", "film", "grain", "film3", "cinema", "chart"]
    /// Starea unei fotografii fără reglaje salvate: valori neutre, modulele opționale dezactivate (valorile se păstrează la activare/dezactivare). `isNeutral` o consideră neutră.
    public static func fresh(_ family: WorkingFamily) -> AdjustmentSet { var a = neutral(family); a.disabledModules = Set(optionalModules); return a }
    /// Valorile proprii ale unui modul opțional, serializate (comparabile); `nil` = id necunoscut.
    func moduleValue(_ id: String) -> String? {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        func j<T: Encodable>(_ v: T) -> String? { (try? enc.encode(v)).flatMap { String(data: $0, encoding: .utf8) } }
        func fx(keeping k: String) -> Effects {
            var e = effects
            if k != "optics" { e.resetOptics() }; if k != "film" { e.resetFilm() }; if k != "grain" { e.resetGrain() }
            if k != "film3" { e.film3 = Film3() }; if k != "cinema" { e.cinema = CinemaStyle() }
            return e
        }
        switch id {
        case "look": return j(look)
        case "detail": return j(detail)
        case "retouch": return j(retouch)
        case "chart": return j(chart)
        case "optics", "film", "grain", "film3", "cinema": return j(fx(keeping: id))
        default:
            guard AdjustmentSet.optionalModules.contains(id) else { return nil }
            var t = tools; for g in ToolSet.Group.allCases where g.module != id { t.reset(g) }; return j(t)
        }
    }
    /// Modulele opționale DEZACTIVATE (și înainte, și acum) ale căror valori proprii s-au schimbat față de `old`: o modificare deliberată le activează.
    public func modulesToActivate(from old: AdjustmentSet) -> [String] {
        AdjustmentSet.optionalModules.filter { disabledModules.contains($0) && old.disabledModules.contains($0) && moduleValue($0) != old.moduleValue($0) }
    }
    public var isGeometryNeutral: Bool { geometry.isNeutral }
    /// Baza comparației: aceeași familie și ACEEAȘI geometrie, fără reglaje creative (Bază/După compară doar reglajele, nu cadrul).
    public var baseForCompare: AdjustmentSet { var a = AdjustmentSet.neutral(family); a.drtProfile = drtProfile; a.rawDev = rawDev; a.chart = chart; a.geometry = geometry; a.effects.distortion = effects.distortion; a.effects.caRed = effects.caRed; a.effects.caBlue = effects.caBlue; return a }
    public static func neutral(_ family: WorkingFamily) -> AdjustmentSet { var a = AdjustmentSet(); a.family = family; return a }
    var withoutStyle: AdjustmentSet { var c = self; c.rawDev = RawDevelopment(); c.styleID = nil; c.engineRevision = 0; c.disabledModules = []; return c }

    /// Modulele dezactivate care chiar schimbă ceva: un modul opțional oprit cu valori neutre nu intră în amprentă (fotografia nouă = aceeași amprentă ca neutrul).
    var offModules: [String] {
        let n = AdjustmentSet.neutral(family)
        return disabledModules.sorted().filter { !AdjustmentSet.optionalModules.contains($0) || moduleValue($0) != n.moduleValue($0) }
    }

    /// Amprentă stabilă (pentru cache): doar valorile care influențează randarea.
    public var fingerprint: String {
        func f(_ v: Double) -> String { String(format: "%.5f", v) }
        let e = exposureAuto ? "auto(\(f(autoOffset)),v\(ExposureEstimatorVersion.current))" : f(exposure)
        let base = ([e] + [temperature, tint, shadows, highlights, contrast, saturation].map(f)).joined(separator: "|")
        let fam = (family == .dwg ? "" : "|fam:\(family.id)") + rawDev.fingerprintPart
        return (locals.isEmpty ? base : base + "|L:" + locals.map { $0.fingerprint }.joined(separator: ";")) + fam + (geometry.isNeutral ? "" : "|" + geometry.fingerprint) + (effects.isNeutral ? "" : "|fx:" + effects.fingerprint) + (tools.isNeutral ? "" : "|tl:" + tools.fingerprint) + (look.on ? "|" + look.fingerprint : "") + (detail.isNeutral ? "" : "|" + detail.fingerprint) + (retouch.contains { $0.enabled } ? "|rt:" + retouch.filter { $0.enabled }.map { $0.fingerprint }.joined(separator: ";") : "") + (drtProfile == 0 ? "" : "|drt:\(drtProfile)") + ((chart == nil || chart!.isIdentity) ? "" : "|chart:" + chart!.matrix.map { String(format: "%.6f", $0) }.joined(separator: ",")) + (offModules.isEmpty ? "" : "|off:" + offModules.joined(separator: ","))
    }

    /// Lanțul GDC: Input Transform (DWG/DI) → [Exposure+Balance] → Linear to Log → [Tone] → [Saturation+Hue] → DRT (sRGB). Etapele neutre sunt omise (identitate demonstrată pe etapele de bază).
    public func chain(estimate: Double? = nil) -> [ChainStage] {
        var c: [ChainStage] = [ChainStage(stage: "input_transform", params: ["v3itCamera": 9])]
        var lin: [String: Double] = [:]
        let ex = effectiveExposure(estimate: estimate)
        if ex != 0 { lin["v3eExposure"] = ex }
        if temperature != 0 { lin["v3eTemp"] = temperature }
        if tint != 0 { lin["v3eTint"] = tint }
        if shadows != 0 { lin["v3eShadows"] = shadows }
        if highlights != 0 { lin["v3eHighlights"] = highlights }
        if !lin.isEmpty { c.append(ChainStage(stage: "exposure_balance", params: lin)) }
        c.append(ChainStage(stage: "linear_to_log", params: [:]))
        if contrast != 1 { c.append(ChainStage(stage: "tone", params: ["v3tContrast": contrast])) }
        if saturation != 1 { c.append(ChainStage(stage: "saturation_hue", params: ["v3hSat": saturation])) }
        c.append(ChainStage(stage: "drt", params: ["v3dOutput": 2]))
        return c
    }
}

public struct ChainStage: Codable, Equatable { public var stage: String; public var params: [String: Double] }

/// Presetări de stil = seturi explicite de parametri (Natural / Intens / Catifelat, valorile din conceptul validat vizual de proprietar).
public struct StylePreset: Equatable { public var id: String, name: String, apply: (inout AdjustmentSet) -> Void
    public static func == (a: StylePreset, b: StylePreset) -> Bool { a.id == b.id }
    public static let all: [StylePreset] = [
        StylePreset(id: "natural", name: "Natural") { $0.contrast = 1; $0.saturation = 1 },
        StylePreset(id: "intens", name: "Intens") { $0.contrast = 1.25; $0.saturation = 1.20 },
        StylePreset(id: "catifelat", name: "Catifelat") { $0.contrast = 0.85; $0.saturation = 0.85 },
    ]
    public func applied(to a: AdjustmentSet) -> AdjustmentSet { var c = a; apply(&c); c.styleID = id; return c }
}

/// Versiunea estimatorului de expunere, inclusă în amprenta modului automat: o schimbare de estimator invalidează aprobările și cache-ul rezultatelor care depind de el.
public enum ExposureEstimatorVersion { public static let current = 2 }

public enum ZoneKind: String, Codable, CaseIterable { case ellipse, gradient, path, brush
    public var label: String { switch self { case .ellipse: return L("Elipsă"); case .gradient: return L("Degrade"); case .path: return L("Contur"); case .brush: return L("Pensulă") } }
    public var coreKind: Int32 { switch self { case .ellipse: return 0; case .gradient: return 1; case .path: return 2; case .brush: return 3 } }
}
public enum MaskOp: String, Codable, CaseIterable { case add, subtract
    public var label: String { self == .add ? L("Adaugă") : L("Scade") }
}
/// Punct al unui contur: coordonate normalizate ale FOTOGRAFIEI (0…1); `smooth` = segmentele din jur sunt curbe (tangentă automată), altfel colț.
public struct MaskPoint: Codable, Equatable { public var x: Double, y: Double; public var smooth = false
    public init(x: Double, y: Double, smooth: Bool = false) { self.x = x; self.y = y; self.smooth = smooth } }

/// O componentă a măștii unei corecții locale. Masca = componentele aplicate ÎN ORDINE (adaugă / scade), apoi inversarea opțională a întregii măști. Construirea măștii e separată de reglajele aplicate în ea.
/// Definiție VECTORIALĂ în coordonatele fotografiei: aceeași pentru previzualizare și export, la orice rezoluție/zoom. Elipsă: centru (x1,y1), semiaxe (x2,y2 = fracții din lățime/înălțime), rotație în grade (sens orar). Degrade: început (efect complet) → sfârșit.
/// Contur: puncte + închis (un contur deschis nu are efect încă). Pensulă: puncte pe traseu, rază = fracție din înălțimea fotografiei, moliciune 0…1. Poligon sau spline cu puncte netede — NU e o unealtă finală pentru margini complexe (păr, blană).
public struct MaskComponent: Codable, Equatable, Identifiable {
    public var id = UUID().uuidString
    public var kind: ZoneKind = .ellipse
    public var op: MaskOp = .add
    public var x1 = 0.5, y1 = 0.5, x2 = 0.25, y2 = 0.25
    public var rotation = 0.0
    public var feather = 0.35
    public var radius = 0.03, softness = 0.5
    public var points: [MaskPoint] = []
    public var closed = false
    public init(kind: ZoneKind = .ellipse) { self.kind = kind }
    enum CodingKeys: String, CodingKey { case id, kind, op, x1, y1, x2, y2, rotation, feather, radius, softness, points, closed }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString; kind = try c.decodeIfPresent(ZoneKind.self, forKey: .kind) ?? .ellipse; op = try c.decodeIfPresent(MaskOp.self, forKey: .op) ?? .add
        x1 = try c.decodeIfPresent(Double.self, forKey: .x1) ?? 0.5; y1 = try c.decodeIfPresent(Double.self, forKey: .y1) ?? 0.5; x2 = try c.decodeIfPresent(Double.self, forKey: .x2) ?? 0.25; y2 = try c.decodeIfPresent(Double.self, forKey: .y2) ?? 0.25
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0; feather = try c.decodeIfPresent(Double.self, forKey: .feather) ?? 0.35; radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0.03; softness = try c.decodeIfPresent(Double.self, forKey: .softness) ?? 0.5
        points = try c.decodeIfPresent([MaskPoint].self, forKey: .points) ?? []; closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false
    }
    /// O componentă fără efect posibil (contur deschis sau cu < 3 puncte, pensulă fără puncte).
    public var isDrawable: Bool { switch kind { case .ellipse, .gradient: return true; case .path: return closed && points.count >= 3; case .brush: return !points.isEmpty } }
    public var fingerprint: String {
        func f(_ v: Double) -> String { String(format: "%.4f", v) }
        var s = [kind.rawValue, op.rawValue, closed ? "c" : "o"].joined(separator: ",") + "," + [x1, y1, x2, y2, rotation, feather, radius, softness].map(f).joined(separator: ",")
        if !points.isEmpty { s += ",P" + points.map { f($0.x) + ":" + f($0.y) + ($0.smooth ? "s" : "k") }.joined(separator: ";") }
        return s
    }
    /// Date plate pentru nucleu (vezi `pc_mask_image_data`).
    var coreData: [Double] {
        var d: [Double] = [Double(kind.coreKind), op == .add ? 0 : 1, feather, rotation, x1, y1, x2, y2, radius, softness, closed ? 1 : 0, Double(points.count)]
        for p in points { d += [p.x, p.y, p.smooth ? 1 : 0] }
        return d
    }
}

/// Corecție locală: o mască (componente adaugă/scade) + reglaje care folosesc ACELEAȘI instrumente ca cele globale, fiecare în domeniul lui (expunere/balans/umbre/lumini în liniar; contrast/saturație în log).
/// Se aplică după ajustarea globală, pe codul DI ajustat; transformarea finală (GDC DRT → sRGB) se aplică o singură dată, după toate corecțiile. Prima componentă = zona de bază (câmpurile `kind`, `x1`… sunt acces la ea; formatul vechi se citește ca zonă de bază).
public struct LocalCorrection: Codable, Equatable, Identifiable {
    public var id = UUID().uuidString
    public var name = L("Corecție locală")
    public var enabled = true
    public var invert = false                    // inversează întreaga mască compusă
    public var components: [MaskComponent] = [MaskComponent(kind: .ellipse)]
    public var exposure = 0.0, shadows = 0.0, highlights = 0.0, contrast = 1.0, temperature = 0.0, tint = 0.0, saturation = 1.0
    public init() {}
    // acces la zona de bază (prima componentă) — aceleași nume ca înainte
    public var kind: ZoneKind { get { components[0].kind } set { components[0].kind = newValue } }
    public var x1: Double { get { components[0].x1 } set { components[0].x1 = newValue } }
    public var y1: Double { get { components[0].y1 } set { components[0].y1 = newValue } }
    public var x2: Double { get { components[0].x2 } set { components[0].x2 = newValue } }
    public var y2: Double { get { components[0].y2 } set { components[0].y2 = newValue } }
    public var feather: Double { get { components[0].feather } set { components[0].feather = newValue } }
    public var rotation: Double { get { components[0].rotation } set { components[0].rotation = newValue } }
    enum CodingKeys: String, CodingKey { case id, name, enabled, kind, x1, y1, x2, y2, feather, invert, exposure, shadows, highlights, contrast, temperature, tint, saturation, components, rotation }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString; name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Corecție locală"; enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true; invert = try c.decodeIfPresent(Bool.self, forKey: .invert) ?? false
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0; shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0; highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0; contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0; tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0; saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        if let cs = try c.decodeIfPresent([MaskComponent].self, forKey: .components), !cs.isEmpty { components = cs }
        else {   // format vechi (înainte de măști compuse): zona simplă devine componenta de bază
            var b = MaskComponent(kind: try c.decodeIfPresent(ZoneKind.self, forKey: .kind) ?? .ellipse)
            b.x1 = try c.decodeIfPresent(Double.self, forKey: .x1) ?? 0.5; b.y1 = try c.decodeIfPresent(Double.self, forKey: .y1) ?? 0.5; b.x2 = try c.decodeIfPresent(Double.self, forKey: .x2) ?? 0.25; b.y2 = try c.decodeIfPresent(Double.self, forKey: .y2) ?? 0.25
            b.feather = try c.decodeIfPresent(Double.self, forKey: .feather) ?? 0.35; b.rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0; components = [b]
        }
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(enabled, forKey: .enabled); try c.encode(invert, forKey: .invert)
        try c.encode(exposure, forKey: .exposure); try c.encode(shadows, forKey: .shadows); try c.encode(highlights, forKey: .highlights); try c.encode(contrast, forKey: .contrast); try c.encode(temperature, forKey: .temperature); try c.encode(tint, forKey: .tint); try c.encode(saturation, forKey: .saturation)
        try c.encode(components, forKey: .components)
        // câmpurile vechi (zona de bază), pentru versiuni mai vechi ale aplicației; un contur/pensulă apare acolo ca elipsă simplă
        let b = components[0]; try c.encode(b.kind == .gradient ? ZoneKind.gradient : ZoneKind.ellipse, forKey: .kind); try c.encode(b.x1, forKey: .x1); try c.encode(b.y1, forKey: .y1); try c.encode(b.x2, forKey: .x2); try c.encode(b.y2, forKey: .y2); try c.encode(b.feather, forKey: .feather)
    }
    /// Resetarea AJUSTĂRILOR corecției (masca — componentele, estomparea, inversarea și numele — rămân).
    public mutating func resetAdjustments() { exposure = 0; shadows = 0; highlights = 0; contrast = 1; temperature = 0; tint = 0; saturation = 1 }
    public var isActiveLocal: Bool { enabled && !adjustmentIsNeutral && hasDrawableMask }
    public var adjustmentIsNeutral: Bool { exposure == 0 && shadows == 0 && highlights == 0 && contrast == 1 && temperature == 0 && tint == 0 && saturation == 1 }
    /// Masca e simplă (o singură elipsă fără rotație sau un degrade): formatul și amprenta rămân cele de dinainte de măștile compuse.
    var isSimpleMask: Bool { components.count == 1 && (components[0].kind == .gradient || (components[0].kind == .ellipse && components[0].rotation == 0)) && components[0].op == .add }
    public var fingerprint: String {
        func f(_ v: Double) -> String { String(format: "%.4f", v) }
        let b = components[0]
        let head = ([enabled ? "1" : "0", b.kind.rawValue, invert ? "i" : "n"] + [b.x1, b.y1, b.x2, b.y2, b.feather, exposure, shadows, highlights, contrast, temperature, tint, saturation].map(f)).joined(separator: ",")
        return isSimpleMask ? head : head + "|M:" + components.map { $0.fingerprint }.joined(separator: ";")
    }
    /// Zonă implicită, vizibilă și utilă: elipsă centrală sau degrade de sus (efect complet) spre mijloc.
    public static func make(_ kind: ZoneKind, number: Int) -> LocalCorrection {
        var l = LocalCorrection(); l.components = [MaskComponent(kind: kind)]; l.name = "\(kind.label) \(number)"
        switch kind {
        case .ellipse: l.x1 = 0.5; l.y1 = 0.5; l.x2 = 0.28; l.y2 = 0.28; l.feather = 0.5
        case .gradient: l.x1 = 0.5; l.y1 = 0.0; l.x2 = 0.5; l.y2 = 0.55; l.feather = 0.6
        case .path: l.feather = 0.25
        case .brush: l.components[0].feather = 0.35
        }
        return l
    }
    /// Date plate ale măștii compuse pentru nucleu.
    var maskData: [Double] { [1, Double(components.count)] + components.flatMap { $0.coreData } }
    public var hasDrawableMask: Bool { components.contains { $0.isDrawable } }
}
