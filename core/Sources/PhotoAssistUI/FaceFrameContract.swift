import Foundation
import CoreGraphics
import AppKit
import PhotoCore
import PhotoResolve

/// CONTRACT al coordonatelor de față/ochi (lupă și ținte).
///  · Intrare: casete Vision normalizate 0…1, origine sus-stânga, în cadrul previzualizării `.view` (JPEG încorporat, orientare EXIF aplicată de ImageIO).
///  · Cadrul SURSĂ al aplicației: RAW orientat (LibRaw `flip`) și decupat implicit, necropat de utilizator (`Geometry` neutră). Casetele se mapează în cadrul de ieșire DOAR prin `GeoMap` (rotire 90°, oglindire, rotire fină, decupare, perspectivă, scară, deformare de lentilă).
///  · Condiție de validitate (verificată, nu presupusă): (1) previzualizarea și sursa au aceeași proporție (±1,5%) — altfel câmpuri de vedere diferite; (2) conținutul lor (luminanță 24×24) corelează în orientarea identică mai bine decât în oricare din celelalte 7 transformări dihedrale (prinde 180°, oglindiri, transpuneri pe care proporția nu le vede). Fără verdict «ok» țintele de față/ochi NU se oferă; lupa manuală rămâne.
///  · Limite: nu se verifică decuparea parțială a previzualizării cu proporție păstrată; un conținut prea uniform dă verdict «insuficient».
enum FaceFrameContract {
    static let aspectTolerance = 0.015
    static let minCorrelation = 0.6
    static let side = 24
    enum Verdict: Equatable {
        case ok(correlation: Double)
        case aspectMismatch(preview: Double, source: Double)
        case orientationMismatch(best: String, correlation: Double)
        case insufficient(correlation: Double)
        var isOK: Bool { if case .ok = self { return true }; return false }
        var message: String {
            switch self {
            case .ok(let c): return String(format: L("Cadru față↔sursă verificat (corelație %.2f)."), c)
            case .aspectMismatch(let p, let s): return String(format: L("Previzualizarea (%.3f) și sursa (%.3f) au proporții diferite: țintele de față nu se oferă."), p, s)
            case .orientationMismatch(let b, let c): return String(format: L("Orientarea previzualizării nu coincide cu sursa (cea mai bună: %@, corelație %.2f): țintele de față nu se oferă."), b, c)
            case .insufficient(let c): return String(format: L("Verificare neconcludentă (corelație %.2f, conținut prea uniform sau diferit): țintele de față nu se oferă."), c)
            }
        }
    }
    static let names = ["identitate", L("rotire 90° orar"), L("rotire 180°"), L("rotire 90° antiorar"), L("oglindire orizontală"), L("oglindire verticală"), "transpunere", "anti-transpunere"]
    /// Luminanță side×side (imaginea e întinsă pe pătrat: cadre cu aceeași proporție se aliniază).
    static func luma(_ cg: CGImage) -> [Double] {
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.interpolationQuality = .medium; ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        return (0..<(side * side)).map { 0.2126 * Double(px[4 * $0]) + 0.7152 * Double(px[4 * $0 + 1]) + 0.0722 * Double(px[4 * $0 + 2]) }
    }
    /// Transformarea dihedrală t (0…7) a unei grile side×side: rezultat[y][x] = sursă[...]
    static func transform(_ l: [Double], _ t: Int) -> [Double] {
        let n = side; var o = [Double](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n {
            let (sx, sy): (Int, Int)
            switch t { case 0: (sx, sy) = (x, y); case 1: (sx, sy) = (y, n - 1 - x); case 2: (sx, sy) = (n - 1 - x, n - 1 - y); case 3: (sx, sy) = (n - 1 - y, x)
            case 4: (sx, sy) = (n - 1 - x, y); case 5: (sx, sy) = (x, n - 1 - y); case 6: (sx, sy) = (y, x); default: (sx, sy) = (n - 1 - y, n - 1 - x) }
            o[y * n + x] = l[sy * n + sx] } }
        return o
    }
    static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }; let n = Double(a.count); let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var sab = 0.0, saa = 0.0, sbb = 0.0; for i in 0..<a.count { let x = a[i] - ma, y = b[i] - mb; sab += x * y; saa += x * x; sbb += y * y }
        return saa > 1e-9 && sbb > 1e-9 ? sab / (saa * sbb).squareRoot() : 0
    }
    static func check(previewLuma: [Double], sourceLuma: [Double], previewSize: CGSize, sourceSize: CGSize) -> Verdict {
        guard previewSize.width > 0, previewSize.height > 0, sourceSize.width > 0, sourceSize.height > 0 else { return .insufficient(correlation: 0) }
        let pa = Double(previewSize.width / previewSize.height), sa = Double(sourceSize.width / sourceSize.height)
        if abs(pa / sa - 1) > aspectTolerance { return .aspectMismatch(preview: pa, source: sa) }
        let c = (0..<8).map { correlation(transform(previewLuma, $0), sourceLuma) }
        let best = c.indices.max { c[$0] < c[$1] }!
        if best != 0 && c[best] > c[0] + 0.05 { return .orientationMismatch(best: names[best], correlation: c[best]) }
        return c[0] >= minCorrelation ? .ok(correlation: c[0]) : .insufficient(correlation: c[0])
    }
}

extension EditingModel {
    /// Verifică (o dată per fotografie) că cadrul analizei de fețe coincide cu cadrul sursă: randează sursa fără geometrie la previzualizare și o compară cu previzualizarea `.view`.
    func verifyFaceFrame(preview: NSImage?) async {
        guard let p = current, let preview = preview, let pcg = preview.cgImage(forProposedRect: nil, context: nil, hints: nil), faceFrameVerdict[p.id] == nil, isReady else { return }
        do {
            var a = AdjustmentSet.neutral(adjustments.family); a.drtProfile = 0
            let r = try await process(p, a, .preview); guard let img = ResultImage.load(r.url), let scg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let v = FaceFrameContract.check(previewLuma: FaceFrameContract.luma(pcg), sourceLuma: FaceFrameContract.luma(scg), previewSize: CGSize(width: pcg.width, height: pcg.height), sourceSize: CGSize(width: scg.width, height: scg.height))
            faceFrameVerdict[p.id] = v; DiagnosticLog.shared?.log(.info, "faceframe", "verdict", v.message)
        } catch { }
    }
}
