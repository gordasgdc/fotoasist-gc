import Foundation

/// Estimare statistică de expunere, ORIENTATIVĂ și NEVALIDATĂ (n = 12 fotografii ale unui singur set; vezi docs/COLOR_AND_OUTPUT_CONTRACT.md §„Expunere: tehnică, sugestie, alegere creativă”).
/// Trei straturi separate: (1) expunerea TEHNICĂ a decodorului = 0 (1.0 = alb de referință; nu e luminozitate de afișare); (2) SUGESTIA = această structură, nu se aplică singură;
/// (3) alegerea CREATIVĂ = valoarea din reglaje (manual sau mod automat + corecție). O scenă low-key NU e subexpusă: „mediană → gri 18%” poate cere 6–8 stopuri și o supraexpune, de aceea
/// sugestia principală e MINIMUL dintre candidați, iar scena low-key e semnalată explicit.
/// Candidați: `medianToGrey` = log2(0.18/mediana luminanței DWG) și `highlightAnchor` = log2(1.0/p99) (nu aduce luminile peste albul de referință; la scene cu lumini deja la alb dă ≈ 0).
public struct ExposureSuggestion: Codable, Equatable {
    public static let estimatorVersion = 2
    public var stops: Double                // sugestia principală = min(medianToGrey, highlightAnchor)
    public var medianToGrey: Double, highlightAnchor: Double
    public var median: Double, p99: Double, p995: Double
    public var lowKeyWarning: Bool          // medianToGrey − highlightAnchor > 2 stopuri: majoritatea cadrului e în umbre; ridicarea la gri 18% ar supraexpune
    public var sceneHint: String            // "low-key" / "intermediar" / "high-key" — doar etichetă informativă
    public var version = ExposureSuggestion.estimatorVersion
    public init(stops: Double, medianToGrey: Double, highlightAnchor: Double, median: Double, p99: Double, p995: Double, lowKeyWarning: Bool, sceneHint: String) {
        self.stops = stops; self.medianToGrey = medianToGrey; self.highlightAnchor = highlightAnchor; self.median = median; self.p99 = p99; self.p995 = p995; self.lowKeyWarning = lowKeyWarning; self.sceneHint = sceneHint }

    static let yw: (Float, Float, Float) = (0.2949, 0.6254, 0.0797)   // luminanța primarelor DWG
    /// `image` = DWG LINIAR (înainte de codarea DI). `step` = pas de eșantionare pe pixel (pe x și y).
    public static func compute(from image: FloatImage, step: Int = 6) -> ExposureSuggestion {
        var ys = [Float](); ys.reserveCapacity((image.width / step + 1) * (image.height / step + 1))
        var y = 0; while y < image.height { var x = 0; while x < image.width { let i = 3 * (y * image.width + x)
            ys.append(max(1e-6, yw.0 * image.rgb[i] + yw.1 * image.rgb[i + 1] + yw.2 * image.rgb[i + 2])); x += step }; y += step }
        guard !ys.isEmpty else { return ExposureSuggestion(stops: 0, medianToGrey: 0, highlightAnchor: 0, median: 0, p99: 0, p995: 0, lowKeyWarning: false, sceneHint: "intermediar") }
        ys.sort()
        func q(_ p: Double) -> Double { Double(ys[min(ys.count - 1, Int((Double(ys.count - 1) * p / 100).rounded()))]) }
        let med = q(50), p99 = q(99), p995 = q(99.5)
        let toGrey = log2(0.18 / med), anchor = log2(1.0 / max(p99, 1e-6))
        let hint = toGrey > 4.5 ? "low-key" : (toGrey < 2.0 ? "high-key" : "intermediar")
        return ExposureSuggestion(stops: min(toGrey, anchor), medianToGrey: toGrey, highlightAnchor: anchor, median: med, p99: p99, p995: p995, lowKeyWarning: toGrey - anchor > 2.0, sceneHint: hint)
    }
}
