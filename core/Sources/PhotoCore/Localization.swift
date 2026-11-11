import Foundation
import Combine

/// Localizare RO / EN / ES. Sursa textelor este româna (cheia = textul românesc); traducerile sunt în `LocalizationTables`. Un text fără traducere rămâne în română (se numără și se raportează: `Localizer.missing`).
/// Nu se traduc: numele fișierelor, identificatorii tehnici, numele profilurilor și albumelor ale utilizatorului (nu trec prin `L`).
public enum AppLanguage: String, CaseIterable, Sendable {
    case system, ro, en, es
    public var nativeName: String { switch self { case .system: return ""; case .ro: return "Română"; case .en: return "English"; case .es: return "Español" } }
}

public final class Localizer: ObservableObject, @unchecked Sendable {
    public static let shared = Localizer()
    private static let key = "gdcpa.language"
    @Published public var choice: AppLanguage { didSet { UserDefaults.standard.set(choice.rawValue, forKey: Self.key); resolved = Self.resolve(choice) } }
    /// Limba efectivă (niciodată `.system`).
    @Published public private(set) var resolved: AppLanguage
    public private(set) var missing = Set<String>()
    private let lock = NSLock()
    public init(defaults: UserDefaults = .standard, preferred: [String] = Locale.preferredLanguages) {
        /* GDC_PA_LANG=ro|en|es: forțează limba (testele automate rulează în română, indiferent de sistem); nu se persistă */
        #if DEBUG
        let forced: AppLanguage? = defaults === UserDefaults.standard ? AppLanguage(rawValue: ProcessInfo.processInfo.environment["GDC_PA_LANG"] ?? "") : nil
        #else
        let forced: AppLanguage? = nil
        #endif
        let c = forced ?? AppLanguage(rawValue: defaults.string(forKey: Self.key) ?? "") ?? .system
        choice = c; resolved = Self.resolve(c, preferred: preferred)
    }
    /// «Urmează sistemul»: prima limbă preferată dintre RO/EN/ES; altă limbă a sistemului ⇒ engleză (româna rămâne doar la alegere explicită sau sistem românesc).
    public static func resolve(_ c: AppLanguage, preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        if c != .system { return c }
        for p in preferred { let code = String(p.lowercased().prefix(2)); if let l = AppLanguage(rawValue: code), l != .system { return l } }
        return .en
    }
    public var locale: Locale { Locale(identifier: resolved == .ro ? "ro_RO" : (resolved == .es ? "es_ES" : "en_GB")) }
    public func tr(_ ro: String) -> String {
        if resolved == .ro { return ro }
        if let t = LocalizationTables.table[resolved]?[ro] { return t }
        lock.lock(); missing.insert(ro); lock.unlock(); return ro
    }
    public func lf(_ ro: String, _ args: [Any]) -> String {
        var out = tr(ro); for a in args { if let r = out.range(of: "%@") { out.replaceSubrange(r, with: argText(a)) } }; return out
    }
    /// Numerele se scriu cu convențiile limbii (virgulă/punct zecimal, separator de mii); șirurile rămân ca atare.
    func argText(_ a: Any) -> String { if let i = a as? Int { return number(i) }; if let d = a as? Double { let f = NumberFormatter(); f.locale = locale; f.numberStyle = .decimal; f.maximumFractionDigits = 2; f.minimumFractionDigits = 0; return f.string(from: NSNumber(value: d)) ?? "\(d)" }; return "\(a)" }
    /// Număr cu separatori ai limbii (1.234 / 1,234).
    public func number(_ n: Int) -> String { let f = NumberFormatter(); f.locale = locale; f.numberStyle = .decimal; return f.string(from: NSNumber(value: n)) ?? "\(n)" }
    public func number(_ d: Double, fraction: Int = 1) -> String { let f = NumberFormatter(); f.locale = locale; f.numberStyle = .decimal; f.maximumFractionDigits = fraction; f.minimumFractionDigits = fraction; return f.string(from: NSNumber(value: d)) ?? "\(d)" }
    public func date(_ d: Date, time: Bool = false) -> String { let f = DateFormatter(); f.locale = locale; f.dateStyle = .medium; f.timeStyle = time ? .short : .none; return f.string(from: d) }
    /// Acord numeric: RO (1 fotografie · 5 fotografii · 20 de fotografii), EN/ES (one/other). `forms` = (singular, plural) ÎN ROMÂNĂ; traducerile sunt în `LocalizationTables.plural`.
    public func count(_ n: Int, _ roOne: String, _ roOther: String) -> String {
        switch resolved {
        case .ro: let m = n % 100; let de = (n >= 20 && (m == 0 || m >= 20)) ? "de " : ""; return "\(number(n)) \(n == 1 ? roOne : de + roOther)"
        case .en, .es, .system:
            let f = LocalizationTables.plural[resolved]?[roOne] ?? (roOne, roOther); return "\(number(n)) \(n == 1 ? f.0 : f.1)"
        }
    }
}

@inline(__always) public func L(_ ro: String) -> String { Localizer.shared.tr(ro) }
public func LF(_ ro: String, _ args: Any...) -> String { Localizer.shared.lf(ro, args) }
