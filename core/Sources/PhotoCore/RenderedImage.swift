import Foundation
import ImageIO
import CoreGraphics

/// Intrare DISPLAY-REFERRED (PNG/JPEG/TIFF), cale EXPLICITĂ și separată de RAW (autorizată de proprietar pentru demonstrații, 2026-10-23).
/// NU e RAW și NU e lumină de scenă recuperată: fără normalizare RAW, fără metadate de cameră inventate, fără DRT peste o imagine deja redată.
/// Culoare: profilul ICC încorporat se respectă (conversie CoreGraphics în sRGB); fără profil ⇒ se ASUMĂ sRGB ca alegere de demonstrație (înregistrată, nu «detectată»).
public struct RenderedInfo: Equatable, Sendable {
    public var format: String            // PNG | JPEG | TIFF
    public var width: Int, height: Int
    public var profileName: String?      // numele profilului încorporat, dacă există
    public var profileDetected: Bool     // true = profil ICC citit din fișier
    public var assumption: String?       // ex. «sRGB asumat (alegere de demonstrație; fișierul nu are profil)»
    public var summary: String { profileDetected ? LF("profil încorporat: %@ → sRGB", profileName ?? "ICC") : (assumption ?? "sRGB asumat") }
}

public enum RenderedImage {
    public static let extensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff"]
    public static func isRendered(path: String) -> Bool { extensions.contains((path as NSString).pathExtension.lowercased()) }
    public struct LoadError: Error, CustomStringConvertible { public var description: String }

    /// Încarcă imaginea orientată (EXIF), la rezoluție plină, convertită în sRGB 16 biți (fără canal alfa: aplatizat pe negru).
    public static func load(url: URL) throws -> (image: CGImage, info: RenderedInfo) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 else { throw LoadError(description: L("fișier ilizibil sau format neacceptat")) }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard w > 0, h > 0 else { throw LoadError(description: "dimensiuni invalide") }
        let profile = props[kCGImagePropertyProfileName] as? String
        let uti = (CGImageSourceGetType(src) as String?) ?? ""
        let fmt = uti.contains("png") ? "PNG" : (uti.contains("jpeg") ? "JPEG" : (uti.contains("tiff") ? "TIFF" : uti))
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max(w, h), kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        guard var img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw LoadError(description: L("decodare eșuată")) }
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        var info = RenderedInfo(format: fmt, width: img.width, height: img.height, profileName: profile, profileDetected: profile != nil, assumption: nil)
        if profile == nil {
            info.assumption = L("sRGB asumat (alegere de demonstrație; fișierul nu are profil ICC)")
            if let a = img.copy(colorSpace: srgb) { img = a }
        }
        let bytesPerRow = img.width * 8
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 16, bytesPerRow: bytesPerRow, space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue) else { throw LoadError(description: "context de culoare indisponibil") }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        guard let out = ctx.makeImage() else { throw LoadError(description: L("conversie de culoare eșuată")) }
        return (out, info)
    }

    /// RGB float (0…1, codat sRGB) din imaginea convertită, pentru procesare geometrică.
    public static func floatRGB(url: URL) throws -> (rgb: [Float], width: Int, height: Int, info: RenderedInfo) {
        let (img, info) = try load(url: url); let w = img.width, h = img.height
        guard let data = img.dataProvider?.data as Data?, data.count >= w * h * 8 else { throw LoadError(description: "date de pixeli indisponibile") }
        var rgb = [Float](repeating: 0, count: w * h * 3); let inv: Float = 1 / 65535
        data.withUnsafeBytes { raw in let p = raw.bindMemory(to: UInt16.self)
            let rowStride = img.bytesPerRow / 2
            for y in 0..<h { for x in 0..<w { let i = y * rowStride + x * 4; let o = (y * w + x) * 3
                rgb[o] = Float(UInt16(littleEndian: p[i])) * inv; rgb[o + 1] = Float(UInt16(littleEndian: p[i + 1])) * inv; rgb[o + 2] = Float(UInt16(littleEndian: p[i + 2])) * inv } } }
        return (rgb, w, h, info)
    }
}

/// Previzualizări pentru intrările redate: aceeași conversie de culoare ca la procesare (ICC → sRGB), apoi scalare; sursa e etichetată «rendered-source» (NU «embedded-camera»).
public struct RenderedPreviewProvider: PreviewProvider {
    public init() {}
    public func preview(for url: URL, maxPixel: Int) throws -> PreviewImage? {
        let t0 = Date(); let (img, _) = try RenderedImage.load(url: url)
        let out = maxPixel >= max(img.width, img.height) ? img : PreviewCache.scale(img, maxPixel: maxPixel)
        return PreviewImage(image: out, source: "rendered-source", seconds: Date().timeIntervalSince(t0))
    }
}
