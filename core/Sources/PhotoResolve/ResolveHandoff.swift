import Foundation
import PhotoCore

/// „Continuă în Resolve”: pregătește fotografia în pagina Color a DaVinci Resolve Studio, cu lanțul de noduri-etapă FotoAsist (1 Liniar · 2 Log · 3 GDC DRT), într-o VERSIUNE de culoare proprie, fără Fusion.
/// Mecanism: proiect Resolve propriu (`FOTOASIST_GC_COLOR`) → intermediar EXR (DI/DWG) → cronologie → versiune nouă → grad DRX generat (drx_chain.py). Nu suprascrie niciodată versiunile existente ale fotografului; fiecare apel creează o versiune NOUĂ.
/// Limite reale: API-ul Resolve nu adaugă OFX pe noduri (DRX e mecanismul); recuperarea înapoi = doar parametrii pluginului FotoAsist (≠ implicit) + rezultatul randat din Resolve; NU măști, keyframe-uri sau alte efecte. Necesită DaVinci Resolve Studio.
public enum HandoffError: Error, CustomStringConvertible {
    case pluginMissing, needsConsent(String), stagesUnavailable(String), familiesUnavailable(String, String)
    public var description: String {
        switch self {
        case .pluginMissing: return L("Componenta FotoAsist GC OFX nu e instalată în /Library/OFX/Plugins (FotoAsistGC.ofx.bundle). Fără ea nodurile din Resolve nu ar procesa imaginea.")
        case .stagesUnavailable(let v): return LF("OFX FotoAsist GC %@ nu separă etapele: un lanț de 3 noduri ar rula de trei ori traseul complet (de trei ori GDC DRT). Actualizează la 0.3.0 sau mai nou; nu se creează un lanț greșit.", v)
        case .familiesUnavailable(let v, let f): return LF("OFX FotoAsist GC %@ nu cunoaște familiile de lucru: nodurile ar interpreta imaginea în familia DaVinci în loc de «%@». Actualizează la 0.4.0 sau mai nou, sau alege familia DaVinci; nu se creează un lanț greșit.", v, f)
        case .needsConsent(let p): return LF("Resolve are deschis proiectul „%@”. Pentru a pregăti fotografia, FotoAsist trebuie să deschidă proiectul propriu (proiectul curent se salvează, nu se șterge).", p)
        }
    }
}
public struct HandoffResult: Equatable { public var timeline: String, version: String, applied: Bool, nodes: [String], stageParam: Bool, ofxVersion: String }
public struct HandoffReadback: Equatable { public var version: String; public var nodes: [(index: Int, label: String, params: [String: String])]
    public static func == (a: HandoffReadback, b: HandoffReadback) -> Bool { a.version == b.version && a.nodes.count == b.nodes.count } }

public final class ResolveHandoff {
    public static let projectName = "FOTOASIST_GC_COLOR"
    public static let bundlePath = "/Library/OFX/Plugins/FotoAsistGC.ofx.bundle"
    /// Versiunea OFX instalată (CFBundleShortVersionString) sau nil.
    public static func installedOFXVersion() -> String? {
        guard let d = NSDictionary(contentsOfFile: bundlePath + "/Contents/Info.plist") else { return nil }; return d["CFBundleShortVersionString"] as? String
    }
    /// Separarea pe etape (`Stage`) există de la OFX 0.3.0.
    public static func supportsStages(_ v: String?) -> Bool { guard let v = v else { return false }; return v.compare("0.3.0", options: .numeric) != .orderedAscending }

    /// Familiile de lucru (`phFamily`) există de la OFX 0.4.0.
    public static func supportsFamilies(_ v: String?) -> Bool { guard let v = v else { return false }; return v.compare("0.4.0", options: .numeric) != .orderedAscending }

    private let bridge: ResolveBridge
    public init() throws { bridge = try ResolveBridge(); try bridge.start() }
    deinit { bridge.stop() }
    public var info: ResolveInfo? { bridge.info }

    /// Deschide proiectul propriu; `allowSwitch` doar după acordul explicit al utilizatorului (proiectul curent se salvează).
    public func ensureProject(allowSwitch: Bool) throws {
        do { try bridge.ensureProject(ResolveHandoff.projectName, allowSwitch: allowSwitch) }
        catch BridgeError.remote(let code, _) where code == "switch_not_allowed" { throw HandoffError.needsConsent(bridge.info?.currentProject ?? L("alt proiect")) }
    }
    public func handoff(exr: URL, width: Int, height: Int, timelineName: String, adjustments a: AdjustmentSet, estimate: Double?, output: Int = 0) throws -> HandoffResult {
        guard let v = ResolveHandoff.installedOFXVersion() else { throw HandoffError.pluginMissing }
        let stage = ResolveHandoff.supportsStages(v); guard stage else { throw HandoffError.stagesUnavailable(v) }   // niciodată un lanț în care toate nodurile rulează traseul complet
        if a.family != .dwg && !ResolveHandoff.supportsFamilies(v) { throw HandoffError.familiesUnavailable(v, a.family.label) }
        let adj: [String: Double] = ["family": Double(a.family.rawValue), "exposure": a.effectiveExposure(estimate: estimate), "temperature": a.temperature, "tint": a.tint, "shadows": a.shadows, "highlights": a.highlights, "contrast": a.contrast, "saturation": a.saturation]
        let r = try bridge.call(["op": "handoff", "project": ResolveHandoff.projectName, "timelineName": timelineName, "exr": exr.path, "width": width, "height": height, "adjustments": adj, "stageParam": stage, "output": output], timeout: 240)
        return HandoffResult(timeline: r["timeline"] as? String ?? "", version: r["version"] as? String ?? "", applied: r["applied"] as? Bool ?? false, nodes: r["nodes"] as? [String] ?? [], stageParam: stage, ofxVersion: v)
    }
    /// Apel SEPARAT, ulterior aplicării (graful nu se citește în același apel): etichete și pluginuri pe noduri.
    public func verify(timeline: String? = nil) throws -> [(index: Int, label: String, tools: [String])] {
        let r = try bridge.call(["op": "handoff_verify", "timeline": timeline as Any], timeout: 60)
        return (r["nodes"] as? [[String: Any]] ?? []).map { ($0["index"] as? Int ?? 0, $0["label"] as? String ?? "", $0["tools"] as? [String] ?? []) }
    }
    /// Reglajele MANUALE ale pluginului FotoAsist din gradul curent (doar parametrii ≠ implicit) — fără măști, keyframe-uri sau alte efecte.
    public func readBack(timeline: String? = nil) throws -> HandoffReadback {
        let r = try bridge.call(["op": "handoff_read", "timeline": timeline as Any], timeout: 90)
        var v = "?"; if let cv = r["version"] as? [String: Any] { v = cv["versionName"] as? String ?? "?" }
        let chain = r["chain"] as? [[String: Any]] ?? []
        return HandoffReadback(version: v, nodes: chain.map { n in
            var ps: [String: String] = [:]; for (k, x) in (n["params"] as? [String: Any] ?? [:]) { if let d = x as? Double { ps[k] = String(format: "%.3f", d) } else if let c = x as? [Any], c.count == 2 { ps[k] = LF("opțiunea %@", c[1]) } else { ps[k] = "\(x)" } }
            return (n["index"] as? Int ?? 0, n["label"] as? String ?? "", ps) })
    }
    /// Rezultatul REAL din Resolve (toate nodurile, inclusiv ce a adăugat fotograful) randat într-un TIFF 16 biți.
    public func render(to dir: URL, name: String, width: Int, height: Int, timeline: String? = nil) throws -> URL {
        let r = try bridge.call(["op": "handoff_render", "outDir": dir.path, "name": name, "width": width, "height": height, "timeline": timeline as Any], timeout: 300)
        return URL(fileURLWithPath: r["output"] as? String ?? "")
    }
}
