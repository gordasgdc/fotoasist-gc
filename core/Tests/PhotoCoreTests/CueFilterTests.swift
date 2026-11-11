import XCTest
@testable import PhotoCore

final class CueFilterTests: XCTestCase {
    func testCueFilterNarrowsVisibleListAndNeverHidesActionsOnHiddenPhotos() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cue-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let cat = try Catalog(url: dir.appendingPathComponent("c.sqlite")); _ = try cat.importFiles((0..<4).map { ("/x/IMG_\($0).ARW", Int64(100 + $0), Int64(1), "Cam", Date(timeIntervalSince1970: Double(1_000 + $0))) })
        let ps = try cat.photos()
        try cat.storeSignals(photoId: ps[0].id, Signals(sharpness: 100, clipHighPct: 6, clipLowPct: 0, medianLuma: 120, dhash: 0, histogram: [Float](repeating: 0, count: 512)))   // lumini tăiate
        try cat.storeSignals(photoId: ps[1].id, Signals(sharpness: 100, clipHighPct: 0, clipLowPct: 0, medianLuma: 120, dhash: 1, histogram: [Float](repeating: 0, count: 512)))   // normal
        // ps[2], ps[3]: fără semnale ⇒ «analiză neefectuată»
        let s = try SelectionSession(catalog: cat)
        XCTAssertEqual(s.cueCount(.clipping), 1); XCTAssertEqual(s.cueCount(.analysisMissing), 2)
        s.cueFilter = .clipping; XCTAssertEqual(s.visible.map { $0.id }, [ps[0].id])
        s.selectAllVisible(); try s.apply(.reject); try s.reload()
        XCTAssertEqual(try cat.photos().filter { $0.decision == .reject }.map { $0.id }, [ps[0].id], "acțiunea de lot a atins doar fotografia vizibilă prin filtru")
        s.cueFilter = .none; s.filter = .all; XCTAssertEqual(s.visible.count, 4)
        s.cueFilter = .analysisMissing; s.filter = .reject; XCTAssertTrue(s.visible.isEmpty, "indiciile se combină cu filtrul de decizii")
    }
}
