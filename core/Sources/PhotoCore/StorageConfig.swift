import Foundation

/// Locația de lucru aleasă de utilizator (clientul): UN folder organizat de aplicație care conține biblioteca (catalog, miniaturi/previzualizări, cache de analiză, intermediare/temporare).
/// Originalele rămân oriunde, nemutate și necopiate; destinația exportului e separată (aleasă per lot, ultima alegere reținută în catalog).
/// Discul se identifică prin UUID-ul volumului (nu doar prin nume) + bookmark; calea e doar indiciu.
public struct StorageLocation: Codable, Equatable {
    public var root: String                // folderul ales de utilizator (părintele bibliotecii)
    public var volumeUUID: String?         // identitatea volumului la momentul alegerii
    public var volumeName: String?         // doar pentru afișare
    public var relativePath: String        // `root` relativ la punctul de montare al volumului (supraviețuiește schimbării punctului de montare)
    public var bookmark: Data?             // bookmark (cu scope de securitate când aplicația e sandboxată; altfel simplu)
    public init(root: String, volumeUUID: String?, volumeName: String?, relativePath: String, bookmark: Data?) { self.root = root; self.volumeUUID = volumeUUID; self.volumeName = volumeName; self.relativePath = relativePath; self.bookmark = bookmark }
}

public enum StorageHealth: Equatable {
    case ok(freeBytes: Int64)
    case missing(volumeName: String?, path: String)          // discul/folderul nu e disponibil (deconectat, schimbat, redenumit fără potrivire de UUID)
    case volumeChanged(expected: String?, found: String?)    // aceeași cale, alt volum
    case notWritable(path: String)
    case lowSpace(freeBytes: Int64, neededBytes: Int64)
    public var isOK: Bool { if case .ok = self { return true }; return false }
    /// Pune în pauză operațiile care scriu (spațiul scăzut doar avertizează).
    public var blocks: Bool { switch self { case .ok, .lowSpace: return false; default: return true } }
    /// Mesaj pentru utilizator: ce disc/folder trebuie reconectat.
    public var message: String {
        switch self {
        case .ok(let f): return LF("Disponibil · %@ liberi", StorageFormat.bytes(f))
        case .missing(let n, let p): return LF("Discul de lucru nu este disponibil%@. Reconectează-l; folderul așteptat: %@. Operațiile care îl folosesc sunt în pauză, rezultatele deja terminate sunt păstrate.", n.map { " („\($0)”)" } ?? "", p)
        case .volumeChanged(let e, let f): return LF("Calea există, dar pe alt disc (așteptat %@, găsit %@). Nu scriu pe un disc necunoscut.", e ?? L("necunoscut"), f ?? L("necunoscut"))
        case .notWritable(let p): return LF("Folderul de lucru nu poate fi scris: %@. Verifică permisiunile discului.", p)
        case .lowSpace(let f, let n): return LF("Spațiu insuficient pe discul de lucru: %@ liberi, %@ necesari.", StorageFormat.bytes(f), StorageFormat.bytes(n))
        }
    }
}

public enum StorageFormat {
    /// Dimensiuni cu unitățile zecimale ale sistemului (KB/MB/GB/TB) și separatorul zecimal al limbii aplicației.
    public static func bytes(_ b: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]; var v = Double(max(0, b)); var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        let f = NumberFormatter(); f.locale = Localizer.shared.locale; f.numberStyle = .decimal; f.minimumFractionDigits = 0; f.maximumFractionDigits = i == 0 ? 0 : (v < 10 ? 2 : (v < 100 ? 1 : 0))
        return (f.string(from: NSNumber(value: v)) ?? "\(v)") + " " + units[i]
    }
}

/// Categoriile afișate utilizatorului. Doar cele `regenerable` pot fi curățate; catalogul (decizii, reglaje, măști, profiluri, albume) nu e niciodată cache.
public enum StorageCategory: String, CaseIterable, Identifiable {
    case catalog, previews, analysis, intermediates, results, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .catalog: return L("Bibliotecă / catalog")
        case .previews: return L("Miniaturi și previzualizări")
        case .analysis: return L("Cache de analiză (culling, ML)")
        case .intermediates: return L("Intermediare și temporare")
        case .results: return L("Rezultate randate (cache)")
        case .other: return L("Alte fișiere ale aplicației")
        }
    }
    public var regenerable: Bool { switch self { case .catalog, .other: return false; default: return true } }
    /// Ce se pierde la curățare (afișat înainte de confirmare).
    public var consequence: String {
        switch self {
        case .catalog: return L("Conține deciziile, reglajele, măștile, profilurile și albumele tale. Nu se curăță.")
        case .previews: return L("Miniaturile și previzualizările se regenerează la nevoie din originale (mai lent la prima deschidere).")
        case .analysis: return L("Rezultatele analizei fețelor se recalculează la următoarea analiză.")
        case .intermediates: return L("Fișierele intermediare (EXR pentru Resolve etc.) se reface la următoarea predare în Resolve.")
        case .results: return L("Rezultatele randate se randează din nou din reglajele păstrate în catalog.")
        case .other: return L("Neidentificat ca regenerabil; nu se curăță.")
        }
    }
}

public struct StorageUsage: Equatable { public var category: StorageCategory; public var bytes: Int64; public var files: Int }

/// Structura bibliotecii în interiorul folderului de lucru.
public enum StorageLayout {
    public static let libraryFolder = "FotoAsist GC"
    public static func library(in root: URL) -> URL { root.appendingPathComponent(libraryFolder, isDirectory: true) }
    public static let catalogFiles = ["catalog.sqlite", "catalog.sqlite-wal", "catalog.sqlite-shm"]
    static let previewsDir = "cache"
    static let intermediateDirs = ["work/handoff", "work/resolve/intermediates"]
    static let resultDirs = ["work/own/results", "work/resolve/results"]
}

public enum StorageConfig {
    // MARK: identitate de volum
    public struct VolumeInfo: Equatable { public var uuid: String?; public var name: String?; public var mount: URL? }
    public static func volumeInfo(for url: URL) -> VolumeInfo {
        var u = url; while !FileManager.default.fileExists(atPath: u.path), u.pathComponents.count > 1 { u.deleteLastPathComponent() }
        let v = try? u.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeNameKey, .volumeURLKey])
        return VolumeInfo(uuid: v?.volumeUUIDString, name: v?.volumeName, mount: v?.volume)
    }
    public static func mountedVolume(uuid: String) -> VolumeInfo? {
        let keys: [URLResourceKey] = [.volumeUUIDStringKey, .volumeNameKey]
        for m in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? [] {
            let v = try? m.resourceValues(forKeys: Set(keys)); if v?.volumeUUIDString == uuid { return VolumeInfo(uuid: uuid, name: v?.volumeName, mount: m) }
        }
        return nil
    }

    // MARK: creare / rezolvare
    public static func make(root: URL) -> StorageLocation {
        let vi = volumeInfo(for: root); let rp = relative(root.standardizedFileURL.path, to: vi.mount?.standardizedFileURL.path)
        let bm = (try? root.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? (try? root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        return StorageLocation(root: root.standardizedFileURL.path, volumeUUID: vi.uuid, volumeName: vi.name, relativePath: rp, bookmark: bm)
    }
    static func relative(_ path: String, to mount: String?) -> String {
        guard let m = mount, path.hasPrefix(m) else { return path }
        var r = String(path.dropFirst(m.count)); while r.hasPrefix("/") { r.removeFirst() }; return r
    }
    /// Calea curentă a folderului de lucru: ordinea de încredere = volumul după UUID (se adaptează la schimbarea punctului de montare), bookmark, calea scrisă.
    public static func resolve(_ loc: StorageLocation) -> URL? {
        if let id = loc.volumeUUID {
            guard let vol = mountedVolume(uuid: id), let m = vol.mount else { return nil }       // volumul cu ACEL UUID nu e montat → indisponibil (nu ghicim după nume)
            let u = loc.relativePath.isEmpty ? m : m.appendingPathComponent(loc.relativePath, isDirectory: true)
            return u
        }
        if let b = loc.bookmark { var stale = false; if let u = try? URL(resolvingBookmarkData: b, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) ?? URL(resolvingBookmarkData: b, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) { return u } }
        return URL(fileURLWithPath: loc.root)
    }

    // MARK: sănătate
    public static func freeBytes(at url: URL) -> Int64? {
        var u = url; while !FileManager.default.fileExists(atPath: u.path), u.pathComponents.count > 1 { u.deleteLastPathComponent() }
        let v = try? u.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let i = v?.volumeAvailableCapacityForImportantUsage { return i }; return v?.volumeAvailableCapacity.map(Int64.init)
    }
    /// Verificare înainte de procesare: există, e pe același volum, se poate scrie (încercare reală), are spațiu minim.
    public static func health(_ loc: StorageLocation, minFreeBytes: Int64 = 512 * 1_048_576) -> (health: StorageHealth, url: URL?) {
        guard let u = resolve(loc), FileManager.default.fileExists(atPath: u.path) else { return (.missing(volumeName: loc.volumeName, path: loc.root), nil) }
        if let want = loc.volumeUUID, let got = volumeInfo(for: u).uuid, want != got { return (.volumeChanged(expected: want, found: got), nil) }
        guard canWrite(u) else { return (.notWritable(path: u.path), u) }
        let free = freeBytes(at: u) ?? 0
        if free < minFreeBytes { return (.lowSpace(freeBytes: free, neededBytes: minFreeBytes), u) }
        return (.ok(freeBytes: free), u)
    }
    public static func canWrite(_ dir: URL) -> Bool {
        let t = dir.appendingPathComponent(".fa-write-test-\(ProcessInfo.processInfo.processIdentifier)")
        guard (try? Data("x".utf8).write(to: t)) != nil else { return false }; try? FileManager.default.removeItem(at: t); return true
    }
    /// Verifică o destinație de export (alt disc posibil) înainte de lot: scriere + spațiu pentru `needed` octeți.
    public static func checkExportDestination(_ dir: URL, needed: Int64) -> StorageHealth {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return .missing(volumeName: volumeInfo(for: dir).name, path: dir.path) }
        guard canWrite(dir) else { return .notWritable(path: dir.path) }
        let free = freeBytes(at: dir) ?? 0
        return free < needed ? .lowSpace(freeBytes: free, neededBytes: needed) : .ok(freeBytes: free)
    }

    // MARK: spațiu pe categorii
    static func size(of url: URL) -> (bytes: Int64, files: Int) {
        var isDir: ObjCBool = false; guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return (0, 0) }
        if !isDir.boolValue { return (((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0, 1) }
        var b: Int64 = 0, n = 0
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: []) {
            for case let f as URL in e { let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]); if v?.isRegularFile == true { b += Int64(v?.fileSize ?? 0); n += 1 } }
        }
        return (b, n)
    }
    /// `analysis`: (număr de rânduri, octeți) din catalog — rezultatele de analiză trăiesc în catalog, nu în fișiere.
    public static func usage(library: URL, analysis: (count: Int, bytes: Int64) = (0, 0)) -> [StorageUsage] {
        func sum(_ rel: [String]) -> (Int64, Int) { rel.map { size(of: library.appendingPathComponent($0)) }.reduce((0, 0)) { ($0.0 + $1.bytes, $0.1 + $1.files) } }
        let cat = sum(StorageLayout.catalogFiles), prev = sum([StorageLayout.previewsDir]), inter = sum(StorageLayout.intermediateDirs), res = sum(StorageLayout.resultDirs)
        let total = size(of: library)
        let analysisBytes = analysis.bytes
        let known = cat.0 + prev.0 + inter.0 + res.0
        return [StorageUsage(category: .catalog, bytes: cat.0, files: cat.1),
                StorageUsage(category: .previews, bytes: prev.0, files: prev.1),
                StorageUsage(category: .analysis, bytes: analysisBytes, files: analysis.count),
                StorageUsage(category: .intermediates, bytes: inter.0, files: inter.1),
                StorageUsage(category: .results, bytes: res.0, files: res.1),
                StorageUsage(category: .other, bytes: max(0, total.bytes - known), files: max(0, total.files - cat.1 - prev.1 - inter.1 - res.1))]
    }
    /// Șterge conținutul unei categorii REGENERABILE (fișiere); întoarce octeții eliberați. `analysis` se curăță din catalog (apelantul).
    @discardableResult public static func clean(_ category: StorageCategory, library: URL) throws -> Int64 {
        guard category.regenerable, category != .analysis else { return 0 }
        let rels: [String] = category == .previews ? [StorageLayout.previewsDir] : category == .intermediates ? StorageLayout.intermediateDirs : StorageLayout.resultDirs
        var freed: Int64 = 0
        let libStd = library.standardizedFileURL.path + "/"
        for r in rels {
            let d = library.appendingPathComponent(r).standardizedFileURL
            guard d.path.hasPrefix(libStd), FileManager.default.fileExists(atPath: d.path) else { continue }     // nu se iese niciodată din bibliotecă
            for f in try FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) { freed += size(of: f).bytes; try FileManager.default.removeItem(at: f) }
        }
        return freed
    }
}

// MARK: migrare controlată
public enum StorageMigrationError: Error, CustomStringConvertible {
    case destinationNotEmpty(String), notEnoughSpace(free: Int64, needed: Int64), verifyFailed(String), cancelled, sameLocation
    public var description: String {
        switch self {
        case .destinationNotEmpty(let p): return LF("Destinația conține deja o bibliotecă FotoAsist: %@. Alege alt folder sau golește-l.", p)
        case .notEnoughSpace(let f, let n): return LF("Spațiu insuficient la destinație: %@ liberi, %@ necesari.", StorageFormat.bytes(f), StorageFormat.bytes(n))
        case .verifyFailed(let m): return LF("Verificarea copiei a eșuat: %@. Locația veche rămâne activă și neatinsă.", m)
        case .cancelled: return L("Migrare anulată; locația veche rămâne activă.")
        case .sameLocation: return L("Aceeași locație.")
        }
    }
}

/// Migrare: COPIERE → VERIFICARE → (apelantul comută). Sursa nu se modifică și nu se șterge. Catalogul (deschis) se copiază printr-un instantaneu consistent (`snapshotCatalog`).
public enum StorageMigration {
    public struct Report: Equatable { public var files: Int; public var bytes: Int64; public var destination: URL }
    public static func run(from srcLibrary: URL, toRoot dstRoot: URL, snapshotCatalog: (URL) throws -> Void, verifyCatalog: (URL) throws -> Bool,
                           progress: ((Double, String) -> Void)? = nil, isCancelled: () -> Bool = { false }) throws -> Report {
        let fm = FileManager.default
        let dst = StorageLayout.library(in: dstRoot)
        if dst.standardizedFileURL == srcLibrary.standardizedFileURL { throw StorageMigrationError.sameLocation }
        if fm.fileExists(atPath: dst.appendingPathComponent("catalog.sqlite").path) { throw StorageMigrationError.destinationNotEmpty(dst.path) }
        try fm.createDirectory(at: dstRoot, withIntermediateDirectories: true)
        let total = StorageConfig.size(of: srcLibrary)
        let need = total.bytes + total.bytes / 20 + 64 * 1_048_576
        let free = StorageConfig.freeBytes(at: dstRoot) ?? 0
        if free < need { throw StorageMigrationError.notEnoughSpace(free: free, needed: need) }
        // copiem într-un folder temporar de lângă destinație și îl redenumim la final: la un eșec nu rămâne o bibliotecă pe jumătate scrisă
        let tmp = dstRoot.appendingPathComponent(".fa-migrate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        do {
            var done: Int64 = 0, count = 0
            let catalogSet = Set(StorageLayout.catalogFiles)
            let srcStd = srcLibrary.standardizedFileURL.path + "/"
            try snapshotCatalog(tmp.appendingPathComponent("catalog.sqlite"))
            if let e = fm.enumerator(at: srcLibrary, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey], options: []) {
                for case let f as URL in e {
                    if isCancelled() { throw StorageMigrationError.cancelled }
                    let rel = String(f.standardizedFileURL.path.dropFirst(srcStd.count))
                    let v = try f.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])
                    if v.isDirectory == true { try fm.createDirectory(at: tmp.appendingPathComponent(rel), withIntermediateDirectories: true); continue }
                    guard v.isRegularFile == true, !catalogSet.contains(rel) else { continue }
                    let to = tmp.appendingPathComponent(rel); try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: f, to: to)                                                    // copiere de nucleu (copyfile): fără acumulare în RAM
                    done += Int64(v.fileSize ?? 0); count += 1
                    progress?(total.bytes > 0 ? Double(done) / Double(total.bytes) : 1, rel)
                }
            }
            // verificare: aceleași fișiere cu aceleași mărimi + catalogul copiat se deschide și conține aceleași date
            let cmp = try compare(src: srcLibrary, dst: tmp, skip: catalogSet)
            if let bad = cmp { throw StorageMigrationError.verifyFailed(bad) }
            guard try verifyCatalog(tmp.appendingPathComponent("catalog.sqlite")) else { throw StorageMigrationError.verifyFailed("catalogul copiat nu corespunde") }
            if isCancelled() { throw StorageMigrationError.cancelled }
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }                        // doar un folder gol/fără catalog (verificat mai sus)
            try fm.moveItem(at: tmp, to: dst)
            return Report(files: count + 1, bytes: done, destination: dst)
        } catch { try? fm.removeItem(at: tmp); throw error }
    }
    /// nil = identice; altfel prima diferență.
    static func compare(src: URL, dst: URL, skip: Set<String>) throws -> String? {
        let fm = FileManager.default; let s = src.standardizedFileURL.path + "/"
        guard let e = fm.enumerator(at: src, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else { return nil }
        for case let f as URL in e {
            let v = try f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]); guard v.isRegularFile == true else { continue }
            let rel = String(f.standardizedFileURL.path.dropFirst(s.count)); if skip.contains(rel) { continue }
            let t = dst.appendingPathComponent(rel)
            let tv = try? t.resourceValues(forKeys: [.fileSizeKey])
            if tv?.fileSize != v.fileSize { return LF("%@ lipsește sau are altă mărime", rel) }
        }
        return nil
    }
}

/// Pointerul de bootstrap (în afara bibliotecii, fiindcă biblioteca însăși e ceea ce se localizează).
public final class StorageConfigStore {
    private let defaults: UserDefaults; private let key = "storage.location.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var location: StorageLocation? {
        get { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(StorageLocation.self, from: $0) } }
        set { if let n = newValue, let d = try? JSONEncoder().encode(n) { defaults.set(d, forKey: key) } else { defaults.removeObject(forKey: key) } }
    }
    /// Propunerea implicită pentru primul start: un singur folder organizat de aplicație.
    public static var suggestedRoot: URL { FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser }
}
