import SwiftUI
import AppKit
import PhotoCore

/// Gestul de tragere pe o valoare numerică (testabil, fără SwiftUI): relativ la valoarea de la început (fără salt la apăsare), prag mic care separă clicul de tragere,
/// sensibilitate dedusă din intervalul și precizia parametrului, Option = ×0,1, limite respectate (sau înfășurare pentru unghiuri), fără zonă moartă la limite.
enum NumericDragMath {
    /// Zecimale afișate de un format de tip `%+.2f` / `%.0f` / `%.3f`.
    static func decimals(_ fmt: String) -> Int {
        guard let dot = fmt.firstIndex(of: ".") else { return 0 }
        return Int(fmt[fmt.index(after: dot)...].prefix { $0.isNumber }) ?? 0
    }
    static func quantum(_ fmt: String, fine: Bool) -> Double { pow(10, -Double(decimals(fmt) + (fine ? 1 : 0))) }
    static func round(_ v: Double, fmt: String, fine: Bool) -> Double { let d = decimals(fmt) + (fine ? 1 : 0); return Double(String(format: "%.\(d)f", v)) ?? v }
    /// Unități pe punct de ecran: tot intervalul în ~320 puncte (parametrul decide prin interval și precizie), fin = ×0,1.
    static func unitsPerPoint(range: ClosedRange<Double>, fine: Bool) -> Double { (range.upperBound - range.lowerBound) / 320 * (fine ? 0.1 : 1) }
    /// Pasul tastaturii: o unitate afișată; pe intervale foarte largi în raport cu precizia (Kelvin, grade) de 10×. Fin = pasul/10.
    static func keyStep(range: ClosedRange<Double>, fmt: String, fine: Bool) -> Double {
        let q = quantum(fmt, fine: false); let span = range.upperBound - range.lowerBound
        return (span / q > 400 ? q * 10 : q) * (fine ? 0.1 : 1)
    }
    static func keyAdjusted(_ v: Double, direction: Int, range: ClosedRange<Double>, fmt: String, fine: Bool, wrap: Bool = false) -> Double {
        normalize(round(v + Double(direction) * keyStep(range: range, fmt: fmt, fine: fine), fmt: fmt, fine: fine), range: range, wrap: wrap)
    }
    static func normalize(_ v: Double, range: ClosedRange<Double>, wrap: Bool) -> Double {
        if wrap { let span = range.upperBound - range.lowerBound; var r = (v - range.lowerBound).truncatingRemainder(dividingBy: span); if r < 0 { r += span }; return range.lowerBound + r }
        return min(range.upperBound, max(range.lowerBound, v))
    }
}

struct NumericDragSession {
    enum Event: Equatable { case none, began, changed(Double) }
    let range: ClosedRange<Double>, fmt: String, wrap: Bool, threshold: Double
    let startValue: Double
    private var raw: Double, pressX: Double, lastX: Double
    private(set) var active = false
    var cancelled = false
    init(value: Double, pressX: Double, range: ClosedRange<Double>, fmt: String, wrap: Bool = false, threshold: Double = 3) {
        self.range = range; self.fmt = fmt; self.wrap = wrap; self.threshold = threshold; startValue = value; raw = value; self.pressX = pressX; lastX = pressX
    }
    /// Apăsare fără deplasare peste prag ⇒ clic (editare prin tastare). Peste prag ⇒ tragere; deplasarea de până la prag nu modifică valoarea.
    mutating func move(x: Double, fine: Bool) -> Event {
        if cancelled { return .none }
        if !active {
            guard abs(x - pressX) >= threshold else { return .none }
            active = true; lastX = x; return .began
        }
        raw += (x - lastX) * NumericDragMath.unitsPerPoint(range: range, fine: fine); lastX = x
        if wrap { raw = NumericDragMath.normalize(raw, range: range, wrap: true) } else { raw = min(range.upperBound, max(range.lowerBound, raw)) }   // fără zonă moartă la limite
        return .changed(NumericDragMath.normalize(NumericDragMath.round(raw, fmt: fmt, fine: fine), range: range, wrap: wrap))
    }
}

struct NumericGestureHooks {
    var begin: (String) -> Void = { _ in }
    var end: () -> Void = {}
    var cancel: () -> Void = {}
    var photo: () -> Int64? = { nil }   // fotografia editată acum: o valoare tastată pe o fotografie nu se aplică pe alta
}
private struct NumericGestureKey: EnvironmentKey { static let defaultValue = NumericGestureHooks() }
extension EnvironmentValues { var numericGesture: NumericGestureHooks { get { self[NumericGestureKey.self] } set { self[NumericGestureKey.self] = newValue } } }

private struct ResizeCursorArea: NSViewRepresentable {
    final class V: NSView { override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }; override func hitTest(_ p: NSPoint) -> NSView? { nil } }
    func makeNSView(context: Context) -> V { V() }
    func updateNSView(_ v: V, context: Context) { v.window?.invalidateCursorRects(for: v) }
}

/// Suprafața de tragere peste valoarea numerică (activă doar când valoarea NU se editează): trage = reglare, clic = `onClick` (editare prin tastare), Escape = anulare.
struct NumericDragSurface: View {
    let label: String; let value: () -> Double; let range: ClosedRange<Double>; let fmt: String; var wrap = false
    let apply: (Double) -> Void; let onClick: () -> Void
    @Environment(\.numericGesture) private var hooks
    @State private var session: NumericDragSession?; @State private var monitor: Any?
    var body: some View {
        Color.clear.contentShape(Rectangle()).background(ResizeCursorArea())
            .help(L("Trage stânga/dreapta pentru a regla (Option = fin) · click: scrii un număr exact · Enter confirmă · Esc anulează"))
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { g in
                if session == nil { session = NumericDragSession(value: value(), pressX: Double(g.startLocation.x), range: range, fmt: fmt, wrap: wrap) }
                switch session?.move(x: Double(g.location.x), fine: NSEvent.modifierFlags.contains(.option)) ?? .none {
                case .began: hooks.begin(label); installMonitor()
                case .changed(let v): if v != value() { apply(v) }
                case .none: break
                }
            }.onEnded { _ in
                defer { session = nil; removeMonitor() }
                guard let s = session, !s.cancelled else { return }
                if s.active { hooks.end() } else { onClick() }
            })
            .accessibilityHidden(true)
    }
    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.keyCode == 53, var s = session, s.active else { return e }   // Escape, doar cât ține tragerea
            apply(s.startValue); hooks.cancel(); s.cancelled = true; session = s; removeMonitor(); return nil
        }
    }
    private func removeMonitor() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }
}

/// Controlul de tastatură al unui slider: o vizualizare AppKit focalizabilă (nu interceptează tastele global; primește săgețile DOAR cât are focusul). Mouse-ul trece prin ea (hitTest nil); focusul se cere explicit la apăsarea pe slider.
struct SliderKeyCatcher: NSViewRepresentable {
    var onKey: (Int, Bool) -> Void          // direcția (−1/+1), Option apăsat
    var onFocus: (Bool) -> Void
    var onReady: (NSView) -> Void
    final class V: NSView {
        var onKey: ((Int, Bool) -> Void)?; var onFocus: ((Bool) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { false }   // nu primește focus la pornire/Tab: doar la apăsarea pe slider (săgețile nu modifică nimic din greșeală)
        override func hitTest(_ p: NSPoint) -> NSView? { nil }
        override func becomeFirstResponder() -> Bool { onFocus?(true); return true }
        override func resignFirstResponder() -> Bool { onFocus?(false); return true }
        override func keyDown(with e: NSEvent) {
            switch e.keyCode { case 123: onKey?(-1, e.modifierFlags.contains(.option)); case 124: onKey?(1, e.modifierFlags.contains(.option)); default: super.keyDown(with: e) }
        }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.onKey = onKey; v.onFocus = { f in DispatchQueue.main.async { onFocus(f) } }; DispatchQueue.main.async { onReady(v) }; return v }
    func updateNSView(_ v: V, context: Context) { v.onKey = onKey; v.onFocus = { f in DispatchQueue.main.async { onFocus(f) } } }
}
