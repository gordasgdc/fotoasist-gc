import XCTest
@testable import PhotoCore

final class LocalizationTests: XCTestCase {
    func fresh(_ choice: AppLanguage, preferred: [String] = ["ro-RO"]) -> Localizer {
        let d = UserDefaults(suiteName: "loc-test-\(UUID().uuidString)")!; d.set(choice.rawValue, forKey: "gdcpa.language"); return Localizer(defaults: d, preferred: preferred)
    }
    func testFollowSystemResolvesAmongSupportedLanguagesWithEnglishFallback() {
        XCTAssertEqual(Localizer.resolve(.system, preferred: ["es-ES", "en"]), .es); XCTAssertEqual(Localizer.resolve(.system, preferred: ["ro-RO"]), .ro)
        XCTAssertEqual(Localizer.resolve(.system, preferred: ["fr-FR", "es"]), .es, "prima limbă acceptată din lista preferințelor"); XCTAssertEqual(Localizer.resolve(.system, preferred: ["fr-FR", "de"]), .en)
        XCTAssertEqual(Localizer.resolve(.en, preferred: ["ro"]), .en, "alegerea explicită bate sistemul")
    }
    func testTranslationsFallBackToRomanianAndAreCountedWhenMissing() {
        let l = fresh(.en); XCTAssertEqual(l.tr("Închide"), "Close"); XCTAssertEqual(l.tr("Text netradus în tabel"), "Text netradus în tabel"); XCTAssertTrue(l.missing.contains("Text netradus în tabel"))
        XCTAssertEqual(fresh(.es).tr("Închide"), "Cerrar"); XCTAssertEqual(fresh(.ro).tr("Închide"), "Închide")
        XCTAssertEqual(fresh(.en).lf("%@ din %@", [3, 10]), "3 of 10"); XCTAssertEqual(fresh(.es).lf("%@ din %@", [3, 10]), "3 de 10")
    }
    func testEveryTranslationKeepsTheSamePlaceholdersAndIsNonEmpty() {
        for (lang, tbl) in LocalizationTables.table {
            XCTAssertFalse(tbl.isEmpty)
            for (k, v) in tbl {
                XCTAssertFalse(v.isEmpty, "\(lang): «\(k)» fără traducere")
                XCTAssertEqual(k.components(separatedBy: "%@").count, v.components(separatedBy: "%@").count, "\(lang): marcajele %@ diferă la «\(k.prefix(50))»")
                XCTAssertEqual(k.components(separatedBy: "\\n").count, v.components(separatedBy: "\\n").count, "\(lang): liniile noi diferă la «\(k.prefix(50))»")
            }
        }
        XCTAssertEqual(Set(LocalizationTables.table[.en]!.keys), Set(LocalizationTables.table[.es]!.keys), "aceleași chei în EN și ES")
    }
    func testPluralsAndNumberFormattingFollowTheLanguage() {
        let ro = fresh(.ro), en = fresh(.en), es = fresh(.es)
        XCTAssertEqual(ro.count(1, "fotografie", "fotografii"), "1 fotografie"); XCTAssertEqual(ro.count(5, "fotografie", "fotografii"), "5 fotografii")
        XCTAssertEqual(ro.count(20, "fotografie", "fotografii"), "20 de fotografii"); XCTAssertEqual(ro.count(119, "fotografie", "fotografii"), "119 fotografii"); XCTAssertEqual(ro.count(100, "fotografie", "fotografii"), "100 de fotografii")
        XCTAssertEqual(ro.count(0, "fotografie", "fotografii"), "0 fotografii")
        XCTAssertEqual(en.count(1, "fotografie", "fotografii"), "1 photo"); XCTAssertEqual(en.count(2, "fotografie", "fotografii"), "2 photos"); XCTAssertEqual(es.count(1, "fotografie", "fotografii"), "1 foto"); XCTAssertEqual(es.count(3, "fotografie", "fotografii"), "3 fotos")
        XCTAssertEqual(ro.number(12345), "12.345"); XCTAssertEqual(en.number(12345), "12,345"); XCTAssertEqual(ro.number(1.5, fraction: 1), "1,5"); XCTAssertEqual(en.number(1.5, fraction: 1), "1.5")
    }

    // --- verificări țintite EN/ES (riscuri concrete, nu repetarea suitei în alte limbi) ---
    func testEnglishAndSpanishTablesCoverTheSameKeys() {
        let en = Set(LocalizationTables.table[.en]!.keys), es = Set(LocalizationTables.table[.es]!.keys)
        XCTAssertEqual(en.subtracting(es), [], "chei fără ES"); XCTAssertEqual(es.subtracting(en), [], "chei fără EN")
    }
    func testNoLongRomanianTextIsLeftUntranslatedInEnglishOrSpanish() {
        let ok: Set<String> = ["ASC CDL", "Lift · Gamma · Gain", "Mired", "Master", "Look", "EXTERNAL TEST STORAGE NOT AVAILABLE"]   /* termeni identici în limbi */
        for (lang, tbl) in LocalizationTables.table { for (k, v) in tbl where k.split(separator: " ").count >= 4 && !ok.contains(k) {
            XCTAssertNotEqual(k, v, "text românesc rămas netradus în \(lang): \(k.prefix(60))") } }
    }
    func testNumbersInDynamicMessagesFollowTheLanguage() {
        let es = fresh(.es), en = fresh(.en), ro = fresh(.ro)
        XCTAssertEqual(es.argText(12345.5), "12.345,5"); XCTAssertEqual(es.argText(1234.5), "1234,5", "ortografia spaniolă nu grupează 4 cifre"); XCTAssertEqual(en.argText(1234.5), "1,234.5"); XCTAssertEqual(ro.argText(1234.5), "1.234,5")
        XCTAssertEqual(es.argText(2.0), "2"); XCTAssertEqual(es.lf("%@ fotografii exportate în %@", [12000, "/x"]), "12.000 fotos exportadas en /x")
        XCTAssertEqual(en.lf("%@ fotografii exportate în %@", [12000, "/x"]), "12,000 photos exported to /x")
    }
    func testPluralisationAtZeroOneAndMany() {
        for (l, one, many) in [(fresh(.en), "photo", "photos"), (fresh(.es), "foto", "fotos")] {
            XCTAssertEqual(l.count(0, "fotografie", "fotografii"), "0 \(many)"); XCTAssertEqual(l.count(1, "fotografie", "fotografii"), "1 \(one)")
            XCTAssertEqual(l.count(2, "fotografie", "fotografii"), "2 \(many)"); XCTAssertEqual(l.count(21, "fotografie", "fotografii"), "21 \(many)")
        }
        XCTAssertEqual(fresh(.ro).count(1, "fotografie", "fotografii"), "1 fotografie"); XCTAssertEqual(fresh(.ro).count(20, "fotografie", "fotografii"), "20 de fotografii")
    }
    func testDynamicMessagesNeverLeavePlaceholdersBehind() {
        for lang in [AppLanguage.en, .es] { let l = fresh(lang)
            for (k, v) in LocalizationTables.table[lang]! where k.contains("%@") {
                let n = k.components(separatedBy: "%@").count - 1; let out = l.lf(k, Array(repeating: "x", count: n)); XCTAssertFalse(out.contains("%@"), v); XCTAssertEqual(out, v.replacingOccurrences(of: "%@", with: "x")) } }
    }
}
