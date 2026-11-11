import Foundation
import CryptoKit

/// „Creează profilul meu” — INFRASTRUCTURĂ (2026-10-21). Registru local de perechi RAW–final, confirmarea EXPLICITĂ a exemplelor, identitatea și versiunea profilului, separarea parametrilor.
/// NU estimează nimic încă: estimarea și evaluarea profilului real așteaptă exemplele APROBATE (și pragul minim de perechi, decizia proprietarului). Presetările (Natural/Intens/Catifelat) NU sunt profil învățat și nu pot crea unul.
/// Fără cloud, fără ML. Stocare: JSON în `session_kv` (cheia `profile_registry_v1`) al catalogului local. Materialele primite pentru evaluare (scripts/materials_ingest.py) NU devin exemple fără alegere + confirmare aici.
public enum PairState: String, Codable { case proposed, confirmed, rejected }
public enum GeometryCheck: String, Codable { case notChecked, passed, failed }   // alinierea reală (dimensiune + corelație de fază) se face la estimare; aici doar evidența

public struct ExamplePair: Codable, Equatable, Identifiable {
    public var id: String = UUID().uuidString
    public var photographer: String, setName: String
    public var rawPath: String, rawSHA256: String, rawBytes: Int64
    public var finalPath: String, finalSHA256: String, finalBytes: Int64
    public var addedAt: Date = Date()
    public var state: PairState = .proposed
    public var confirmedAt: Date?
    /// Textul confirmării afirmat de fotograf (aceeași fotografie + acord pentru folosirea ca exemplu de învățare locală). Gol ⇒ neconfirmată.
    public var confirmationStatement: String = ""
    public var geometry: GeometryCheck = .notChecked
    public var note: String = ""
    /// `learning_approved` din protocolul de materiale: adevărat DOAR pentru perechi confirmate explicit.
    public var learningApproved: Bool { state == .confirmed && !confirmationStatement.isEmpty }
}

public enum ProfileSource: String, Codable { case learnedFromExamples }          // presetările NU au sursă de profil
public enum ProfileStatus: String, Codable { case draft, estimated }

/// Un parametru estimat (viitor): valoare mediană și dispersie pe perechile confirmate; `nil` până la estimare.
public struct ParameterEstimate: Codable, Equatable { public var median: Double, spread: Double, count: Int; public init(median: Double, spread: Double, count: Int) { self.median = median; self.spread = spread; self.count = count } }
/// Separarea parametrilor (cerința proprietarului): tehnic ≠ adaptiv la scenă ≠ creativ stabil ≠ corecții locale.
public struct ProfileParameters: Codable, Equatable {
    /// TEHNIC: interpretarea RAW (politici de decodare) — nu se învață din finaluri; se consemnează politica folosită, ca profilul să rămână reproductibil.
    public var technicalPolicy: String
    public init(technicalPolicy: String) { self.technicalPolicy = technicalPolicy }
    /// ADAPTIV: reguli de adaptare a expunerii și balansului la fotografia curentă (viitor; fără ele expunerea unei scene întunecate NU devine regulă universală).
    public var adaptive: [String: ParameterEstimate] = [:]
    /// CREATIV STABIL: preferințe globale repetabile exprimabile prin parametrii nucleului (contrast, saturație, umbre, lumini, deplasări de temperatură/tentă).
    public var creative: [String: ParameterEstimate] = [:]
    /// Corecțiile LOCALE și efectele NU intră în profil (specifice cadrului); lista fixă documentează ce rămâne ne-reprezentabil.
    public static let notRepresentable = [L("corecții locale (măști)"), L("retușuri / dodge & burn"), L("curbe de formă arbitrară"), L("HSL pe nuanțe"), "balans de alb pe regiuni", "grain / claritate / reducere de zgomot", L("decupări")]
    public static let estimable = ["contrast", "saturation", "shadows", "highlights", "temperature offset", "tint offset", L("exposure offset față de estimare (adaptiv)")]
}

public struct PersonalProfile: Codable, Equatable, Identifiable {
    public var id: String = UUID().uuidString
    public var name: String, photographer: String, setName: String
    public var version: Int = 1
    public var status: ProfileStatus = .draft
    public var source: ProfileSource = .learnedFromExamples
    public var createdAt: Date = Date()
    public var pairIDs: [String]                       // DOAR perechi confirmate, ale aceluiași fotograf și set
    /// Identitatea motorului la crearea profilului (profilul se evaluează față de ACEST motor; o schimbare de motor cere re-evaluare, nu schimbă tăcut profilul).
    public var engineVersion: String
    public var parameters: ProfileParameters
    /// Estimare (după aplicarea estimatorului): versiunea lui, setul de parametri estimați, ce NU s-a estimat, rezultatul evaluării pe perechi REȚINUTE, perechi reținute/excluse. `nil` la ciorne.
    public var estimatorVersion: Int? = nil
    public var paramSet: [String]? = nil
    public var notEstimated: [String]? = nil
    public var evaluation: String? = nil
    public var heldOutPairIDs: [String]? = nil
    public var excluded: [String]? = nil
    public var estimatedAt: Date? = nil
    /// Rezultatele evaluării pe perechi reținute, structurate (eticheta «evaluat» descrie protocolul și aceste rezultate, nu doar numărul de fotografii).
    public var evalHeld: Int? = nil, evalImproved: Int? = nil
    public var evalBaselineDE: Double? = nil, evalProfileDE: Double? = nil
    public var evalConsistent: Bool? = nil
    /// Profil IMPORTAT dintr-un fișier de schimb (`ProfileExchange`): arată provenința; evaluarea originală NU se transferă (nu devine «evaluat» pe exemplele acestui utilizator).
    public var importedFrom: String? = nil
    public init(name: String, photographer: String, setName: String, version: Int = 1, pairIDs: [String], engineVersion: String, parameters: ProfileParameters) { self.name = name; self.photographer = photographer; self.setName = setName; self.version = version; self.pairIDs = pairIDs; self.engineVersion = engineVersion; self.parameters = parameters }
    public var note: String { status == .draft ? L("Ciornă: perechi confirmate înregistrate; nicio estimare efectuată (așteaptă exemplele aprobate și pragul minim).") : "" }
}

public enum ProfileRegistryError: Error, Equatable, CustomStringConvertible {
    case sameFile, notConfirmedStatementMissing, noConfirmedPairs, mixedPhotographers, unknownPair, fileUnreadable(String)
    public var description: String {
        switch self {
        case .sameFile: return L("RAW-ul și finalul sunt același fișier.")
        case .notConfirmedStatementMissing: return L("Confirmarea cere declarația explicită a fotografului.")
        case .noConfirmedPairs: return L("Profilul cere cel puțin o pereche confirmată explicit.")
        case .mixedPhotographers: return L("Un profil folosește perechile unui singur fotograf și ale unui singur set; nu se amestecă.")
        case .unknownPair: return L("Pereche necunoscută.")
        case .fileUnreadable(let p): return LF("Fișier ilizibil: %@", p)
        }
    }
}

public struct ProfileRegistry: Codable, Equatable {
    public var pairs: [ExamplePair] = []
    public var profiles: [PersonalProfile] = []
    /// Pragul minim de perechi pentru a estima un profil: decizia proprietarului, NEluată; `nil` = nedecis ⇒ niciun profil nu devine eligibil pentru estimare.
    public var minConfirmedPairs: Int? = nil
    public static let sessionKey = "profile_registry_v1"
    /// PRAG PROPUS (nu cerut proprietarului), derivat din numărul de parametri estimabili și din evaluarea pe exemple SEPARATE de cele de ajustare:
    /// profilul estimează 7 parametri globali (contrast, saturație, umbre, lumini, deplasare de temperatură, de tentă, offset de expunere față de estimare), fiecare ca mediană + dispersie pe perechi (un vector de 7 valori per pereche). O mediană și o dispersie robustă (MAD) devin
    /// stabile de la ~8 observații; evaluarea cere perechi REȚINUTE (nefolosite la ajustare), minimum 3 ca eroarea să aibă o dispersie. ⇒ EXPERIMENTAL: ≥ 8 perechi de ajustare + ≥ 3 reținute = 11 confirmate (fără promisiune de generalizare);
    /// EVALUAT: ≥ 16 + ≥ 8 reținute = 24 confirmate și ≥ 3 situații de lumină diferite (altfel regula adaptivă de expunere nu se estimează). Pragurile sunt propuneri documentate, revizuibile de proprietar; nu blochează înregistrarea perechilor.
    public static let experimentalFit = 8, experimentalHeldOut = 3, evaluatedFit = 16, evaluatedHeldOut = 8
    public static var experimentalMinPairs: Int { experimentalFit + experimentalHeldOut }
    /// Cel mai mic set eligibil pentru un profil EXPERIMENTAL de set mic: 4 perechi confirmate (3 de ajustare + 1 reținută). Evaluarea cu < 3 reținute e doar INDICATIVĂ (fără dispersie); nu autorizează eticheta «evaluat».
    public static let minimumPairs = 4
    public static var evaluatedMinPairs: Int { evaluatedFit + evaluatedHeldOut }
    /// Împărțire DETERMINISTĂ și disjunctă ajustare / reținute (după hash-ul RAW): fiecare a 4-a pereche (≈ 25%) e reținută pentru evaluare și NU intră niciodată în ajustare.
    public static func split(_ pairs: [ExamplePair]) -> (fit: [ExamplePair], heldOut: [ExamplePair]) {
        let sorted = pairs.sorted { $0.rawSHA256 < $1.rawSHA256 }; var fit: [ExamplePair] = [], held: [ExamplePair] = []
        for (i, p) in sorted.enumerated() { if i % 4 == 3 { held.append(p) } else { fit.append(p) } }
        return (fit, held)
    }
    public static let confirmationText = L("Confirm că RAW-ul și finalul sunt aceeași fotografie și accept să fie folosite ca exemplu pentru profilul meu local.")
    public init() {}

    public static func sha256(of path: String) throws -> (hex: String, bytes: Int64) {
        guard let f = FileHandle(forReadingAtPath: path) else { throw ProfileRegistryError.fileUnreadable(path) }; defer { try? f.close() }
        var h = SHA256(); var n: Int64 = 0
        while true { let d = f.readData(ofLength: 4 << 20); if d.isEmpty { break }; h.update(data: d); n += Int64(d.count) }
        return (h.finalize().map { String(format: "%02x", $0) }.joined(), n)
    }

    /// Înregistrează o pereche PROPUSĂ (nu confirmată). Hash-urile se calculează în flux; originalele nu se ating. Aceeași pereche (hash RAW + hash final) nu se dublează.
    @discardableResult public mutating func addPair(raw: String, final: String, photographer: String, setName: String) throws -> ExamplePair {
        if URL(fileURLWithPath: raw).standardizedFileURL == URL(fileURLWithPath: final).standardizedFileURL { throw ProfileRegistryError.sameFile }
        let r = try ProfileRegistry.sha256(of: raw), f = try ProfileRegistry.sha256(of: final)
        if r.hex == f.hex { throw ProfileRegistryError.sameFile }
        if let e = pairs.first(where: { $0.rawSHA256 == r.hex && $0.finalSHA256 == f.hex }) { return e }
        let p = ExamplePair(photographer: photographer, setName: setName, rawPath: raw, rawSHA256: r.hex, rawBytes: r.bytes, finalPath: final, finalSHA256: f.hex, finalBytes: f.bytes)
        pairs.append(p); return p
    }
    /// Confirmarea EXPLICITĂ: doar cu declarația fotografului (textul afișat în aplicație). Fără declarație nu se confirmă nimic.
    public mutating func confirm(_ id: String, statement: String) throws {
        guard let i = pairs.firstIndex(where: { $0.id == id }) else { throw ProfileRegistryError.unknownPair }
        guard statement == ProfileRegistry.confirmationText else { throw ProfileRegistryError.notConfirmedStatementMissing }
        pairs[i].state = .confirmed; pairs[i].confirmedAt = Date(); pairs[i].confirmationStatement = statement
    }
    public mutating func reject(_ id: String) throws { guard let i = pairs.firstIndex(where: { $0.id == id }) else { throw ProfileRegistryError.unknownPair }; pairs[i].state = .rejected; pairs[i].confirmedAt = nil; pairs[i].confirmationStatement = "" }
    public mutating func remove(_ id: String) { pairs.removeAll { $0.id == id }; profiles = profiles.map { var p = $0; p.pairIDs.removeAll { $0 == id }; return p } }
    public func confirmedPairs(photographer: String, setName: String) -> [ExamplePair] { pairs.filter { $0.learningApproved && $0.photographer == photographer && $0.setName == setName } }

    /// Ciornă de profil dintr-un set de perechi CONFIRMATE ale unui singur fotograf/set. Nu estimează. `engineVersion` = identitatea motorului la creare. Versiunea crește pentru același nume/fotograf/set.
    public mutating func makeDraftProfile(name: String, pairIDs: [String], engineVersion: String, technicalPolicy: String) throws -> PersonalProfile {
        let sel = pairs.filter { pairIDs.contains($0.id) }
        guard !sel.isEmpty, sel.allSatisfy({ $0.learningApproved }) else { throw ProfileRegistryError.noConfirmedPairs }
        guard Set(sel.map { $0.photographer }).count == 1, Set(sel.map { $0.setName }).count == 1 else { throw ProfileRegistryError.mixedPhotographers }
        let v = (profiles.filter { $0.name == name && $0.photographer == sel[0].photographer && $0.setName == sel[0].setName }.map { $0.version }.max() ?? 0) + 1
        let p = PersonalProfile(name: name, photographer: sel[0].photographer, setName: sel[0].setName, version: v, pairIDs: sel.map { $0.id }, engineVersion: engineVersion, parameters: ProfileParameters(technicalPolicy: technicalPolicy))
        profiles.append(p); return p
    }
    /// Memorează rezultatul unei estimări (status estimated). Parametrii vin DOAR din perechile de ajustare; evaluarea din cele reținute.
    public mutating func storeEstimate(profileID: String, parameters: ProfileParameters, estimatorVersion: Int, paramSet: [String], evaluation: String, heldOut: [String], excluded: [String], engineIdentity: String, evalDetail: (held: Int, baselineDE: Double, profileDE: Double, improved: Int, consistent: Bool)? = nil) {
        guard let i = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[i].parameters = parameters; profiles[i].status = .estimated; profiles[i].estimatorVersion = estimatorVersion; profiles[i].paramSet = paramSet; profiles[i].notEstimated = ProfileParameters.notRepresentable
        profiles[i].evaluation = evaluation; profiles[i].heldOutPairIDs = heldOut; profiles[i].excluded = excluded; profiles[i].estimatedAt = Date(); profiles[i].engineVersion = engineIdentity
        profiles[i].evalHeld = evalDetail?.held; profiles[i].evalBaselineDE = evalDetail?.baselineDE; profiles[i].evalProfileDE = evalDetail?.profileDE; profiles[i].evalImproved = evalDetail?.improved; profiles[i].evalConsistent = evalDetail?.consistent
    }
    /// Eligibilitatea pentru estimare: pragul trebuie decis ȘI atins. Estimarea reală NU e implementată: întoarce motivul exact.
    public func estimationBlocker(for p: PersonalProfile) -> String? {
        let m = minConfirmedPairs ?? ProfileRegistry.minimumPairs   // set mic eligibil (experimental); pragurile mai mari sunt propuneri de evaluare, nu condiții de estimare
        let n = p.pairIDs.count; if n < m { return LF("Perechi confirmate: %@ din %@ necesare pentru un profil EXPERIMENTAL de set mic (%@ de ajustare + 1 reținută pentru o evaluare indicativă). Cu %@ perechi evaluarea are dispersie; eticheta «evaluat» cere protocolul descris în fluxul profilului.", n, m, m - 1, ProfileRegistry.experimentalMinPairs) }
        return nil   // prag atins: estimarea poate rula (experimental; fără promisiune de generalizare)
    }

    public static func load(from c: Catalog) -> ProfileRegistry { (try? c.session(sessionKey)).flatMap { $0 }.flatMap { $0.data(using: .utf8) }.flatMap { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return try? d.decode(ProfileRegistry.self, from: $0) } ?? ProfileRegistry() }
    public func save(to c: Catalog) throws { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; try c.setSession(ProfileRegistry.sessionKey, String(data: try e.encode(self), encoding: .utf8)!) }
}
