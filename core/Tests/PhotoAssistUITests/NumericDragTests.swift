import XCTest
@testable import PhotoAssistUI

final class NumericDragTests: XCTestCase {
    func session(_ v: Double, _ r: ClosedRange<Double>, _ fmt: String = "%+.2f", wrap: Bool = false) -> NumericDragSession { NumericDragSession(value: v, pressX: 100, range: r, fmt: fmt, wrap: wrap) }
    func drive(_ s: inout NumericDragSession, to xs: [Double], fine: Bool = false) -> Double? {
        var last: Double?; for x in xs { if case .changed(let v) = s.move(x: x, fine: fine) { last = v } }; return last
    }

    func testPressAndSubThresholdMovesNeverChangeTheValue() {
        var s = session(0.5, -1...1)
        XCTAssertEqual(s.move(x: 100, fine: false), .none); XCTAssertEqual(s.move(x: 102, fine: false), .none); XCTAssertFalse(s.active)
        XCTAssertEqual(s.move(x: 103, fine: false), .began, "pragul de 3 puncte începe tragerea fără a schimba valoarea (fără salt)")
    }
    func testRightIncreasesLeftDecreasesAndCrossesNeutral() {
        var s = session(0.10, -1...1); _ = s.move(x: 104, fine: false)
        let up = drive(&s, to: [124, 144]); XCTAssertNotNil(up); XCTAssertGreaterThan(up!, 0.10)
        var d = session(0.10, -1...1); _ = d.move(x: 104, fine: false)
        let down = drive(&d, to: Array(stride(from: 100.0, through: 40.0, by: -4))); XCTAssertNotNil(down); XCTAssertLessThan(down!, 0, "traversează neutrul spre valori negative")
    }
    func testLimitsAreRespectedAndThereIsNoDeadZoneAfterTheLimit() {
        var s = session(0.9, -1...1); _ = s.move(x: 104, fine: false)
        XCTAssertEqual(drive(&s, to: [400, 800, 1200]), 1.0)
        let back = drive(&s, to: [1190]); XCTAssertNotNil(back); XCTAssertLessThan(back!, 1.0, "mișcarea înapoi răspunde imediat (raw e fixat la limită)")
    }
    func testNeutralOneParameterAndRangeScaledSensitivity() {
        var s = session(1.0, 0...2, "%.2f"); _ = s.move(x: 104, fine: false)
        let v = drive(&s, to: [104 + 32])!; XCTAssertEqual(v, 1.0 + 32 * (2.0 / 320), accuracy: 0.011)
        var k = session(6500, 2000...12000, "%.0f"); _ = k.move(x: 104, fine: false)
        XCTAssertEqual(drive(&k, to: [104 + 32])!, 6500 + 32 * (10000.0 / 320), accuracy: 1, "Kelvin: sensibilitate proporțională cu intervalul, nu aceeași variație numerică")
    }
    func testFineModeIsTenTimesFinerAndSwitchingMidDragDoesNotJump() {
        var n = session(0, -1...1); _ = n.move(x: 104, fine: false); let a = drive(&n, to: [204])!
        var f = session(0, -1...1); _ = f.move(x: 104, fine: true); let b = drive(&f, to: [204], fine: true)!
        XCTAssertEqual(b, a / 10, accuracy: 0.002)
        var m = session(0, -1...1); _ = m.move(x: 104, fine: false); let first = drive(&m, to: [124])!
        let after = drive(&m, to: [125], fine: true)!; XCTAssertEqual(after, first, accuracy: 0.0101, "comutarea Option nu produce salt mai mare decât o unitate afișată")
    }
    func testValuesFollowDisplayPrecisionAndFineAddsOneDigit() {
        XCTAssertEqual(NumericDragMath.decimals("%+.2f"), 2); XCTAssertEqual(NumericDragMath.decimals("%.0f"), 0); XCTAssertEqual(NumericDragMath.decimals("%.3f"), 3)
        XCTAssertEqual(NumericDragMath.round(0.12345, fmt: "%+.2f", fine: false), 0.12, accuracy: 1e-12); XCTAssertEqual(NumericDragMath.round(0.12345, fmt: "%+.2f", fine: true), 0.123, accuracy: 1e-12)
    }
    func testWrapAroundForAngles() {
        var s = session(350, 0...360, "%.0f", wrap: true); _ = s.move(x: 104, fine: false)
        let v = drive(&s, to: [104 + 60])!; XCTAssertEqual(v, (350 + 60 * 360.0 / 320).truncatingRemainder(dividingBy: 360), accuracy: 1.01); XCTAssertLessThan(v, 350, "a trecut de 360 și a reintrat de la 0")
    }
    func testCancelStopsFurtherChanges() {
        var s = session(0.2, -1...1); _ = s.move(x: 104, fine: false); XCTAssertNotNil(drive(&s, to: [150]))
        s.cancelled = true; XCTAssertEqual(s.move(x: 300, fine: false), .none); XCTAssertEqual(s.startValue, 0.2, "Escape restabilește startValue")
    }
    func testKeyboardStepsRespectParameterStepFineStepLimitsAndWrap() {
        XCTAssertEqual(NumericDragMath.keyAdjusted(0.5, direction: 1, range: -1...1, fmt: "%+.2f", fine: false), 0.51, accuracy: 1e-12)
        XCTAssertEqual(NumericDragMath.keyAdjusted(0.5, direction: -1, range: -1...1, fmt: "%+.2f", fine: true), 0.499, accuracy: 1e-12)
        XCTAssertEqual(NumericDragMath.keyAdjusted(1.0, direction: 1, range: -1...1, fmt: "%+.2f", fine: false), 1.0)
        XCTAssertEqual(NumericDragMath.keyAdjusted(6500, direction: 1, range: 2000...12000, fmt: "%.0f", fine: false), 6510); XCTAssertEqual(NumericDragMath.keyAdjusted(6500, direction: 1, range: 2000...12000, fmt: "%.0f", fine: true), 6501)
        XCTAssertEqual(NumericDragMath.keyAdjusted(0.0, direction: -1, range: -1...1, fmt: "%+.2f", fine: false), -0.01, accuracy: 1e-12, "trece prin neutru")
        XCTAssertEqual(NumericDragMath.keyAdjusted(359, direction: 1, range: 0...360, fmt: "%.0f", fine: false, wrap: true), 0, accuracy: 1e-9)
    }
    func testTypingStillCommitsExactNumbersThroughTheExistingFieldModel() {
        var f = NumericFieldModel(fmt: "%+.2f", range: -1...1, value: 0.2); f.text = "0,375"
        XCTAssertEqual(f.pendingValue(current: 0.2), 0.375, "tastarea exactă nu e cuantizată de gest")
        f.text = "5"; XCTAssertEqual(f.pendingValue(current: 0.2), 1.0, "limitele se respectă și la tastare")
    }
}
