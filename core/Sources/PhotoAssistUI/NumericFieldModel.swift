import Foundation

/// Logica de sincronizare a câmpului numeric din `SliderRow` (testabilă, fără SwiftUI). Cauza defectului din dev.47: cât timp câmpul avea focus,
/// o schimbare EXTERNĂ a valorii (Anulează, resetare, schimbarea fotografiei) nu actualiza textul, iar la ieșirea din câmp textul vechi era reaplicat
/// (valoare veche + reactivarea modulului). Tastarea schimbă doar `text`, nu valoarea (se confirmă la Enter/ieșire), deci orice schimbare a valorii
/// vine din altă sursă și textul o urmează mereu; la ieșire se confirmă DOAR un text diferit de cel afișat pentru valoarea curentă.
extension Notification.Name { static let gdcCommitNumericFields = Notification.Name("gdcpa.commitNumericFields") }

struct NumericFieldModel {
    var fmt: String
    var range: ClosedRange<Double>
    var text = ""
    init(fmt: String, range: ClosedRange<Double>, value: Double) { self.fmt = fmt; self.range = range; text = String(format: fmt, value) }
    func display(_ v: Double) -> String { String(format: fmt, v) }
    /// Valoarea s-a schimbat din afara câmpului: textul o urmează (și cu focus, fără pierderea focusului).
    mutating func externalChange(to v: Double) { text = display(v) }
    /// Valoarea de aplicat la Enter/ieșire din câmp; `nil` = nimic de aplicat (text neschimbat sau neinterpretabil). Textul rămâne cel tastat până la `finish`.
    func pendingValue(current: Double) -> Double? {
        guard text != display(current) else { return nil }
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t) else { return nil }
        let c = min(range.upperBound, max(range.lowerBound, v)); return c == current ? nil : c
    }
    /// După confirmare/abandon: textul arată valoarea reală.
    mutating func finish(value: Double) { text = display(value) }
}
