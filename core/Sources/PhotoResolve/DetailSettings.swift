import Foundation
import CPhotoCore

/// Detalii: reducere de zgomot (luminanță + culoare), claritate (contrast local de scară mare) și accentuare (unsharp mask), pe luminanța imaginii FINALE sRGB (după GDC DRT), ca ultimă etapă a procesării.
/// Aceeași cale pentru previzualizare, interactiv, rezoluție plină și export; razele sunt fracții din înălțimea cadrului (rezultat independent de rezoluție). Neutru la accentuare 0 și claritate 0.
/// Metodă: CLASICĂ (unsharp mask cu prag moale; claritate ponderată pe tonuri medii), fără ML.
public struct DetailSettings: Equatable, Codable {
    public var on = true                 // modulul poate fi scos temporar din procesare (valorile rămân)
    public var sharpAmount = 0.0         // 0…2
    public var sharpRadius = 0.3         // ‰ din înălțime (0,1…2)
    public var sharpThreshold = 0.0      // 0…0,1 (diferențe de luminanță sub prag nu se accentuează)
    public var clarity = 0.0             // −1…1 (negativ = înmoaie contrastul local)
    public var nrLuma = 0.0              // reducere de zgomot, luminanță 0…1 (filtru ghidat; păstrează muchiile)
    public var nrChroma = 0.0            // reducere de zgomot, culoare 0…1 (crominanță netezită în zone de luminanță netedă)
    public init() {}
    enum CodingKeys: String, CodingKey { case on, sharpAmount, sharpRadius, sharpThreshold, clarity, nrLuma, nrChroma }
    public init(from d: Decoder) throws {   // câmpurile lipsă (salvări vechi) rămân la valorile neutre
        let c = try d.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? true; sharpAmount = try c.decodeIfPresent(Double.self, forKey: .sharpAmount) ?? 0; sharpRadius = try c.decodeIfPresent(Double.self, forKey: .sharpRadius) ?? 0.3
        sharpThreshold = try c.decodeIfPresent(Double.self, forKey: .sharpThreshold) ?? 0; clarity = try c.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        nrLuma = try c.decodeIfPresent(Double.self, forKey: .nrLuma) ?? 0; nrChroma = try c.decodeIfPresent(Double.self, forKey: .nrChroma) ?? 0
    }
    public static let ranges: [String: ClosedRange<Double>] = ["amount": 0...2, "radius": 0.1...2, "threshold": 0...0.1, "clarity": -1...1, "nr": 0...1]
    public var isNeutral: Bool { sharpAmount == 0 && clarity == 0 && nrLuma == 0 && nrChroma == 0 }
    public var fingerprint: String { func f(_ v: Double) -> String { String(format: "%.4f", v) }; return "dt:" + [sharpAmount, sharpRadius, sharpThreshold, clarity, nrLuma, nrChroma].map(f).joined(separator: ",") }
    public mutating func reset() { self = DetailSettings() }
    public var core: pc_detail { pc_detail(on: on ? 1 : 0, sharpAmount: sharpAmount, sharpRadius: sharpRadius, sharpThreshold: sharpThreshold, clarity: clarity, nrLuma: nrLuma, nrChroma: nrChroma) }
}
