import Foundation
import PhotoRaw
import CPhotoCore
import PhotoResolve

// Uz: PhotoDecode RAW OUT.exr [--family 0..3] [--crop default|active] [--white vendor|N] [--no-orient] [--keep-highlights] [--neutral-wb] [--linear]
// Scrie intermediarul float32 (implicit codat DaVinci Intermediate/DWG; --linear = DWG liniar) și tipărește raportul JSON.
var args = Array(CommandLine.arguments.dropFirst()); guard args.count >= 2 else { FileHandle.standardError.write(Data("uz: PhotoDecode RAW OUT.exr [opțiuni]\n".utf8)); exit(2) }
let input = args.removeFirst(), output = args.removeFirst(); var opt = DecodeOptions(); var linear = false; var family = WorkingFamily.dwg; var coreOut: String? = nil; var coreParams = pc_params(); pc_default_params(&coreParams)
var i = 0
while i < args.count {
    switch args[i] {
    case "--crop": i += 1; opt.crop = args[i] == "active" ? .activeArea : .defaultCrop
    case "--white": i += 1; opt.white = args[i] == "vendor" ? .vendorViaLibRaw : .explicit(Int(args[i]) ?? 0)
    case "--no-orient": opt.applyOrientation = false
    case "--keep-highlights": opt.highlight = .keep
    case "--highlight": i += 1; opt.highlight = HighlightPolicy(rawValue: args[i]) ?? .clipWhite
    case "--half": opt.halfSize = true
    case "--neutral-wb": opt.wb = .neutral
    case "--linear": linear = true
    case "--family": i += 1; family = WorkingFamily(rawValue: Int(args[i]) ?? 0) ?? .dwg   // intermediar în codul log al familiei (DWG = DaVinci Intermediate)
    case "--core-out": i += 1; coreOut = args[i]                      // scrie și rezultatul NUCLEULUI propriu (TIFF 16 sRGB) din intermediarul DI/DWG
    case "--p": i += 1; for kv in args[i].split(separator: ",") { let a = kv.split(separator: "="); guard a.count == 2, let v = Double(a[1]) else { continue }
        switch a[0] { case "exposure": coreParams.exposure = v; case "temperature": coreParams.temperature = v; case "tint": coreParams.tint = v; case "shadows": coreParams.shadows = v; case "highlights": coreParams.highlights = v
        case "drtout": coreParams.drtOutput = Int32(v); case "contrast": coreParams.contrast = v; case "pivot": coreParams.pivot = v; case "saturation": coreParams.saturation = v; case "drt": coreParams.drt = Int32(v); default: break } }
    default: FileHandle.standardError.write(Data("opțiune necunoscută: \(args[i])\n".utf8)); exit(2)
    }
    i += 1
}
do {
    let t0 = Date(); let d = try RawFile(path: input).decodeLinearDWG(opt); let t1 = Date()
    try FloatImageIO.writeEXR(linear ? d.image : d.image.familyEncoded(family), to: URL(fileURLWithPath: output)); let t2 = Date()
    if let co = coreOut { let enc = d.image.familyEncoded(family); coreParams.family = family.coreIndex; var o = [Float](repeating: 0, count: enc.rgb.count); var p = coreParams; p.inputIsLinear = 0
        if p.drt == 2 { _ = GDCDRTData.load(devRoot: ProcessInfo.processInfo.environment["GDC_PA_ROOT"]); if case .loaded = GDCDRTData.status {} else { FileHandle.standardError.write(Data("datele GDC DRT indisponibile: \(GDCDRTData.status)\n".utf8)); exit(4) } }
        _ = enc.rgb.withUnsafeBufferPointer { a in o.withUnsafeMutableBufferPointer { b in pc_process_image(&p, a.baseAddress, b.baseAddress, Int32(enc.width), Int32(enc.height), 0) } }; try TIFF16.write(rgb: o, width: enc.width, height: enc.height, to: URL(fileURLWithPath: co)) }
    let r = d.report; let sg = ExposureSuggestion.compute(from: d.image)
    let json: [String: Any] = ["input": input, "output": output, "width": d.image.width, "height": d.image.height, "encoding": linear ? "DWG-linear" : (family == .dwg ? "DaVinciIntermediate/DWG" : family.id),
        "make": r.make, "model": r.model, "libraw": r.libRawVersion, "black": r.whitePlan.black, "white": r.whitePlan.white, "vendorWhite": r.whitePlan.vendorWhite, "adcMax": r.whitePlan.adcMax, "headroomStops": r.whitePlan.headroomStops,
        "appliedCrop": [r.appliedCrop.x, r.appliedCrop.y, r.appliedCrop.w, r.appliedCrop.h], "defaultCropSource": r.cropPlan.defaultCropSource.rawValue, "flip": r.orientationFlip,
        "wb": r.wbMultipliers.map { Double($0) }, "fracChannelOverWhiteAfterWB": r.fracChannelOverWhiteAfterWB, "highlight": r.highlight.rawValue, "causes": ["rawAboveReference": r.causes.rawAboveReference, "whiteBalanceOnly": r.causes.whiteBalanceOnly, "adcSaturated": r.causes.adcSaturated, "matrixOnly": r.causes.matrixOnly], "linMin": Double(r.linMin), "linMax": Double(r.linMax), "fracNegative": r.fracNegative,
        "suggestedStops": sg.stops, "medianToGrey": sg.medianToGrey, "highlightAnchor": sg.highlightAnchor, "lowKey": sg.lowKeyWarning, "median": sg.median, "p99": sg.p99, "sceneHint": sg.sceneHint, "decodeSeconds": t1.timeIntervalSince(t0), "writeSeconds": t2.timeIntervalSince(t1)]
    print(String(data: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]), encoding: .utf8)!)
} catch { FileHandle.standardError.write(Data("eroare: \(error)\n".utf8)); exit(1) }
