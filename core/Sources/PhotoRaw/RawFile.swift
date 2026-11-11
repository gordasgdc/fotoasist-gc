import Foundation
import CoreGraphics
import ImageIO
import CLibRaw

public enum RawError: Error, Equatable { case open(Int32, String), unpack(Int32), noThumbnail, process(Int32) }

/// Informații citite din fișierul RAW prin LibRaw (versiune fixată, dylib propriu). NU developează nimic aici.
public struct RawInfo: Equatable {
    public var make: String, model: String
    public var iso: Float, rawWidth: Int, rawHeight: Int, visibleWidth: Int, visibleHeight: Int, flip: Int
    public var blackLevel: Int, whiteLevel: Int          // `maximum` raportat de LibRaw (limita de liniaritate folosită la scalare)
    public var cameraWB: [Float]
    public var thumbnailFormat: String, thumbnailWidth: Int, thumbnailHeight: Int, thumbnailBytes: Int
}

/// Dreptunghi în coordonatele BUFFERULUI RAW complet (raw_width × raw_height), origine sus-stânga.
public struct PixelRect: Equatable, Codable { public var x: Int, y: Int, w: Int, h: Int
    public var isEmpty: Bool { w <= 0 || h <= 0 }
    public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h } }

/// Geometria raportată de LibRaw (fără a decide nimic): zona activă a decodorului, decuparea implicită a producătorului (dacă există), indiciul de aspect.
public struct RawGeometry: Equatable {
    public var rawWidth: Int, rawHeight: Int
    public var activeArea: PixelRect          // `sizes.left_margin/top_margin/width/height` (ce developează LibRaw)
    public var insetCrops: [PixelRect]        // `sizes.raw_inset_crops` (necompletat = gol)
    public var makerDefaultCrop: PixelRect?   // DefaultCropAbsolute (Canon), dacă e completat
    public var makerRecommendedArea: PixelRect? // RecommendedImageArea (Canon), dacă e completat
    public var rawAspect: Int                 // `sizes.raw_aspect` (cod LibRaw; 0 = necunoscut)
}

public struct RawSaturation: Equatable {
    public var maxRaw: Int, mostFrequentTop: Int, countAtMostFrequentTop: Int, whiteLevelReported: Int
    public var spikeAboveReportedWhite: Bool { mostFrequentTop > whiteLevelReported + 4 && countAtMostFrequentTop > 100 }
}

public final class RawFile {
    private let lr: UnsafeMutablePointer<libraw_data_t>
    public let path: String
    public static var libraryVersion: String { String(cString: libraw_version()) }

    public init(path: String) throws {
        guard let p = libraw_init(0) else { throw RawError.open(-1, "libraw_init") }
        lr = p; self.path = path
        let rc = libraw_open_file(lr, path)
        if rc != 0 { throw RawError.open(rc, String(cString: libraw_strerror(rc))) }   // deinit închide o singură dată
    }
    deinit { libraw_close(lr) }

    public var info: RawInfo {
        // NU se copiază libraw_data_t întreg (sute de KB: ar depăși stiva firelor GCD); se citesc câmpurile direct prin pointer.
        func str<T>(_ t: T) -> String { withUnsafeBytes(of: t) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) } }
        let tf: String = { switch lr.pointee.thumbnail.tformat { case LIBRAW_THUMBNAIL_JPEG: return "jpeg"; case LIBRAW_THUMBNAIL_BITMAP: return "bitmap"; case LIBRAW_THUMBNAIL_BITMAP16: return "bitmap16"; default: return "none" } }()
        let cm = withUnsafeBytes(of: lr.pointee.color.cam_mul) { Array($0.bindMemory(to: Float.self).prefix(4)) }
        return RawInfo(make: str(lr.pointee.idata.make), model: str(lr.pointee.idata.model), iso: lr.pointee.other.iso_speed, rawWidth: Int(lr.pointee.sizes.raw_width), rawHeight: Int(lr.pointee.sizes.raw_height),
                       visibleWidth: Int(lr.pointee.sizes.width), visibleHeight: Int(lr.pointee.sizes.height), flip: Int(lr.pointee.sizes.flip), blackLevel: Int(lr.pointee.color.black), whiteLevel: Int(lr.pointee.color.maximum),
                       cameraWB: cm, thumbnailFormat: tf, thumbnailWidth: Int(lr.pointee.thumbnail.twidth), thumbnailHeight: Int(lr.pointee.thumbnail.theight), thumbnailBytes: Int(lr.pointee.thumbnail.tlength))
    }

    var geometryFlip: Int32 { lr.pointee.sizes.flip }

    /// (negru mediu, negru întreg, alb declarat, max ADC, cam_mul[4], XYZ→cameră 3×3 rând-major)
    /// Compensarea de expunere a RAW declarată de cameră, în EV (Fuji: tag 0x9650 `RawExposureBias`, LibRaw `ExpoMidPointShift`; negativ = fișierul RAW e mai întunecat decât redarea camerei, ex. DR200 ⇒ −1.72).
    /// Numai Fuji și numai când valoarea există și e finită: pentru alte mărci semantica NU e verificată (LibRaw o notează și pentru Canon HTP / Nikon HLG, dar nu s-a confirmat aici). LibRaw nu o aplică singur.
    public var cameraExposureShift: Double? {
        guard info.make.uppercased().contains("FUJI") else { return nil }
        let v = Double(lr.pointee.makernotes.fuji.ExpoMidPointShift); return v.isFinite && v > -20 && v < 20 && v != 0 ? v : nil
    }
    func lrParams(legacy: Bool = false) -> (Double, Int, Int, Int, [Float], [Double], Double) {
        // `cblack[4104]` nu se importă în Swift (tablou prea mare); precede imediat `black` în libraw_colordata_t (verificat: valorile coincid cu rawpy pe toate cele 12 fișiere de probă).
        let cbAll: [UInt32] = withUnsafeMutablePointer(to: &lr.pointee.color.black) { pb in (0..<4104).map { (pb - 4104 + $0).pointee } }
        let cb = Array(cbAll[0..<4])
        // Negrul pe model de pixeli (cblack[4]×cblack[5], valori de la cblack[6]), ca în `subtract_black_internal` din LibRaw: negru(pixel) = black + cblack[canal] + model[rând % cblack[4]][col % cblack[5]].
        // Fuji GFX: cblack[0…3] = 0, modelul 2×2 = 4095. Aici se ia MEDIA; `spread` (max − min peste canale + model) arată cât de puțin reprezintă media: peste prag, apelantul NU folosește piedestal (vezi `decodeLinearDWG`).
        let patW = Int(cbAll[4]), patH = Int(cbAll[5]); let patN = !legacy && patW > 0 && patH > 0 && patW * patH <= 4098 ? patW * patH : 0
        let pat = patN == 0 ? [] : Array(cbAll[6..<(6 + patN)])
        let patMean = pat.isEmpty ? 0.0 : pat.reduce(0.0) { $0 + Double($1) } / Double(pat.count)
        let spread = Double((cb.max() ?? 0) - (cb.min() ?? 0)) + Double((pat.max() ?? 0) - (pat.min() ?? 0))
        let base = Double(lr.pointee.color.black); let black = base + Double(cb.reduce(0, +)) / 4.0 + patMean
        let cm = withUnsafeBytes(of: lr.pointee.color.cam_mul) { Array($0.bindMemory(to: Float.self).prefix(4)) }
        let cx = withUnsafeBytes(of: lr.pointee.color.cam_xyz) { Array($0.bindMemory(to: Float.self).prefix(9)).map { Double($0) } }
        let bps = Int(lr.pointee.color.raw_bps); let adc = (1 << (bps > 0 ? bps : 14)) - 1
        return (black, Int(black.rounded()), Int(lr.pointee.color.maximum), adc, cm, cx, spread)
    }

    /// Configurează LibRaw pentru decodare științifică (fără scalare automată, gamma 1, spațiu cameră, WB neutru — WB se aplică în float) și demosaicează.
    func unpackForDecode() throws { let rc = libraw_unpack(lr); if rc != 0 { throw RawError.unpack(rc) } }   // Canon: nivelul de negru se calculează la unpack (zone mascate)

    func processForDecode(userBlack: Int, halfSize: Bool = false) throws {
        var rc: Int32
        lr.pointee.params.output_color = 0; lr.pointee.params.user_mul = (1, 1, 1, 1); lr.pointee.params.no_auto_scale = 1; lr.pointee.params.no_auto_bright = 1
        lr.pointee.params.gamm.0 = 1; lr.pointee.params.gamm.1 = 1; lr.pointee.params.output_bps = 16; lr.pointee.params.user_black = Int32(userBlack)
        lr.pointee.params.highlight = 0; lr.pointee.params.user_sat = 65535; lr.pointee.params.half_size = halfSize ? 1 : 0; lr.pointee.params.user_flip = 0; lr.pointee.params.use_camera_wb = 0
        rc = libraw_dcraw_process(lr); if rc != 0 { throw RawError.process(rc) }
    }

    func makeMem16() throws -> (Int, Int, [UInt16]) {
        var err: Int32 = 0
        guard let mem = libraw_dcraw_make_mem_image(lr, &err), err == 0 else { throw RawError.process(err) }
        defer { libraw_dcraw_clear_mem(mem) }
        let m = mem.pointee; let w = Int(m.width), h = Int(m.height)
        guard m.type == LIBRAW_IMAGE_BITMAP, m.colors == 3, m.bits == 16 else { throw RawError.process(-2) }
        let n = w * h * 3; var out = [UInt16](repeating: 0, count: n)
        withUnsafePointer(to: &mem.pointee.data) { p in out.withUnsafeMutableBytes { _ = memcpy($0.baseAddress!, UnsafeRawPointer(p), n * 2) } }
        return (w, h, out)
    }

    public var geometry: RawGeometry {
        let sz = lr.pointee.sizes
        func r(_ c: libraw_raw_inset_crop_t) -> PixelRect { PixelRect(x: Int(c.cleft), y: Int(c.ctop), w: Int(c.cwidth), h: Int(c.cheight)) }
        let insets = [r(sz.raw_inset_crops.0), r(sz.raw_inset_crops.1)].filter { !$0.isEmpty }
        func a(_ t: libraw_area_t) -> PixelRect? { let rc = PixelRect(x: Int(t.l), y: Int(t.t), w: Int(t.r) - Int(t.l) + 1, h: Int(t.b) - Int(t.t) + 1); return rc.w > 1 && rc.h > 1 && t.l >= 0 && t.t >= 0 ? rc : nil }
        let mk = lr.pointee.makernotes.canon
        return RawGeometry(rawWidth: Int(sz.raw_width), rawHeight: Int(sz.raw_height),
                           activeArea: PixelRect(x: Int(sz.left_margin), y: Int(sz.top_margin), w: Int(sz.width), h: Int(sz.height)),
                           insetCrops: insets, makerDefaultCrop: a(mk.DefaultCropAbsolute), makerRecommendedArea: a(mk.RecommendedImageArea), rawAspect: Int(sz.raw_aspect))
    }

    /// Previzualizarea încorporată de cameră, la rezoluția în care e stocată (JPEG), ca CGImage cu orientarea aplicată de ImageIO. Sursa: „din cameră, rezoluție completă”.
    public func embeddedPreview() throws -> CGImage {
        var rc = libraw_unpack_thumb(lr); if rc != 0 { throw RawError.noThumbnail }
        var err: Int32 = 0
        guard let mem = libraw_dcraw_make_mem_thumb(lr, &err), err == 0 else { throw RawError.noThumbnail }
        defer { libraw_dcraw_clear_mem(mem) }
        let t = mem.pointee
        if t.type == LIBRAW_IMAGE_JPEG {
            let data = withUnsafePointer(to: &mem.pointee.data) { p in Data(bytes: UnsafeRawPointer(p), count: Int(t.data_size)) }
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 20000] as CFDictionary) else { throw RawError.noThumbnail }
            return img
        }
        rc = -1; _ = rc; throw RawError.noThumbnail
    }

    /// Developare de previzualizare a APLICAȚIEI (LibRaw, balans de cameră, 8 biți, jumătate de rezoluție): NU e previzualizarea camerei și NU e rezultatul exportului final.
    public func developedPreview(halfSize: Bool = true) throws -> CGImage {
        lr.pointee.params.half_size = halfSize ? 1 : 0; lr.pointee.params.use_camera_wb = 1; lr.pointee.params.output_bps = 8; lr.pointee.params.no_auto_bright = 0; lr.pointee.params.user_flip = -1
        var rc = libraw_unpack(lr); if rc != 0 { throw RawError.unpack(rc) }
        rc = libraw_dcraw_process(lr); if rc != 0 { throw RawError.process(rc) }
        var err: Int32 = 0
        guard let mem = libraw_dcraw_make_mem_image(lr, &err), err == 0 else { throw RawError.process(err) }
        defer { libraw_dcraw_clear_mem(mem) }
        let m = mem.pointee; let w = Int(m.width), h = Int(m.height)
        guard m.type == LIBRAW_IMAGE_BITMAP, m.colors == 3, m.bits == 8 else { throw RawError.process(-2) }
        let bytes = w * h * 3
        let data = withUnsafePointer(to: &mem.pointee.data) { p in Data(bytes: UnsafeRawPointer(p), count: bytes) }
        guard let prov = CGDataProvider(data: data as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: w * 3, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw RawError.process(-3) }
        return img
    }

    /// Cea mai frecventă valoare din vârful histogramei brute (spike = tăiere ADC) față de `maximum` raportat: răspunde dacă „nivelul alb” al LibRaw e tăierea reală sau limita de liniaritate.
    public func saturation() throws -> RawSaturation {
        let rc = libraw_unpack(lr); if rc != 0 { throw RawError.unpack(rc) }
        let sz = lr.pointee.sizes; let w = Int(sz.raw_width), h = Int(sz.raw_height); guard let base = lr.pointee.rawdata.raw_image else { throw RawError.unpack(-1) }
        var mx = 0; var hist = [Int](repeating: 0, count: 65536)
        for i in 0..<(w * h) { let v = Int(base[i]); if v > mx { mx = v }; hist[v] += 1 }
        let floor = Int(lr.pointee.color.black) + Int(0.8 * Double(mx - Int(lr.pointee.color.black)))
        var best = 0, bestN = 0; for v in floor...mx where hist[v] > bestN { best = v; bestN = hist[v] }
        return RawSaturation(maxRaw: mx, mostFrequentTop: best, countAtMostFrequentTop: bestN, whiteLevelReported: Int(lr.pointee.color.maximum))
    }
}
