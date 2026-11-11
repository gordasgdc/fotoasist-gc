import Foundation
import Vision
import CoreImage
import ImageIO

/// Mască de PRIM-PLAN (subiect) prin Vision `VNGenerateForegroundInstanceMaskRequest` (macOS 14+, local, fără model descărcat).
/// NU este hartă de adâncime și NU măsoară distanța: separă „subiect” de „fundal” după aspect. Coordonatele sunt ale imaginii date (în orientarea SURSEI):
/// rezultatul se folosește în coordonate normalizate ale sursei, deci rămâne corect după decupare/rotire, ca restul măștilor.
public enum SubjectMask {
    public struct Result { public var width: Int, height: Int; public var alpha: [Float]; public var instances: Int }
    public static var isAvailable: Bool { if #available(macOS 14.0, *) { return true } else { return false } }
    /// `nil` = indisponibil (macOS < 14) sau niciun subiect găsit; nu aruncă. Alfa 0…1 cu margini moi (nu binară).
    public static func generate(_ image: CGImage) -> Result? {
        guard #available(macOS 14.0, *) else { return nil }
        let req = VNGenerateForegroundInstanceMaskRequest(); let h = VNImageRequestHandler(cgImage: image)
        guard (try? h.perform([req])) != nil, let o = req.results?.first, !o.allInstances.isEmpty, let pb = try? o.generateScaledMaskForImage(forInstances: o.allInstances, from: h) else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_OneComponent32Float, let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb), hh = CVPixelBufferGetHeight(pb), stride = CVPixelBufferGetBytesPerRow(pb) / 4; let p = base.assumingMemoryBound(to: Float.self)
        var a = [Float](repeating: 0, count: w * hh); for y in 0..<hh { for x in 0..<w { a[y * w + x] = min(1, max(0, p[y * stride + x])) } }
        return Result(width: w, height: hh, alpha: a, instances: o.allInstances.count)
    }

    // MARK: contur al celui mai mare subiect (coordonate normalizate 0…1, origine sus-stânga) — pentru o mască de tip contur închis, deci Undo/Redo, persistență și geometrie le oferă masca existentă.
    /// Conturul exterior al celei mai mari componente conexe (alfa ≥ 0,5), simplificat Douglas–Peucker (`epsilon` normalizat). nil dacă nu există o componentă de cel puțin `minArea` (fracție din imagine).
    public static func contour(alpha: [Float], width w: Int, height h: Int, epsilon: Double = 0.004, minArea: Double = 0.002) -> [(x: Double, y: Double)]? {
        guard w > 2, h > 2, alpha.count >= w * h else { return nil }
        // coborâm la ≤ 256 px pe latura mare (un contur al unei măști moi nu are nevoie de mai mult)
        let f = max(1, (max(w, h) + 255) / 256); let gw = w / f, gh = h / f; guard gw > 2, gh > 2 else { return nil }
        var g = [Bool](repeating: false, count: gw * gh); for y in 0..<gh { for x in 0..<gw { var a: Float = 0; for yy in 0..<f { for xx in 0..<f { a += alpha[(y * f + yy) * w + x * f + xx] } }; g[y * gw + x] = a / Float(f * f) >= 0.5 } }
        var comp = [Int32](repeating: -1, count: gw * gh); var best = -1, bestN = 0, n = 0
        for st in 0..<(gw * gh) where g[st] && comp[st] < 0 { var stack = [st]; comp[st] = Int32(n); var cnt = 0
            while let c = stack.popLast() { cnt += 1; let cx = c % gw, cy = c / gw
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { let nx = cx + dx, ny = cy + dy; if nx >= 0, ny >= 0, nx < gw, ny < gh, g[ny * gw + nx], comp[ny * gw + nx] < 0 { comp[ny * gw + nx] = Int32(n); stack.append(ny * gw + nx) } } }
            if cnt > bestN { bestN = cnt; best = n }; n += 1 }
        guard best >= 0, Double(bestN) / Double(gw * gh) >= minArea else { return nil }
        func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < gw && y < gh && comp[y * gw + x] == Int32(best) }
        // urmărirea conturului (Moore) pornind de la primul pixel al componentei în ordinea rândurilor
        guard let st = (0..<(gw * gh)).first(where: { comp[$0] == Int32(best) }) else { return nil }
        let sx = st % gw, sy = st / gw; let nb = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
        var pts: [(Int, Int)] = [(sx, sy)]; var cx = sx, cy = sy, dir = 6; var guardN = 0
        repeat { var found = false
            for k in 0..<8 { let d = (dir + 6 + k) % 8; let nx = cx + nb[d].0, ny = cy + nb[d].1; if inside(nx, ny) { cx = nx; cy = ny; dir = d; found = true; break } }
            if !found { break }; if (cx, cy) != (sx, sy) { pts.append((cx, cy)) }; guardN += 1
        } while (cx, cy) != (sx, sy) && guardN < gw * gh * 4
        guard pts.count >= 3 else { return nil }
        let norm = pts.map { (x: (Double($0.0) + 0.5) / Double(gw), y: (Double($0.1) + 0.5) / Double(gh)) }
        let simp = douglasPeuckerClosed(norm, epsilon: epsilon); return simp.count >= 3 ? simp : nil
    }
    static func douglasPeuckerClosed(_ p: [(x: Double, y: Double)], epsilon: Double) -> [(x: Double, y: Double)] {
        guard p.count > 3 else { return p }
        func dist(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double), _ c: (x: Double, y: Double)) -> Double { let dx = c.x - b.x, dy = c.y - b.y, L = dx * dx + dy * dy; if L == 0 { return hypot(a.x - b.x, a.y - b.y) }; let t = max(0, min(1, ((a.x - b.x) * dx + (a.y - b.y) * dy) / L)); return hypot(a.x - (b.x + t * dx), a.y - (b.y + t * dy)) }
        func dp(_ a: Int, _ b: Int, _ keep: inout [Bool]) { var m = -1.0, mi = -1; if b - a < 2 { return }; for i in (a + 1)..<b { let d = dist(p[i], p[a], p[b]); if d > m { m = d; mi = i } }; if m > epsilon, mi >= 0 { keep[mi] = true; dp(a, mi, &keep); dp(mi, b, &keep) } }
        var far = 0, fd = 0.0; for i in 1..<p.count { let d = hypot(p[i].x - p[0].x, p[i].y - p[0].y); if d > fd { fd = d; far = i } }
        var keep = [Bool](repeating: false, count: p.count); keep[0] = true; keep[far] = true; dp(0, far, &keep)
        var rest = Array(p[far...]); rest.append(p[0]); var keep2 = [Bool](repeating: false, count: rest.count); keep2[0] = true; keep2[rest.count - 1] = true; dp(0, rest.count - 1, &keep2)
        var out: [(x: Double, y: Double)] = []; for i in 0..<far where keep[i] { out.append(p[i]) }; for i in 0..<(rest.count - 1) where keep2[i] { out.append(rest[i]) }; return out
    }
    /// Matte 8 biți (gri, alb = subiect) la dimensiunea alfa — pentru predarea în Resolve ca matte extern (fișier PNG); aceeași geometrie ca fotografia sursă, nu ca vederea decupată.
    public static func mattePNG(alpha: [Float], width w: Int, height h: Int) -> Data? {
        var px = alpha.prefix(w * h).map { UInt8(max(0, min(255, $0 * 255 + 0.5))) }
        guard let cg: CGImage = px.withUnsafeMutableBytes({ b in CGContext(data: b.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage() }) else { return nil }
        let out = NSMutableData(); guard let d = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }; CGImageDestinationAddImage(d, cg, nil); return CGImageDestinationFinalize(d) ? out as Data : nil
    }
}
