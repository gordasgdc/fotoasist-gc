import Foundation

/// Geometria conturului pentru editare/afișare: ACELEAȘI formule ca în nucleu (Catmull-Rom → Bézier cubic între puncte; colț = tangentă zero), ca ghidajul să coincidă cu masca reală.
public enum MaskGeometry {
    public typealias P = (x: Double, y: Double)
    /// Pentru fiecare segment i→i+1 (circular dacă `closed`): punctele curbei aplatizate (inclusiv capetele). Coordonatele sunt înmulțite cu (sx, sy) (ex.: dimensiunea imaginii în pixeli sau a ecranului).
    public static func flatten(_ pts: [MaskPoint], closed: Bool, sx: Double = 1, sy: Double = 1, steps: Int = 16) -> [[P]] {
        let n = pts.count; guard n >= 2 else { return [] }
        func X(_ i: Int) -> Double { pts[((i % n) + n) % n].x * sx }; func Y(_ i: Int) -> Double { pts[((i % n) + n) % n].y * sy }; func S(_ i: Int) -> Bool { pts[((i % n) + n) % n].smooth }
        func T(_ i: Int) -> P { guard S(i), closed || (i > 0 && i < n - 1) else { return (0, 0) }; return ((X(i + 1) - X(i - 1)) / 6, (Y(i + 1) - Y(i - 1)) / 6) }
        var out: [[P]] = []; let count = closed ? n : n - 1
        for i in 0..<count {
            let j = (i + 1) % n
            if !S(i) && !S(j) { out.append([(X(i), Y(i)), (X(j), Y(j))]); continue }
            let t0 = T(i), t1 = T(j); let c1: P = (X(i) + t0.x, Y(i) + t0.y), c2: P = (X(j) - t1.x, Y(j) - t1.y); var seg: [P] = [(X(i), Y(i))]
            for k in 1...steps { let t = Double(k) / Double(steps), u = 1 - t, b0 = u * u * u, b1 = 3 * u * u * t, b2 = 3 * u * t * t, b3 = t * t * t
                seg.append((b0 * X(i) + b1 * c1.x + b2 * c2.x + b3 * X(j), b0 * Y(i) + b1 * c1.y + b2 * c2.y + b3 * Y(j))) }
            out.append(seg)
        }
        return out
    }
    /// Cel mai apropiat segment de un punct (în același sistem de coordonate ca `sx, sy`): indicele segmentului, punctul proiectat (normalizat) și distanța.
    public static func nearestSegment(_ pts: [MaskPoint], closed: Bool, to p: P, sx: Double, sy: Double) -> (segment: Int, point: P, distance: Double)? {
        let segs = flatten(pts, closed: closed, sx: sx, sy: sy); var best: (Int, P, Double)? = nil
        for (i, s) in segs.enumerated() { for k in 0..<(s.count - 1) {
            let a = s[k], b = s[k + 1], ex = b.x - a.x, ey = b.y - a.y, L2 = ex * ex + ey * ey; var t = L2 > 0 ? ((p.x - a.x) * ex + (p.y - a.y) * ey) / L2 : 0; t = min(1, max(0, t))
            let q: P = (a.x + t * ex, a.y + t * ey), d = hypot(q.x - p.x, q.y - p.y); if best == nil || d < best!.2 { best = (i, q, d) } } }
        return best.map { ($0.0, ($0.1.x / sx, $0.1.y / sy), $0.2) }
    }
    /// Reduce o traiectorie de pensulă: păstrează un punct doar dacă e la cel puțin `minDistance` de precedentul (în coordonatele date), ca definiția să rămână mică.
    public static func decimate(_ pts: [P], minDistance: Double) -> [P] { var o: [P] = []; for p in pts { if let l = o.last, hypot(p.x - l.x, p.y - l.y) < minDistance { continue }; o.append(p) }; return o }
}
