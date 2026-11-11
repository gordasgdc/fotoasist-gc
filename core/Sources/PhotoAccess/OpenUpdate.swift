import Foundation

// Update check of the open-source edition: asks the public GitHub repository for its latest release.
// Nothing is downloaded or installed automatically; the result only offers the official installer page.

public enum PhotoUpdateSource {
    public static let repository = "gordasgdc/fotoasist-gc"
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    /// Hosts an installer link may point to. Anything else is rejected.
    public static let allowedHosts: Set<String> = ["github.com"]
}

public struct PhotoUpdateOffer: Equatable, Sendable {
    public let installed: String, version: String, build: Int?, size: Int64, sha256: String
    public let downloadURL: URL
    public let notes: [String: String]
}

public enum PhotoUpdateResult: Equatable, Sendable {
    case upToDate(installed: String, available: String)
    case updateAvailable(PhotoUpdateOffer)
    case offline
    /// The release description was rejected (unexpected tag, asset name or host): nothing is offered.
    case invalid(code: String)
    case failed(String)
}

public struct PhotoUpdateChecker: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> (Data, Int)
    let source: URL, fetch: Fetch
    public init(source: URL = PhotoUpdateSource.latestReleaseAPI, fetch: @escaping Fetch = PhotoUpdateChecker.liveFetch) { self.source = source; self.fetch = fetch }

    public static let liveFetch: Fetch = { url in
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("FotoAsistGC-update-check", forHTTPHeaderField: "User-Agent")
        let (d, resp) = try await URLSession(configuration: .ephemeral).data(for: r)
        return (d, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// "Cannot check" (offline / error) is not "up to date", and neither is a rejected release description.
    public func check(installedVersion: String) async -> PhotoUpdateResult {
        let data: Data, status: Int
        do { (data, status) = try await fetch(source) }
        catch let e as URLError where Self.offlineCodes.contains(e.code) { return .offline }
        catch { return .failed("network: \((error as NSError).domain) \((error as NSError).code)") }
        if status == 404 { return .failed("no published release yet") }
        guard status == 200 else { return .failed("HTTP \(status)") }
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = o["tag_name"] as? String else { return .invalid(code: "invalid_release:format") }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard let available = Self.parse(version) else { return .invalid(code: "invalid_release:version") }
        guard let installed = Self.parse(installedVersion) else { return .failed("installed version \(installedVersion) is not numeric") }
        if !Self.isNewer(available, than: installed) { return .upToDate(installed: installedVersion, available: version) }
        // The official installer carries the version in its file name; a release without it is not offered.
        let expected = "FotoAsistGC-\(version).pkg"
        guard let assets = o["assets"] as? [[String: Any]], let a = assets.first(where: { ($0["name"] as? String) == expected }),
              let s = a["browser_download_url"] as? String, let url = URL(string: s) else { return .invalid(code: "invalid_release:asset") }
        guard url.scheme == "https", let host = url.host, PhotoUpdateSource.allowedHosts.contains(host), url.lastPathComponent == expected else { return .invalid(code: "invalid_release:host") }
        let size = (a["size"] as? NSNumber)?.int64Value ?? 0
        let digest = (a["digest"] as? String).map { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : $0 } ?? ""
        return .updateAvailable(PhotoUpdateOffer(installed: installedVersion, version: version, build: nil, size: size, sha256: digest, downloadURL: url, notes: [:]))
    }

    /// "1.2.3" → [1, 2, 3]. Pre-release suffixes ("1.2.3-dev.4") are ignored for the comparison.
    static func parse(_ v: String) -> [Int]? {
        let core = v.split(separator: "-", maxSplits: 1).first.map(String.init) ?? v
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }
    }
    static func isNewer(_ a: [Int], than b: [Int]) -> Bool {
        for i in 0..<max(a.count, b.count) { let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0; if x != y { return x > y } }
        return false
    }
    static let offlineCodes: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff]
}
