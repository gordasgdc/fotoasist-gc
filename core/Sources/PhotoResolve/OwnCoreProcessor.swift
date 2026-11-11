import Foundation
import CryptoKit
import CPhotoCore
import PhotoCore
import PhotoRaw
#if !GDC_PA_OPEN_EDITION
import PhotoDRTSeal
#endif

/// Interfața comună a motoarelor de procesare: nucleul fotografic PROPRIU (în aplicație, CPU) și traseul Resolve + module STYLE (dependență TEMPORARĂ, doar comparație).
public protocol PhotoProcessing: AnyObject {
    var engineName: String { get }
    func process(photoPath: String, quality: ProcessQuality, adjustments: AdjustmentSet, decode: DecodeOptions) throws -> ProcessedImage
}
extension PhotoProcessor: PhotoProcessing { public var engineName: String { "Resolve + STYLE (temporar)" } }
extension PhotoProcessing { public func process(photoPath: String, quality: ProcessQuality, adjustments: AdjustmentSet) throws -> ProcessedImage { try process(photoPath: photoPath, quality: quality, adjustments: adjustments, decode: DecodeOptions()) } }

/// Transformarea de ieșire a motorului propriu. Implicit: GDC DRT adaptat (algoritm + date ale proprietarului, profil Natural ca reper inițial, codificare sRGB aplicată o singură dată).
/// `p1Experimental` = prototip (NU GDC DRT), păstrat doar pentru comparație explicită.
public enum OutputTransform: String, CaseIterable, Codable { case gdcDRTNatural, p1Experimental
    public var label: String { self == .gdcDRTNatural ? "GDC DRT (Natural) → sRGB" : (Edition.full ? "DRT p1 (experimental, NU GDC DRT) → sRGB" : "Open display transform → sRGB") }
    /// Transformarea implicită a ediției: GDC DRT Natural în ediția completă; transformarea de afișare deschisă în ediția cu sursă deschisă.
    public static var standard: OutputTransform { Edition.full ? .gdcDRTNatural : .p1Experimental }
    /// Transformarea efectiv aplicată: ediția cu sursă deschisă nu conține GDC DRT, deci orice alegere salvată se redă cu transformarea deschisă.
    public var effective: OutputTransform { Edition.full ? self : .p1Experimental }
}

/// Datele GDC DRT (activ al proprietarului, NU în git): fișierul `drt_1.bin` din depozitul GDC STYLE Lab (tag v2.10.0, commit 86d1770…), verificat prin SHA-256 înainte de încărcare. Fără rezervă tăcută.
public enum GDCDRTData {
    public static let expectedSHA256 = "c3069d284d0e1d484ab172f3d6c0bf34c76b785e2f6fed95a94f2a7e28b9e9e2"
    public enum Status: Equatable { case notLoaded, loaded(String), missing, invalid(String) }
    public private(set) static var status: Status = .notLoaded
    private static let lock = NSLock()
    /// Pachetele SIGILATE poartă `GDCPADRTSealedRequired` în Info.plist: în ele datele în clar NU se acceptă niciodată (fără revenire tăcută), iar lipsa/alterarea/cheia greșită sunt erori explicite.
    static var sealedRequired: Bool { (Bundle.main.infoDictionary?["GDCPADRTSealedRequired"] as? Bool) ?? false }
    public static func resetForTesting() { lock.lock(); status = .notLoaded; lock.unlock() }
    /// Căutare date sigilate: GDC_PA_DRT_SEALED (probă), apoi Resources din aplicație (`drt_1.sealed`).
    static func locateSealed() -> URL? {
        var c: [URL] = []; if let e = ProcessInfo.processInfo.environment["GDC_PA_DRT_SEALED"] { c.append(URL(fileURLWithPath: e)) }
        if let u = Bundle.main.url(forResource: "drt_1", withExtension: "sealed") { c.append(u) }
        return c.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    /// Căutare date în clar (dezvoltare/legacy): GDC_PA_DRT_DATA, Resources (`drt_1.bin`), <GDCPADevRoot>/data/drt/drt_1.bin.
    public static func locate(devRoot: String? = nil) -> URL? {
        let env = ProcessInfo.processInfo.environment["GDC_PA_DRT_DATA"]
        var c: [URL] = []; if let e = env { c.append(URL(fileURLWithPath: e)) }
        if let u = Bundle.main.url(forResource: "drt_1", withExtension: "bin") { c.append(u) }
        if let r = devRoot ?? (Bundle.main.infoDictionary?["GDCPADevRoot"] as? String) ?? ProcessInfo.processInfo.environment["GDC_PA_ROOT"] { c.append(URL(fileURLWithPath: r).appendingPathComponent("data/drt/drt_1.bin")) }   // dezvoltare
        return c.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    @discardableResult public static func load(devRoot: String? = nil) -> Status {
        lock.lock(); defer { lock.unlock() }
        #if GDC_PA_OPEN_EDITION
        _ = devRoot; status = .missing; return status   // GDC DRT nu face parte din ediția cu sursă deschisă
        #else
        if case .loaded = status, pc_drt_available() == 1 { return status }
        var d: Data; var origin: String
        if let su = locateSealed() {
            // Date sigilate: orice eșec e o eroare EXPLICITĂ; niciodată revenire la datele în clar.
            guard let sealed = try? Data(contentsOf: su) else { status = .invalid("datele DRT sigilate nu pot fi citite"); return status }
            do { d = try DRTSeal.open(sealed, secret: DRTSecret.resolve()); origin = su.path + " (sigilat)" }
            catch let e as DRTSecret.Failure { status = .invalid("DRT sigilat: \(e)"); return status }
            catch let e as DRTSeal.SealError { status = .invalid("DRT sigilat: " + (e == .authenticationFailed ? "date alterate sau cheie greșită" : (e == .notSealed ? "format necunoscut" : "date trunchiate"))); return status }
            catch { status = .invalid("DRT sigilat: eroare necunoscută"); return status }
        } else if sealedRequired {
            status = .missing; return status          // pachet sigilat fără resursa sigilată: nu se caută date în clar
        } else {
            guard let u = locate(devRoot: devRoot), let c = try? Data(contentsOf: u) else { status = .missing; return status }
            d = c; origin = u.path
        }
        let sha = SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
        guard sha == expectedSHA256 else { status = .invalid("SHA-256 diferit (\(sha.prefix(12))…)"); return status }
        var err = [CChar](repeating: 0, count: 128)
        let rc = d.withUnsafeBytes { pc_drt_load($0.bindMemory(to: UInt8.self).baseAddress, UInt(d.count), &err, 128) }
        status = rc == 0 ? .loaded(origin) : .invalid(String(cString: err)); return status
        #endif
    }
}

extension AdjustmentSet {
    /// Maparea reglajelor pe parametrii nucleului propriu (`photo_develop.hpp`). `estimate` = estimarea pentru modul automat.
    public func coreParams(estimate: Double?, inputIsLinear: Bool, output: OutputTransform = .gdcDRTNatural) -> pc_params {
        var p = pc_params(); pc_default_params(&p)
        p.exposure = effectiveExposure(estimate: estimate); p.temperature = temperature; p.tint = tint; p.shadows = shadows; p.highlights = highlights; p.contrast = contrast; p.saturation = saturation
        tools.apply(to: &p); look.apply(to: &p)
        if let c = chart, !c.isIdentity, c.matrix.count == 9 { p.chartOn = 1; withUnsafeMutableBytes(of: &p.chartM) { r in for i in 0..<9 { r.storeBytes(of: c.matrix[i], toByteOffset: i * 8, as: Double.self) } } }
        p.family = family.coreIndex; p.inputIsLinear = inputIsLinear ? 2 : 0   // 2 = scene-liniar DWG (decodorul) → gamutul familiei; 0 = cod log al familiei
        switch output.effective { case .gdcDRTNatural: p.drt = 2; p.drtProfile = Int32(drtProfile); p.drtOutput = 2   // sRGB = recodare a luminii de afișare, o singură dată
        case .p1Experimental: p.drt = 1 }
        return p
    }
}

/// Rulează nucleul cu corecțiile locale și măștile lor compuse (aceeași cale pentru previzualizare, export și analiză).
public func makeGeom(_ p: Geometry.Plan, srcW: Int, srcH: Int) -> pc_geom {
    var g = pc_geom(); withUnsafeMutableBytes(of: &g.h) { raw in for i in 0..<9 { raw.storeBytes(of: p.h[i], toByteOffset: i * 8, as: Double.self) } }
    g.srcW = Int32(srcW); g.srcH = Int32(srcH); g.outW = Int32(p.outW); g.outH = Int32(p.outH); return g
}
public func runCoreMasks(_ params: inout pc_params, _ cm: (locals: [pc_local], data: [Double], offsets: [Int]), input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, width: Int, height: Int) -> Int32 {
    var offs = cm.offsets
    return cm.data.withUnsafeBufferPointer { md in offs.withUnsafeMutableBufferPointer { op in pc_process_image_masks(&params, cm.locals, Int32(cm.locals.count), md.baseAddress, op.baseAddress, input, output, Int32(width), Int32(height), 0) } }
}
extension LocalCorrection {
    /// Doar corecțiile active și cu efect: o corecție neutră sau oprită nu intră în calcul (și nu schimbă rezultatul). Întoarce corecțiile pentru nucleu + datele măștilor compuse (concatenate, cu decalaje).
    public static func coreMasks(_ ls: [LocalCorrection], family: WorkingFamily = .dwg) -> (locals: [pc_local], data: [Double], offsets: [Int]) {
        var out: [pc_local] = []; var data: [Double] = []; var offs: [Int] = [0]
        for l in ls where l.enabled && !l.adjustmentIsNeutral {
            var a = pc_params(); pc_default_params(&a); a.exposure = l.exposure; a.shadows = l.shadows; a.highlights = l.highlights; a.contrast = l.contrast; a.temperature = l.temperature; a.tint = l.tint; a.saturation = l.saturation; a.drt = 0; a.family = family.coreIndex   /* corecția lucrează în aceeași familie ca ajustarea globală */
            let z = pc_zone(kind: l.kind == .gradient ? 1 : 0, x1: l.x1, y1: l.y1, x2: l.x2, y2: l.y2, feather: l.feather, invert: l.invert ? 1 : 0)
            out.append(pc_local(enabled: 1, zone: z, adj: a)); if !l.isSimpleMask { data += l.maskData }; offs.append(data.count)
        }
        return (out, data, offs)
    }
    static func coreLocals(_ ls: [LocalCorrection], family: WorkingFamily = .dwg) -> [pc_local] { coreMasks(ls, family: family).locals }
    /// Masca pe o grilă a VEDERII transformate (geometria dată), evaluată exact ca la procesare.
    public func maskValuesInView(geometry: Geometry, effects: Effects = Effects(), srcW: Int, srcH: Int, width: Int, height: Int) -> [Float] {
        var z = pc_zone(kind: kind == .gradient ? 1 : 0, x1: x1, y1: y1, x2: x2, y2: y2, feather: feather, invert: invert ? 1 : 0); let d = maskData; let plan = geometry.plan(srcW: srcW, srcH: srcH); var geo = makeGeom(plan, srcW: srcW, srcH: srcH); var cfx = effects.c
        var out = [Float](repeating: 0, count: max(0, width * height)); if width > 0 && height > 0 { out.withUnsafeMutableBufferPointer { o in d.withUnsafeBufferPointer { pc_mask_image_geom_fx(&z, $0.baseAddress, $0.count, &geo, &cfx, o.baseAddress, Int32(width), Int32(height)) } } }; return out
    }
    /// Valorile măștii compuse [0,1] pe o grilă (pentru afișarea zonei peste fotografie; ACEEAȘI funcție ca la procesare).
    public func maskValues(width: Int, height: Int) -> [Float] {
        var z = pc_zone(kind: kind == .gradient ? 1 : 0, x1: x1, y1: y1, x2: x2, y2: y2, feather: feather, invert: invert ? 1 : 0); let d = maskData
        var out = [Float](repeating: 0, count: max(0, width * height)); if width > 0 && height > 0 { out.withUnsafeMutableBufferPointer { o in d.withUnsafeBufferPointer { pc_mask_image_data(&z, $0.baseAddress, $0.count, o.baseAddress, Int32(width), Int32(height)) } } }; return out
    }
}

/// Fotografie → decodare float (LibRaw, DWG liniar) → nucleul propriu (balans/expunere/umbre-lumini → log → contrast/saturație → DRT propriu) → TIFF 16 biți sRGB. Nu folosește Resolve, STYLE sau LT AutoEdit.
public final class OwnCoreProcessor: PhotoProcessing {
    public var engineName: String { !Edition.full ? L("Nucleu propriu (CPU) + redare deschisă") : (outputTransform == .gdcDRTNatural ? "Nucleu propriu (CPU) + GDC DRT Natural adaptat → sRGB" : L("Prototip experimental (nucleu propriu CPU + DRT p1)")) }
    public let workDir: URL
    /// Transformarea de ieșire curentă (se schimbă explicit din UI; intră în cheia rezultatelor).
    public var outputTransform: OutputTransform = .standard
    private struct Cached { var image: FloatImage; var report: DecodeReport; var suggestion: ExposureSuggestion }
    private var cache: [String: Cached] = [:]; private var order: [String] = []; private let lock = NSLock()
    /// Timpi pe etape ai ultimei procesări (secunde): decode · core (transformări + module + măști/geometrie + DRT, într-o trecere) · tiff (scriere). Diagnostic/măsurare; nu influențează rezultatul.
    public private(set) var lastTimings: [String: Double] = [:]
    private let log: DiagnosticLog?

    public init(workDir: URL, log: DiagnosticLog? = nil) throws {
        self.workDir = workDir; self.log = log
        try FileManager.default.createDirectory(at: workDir.appendingPathComponent("results"), withIntermediateDirectories: true)
    }

    private var shiftCache: [String: Double?] = [:]
    /// Compensarea de expunere declarată de cameră pentru fișier (EV; nil = necunoscută). Citită o singură dată pe fișier (doar metadatele).
    public func cameraExposureShift(photoPath: String) -> Double? {
        lock.lock(); if let c = shiftCache[photoPath] { lock.unlock(); return c }; lock.unlock()
        let v = (try? RawFile(path: photoPath))?.cameraExposureShift
        lock.lock(); shiftCache[photoPath] = .some(v); lock.unlock(); return v
    }
    /// Opțiunile de decodare ale fotografiei = opțiunile de bază + dezvoltarea RAW din reglaje (revizia decodării și compensarea). ACEEAȘI cale pentru procesare, analiză și intermediar.
    public func decodeOptions(photoPath: String, adjustments: AdjustmentSet, base: DecodeOptions = DecodeOptions()) -> DecodeOptions {
        var o = base; o.legacyV1 = adjustments.rawDev.isLegacyDecode
        o.baselineEV = adjustments.rawDev.appliedEV(cameraShift: adjustments.rawDev.baseline == .camera ? cameraExposureShift(photoPath: photoPath) : nil); return o
    }
    private func decoded(_ photoPath: String, _ opt: DecodeOptions, _ quality: ProcessQuality, _ job: String) throws -> (Cached, Bool, Double) {
        let attrs = try FileManager.default.attributesOfItem(atPath: photoPath)
        let key = PhotoProcessor.hash("\(photoPath)|\((attrs[.size] as? NSNumber)?.intValue ?? 0)|\((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\(quality)|\(opt.white)|\(opt.highlight)|\(opt.wb)|\(opt.crop)|\(opt.legacyV1)|\(String(format: "%.4f", opt.baselineEV))|\(RawFile.libraryVersion)")
        lock.lock(); if let c = cache[key] { order.removeAll { $0 == key }; order.append(key); lock.unlock(); return (c, true, 0) }; lock.unlock()
        let t0 = Date(); log?.log(.info, "decode", "start", photoPath, job: job)
        let dec = try RawFile(path: photoPath).decodeLinearDWG(opt)
        let c = Cached(image: dec.image, report: dec.report, suggestion: ExposureSuggestion.compute(from: dec.image))
        log?.log(.info, "decode", "ok", "\(dec.image.width)x\(dec.image.height) \(dec.report.model)", job: job, durationMs: Date().timeIntervalSince(t0) * 1000)
        lock.lock(); cache[key] = c; order.append(key); while order.count > (quality == .full ? 1 : 3) { cache[order.removeFirst()] = nil }; lock.unlock()
        return (c, false, Date().timeIntervalSince(t0))
    }

    private var dsKey = ""; private var dsValue: Cached?
    /// Previzualizare redusă pentru interacțiune: medie k×k (k întreg) până la ≤ ~1400 px latura mare; ținută pentru ultima fotografie (decodarea rămâne în cache-ul normal).
    private func downsampled(_ c: Cached, key: String) -> Cached {
        lock.lock(); if dsKey == key, let v = dsValue { lock.unlock(); return v }; lock.unlock()
        let w = c.image.width, h = c.image.height, k = max(1, Int((Double(max(w, h)) / 1400.0).rounded(.up))); if k == 1 { return c }
        let nw = w / k, nh = h / k; var out = [Float](repeating: 0, count: nw * nh * 3); let inv = 1.0 / Float(k * k)
        for y in 0..<nh { for x in 0..<nw { var r: Float = 0, g: Float = 0, b: Float = 0
            for dy in 0..<k { let row = ((y * k + dy) * w + x * k) * 3; for dx in 0..<k { r += c.image.rgb[row + dx * 3]; g += c.image.rgb[row + dx * 3 + 1]; b += c.image.rgb[row + dx * 3 + 2] } }
            let o = (y * nw + x) * 3; out[o] = r * inv; out[o + 1] = g * inv; out[o + 2] = b * inv } }
        var d = c; d.image = FloatImage(width: nw, height: nh, rgb: out)
        lock.lock(); dsKey = key; dsValue = d; lock.unlock(); return d
    }

    /// Intermediarul tehnic pentru pagina Color: decodare LibRaw la REZOLUȚIE PLINĂ (aceeași politică ca la export), cod DaVinci Intermediate / DaVinci Wide Gamut, EXR float32. Reutilizat dacă există deja (cheia = fișier + dimensiune + dată).
    /// Intermediarul pentru pagina Color: decodare LibRaw la rezoluție plină, cod log al familiei, EXR float32. Cu geometrie activă: geometria FotoAsist e APLICATĂ în intermediar (o singură reeșantionare, pe liniar), iar fișierul e identificat explicit (`_GEO-…` în nume) — nodurile OFX nu au geometrie, deci nu se aplică a doua oară.
    public func intermediateEXR(photoPath: String, decode: DecodeOptions = DecodeOptions(), family: WorkingFamily = .dwg, geometry: Geometry = Geometry(), effects: Effects = Effects(), bake: AdjustmentSet? = nil, rawDev: RawDevelopment = RawDevelopment()) throws -> (url: URL, width: Int, height: Int, geometryApplied: Bool, baked: Bool) {
        let attrs = try FileManager.default.attributesOfItem(atPath: photoPath)
        let bakeEff = bake?.effective
        var devSet = AdjustmentSet(); devSet.rawDev = bake?.rawDev ?? rawDev; let decode = decodeOptions(photoPath: photoPath, adjustments: devSet, base: decode)   // aceeași dezvoltare RAW ca în procesare
        let bakeEst: Double? = bake == nil ? nil : (try? decodedPreview(photoPath, decode).suggestion.stops)   // aceeași estimare automată de expunere ca în procesarea FotoAsist (altfel expunerea automată lipsea din intermediarul BAKED)
        let fx = bakeEff?.effects ?? effects                    // fără bake: doar optica (mută pixelii) intră în intermediar; cu bake: totul (peliculă, grain, vinietă) într-o singură trecere
        let optics = (bake == nil && (!fx.framingIsNeutral || fx.lensVignette != 0)) ? Effects.opticsOnly(fx) : Effects()
        let key = PhotoProcessor.hash("exr|\(decode.legacyV1)|\(String(format: "%.4f", decode.baselineEV))|\(photoPath)|\((attrs[.size] as? NSNumber)?.intValue ?? 0)|\((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\(decode.white)|\(decode.highlight)|\(decode.wb)|\(decode.crop)" + (family == .dwg ? "" : "|\(family.id)") + (geometry.isNeutral ? "" : "|" + geometry.fingerprint) + (optics.isNeutral ? "" : "|fx:" + optics.fingerprint) + (bake.map { "|bake-est:" + String(format: "%.4f", bakeEst ?? 0) + "|bake:" + $0.fingerprint } ?? ""))
        let dir = workDir.appendingPathComponent("handoff"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stem = ((photoPath as NSString).lastPathComponent as NSString).deletingPathExtension
        let tag = family == .dwg ? "DI-DWG" : family.id; let resampled = !geometry.isNeutral || !optics.isNeutral
        let geoTag = (geometry.isNeutral ? "" : "_GEO-" + String(PhotoProcessor.hash(geometry.fingerprint).prefix(6))) + (optics.isNeutral ? "" : "_OPT-" + String(PhotoProcessor.hash(optics.fingerprint).prefix(6))) + (bake == nil ? "" : "_BAKED-" + String(PhotoProcessor.hash(bake!.fingerprint).prefix(6)))
        let url = dir.appendingPathComponent("\(stem)_\(tag)\(geoTag)_\(String(key.prefix(8))).exr"); var opt = decode; opt.halfSize = false
        let d = try RawFile(path: photoPath).decodeLinearDWG(opt); var img = d.image
        if let b = bake, b.effective.retouch.contains(where: { $0.enabled }) { img = FloatImage(width: img.width, height: img.height, rgb: Retouch.apply(b.effective.retouch, to: img.rgb, width: img.width, height: img.height)) }   // retușul se integrează în intermediar (o singură dată)
        if let b = bake {   // corecțiile (globale + locale) și efectele INTEGRATE în intermediar: cod log al familiei, înaintea DRT-ului; geometria/optica se aplică O SINGURĂ dată, în aceeași trecere (sursa → ieșire)
            let plan = geometry.plan(srcW: img.width, srcH: img.height)
            if !FileManager.default.fileExists(atPath: url.path) {
                var a = b.effective; a.geometry = Geometry(); var p = a.coreParams(estimate: bakeEst, inputIsLinear: true, output: outputTransform); p.drt = 0
                var out = [Float](repeating: 0, count: plan.outW * plan.outH * 3); let cm = LocalCorrection.coreMasks(a.locals, family: a.family)
                var geo = makeGeom(plan, srcW: img.width, srcH: img.height); var offs = cm.offsets; var cfx = a.effects.c; var cfilm = a.effects.film3C; var ccin = a.effects.cinemaC
                let rc = img.rgb.withUnsafeBufferPointer { i in out.withUnsafeMutableBufferPointer { o in cm.data.withUnsafeBufferPointer { md in offs.withUnsafeMutableBufferPointer { op in pc_process_image_fx4(&p, cm.locals, Int32(cm.locals.count), md.baseAddress, op.baseAddress, &geo, &cfx, &cfilm, &ccin, i.baseAddress!, o.baseAddress!, 0) } } } }
                guard rc == 0 else { throw PipelineError.badOutput("integrare corecții") }
                try FloatImageIO.writeEXR(FloatImage(width: plan.outW, height: plan.outH, rgb: out), to: url)
            }
            return (url, plan.outW, plan.outH, !geometry.isNeutral, true)
        }
        if resampled {
            let plan = geometry.plan(srcW: img.width, srcH: img.height); var geo = makeGeom(plan, srcW: img.width, srcH: img.height); var out = [Float](repeating: 0, count: plan.outW * plan.outH * 3); var cfx = optics.c
            let rc = img.rgb.withUnsafeBufferPointer { i in out.withUnsafeMutableBufferPointer { o in pc_resample_fx(&geo, &cfx, i.baseAddress!, o.baseAddress!, 0) } }
            guard rc == 0 else { throw PipelineError.badOutput("reeșantionare geometrică") }; img = FloatImage(width: plan.outW, height: plan.outH, rgb: out)
        }
        if !FileManager.default.fileExists(atPath: url.path) { try FloatImageIO.writeEXR(img.familyEncoded(family), to: url) }
        return (url, img.width, img.height, resampled, false)
    }

    /// Intrările estimatorului de profil: imaginea decodată la jumătate de rezoluție (liniar DWG) și estimarea automată a expunerii. Numai citire.
    public func estimationInputs(photoPath: String) throws -> (image: FloatImage, estimate: Double) { let (img, sug) = try decodedPreview(photoPath, DecodeOptions()); return (img, sug.stops) }
    /// Pick Color: culoarea (nuanță°, croma relativă, luminanță în stopuri) la punctul normalizat (nx, ny) al SURSEI, citită din codul log care intră în Color (după instrumentele globale), pe o vecinătate 5×5. nil = gri/neselectabil.
    public func pickColor(photoPath: String, nx: Double, ny: Double, adjustments adjIn: AdjustmentSet) throws -> (hue: Double, c: Double, l: Double)? {
        let a = adjIn.effective; let (img, sug) = try decodedPreview(photoPath, decodeOptions(photoPath: photoPath, adjustments: a)); var p = a.coreParams(estimate: sug.stops, inputIsLinear: true, output: outputTransform)
        let cx = Int(nx * Double(img.width)), cy = Int(ny * Double(img.height)); var acc = [Double](repeating: 0, count: 3); var n = 0.0
        for dy in -2...2 { for dx in -2...2 { let x = min(img.width - 1, max(0, cx + dx)), y = min(img.height - 1, max(0, cy + dy)); var lin: [Float] = [img.rgb[(y * img.width + x) * 3], img.rgb[(y * img.width + x) * 3 + 1], img.rgb[(y * img.width + x) * 3 + 2]]; var code = [Double](repeating: 0, count: 3)
            pc_color_stage_code(&p, &lin, &code); for k in 0..<3 { acc[k] += code[k] }; n += 1 } }
        var mean = acc.map { $0 / n }; var h = 0.0, c = 0.0, l = 0.0; guard pc_color_pick(Int32(a.family.coreIndex), &mean, &h, &c, &l) == 1 else { return nil }; return (h, c, l)
    }
    /// Media liniară DWG (după decodare, înaintea instrumentelor) a punctelor normalizate ale SURSEI; baza pipetei de balans de alb.
    public func linearSample(photoPath: String, points: [(x: Double, y: Double)]) throws -> [Double]? {
        let (img, _) = try decodedPreview(photoPath, DecodeOptions()); var acc = [Double](repeating: 0, count: 3); var n = 0.0
        for pt in points.prefix(512) { let x = min(img.width - 1, max(0, Int(pt.x * Double(img.width)))), y = min(img.height - 1, max(0, Int(pt.y * Double(img.height)))); for k in 0..<3 { acc[k] += Double(img.rgb[(y * img.width + x) * 3 + k]) }; n += 1 }
        return n > 0 ? acc.map { $0 / n } : nil
    }
    /// Pick Range: eșantioane (≤512 puncte normalizate ale sursei) → familia de culori observată (mod dominant, outlieri respinși, limite 5–95%). nil dacă nu există eșantioane cromatice.
    public func pickRange(photoPath: String, points: [(x: Double, y: Double)], adjustments adjIn: AdjustmentSet) throws -> pc_range_pick? {
        let a = adjIn.effective; let (img, sug) = try decodedPreview(photoPath, decodeOptions(photoPath: photoPath, adjustments: a)); var p = a.coreParams(estimate: sug.stops, inputIsLinear: true, output: outputTransform)
        var codes = [Double](); codes.reserveCapacity(points.count * 3)
        for pt in points.prefix(512) { let x = min(img.width - 1, max(0, Int(pt.x * Double(img.width)))), y = min(img.height - 1, max(0, Int(pt.y * Double(img.height))))
            var lin: [Float] = [img.rgb[(y * img.width + x) * 3], img.rgb[(y * img.width + x) * 3 + 1], img.rgb[(y * img.width + x) * 3 + 2]]; var code = [Double](repeating: 0, count: 3); pc_color_stage_code(&p, &lin, &code); codes += code }
        var o = pc_range_pick(); pc_color_pick_range(Int32(a.family.coreIndex), codes, Int32(codes.count / 3), &o); return o.valid != 0 ? o : nil
    }
    /// Matte-ul selecției (0 = Color, 1 = Skin) pe grila vederii (geometria dată), valori [0,1], aceeași cale ca procesarea.
    public func selectionMatte(photoPath: String, adjustments adjIn: AdjustmentSet, which: Int, width: Int, height: Int) throws -> [Float] {
        let a = adjIn.effective; let (img, sug) = try decodedPreview(photoPath, decodeOptions(photoPath: photoPath, adjustments: a)); var p = a.coreParams(estimate: sug.stops, inputIsLinear: true, output: outputTransform)
        let plan = a.geometry.plan(srcW: img.width, srcH: img.height); var geo = makeGeom(plan, srcW: img.width, srcH: img.height)
        let sx = Double(plan.outW) / Double(max(1, width)), sy = Double(plan.outH) / Double(max(1, height))   // grila cerută: h' = h · diag(outW/w, outH/h, 1)
        withUnsafeMutableBytes(of: &geo.h) { r in for row in 0..<3 { for col in 0..<3 { let v = r.load(fromByteOffset: (row * 3 + col) * 8, as: Double.self); r.storeBytes(of: col == 0 ? v * sx : (col == 1 ? v * sy : v), toByteOffset: (row * 3 + col) * 8, as: Double.self) } } }
        geo.outW = Int32(width); geo.outH = Int32(height); var out = [Float](repeating: 0, count: max(0, width * height)); if out.isEmpty { return out }
        let rc = img.rgb.withUnsafeBufferPointer { i in out.withUnsafeMutableBufferPointer { o in pc_selection_matte_view(&p, Int32(which), &geo, i.baseAddress!, o.baseAddress!, 0) } }
        guard rc == 0 else { throw PipelineError.badOutput("matte selecție") }; return out
    }
    /// Decodarea (în cache) la rezoluție de previzualizare, pentru analize (numai citire).
    func decodedPreview(_ photoPath: String, _ decode: DecodeOptions) throws -> (image: FloatImage, suggestion: ExposureSuggestion) {
        var opt = decode; opt.halfSize = true; let (c, _, _) = try decoded(photoPath, opt, .preview, "analysis"); return (c.image, c.suggestion)
    }

    private var rendCache: (key: String, rgb: [Float], w: Int, h: Int, info: RenderedInfo)?
    /// Intrare redată (PNG/JPEG/TIFF): SINGURA prelucrare permisă e geometria (decupare/rotire/oglindire), aplicată o singură dată prin reeșantionarea bilineară a nucleului pe valorile deja codate sRGB.
    /// Fără DRT, fără normalizare RAW, fără balans de alb, fără module de ton/culoare (neaplicabile unei imagini redate). Neutru ⇒ pixelii sursei, în limita conversiei ICC → sRGB documentate.
    func processRendered(photoPath: String, quality: ProcessQuality, adjustments: AdjustmentSet) throws -> ProcessedImage {
        let t0 = Date(); let attrs = try FileManager.default.attributesOfItem(atPath: photoPath)
        let ckey = PhotoProcessor.hash("rend|\(photoPath)|\((attrs[.size] as? NSNumber)?.intValue ?? 0)|\((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)")
        lock.lock(); let hit = rendCache?.key == ckey ? rendCache : nil; lock.unlock()
        let (rgb, w, h, info): ([Float], Int, Int, RenderedInfo)
        if let c = hit { (rgb, w, h, info) = (c.rgb, c.w, c.h, c.info) } else {
            let l = try RenderedImage.floatRGB(url: URL(fileURLWithPath: photoPath)); (rgb, w, h, info) = (l.rgb, l.width, l.height, l.info)
            lock.lock(); rendCache = (ckey, rgb, w, h, info); lock.unlock()
            log?.log(.info, "rendered", "load", "\(w)x\(h) \(info.format) · \(info.summary)")
        }
        let geom = adjustments.geometry; let plan = geom.plan(srcW: w, srcH: h)
        let outW = geom.isNeutral ? w : plan.outW, outH = geom.isNeutral ? h : plan.outH
        let rkey = PhotoProcessor.hash("rendered-v1|\(ckey)|\(geom.fingerprint)")
        let out = workDir.appendingPathComponent("results/\(rkey).tif"); var fromResult = true
        if !FileManager.default.fileExists(atPath: out.path) {
            fromResult = false; var o = rgb
            if !geom.isNeutral {
                o = [Float](repeating: 0, count: outW * outH * 3); var geo = makeGeom(plan, srcW: w, srcH: h)
                let rc = rgb.withUnsafeBufferPointer { i in o.withUnsafeMutableBufferPointer { op in pc_resample_geom(&geo, i.baseAddress!, op.baseAddress!, Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))) } }
                if rc != 0 { throw PipelineError.badOutput("reeșantionarea geometriei a refuzat (cod \(rc))") }
            }
            try TIFF16.write(rgb: o, width: outW, height: outH, to: out)
            log?.log(.info, "rendered", "ok", "\(w)x\(h) → \(outW)x\(outH)", durationMs: Date().timeIntervalSince(t0) * 1000)
        }
        let none = ExposureSuggestion(stops: 0, medianToGrey: 0, highlightAnchor: 0, median: 0, p99: 0, p995: 0, lowKeyWarning: false, sceneHint: "imagine redată")
        return ProcessedImage(url: out, width: outW, height: outH, quality: quality, decode: nil, liveness: 1.0, decodeSeconds: 0, resolveSeconds: Date().timeIntervalSince(t0), fromIntermediateCache: hit != nil, fromResultCache: fromResult, readBack: [:], suggestion: none, effectiveExposure: 0, sourceWidth: w, sourceHeight: h, rendered: info)
    }

    public func process(photoPath: String, quality: ProcessQuality, adjustments adjIn: AdjustmentSet, decode: DecodeOptions = DecodeOptions()) throws -> ProcessedImage {
        if RenderedImage.isRendered(path: photoPath) { return try processRendered(photoPath: photoPath, quality: quality, adjustments: adjIn.effective) }
        let adjustments = adjIn.effective   // modulele dezactivate sunt neutre în procesare (valorile rămân salvate)
        let job = String(UUID().uuidString.prefix(8)).lowercased()
        let ot = outputTransform.effective
        if ot == .gdcDRTNatural { switch GDCDRTData.load() { case .loaded: break
            case .missing: throw PipelineError.drtData("Datele GDC DRT lipsesc (drt_1.bin). Nu se folosește nicio rezervă tăcută; alege explicit „DRT p1 (experimental)” sau pune fișierul la locul lui.")
            case .invalid(let m): throw PipelineError.drtData("Datele GDC DRT sunt neașteptate: \(m)")
            case .notLoaded: throw PipelineError.drtData("Datele GDC DRT nu s-au încărcat") } }
        var opt = decodeOptions(photoPath: photoPath, adjustments: adjIn, base: decode); opt.halfSize = quality != .full
        let (c0, cached, decodeSeconds) = try decoded(photoPath, opt, quality == .full ? .full : .preview, job)
        let c = quality == .interactive ? downsampled(c0, key: "\(photoPath)|\(c0.image.width)x\(c0.image.height)|\(c0.report.model)") : c0
        let eff = adjustments.effectiveExposure(estimate: c.suggestion.stops)
        let rkey = PhotoProcessor.hash("own-\(String(cString: pc_version()))|\(ot.rawValue)|\(photoPath)|\(quality)|\(opt.highlight)|\(opt.white)|\(opt.wb)|\(adjustments.fingerprint)|eff\(String(format: "%.4f", eff))|v\(c.image.width)x\(c.image.height)")
        let out = workDir.appendingPathComponent("results/\(rkey).tif")
        var fromResult = true; var seconds = 0.0; var outW = c.image.width, outH = c.image.height
        let gp = adjustments.geometry.plan(srcW: c.image.width, srcH: c.image.height); if !adjustments.geometry.isNeutral { outW = gp.outW; outH = gp.outH }
        if !FileManager.default.fileExists(atPath: out.path) {
            fromResult = false; let t0 = Date()
            let inRGB: [Float] = adjustments.retouch.contains { $0.enabled } ? Retouch.apply(adjustments.retouch, to: c.image.rgb, width: c.image.width, height: c.image.height) : c.image.rgb   // retuș pe liniar DWG, înainte de instrumente și geometrie
            var params = adjustments.coreParams(estimate: c.suggestion.stops, inputIsLinear: true, output: ot)
            let geom = adjustments.geometry; let plan = geom.plan(srcW: c.image.width, srcH: c.image.height)
            let fxNeutral = adjustments.effects.isNeutral && adjustments.tools.isNeutral(.diffusion)   // Optics (difuzie/bloom) e spațial: cere calea pe tot cadrul
            var rgb = [Float](repeating: 0, count: geom.isNeutral ? c.image.rgb.count : plan.outW * plan.outH * 3)
            var rc: Int32 = 0
            let cm = LocalCorrection.coreMasks(adjustments.locals, family: adjustments.family)
            if geom.isNeutral && fxNeutral {
                inRGB.withUnsafeBufferPointer { i in rgb.withUnsafeMutableBufferPointer { o in rc = runCoreMasks(&params, cm, input: i.baseAddress!, output: o.baseAddress!, width: c.image.width, height: c.image.height) } }
            } else {   // geometrie și/sau efecte: o singură reeșantionare (liniar; optica la eșantionare), măști în coordonatele sursei, peliculă/grain după corecții, la rezoluția livrabilului
                var geo = makeGeom(plan, srcW: c.image.width, srcH: c.image.height); var offs = cm.offsets; var cfx = adjustments.effects.c; var cfilm = adjustments.effects.film3C; var ccin = adjustments.effects.cinemaC
                inRGB.withUnsafeBufferPointer { i in rgb.withUnsafeMutableBufferPointer { o in cm.data.withUnsafeBufferPointer { md in offs.withUnsafeMutableBufferPointer { op in rc = pc_process_image_fx4(&params, cm.locals, Int32(cm.locals.count), md.baseAddress, op.baseAddress, &geo, &cfx, &cfilm, &ccin, i.baseAddress!, o.baseAddress!, 0) } } } }
            }
            if !adjustments.detail.isNeutral { var dd = adjustments.detail.core; outW = geom.isNeutral ? c.image.width : plan.outW; outH = geom.isNeutral ? c.image.height : plan.outH; if rc == 0 { _ = rgb.withUnsafeMutableBufferPointer { pc_detail_apply(&dd, $0.baseAddress, Int32(outW), Int32(outH), 0) } } }   // ultima etapă: pe imaginea finală sRGB
            let tCore = Date().timeIntervalSince(t0)
            if rc != 0 { throw PipelineError.drtData("Procesarea a refuzat (cod \(rc)): datele DRT nu sunt încărcate") }
            outW = geom.isNeutral ? c.image.width : plan.outW; outH = geom.isNeutral ? c.image.height : plan.outH
            let tW0 = Date(); try TIFF16.write(rgb: rgb, width: outW, height: outH, to: out)
            lastTimings = ["decode": decodeSeconds, "core": tCore, "tiff": Date().timeIntervalSince(tW0)]
            seconds = Date().timeIntervalSince(t0); log?.log(.info, "develop", "ok", "\(c.image.width)x\(c.image.height) exp \(String(format: "%+.2f", eff))", job: job, durationMs: seconds * 1000)
        }
        // „liveness” nu se aplică: nu există gazdă externă care să poată lăsa lanțul inactiv; valoarea 1.0 marchează „nu se aplică”.
        return ProcessedImage(url: out, width: outW, height: outH, quality: quality, decode: c.report, liveness: 1.0, decodeSeconds: decodeSeconds, resolveSeconds: seconds,
                              fromIntermediateCache: cached, fromResultCache: fromResult, readBack: [:], suggestion: c.suggestion, effectiveExposure: eff, sourceWidth: c0.image.width, sourceHeight: c0.image.height)
    }
}

/// TIFF 16 biți RGB necomprimat, little-endian, valori sRGB codate (0…1 → 0…65535). Scriitor propriu mic (fără canal alfa, fără profil; profilul sRGB se atașează la export).
public enum TIFF16 {
    public static func write(rgb: [Float], width w: Int, height h: Int, to url: URL) throws {
        guard w > 0, h > 0, rgb.count == w * h * 3 else { throw PipelineError.badOutput("dimensiuni TIFF") }
        let dataBytes = w * h * 6; let entries = 9; let ifdOffset = 8 + dataBytes + 6 /* BitsPerSample */ + (dataBytes % 2)
        var d = Data(capacity: ifdOffset + 2 + entries * 12 + 4 + 8)
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: [0x49, 0x49]); u16(42); u32(ifdOffset)
        var px = [UInt16](repeating: 0, count: w * h * 3); for i in 0..<px.count { let v = rgb[i]; px[i] = UInt16(max(0, min(65535, (v.isFinite ? v : 0) * 65535 + 0.5))).littleEndian }
        px.withUnsafeBufferPointer { d.append(contentsOf: UnsafeRawBufferPointer($0)) }
        let bpsOffset = d.count; u16(16); u16(16); u16(16); if d.count % 2 == 1 { d.append(0) }
        precondition(d.count == ifdOffset, "TIFF: decalaj IFD")
        u16(entries)
        func entry(_ tag: Int, _ type: Int, _ count: Int, _ value: Int) { u16(tag); u16(type); u32(count); if type == 3 && count == 1 { u16(value); u16(0) } else { u32(value) } }
        entry(256, 4, 1, w); entry(257, 4, 1, h); entry(258, 3, 3, bpsOffset); entry(259, 3, 1, 1); entry(262, 3, 1, 2); entry(273, 4, 1, 8); entry(277, 3, 1, 3); entry(278, 4, 1, h); entry(279, 4, 1, dataBytes)
        u32(0)
        try d.write(to: url, options: .atomic)
    }
}

extension FloatImage {
    /// Intermediar în codul log al familiei: DWG liniar → gamutul familiei → codificarea familiei (aceleași funcții ca nucleul). DWG = DaVinci Intermediate, ca până acum.
    public func familyEncoded(_ f: WorkingFamily) -> FloatImage {
        if f == .dwg { return diEncoded() }
        var o = [Float](repeating: 0, count: rgb.count)
        rgb.withUnsafeBufferPointer { i in o.withUnsafeMutableBufferPointer { pc_convert_dwg_to_family(f.coreIndex, i.baseAddress, $0.baseAddress, i.count / 3) } }
        for k in 0..<o.count { o[k] = Float(pc_family_encode(f.coreIndex, Double(o[k]))) }
        return FloatImage(width: width, height: height, rgb: o)
    }
}
