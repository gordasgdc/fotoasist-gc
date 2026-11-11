import Foundation

/// XMP: citire (doar citire) a evaluării dintr-un sidecar `.xmp` aflat lângă un RAW original și maparea decizie/evaluare → `xmp:Rating`.
/// Convenția Adobe: `xmp:Rating` 1…5 = stele, 0 = fără evaluare, −1 = respins. Originalele și sidecar-urile lor NU se modifică niciodată.
public enum XMPSidecar {
    public static func sidecarURL(forRaw raw: String) -> URL? {
        let u = URL(fileURLWithPath: raw); let base = u.deletingPathExtension()
        for cand in [base.appendingPathExtension("xmp"), base.appendingPathExtension("XMP"), u.appendingPathExtension("xmp")] where FileManager.default.fileExists(atPath: cand.path) { return cand }
        return nil
    }
    /// Evaluarea din sidecar: atribut `xmp:Rating="N"` sau element `<xmp:Rating>N</xmp:Rating>`; nil dacă lipsește sau nu e un număr în −1…5.
    public static func rating(inXMP text: String) -> Int? {
        for pat in [#"xmp:Rating\s*=\s*"(-?\d+)""#, #"<xmp:Rating>\s*(-?\d+)\s*</xmp:Rating>"#] {
            if let re = try? NSRegularExpression(pattern: pat), let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range(at: 1), in: text), let v = Int(text[r]), (-1...5).contains(v) { return v }
        }
        return nil
    }
    public static func readRating(forRaw raw: String) -> Int? {
        guard let u = sidecarURL(forRaw: raw), let d = try? Data(contentsOf: u), d.count < 2_000_000, let t = String(data: d, encoding: .utf8) else { return nil }
        return rating(inXMP: t)
    }
    /// Valoarea `xmp:Rating` pentru un export: respins → −1, altfel stelele (0…5).
    public static func ratingForExport(decision: Decision, stars: Int) -> Int { decision == .reject ? -1 : min(5, max(0, stars)) }
}
