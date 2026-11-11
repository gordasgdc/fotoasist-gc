import XCTest
@testable import PhotoAssistUI
import PhotoCore

@MainActor
final class FaceCenterTests: XCTestCase {
    private var savedLanguage: AppLanguage = .system
    override func setUp() { savedLanguage = Localizer.shared.choice; Localizer.shared.choice = .ro }
    override func tearDown() { Localizer.shared.choice = savedLanguage }
    var dir: URL!; var catalog: Catalog!; var photos: [PhotoRecord] = []; var fc: FaceCenter!
    override func setUp() async throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("face-tests-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        catalog = try Catalog(url: dir.appendingPathComponent("c.sqlite")); var e: [Inventory.Entry] = []; for i in 0..<3 { e.append(("/x/IMG_\(i).ARW", Int64(100 + i), Int64(1), "Cam", Date(timeIntervalSince1970: Double(1_000 + i)))) }
        _ = try catalog.importFiles(e); photos = try catalog.photos()
        fc = FaceCenter(catalog: catalog, store: ImageStore(cache: try PreviewCache(catalog: catalog, directory: dir.appendingPathComponent("cache"))))
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }
    func eye(_ o: Double) -> StoredEye { StoredEye(box: [0, 0, 0.1, 0.05], openness: o) }
    func face(_ l: Double?, _ r: Double?) -> StoredFace { StoredFace(box: [0.4, 0.3, 0.2, 0.25], confidence: 1, roll: nil, yaw: nil, left: l.map(eye), right: r.map(eye)) }
    func result(_ p: PhotoRecord, faces: [StoredFace], version: Int = FaceAnalyzer.version) -> FaceResult { FaceResult(version: version, size: p.size, mtimeNs: p.mtimeNs, previewW: 1400, previewH: 933, faces: faces, seconds: 0.02, config: FaceAnalyzer.configLabel) }

    func testCacheIsVersionedAndInvalidatedByFileChange() throws {
        let p = photos[0]; XCTAssertEqual(fc.pending(photos).count, 3); try catalog.setFaceResult(result(p, faces: []), photoId: p.id); XCTAssertEqual(fc.pending(photos).count, 2, "rezultatul valid (chiar fără fețe) nu se reface")
        try catalog.setFaceResult(result(p, faces: [], version: FaceAnalyzer.version + 1), photoId: p.id); XCTAssertEqual(fc.pending(photos).count, 3, "altă versiune a analizei ⇒ de refăcut")
        try catalog.setFaceResult(result(p, faces: []), photoId: p.id); var changed = p; changed.mtimeNs += 1; XCTAssertNil(catalog.faceResult(for: changed), "fișier schimbat ⇒ rezultat invalid")
    }
    func testNoFaceIsNotAScoreNorAnAbsenceOfPeople() throws {
        let p = photos[0]; try catalog.setFaceResult(result(p, faces: []), photoId: p.id); fc.setSubject(SubjectState(), p)
        let h = fc.hints(p); XCTAssertEqual(h.count, 1); XCTAssertEqual(h[0].title, "Nicio față detectată"); XCTAssertTrue(h[0].why.contains("Nu înseamnă fotografie fără persoane")); XCTAssertTrue(h[0].why.contains("nu e un scor"))
        XCTAssertEqual(fc.hints(photos[1]).first?.title, "Analiză neefectuată", "neanalizat ≠ fără fețe")
    }
    func testBlinkSuggestionIsExperimentalExplainedAndNeverASingleEyeVerdict() throws {
        let p = photos[0]; try catalog.setFaceResult(result(p, faces: [face(0.05, 0.06), face(0.05, 0.4), face(0.4, 0.45), face(nil, nil), face(0.05, nil)]), photoId: p.id)
        let h = fc.hints(p); XCTAssertEqual(h.count, 5); XCTAssertTrue(h.allSatisfy { $0.title.contains("experimental") || $0.title == "Analiză neefectuată" }); XCTAssertTrue(h.dropFirst(0).allSatisfy { $0.why.contains("nu e probabilitatea") })
        XCTAssertTrue(h[0].title.contains("posibilă clipire")); XCTAssertTrue(h[1].title.contains("incert")); XCTAssertTrue(h[2].title.contains("deschiși")); XCTAssertTrue(h[3].title.contains("neevaluați")); XCTAssertTrue(h[4].title.contains("incert"), "un singur ochi localizat ⇒ incert")
        XCTAssertTrue(Set(h.map { $0.symbol }).count >= 3, "simboluri distincte (nu doar culoare)")
    }
    func testSubjectChoiceIsPersistentReversibleAndWorksWithoutFaces() throws {
        let p = photos[0]; fc.setSubject(.zone([0.1, 0.2, 0.3, 0.3]), p); XCTAssertEqual(fc.subject(p).kind, "zone"); XCTAssertEqual(fc.subject(p).zone, [0.1, 0.2, 0.3, 0.3])
        fc.setSubject(.face(1), p); XCTAssertEqual(fc.subject(p).face, 1); var s = fc.subject(p); s.dismissed = true; fc.setSubject(s, p); XCTAssertTrue(fc.subject(p).dismissed); fc.setSubject(SubjectState(), p); XCTAssertEqual(fc.subject(p).kind, "none")
        XCTAssertEqual(Catalog.self == Catalog.self, true); let again = try Catalog(url: dir.appendingPathComponent("c.sqlite")); fc.setSubject(.face(0), p); XCTAssertEqual(again.subject(photoId: p.id).face, 0, "supraviețuiește redeschiderii catalogului")
    }
    func testRoundTripOfStoredFacesAndEyeStates() {
        XCTAssertEqual(FaceAnalyzer.eyeState(EyeObservation(box: .zero, openness: 0.3)), .open); XCTAssertEqual(FaceAnalyzer.eyeState(EyeObservation(box: .zero, openness: 0.17)), .uncertain); XCTAssertEqual(FaceAnalyzer.eyeState(EyeObservation(box: .zero, openness: 0.1)), .closed); XCTAssertEqual(FaceAnalyzer.eyeState(nil), .notEvaluated)
        let f = face(0.3, 0.2); XCTAssertEqual(FaceAnalyzer.stored(FaceAnalyzer.observation(f)).left?.openness ?? 0, 0.3, accuracy: 1e-9)
    }
}
