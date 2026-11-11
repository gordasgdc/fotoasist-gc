import Foundation

/// Indicii fotografice explicabile din semnalele deja calculate pe PREVIZUALIZAREA camerei (nu pe RAW). Nu sunt verdicte: niciun cadru nu e respins sau declarat „prost”.
/// Starea „analiză neefectuată” (fără semnale) e separată de „indiciu” și de „fișier invalid” (tratat în altă parte, prin sănătatea fișierului).
public struct PhotoCue: Identifiable, Equatable {
    public enum Kind: Equatable { case analysisMissing, exposure, sharpness }
    public enum Certainty: Equatable { case info, uncertain }
    public var id: String { "\(kind)-\(title)" }
    public var kind: Kind; public var certainty: Certainty; public var title: String; public var why: String
}

public enum ExposureCues {
    /// Praguri INIȚIALE (neevaluate pe un set etichetat): peste 5% pixeli la capăt = notabil (pe 197 de cadre reale: ≥2% = 118 cadre semnalate, ≥5% ≈ 75, ≥10% ≈ 50; 5% reduce zgomotul fără prag validat); mediana sub 40 / peste 200 (din 255) = cadru întunecat/luminos în previzualizare.
    public static let clipNoticePct = 5.0, darkMedian = 40.0, brightMedian = 200.0
    public static func exposure(_ s: Signals?) -> [PhotoCue] {
        guard let s = s else { return [PhotoCue(kind: .analysisMissing, certainty: .info, title: L("Semnale de expunere/claritate: analiză neefectuată"), why: L("Semnalele cadrului nu au fost calculate încă; asta nu înseamnă că fotografia e bună sau proastă."))] }
        var out: [PhotoCue] = []
        if s.clipHighPct >= clipNoticePct { out.append(PhotoCue(kind: .exposure, certainty: .uncertain, title: LF("Lumini posibil tăiate: %@% din pixeli", String(format: "%.1f", s.clipHighPct)), why: L("Măsurat pe previzualizarea camerei (JPEG), nu pe RAW: RAW-ul poate păstra detaliu aici. Verifică în «Tăieri» pe imaginea redată."))) }
        if s.clipLowPct >= clipNoticePct { out.append(PhotoCue(kind: .exposure, certainty: .uncertain, title: LF("Umbre posibil la zero: %@% din pixeli", String(format: "%.1f", s.clipLowPct)), why: L("Poate fi intenționat (siluete, fundal negru). Previzualizarea camerei, nu RAW."))) }
        if s.medianLuma <= darkMedian { out.append(PhotoCue(kind: .exposure, certainty: .uncertain, title: L("Cadru întunecat în previzualizare"), why: LF("Luminanța mediană %@ din 255; scenele în ton scăzut sunt adesea intenționate.", String(format: "%.0f", s.medianLuma)))) }
        if s.medianLuma >= brightMedian { out.append(PhotoCue(kind: .exposure, certainty: .uncertain, title: L("Cadru luminos în previzualizare"), why: LF("Luminanța mediană %@ din 255; scenele în ton înalt sunt adesea intenționate.", String(format: "%.0f", s.medianLuma)))) }
        return out
    }
    /// Claritate RELATIVĂ în rafală: scorul (varianța Laplacianului) nu e comparabil între conținuturi și e umflat de zgomot; se compară doar cadrele aceleiași rafale, iar rezultatul e „mai puțin clar decât cel mai clar din grup”, doar dacă diferența e mare.
    public static func sharpness(own: Signals?, groupSignals: [Signals]) -> PhotoCue? {
        guard let own = own, groupSignals.count >= 2, let best = groupSignals.map({ $0.sharpness }).max(), best > 0 else { return nil }
        let ratio = own.sharpness / best; guard ratio < 0.5 else { return nil }
        return PhotoCue(kind: .sharpness, certainty: .uncertain, title: LF("Posibil mai puțin clar decât cel mai clar din rafală (%@% din scor)", String(format: "%.0f", ratio * 100)), why: L("Comparație prudentă doar în aceeași rafală, pe previzualizare. Nu arată focalizarea pe ochi și poate fi mișcare intenționată; zgomotul umflă scorul."))
    }
}
