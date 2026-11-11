import Foundation
import os

/// Jurnal structurat local (OBSERVABILITY_STANDARD): JSON pe linii, niveluri, session/job ID, rotație cu limită de dimensiune și număr, redactare la scriere (căi/nume de media → hash, secrete → ***), pachet de diagnostic exportabil.
/// Scrierea logului NU blochează și NU schimbă verdictul operației (erorile de log sunt înghițite; fallback = doar os_log).
public enum LogLevel: Int, Comparable, Codable, CustomStringConvertible { case trace = 0, debug, info, warning, error, critical
    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
    public var description: String { ["trace", "debug", "info", "warning", "error", "critical"][rawValue] }
}

public enum Redactor {
    /// Căile și numele fișierelor media devin `media#<hash8>.<ext>`; adresele de e-mail, tokenurile lungi și valorile după `key=`/`token=` etc. devin `***`. Hash stabil → corelabil, nu reversibil.
    public static func redact(_ s: String) -> String {
        var t = s
        t = replace(t, #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#) { _ in "***@***" }
        t = replace(t, #"(?i)\b(password|passwd|token|secret|apikey|api_key|serial|license|licence|key)\s*[=:]\s*\S+"#) { m in (m.split(whereSeparator: { $0 == "=" || $0 == ":" }).first.map(String.init) ?? "secret") + "=***" }
        t = replace(t, #"(/Users|/Volumes|/Library|/Applications|/private|/tmp|/var)/[^\s"',;:)\]]+"#) { p in pathToken(p) }
        t = replace(t, #"\b[A-Fa-f0-9]{32,}\b"#) { _ in "***" }
        return t
    }
    static func pathToken(_ p: String) -> String {
        let url = URL(fileURLWithPath: p); let ext = url.pathExtension.lowercased()
        var h: UInt64 = 0xcbf29ce484222325; for b in p.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return "media#" + String(format: "%08x", UInt32(truncatingIfNeeded: h ^ (h >> 32))) + (ext.isEmpty ? "" : "." + ext)
    }
    private static func replace(_ s: String, _ pattern: String, _ f: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        var out = ""; var last = s.startIndex; let ns = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard let r = Range(m.range, in: s) else { continue }; out += s[last..<r.lowerBound]; out += f(String(s[r])); last = r.upperBound
        }
        return out + s[last...]
    }
}

public final class DiagnosticLog {
    public struct Config { public var maxFileBytes = 1_000_000; public var maxFiles = 5; public var level: LogLevel = .info; public init() {} }
    public let directory: URL, sessionID: String, subsystem: String
    public private(set) var config: Config
    private let queue = DispatchQueue(label: "photoassist.log")
    private let os = Logger(subsystem: "dev.gordas.photoassist", category: "app")
    private let buildInfo: [String: String]
    private var debugUntil: Date?
    public static var shared: DiagnosticLog?

    public init(directory: URL, config: Config = Config(), version: String, build: String) {
        self.directory = directory; self.config = config; sessionID = String(UUID().uuidString.prefix(8)).lowercased(); subsystem = "photoassist"
        buildInfo = ["version": version, "build": build]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public var activeFile: URL { directory.appendingPathComponent("photoassist.log") }
    public var archives: [URL] { (1..<max(2, config.maxFiles)).map { directory.appendingPathComponent("photoassist.\($0).log") }.filter { FileManager.default.fileExists(atPath: $0.path) } }

    /// Debug extins, temporar și vizibil (apelantul afișează starea); revine la `info` la următoarea pornire sau după `minutes`.
    public func enableDebug(minutes: Int = 30) { queue.sync { debugUntil = Date().addingTimeInterval(Double(minutes) * 60) } }
    public var debugActive: Bool { queue.sync { if let d = debugUntil, d > Date() { return true }; return false } }
    private func effective() -> LogLevel { if let d = debugUntil, d > Date() { return .debug }; return config.level }

    public func log(_ level: LogLevel, _ sub: String, _ event: String, _ msg: String = "", job: String? = nil, durationMs: Double? = nil, error: Error? = nil, fields: [String: String] = [:]) {
        let sess = sessionID, bi = buildInfo
        queue.async { [self] in
            guard level >= effective() else { return }
            var rec: [String: Any] = ["ts": DiagnosticLog.iso.string(from: Date()), "level": level.description, "ver": bi["version"] ?? "?", "build": bi["build"] ?? "?", "platform": "macOS", "sub": sub, "event": event, "session": sess, "msg": Redactor.redact(msg)]
            if let j = job { rec["job"] = j }; if let d = durationMs { rec["dur_ms"] = (d * 10).rounded() / 10 }
            if let e = error { rec["error"] = Redactor.redact("\(type(of: e)): \(e)"); rec["error_code"] = (e as NSError).code; rec["error_domain"] = (e as NSError).domain }
            for (k, v) in fields { rec["f_" + k] = Redactor.redact(v) }
            os.log(level: level >= .error ? .error : .info, "\(sub, privacy: .public) \(event, privacy: .public)")
            guard let d = try? JSONSerialization.data(withJSONObject: rec, options: [.sortedKeys]) else { return }
            write(d + Data("\n".utf8))
        }
    }
    /// Operație cu început, rezultat și durată (și eroare): returnează valoarea sau relansează eroarea; logul nu influențează rezultatul.
    public func timed<T>(_ sub: String, _ event: String, job: String? = UUID().uuidString.prefix(8).lowercased().description, msg: String = "", _ body: () throws -> T) rethrows -> T {
        log(.info, sub, event + ".start", msg, job: job); let t0 = Date()
        do { let r = try body(); log(.info, sub, event + ".ok", msg, job: job, durationMs: Date().timeIntervalSince(t0) * 1000); return r }
        catch { log(.error, sub, event + ".fail", msg, job: job, durationMs: Date().timeIntervalSince(t0) * 1000, error: error); throw error }
    }
    public func flush() { queue.sync {} }

    private func write(_ line: Data) {
        do {
            let fm = FileManager.default
            if !fm.fileExists(atPath: activeFile.path) { fm.createFile(atPath: activeFile.path, contents: nil) }
            let size = (try? fm.attributesOfItem(atPath: activeFile.path)[.size] as? NSNumber)?.intValue ?? 0
            if size + line.count > config.maxFileBytes { try rotate() }
            let h = try FileHandle(forWritingTo: activeFile); defer { try? h.close() }; try h.seekToEnd(); try h.write(contentsOf: line)
        } catch { /* fallback: doar os_log; operația principală nu e afectată */ }
    }
    private func rotate() throws {
        let fm = FileManager.default; let n = max(2, config.maxFiles)
        try? fm.removeItem(at: directory.appendingPathComponent("photoassist.\(n - 1).log"))
        for i in stride(from: n - 2, through: 1, by: -1) { let a = directory.appendingPathComponent("photoassist.\(i).log"), b = directory.appendingPathComponent("photoassist.\(i + 1).log"); if fm.fileExists(atPath: a.path) { try? fm.removeItem(at: b); try fm.moveItem(at: a, to: b) } }
        try fm.moveItem(at: activeFile, to: directory.appendingPathComponent("photoassist.1.log")); fm.createFile(atPath: activeFile.path, contents: nil)
    }
    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]; f.timeZone = .current; return f }()

    // MARK: pachet de diagnostic (local, inspectabil; NU se încarcă automat)
    /// ZIP cu: logurile (deja redactate), `manifest.json` (versiune/build/platformă/setări tehnice nesensibile/ID sesiune) și, opțional, un raport al ultimului job. Nu conține fișiere media sau credențiale.
    @discardableResult public func exportDiagnostics(to destination: URL, settings: [String: String] = [:], lastJobReport: String? = nil) throws -> URL {
        flush(); let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("diag-\(sessionID)-\(UUID().uuidString.prefix(4))"); try fm.createDirectory(at: stage, withIntermediateDirectories: true); defer { try? fm.removeItem(at: stage) }
        for f in [activeFile] + archives where fm.fileExists(atPath: f.path) { try fm.copyItem(at: f, to: stage.appendingPathComponent(f.lastPathComponent)) }
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let manifest: [String: Any] = ["created": DiagnosticLog.iso.string(from: Date()), "version": buildInfo["version"] ?? "?", "build": buildInfo["build"] ?? "?", "platform": "macOS", "os": os, "session": sessionID,
                                       "files": ((try? fm.contentsOfDirectory(atPath: stage.path)) ?? []).sorted(), "settings": settings.mapValues { Redactor.redact($0) }, "note": "Pachet local; nu conține media sau credențiale; căile sunt redactate. Nu se trimite automat."]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: stage.appendingPathComponent("manifest.json"))
        if let r = lastJobReport { try Redactor.redact(r).write(to: stage.appendingPathComponent("last_job_report.txt"), atomically: true, encoding: .utf8) }
        try? fm.removeItem(at: destination)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); p.arguments = ["-c", "-k", "--keepParent", stage.path, destination.path]; try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw NSError(domain: "DiagnosticLog", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ditto a eșuat"]) }
        return destination
    }
}
