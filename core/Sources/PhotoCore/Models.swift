import Foundation

/// Starea unei fotografii în catalogul sesiunii. „Respinge” e REVERSIBILĂ și nu atinge fișierul de pe disc.
public enum Decision: String, CaseIterable, Sendable { case check, keep, reject }

public struct PhotoRecord: Equatable, Sendable {
    public var id: Int64
    public var path: String
    public var size: Int64
    public var mtimeNs: Int64
    public var decision: Decision
    public var rating: Int          // 0...5
    public var favorite: Bool
    public var groupId: Int64?      // grup de cadre similare (sugestie, setat de analiză)
    public var camera: String?
    public var capturedAt: Date?
    public var previewSource: String?   // ex. "embedded-camera" — NU e rezultatul exportului final
    /// Intrare display-referred (PNG/JPEG/TIFF), nu RAW: se deduce din extensie (fără schimbare de schemă).
    public var isRendered: Bool { RenderedImage.isRendered(path: path) }
}

public enum CatalogError: Error, Equatable { case open(String), sql(String), invalid(String) }
