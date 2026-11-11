import Foundation

/// Import incremental complet (fără UI): inventar read-only → catalog → previzualizări (view/grid/filmstrip) → semnale → grupuri sugerate.
/// Reutilizează tot ce e valid: fișierele neschimbate nu se reprocesează (nici previzualizări, nici semnale); cele schimbate se invalidează și se regenerează.
public enum LibraryImporter {
    public struct Skipped: Equatable { public var path: String; public var reason: String }
    public struct Summary: Equatable { public var added = 0, updated = 0, unchanged = 0, withPreview = 0, withoutPreview = 0, analyzed = 0, groups = 0
        /// Fișiere omise CONTROLAT (ilizibile/invalide): raportate cu motiv; originalul nu se modifică, iar importul continuă cu restul.
        public var skipped: [Skipped] = [] }
    public enum Phase: Equatable { case scanning, previews(done: Int, total: Int), analyzing(done: Int, total: Int) }

    /// Sincron (apelantul îl rulează pe un fir de fundal). `cache` trebuie accesat doar prin acest apel (nu e thread-safe pe contoare).
    public static func run(directory: URL, catalog: Catalog, cache: PreviewCache, recursive: Bool = false, rendered: Bool = false, progress: (Phase) -> Void = { _ in }) throws -> Summary {
        var sum = Summary(); progress(.scanning)
        let res = try catalog.importFiles(try Inventory.scan(directory: directory, recursive: recursive, rendered: rendered))
        sum.added = res.added; sum.updated = res.updated; sum.unchanged = res.unchanged; cache.purge(files: res.orphanedCacheFiles)
        let photos = try catalog.photos(); var noPreview = Set<Int64>()
        for (i, p) in photos.enumerated() {
            progress(.previews(done: i, total: photos.count))
            do {
                guard try cache.url(for: p, kind: .view) != nil else { sum.withoutPreview += 1; noPreview.insert(p.id); sum.skipped.append(.init(path: p.path, reason: L("fără previzualizare încorporată sau fișier ilizibil/invalid"))); continue }
                _ = try cache.url(for: p, kind: .grid); _ = try cache.url(for: p, kind: .filmstrip); sum.withPreview += 1
            } catch { sum.withoutPreview += 1; noPreview.insert(p.id); sum.skipped.append(.init(path: p.path, reason: LF("previzualizare eșuată: %@", error))) }
        }
        var signals: [Int64: Signals] = [:]
        for (i, p) in photos.enumerated() {
            if noPreview.contains(p.id) { progress(.analyzing(done: i + 1, total: photos.count)); continue }   // fără previzualizare nu există ce analiza (și nu se mai reîncearcă degeaba)
            do {
                if let s = try catalog.signals(photoId: p.id) { signals[p.id] = s }
                else if let u = try cache.url(for: p, kind: .grid), let img = PreviewCache.load(u) { let s = SignalAnalyzer.analyze(img); try catalog.storeSignals(photoId: p.id, s); signals[p.id] = s; sum.analyzed += 1 }
            } catch { sum.skipped.append(.init(path: p.path, reason: LF("analiză eșuată: %@", error))) }
            progress(.analyzing(done: i + 1, total: photos.count))
        }
        let groups = Grouping.suggest(photos: photos, signals: signals); try catalog.storeGroups(groups); sum.groups = groups.count
        return sum
    }
}
