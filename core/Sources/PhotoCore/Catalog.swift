import Foundation
import CryptoKit
import SQLite3

/// Catalogul sesiunii: SQLite, SEPARAT de originale (calea bazei o alege apelantul; nu se scrie nimic lângă fotografii).
/// Migrații versionate prin `PRAGMA user_version`; toate schimbările de stare sunt tranzacționale și reversibile.
public final class Catalog {
    public static let schemaVersion = 4
    private var db: OpaquePointer?
    public let url: URL

    public init(url: URL) throws {
        self.url = url
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw CatalogError.open(String(cString: sqlite3_errmsg(db)))
        }
        try exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
        try migrate()
    }
    deinit { sqlite3_close(db) }

    private func migrate() throws {
        let v = Int(try scalar("PRAGMA user_version") ?? 0)
        if v > Catalog.schemaVersion { throw CatalogError.invalid("catalog creat de o versiune mai nouă (\(v))") }
        if v < 1 {
            try exec("""
            BEGIN;
            CREATE TABLE photos(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              path TEXT NOT NULL UNIQUE,
              size INTEGER NOT NULL,
              mtime_ns INTEGER NOT NULL,
              decision TEXT NOT NULL DEFAULT 'check' CHECK(decision IN ('check','keep','reject')),
              rating INTEGER NOT NULL DEFAULT 0 CHECK(rating BETWEEN 0 AND 5),
              favorite INTEGER NOT NULL DEFAULT 0,
              group_id INTEGER,
              camera TEXT,
              captured_at REAL,
              preview_source TEXT
            );
            CREATE TABLE decision_log(id INTEGER PRIMARY KEY AUTOINCREMENT, photo_id INTEGER NOT NULL REFERENCES photos(id) ON DELETE CASCADE, at REAL NOT NULL, from_state TEXT, to_state TEXT NOT NULL);
            PRAGMA user_version=1;
            COMMIT;
            """)
        }
        if v < 2 {
            try exec("""
            BEGIN;
            CREATE TABLE previews(
              photo_id INTEGER NOT NULL REFERENCES photos(id) ON DELETE CASCADE, kind TEXT NOT NULL, file TEXT NOT NULL, w INTEGER NOT NULL, h INTEGER NOT NULL,
              source TEXT NOT NULL, for_size INTEGER NOT NULL, for_mtime_ns INTEGER NOT NULL, PRIMARY KEY(photo_id, kind));
            CREATE TABLE signals(
              photo_id INTEGER PRIMARY KEY REFERENCES photos(id) ON DELETE CASCADE, version INTEGER NOT NULL, sharp REAL, clip_hi REAL, clip_lo REAL, median REAL, dhash INTEGER, hist BLOB, analyzed_at REAL);
            CREATE TABLE group_info(group_id INTEGER PRIMARY KEY, kind TEXT NOT NULL, confidence TEXT NOT NULL, reason TEXT NOT NULL);
            PRAGMA user_version=2;
            COMMIT;
            """)
        }
        if v < 3 {
            try exec("""
            BEGIN;
            CREATE TABLE edits(photo_id INTEGER PRIMARY KEY REFERENCES photos(id) ON DELETE CASCADE, json TEXT NOT NULL, updated_at REAL NOT NULL);
            CREATE TABLE session_kv(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE export_log(id INTEGER PRIMARY KEY AUTOINCREMENT, photo_id INTEGER NOT NULL REFERENCES photos(id) ON DELETE CASCADE, path TEXT NOT NULL, format TEXT NOT NULL, at REAL NOT NULL);
            PRAGMA user_version=3;
            COMMIT;
            """)
        }
        if v < 4 {   // albume = colecții VIRTUALE (nu ating originalele, editările sau grupurile de rafale); aceeași fotografie în mai multe albume
            try exec("""
            BEGIN;
            CREATE TABLE albums(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at REAL NOT NULL);
            CREATE TABLE album_photos(album_id INTEGER NOT NULL REFERENCES albums(id) ON DELETE CASCADE, photo_id INTEGER NOT NULL REFERENCES photos(id) ON DELETE CASCADE, added_at REAL NOT NULL, PRIMARY KEY(album_id, photo_id));
            PRAGMA user_version=4;
            COMMIT;
            """)
        }
    }

    // MARK: albume (colecții virtuale)
    public struct AlbumInfo: Equatable, Identifiable, Sendable { public var id: Int64; public var name: String; public var count: Int }
    public func albums() throws -> [AlbumInfo] {
        try rows("SELECT a.id, a.name, (SELECT COUNT(*) FROM album_photos p WHERE p.album_id=a.id) FROM albums a ORDER BY a.name COLLATE NOCASE", []).compactMap { r in if case .int(let i) = r[0], case .text(let n) = r[1], case .int(let c) = r[2] { return AlbumInfo(id: i, name: n, count: Int(c)) }; return nil }
    }
    @discardableResult public func createAlbum(_ name: String) throws -> Int64 {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !n.isEmpty else { throw CatalogError.invalid("nume de album gol") }
        try run("INSERT INTO albums(name, created_at) VALUES(?,?)", [.text(n), .real(Date().timeIntervalSince1970)]); return try scalar("SELECT last_insert_rowid()") ?? 0
    }
    public func renameAlbum(_ id: Int64, to name: String) throws { let n = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !n.isEmpty else { throw CatalogError.invalid("nume de album gol") }; try run("UPDATE albums SET name=? WHERE id=?", [.text(n), .int(id)]) }
    /// Șterge DOAR albumul și apartenențele (fotografiile, editările, deciziile și fișierele rămân).
    public func deleteAlbum(_ id: Int64) throws { try run("DELETE FROM album_photos WHERE album_id=?", [.int(id)]); try run("DELETE FROM albums WHERE id=?", [.int(id)]) }
    public func addToAlbum(_ id: Int64, photoIds: [Int64]) throws { for p in photoIds { try run("INSERT OR IGNORE INTO album_photos(album_id, photo_id, added_at) VALUES(?,?,?)", [.int(id), .int(p), .real(Date().timeIntervalSince1970)]) } }
    public func removeFromAlbum(_ id: Int64, photoIds: [Int64]) throws { for p in photoIds { try run("DELETE FROM album_photos WHERE album_id=? AND photo_id=?", [.int(id), .int(p)]) } }
    public func albumPhotoIds(_ id: Int64) throws -> Set<Int64> { Set(try rows("SELECT photo_id FROM album_photos WHERE album_id=?", [.int(id)]).compactMap { if case .int(let v) = $0[0] { return v }; return nil }) }
    public func albumIds(of photoId: Int64) throws -> [Int64] { try rows("SELECT album_id FROM album_photos WHERE photo_id=?", [.int(photoId)]).compactMap { if case .int(let v) = $0[0] { return v }; return nil } }

    // MARK: organizarea bibliotecii (scoaterea din catalog NU atinge fișierele originale)
    public struct RemovalImpact: Equatable, Sendable { public var photos = 0, withEdits = 0, inAlbums = 0, exported = 0, decided = 0
        public init(photos: Int = 0, withEdits: Int = 0, inAlbums: Int = 0, exported: Int = 0, decided: Int = 0) { self.photos = photos; self.withEdits = withEdits; self.inAlbums = inAlbums; self.exported = exported; self.decided = decided } }
    public struct SourceFolder: Equatable, Identifiable, Sendable { public var path: String; public var count: Int; public var id: String { path } }
    /// Ce se pierde din catalog dacă fotografiile sunt scoase: reglaje salvate, apartenențe la albume, istoric de export, decizii keep/reject. Fișierele de pe disc rămân neatinse.
    public func removalImpact(photoIds: [Int64]) throws -> RemovalImpact {
        var r = RemovalImpact(); r.photos = photoIds.count
        for id in photoIds {
            if try scalar("SELECT COUNT(*) FROM edits WHERE photo_id=\(id)") ?? 0 > 0 { r.withEdits += 1 }
            if try scalar("SELECT COUNT(*) FROM album_photos WHERE photo_id=\(id)") ?? 0 > 0 { r.inAlbums += 1 }
            if try scalar("SELECT COUNT(*) FROM export_log WHERE photo_id=\(id)") ?? 0 > 0 { r.exported += 1 }
            if try scalar("SELECT COUNT(*) FROM photos WHERE id=\(id) AND decision<>'check'") ?? 0 > 0 { r.decided += 1 }
        }
        return r
    }
    /// Scoate fotografiile din catalog (cascadă: decizii, reglaje, albume, previzualizări înregistrate, semnale). NU șterge niciun fișier original sau exportat.
    @discardableResult public func removeFromCatalog(photoIds: [Int64]) throws -> Int {
        guard !photoIds.isEmpty else { return 0 }
        try exec("BEGIN")
        do { for id in photoIds { try run("DELETE FROM photos WHERE id=?", [.int(id)]) }; try exec("COMMIT") } catch { try? exec("ROLLBACK"); throw error }
        return photoIds.count
    }
    /// Folderele sursă (după calea de pe disc) cu numărul de fotografii din catalog.
    public func sourceFolders() throws -> [SourceFolder] {
        var counts: [String: Int] = [:]
        for p in try photos() { counts[(p.path as NSString).deletingLastPathComponent, default: 0] += 1 }
        return counts.map { SourceFolder(path: $0.key, count: $0.value) }.sorted { $0.path < $1.path }
    }

    // MARK: inventar incremental
    public struct ImportResult: Equatable { public var added = 0, updated = 0, unchanged = 0, missing = 0; public var orphanedCacheFiles: [String] = [] }

    /// Înregistrează fișierele găsite (hash NU se calculează aici: identitatea = cale + mărime + mtime; hash-ul se adaugă la nevoie). Fișierele neschimbate nu se reprocesează;
    /// cele modificate își păstrează decizia/ratingul dar se marchează pentru reanaliză (preview_source = NULL). Fișierele dispărute rămân în catalog (numărate în `missing`).
    @discardableResult
    public func importFiles(_ files: [(path: String, size: Int64, mtimeNs: Int64, camera: String?, capturedAt: Date?)]) throws -> ImportResult {
        var r = ImportResult()
        try exec("BEGIN")
        do {
            for f in files {
                let row = try rows("SELECT size, mtime_ns FROM photos WHERE path=?", [.text(f.path)]).first
                if let row = row {
                    if row[0] == .int(f.size) && row[1] == .int(f.mtimeNs) { r.unchanged += 1; continue }
                    // Fișier schimbat: se invalidează previzualizările și semnalele lui (decizia/ratingul rămân); fișierele de cache orfane se întorc apelantului.
                    if case .int(let pid) = try rows("SELECT id FROM photos WHERE path=?", [.text(f.path)])[0][0] {
                        for pr in try rows("SELECT file FROM previews WHERE photo_id=?", [.int(pid)]) { if case .text(let fl) = pr[0] { r.orphanedCacheFiles.append(fl) } }
                        try run("DELETE FROM previews WHERE photo_id=?", [.int(pid)]); try run("DELETE FROM signals WHERE photo_id=?", [.int(pid)])
                    }
                    try run("UPDATE photos SET size=?, mtime_ns=?, preview_source=NULL, group_id=NULL WHERE path=?", [.int(f.size), .int(f.mtimeNs), .text(f.path)]); r.updated += 1
                } else {
                    try run("INSERT INTO photos(path,size,mtime_ns,camera,captured_at) VALUES(?,?,?,?,?)",
                            [.text(f.path), .int(f.size), .int(f.mtimeNs), f.camera.map { .text($0) } ?? .null, f.capturedAt.map { .real($0.timeIntervalSince1970) } ?? .null]); r.added += 1
                }
            }
            let known = Set(files.map { $0.path })
            for row in try rows("SELECT path FROM photos", []) { if case .text(let p) = row[0], !known.contains(p) { r.missing += 1 } }
            try exec("COMMIT")
        } catch { try? exec("ROLLBACK"); throw error }
        return r
    }

    // MARK: stări
    public func setDecision(_ d: Decision, photoId: Int64) throws { try setDecision(d, photoIds: [photoId]) }
    /// Selecție multiplă: tranzacție unică; jurnalul păstrează starea anterioară ⇒ `undoLastDecisionBatch` e posibil.
    public func setDecision(_ d: Decision, photoIds: [Int64]) throws {
        try exec("BEGIN")
        do {
            let last = try rows("SELECT MAX(at) FROM decision_log", []).first.flatMap { r -> Double? in if case .real(let v) = r[0] { return v }; return nil } ?? 0
            let now = max(Date().timeIntervalSince1970, last + 0.000_001)   // marcă de lot strict crescătoare (anulare per lot)
            for id in photoIds {
                guard let cur = try rows("SELECT decision FROM photos WHERE id=?", [.int(id)]).first, case .text(let from) = cur[0] else { throw CatalogError.invalid("fotografie necunoscută \(id)") }
                if from == d.rawValue { continue }
                try run("UPDATE photos SET decision=? WHERE id=?", [.text(d.rawValue), .int(id)])
                try run("INSERT INTO decision_log(photo_id,at,from_state,to_state) VALUES(?,?,?,?)", [.int(id), .real(now), .text(from), .text(d.rawValue)])
            }
            try exec("COMMIT")
        } catch { try? exec("ROLLBACK"); throw error }
    }
    public func setRating(_ n: Int, photoId: Int64) throws {
        guard (0...5).contains(n) else { throw CatalogError.invalid("rating în afara 0…5") }
        try run("UPDATE photos SET rating=? WHERE id=?", [.int(Int64(n)), .int(photoId)])
    }
    public func setFavorite(_ f: Bool, photoId: Int64) throws { try run("UPDATE photos SET favorite=? WHERE id=?", [.int(f ? 1 : 0), .int(photoId)]) }

    /// Anulează ULTIMA schimbare (un lot = aceeași marcă de timp): restaurează starea anterioară a tuturor fotografiilor din lot.
    @discardableResult
    public func undoLastDecisionBatch() throws -> Int {
        guard let t = try rows("SELECT MAX(at) FROM decision_log", []).first, case .real(let at) = t[0] else { return 0 }
        let batch = try rows("SELECT id, photo_id, from_state FROM decision_log WHERE at=?", [.real(at)])
        try exec("BEGIN")
        do {
            for b in batch { if case .int(let lid) = b[0], case .int(let pid) = b[1], case .text(let from) = b[2] {
                try run("UPDATE photos SET decision=? WHERE id=?", [.text(from), .int(pid)]); try run("DELETE FROM decision_log WHERE id=?", [.int(lid)]) } }
            try exec("COMMIT")
        } catch { try? exec("ROLLBACK"); throw error }
        return batch.count
    }

    // MARK: interogări
    public func photos(decision: Decision? = nil, favoritesOnly: Bool = false) throws -> [PhotoRecord] {
        var sql = "SELECT id,path,size,mtime_ns,decision,rating,favorite,group_id,camera,captured_at,preview_source FROM photos WHERE 1=1"
        var args: [Value] = []
        if let d = decision { sql += " AND decision=?"; args.append(.text(d.rawValue)) }
        if favoritesOnly { sql += " AND favorite=1" }
        sql += " ORDER BY COALESCE(captured_at,0), path"
        return try rows(sql, args).map { r in
            func i(_ k: Int) -> Int64 { if case .int(let v) = r[k] { return v }; return 0 }
            func t(_ k: Int) -> String? { if case .text(let v) = r[k] { return v }; return nil }
            func d(_ k: Int) -> Date? { if case .real(let v) = r[k] { return Date(timeIntervalSince1970: v) }; return nil }
            return PhotoRecord(id: i(0), path: t(1) ?? "", size: i(2), mtimeNs: i(3), decision: Decision(rawValue: t(4) ?? "check") ?? .check, rating: Int(i(5)), favorite: i(6) == 1,
                               groupId: { if case .int(let v) = r[7] { return v }; return nil }(), camera: t(8), capturedAt: d(9), previewSource: t(10))
        }
    }
    public func counts() throws -> (total: Int, keep: Int, reject: Int, check: Int) {
        var c = (total: 0, keep: 0, reject: 0, check: 0)
        for r in try rows("SELECT decision, COUNT(*) FROM photos GROUP BY decision", []) { if case .text(let d) = r[0], case .int(let n) = r[1] { c.total += Int(n); switch d { case "keep": c.keep = Int(n); case "reject": c.reject = Int(n); default: c.check = Int(n) } } }
        return c
    }
    /// Ce trece la editare: doar „păstrate” (implicit) sau TOATE (selecția a fost sărită).
    public func forEditing(allPhotos: Bool) throws -> [PhotoRecord] { allPhotos ? try photos() : try photos(decision: .keep) }

    // MARK: cache de previzualizări (metadate; fișierele le gestionează PreviewCache)
    public struct CachedPreview: Equatable { public var file: String, w: Int, h: Int, source: String, forSize: Int64, forMtimeNs: Int64 }
    public func cachedPreview(photoId: Int64, kind: String) throws -> CachedPreview? {
        guard let r = try rows("SELECT file,w,h,source,for_size,for_mtime_ns FROM previews WHERE photo_id=? AND kind=?", [.int(photoId), .text(kind)]).first else { return nil }
        guard case .text(let f) = r[0], case .int(let w) = r[1], case .int(let h) = r[2], case .text(let s) = r[3], case .int(let fs) = r[4], case .int(let fm) = r[5] else { return nil }
        return CachedPreview(file: f, w: Int(w), h: Int(h), source: s, forSize: fs, forMtimeNs: fm)
    }
    public func storePreview(photoId: Int64, kind: String, _ c: CachedPreview) throws {
        try run("INSERT OR REPLACE INTO previews(photo_id,kind,file,w,h,source,for_size,for_mtime_ns) VALUES(?,?,?,?,?,?,?,?)",
                [.int(photoId), .text(kind), .text(c.file), .int(Int64(c.w)), .int(Int64(c.h)), .text(c.source), .int(c.forSize), .int(c.forMtimeNs)])
        try run("UPDATE photos SET preview_source=? WHERE id=?", [.text(c.source), .int(photoId)])
    }
    public func photo(id: Int64) throws -> PhotoRecord? { try photos().first { $0.id == id } }

    // MARK: semnale și grupuri (sugestii)
    public func storeSignals(photoId: Int64, _ s: Signals) throws {
        try run("INSERT OR REPLACE INTO signals(photo_id,version,sharp,clip_hi,clip_lo,median,dhash,hist,analyzed_at) VALUES(?,?,?,?,?,?,?,?,?)",
                [.int(photoId), .int(Int64(Signals.version)), .real(s.sharpness), .real(s.clipHighPct), .real(s.clipLowPct), .real(s.medianLuma), .int(Int64(bitPattern: s.dhash)),
                 .blob(s.histogram.withUnsafeBufferPointer { Data(buffer: $0) }), .real(Date().timeIntervalSince1970)])
    }
    public func signals(photoId: Int64) throws -> Signals? {
        guard let r = try rows("SELECT version,sharp,clip_hi,clip_lo,median,dhash,hist FROM signals WHERE photo_id=?", [.int(photoId)]).first,
              case .int(let v) = r[0], Int(v) == Signals.version, case .real(let sh) = r[1], case .real(let ch) = r[2], case .real(let cl) = r[3], case .real(let md) = r[4], case .int(let dh) = r[5], case .blob(let hb) = r[6] else { return nil }
        let hist = hb.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return Signals(sharpness: sh, clipHighPct: ch, clipLowPct: cl, medianLuma: md, dhash: UInt64(bitPattern: dh), histogram: hist)
    }
    /// Înlocuiește sugestiile de grupare (nu sunt decizii): grupurile vechi dispar, deciziile fotografului rămân neatinse.
    public func storeGroups(_ groups: [SuggestedGroup]) throws {
        try exec("BEGIN")
        do {
            try run("UPDATE photos SET group_id=NULL", []); try run("DELETE FROM group_info", [])
            for (i, g) in groups.enumerated() {
                let gid = Int64(i + 1)
                try run("INSERT INTO group_info(group_id,kind,confidence,reason) VALUES(?,?,?,?)", [.int(gid), .text(g.kind.rawValue), .text(g.confidence.rawValue), .text(g.reason)])
                for id in g.memberIds { try run("UPDATE photos SET group_id=? WHERE id=?", [.int(gid), .int(id)]) }
            }
            try exec("COMMIT")
        } catch { try? exec("ROLLBACK"); throw error }
    }
    public func groups() throws -> [SuggestedGroup] {
        try rows("SELECT group_id,kind,confidence,reason FROM group_info ORDER BY group_id", []).compactMap { r in
            guard case .int(let gid) = r[0], case .text(let k) = r[1], case .text(let c) = r[2], case .text(let why) = r[3], let kind = SuggestedGroup.Kind(rawValue: k), let conf = SuggestedGroup.Confidence(rawValue: c) else { return nil }
            let members = (try? rows("SELECT id FROM photos WHERE group_id=? ORDER BY COALESCE(captured_at,0), path", [.int(gid)]).compactMap { r2 -> Int64? in if case .int(let i) = r2[0] { return i }; return nil }) ?? []
            return SuggestedGroup(kind: kind, confidence: conf, reason: why, memberIds: members)
        }
    }

    // MARK: reglaje, sesiune, jurnal de export (v3). Reglajele sunt JSON opac pentru catalog (modelul îl deține stratul de procesare); NU se scrie nimic lângă originale.
    public func setEdits(photoId: Int64, json: String) throws {
        try run("INSERT OR REPLACE INTO edits(photo_id,json,updated_at) VALUES(?,?,?)", [.int(photoId), .text(json), .real(Date().timeIntervalSince1970)])
    }
    public func edits(photoId: Int64) throws -> String? {
        if let r = try rows("SELECT json FROM edits WHERE photo_id=?", [.int(photoId)]).first, case .text(let j) = r[0] { return j }; return nil
    }
    public func clearEdits(photoId: Int64) throws { try run("DELETE FROM edits WHERE photo_id=?", [.int(photoId)]) }
    public func editedPhotoIds() throws -> [Int64] { try rows("SELECT photo_id FROM edits ORDER BY photo_id", []).compactMap { if case .int(let i) = $0[0] { return i }; return nil } }
    /// Copie consistentă a catalogului deschis (inclusiv WAL) în `url`; destinația nu trebuie să existe. Folosită la migrarea locației de lucru.
    public func snapshot(to url: URL) throws { try exec("VACUUM INTO '\(url.path.replacingOccurrences(of: "'", with: "''"))'") }
    /// Amprenta TUTUROR datelor din catalog (fotografii cu calea originalului, decizii, rating, reglaje/măști, profiluri, albume, cache de analiză, jurnal de export): independentă de ordinea rândurilor. Folosită la verificarea migrării.
    public func contentDigest() throws -> String {
        var h = SHA256()
        let tables = try rows("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name", []).compactMap { r -> String? in if case .text(let t) = r[0] { return t }; return nil }
        for t in tables {
            let lines = try rows("SELECT * FROM \"\(t)\"", []).map { r in r.map { v -> String in switch v { case .int(let i): return "i\(i)"; case .real(let d): return "r\(d)"; case .text(let x): return "t\(x)"; case .blob(let b): return "b\(SHA256.hash(data: b).map { String(format: "%02x", $0) }.joined())"; case .null: return "n" } }.joined(separator: "\u{1f}") }.sorted()
            h.update(data: Data("#\(t):\(lines.count)\n".utf8)); for l in lines { h.update(data: Data((l + "\n").utf8)) }
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
    /// Rezultatele de analiză (regenerabile) sunt chei `session_kv` cu un prefix; numărul și mărimea lor pentru raportul de spațiu.
    public func sessionStats(prefix: String) throws -> (count: Int, bytes: Int64) {
        let r = try rows("SELECT COUNT(*), COALESCE(SUM(LENGTH(value)),0) FROM session_kv WHERE key LIKE ? ESCAPE '\\'", [.text(prefix.replacingOccurrences(of: "%", with: "\\%") + "%")])
        guard let a = r.first, case .int(let n) = a[0], case .int(let b) = a[1] else { return (0, 0) }; return (Int(n), b)
    }
    public func removeSession(prefix: String) throws { try run("DELETE FROM session_kv WHERE key LIKE ? ESCAPE '\\'", [.text(prefix.replacingOccurrences(of: "%", with: "\\%") + "%")]) }
    public func setSession(_ key: String, _ value: String) throws { try run("INSERT OR REPLACE INTO session_kv(key,value) VALUES(?,?)", [.text(key), .text(value)]) }
    public func session(_ key: String) throws -> String? { if let r = try rows("SELECT value FROM session_kv WHERE key=?", [.text(key)]).first, case .text(let v) = r[0] { return v }; return nil }
    public func logExport(photoId: Int64, path: String, format: String) throws {
        try run("INSERT INTO export_log(photo_id,path,format,at) VALUES(?,?,?,?)", [.int(photoId), .text(path), .text(format), .real(Date().timeIntervalSince1970)])
    }
    public func exports(photoId: Int64) throws -> [(path: String, format: String, at: Date)] {
        try rows("SELECT path,format,at FROM export_log WHERE photo_id=? ORDER BY id", [.int(photoId)]).compactMap { r in
            guard case .text(let p) = r[0], case .text(let f) = r[1], case .real(let a) = r[2] else { return nil }; return (p, f, Date(timeIntervalSince1970: a)) }
    }

    // MARK: SQLite minimal
    enum Value: Equatable { case int(Int64), real(Double), text(String), blob(Data), null }
    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK { let m = err.map { String(cString: $0) } ?? "?"; sqlite3_free(err); throw CatalogError.sql(m) }
    }
    private func scalar(_ sql: String) throws -> Int64? { if let r = try rows(sql, []).first, case .int(let v) = r[0] { return v }; return nil }
    private func run(_ sql: String, _ args: [Value]) throws { _ = try rows(sql, args) }
    private func rows(_ sql: String, _ args: [Value]) throws -> [[Value]] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { throw CatalogError.sql(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(st) }
        for (i, a) in args.enumerated() {
            let k = Int32(i + 1)
            switch a {
            case .int(let v): sqlite3_bind_int64(st, k, v)
            case .real(let v): sqlite3_bind_double(st, k, v)
            case .text(let v): sqlite3_bind_text(st, k, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .blob(let d): _ = d.withUnsafeBytes { sqlite3_bind_blob(st, k, $0.baseAddress, Int32(d.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            case .null: sqlite3_bind_null(st, k)
            }
        }
        var out: [[Value]] = []
        while true {
            let rc = sqlite3_step(st)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw CatalogError.sql(String(cString: sqlite3_errmsg(db))) }
            out.append((0..<sqlite3_column_count(st)).map { c in
                switch sqlite3_column_type(st, c) {
                case SQLITE_INTEGER: return .int(sqlite3_column_int64(st, c))
                case SQLITE_FLOAT: return .real(sqlite3_column_double(st, c))
                case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(st, c)))
                case SQLITE_BLOB: let n = Int(sqlite3_column_bytes(st, c)); return .blob(n > 0 ? Data(bytes: sqlite3_column_blob(st, c), count: n) : Data())
                default: return .null
                }
            })
        }
        return out
    }
}
