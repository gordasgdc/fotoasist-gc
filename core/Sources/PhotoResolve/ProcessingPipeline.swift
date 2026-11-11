import Foundation
import CryptoKit
import ImageIO
import CoreGraphics
import PhotoRaw
import PhotoCore

public enum ProcessQuality: String, Codable { case preview, full, interactive }   // interactive = previzualizare redusă (≤ ~1400 px latura mare) pentru răspunsul în timpul gestului; se rafinează ulterior cu `preview`   // preview = LibRaw half_size (etichetat „previzualizare”); full = rezoluție plină

public struct ProcessedImage {
    public var url: URL                      // TIFF 16 biți sRGB (fără profil încorporat; profilul se atașează la export)
    public var width: Int, height: Int
    public var quality: ProcessQuality
    public var decode: DecodeReport?         // nil pentru intrările redate (PNG/JPEG/TIFF): nu există decodare RAW
    public var liveness: Double              // diferență medie absolută față de trecerea directă (pass-through ar fi ≈ 0)
    public var decodeSeconds: Double, resolveSeconds: Double
    public var fromIntermediateCache: Bool, fromResultCache: Bool
    public var readBack: [String: Double]
    public var suggestion: ExposureSuggestion?   // doar sugestie; se aplică explicit de utilizator
    public var effectiveExposure: Double         // expunerea efectiv trimisă lanțului (manuală sau estimare + corecție)
    public var sourceWidth = 0, sourceHeight = 0 // dimensiunea sursei decodate (înainte de geometrie), pentru planul de decupare
    public var rendered: RenderedInfo? = nil     // intrare display-referred: profilul/asumția de culoare (nu RAW)
}

public enum PipelineError: Error, CustomStringConvertible {
    case chainInactive(Double), badOutput(String), insideOriginalsFolder, drtData(String), outputExists(String)
    public var description: String {
        switch self {
        case .chainInactive(let d): return "Lanțul GDC nu a participat la randare (diferență \(String(format: "%.4f", d)) față de trecerea directă); rezultatul nu se folosește."
        case .badOutput(let m): return "Rezultat Resolve neutilizabil: \(m)"
        case .drtData(let m): return m
        case .outputExists(let n): return "Omisă: fișierul «\(n)» există deja în destinație (politica aleasă: nu se suprascrie)."
        case .insideOriginalsFolder: return "Destinația exportului este folderul fotografiei originale; alege alt folder (originalele nu se ating)."
        }
    }
}

/// Fotografie → decodare float (LibRaw) → intermediar EXR (cache) → lanț GDC în Resolve → sRGB TIFF 16 biți, cu verificare „liveness”. Nu modifică originalul.
public final class PhotoProcessor {
    public let bridge: ResolveBridge, workDir: URL, projectName: String
    public init(bridge: ResolveBridge, workDir: URL, projectName: String = "GDC_PHOTO_ASSIST_WORK_0001") throws {
        self.bridge = bridge; self.workDir = workDir; self.projectName = projectName
        for d in ["intermediates", "results"] { try FileManager.default.createDirectory(at: workDir.appendingPathComponent(d), withIntermediateDirectories: true) }
    }

    static func hash(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined() }

    struct IntermediateMeta: Codable { var width: Int, height: Int; var thumb: [Float]; var thumbW: Int, thumbH: Int; var reportJSON: String; var suggestion: ExposureSuggestion? }

    public func process(photoPath: String, quality: ProcessQuality, adjustments: AdjustmentSet, decode: DecodeOptions = DecodeOptions()) throws -> ProcessedImage {
        let attrs = try FileManager.default.attributesOfItem(atPath: photoPath)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0, mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        var opt = decode; opt.halfSize = quality == .preview
        let ikey = PhotoProcessor.hash("\(photoPath)|\(size)|\(mtime)|\(quality)|\(opt.white)|\(opt.highlight)|\(opt.wb)|\(opt.crop)|\(opt.applyOrientation)|\(RawFile.libraryVersion)")
        let exr = workDir.appendingPathComponent("intermediates/\(ikey).exr"), meta = workDir.appendingPathComponent("intermediates/\(ikey).json")
        var decodeSeconds = 0.0, cached = true
        var report: DecodeReport; var imeta: IntermediateMeta
        if let d = try? Data(contentsOf: meta), let m = try? JSONDecoder().decode(IntermediateMeta.self, from: d), FileManager.default.fileExists(atPath: exr.path) {
            imeta = m; report = try PhotoProcessor.reportStub(from: m.reportJSON)
        } else {
            cached = false; let t0 = Date()
            let dec = try RawFile(path: photoPath).decodeLinearDWG(opt)
            let sugg = ExposureSuggestion.compute(from: dec.image); let enc = dec.image.diEncoded(); try FloatImageIO.writeEXR(enc, to: exr)
            let th = enc.thumbnail(maxSide: 64)
            imeta = IntermediateMeta(width: enc.width, height: enc.height, thumb: th.rgb, thumbW: th.width, thumbH: th.height, reportJSON: PhotoProcessor.reportJSON(dec.report), suggestion: sugg)
            try JSONEncoder().encode(imeta).write(to: meta); report = dec.report; decodeSeconds = Date().timeIntervalSince(t0)
        }
        let eff = adjustments.effectiveExposure(estimate: imeta.suggestion?.stops)
        let rkey = PhotoProcessor.hash(ikey + "|" + adjustments.fingerprint + "|eff" + String(format: "%.4f", eff))
        let out = workDir.appendingPathComponent("results/\(rkey).tif")
        var resolveSeconds = 0.0, readBack: [String: Double] = [:], fromResult = false
        if FileManager.default.fileExists(atPath: out.path) { fromResult = true }
        else {
            let t0 = Date()
            let chain = adjustments.chain(estimate: imeta.suggestion?.stops).map { ["stage": $0.stage, "params": $0.params] as [String: Any] }
            let r = try bridge.call(["op": "process", "project": projectName, "exr": exr.path, "outDir": workDir.appendingPathComponent("results").path, "baseName": rkey,
                                     "width": imeta.width, "height": imeta.height, "format": "tif16", "chain": chain], timeout: 600)
            resolveSeconds = Date().timeIntervalSince(t0)
            if let rb = r["readBack"] as? [String: Any] { for (k, v) in rb { if let d = v as? Double { readBack[k] = d } } }
        }
        let live = try PhotoProcessor.liveness(output: out, inputThumb: FloatImage(width: imeta.thumbW, height: imeta.thumbH, rgb: imeta.thumb))
        if live < 0.01 { try? FileManager.default.removeItem(at: out); throw PipelineError.chainInactive(live) }
        return ProcessedImage(url: out, width: imeta.width, height: imeta.height, quality: quality, decode: report, liveness: live, decodeSeconds: decodeSeconds, resolveSeconds: resolveSeconds,
                              fromIntermediateCache: cached, fromResultCache: fromResult, readBack: readBack, suggestion: imeta.suggestion, effectiveExposure: eff)
    }

    /// Diferența medie absolută dintre miniatura rezultatului (sRGB cod) și miniatura intrării (cod DI limitat la 0…1); trecerea directă ar da ≈ 0.
    static func liveness(output: URL, inputThumb: FloatImage) throws -> Double {
        guard let src = CGImageSourceCreateWithURL(output as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary) else { throw PipelineError.badOutput("TIFF ilizibil") }
        let w = cg.width, h = cg.height; var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw PipelineError.badOutput("context") }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var acc = 0.0, n = 0.0
        for y in 0..<h { for x in 0..<w {
            let tx = min(inputThumb.width - 1, x * inputThumb.width / w), ty = min(inputThumb.height - 1, y * inputThumb.height / h); let ti = 3 * (ty * inputThumb.width + tx)
            for c in 0..<3 { acc += abs(Double(px[4 * (y * w + x) + c]) / 255 - Double(max(0, min(1, inputThumb.rgb[ti + c])))); n += 1 }
        } }
        return acc / n
    }

    // Raportul de decodare se păstrează ca JSON compact (doar câmpurile de afișat/audit).
    static func reportJSON(_ r: DecodeReport) -> String {
        let d: [String: Any] = ["make": r.make, "model": r.model, "libRaw": r.libRawVersion, "black": r.whitePlan.black, "white": r.whitePlan.white, "vendorWhite": r.whitePlan.vendorWhite, "adcMax": r.whitePlan.adcMax,
            "crop": [r.appliedCrop.x, r.appliedCrop.y, r.appliedCrop.w, r.appliedCrop.h], "cropSource": r.cropPlan.defaultCropSource.rawValue, "flip": r.orientationFlip, "wb": r.wbMultipliers.map { Double($0) },
            "over": r.fracChannelOverWhiteAfterWB, "highlight": r.highlight.rawValue, "neg": r.fracNegative]
        return String(data: try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]), encoding: .utf8)!
    }
    static func reportStub(from json: String) throws -> DecodeReport {
        guard let d = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { throw PipelineError.badOutput("raport") }
        let crop = (d["crop"] as? [Int]) ?? [0, 0, 0, 0]; let rect = PixelRect(x: crop[0], y: crop[1], w: crop[2], h: crop[3])
        let wp = WhiteLevelPlan.plan(black: d["black"] as? Int ?? 0, vendorWhite: d["vendorWhite"] as? Int ?? 0, adcMax: d["adcMax"] as? Int ?? 16383)
        return DecodeReport(make: d["make"] as? String ?? "", model: d["model"] as? String ?? "", libRawVersion: d["libRaw"] as? String ?? "", whitePlan: wp,
                            cropPlan: CropPlan(activeArea: rect, defaultCrop: rect, defaultCropSource: CropPlan.Source(rawValue: d["cropSource"] as? String ?? "") ?? .activeAreaFallback, cameraAspectPreference: nil),
                            appliedCrop: rect, orientationFlip: d["flip"] as? Int ?? 0, wbMultipliers: (d["wb"] as? [Double] ?? []).map { Float($0) }, fracChannelOverWhiteAfterWB: d["over"] as? Double ?? 0,
                            highlight: HighlightPolicy(rawValue: d["highlight"] as? String ?? "") ?? .clipWhite, pedestal: RawFile.outputPedestal, linMin: 0, linMax: 0, fracNegative: d["neg"] as? Double ?? 0)
    }
}

public enum ExportFormat: Equatable { case tiff16, jpeg(quality: Double) }

/// Ce se întâmplă când fișierul de ieșire există deja. Implicit NICIODATĂ suprascriere tăcută: `unique` adaugă sufix numeric (nume-2), `skip` omite și raportează, `overwrite` cere alegere explicită în interfață.
public enum ExportCollision: String, CaseIterable, Sendable { case unique, skip, overwrite
    public var label: String { switch self { case .unique: return "Păstrează ambele (sufix numeric)"; case .skip: return "Omite fișierele existente"; case .overwrite: return "Suprascrie fișierele existente" } }
}
public struct PlannedOutput: Equatable, Sendable { public let name: String; public let url: URL; public let exists: Bool; public let skipped: Bool }

public enum ExportService {
    /// Numele de ieșire pentru UN fișier: `reserved` = nume deja alocate în același lot (fără suprapuneri între fotografii cu același nume de bază). `nil` = de omis (politica `skip`, fișier existent).
    public static func resolveOutput(dir: URL, name: String, ext: String, policy: ExportCollision, reserved: Set<String> = []) -> PlannedOutput {
        func taken(_ n: String) -> Bool { reserved.contains(n.lowercased()) || FileManager.default.fileExists(atPath: dir.appendingPathComponent(n + "." + ext).path) }
        switch policy {
        case .overwrite: return PlannedOutput(name: name, url: dir.appendingPathComponent(name + "." + ext), exists: FileManager.default.fileExists(atPath: dir.appendingPathComponent(name + "." + ext).path), skipped: false)
        case .skip: return PlannedOutput(name: name, url: dir.appendingPathComponent(name + "." + ext), exists: taken(name), skipped: taken(name))
        case .unique:
            var n = name, i = 2; while taken(n) { n = "\(name)-\(i)"; i += 1 }
            return PlannedOutput(name: n, url: dir.appendingPathComponent(n + "." + ext), exists: n != name, skipped: false)
        }
    }
    /// Planul exact al unui lot (pentru rezumat înainte de export): aceleași reguli ca la scriere.
    public static func plan(dir: URL, names: [String], ext: String, policy: ExportCollision) -> [PlannedOutput] {
        var reserved = Set<String>(); var out: [PlannedOutput] = []
        for n in names { let r = resolveOutput(dir: dir, name: n, ext: ext, policy: policy, reserved: reserved); out.append(r); if !r.skipped { reserved.insert(r.name.lowercased()) } }
        return out
    }
    /// Atașează profilul sRGB fără a modifica valorile pixelilor (Resolve scrie TIFF-ul nemanagiat, deja în codificarea sRGB a DRT) și scrie TIFF 16 biți sau JPEG.
    /// Refuză destinația = folderul originalului (nimic scris lângă originale).
    /// `rating`: se scrie ca `xmp:Rating` în fișierul EXPORTAT (nu în original): −1 respins, 0…5 stele; nil = nicio etichetă.
    public static func export(result: URL, original: URL, to destDir: URL, name: String, format: ExportFormat, allowBesideOriginal: Bool = false, rating: Int? = nil, collision: ExportCollision = .unique) throws -> URL {
        if !allowBesideOriginal && destDir.standardizedFileURL.path == original.deletingLastPathComponent().standardizedFileURL.path { throw PipelineError.insideOriginalsFolder }
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        // Profil ICC explicit (fișierul sRGB al sistemului): ImageIO omite profilul când spațiul e „sRGB” numit (doar EXIF ColorSpace), iar cerința e un ICC verificabil în fișier.
        let iccURL = URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/sRGB Profile.icc")
        let srgb = (try? Data(contentsOf: iccURL)).flatMap { CGColorSpace(iccData: $0 as CFData) } ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let src = CGImageSourceCreateWithURL(result as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil), let cs = srgb,
              let tagged = img.copy(colorSpace: cs) else { throw PipelineError.badOutput("nu pot atașa profilul sRGB") }
        let (ext, uti, props): (String, String, [CFString: Any]) = {
            switch format { case .tiff16: return ("tif", "public.tiff", [:]); case .jpeg(let q): return ("jpg", "public.jpeg", [kCGImageDestinationLossyCompressionQuality: q]) } }()
        let planned = resolveOutput(dir: destDir, name: name, ext: ext, policy: collision)
        if planned.skipped { throw PipelineError.outputExists(planned.url.lastPathComponent) }
        let out = planned.url
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, uti as CFString, 1, nil) else { throw PipelineError.badOutput("destinație") }
        if let r = rating, let md = CGImageMetadataCreateMutable() as CGMutableImageMetadata? {
            CGImageMetadataRegisterNamespaceForPrefix(md, kCGImageMetadataNamespaceXMPBasic, kCGImageMetadataPrefixXMPBasic, nil)
            CGImageMetadataSetValueWithPath(md, nil, "xmp:Rating" as CFString, String(r) as CFString)
            CGImageDestinationAddImageAndMetadata(dest, tagged, md, props as CFDictionary)
        } else { CGImageDestinationAddImage(dest, tagged, props as CFDictionary) }
        guard CGImageDestinationFinalize(dest) else { throw PipelineError.badOutput("scriere") }
        if case .jpeg = format, let icc = try? Data(contentsOf: iccURL) {
            // ImageIO nu scrie ICC în JPEG pentru sRGB; segment APP2 „ICC_PROFILE” explicit (profil < 64 KB, un singur fragment), după APP0/APP1.
            let jpeg = try Data(contentsOf: out); guard let withICC = JPEGICC.insert(icc: icc, into: jpeg) else { throw PipelineError.badOutput("JPEG neașteptat la atașarea ICC") }
            try withICC.write(to: out, options: .atomic)
        }
        return out
    }
}

public enum JPEGICC {
    /// Inserează profilul ICC ca segment APP2 (marker 0xFFE2, „ICC_PROFILE\0”, 1 din 1) după segmentele APP0/APP1 de la începutul fișierului. nil dacă fișierul nu pare JPEG sau profilul e prea mare.
    public static func insert(icc: Data, into jpeg: Data) -> Data? {
        guard jpeg.count > 4, jpeg[0] == 0xFF, jpeg[1] == 0xD8, icc.count + 16 <= 65535 else { return nil }
        var i = 2
        while i + 4 <= jpeg.count, jpeg[i] == 0xFF, jpeg[i + 1] == 0xE0 || jpeg[i + 1] == 0xE1 { i += 2 + (Int(jpeg[i + 2]) << 8 | Int(jpeg[i + 3])) }
        let len = 2 + 12 + 2 + icc.count
        var seg = Data([0xFF, 0xE2, UInt8(len >> 8), UInt8(len & 0xFF)]); seg.append(Data("ICC_PROFILE".utf8)); seg.append(0); seg.append(contentsOf: [1, 1]); seg.append(icc)
        var out = jpeg.subdata(in: 0..<i); out.append(seg); out.append(jpeg.subdata(in: i..<jpeg.count)); return out
    }
}
