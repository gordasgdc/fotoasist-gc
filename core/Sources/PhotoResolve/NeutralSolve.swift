import Foundation
import PhotoCore
import CPhotoCore

/// Pipeta de balans de alb: dintr-un eșantion neutru (RGB liniar DWG, după decodare) se află temperatura (mired) și tenta pentru care matricea de balans a nucleului (`pc_balance_matrix`, aceeași ca în procesare) face R = G = B.
/// Rezolvare numerică (Gauss–Newton cu diferențe finite, în limitele sliderelor); rezultatul e verificat prin reziduu, iar limitele atinse sau eșantioanele nepotrivite sunt raportate, nu ascunse.
public enum NeutralSolve {
    public struct Result: Equatable { public var temperature: Double; public var tint: Double; public var residual: Double; public var atBounds: Bool; public var warnings: [String] }
    public static let tempRange = -150.0...150.0, tintRange = -0.05...0.05
    static func apply(_ t: Double, _ s: Double, _ x: [Double]) -> [Double] {
        var m = [Double](repeating: 0, count: 9); pc_balance_matrix(t, s, &m)
        return (0..<3).map { m[$0 * 3] * x[0] + m[$0 * 3 + 1] * x[1] + m[$0 * 3 + 2] * x[2] }
    }
    static func err(_ t: Double, _ s: Double, _ x: [Double]) -> (Double, Double) { let y = apply(t, s, x); let g = max(y[1], 1e-12); return (y[0] / g - 1, y[2] / g - 1) }
    public static func solve(rgb x: [Double]) -> Result? {
        guard x.count == 3, x.allSatisfy({ $0.isFinite }) else { return nil }
        var warns: [String] = []
        guard x.min()! > 1e-4 else { return nil }   // negru/clipat: nu există neutru de estimat
        if x.min()! < 0.01 { warns.append(L("Zonă foarte întunecată: estimarea e nesigură.")) }
        var t = 0.0, s = 0.0
        for _ in 0..<40 {
            let (e0, e1) = err(t, s, x); if max(abs(e0), abs(e1)) < 1e-7 { break }
            let ht = 0.5, hs = 0.0005
            let (a0, a1) = err(t + ht, s, x), (b0, b1) = err(t, s + hs, x)
            let j00 = (a0 - e0) / ht, j10 = (a1 - e1) / ht, j01 = (b0 - e0) / hs, j11 = (b1 - e1) / hs
            let det = j00 * j11 - j01 * j10; guard abs(det) > 1e-12 else { break }
            var dt = -( j11 * e0 - j01 * e1) / det, ds = -(-j10 * e0 + j00 * e1) / det
            dt = max(-60, min(60, dt)); ds = max(-0.02, min(0.02, ds))
            t = max(tempRange.lowerBound, min(tempRange.upperBound, t + dt)); s = max(tintRange.lowerBound, min(tintRange.upperBound, s + ds))
        }
        let (r0, r1) = err(t, s, x); let res = max(abs(r0), abs(r1))
        let bounds = abs(t) >= tempRange.upperBound - 1e-6 || abs(s) >= tintRange.upperBound - 1e-9
        if bounds { warns.append(L("Limita sliderului a fost atinsă: zona aleasă probabil nu e neutră.")) }
        if res > 0.02 { warns.append(LF("Nu s-a obținut un neutru exact (eroare reziduală %@%): alege o zonă cu adevărat gri.", String(format: "%.1f", res * 100))) }
        return Result(temperature: t, tint: s, residual: res, atBounds: bounds, warnings: warns)
    }
}
