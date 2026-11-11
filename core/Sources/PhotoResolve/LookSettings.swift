import Foundation
import CPhotoCore

/// Look (generația FIELD, 37 de rețete — port din GDC STYLE, vezi CPhotoCore/docs/ADAPTATION_MANIFEST.md): caracter artistic în cod log, după Color/Skin și înaintea Highlights+Gamut/DRT.
/// Rețetele sunt date versionate (ordinea = indexul salvat, ÎNGHEȚATĂ); designul lor are verdict doar de la colorist. Oprit implicit; valorile se păstrează.
public struct LookSettings: Equatable, Codable {
    public var on = false
    public var look = 0
    public var contrast = 0.0, blacks = 0.0, roll = 0.0, color = 1.0, sat = 0.0, warm = 0.0
    public var protectSkin = 0.5, strength = 1.0
    public init() {}
    public static let ranges: [String: ClosedRange<Double>] = ["trim": -1...1, "color": 0...1.5, "protect": 0...1, "strength": 0...1.5]
    public var fingerprint: String { func f(_ v: Double) -> String { String(format: "%.4f", v) }; return "lk:\(look)," + [contrast, blacks, roll, color, sat, warm, protectSkin, strength].map(f).joined(separator: ",") }
    public mutating func reset() { let keep = on; self = LookSettings(); on = keep }
    public func apply(to p: inout pc_params) { p.lookOn = on ? 1 : 0; p.lookIndex = Int32(look); p.lookStrength = strength; p.lookProtect = protectSkin; p.lookContrast = contrast; p.lookBlacks = blacks; p.lookRoll = roll; p.lookSat = sat; p.lookWarm = warm; p.lookColor = color }
    /// Etichetele din listă („Look 01” …), în ordinea bibliotecii (indexul salvat).
    public static var names: [String] { (0..<Int(pc_look_count())).map { String(cString: pc_look_name(Int32($0))) } }
}
