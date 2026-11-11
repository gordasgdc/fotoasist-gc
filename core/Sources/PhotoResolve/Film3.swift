import Foundation
import CPhotoCore

/// Film V3 (motor fotochimic GDC, port din STYLE — vezi CPhotoCore/docs/ADAPTATION_MANIFEST.md): negativ Kodak → expunere → [MTF] → [halație] → grăunte în densitate → print → proiecție.
/// Domeniu: coduri log ale familiei active, după toate ajustările, înaintea DRT-ului; cadru complet (MTF/halație/grăunte sunt spațiale). Oprit implicit; valorile se păstrează când e oprit. Controalele de textură sunt UMANE (relative la cadru), ca în referință.
public struct Film3: Equatable, Codable {
    public var on = false
    public var negStock = 0, printStock = 0, format = Int(pc_film3_format_default())
    public var colourSeparation = 0.0, negContrast = 1.0, printContrast = 1.0, exposure = 0.0
    public var lightsMaster = 0.0, lightsR = 0.0, lightsG = 0.0, lightsB = 0.0
    public var mtfOn = true, softness = 1.0                       // × Super 35
    public var halOn = true, halAmount = 1.0, halSizePct = 1.6    // cantitate fizică (1 = 1% din energie) · % din lățimea cadrului
    public var grainOn = true, grainAmount = 0.5, grainSizeHuman = 1.0, grainShadows = 1.0, grainHighlights = 1.0, grainSeed = 0, grainAnimate = true
    public var mix = 1.0
    public init() { applyFormat(Int(pc_film3_format_default())) }
    public static let ranges: [String: ClosedRange<Double>] = ["exposure": -4...4, "colourSeparation": 0...1, "negContrast": 0.5...1.6, "printContrast": 0.5...1.6, "lights": -12...12,
        "softness": 0...12, "halAmount": 0...4, "halSizePct": 0.1...20, "grainAmount": 0...2, "grainSizeHuman": 0.1...12, "grainTone": 0...3, "mix": 0...1]
    /// Valorile de pornire ale formatului pentru controalele legate (cele nelegate rămân).
    public mutating func applyFormat(_ i: Int) {
        format = i; var v = [Double](repeating: 0, count: 5), s = [Int32](repeating: 0, count: 5); pc_film3_format_start(Int32(i), &v, &s)
        if s[0] != 0 { grainSizeHuman = v[0] }; if s[1] != 0 { softness = v[1] }; if s[2] != 0 { halSizePct = v[2] }; if s[3] != 0 { grainAmount = v[3] }; if s[4] != 0 { halAmount = v[4] }
    }
    public var gateMm: Double { pc_film3_format_gate(Int32(format)) }
    public var fingerprint: String {
        func f(_ v: Double) -> String { String(format: "%.4f", v) }
        return "f3:\(negStock),\(printStock),\(format)," + [colourSeparation, negContrast, printContrast, exposure, lightsMaster, lightsR, lightsG, lightsB, mtfOn ? softness : -1, halOn ? halAmount : -1, halOn ? halSizePct : 0, grainOn ? grainAmount : -1, grainSizeHuman, grainShadows, grainHighlights, mix].map(f).joined(separator: ",") + ",\(grainSeed),\(grainAnimate ? 1 : 0)"
    }
    public mutating func reset() { let keepOn = on; self = Film3(); on = keepOn }
    /// Parametrii fizici pentru motor: factorii umani (× Super 35, % cadru) → mărimi pe film, ca `filmV3PhysicalFromHuman`.
    public var c: pc_film3 {
        var r = pc_film3(); pc_default_film3(&r); r.on = on ? 1 : 0
        let mag = 24.89 / gateMm   // = formatReferenceGateMm / poartă (referința Super 35)
        r.negStock = Int32(negStock); r.printStock = Int32(printStock); r.colourSeparation = colourSeparation; r.negContrast = negContrast; r.printContrast = printContrast; r.exposure = exposure
        r.lightsMaster = lightsMaster; r.lightsR = lightsR; r.lightsG = lightsG; r.lightsB = lightsB
        r.grainShadows = grainShadows; r.grainHighlights = grainHighlights; r.grainAmount = grainAmount; r.grainSize = grainSizeHuman / mag; r.mtfAmount = softness / mag; r.halationAmount = halAmount; r.halationRadiusMm = halSizePct * gateMm / 100
        r.grainAnimate = grainAnimate ? 1 : 0; r.grainSeed = Double(grainSeed); r.frame = 0; r.formatWidthMm = gateMm; r.mix = mix; r.mtfEnabled = mtfOn ? 1 : 0; r.halationEnabled = halOn ? 1 : 0; r.grainEnabled = grainOn ? 1 : 0
        return r
    }
    public static var stockLabels: [String] { (0..<Int(pc_film3_stock_count())).map { String(cString: pc_film3_stock_label(Int32($0))) } }
    public static var stockInfos: [String] { (0..<Int(pc_film3_stock_count())).map { String(cString: pc_film3_stock_info(Int32($0))) } }
    public static var printLabels: [String] { (0..<Int(pc_film3_print_count())).map { String(cString: pc_film3_print_label(Int32($0))) } }
    public static var formatLabels: [String] { (0..<Int(pc_film3_format_count())).map { String(cString: pc_film3_format_label(Int32($0))) } }
}
