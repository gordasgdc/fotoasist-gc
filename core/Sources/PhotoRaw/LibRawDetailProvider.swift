import Foundation
import CoreGraphics
import PhotoCore

/// Furnizor pentru „100%”: previzualizarea încorporată de cameră DACĂ are rezoluție aproape completă („camera-full”); altfel o developare a APLICAȚIEI din RAW („app-developed-libraw”,
/// LibRaw, balans de cameră, 8 biți). Sursa se înregistrează în cache și se arată utilizatorului; niciuna nu e rezultatul exportului final.
public struct LibRawDetailProvider: PreviewProvider {
    public init() {}
    public func preview(for url: URL, maxPixel: Int) throws -> PreviewImage? {
        let t0 = Date(); let f = try RawFile(path: url.path); let i = f.info
        if let img = try? f.embeddedPreview(), Double(max(img.width, img.height)) >= 0.9 * Double(max(i.visibleWidth, i.visibleHeight)) {
            return PreviewImage(image: img, source: "camera-full", seconds: Date().timeIntervalSince(t0))
        }
        let f2 = try RawFile(path: url.path)      // instanță nouă: developarea cere un fișier neatins de unpack_thumb
        return PreviewImage(image: try f2.developedPreview(halfSize: false), source: "app-developed-libraw", seconds: Date().timeIntervalSince(t0))
    }
}
