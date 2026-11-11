import Foundation
import PhotoCore
import CPhotoCore

/// Retuș punctual (clone / heal): o listă de operații pe fotografie, în coordonatele SURSEI (normalizate), aplicate pe imaginea liniară DWG înaintea instrumentelor și a geometriei.
/// Deci rămân corecte la decupare/rotire și la orice rezoluție (raza = fracție din înălțime). Fără detecție automată (ar cere ML; ML e permis doar pentru culling).
public struct RetouchSpot: Codable, Equatable, Identifiable {
    public enum Mode: Int, Codable, CaseIterable { case clone = 0, heal = 1, redEye = 2
        public var label: String { switch self { case .clone: return L("Clonă"); case .heal: return "Vindecare"; case .redEye: return L("Ochi roșii") } } }
    public var id = UUID().uuidString
    public var enabled = true
    public var mode: Mode = .heal
    public var x = 0.5, y = 0.5            // destinația (centrul), normalizat
    public var sx = 0.55, sy = 0.5         // sursa (centrul), normalizat
    public var radius = 0.02               // fracție din înălțime
    public var feather = 0.5               // 0…1 (fracția din rază cu margine moale)
    /// Doar «Ochi roșii»: intensitatea corecției 0…1 (lipsă = 1). Cheie opțională ⇒ fișierele salvate înainte rămân valide.
    public var strength: Double? = nil
    public init() {}
    public var fingerprint: String { func f(_ v: Double) -> String { String(format: "%.5f", v) }; return "\(enabled ? 1 : 0)\(mode.rawValue)," + ([x, y, sx, sy, radius, feather] + (mode == .redEye ? [strength ?? 1] : [])).map(f).joined(separator: ",") }
    var core: pc_spot { pc_spot(mode: Int32(mode.rawValue), enabled: enabled ? 1 : 0, x: x, y: y, sx: sx, sy: sy, radius: radius, feather: feather) }
}

public enum Retouch {
    /// Copie a imaginii cu retușurile aplicate; imaginea de intrare rămâne neatinsă.
    public static func apply(_ spots: [RetouchSpot], to rgb: [Float], width: Int, height: Int) -> [Float] {
        let active = spots.filter { $0.enabled }; guard !active.isEmpty else { return rgb }
        var out = rgb
        for e in active where e.mode == .redEye { RedEye.apply(e, to: &out, width: width, height: height) }      // ochi roșii: în Swift, în ordinea listei, înaintea clonei/vindecării
        let cs = active.filter { $0.mode != .redEye }.map { $0.core }; guard !cs.isEmpty else { return out }
        _ = out.withUnsafeMutableBufferPointer { pc_retouch_apply(cs, Int32(cs.count), $0.baseAddress, Int32(width), Int32(height)) }
        return out
    }
}

/// Corecție MANUALĂ de ochi roșii (nu detector): utilizatorul pune un cerc peste ochi; în interior se atenuează DOAR pixelii puternic roșii
/// (roșeață = (R − max(G,B)) / (R+G+B), în liniar DWG), roșul se neutralizează spre max(G,B) și pixelul se întunecă. Pielea (roșeață ≈ 0,15–0,28), irisul și reflexele
/// (albe, fără dominantă roșie) rămân neatinse. Metoda urmează ideea documentată în LightCraft `redeye.rs` (MIT OR Apache-2.0): codul NU e preluat.
/// Limite: ochi de animale (reflex verde/galben) neacoperiți; o buză/piele foarte roșie în cerc poate fi atinsă — ținta se ajustează prin rază și intensitate.
public enum RedEye {
    public static let rednessLow: Float = 0.34, rednessHigh: Float = 0.50
    @inline(__always) static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
    public static func apply(_ e: RetouchSpot, to rgb: inout [Float], width w: Int, height h: Int) {
        guard w > 0, h > 0, rgb.count >= w * h * 3 else { return }
        let k = Float(min(1, max(0, e.strength ?? 1))); guard k > 0 else { return }
        let cx = Float(e.x) * Float(w), cy = Float(e.y) * Float(h), r = max(1, Float(e.radius) * Float(h))
        let x0 = max(0, Int(cx - r - 1)), x1 = min(w - 1, Int(cx + r + 1)), y0 = max(0, Int(cy - r - 1)), y1 = min(h - 1, Int(cy + r + 1)); guard x0 <= x1, y0 <= y1 else { return }
        let soft = Float(min(1, max(0, e.feather)))
        for y in y0...y1 { for x in x0...x1 {
            let dx = Float(x) + 0.5 - cx, dy = Float(y) + 0.5 - cy, d = (dx * dx + dy * dy).squareRoot() / r; guard d < 1 else { continue }
            let edge = soft > 0 ? 1 - smooth(1 - soft, 1, d) : 1
            let i = (y * w + x) * 3, R = rgb[i], G = rgb[i + 1], B = rgb[i + 2]; guard R.isFinite, G.isFinite, B.isFinite else { continue }
            let sum = R + G + B; guard sum > 1e-6 else { continue }
            let red = (R - max(G, B)) / sum; let a = smooth(rednessLow, rednessHigh, red) * edge * k; guard a > 0 else { continue }
            let target = max(G, B), nr = R + (target - R) * a, dark = 1 - 0.55 * a
            rgb[i] = nr * dark; rgb[i + 1] = G * dark; rgb[i + 2] = B * dark
        } }
    }
}
