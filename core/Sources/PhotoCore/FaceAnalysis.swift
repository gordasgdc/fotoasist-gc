import Foundation
import CoreGraphics
import Vision

/// Localizare de fețe și ochi cu Vision (model preantrenat de sistem, local, fără rețea, fără identitate). Rezultatele sunt OBSERVAȚII + sugestii: localizarea ochilor NU dovedește focalizarea sau clipirea;
/// raportul de deschidere (înălțime/lățime a conturului ochiului) e un indiciu, cu stare „incert” între praguri. Pragurile sunt valori inițiale de EVALUAT pe exemple etichetate (docs/MATERIALS_PROTOCOL.md).
public struct EyeObservation: Equatable { public var box: CGRect; public var openness: Double; public init(box: CGRect, openness: Double) { self.box = box; self.openness = openness } }   // box normalizat 0…1, origine sus-stânga; openness = h/l a punctelor conturului
public enum EyeState: String { case open, closed, uncertain, notEvaluated }
public struct FaceObservation: Equatable {
    public var box: CGRect; public var confidence: Float; public var roll: Double?; public var yaw: Double?; public var captureQuality: Float?
    public var left: EyeObservation?; public var right: EyeObservation?
}
public enum FaceAnalyzer {
    public static let openMin = 0.22, closedMax = 0.12        // praguri inițiale, de evaluat; între ele = incert
    public static func eyeState(_ e: EyeObservation?) -> EyeState { guard let e = e else { return .notEvaluated }; return e.openness >= openMin ? .open : (e.openness <= closedMax ? .closed : .uncertain) }
    /// Sugestie pe față: „posibilă clipire” doar dacă ambii ochi localizați par închiși; un singur ochi sau stare incertă ⇒ incert; fără ochi ⇒ neevaluat.
    public static func blinkSuggestion(_ f: FaceObservation) -> (state: EyeState, text: String) {
        let l = eyeState(f.left), r = eyeState(f.right)
        if l == .notEvaluated && r == .notEvaluated { return (.notEvaluated, L("ochi neevaluați")) }
        if l == .closed && r == .closed { return (.closed, L("posibilă clipire (ambii ochi par închiși; poate fi intenționat)")) }
        if l == .open && r == .open { return (.open, L("ochi deschiși")) }
        return (.uncertain, L("incert (ochi parțial închiși, un singur ochi localizat sau unghi nefavorabil)"))
    }
    public static func analyze(_ image: CGImage, cpuOnly: Bool = false) throws -> [FaceObservation] {
        let req = VNDetectFaceLandmarksRequest(); if cpuOnly { req.usesCPUOnly = true }
        let qreq = VNDetectFaceCaptureQualityRequest(); if cpuOnly { qreq.usesCPUOnly = true }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
        let qres: [VNFaceObservation] = ((try? VNImageRequestHandler(cgImage: image, options: [:]).perform([qreq])) != nil) ? (qreq.results ?? []) : []   // eșecul calității nu strică restul analizei
        func quality(_ b: CGRect) -> Float? { qres.min { hypot($0.boundingBox.midX - b.midX, $0.boundingBox.midY - b.midY) < hypot($1.boundingBox.midX - b.midX, $1.boundingBox.midY - b.midY) }.flatMap { o in hypot(o.boundingBox.midX - b.midX, o.boundingBox.midY - b.midY) < 0.5 * max(b.width, b.height) ? o.faceCaptureQuality : nil } }
        func eye(_ r: VNFaceLandmarkRegion2D?, _ face: CGRect) -> EyeObservation? {
            guard let r = r, r.pointCount >= 4 else { return nil }
            let pts = r.normalizedPoints.map { CGPoint(x: face.minX + $0.x * face.width, y: face.minY + $0.y * face.height) }   // în coordonatele imaginii (Vision: origine jos-stânga)
            let xs = pts.map { $0.x }, ys = pts.map { $0.y }; let w = xs.max()! - xs.min()!, h = ys.max()! - ys.min()!; guard w > 0 else { return nil }
            return EyeObservation(box: CGRect(x: xs.min()!, y: 1 - ys.max()!, width: w, height: h), openness: Double(h / w))
        }
        return (req.results ?? []).map { o in
            let fb = o.boundingBox
            return FaceObservation(box: CGRect(x: fb.minX, y: 1 - fb.maxY, width: fb.width, height: fb.height), confidence: o.confidence, roll: o.roll?.doubleValue, yaw: o.yaw?.doubleValue, captureQuality: quality(fb),
                                   left: eye(o.landmarks?.leftEye, fb), right: eye(o.landmarks?.rightEye, fb))
        }
    }
    /// Claritate LOCALĂ într-o zonă normalizată (indicată de fotograf sau o față): energia gradientului pe luminanță, normalizată cu zgomotul estimat din zona cea mai netedă a aceleiași zone. Comparabilă doar între cadre ale aceluiași grup, pe aceeași zonă.
    public static func localSharpness(_ image: CGImage, region: CGRect) -> (value: Double, noise: Double)? {
        let W = image.width, H = image.height; let x0 = max(0, Int(region.minX * Double(W))), y0 = max(0, Int(region.minY * Double(H))), x1 = min(W, Int(region.maxX * Double(W))), y1 = min(H, Int(region.maxY * Double(H)))
        guard x1 - x0 > 8, y1 - y0 > 8, let crop = image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { return nil }
        let w = crop.width, h = crop.height; var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        var l = [Float](repeating: 0, count: w * h); for i in 0..<(w * h) { l[i] = 0.2126 * Float(px[4 * i]) + 0.7152 * Float(px[4 * i + 1]) + 0.0722 * Float(px[4 * i + 2]) }
        var g: [Float] = []; for y in 1..<(h - 1) { for x in 1..<(w - 1) { let gx = l[y * w + x + 1] - l[y * w + x - 1], gy = l[(y + 1) * w + x] - l[(y - 1) * w + x]; g.append(sqrtf(gx * gx + gy * gy)) } }
        guard g.count > 16 else { return nil }; let s = g.sorted(); let noise = Double(s[g.count / 10]); let top = Double(s[g.count * 9 / 10])   // zgomot ≈ percentila 10; claritate = percentila 90 a gradientului
        return (top, noise)
    }
}

/// Calitatea de captură a feței (Vision `VNDetectFaceCaptureQualityRequest`, local): scor RELATIV 0…1 care combină claritatea, expunerea, poziția și expresia feței; NU e focalizarea pe ochi și nu e un verdict.
/// Pe fețe mici (< ~4% din înălțime) sau în profil e mai puțin de încredere. Folosit doar ca indiciu, în explicații; decizia rămâne a fotografului.
public enum FaceQualityCompare {
    public static let minFaceHeight = 0.04, margin: Float = 0.10
    /// Cea mai mare față a cadrului (calitatea ei), sau nil dacă nu e evaluabilă (fără față, calitate lipsă, față prea mică).
    public static func representative(_ faces: [FaceObservation]) -> Float? {
        guard let f = faces.max(by: { $0.box.height < $1.box.height }), f.box.height >= minFaceHeight else { return nil }; return f.captureQuality
    }
    /// Cadrul „mai promițător” al unui grup: doar dacă ≥ 2 cadre au calitate evaluabilă și cel mai bun depășește al doilea cu `margin`; altfel nil (incert, nu se evidențiază nimic).
    public static func promising(_ q: [Int64: Float]) -> (id: Int64, lead: Float)? {
        let s = q.sorted { $0.value > $1.value }; guard s.count >= 2, s[0].value - s[1].value >= margin else { return nil }; return (s[0].key, s[0].value - s[1].value)
    }
}
