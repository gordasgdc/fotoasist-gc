import Foundation
import CoreGraphics

/// Semnale CLASICE (fără ML) calculate pe o previzualizare mică. Sunt SUGESTII: mișcarea intenționată, profunzimea mică de câmp și scenele low-key pot fi alegeri creative.
public struct Signals: Equatable {
    public static let version = 1
    public var sharpness: Double        // varianța Laplacianului pe luminanță (relativă; comparabilă doar în același conținut/grup; umflată de zgomot)
    public var clipHighPct: Double      // % pixeli cu un canal ≥ 250/255 în previzualizare (decupare în previzualizarea camerei, nu în RAW)
    public var clipLowPct: Double       // % pixeli cu toate canalele ≤ 5
    public var medianLuma: Double       // 0…255
    public var dhash: UInt64            // 64 de biți, 9×8 pe luminanță
    public var histogram: [Float]       // 8×8×8 normalizat (512)
    public static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }
    public static func histogramIntersection(_ a: [Float], _ b: [Float]) -> Double { zip(a, b).reduce(0) { $0 + Double(min($1.0, $1.1)) } }
}

public enum SignalAnalyzer {
    /// Desenează imaginea în RGBA 8 biți (latura lungă ≤ `maxSide`) și calculează semnalele.
    public static func analyze(_ image: CGImage, maxSide: Int = 256) -> Signals {
        let (w, h, px) = rgba(image, maxSide: maxSide)
        var luma = [Float](repeating: 0, count: w * h); var clipHi = 0, clipLo = 0
        var hist = [Float](repeating: 0, count: 512); var lumaHist = [Int](repeating: 0, count: 256)
        for i in 0..<(w * h) {
            let r = Int(px[i * 4]), g = Int(px[i * 4 + 1]), b = Int(px[i * 4 + 2])
            let y = 0.2126 * Float(r) + 0.7152 * Float(g) + 0.0722 * Float(b); luma[i] = y; lumaHist[min(255, Int(y))] += 1
            if max(r, g, b) >= 250 { clipHi += 1 }; if max(r, g, b) <= 5 { clipLo += 1 }
            hist[(r >> 5) << 6 | (g >> 5) << 3 | (b >> 5)] += 1
        }
        let n = Float(w * h); for i in 0..<512 { hist[i] /= n }
        var acc = 0, median = 0.0; for v in 0..<256 { acc += lumaHist[v]; if acc * 2 >= w * h { median = Double(v); break } }
        var s = 0.0, s2 = 0.0, c = 0.0
        if w > 2 && h > 2 {
            for y in 1..<(h - 1) { for x in 1..<(w - 1) {
                let i = y * w + x; let l = Double(luma[i - 1] + luma[i + 1] + luma[i - w] + luma[i + w] - 4 * luma[i]); s += l; s2 += l * l; c += 1 } }
        }
        let mean = c > 0 ? s / c : 0, variance = c > 0 ? s2 / c - mean * mean : 0
        return Signals(sharpness: variance, clipHighPct: Double(clipHi) / Double(w * h) * 100, clipLowPct: Double(clipLo) / Double(w * h) * 100, medianLuma: median, dhash: dhash(image), histogram: hist)
    }

    static func dhash(_ image: CGImage) -> UInt64 {
        let (_, _, px) = rgba(image, exactW: 9, exactH: 8)
        var bits: UInt64 = 0, k = 0
        for y in 0..<8 { for x in 0..<8 {
            func l(_ xx: Int) -> Float { let i = (y * 9 + xx) * 4; return 0.2126 * Float(px[i]) + 0.7152 * Float(px[i + 1]) + 0.0722 * Float(px[i + 2]) }
            if l(x + 1) > l(x) { bits |= (1 << UInt64(k)) }; k += 1 } }
        return bits
    }

    static func rgba(_ image: CGImage, maxSide: Int = 0, exactW: Int = 0, exactH: Int = 0) -> (Int, Int, [UInt8]) {
        var w = exactW, h = exactH
        if exactW == 0 { let s = min(1.0, Double(maxSide) / Double(max(image.width, image.height))); w = max(1, Int(Double(image.width) * s)); h = max(1, Int(Double(image.height) * s)) }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { p in
            if let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .high; ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        return (w, h, buf)
    }
}

/// Grup SUGERAT de cadre (nu decizie). Pragurile sunt conservatoare și documentate; la ele se adaugă mereu confirmarea fotografului.
public struct SuggestedGroup: Equatable {
    public enum Kind: String { case burst, similar }
    public enum Confidence: String { case likely, weak }
    public var kind: Kind, confidence: Confidence, reason: String, memberIds: [Int64]
}

public enum Grouping {
    public static let burstGapSeconds = 3.0
    public static let similarMaxHamming = 10
    public static let similarMinHistogramIntersection = 0.6
    /// Rafale = cadre consecutive ≤3 s de același aparat (semnal puternic de timp; „likely” dacă și dHash e apropiat, altfel „weak”). Similare = dHash ≤10 ȘI histogramă ≥0.6 (semnal slab).
    public static func suggest(photos: [PhotoRecord], signals: [Int64: Signals]) -> [SuggestedGroup] {
        var parent = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0.id) })
        func find(_ x: Int64) -> Int64 { var r = x; while parent[r]! != r { r = parent[r]! }; return r }
        func union(_ a: Int64, _ b: Int64) { let ra = find(a), rb = find(b); if ra != rb { parent[ra] = rb } }
        var timeLinked = Set<Int64>(), simLinked = Set<Int64>(), tightBurst = Set<Int64>()
        let timed = photos.filter { $0.capturedAt != nil }.sorted { $0.capturedAt! < $1.capturedAt! }
        for (a, b) in zip(timed, timed.dropFirst()) where a.camera == b.camera && b.capturedAt!.timeIntervalSince(a.capturedAt!) <= burstGapSeconds {
            union(a.id, b.id); timeLinked.insert(a.id); timeLinked.insert(b.id)
            if let sa = signals[a.id], let sb = signals[b.id], Signals.hamming(sa.dhash, sb.dhash) <= 20 { tightBurst.insert(a.id); tightBurst.insert(b.id) }
        }
        for i in 0..<photos.count { for j in (i + 1)..<max(i + 1, photos.count) {
            guard let a = signals[photos[i].id], let b = signals[photos[j].id] else { continue }
            if Signals.hamming(a.dhash, b.dhash) <= similarMaxHamming && Signals.histogramIntersection(a.histogram, b.histogram) >= similarMinHistogramIntersection {
                union(photos[i].id, photos[j].id); simLinked.insert(photos[i].id); simLinked.insert(photos[j].id) } } }
        var buckets: [Int64: [PhotoRecord]] = [:]; for p in photos { buckets[find(p.id), default: []].append(p) }
        return buckets.values.filter { $0.count > 1 }.map { members in
            let ids = members.map { $0.id }
            let isBurst = ids.contains { timeLinked.contains($0) }
            let tight = isBurst && ids.filter({ timeLinked.contains($0) }).allSatisfy { tightBurst.contains($0) }
            return SuggestedGroup(kind: isBurst ? .burst : .similar, confidence: isBurst ? (tight ? .likely : .weak) : .weak,
                                  reason: isBurst ? LF("Cadre consecutive la ≤%@ s de același aparat", Int(burstGapSeconds)) : LF("Aspect apropiat (dHash ≤%@, histogramă ≥%@)", similarMaxHamming, similarMinHistogramIntersection),
                                  memberIds: members.sorted { ($0.capturedAt ?? .distantPast, $0.path) < ($1.capturedAt ?? .distantPast, $1.path) }.map { $0.id })
        }.sorted { $0.memberIds[0] < $1.memberIds[0] }
    }
}
