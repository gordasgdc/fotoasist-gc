import Foundation

/// Rezultatele analizei de fețe, păstrate în catalogul sesiunii (cache VERSIONAT: o schimbare de versiune sau de fișier le invalidează). „Nicio față detectată” = lista goală cu rezultat valid — NU înseamnă fotografie fără persoane și nu e un scor.
public struct StoredEye: Codable, Equatable { public var box: [Double]; public var openness: Double; public init(box: [Double], openness: Double) { self.box = box; self.openness = openness } }
public struct StoredFace: Codable, Equatable { public var box: [Double]; public var confidence: Float; public var roll: Double?; public var yaw: Double?; public var left: StoredEye?; public var right: StoredEye?
    /// Calitatea de captură Vision (0…1); lipsă la rezultatele salvate înainte de versiunea 2.
    public var captureQuality: Float?
    public init(box: [Double], confidence: Float, roll: Double?, yaw: Double?, left: StoredEye?, right: StoredEye?, captureQuality: Float? = nil) { self.box = box; self.confidence = confidence; self.roll = roll; self.yaw = yaw; self.left = left; self.right = right; self.captureQuality = captureQuality } }
public struct FaceResult: Codable, Equatable {
    public var version: Int; public var size: Int64; public var mtimeNs: Int64; public var previewW: Int; public var previewH: Int
    public var faces: [StoredFace]; public var seconds: Double; public var config: String
    public init(version: Int, size: Int64, mtimeNs: Int64, previewW: Int, previewH: Int, faces: [StoredFace], seconds: Double, config: String) { self.version = version; self.size = size; self.mtimeNs = mtimeNs; self.previewW = previewW; self.previewH = previewH; self.faces = faces; self.seconds = seconds; self.config = config }
}
/// Subiectul prioritar ales de fotograf: o față detectată, o zonă manuală (și când Vision nu găsește nicio față) sau nimic. `dismissed` = sugestiile ascunse pentru cadru (reversibil).
public struct SubjectState: Codable, Equatable, Hashable { public var kind: String = "none"; public var face: Int?; public var zone: [Double]?; public var dismissed = false
    public init() {}
    public static func face(_ i: Int) -> SubjectState { var s = SubjectState(); s.kind = "face"; s.face = i; return s }
    public static func zone(_ r: [Double]) -> SubjectState { var s = SubjectState(); s.kind = "zone"; s.zone = r; return s }
}
extension FaceAnalyzer {
    public static let version = 2     // 2: păstrează și calitatea de captură a feței
    /// Configurația CERUTĂ (nu procesorul efectiv, care rămâne necunoscut): Vision, revizia implicită a sistemului.
    public static let configLabel = "Vision VNDetectFaceLandmarksRequest, calcul implicit (procesor efectiv neidentificat)"
    public static func stored(_ f: FaceObservation) -> StoredFace {
        func r(_ x: CGRect) -> [Double] { [Double(x.minX), Double(x.minY), Double(x.width), Double(x.height)] }
        return StoredFace(box: r(f.box), confidence: f.confidence, roll: f.roll, yaw: f.yaw, left: f.left.map { StoredEye(box: r($0.box), openness: $0.openness) }, right: f.right.map { StoredEye(box: r($0.box), openness: $0.openness) }, captureQuality: f.captureQuality)
    }
    public static func observation(_ s: StoredFace) -> FaceObservation {
        func e(_ x: StoredEye?) -> EyeObservation? { x.map { EyeObservation(box: CGRect(x: $0.box[0], y: $0.box[1], width: $0.box[2], height: $0.box[3]), openness: $0.openness) } }
        return FaceObservation(box: CGRect(x: s.box[0], y: s.box[1], width: s.box[2], height: s.box[3]), confidence: s.confidence, roll: s.roll, yaw: s.yaw, captureQuality: s.captureQuality, left: e(s.left), right: e(s.right))
    }
}
extension Catalog {
    /// Rezultatul valid pentru fotografie (aceeași versiune, același fișier) sau nil.
    public func faceResult(for p: PhotoRecord) -> FaceResult? {
        guard let j = (try? session("faces:\(p.id)")) ?? nil, let r = try? JSONDecoder().decode(FaceResult.self, from: Data(j.utf8)), r.version == FaceAnalyzer.version, r.size == p.size, r.mtimeNs == p.mtimeNs else { return nil }; return r
    }
    public func setFaceResult(_ r: FaceResult, photoId: Int64) throws { if let d = try? JSONEncoder().encode(r), let s = String(data: d, encoding: .utf8) { try setSession("faces:\(photoId)", s) } }
    public func subject(photoId: Int64) -> SubjectState { ((try? session("subject:\(photoId)")) ?? nil).flatMap { try? JSONDecoder().decode(SubjectState.self, from: Data($0.utf8)) } ?? SubjectState() }
    public func setSubject(_ s: SubjectState, photoId: Int64) throws { if let d = try? JSONEncoder().encode(s), let j = String(data: d, encoding: .utf8) { try setSession("subject:\(photoId)", j) } }
}
