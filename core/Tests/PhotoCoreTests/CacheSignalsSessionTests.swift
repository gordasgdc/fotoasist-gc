import XCTest
import CoreGraphics
@testable import PhotoCore

/// Furnizor sintetic: nu citește RAW; produce imagini deterministe și numără apelurile (verifică ce se regenerează).
final class StubProvider: PreviewProvider {
    var calls = 0; var size = 600; var seedFor: (URL) -> Int = { _ in 1 }
    func preview(for url: URL, maxPixel: Int) throws -> PreviewImage? {
        calls += 1; if url.lastPathComponent.hasPrefix("NOPREVIEW") { return nil }
        return PreviewImage(image: Synth.image(seed: seedFor(url), side: min(size, maxPixel)), source: "stub-embedded", seconds: 0)
    }
}
enum Synth {
    static func image(seed: Int, side: Int, blur: Int = 0, noise: Double = 0, gain: Double = 1, shiftPct: Double = 0) -> CGImage {
        var px = [UInt8](repeating: 0, count: side * side * 4); var rng = SystemRandomNumberGenerator(); _ = rng
        var s = UInt64(seed &* 2654435761 &+ 1)
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 33) / Double(1 << 31) }
        let rects = (0..<6).map { _ in (rnd(), rnd(), 0.1 + rnd() * 0.3, 0.1 + rnd() * 0.3, rnd()) }
        let off = Int(Double(side) * shiftPct)
        for y in 0..<side { for x in 0..<side {
            let xx = x - off, yy = y - off
            var v = 40.0 + 120.0 * Double(xx + yy) / Double(2 * side)
            for r in rects { let rx = Int(r.0 * Double(side)), ry = Int(r.1 * Double(side)), rw = Int(r.2 * Double(side)), rh = Int(r.3 * Double(side)); if xx >= rx && xx < rx + rw && yy >= ry && yy < ry + rh { v = 30 + r.4 * 200 } }
            px[(y * side + x) * 4] = UInt8(max(0, min(255, v * gain))); px[(y * side + x) * 4 + 1] = UInt8(max(0, min(255, v * gain * 0.95))); px[(y * side + x) * 4 + 2] = UInt8(max(0, min(255, v * gain * 0.9))); px[(y * side + x) * 4 + 3] = 255 } }
        for _ in 0..<blur { var o = px; for y in 1..<(side - 1) { for x in 1..<(side - 1) { for c in 0..<3 { var a = 0; for dy in -1...1 { for dx in -1...1 { a += Int(px[((y + dy) * side + x + dx) * 4 + c]) } }; o[(y * side + x) * 4 + c] = UInt8(a / 9) } } }; px = o }
        if noise > 0 { for i in 0..<(side * side) { let n = (rnd() - 0.5) * 2 * noise; for c in 0..<3 { px[i * 4 + c] = UInt8(max(0, min(255, Double(px[i * 4 + c]) + n))) } } }
        let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}

final class CacheSignalsSessionTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()).appendingPathComponent("photocore-t2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }
    func entries(_ n: Int, mtime: Int64 = 1, spacing: Double = 100) -> [Inventory.Entry] { (0..<n).map { ("/x/IMG_\($0).ARW", 100 + Int64($0), mtime, "Cam", Date(timeIntervalSince1970: 1_000 + Double($0) * spacing)) } }

    // ---------- cache ----------
    func testCacheGeneratesOnDemandThenHitsAndDerivesSmallFromView() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(2)); let ps = try c.photos()
        let prov = StubProvider(); let cache = try PreviewCache(catalog: c, directory: dir.appendingPathComponent("cache"), provider: prov)
        let u1 = try cache.url(for: ps[0], kind: .view); XCTAssertNotNil(u1); XCTAssertEqual(prov.calls, 1)
        _ = try cache.url(for: ps[0], kind: .view); XCTAssertEqual(cache.stats.hits, 1); XCTAssertEqual(prov.calls, 1, "al doilea acces = din cache")
        let g = try cache.url(for: ps[0], kind: .grid)!; XCTAssertEqual(prov.calls, 1, "grid derivă din view, fără a redeschide originalul"); XCTAssertEqual(cache.stats.derived, 1)
        let img = PreviewCache.load(g)!; XCTAssertLessThanOrEqual(max(img.width, img.height), 420)
        XCTAssertEqual(try c.cachedPreview(photoId: ps[0].id, kind: "grid")?.source, "stub-embedded")
        XCTAssertEqual(try c.photo(id: ps[0].id)?.previewSource, "stub-embedded")
    }
    func testDetailKindUsesDetailProviderAndIsNotDerivedFromView() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(1)); let p = try c.photos()[0]
        let base = StubProvider(), det = StubProvider(); det.size = 900
        let cache = try PreviewCache(catalog: c, directory: dir.appendingPathComponent("cache"), provider: base, detailProvider: det)
        _ = try cache.url(for: p, kind: .view); XCTAssertEqual(base.calls, 1)
        let u = try cache.url(for: p, kind: .detail)!; XCTAssertEqual(det.calls, 1); XCTAssertEqual(base.calls, 1, "„100%” nu derivă din view și folosește furnizorul dedicat")
        XCTAssertEqual(PreviewCache.load(u)!.width, 900); _ = try cache.url(for: p, kind: .detail); XCTAssertEqual(det.calls, 1, "al doilea acces = din cache")
    }
    func testCacheInvalidatesWhenOriginalChangesAndPurgesOrphans() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(1)); var p = try c.photos()[0]
        let prov = StubProvider(); let cache = try PreviewCache(catalog: c, directory: dir.appendingPathComponent("cache"), provider: prov)
        let u = try cache.url(for: p, kind: .view)!; XCTAssertTrue(FileManager.default.fileExists(atPath: u.path))
        let r = try c.importFiles(entries(1, mtime: 2)); XCTAssertEqual(r.updated, 1); XCTAssertEqual(r.orphanedCacheFiles.count, 1)
        cache.purge(files: r.orphanedCacheFiles); XCTAssertFalse(FileManager.default.fileExists(atPath: u.path))
        p = try c.photos()[0]; XCTAssertNil(try c.cachedPreview(photoId: p.id, kind: "view")); XCTAssertNil(try c.signals(photoId: p.id))
        _ = try cache.url(for: p, kind: .view); XCTAssertEqual(prov.calls, 2, "după schimbare se regenerează o singură dată")
    }
    func testCacheDetectsMissingFileAndNoPreview() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(1) + [("/x/NOPREVIEW_9.ARW", 5, 1, nil, nil)]); let ps = try c.photos()
        let prov = StubProvider(); let cache = try PreviewCache(catalog: c, directory: dir.appendingPathComponent("cache"), provider: prov)
        let u = try cache.url(for: ps.first { $0.path.contains("IMG_0") }!, kind: .grid)!; try FileManager.default.removeItem(at: u)
        XCTAssertNotNil(try cache.url(for: ps.first { $0.path.contains("IMG_0") }!, kind: .grid), "fișier de cache dispărut ⇒ regenerat")
        XCTAssertNil(try cache.url(for: ps.first { $0.path.contains("NOPREVIEW") }!, kind: .grid)); XCTAssertEqual(cache.stats.failed, 1)
    }
    func testCacheLivesOnlyInItsDirectory() throws {
        let orig = dir.appendingPathComponent("orig"); try FileManager.default.createDirectory(at: orig, withIntermediateDirectories: true)
        try Data(count: 10).write(to: orig.appendingPathComponent("A.ARW")); let before = try FileManager.default.contentsOfDirectory(atPath: orig.path)
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(try Inventory.scan(directory: orig, readMetadata: false))
        let cache = try PreviewCache(catalog: c, directory: dir.appendingPathComponent("cache"), provider: StubProvider()); _ = try cache.url(for: try c.photos()[0], kind: .view)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: orig.path), before, "nimic scris lângă original")
    }

    // ---------- semnale ----------
    func testSharpnessDropsWithBlurWithinSameContent() {
        let v = (0...3).map { SignalAnalyzer.analyze(Synth.image(seed: 7, side: 256, blur: $0)).sharpness }
        XCTAssertTrue(v[0] > v[1] && v[1] > v[2] && v[2] > v[3], "\(v)")
    }
    func testNoiseInflatesSharpnessDocumentedLimitation() {
        XCTAssertGreaterThan(SignalAnalyzer.analyze(Synth.image(seed: 7, side: 256, noise: 20)).sharpness, SignalAnalyzer.analyze(Synth.image(seed: 7, side: 256)).sharpness)
    }
    func testClippingAndMedianSignals() {
        let hi = SignalAnalyzer.analyze(Synth.image(seed: 3, side: 128, gain: 3)), lo = SignalAnalyzer.analyze(Synth.image(seed: 3, side: 128, gain: 0.02))
        XCTAssertGreaterThan(hi.clipHighPct, 20); XCTAssertGreaterThan(lo.clipLowPct, 90); XCTAssertLessThan(lo.medianLuma, 10)
    }
    func testDHashStableForNearDuplicateAndFarForDifferent() {
        let a = SignalAnalyzer.analyze(Synth.image(seed: 11, side: 256)), b = SignalAnalyzer.analyze(Synth.image(seed: 11, side: 256, gain: 1.1))
        let d = SignalAnalyzer.analyze(Synth.image(seed: 99, side: 256))
        XCTAssertLessThanOrEqual(Signals.hamming(a.dhash, b.dhash), 6); XCTAssertGreaterThan(Signals.hamming(a.dhash, d.dhash), 10)
        XCTAssertGreaterThan(Signals.histogramIntersection(a.histogram, b.histogram), 0.6)
    }
    func testSignalsRoundTripThroughCatalog() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(1)); let id = try c.photos()[0].id
        let s = SignalAnalyzer.analyze(Synth.image(seed: 5, side: 128)); try c.storeSignals(photoId: id, s)
        XCTAssertEqual(try c.signals(photoId: id), s)
    }

    // ---------- grupare ----------
    func testBurstGroupingByTimeAndSameCameraOnly() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite"))
        try c.importFiles([("/x/a.ARW", 1, 1, "A", Date(timeIntervalSince1970: 100)), ("/x/b.ARW", 1, 1, "A", Date(timeIntervalSince1970: 101.5)), ("/x/c.ARW", 1, 1, "B", Date(timeIntervalSince1970: 102)), ("/x/d.ARW", 1, 1, "A", Date(timeIntervalSince1970: 200))])
        let g = Grouping.suggest(photos: try c.photos(), signals: [:])
        XCTAssertEqual(g.count, 1); XCTAssertEqual(g[0].kind, .burst); XCTAssertEqual(g[0].memberIds.count, 2); XCTAssertEqual(g[0].confidence, .weak, "fără semnale vizuale, doar timp ⇒ slab")
    }
    func testSimilarGroupingNeedsBothHashAndHistogramAndIsWeak() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(3, spacing: 1000)); let ps = try c.photos()
        let a = SignalAnalyzer.analyze(Synth.image(seed: 11, side: 256)), b = SignalAnalyzer.analyze(Synth.image(seed: 11, side: 256, gain: 1.1)), d = SignalAnalyzer.analyze(Synth.image(seed: 99, side: 256))
        let g = Grouping.suggest(photos: ps, signals: [ps[0].id: a, ps[1].id: b, ps[2].id: d])
        XCTAssertEqual(g.count, 1); XCTAssertEqual(g[0].kind, .similar); XCTAssertEqual(g[0].confidence, .weak); XCTAssertEqual(Set(g[0].memberIds), [ps[0].id, ps[1].id])
        try c.storeGroups(g); XCTAssertEqual(try c.groups(), g); XCTAssertEqual(try c.photos().filter { $0.groupId != nil }.count, 2)
    }
    func testGroupsDoNotChangeDecisions() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(2, spacing: 1)); let ps = try c.photos(); try c.setDecision(.keep, photoId: ps[0].id)
        try c.storeGroups(Grouping.suggest(photos: ps, signals: [:])); XCTAssertEqual(try c.photos()[0].decision, .keep); XCTAssertEqual(try c.photos()[1].decision, .check)
    }

    // ---------- sesiune ----------
    func testSessionFiltersNavigationBatchActionsUndoAndEditQueue() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(5)); let s = try SelectionSession(catalog: c)
        XCTAssertEqual(s.counts.total, 5); XCTAssertEqual(s.currentId, s.visible[0].id)
        try s.apply(.keep); XCTAssertEqual(s.counts.keep, 1); XCTAssertEqual(s.currentId, s.visible[1].id, "avansează după decizie")
        s.toggleSelected(s.visible[2].id); s.toggleSelected(s.visible[3].id); try s.apply(.reject); XCTAssertEqual(s.counts.reject, 2); XCTAssertTrue(s.selectedIds.isEmpty)
        s.filter = .reject; XCTAssertEqual(s.visible.count, 2); s.filter = .all
        XCTAssertEqual(s.editQueue(allPhotos: false).count, 1); XCTAssertEqual(s.editQueue(allPhotos: true).count, 5, "selecția poate fi sărită")
        XCTAssertEqual(try s.undo(), 2); XCTAssertEqual(s.counts.reject, 0); XCTAssertEqual(s.counts.keep, 1)
    }
    func testSessionFilterKeepsCurrentValidAndPinForCompare() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(3)); let s = try SelectionSession(catalog: c)
        s.autoAdvance = false; try s.apply(.keep); s.filter = .keep; XCTAssertEqual(s.visible.count, 1); XCTAssertEqual(s.currentId, s.visible[0].id)
        s.filter = .all; s.pinCurrent(); s.move(2); XCTAssertNotEqual(s.pinnedId, s.currentId); XCTAssertNotNil(s.pinned)
        s.move(-100); XCTAssertEqual(s.currentId, s.visible[0].id); s.move(100); XCTAssertEqual(s.currentId, s.visible.last!.id)
    }
    func testPinCanBeReplacedAndCleared() throws {
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); try c.importFiles(entries(3)); let s = try SelectionSession(catalog: c)
        s.pinCurrent(); let first = s.pinnedId; s.move(1); s.pinCurrent(); XCTAssertNotEqual(s.pinnedId, first, "referința se poate schimba")
        s.clearPin(); XCTAssertNil(s.pinned, "referința se poate elimina"); XCTAssertNotNil(s.current)
    }
    func testSessionFavoriteRatingAndPersistence() throws {
        let u = dir.appendingPathComponent("c.sqlite"); var c: Catalog? = try Catalog(url: u); try c!.importFiles(entries(2)); var s: SelectionSession? = try SelectionSession(catalog: c!)
        try s!.toggleFavorite(); try s!.setRating(4); try s!.setRating(4); try s!.apply(.keep); s = nil; c = nil
        let s2 = try SelectionSession(catalog: try Catalog(url: u)); let first = s2.photos[0]
        XCTAssertTrue(first.favorite); XCTAssertEqual(first.rating, 0, "al doilea apel cu același rating îl resetează"); XCTAssertEqual(first.decision, .keep)
    }

    // ---------- import complet ----------
    func testImporterIsIncrementalAndInvalidatesOnlyChangedFile() throws {
        let src = dir.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        for n in ["A.ARW", "B.ARW", "NOPREVIEW_C.ARW"] { try Data(repeating: 1, count: 64).write(to: src.appendingPathComponent(n)) }
        let c = try Catalog(url: dir.appendingPathComponent("c.sqlite")); let prov = StubProvider(); let cache = try PreviewCache(catalog: c, directory: dir.appendingPathComponent("cache"), provider: prov)
        let s1 = try LibraryImporter.run(directory: src, catalog: c, cache: cache)
        XCTAssertEqual(s1.added, 3); XCTAssertEqual(s1.withPreview, 2); XCTAssertEqual(s1.withoutPreview, 1); XCTAssertEqual(s1.analyzed, 2)
        let callsAfterFirst = prov.calls
        let s2 = try LibraryImporter.run(directory: src, catalog: c, cache: cache)
        XCTAssertEqual(s2.unchanged, 3); XCTAssertEqual(s2.analyzed, 0, "semnalele valide se reutilizează"); XCTAssertEqual(prov.calls, callsAfterFirst + 1, "doar fișierul fără previzualizare se reîncearcă; ceilalți vin din cache")
        // modificăm B: doar B se reprocesează
        try Data(repeating: 2, count: 80).write(to: src.appendingPathComponent("B.ARW"))
        let before = prov.calls; let s3 = try LibraryImporter.run(directory: src, catalog: c, cache: cache)
        XCTAssertEqual(s3.updated, 1); XCTAssertEqual(s3.unchanged, 2); XCTAssertEqual(s3.analyzed, 1)
        XCTAssertEqual(prov.calls - before, 2, "B regenerat o dată (view) + reîncercarea fișierului fără previzualizare")
        XCTAssertEqual(try c.counts().total, 3)
    }
    func testImporterNeverWritesBesideOriginals() throws {
        let src = dir.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: src.appendingPathComponent("A.ARW")); let before = try FileManager.default.contentsOfDirectory(atPath: src.path)
        let c = try Catalog(url: dir.appendingPathComponent("lib/c.sqlite".replacingOccurrences(of: "lib/", with: ""))); let cache = try PreviewCache(catalog: c, directory: dir.appendingPathComponent("cache"), provider: StubProvider())
        _ = try LibraryImporter.run(directory: src, catalog: c, cache: cache); try c.setDecision(.reject, photoId: try c.photos()[0].id)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: src.path), before)
    }
}
