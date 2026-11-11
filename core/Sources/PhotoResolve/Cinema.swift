import Foundation
import CPhotoCore

/// Biblioteca GDC Cinema Style (86 de stiluri în 4 straturi) — registrul și modelele (resursă `film/film_models.gdcfilm`), încărcate o singură dată.
public enum CinemaLibrary {
    public struct Entry: Equatable { public let index: Int; public let id: String; public let name: String; public let category: String; public let layer: Int; public let layerIndex: Int; public let stockIndex: Int
        public var displayName: String { name.replacingOccurrences(of: "_", with: " ") } }
    public static let layerLabels = ["Chemical Process", "Film Stock", "Contrast Response", "Color & Skin Tuning"]
    public static let layerDefaultOn = [false, true, false, false]
    /// Încarcă modelele (idempotent). false dacă resursa lipsește sau e invalidă.
    @discardableResult public static func ensureLoaded() -> Bool {
        if pc_cinema_ready() != 0 { return true }
        return loadOnce
    }
    private static let loadOnce: Bool = {
        // Bundle.main primul; Bundle.module se evaluează DOAR ca rezervă (în aplicația împachetată cere un pachet de resurse care nu există și oprește procesul)
        let u = Bundle.main.url(forResource: "film_models", withExtension: "gdcfilm", subdirectory: "film") ?? ModuleBundle.optional?.url(forResource: "film_models", withExtension: "gdcfilm", subdirectory: "film")
        let candidates = [u].compactMap { $0 }
        for u in candidates where pc_cinema_load(u.path) == 0 { return true }
        return pc_cinema_ready() != 0
    }()
    public static let entries: [Entry] = (0..<Int(pc_cinema_style_count())).map { i in
        var l: Int32 = 0, li: Int32 = 0, si: Int32 = 0; pc_cinema_style_info(Int32(i), &l, &li, &si)
        return Entry(index: i, id: String(cString: pc_cinema_style_id(Int32(i))), name: String(cString: pc_cinema_style_name(Int32(i))), category: String(cString: pc_cinema_style_category(Int32(i))), layer: Int(l), layerIndex: Int(li), stockIndex: Int(si)) }
    public static func entries(ofLayer l: Int) -> [Entry] { entries.filter { $0.layer == l }.sorted { $0.layerIndex < $1.layerIndex } }
    public static var defaultFilmStyle: Int { entries(ofLayer: 1).firstIndex { $0.id == "kodak-5219" } ?? 0 }
}

/// GDC Cinema Style: patru straturi On/Off (Chemical Process · Film Stock · Contrast Response · Color & Skin) cu stil și mix, trim-uri, textură opțională (format, MTF, halație, grăunte după stil). Oprit implicit; valorile se păstrează.
/// Domeniu și poziție: după ajustări, înaintea Film V3 și a DRT-ului; stilurile lucrează în ACEScct/AP1. Biblioteca e creativă (nume originale păstrate; fără afiliere cu producătorii).
public struct CinemaStyle: Equatable, Codable {
    public struct Slot: Equatable, Codable { public var on = false; public var style = 0; public var mix = 1.0; public init(on: Bool = false, style: Int = 0, mix: Double = 1) { self.on = on; self.style = style; self.mix = mix } }
    public var on = false
    public var slots: [Slot] = (0..<4).map { Slot(on: CinemaLibrary.layerDefaultOn[$0], style: $0 == 1 ? CinemaLibrary.defaultFilmStyle : 0, mix: 1) }
    public var exposure = 0.0, contrast = 1.0, density = 0.0, warmth = 0.0, tint = 0.0, saturation = 1.0, amount = 1.0
    public var format = Int(pc_film3_format_default()), textureModel = 0
    public var mtfOn = false, softness = 1.0, halOn = false, halAmount = 1.0, halSizePct = 1.6, grainOn = false, grainAmount = 0.5, grainSizeHuman = 1.0, grainShadows = 1.0, grainHighlights = 1.0, grainSeed = 0
    public var mix = 1.0
    public init() { applyFormat(Int(pc_film3_format_default())) }
    public mutating func applyFormat(_ i: Int) {
        format = i; var v = [Double](repeating: 0, count: 5), s = [Int32](repeating: 0, count: 5); pc_film3_format_start(Int32(i), &v, &s)
        if s[0] != 0 { grainSizeHuman = v[0] }; if s[1] != 0 { softness = v[1] }; if s[2] != 0 { halSizePct = v[2] }; if s[3] != 0 { grainAmount = v[3] }; if s[4] != 0 { halAmount = v[4] }
    }
    public var gateMm: Double { pc_film3_format_gate(Int32(format)) }
    public var textureActive: Bool { mtfOn || halOn || grainOn }
    public var fingerprint: String {
        func f(_ v: Double) -> String { String(format: "%.4f", v) }
        return "cs:" + slots.map { "\($0.on ? 1 : 0).\($0.style).\(f($0.mix))" }.joined(separator: ",") + "|" + [exposure, contrast, density, warmth, tint, saturation, amount, mix].map(f).joined(separator: ",")
            + (textureActive ? "|tx:\(format),\(textureModel)," + [mtfOn ? softness : -1, halOn ? halAmount : -1, halOn ? halSizePct : 0, grainOn ? grainAmount : -1, grainSizeHuman, grainShadows, grainHighlights].map(f).joined(separator: ",") + ",\(grainSeed)" : "")
    }
    public mutating func reset() { let keep = on; self = CinemaStyle(); on = keep }
    public var c: pc_cinema {
        var r = pc_cinema(); pc_default_cinema(&r); r.on = on ? 1 : 0
        let active = slots.enumerated().filter { $0.element.on }   // straturile active, în ordinea sloturilor, compactate
        r.layers = Int32(active.count)
        withUnsafeMutableBytes(of: &r.layerStock) { st in withUnsafeMutableBytes(of: &r.layerMix) { mx in
            for (k, a) in active.enumerated() { let list = CinemaLibrary.entries(ofLayer: a.offset); let e = list[min(max(0, a.element.style), max(0, list.count - 1))]
                st.storeBytes(of: Int32(e.stockIndex), toByteOffset: k * 4, as: Int32.self); mx.storeBytes(of: a.element.mix, toByteOffset: k * 8, as: Double.self) } } }
        r.exposure = exposure; r.contrast = contrast; r.density = density; r.warmth = warmth; r.tint = tint; r.saturation = saturation; r.amount = amount; r.mix = mix
        let mag = 24.89 / gateMm
        r.texture.negStock = Int32(textureModel); r.texture.formatWidthMm = gateMm; r.texture.mtfAmount = softness / mag; r.texture.halationAmount = halAmount; r.texture.halationRadiusMm = halSizePct * gateMm / 100
        r.texture.grainAmount = grainAmount; r.texture.grainSize = grainSizeHuman / mag; r.texture.grainShadows = grainShadows; r.texture.grainHighlights = grainHighlights; r.texture.grainSeed = Double(grainSeed)
        r.texture.mtfEnabled = mtfOn ? 1 : 0; r.texture.halationEnabled = halOn ? 1 : 0; r.texture.grainEnabled = grainOn ? 1 : 0
        return r
    }
}
