import Foundation

public enum BridgeError: Error, Equatable, CustomStringConvertible {
    case resolveNotInstalled, resolveNotRunning, workerMissing, startFailed(String), remote(code: String, message: String), protocolError(String), terminated
    public var description: String {
        switch self {
        case .resolveNotInstalled: return "DaVinci Resolve Studio nu este instalat în locația standard."
        case .resolveNotRunning: return "DaVinci Resolve nu rulează. Pornește-l și permite scriptarea locală (Preferences → General → External scripting using: Local)."
        case .workerMissing: return "Lipsește scriptul punții Resolve din pachet."
        case .startFailed(let m): return "Puntea Resolve nu a pornit: \(m)"
        case .remote(let c, let m): return "Resolve: \(m) [\(c)]"
        case .protocolError(let m): return "Răspuns neașteptat de la punte: \(m)"
        case .terminated: return "Puntea Resolve s-a oprit."
        }
    }
}

public struct ResolveInfo: Equatable { public var version: String, product: String, python: String, currentProject: String?
    /// Interfața de scriptare a fost verificată doar pe seria 21.1 (Studio). Alte versiuni: funcționează poate, dar NU sunt verificate.
    public var verified: Bool { product.contains("Studio") && version.hasPrefix("21.1.") } }

/// Punte către Resolve: procesul Python livrat în Resolve (ResolvePython) rulează `resolve_worker.py` (stdlib-only), JSON pe linii. Dependență de compatibilitate, nu interfață stabilă garantată.
public final class ResolveBridge {
    public static let appPath = "/Applications/DaVinci Resolve/DaVinci Resolve.app"
    public static var pythonPath: String { appPath + "/Contents/Resources/ResolvePython/ResolvePython" }
    public static let scriptingAPI = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
    public static var scriptingLib: String { appPath + "/Contents/Libraries/Fusion/fusionscript.so" }
    public static var isResolveRunning: Bool { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); p.arguments = ["-x", "Resolve"]; p.standardOutput = Pipe()
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false } }

    private let proc = Process(); private let inPipe = Pipe(), outPipe = Pipe()
    private var buffer = Data(); private var nextID = 1; private let lock = NSLock()
    public private(set) var info: ResolveInfo?
    public let workerURL: URL
    /// Folderul temporar al worker-ului (stills DRX etc.): în folderul de lucru al utilizatorului, nu în TMPDIR-ul de sistem.
    public let tempDir: URL?

    public init(workerURL: URL? = nil, tempDir: URL? = nil) throws {
        self.tempDir = tempDir
        guard FileManager.default.isExecutableFile(atPath: ResolveBridge.pythonPath) else { throw BridgeError.resolveNotInstalled }
        guard let w = workerURL ?? Bundle.main.url(forResource: "resolve_worker", withExtension: "py") ?? ModuleBundle.optional?.url(forResource: "resolve_worker", withExtension: "py") else { throw BridgeError.workerMissing }   // în .app: Resources/ (fără Bundle.module, care ar căuta lângă rădăcina pachetului)
        self.workerURL = w
    }
    deinit { stop() }

    public func start() throws {
        guard ResolveBridge.isResolveRunning else { throw BridgeError.resolveNotRunning }
        proc.executableURL = URL(fileURLWithPath: ResolveBridge.pythonPath); proc.arguments = [workerURL.path]
        var env = ProcessInfo.processInfo.environment; env["RESOLVE_SCRIPT_API"] = ResolveBridge.scriptingAPI; env["RESOLVE_SCRIPT_LIB"] = ResolveBridge.scriptingLib
        if let t = tempDir { try? FileManager.default.createDirectory(at: t, withIntermediateDirectories: true); env["TMPDIR"] = t.path; env["FOTOASIST_TEMP_ROOT"] = t.path }
        proc.environment = env; proc.standardInput = inPipe; proc.standardOutput = outPipe; proc.standardError = Pipe()
        do { try proc.run() } catch { throw BridgeError.startFailed(error.localizedDescription) }
        let h = try call(["op": "hello"], timeout: 30)
        info = ResolveInfo(version: h["version"] as? String ?? "?", product: h["product"] as? String ?? "?", python: h["python"] as? String ?? "?", currentProject: h["currentProject"] as? String)
    }
    public func stop() { if proc.isRunning { _ = try? send(["op": "quit"]); proc.terminate() } }

    private func send(_ obj: [String: Any]) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        var o = obj; let id = nextID; nextID += 1; o["id"] = id
        let data = try JSONSerialization.data(withJSONObject: o) + Data("\n".utf8)
        inPipe.fileHandleForWriting.write(data); return id
    }
    private func readLine(timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout); let fd = outPipe.fileHandleForReading.fileDescriptor
        while true {
            if let nl = buffer.firstIndex(of: 10) {
                let line = buffer.subdata(in: buffer.startIndex..<nl); buffer.removeSubrange(buffer.startIndex...nl)
                guard let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw BridgeError.protocolError(String(data: line, encoding: .utf8) ?? "?") }
                return j
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0); let remaining = Int32(max(0, deadline.timeIntervalSinceNow * 1000))
            if remaining == 0 { throw BridgeError.protocolError("timeout") }
            let r = poll(&pfd, 1, min(remaining, 500))
            if r > 0 { var tmp = [UInt8](repeating: 0, count: 65536); let n = read(fd, &tmp, tmp.count); if n <= 0 { throw BridgeError.terminated }; buffer.append(contentsOf: tmp[0..<n]) }
            else if !proc.isRunning && buffer.isEmpty { throw BridgeError.terminated }
        }
    }
    /// Cerere sincronă (apelantul o rulează pe un fir de fundal). Răspunsul `ok:false` devine `BridgeError.remote`.
    @discardableResult public func call(_ req: [String: Any], timeout: TimeInterval = 120) throws -> [String: Any] {
        let id = try send(req)
        while true {
            let r = try readLine(timeout: timeout)
            if (r["id"] as? Int) != id && (r["id"] as? Int) != 0 { continue }
            if r["ok"] as? Bool == true { return r }
            throw BridgeError.remote(code: r["code"] as? String ?? "?", message: r["message"] as? String ?? "")
        }
    }

    public func ensureProject(_ name: String, allowSwitch: Bool) throws { _ = try call(["op": "ensure_project", "name": name, "allowSwitch": allowSwitch], timeout: 60) }
}
