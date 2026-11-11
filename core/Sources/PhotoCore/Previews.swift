import Foundation
import ImageIO
import CoreGraphics

/// Previzualizarea folosită la parcurgere. `source` precizează ce e: NU e rezultatul exportului final.
public struct PreviewImage { public let image: CGImage; public let source: String; public let seconds: Double
    public init(image: CGImage, source: String, seconds: Double) { self.image = image; self.source = source; self.seconds = seconds } }

public protocol PreviewProvider { func preview(for url: URL, maxPixel: Int) throws -> PreviewImage? }

/// Implementare cu ImageIO (sistem, fără dependențe): cere miniatura/previzualizarea încorporată în fișier și NU developează RAW-ul dacă lipsește (`CreateThumbnailFromImageIfAbsent` = false).
public struct EmbeddedPreviewProvider: PreviewProvider {
    public init() {}
    public func preview(for url: URL, maxPixel: Int) throws -> PreviewImage? {
        let t0 = Date()
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageIfAbsent: false, kCGImageSourceCreateThumbnailFromImageAlways: false,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceCreateThumbnailWithTransform: true]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return PreviewImage(image: img, source: "embedded-camera", seconds: Date().timeIntervalSince(t0))
    }
}

public enum PreviewKind: String, CaseIterable, Sendable {
    case filmstrip, grid, view, detail      // detail = 100% (încărcat doar la cerere; rezoluție completă din cameră sau developare a aplicației)
    public var maxPixel: Int { switch self { case .filmstrip: return 144; case .grid: return 420; case .view: return 1400; case .detail: return Int.max } }
}

/// Cache incremental de miniaturi/previzualizări: fișiere JPEG în `directory` (sub rădăcina de date, NU lângă originale), metadate în catalog.
/// Intrarea e validă doar dacă (mărime, mtime) al originalului coincid cu cele din momentul generării ȘI fișierul există. La cerere: se generează doar ce lipsește;
/// dimensiunile mici derivă din „view” când acesta e deja în cache (fără a redeschide RAW-ul).
public final class PreviewCache {
    public struct Stats: Equatable { public var hits = 0, generated = 0, derived = 0, failed = 0 }
    public private(set) var stats = Stats()
    private let catalog: Catalog, directory: URL, provider: PreviewProvider, detailProvider: PreviewProvider?
    public init(catalog: Catalog, directory: URL, provider: PreviewProvider = EmbeddedPreviewProvider(), detailProvider: PreviewProvider? = nil) throws {
        self.catalog = catalog; self.directory = directory; self.provider = provider; self.detailProvider = detailProvider
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public func fileURL(photo: PhotoRecord, kind: PreviewKind) -> URL { directory.appendingPathComponent("\(photo.id)_\(kind.rawValue).jpg") }

    /// Întoarce URL-ul fișierului din cache (generându-l la cerere) sau nil dacă originalul nu are previzualizare încorporată.
    @discardableResult
    public func url(for photo: PhotoRecord, kind: PreviewKind) throws -> URL? {
        if let c = try catalog.cachedPreview(photoId: photo.id, kind: kind.rawValue), c.forSize == photo.size, c.forMtimeNs == photo.mtimeNs, FileManager.default.fileExists(atPath: directory.appendingPathComponent(c.file).path) {
            stats.hits += 1; return directory.appendingPathComponent(c.file)
        }
        var image: CGImage?; var source = "embedded-camera"
        if kind != .view && kind != .detail, let v = try catalog.cachedPreview(photoId: photo.id, kind: PreviewKind.view.rawValue), v.forSize == photo.size, v.forMtimeNs == photo.mtimeNs,
           let img = Self.load(directory.appendingPathComponent(v.file)) { image = Self.scale(img, maxPixel: kind.maxPixel); source = v.source; stats.derived += 1 }
        if image == nil {
            guard let p = try (RenderedImage.isRendered(path: photo.path) ? RenderedPreviewProvider() : (kind == .detail ? (detailProvider ?? provider) : provider) as PreviewProvider).preview(for: URL(fileURLWithPath: photo.path), maxPixel: kind.maxPixel) else { stats.failed += 1; return nil }
            image = p.image; source = p.source; stats.generated += 1
        }
        let file = "\(photo.id)_\(kind.rawValue).jpg"; let dest = directory.appendingPathComponent(file)
        try Self.writeJPEG(image!, to: dest)
        try catalog.storePreview(photoId: photo.id, kind: kind.rawValue, .init(file: file, w: image!.width, h: image!.height, source: source, forSize: photo.size, forMtimeNs: photo.mtimeNs))
        return dest
    }
    /// Șterge fișierele orfane raportate de `Catalog.importFiles` (fișiere schimbate). Doar în `directory`.
    public func purge(files: [String]) { for f in files { try? FileManager.default.removeItem(at: directory.appendingPathComponent((f as NSString).lastPathComponent)) } }

    public static func load(_ url: URL) -> CGImage? { CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } }
    static func scale(_ img: CGImage, maxPixel: Int) -> CGImage {
        let s = min(1.0, Double(maxPixel) / Double(max(img.width, img.height))); if s >= 1 { return img }
        let w = max(1, Int(Double(img.width) * s)), h = max(1, Int(Double(img.height) * s))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: img.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.interpolationQuality = .high; ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return ctx.makeImage() ?? img
    }
    static func writeJPEG(_ img: CGImage, to url: URL) throws {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { throw CatalogError.invalid("nu pot scrie \(url.path)") }
        CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(d) else { throw CatalogError.invalid(LF("JPEG eșuat %@", url.path)) }
    }
}
