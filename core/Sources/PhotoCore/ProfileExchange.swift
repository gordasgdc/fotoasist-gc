import Foundation
import CryptoKit

/// Export / import de profil personal: fișier JSON VERSIONAT (`gdc.personal-profile/1`) cu suma de control SHA-256 a conținutului. Conține NUMAI parametrii estimați + metadate tehnice de compatibilitate.
/// NU conține: fotografiile de antrenare, căile, hash-urile și id-urile perechilor, numele fotografului sau al setului, date personale, credențiale. Importul doar PARSEAZĂ și VALIDEAZĂ date (niciun cod executat), refuză fișiere mari/incompatibile/alterate,
/// tratează duplicatele și NU transformă un profil experimental în unul evaluat: evaluarea originală nu se transferă (rămâne text informativ), iar profilul importat e marcat «IMPORTAT · neevaluat pe exemplele tale».
public enum ProfileExchange {
    public static let format = "gdc.personal-profile/1"
    public static let maxBytes = 256 * 1024
    public struct Body: Codable, Equatable {
        public var name: String; public var version: Int
        public var engineIdentity: String; public var estimatorVersion: Int; public var paramSet: [String]
        public var parameters: ProfileParameters
        public var pairCount: Int; public var heldOutCount: Int
        public var originTrustLabel: String          // text informativ: cum era etichetat la sursă; NU se aplică la import
    }
    public struct Package: Codable, Equatable { public var format: String; public var exportedBy: String; public var exportedAt: String; public var body: Body; public var sha256: String }
    public enum ImportError: Error, Equatable, CustomStringConvertible {
        case tooLarge, notAProfile, wrongFormat(String), checksumMismatch, notEstimated, incompatibleEngine(file: String, current: String), incompatibleParameters, invalidValues(String)
        public var description: String {
            switch self {
            case .tooLarge: return L("Fișierul e prea mare pentru un profil (peste 256 KB).")
            case .notAProfile: return L("Fișierul nu este un profil FotoAsist valid (JSON necitibil sau câmpuri lipsă).")
            case .wrongFormat(let f): return LF("Format neacceptat: «%@». Se acceptă %@.", f, format)
            case .checksumMismatch: return L("Suma de control nu se potrivește: fișierul a fost modificat sau corupt. Nu s-a importat nimic.")
            case .notEstimated: return L("Profilul din fișier nu are o estimare (e doar ciornă).")
            case .incompatibleEngine(let f, let c): return LF("Profilul a fost estimat cu alt motor sau alt set de parametri (fișier: %@; aici: %@). Re-estimează-l local din exemple.", f, c)
            case .incompatibleParameters: return L("Setul de parametri din fișier nu corespunde cu cel al acestei versiuni.")
            case .invalidValues(let w): return LF("Valori neașteptate în profil: %@.", w)
            }
        }
    }
    public enum ImportOutcome: Equatable { case added(PersonalProfile), duplicate(existing: PersonalProfile) }

    private static func canonical(_ b: Body) throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try e.encode(b) }
    private static func digest(_ b: Body) throws -> String { SHA256.hash(data: try canonical(b)).map { String(format: "%02x", $0) }.joined() }

    /// Exportă un profil ESTIMAT. `engineIdentity`/`paramSet` = ale motorului curent (pentru verificarea la import); `trustLabel` = eticheta de încredere de la sursă (informativă).
    public static func export(_ p: PersonalProfile, engineIdentity: String, paramSet: [String], trustLabel: String, now: Date = Date()) throws -> Data {
        guard p.status == .estimated else { throw ImportError.notEstimated }
        let body = Body(name: p.name, version: p.version, engineIdentity: engineIdentity, estimatorVersion: p.estimatorVersion ?? 1, paramSet: paramSet, parameters: p.parameters,
                        pairCount: p.pairIDs.count, heldOutCount: p.heldOutPairIDs?.count ?? 0, originTrustLabel: trustLabel)
        let f = ISO8601DateFormatter(); let pkg = Package(format: format, exportedBy: "FotoAsist GC", exportedAt: f.string(from: now), body: body, sha256: try digest(body))
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return try e.encode(pkg)
    }
    /// Validează fără a modifica nimic; întoarce corpul sau eroarea clară.
    public static func inspect(_ data: Data, engineIdentity: String, paramSet: [String]) -> Result<Body, ImportError> {
        guard data.count <= maxBytes else { return .failure(.tooLarge) }
        guard let pkg = try? JSONDecoder().decode(Package.self, from: data) else { return .failure(.notAProfile) }
        guard pkg.format == format else { return .failure(.wrongFormat(pkg.format)) }
        guard let d = try? digest(pkg.body), d == pkg.sha256 else { return .failure(.checksumMismatch) }
        let b = pkg.body
        guard b.engineIdentity == engineIdentity else { return .failure(.incompatibleEngine(file: b.engineIdentity, current: engineIdentity)) }
        guard b.paramSet == paramSet else { return .failure(.incompatibleParameters) }
        for (grp, dict) in [("adaptiv", b.parameters.adaptive), ("creativ", b.parameters.creative)] {
            for (k, v) in dict {
                guard paramSet.contains(k) else { return .failure(.invalidValues(LF("parametru necunoscut «%@» în grupul %@", k, grp))) }
                guard v.median.isFinite, abs(v.median) <= 5, v.spread.isFinite, v.spread >= 0, v.spread <= 5, (0...100_000).contains(v.count) else { return .failure(.invalidValues(LF("«%@» în afara intervalului", k))) }
            }
        }
        guard !b.name.trimmingCharacters(in: .whitespaces).isEmpty, b.name.count <= 120, b.version >= 1, b.version < 10_000 else { return .failure(.invalidValues("nume sau versiune")) }
        return .success(b)
    }
    /// Importă în registru, ca profil NOU legat de fotograful/setul alese de utilizator acum (în fișier nu există). Duplicat (aceleași valori + același nume în același fotograf/set) ⇒ nu se adaugă.
    public static func importProfile(_ data: Data, into reg: inout ProfileRegistry, photographer: String, setName: String, engineIdentity: String, paramSet: [String], engineVersionLabel: String, now: Date = Date()) -> Result<ImportOutcome, ImportError> {
        switch inspect(data, engineIdentity: engineIdentity, paramSet: paramSet) {
        case .failure(let e): return .failure(e)
        case .success(let b):
            let sameScope = reg.profiles.filter { $0.photographer == photographer && $0.setName == setName }
            if let dup = sameScope.first(where: { $0.parameters == b.parameters && $0.status == .estimated }) { return .success(.duplicate(existing: dup)) }
            var name = b.name; var n = 1
            while sameScope.contains(where: { $0.name == name }) { n += 1; name = n == 2 ? "\(b.name) (importat)" : "\(b.name) (importat \(n - 1))" }
            let v = (sameScope.filter { $0.name == name }.map { $0.version }.max() ?? 0) + 1
            var p = PersonalProfile(name: name, photographer: photographer, setName: setName, version: v, pairIDs: [], engineVersion: engineVersionLabel, parameters: b.parameters)
            p.status = .estimated; p.estimatorVersion = b.estimatorVersion; p.paramSet = b.paramSet; p.estimatedAt = now
            p.evaluation = LF("Importat dintr-un fișier de schimb. Evaluarea originală (%@) NU se transferă: profilul nu e evaluat pe exemplele tale. Transferabilitatea între camere și iluminări rămâne de evaluat.", b.originTrustLabel)
            p.importedFrom = L("fișier · ") + ISO8601DateFormatter().string(from: now)
            reg.profiles.append(p); return .success(.added(p))
        }
    }
}
