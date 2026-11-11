import SwiftUI
import AppKit
import PhotoCore

/// Roată de culoare fină pentru o zonă (umbre / tonuri medii / lumini). Controlează EXACT aceleași patru valori ca sliderele R/G/B/Master din «Roți pe zone»
/// (nimic nou în model): poziția butonului = deplasarea cromatică (nuanță, cantitate) a decalajelor R/G/B, cu componenta de luminanță păstrată; slider-ul de dedesubt = Master.
/// Mapare: u = r − s, v = (g − b)/√3, cu s = (r+g+b)/3; nuanța θ = atan2(v, u) (roșu 0°, verde 120°, albastru 240°), cantitatea a = √(u²+v²). Raza roții = `maxAmount`.
enum WheelMath {
    static let k3 = 3.0.squareRoot()
    static func decompose(_ r: Double, _ g: Double, _ b: Double) -> (s: Double, u: Double, v: Double) { let s = (r + g + b) / 3; return (s, r - s, (g - b) / k3) }
    static func compose(s: Double, u: Double, v: Double) -> (r: Double, g: Double, b: Double) { (s + u, s - u / 2 + (k3 / 2) * v, s - u / 2 - (k3 / 2) * v) }
}

struct ColorWheel: View {
    enum Part { case ring, fields }
    let title: String
    @Binding var r: Double; @Binding var g: Double; @Binding var b: Double; @Binding var master: Double
    var maxAmount = 0.25
    var part: Part = .ring
    @Environment(\.resetHook) private var resetHook; @Environment(\.numericGesture) private var gesture
    @State private var hueText = ""; @State private var amountText = ""; @State private var lumText = ""
    @State private var editPhoto: Int64?; @State private var hueEdit = false; @State private var amountEdit = false; @State private var lumEdit = false
    @FocusState private var hueFocus: Bool; @FocusState private var amountFocus: Bool; @FocusState private var lumFocus: Bool
    private var s: Double { (r + g + b) / 3 }
    private var u: Double { r - s }
    private var v: Double { (g - b) / 3.0.squareRoot() }
    private var amount: Double { (u * u + v * v).squareRoot() }
    private var hue: Double { let h = atan2(v, u) * 180 / .pi; return h < 0 ? h + 360 : h }
    private var atNeutral: Bool { abs(r) < 1e-9 && abs(g) < 1e-9 && abs(b) < 1e-9 && abs(master) < 1e-9 }
    private func set(u nu: Double, v nv: Double) {
        let a = (nu * nu + nv * nv).squareRoot(); let k = a > maxAmount ? maxAmount / a : 1; let uu = nu * k, vv = nv * k
        let n = WheelMath.compose(s: s, u: uu, v: vv); r = n.r; g = n.g; b = n.b
    }
    private func setPolar(hue h: Double, amount a: Double) { let t = h * .pi / 180, aa = min(maxAmount, max(0, a)); set(u: aa * cos(t), v: aa * sin(t)) }
    private func resetAll() { guard !atNeutral else { return }; resetHook(title); r = 0; g = 0; b = 0; master = 0 }
    private func syncTexts() { hueText = String(format: "%.0f", hue); amountText = String(format: "%.3f", amount); lumText = String(format: "%+.2f", master) }   // și cu focus: o schimbare externă (Anulează/resetare) nu lasă text vechi de reaplicat

    var body: some View {
        Group { if part == .ring { ringColumn } else { fieldsRow } }
            .onAppear { syncTexts() }.onChange(of: r) { _ in syncTexts() }.onChange(of: g) { _ in syncTexts() }.onChange(of: b) { _ in syncTexts() }.onChange(of: master) { _ in syncTexts() }
    }
    /// Controlul principal al unei zone: titlu + resetare, roata, luminanța (slider). Valorile numerice sunt în «Valori precise».
    private var ringColumn: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(title).font(Theme.f(12.5, weight: .semibold)).foregroundColor(Theme.text).lineLimit(1)
                Spacer(minLength: 2)
                resetButton
            }
            ring.aspectRatio(1, contentMode: .fit)
            Slider(value: $master, in: -0.5...0.5).controlSize(.small).tint(Theme.accent).help(LF("Luminanța (Master) a zonei «%@»: %@", title, String(format: "%+.2f", master))).accessibilityLabel(LF("Luminanță %@", title))
        }
    }
    private var resetButton: some View {
        Button { resetAll() } label: { Image(systemName: "arrow.counterclockwise").font(Theme.f(11, weight: .semibold)).frame(width: Theme.px(18), height: Theme.px(18)) }.buttonStyle(.plain)
            .foregroundColor(atNeutral ? Theme.faint.opacity(0.45) : Theme.accent).disabled(atNeutral).help(LF("Resetează «%@» (dominantă și luminanță)", title)).accessibilityLabel(LF("Resetează %@", title))
    }
    private var fieldsRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(title).font(Theme.f(12)).foregroundColor(Theme.text).frame(width: Theme.px(86), alignment: .leading).lineLimit(1)
            labelled(L("Nuanță"), text: $hueText, focus: $hueFocus, edit: $hueEdit, drag: DragSpec(label: LF("%@ · nuanță", title), value: { hue }, range: 0...360, fmt: "%.0f", wrap: true, apply: { setPolar(hue: $0, amount: amount) }), suffix: "°") { if let h = Double($0.replacingOccurrences(of: ",", with: ".")) { setPolar(hue: ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360), amount: amount) } }
            labelled(L("Cantitate"), text: $amountText, focus: $amountFocus, edit: $amountEdit, drag: DragSpec(label: LF("%@ · cantitate", title), value: { amount }, range: 0...maxAmount, fmt: "%.3f", wrap: false, apply: { setPolar(hue: amount < 1e-9 ? 0 : hue, amount: $0) }), suffix: "") { if let a = Double($0.replacingOccurrences(of: ",", with: ".")) { setPolar(hue: amount < 1e-9 ? 0 : hue, amount: a) } }
            labelled(L("Luminanță"), text: $lumText, focus: $lumFocus, edit: $lumEdit, drag: DragSpec(label: LF("%@ · luminanță", title), value: { master }, range: -0.5...0.5, fmt: "%+.2f", wrap: false, apply: { master = $0 }), suffix: "") { if let m = Double($0.replacingOccurrences(of: ",", with: ".")) { master = min(0.5, max(-0.5, m)) } }
            resetButton
        }
    }
    private var ring: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height); let R = d / 2 - 2; let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2); let inner = R * 0.935
            ZStack {
                Canvas { ctx, _ in
                    let seg = 240
                    for k in 0..<seg {
                        let t0: Double = Double(k) / Double(seg) * 2 * Double.pi
                        let t1: Double = (Double(k) + 1.6) / Double(seg) * 2 * Double.pi
                        var p = Path()
                        p.addArc(center: c, radius: R, startAngle: Angle.radians(-t0), endAngle: Angle.radians(-t1), clockwise: true)
                        p.addArc(center: c, radius: inner, startAngle: Angle.radians(-t1), endAngle: Angle.radians(-t0), clockwise: false)
                        p.closeSubpath()
                        ctx.fill(p, with: .color(Color(hue: Double(k) / Double(seg), saturation: 0.55, brightness: 0.74)))
                    }
                    let disc = Path(ellipseIn: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
                    ctx.fill(disc, with: .radialGradient(Gradient(colors: [Theme.c(0x242424), Theme.c(0x181818)]), center: c, startRadius: 0, endRadius: inner))
                    let half = Path(ellipseIn: CGRect(x: c.x - inner * 0.5, y: c.y - inner * 0.5, width: inner, height: inner))
                    ctx.stroke(half, with: .color(Color.white.opacity(0.05)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    var cross = Path(); cross.move(to: CGPoint(x: c.x - inner, y: c.y)); cross.addLine(to: CGPoint(x: c.x + inner, y: c.y)); cross.move(to: CGPoint(x: c.x, y: c.y - inner)); cross.addLine(to: CGPoint(x: c.x, y: c.y + inner))
                    ctx.stroke(cross, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)), with: .color(Color.white.opacity(0.3)))   // reper neutru
                }
                let pr = inner * min(1, amount / maxAmount); let t = hue * .pi / 180
                let puck = amount < 1e-9 ? c : CGPoint(x: c.x + pr * cos(t), y: c.y - pr * sin(t))
                ZStack { Circle().fill(Color.black.opacity(0.35)).frame(width: Theme.px(13), height: Theme.px(13)); Circle().stroke(Color.white.opacity(atNeutral ? 0.5 : 0.95), lineWidth: 1.3).frame(width: Theme.px(11), height: Theme.px(11))
                    Circle().fill(Color.white.opacity(atNeutral ? 0.5 : 0.95)).frame(width: 2.5, height: 2.5) }.position(puck)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d0 in
                let dx = Double(d0.location.x - c.x), dy = Double(c.y - d0.location.y); let k = maxAmount / (Double(inner))
                set(u: dx * k, v: dy * k) })
            .onTapGesture(count: 2) { resetAll() }
        }
        .help(L("Trage pentru a alege dominanta (nuanță și cantitate). Dublu-click: resetează roata (R, G, B și Master)"))
        .accessibilityElement(children: .ignore).accessibilityLabel(LF("Roată %@", title)).accessibilityValue(String(format: L("nuanță %.0f grade, cantitate %.3f"), hue, amount))
    }
    struct DragSpec { let label: String; let value: () -> Double; let range: ClosedRange<Double>; let fmt: String; let wrap: Bool; let apply: (Double) -> Void }
    private func labelled(_ name: String, text: Binding<String>, focus: FocusState<Bool>.Binding, edit: Binding<Bool>, drag: DragSpec, suffix: String, commit: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(Theme.f(10.5)).foregroundColor(Theme.faint).lineLimit(1)
            HStack(spacing: 2) { plainField(text: text, focus: focus, edit: edit, drag: drag, commit: commit); if !suffix.isEmpty { Text(suffix).font(Theme.f(10.5)).foregroundColor(Theme.faint) } }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    /// Valoare tastată în roată: o singură operație de anulare, doar dacă s-a schimbat ceva.
    private func typed(_ d: DragSpec, _ t: String, _ commit: (String) -> Void) { if let p = editPhoto, p != gesture.photo() { return }; gesture.begin(d.label); commit(t); gesture.end() }
    private func plainField(text: Binding<String>, focus: FocusState<Bool>.Binding, edit: Binding<Bool>, drag: DragSpec, commit: @escaping (String) -> Void) -> some View {
        TextField("", text: text).textFieldStyle(.plain).font(Theme.f(11.5, design: .monospaced)).multilineTextAlignment(.trailing).focused(focus).lineLimit(1)
            .allowsHitTesting(edit.wrappedValue)
            .overlay { if !edit.wrappedValue { NumericDragSurface(label: drag.label, value: drag.value, range: drag.range, fmt: drag.fmt, wrap: drag.wrap, apply: drag.apply, onClick: { editPhoto = gesture.photo(); edit.wrappedValue = true; DispatchQueue.main.async { focus.wrappedValue = true; DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) } } }) } }
            .onSubmit { typed(drag, text.wrappedValue, commit); syncTexts(); focus.wrappedValue = false; edit.wrappedValue = false }.onChange(of: focus.wrappedValue) { f in if !f { typed(drag, text.wrappedValue, commit); syncTexts(); edit.wrappedValue = false } }
            .onExitCommand { syncTexts(); focus.wrappedValue = false; edit.wrappedValue = false }
            .padding(.horizontal, 6).padding(.vertical, 3).frame(minWidth: Theme.px(48)).background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.28))).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Cele trei roți ale zonelor (Umbre · Tonuri medii · Lumini), legate de `tools.wheels` ([umbre, mijloc, lumini] × [R, G, B, Master]).
/// Trei coloane doar când fiecare are ≥ ~124 puncte; altfel pe rânduri (roata mai mică, nu comprimată). Valorile precise sunt sub un detaliu pliat.
struct ZoneWheelsRow: View {
    @ObservedObject var ed: EditingModel
    @Environment(\.inspectorWidth) private var inspectorWidth
    private func bind(_ i: Int) -> Binding<Double> { Binding(get: { ed.adjustments.tools.wheels[i] }, set: { ed.adjustments.tools.wheels[i] = $0 }) }
    private let names = [L("Umbre"), L("Tonuri medii"), L("Lumini")]
    private func wheel(_ k: Int, _ part: ColorWheel.Part = .ring) -> ColorWheel { ColorWheel(title: names[k], r: bind(k * 4), g: bind(k * 4 + 1), b: bind(k * 4 + 2), master: bind(k * 4 + 3), part: part) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if inspectorWidth >= Theme.px(124) * 3 + 70 {
                HStack(alignment: .top, spacing: 14) { ForEach(0..<3, id: \.self) { k in wheel(k) } }
            } else {
                VStack(spacing: 12) { ForEach(0..<3, id: \.self) { k in wheel(k).frame(maxWidth: Theme.px(170)) } }
            }
            Details(title: L("Valori precise (nuanță, cantitate, luminanță)")) { VStack(alignment: .leading, spacing: 8) { ForEach(0..<3, id: \.self) { k in wheel(k, .fields) } } }
        }
    }
}
