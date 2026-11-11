import Foundation
import CPhotoCore

/// Efecte fotografice proprii (nedistructive; neutre implicit; în amprentă doar când ≠ neutru): Optică, Peliculă, Grain. Contract și modele: core/Sources/CPhotoCore/photo_fx.hpp.
/// Nu depind de GDC STYLE. Grain-ul și vinieta se calculează la rezoluția livrabilului (mărimi relative la înălțimea ieșirii).
public struct Effects: Equatable, Codable {
    // Optică (liniar, coordonatele sursei)
    public var distortion = 0.0, caRed = 0.0, caBlue = 0.0, lensVignette = 0.0                       // −100…100 (distorsiune: + corectează butoi / − pernuță)
    public var vignette = 0.0, vignetteMid = 50.0                                                     // vinietă creativă (în ieșire): −100…100 (− întunecă), început 0…100 % din rază
    // Peliculă
    public var halAmount = 0.0, halRadius = 5.0, halThreshold = 1.5, halWarm = 0.8                    // halație: 0…100 · 1…10 · 0…4 stopuri · 0…1
    public var filmAmount = 0.0, filmContrast = 0.0, filmToe = 0.4, filmShoulder = 0.5, filmSat = 1.0, filmCrosstalk = 0.0
    // Grain
    public var grainAmount = 0.0, grainSize = 1.5, grainRough = 0.5, grainChroma = 0.3, grainShadows = 1.0, grainHighlights = 1.0
    public var grainSeed = 1
    /// Film V3 (motor fotochimic; oprit implicit).
    public var film3 = Film3()
    /// GDC Cinema Style (biblioteca de 86 de stiluri; oprit implicit).
    public var cinema = CinemaStyle()
    public init() {}
    enum CodingKeys: String, CodingKey { case distortion, caRed, caBlue, lensVignette, vignette, vignetteMid, halAmount, halRadius, halThreshold, halWarm, filmAmount, filmContrast, filmToe, filmShoulder, filmSat, filmCrosstalk, grainAmount, grainSize, grainRough, grainChroma, grainShadows, grainHighlights, grainSeed, film3, cinema }
    public init(from d: Decoder) throws {   // chei lipsă → neutru
        let c = try d.container(keyedBy: CodingKeys.self); var e = Effects()
        func v(_ k: CodingKeys, _ def: Double) -> Double { (try? c.decodeIfPresent(Double.self, forKey: k)) ?? def }
        e.distortion = v(.distortion, 0); e.caRed = v(.caRed, 0); e.caBlue = v(.caBlue, 0); e.lensVignette = v(.lensVignette, 0); e.vignette = v(.vignette, 0); e.vignetteMid = v(.vignetteMid, 50)
        e.halAmount = v(.halAmount, 0); e.halRadius = v(.halRadius, 5); e.halThreshold = v(.halThreshold, 1.5); e.halWarm = v(.halWarm, 0.8)
        e.filmAmount = v(.filmAmount, 0); e.filmContrast = v(.filmContrast, 0); e.filmToe = v(.filmToe, 0.4); e.filmShoulder = v(.filmShoulder, 0.5); e.filmSat = v(.filmSat, 1); e.filmCrosstalk = v(.filmCrosstalk, 0)
        e.grainAmount = v(.grainAmount, 0); e.grainSize = v(.grainSize, 1.5); e.grainRough = v(.grainRough, 0.5); e.grainChroma = v(.grainChroma, 0.3); e.grainShadows = v(.grainShadows, 1); e.grainHighlights = v(.grainHighlights, 1)
        e.grainSeed = (try? c.decodeIfPresent(Int.self, forKey: .grainSeed)) ?? 1; e.film3 = (try? c.decodeIfPresent(Film3.self, forKey: .film3)) ?? Film3(); e.cinema = (try? c.decodeIfPresent(CinemaStyle.self, forKey: .cinema)) ?? CinemaStyle(); self = e
    }
    public static let ranges: [String: ClosedRange<Double>] = ["distortion": -100...100, "caRed": -100...100, "caBlue": -100...100, "lensVignette": -100...100, "vignette": -100...100, "vignetteMid": 0...100,
        "halAmount": 0...100, "halRadius": 1...10, "halThreshold": 0...4, "halWarm": 0...1, "filmAmount": 0...100, "filmContrast": -0.5...0.5, "filmToe": 0...1, "filmShoulder": 0...1, "filmSat": 0.5...1.5, "filmCrosstalk": 0...0.3,
        "grainAmount": 0...100, "grainSize": 0.5...6, "grainRough": 0...1, "grainChroma": 0...1, "grainShadows": 0...2, "grainHighlights": 0...2]
    /// Grupuri (resetare pe secțiune; module activabile): optică (cu vinietă), peliculă, grain.
    public var opticsIsNeutral: Bool { distortion == 0 && caRed == 0 && caBlue == 0 && lensVignette == 0 && vignette == 0 }
    /// Partea de optică ce schimbă CADRUL/poziția pixelilor (intră în eșantionare și în ghidajele măștilor; rămâne și în „Bază”).
    public var framingIsNeutral: Bool { distortion == 0 && caRed == 0 && caBlue == 0 }
    public var filmIsNeutral: Bool { filmAmount == 0 && halAmount == 0 }
    public var grainIsNeutral: Bool { grainAmount == 0 }
    public var isNeutral: Bool { opticsIsNeutral && filmIsNeutral && grainIsNeutral && lensVignette == 0 && !film3.on && !cinema.on }
    /// Efecte aplicate DUPĂ eșantionare (vinietă, peliculă, grain): se pierd într-un intermediar pentru Resolve dacă nu sunt integrate (vezi predarea).
    public var hasPostEffects: Bool { vignette != 0 || filmAmount > 0 || halAmount > 0 || grainAmount > 0 || film3.on || cinema.on }
    /// Doar optica care se aplică la eșantionare (distorsiune, aberație, vinietă de obiectiv).
    public static func opticsOnly(_ e: Effects) -> Effects { var r = Effects(); r.distortion = e.distortion; r.caRed = e.caRed; r.caBlue = e.caBlue; r.lensVignette = e.lensVignette; return r }
    public mutating func resetOptics() { distortion = 0; caRed = 0; caBlue = 0; lensVignette = 0; vignette = 0; vignetteMid = 50 }
    public mutating func resetFilm() { halAmount = 0; halRadius = 5; halThreshold = 1.5; halWarm = 0.8; filmAmount = 0; filmContrast = 0; filmToe = 0.4; filmShoulder = 0.5; filmSat = 1; filmCrosstalk = 0 }
    public mutating func resetGrain() { grainAmount = 0; grainSize = 1.5; grainRough = 0.5; grainChroma = 0.3; grainShadows = 1; grainHighlights = 1; grainSeed = 1 }
    public var fingerprint: String {
        func f(_ v: Double) -> String { String(format: "%.4f", v) }
        var parts: [String] = []
        if !opticsIsNeutral { parts.append("o:" + [distortion, caRed, caBlue, lensVignette, vignette, vignetteMid].map(f).joined(separator: ",")) }
        if !filmIsNeutral { parts.append("f:" + [halAmount, halRadius, halThreshold, halWarm, filmAmount, filmContrast, filmToe, filmShoulder, filmSat, filmCrosstalk].map(f).joined(separator: ",")) }
        if !grainIsNeutral { parts.append("g:" + ([grainAmount, grainSize, grainRough, grainChroma, grainShadows, grainHighlights].map(f) + ["\(grainSeed)"]).joined(separator: ",")) }
        if film3.on { parts.append(film3.fingerprint) }
        if cinema.on { parts.append(cinema.fingerprint) }
        return parts.joined(separator: ";")
    }
    public var film3C: pc_film3 { film3.c }
    public var cinemaC: pc_cinema { if cinema.on { CinemaLibrary.ensureLoaded() }; return cinema.c }
    public var c: pc_fx {
        var r = pc_fx(); pc_default_fx(&r)
        r.distortion = distortion; r.caRed = caRed; r.caBlue = caBlue; r.lensVignette = lensVignette; r.vignette = vignette; r.vignetteMid = vignetteMid
        r.halAmount = halAmount; r.halRadius = halRadius; r.halThreshold = halThreshold; r.halWarm = halWarm; r.filmAmount = filmAmount; r.filmContrast = filmContrast; r.filmToe = filmToe; r.filmShoulder = filmShoulder; r.filmSat = filmSat; r.filmCrosstalk = filmCrosstalk
        r.grainAmount = grainAmount; r.grainSize = grainSize; r.grainRough = grainRough; r.grainChroma = grainChroma; r.grainShadows = grainShadows; r.grainHighlights = grainHighlights; r.grainSeed = Int32(grainSeed); return r
    }
    /// Optica care mută pixelii (pentru ghidaje): ideal → eșantionat / invers, în pixeli ai sursei.
    public func distort(_ x: Double, _ y: Double, srcW: Int, srcH: Int) -> (x: Double, y: Double) { var f = c; var ox = 0.0, oy = 0.0; pc_fx_distort(&f, Int32(srcW), Int32(srcH), x, y, &ox, &oy); return (ox, oy) }
    public func undistort(_ x: Double, _ y: Double, srcW: Int, srcH: Int) -> (x: Double, y: Double) { var f = c; var ox = 0.0, oy = 0.0; pc_fx_undistort(&f, Int32(srcW), Int32(srcH), x, y, &ox, &oy); return (ox, oy) }
}
