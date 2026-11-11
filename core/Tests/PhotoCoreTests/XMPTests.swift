import XCTest
@testable import PhotoCore

final class XMPTests: XCTestCase {
    func testRatingParsingAttributeAndElementAndBounds() {
        XCTAssertEqual(XMPSidecar.rating(inXMP: #"<rdf:Description xmp:Rating="4" xmlns:xmp="x"/>"#), 4)
        XCTAssertEqual(XMPSidecar.rating(inXMP: "<xmp:Rating>-1</xmp:Rating>"), -1)
        XCTAssertNil(XMPSidecar.rating(inXMP: #"xmp:Rating="9""#)); XCTAssertNil(XMPSidecar.rating(inXMP: "<x/>"))
        XCTAssertEqual(XMPSidecar.ratingForExport(decision: .reject, stars: 3), -1); XCTAssertEqual(XMPSidecar.ratingForExport(decision: .keep, stars: 3), 3)
    }
    func testSidecarIsFoundBesideRawAndReadOnly() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("xmp-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let raw = d.appendingPathComponent("IMG_1.ARW"); try Data([1]).write(to: raw); let x = d.appendingPathComponent("IMG_1.xmp"); try #"<x:xmpmeta><rdf:RDF><rdf:Description xmp:Rating="5"/></rdf:RDF></x:xmpmeta>"#.write(to: x, atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: x); XCTAssertEqual(XMPSidecar.readRating(forRaw: raw.path), 5); XCTAssertEqual(try Data(contentsOf: x), before)
        XCTAssertNil(XMPSidecar.readRating(forRaw: d.appendingPathComponent("NONE.ARW").path))
    }
}
