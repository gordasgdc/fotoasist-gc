import XCTest
import CryptoKit
@testable import PhotoAssistUI

@MainActor
final class BrandTests: XCTestCase {
    func testSymbolIsLoadedFromTheOriginalSVGAndIsSquare() throws {
        let img = try XCTUnwrap(Brand.symbolImage()); XCTAssertEqual(img.size.width, img.size.height); XCTAssertTrue(img.isTemplate)           // proporții păstrate (110×110), monocrom
    }
    /// Copia din resurse e identică octet cu octet cu simbolul original al proprietarului (originalul rămâne intact pe extern).
    func testBundledSymbolIsByteIdenticalToTheOriginal() throws {
        guard let root = ProcessInfo.processInfo.environment["GDC_PA_ROOT"], let orig = try? Data(contentsOf: URL(fileURLWithPath: root + "/design/identity/author-concept-01/FotoAsist-GC_simbol.svg")) else { throw XCTSkip("fără originalul") }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "FotoAsist-GC_simbol", withExtension: "svg", subdirectory: "Brand"))
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: url)), SHA256.hash(data: orig))
    }
    func testProductNameIsExact() { XCTAssertEqual(Brand.productName, "FotoAsist GC"); XCTAssertEqual(Brand.author, "Cristi Gordaș") }
}
