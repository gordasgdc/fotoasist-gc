import XCTest
import ImageIO
import CoreGraphics
import CPhotoCore
@testable import PhotoResolve
@testable import PhotoRaw

final class OwnCoreTests: XCTestCase {
    func testTIFF16WriterRoundTripsThroughImageIOWithThreeChannels() throws {
        let w = 13, h = 7; var rgb = [Float](); for i in 0..<(w * h * 3) { rgb.append(Float(i % 251) / 250) }
        let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("t16_\(UUID().uuidString).tif"); defer { try? FileManager.default.removeItem(at: u) }
        try TIFF16.write(rgb: rgb, width: w, height: h, to: u)
        let src = CGImageSourceCreateWithURL(u as CFURL, nil)!; let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        XCTAssertEqual(img.width, w); XCTAssertEqual(img.height, h); XCTAssertEqual(img.bitsPerComponent, 16); XCTAssertEqual(img.bitsPerPixel, 48)
        let data = img.dataProvider!.data!; let p = CFDataGetBytePtr(data)!; let bpr = img.bytesPerRow
        for y in 0..<h { for x in 0..<w { for c in 0..<3 { let o = y * bpr + x * 6 + c * 2; let v = Int(p[o]) | Int(p[o + 1]) << 8; let vb = Int(p[o]) << 8 | Int(p[o + 1])
            let expect = Int(rgb[(y * w + x) * 3 + c] * 65535 + 0.5); XCTAssertTrue(v == expect || vb == expect, "px \(x),\(y),\(c)") } } }
    }
    func testAdjustmentMappingToCoreParams() {
        var a = AdjustmentSet(); a.exposure = 1.5; a.temperature = 20; a.tint = -0.01; a.shadows = 0.5; a.highlights = -0.5; a.contrast = 1.2; a.saturation = 0.9
        let p = a.coreParams(estimate: 9, inputIsLinear: true)
        XCTAssertEqual(p.exposure, 1.5); XCTAssertEqual(p.temperature, 20); XCTAssertEqual(p.tint, -0.01); XCTAssertEqual(p.shadows, 0.5); XCTAssertEqual(p.highlights, -0.5); XCTAssertEqual(p.contrast, 1.2); XCTAssertEqual(p.saturation, 0.9); XCTAssertEqual(p.inputIsLinear, 2); XCTAssertEqual(p.family, 0)   /* scene-liniar DWG → gamutul familiei; DWG implicit */; XCTAssertEqual(p.drt, Edition.full ? 2 : 1); XCTAssertEqual(p.drtProfile, 0); XCTAssertEqual(p.drtOutput, 2)   // implicit: GDC DRT Natural adaptat, sRGB
        XCTAssertEqual(a.coreParams(estimate: nil, inputIsLinear: true, output: .p1Experimental).drt, 1)                                  // p1 doar explicit
        a.exposureAuto = true; a.autoOffset = 0.5; XCTAssertEqual(a.coreParams(estimate: 2, inputIsLinear: false).exposure, 2.5)
    }
    /// Pe un RAW real (previzualizare): rezultatul nucleului propriu e determinist, cache-ul de rezultat funcționează, expunerea efectivă e raportată, originalul rămâne neatins; exportul poartă ICC sRGB.
    // MARK: familii de lucru (selector → parametri nucleu → procesare)
    func testFamilyReachesCoreParamsAndLocalCorrections() {
        for f in WorkingFamily.allCases {
            var a = AdjustmentSet(); a.family = f; a.locals = [{ var l = LocalCorrection(); l.exposure = 0.5; return l }()]
            XCTAssertEqual(a.coreParams(estimate: nil, inputIsLinear: true).family, f.coreIndex)
            XCTAssertEqual(LocalCorrection.coreLocals(a.locals, family: a.family).first?.adj.family, f.coreIndex, "corecția lucrează în aceeași familie ca ajustarea globală")
            XCTAssertEqual(String(cString: pc_family_id(f.coreIndex)), f.id, "identificatorul tehnic = cel din nucleu/STYLE")
        }
        XCTAssertEqual(WorkingFamily.allCases.count, Int(pc_family_count()))
    }
    /// Pe fiecare familie: expunerea e câștig LINEAR (în gamutul familiei), neutrii rămân neutri, ieșirea e finită; familii diferite dau coduri log diferite pentru aceleași valori.
    func testExposureIsLinearGainInEveryFamilyAndNeutralsStayNeutral() {
        var codes: [Double] = []
        for f in WorkingFamily.allCases {
            var a = AdjustmentSet(); a.family = f; a.exposure = 1
            var p = a.coreParams(estimate: nil, inputIsLinear: true); p.drt = 0            // cod log al familiei, fără DRT
            let grays: [Float] = [0.0045, 0.18, 0.5, 2.0, 8.0]
            for g in grays {
                var o = [Float](repeating: 0, count: 3); let i: [Float] = [g, g, g]; pc_process_pixel_c(&p, i, &o)
                XCTAssertEqual(o[0], o[1], accuracy: 1e-5, "neutru R=G \(f.id)"); XCTAssertEqual(o[1], o[2], accuracy: 1e-5, "neutru G=B \(f.id)")
                let lin = pc_family_decode(f.coreIndex, Double(o[1])); XCTAssertEqual(lin, 2 * Double(g), accuracy: 2e-5 * max(1, 2 * Double(g)), "câștig 2^1 în liniar \(f.id) @\(g)")
            }
            var o = [Float](repeating: 0, count: 3); let i: [Float] = [0.18, 0.18, 0.18]; var q = a.coreParams(estimate: nil, inputIsLinear: true); q.exposure = 0; q.drt = 0; pc_process_pixel_c(&q, i, &o); codes.append(Double(o[1]))
        }
        XCTAssertEqual(Set(codes.map { String(format: "%.4f", $0) }).count, 4, "gri 18% codat diferit în fiecare familie (ACEScct, LogC3, LogC4, DI)")
    }
    func testMissingDRTDataFailsExplicitlyWithoutSilentFallback() throws {
        // fără date, `pc_process_image` refuză (cod 2) și nu scrie nimic; stratul Swift ridică eroare explicită (testat doar dacă datele nu sunt încărcate în acest proces)
        guard pc_drt_available() == 0 else { throw XCTSkip("datele sunt deja încărcate în proces") }
        var p = pc_params(); pc_default_params(&p); p.drt = 2; var o = [Float](repeating: -1, count: 3); let i: [Float] = [0.4, 0.4, 0.4]
        XCTAssertEqual(pc_process_image(&p, i, &o, 1, 1, 1), 2); XCTAssertEqual(o, [-1, -1, -1])
    }
    func testRealRawThroughOwnCoreAndExport() throws {
        guard let dir = ProcessInfo.processInfo.environment["GDC_PA_RAW_DIR"], let scratch = ProcessInfo.processInfo.environment["GDC_PA_SCRATCH"] else { throw XCTSkip("fără GDC_PA_RAW_DIR / GDC_PA_SCRATCH") }
        let photo = dir + "/IMG_3504.CR2"; guard FileManager.default.fileExists(atPath: photo) else { throw XCTSkip("OMITERE motivată: lipsește IMG_3504.CR2 din GDC_PA_RAW_DIR (testul cere acest fișier și dimensiunile lui 3120×2080); nu e un eșec al codului") }
        let m0 = try FileManager.default.attributesOfItem(atPath: photo)[.modificationDate] as? Date
        let work = URL(fileURLWithPath: scratch).appendingPathComponent("owncore_\(UUID().uuidString.prefix(6))"); defer { try? FileManager.default.removeItem(at: work) }
        let proc = try OwnCoreProcessor(workDir: work); var a = AdjustmentSet(); a.exposure = 1.0
        let r1 = try proc.process(photoPath: photo, quality: .preview, adjustments: a); XCTAssertFalse(r1.fromResultCache); XCTAssertEqual(r1.effectiveExposure, 1.0)
        XCTAssertEqual(r1.width, 3120); XCTAssertEqual(r1.height, 2080)
        let r2 = try proc.process(photoPath: photo, quality: .preview, adjustments: a); XCTAssertTrue(r2.fromResultCache); XCTAssertEqual(r1.url, r2.url)
        var b = a; b.exposure = 2.0; let r3 = try proc.process(photoPath: photo, quality: .preview, adjustments: b); XCTAssertTrue(r3.fromIntermediateCache); XCTAssertNotEqual(r3.url, r1.url)
        let exp = try ExportService.export(result: r3.url, original: URL(fileURLWithPath: photo), to: work.appendingPathComponent("out"), name: "t", format: .tiff16)
        let src = CGImageSourceCreateWithURL(exp as CFURL, nil)!; let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!; XCTAssertEqual(img.bitsPerComponent, 16); XCTAssertTrue((img.colorSpace?.name as String?)?.lowercased().contains("srgb") ?? false)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: photo)[.modificationDate] as? Date, m0)
    }
}
