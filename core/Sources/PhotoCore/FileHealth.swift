import Foundation

/// Clasificarea fișierelor cu probleme, cu DOVADĂ pentru fiecare concluzie. Nu atinge fișierele și nu concluzionează «corupt» din dimensiune sau nume: verifică existența, volumul, citirea, stabilitatea (două citiri la interval) și semnătura.
public struct FileHealth: Equatable {
    public enum Kind: String { case ok, missing, volumeUnavailable, unreadable, empty, appleDouble, truncatedSuspect, unstable
        public var label: String { switch self { case .ok: return L("în regulă"); case .missing: return L("lipsă pe disc"); case .volumeUnavailable: return L("volum indisponibil"); case .unreadable: return L("eroare la citire"); case .empty: return L("fișier gol (0 B)"); case .appleDouble: return L("AppleDouble (resource fork)"); case .truncatedSuspect: return L("posibil trunchiat"); case .unstable: return L("instabil (se modifică)") } } }
    public var kind: Kind; public var evidence: String
    static let rawSignatures: [[UInt8]] = [[0x49, 0x49, 0x2A, 0x00], [0x4D, 0x4D, 0x00, 0x2A], Array("FUJIFILM".utf8)]   // TIFF-based (ARW/CR2/NEF/DNG/RW2/ORF), RAF
    /// `recordedSize` = dimensiunea din catalog la import (dacă diferă de cea actuală, fișierul s-a schimbat de la import).
    public static func inspect(path: String, recordedSize: Int64? = nil, stabilityDelay: TimeInterval = 0.4) -> FileHealth {
        let fm = FileManager.default; let url = URL(fileURLWithPath: path)
        let comps = url.pathComponents; if comps.count > 3, comps[1] == "Volumes" { let vol = "/Volumes/" + comps[2]; if !fm.fileExists(atPath: vol) { return FileHealth(kind: .volumeUnavailable, evidence: "volumul \(vol) nu e montat") } }
        guard fm.fileExists(atPath: path) else { return FileHealth(kind: .missing, evidence: L("calea nu există (volumul e montat)")) }
        guard let a = try? fm.attributesOfItem(atPath: path), let size1 = (a[.size] as? NSNumber)?.int64Value else { return FileHealth(kind: .unreadable, evidence: L("atributele nu se pot citi")) }
        let m1 = a[.modificationDate] as? Date
        var head = Data()
        if size1 > 0 { guard let h = FileHandle(forReadingAtPath: path) else { return FileHealth(kind: .unreadable, evidence: L("fișierul nu se poate deschide pentru citire")) }; defer { try? h.close() }
            do { head = try h.read(upToCount: 16) ?? Data() } catch { return FileHealth(kind: .unreadable, evidence: LF("eroare la citire: %@", error.localizedDescription)) } }
        if stabilityDelay > 0 { Thread.sleep(forTimeInterval: stabilityDelay) }
        let a2 = try? fm.attributesOfItem(atPath: path); let size2 = (a2?[.size] as? NSNumber)?.int64Value ?? size1; let m2 = a2?[.modificationDate] as? Date
        if size2 != size1 || m1 != m2 { return FileHealth(kind: .unstable, evidence: LF("dimensiunea/data s-au schimbat între două citiri (%@ → %@ B): se copiază sau se scrie", size1, size2)) }
        let when = m1.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .medium) } ?? "?"
        let rec = recordedSize.map { $0 == size1 ? L("; identic cu dimensiunea din catalog la import") : LF("; DIFERIT de dimensiunea din catalog la import (%@ B)", $0) } ?? ""
        if size1 == 0 { return FileHealth(kind: .empty, evidence: LF("0 B, stabil între două citiri, modificat %@%@", when, rec)) }
        let b = [UInt8](head)
        if b.count >= 4, b[0] == 0x00, b[1] == 0x05, b[2] == 0x16, (b[3] == 0x07 || b[3] == 0x00) { return FileHealth(kind: .appleDouble, evidence: LF("semnătura AppleDouble 0x00051607 la început; %@ B%@", size1, rec)) }
        let sig = rawSignatures.contains { s in b.count >= s.count && Array(b.prefix(s.count)) == s } || (b.count >= 12 && Array(b[4..<8]) == Array("ftyp".utf8))
        if !sig { return FileHealth(kind: .truncatedSuspect, evidence: LF("%@ B, fără semnătură RAW cunoscută (primii octeți: %@)%@; decodorul decide", size1, b.prefix(8).map { String(format: "%02x", $0) }.joined(), rec)) }
        return FileHealth(kind: .ok, evidence: LF("%@ B, semnătură RAW validă, stabil%@", size1, rec))
    }
}
