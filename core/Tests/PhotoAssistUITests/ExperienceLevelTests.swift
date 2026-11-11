import XCTest
@testable import PhotoAssistUI

final class ExperienceLevelTests: XCTestCase {
    func testLevelsAreNestedViews() {
        XCTAssertEqual(ExperienceLevel.level(ofPanel: "exposure"), .beginner)
        XCTAssertEqual(ExperienceLevel.level(ofPanel: "skin"), .intermediate)
        XCTAssertEqual(ExperienceLevel.level(ofPanel: "printer"), .advanced)
        XCTAssertEqual(ExperienceLevel.level(ofPanel: "panou-necunoscut"), .advanced, "panourile neînregistrate nu dispar la nivelul avansat")
        let p = PanelState(); let saved = p.level; defer { p.level = saved }
        p.level = .beginner; XCTAssertTrue(p.shows("exposure")); XCTAssertFalse(p.shows("skin")); XCTAssertFalse(p.shows("printer"))
        p.level = .intermediate; XCTAssertTrue(p.shows("skin")); XCTAssertFalse(p.shows("printer"))
        p.level = .advanced; XCTAssertTrue(p.shows("printer"))
    }
}
