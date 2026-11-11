import XCTest
@testable import PhotoAccess

/// Open-source edition: nothing is restricted, and the update check only trusts a well-formed release of the public repository.
final class OpenEditionTests: XCTestCase {
    func testEveryFeatureIsAlwaysPermitted() {
        let p = PhotoPolicies.standard()
        XCTAssertFalse(p.restrictsAnything)
        for f in PhotoFeature.allCases { XCTAssertTrue(p.permits(f), f.rawValue) }
    }

    private func checker(_ json: String, status: Int = 200) -> PhotoUpdateChecker {
        PhotoUpdateChecker(source: URL(string: "https://api.github.com/x")!) { _ in (Data(json.utf8), status) }
    }
    private func release(_ tag: String, asset: String, url: String) -> String {
        "{\"tag_name\":\"\(tag)\",\"assets\":[{\"name\":\"\(asset)\",\"size\":123,\"browser_download_url\":\"\(url)\"}]}"
    }

    func testNewerReleaseWithTheVersionedInstallerIsOffered() async {
        let url = "https://github.com/gordasgdc/fotoasist-gc/releases/download/v1.2.0/FotoAsistGC-1.2.0.pkg"
        let r = await checker(release("v1.2.0", asset: "FotoAsistGC-1.2.0.pkg", url: url)).check(installedVersion: "1.1.9")
        guard case .updateAvailable(let o) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(o.version, "1.2.0"); XCTAssertEqual(o.downloadURL.absoluteString, url); XCTAssertEqual(o.size, 123)
    }

    func testSameOrOlderReleaseIsUpToDate() async {
        let url = "https://github.com/gordasgdc/fotoasist-gc/releases/download/v1.0.0/FotoAsistGC-1.0.0.pkg"
        let same = await checker(release("v1.0.0", asset: "FotoAsistGC-1.0.0.pkg", url: url)).check(installedVersion: "1.0.0")
        XCTAssertEqual(same, .upToDate(installed: "1.0.0", available: "1.0.0"))
        let older = await checker(release("v1.0.0", asset: "FotoAsistGC-1.0.0.pkg", url: url)).check(installedVersion: "1.0.1")
        XCTAssertEqual(older, .upToDate(installed: "1.0.1", available: "1.0.0"))
    }

    func testInstallerOnAnotherHostOrWithAnotherNameIsRejected() async {
        let foreign = await checker(release("v2.0.0", asset: "FotoAsistGC-2.0.0.pkg", url: "https://example.org/FotoAsistGC-2.0.0.pkg")).check(installedVersion: "1.0.0")
        XCTAssertEqual(foreign, .invalid(code: "invalid_release:host"))
        let renamed = await checker(release("v2.0.0", asset: "Other.pkg", url: "https://github.com/gordasgdc/fotoasist-gc/releases/download/v2.0.0/Other.pkg")).check(installedVersion: "1.0.0")
        XCTAssertEqual(renamed, .invalid(code: "invalid_release:asset"))
        let plain = await checker(release("v2.0.0", asset: "FotoAsistGC-2.0.0.pkg", url: "http://github.com/gordasgdc/fotoasist-gc/releases/download/v2.0.0/FotoAsistGC-2.0.0.pkg")).check(installedVersion: "1.0.0")
        XCTAssertEqual(plain, .invalid(code: "invalid_release:host"))
    }

    func testCannotCheckIsNeverReportedAsUpToDate() async {
        let off = await PhotoUpdateChecker(source: URL(string: "https://api.github.com/x")!) { _ in throw URLError(.notConnectedToInternet) }.check(installedVersion: "1.0.0")
        XCTAssertEqual(off, .offline)
        let http = await checker("{}", status: 500).check(installedVersion: "1.0.0")
        XCTAssertEqual(http, .failed("HTTP 500"))
        let garbage = await checker("not json").check(installedVersion: "1.0.0")
        XCTAssertEqual(garbage, .invalid(code: "invalid_release:format"))
    }

    func testVersionOrderingIsNumericNotLexical() {
        XCTAssertTrue(PhotoUpdateChecker.isNewer([1, 10, 0], than: [1, 9, 9]))
        XCTAssertFalse(PhotoUpdateChecker.isNewer([1, 0], than: [1, 0, 0]))
        XCTAssertEqual(PhotoUpdateChecker.parse("1.2.3-dev.4") ?? [], [1, 2, 3])
        XCTAssertNil(PhotoUpdateChecker.parse("abc"))
    }
}
