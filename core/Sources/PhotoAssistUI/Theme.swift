import SwiftUI
import PhotoCore

/// Tokeni de culoare eșantionați din conceptul APROBAT (photographer-workspace-v1): suprafețe grafit-albăstrui, accent argintiu-albastru, stări semantice.
/// Zona din jurul fotografiei rămâne aproape neutră; fotografia nu primește efecte.
public enum Theme {
    /// Mărimea textului și a controalelor (preferință persistentă simplă: Normal / Mărit / Mare). Fontul și dimensiunile fixe ale controalelor scalează ÎMPREUNĂ; nu se micșorează nimic compensatoriu.
    public static let scaleKey = "gdcpa.textScale"
    public static let scaleOptions: [(level: Int, factor: CGFloat, label: String)] = [(0, 1.0, "Normal"), (1, 1.18, L("Mărit")), (2, 1.36, L("Mare"))]
    public static func factor(level: Int) -> CGFloat { scaleOptions.first { $0.level == level }?.factor ?? 1 }
    public static var level: Int { get { UserDefaults.standard.integer(forKey: scaleKey) } set { UserDefaults.standard.set(newValue, forKey: scaleKey); scale = factor(level: newValue) } }
    public private(set) static var scale: CGFloat = factor(level: UserDefaults.standard.integer(forKey: scaleKey))
    public static func setLevelForTesting(_ l: Int) { scale = factor(level: l) }
    static func f(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font { .system(size: size * scale, weight: weight, design: design) }
    static func px(_ v: CGFloat) -> CGFloat { v * scale }
    static func c(_ hex: UInt32) -> Color { Color(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
    // Tema NEUTRĂ (2026-10-23): griuri pure, suprafețe distincte discret; fără dominantă cromatică. Canvasul fotografiei rămâne gri neutru (fără filtre peste imagine).
    static let toolbar = c(0x131313), app = c(0x181818), panel = c(0x1f1f1f), panel2 = c(0x282828), line = c(0x363636), canvas = c(0x141414)
    static let text = c(0xeeeeee), muted = c(0xb0b0b0), faint = c(0x959595)
    static let accent = c(0xd9a06a), accentHi = c(0xe6b98d), accentInk = c(0x1c1409), selected = c(0x3a3a3a)
    static let keep = c(0x64c555), reject = c(0xe5675c), check = c(0xe3b24b), auto = c(0xbdb2a4)
    static func color(_ d: Decision) -> Color { switch d { case .keep: return keep; case .reject: return reject; case .check: return check } }
    static func label(_ d: Decision) -> String { switch d { case .keep: return L("Păstrată"); case .reject: return L("Respinsă"); case .check: return L("De verificat") } }
}

struct Badge: View {
    let text: String; let color: Color; var dashed = false
    var body: some View {
        Text(text).font(Theme.f(11, weight: .semibold)).foregroundColor(color).padding(.horizontal, 8).padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : [])))
    }
}
struct AutoTag: View { var text = L("sugestie"); var body: some View { Badge(text: text, color: Theme.auto, dashed: true) } }

/// Resetarea unei SECȚIUNI (acțiune vizibilă, cu tooltip, doar când secțiunea diferă de neutru). Separată de resetarea unui parametru (rândul lui) și de „Resetează tot” (bara de jos).
struct SectionReset { let help: String; let isNeutral: Bool; let action: () -> Void }
struct Box<Content: View>: View {
    let title: String; var auto = false; var tag: String? = nil; var panel: String? = nil; var summary: String? = nil; var module: Binding<Bool>? = nil; var reset: SectionReset? = nil; @ViewBuilder var content: Content
    var body: some View {
        if let id = panel { CollapsibleBox(id: id, title: title, summary: summary, module: module, reset: reset, auto: auto) { content } } else { plain }
    }
    var plain: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) { Text(title).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted).lineLimit(2); if let t = tag { AutoTag(text: t) }; Spacer(minLength: 4)
                if let r = reset { Button { r.action() } label: { Image(systemName: "arrow.counterclockwise").font(Theme.f(11, weight: .semibold)) }.buttonStyle(.plain).foregroundColor(r.isNeutral ? Theme.faint : Theme.accent).disabled(r.isNeutral).help(r.help).accessibilityLabel(r.help) } }
            content
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(auto ? Theme.auto.opacity(0.06) : Theme.panel2))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(auto ? Color(red: 0.27, green: 0.33, blue: 0.42) : Theme.line, style: StrokeStyle(lineWidth: 1, dash: auto ? [4, 3] : [])))
    }
}
struct KV: View { let k: String; let v: String; var body: some View { HStack { Text(k).foregroundColor(Theme.muted); Spacer(); Text(v).foregroundColor(Theme.text) }.font(Theme.f(12)) } }

public enum AppStep: Int, CaseIterable { case imp = 0, selection, style, review, export
    var title: String { [L("Bibliotecă"), L("Selecție"), L("Editare"), L("Revizuire"), L("Export")][rawValue] }
}
struct StepBar: View {
    let current: AppStep; var canOpen: (AppStep) -> Bool = { _ in false }; var onSelect: (AppStep) -> Void = { _ in }
    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppStep.allCases, id: \.rawValue) { s in
                Button { if canOpen(s) { onSelect(s) } } label: {
                    VStack(spacing: 5) {
                        HStack(spacing: 5) {
                            if s.rawValue < current.rawValue { Image(systemName: "checkmark").font(Theme.f(9, weight: .bold)).foregroundColor(Theme.keep) }
                            Text(s.title).font(Theme.f(13, weight: s == current ? .semibold : .regular)).foregroundColor(s == current ? Theme.text : Theme.muted)
                        }
                        Rectangle().fill(s == current ? Theme.accent : Color.clear).frame(height: 2)
                    }.fixedSize().padding(.horizontal, 14).padding(.top, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).opacity(canOpen(s) || s == current ? 1 : 0.45).accessibilityAddTraits(s == current ? .isSelected : [])
                .help(canOpen(s) ? LF("Mergi la «%@» (nimic nu se pierde: deciziile, reglajele și măștile rămân)", s.title) : L("Indisponibil acum (ex. nu există încă fotografii sau o coadă de editare)"))
            }
        }
    }
}
/// Suprafață „satinată” discretă: gradient foarte fin + linie de lumină sus + margine; fără efecte pe fotografii.
struct Satin: ViewModifier {
    var radius: CGFloat = 8; var fill: Color = Theme.panel2; var stroke: Color = Theme.line; var hover = false; var tint: Color? = nil
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: radius).fill(LinearGradient(colors: [fill, Theme.panel], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: radius).fill((tint ?? Color.clear).opacity(0.22)))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(stroke.opacity(hover ? 1 : 0.85), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.07), Color.clear], startPoint: .top, endPoint: .center), lineWidth: 1).padding(1))
        )
    }
}
extension View { func satin(_ radius: CGFloat = 8, fill: Color = Theme.panel2, stroke: Color = Theme.line, hover: Bool = false, tint: Color? = nil) -> some View { modifier(Satin(radius: radius, fill: fill, stroke: stroke, hover: hover, tint: tint)) } }

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.f(13, weight: .semibold)).foregroundColor(Theme.accentInk).padding(.horizontal, 16).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [Theme.accentHi, Theme.accentHi.opacity(0.86)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
    }
}
struct SoftButtonStyle: ButtonStyle {
    var tint: Color? = nil; var active = false
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.f(13, weight: .medium)).foregroundColor(Theme.text).padding(.horizontal, 12).padding(.vertical, 6)
            .satin(8, fill: hover ? Theme.c(0x262d37) : Theme.panel2, stroke: active ? (tint ?? Theme.accent) : Theme.line, hover: hover, tint: active ? (tint ?? Theme.selected) : nil)
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .onHover { hover = $0 }
    }
}

/// Selector segmentat propriu (aceeași familie): stare activă clară, hover, accesibil.
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]; @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (v, label) = options[i]
                Button { selection = v } label: {
                    Text(label).lineLimit(1).fixedSize().font(Theme.f(13, weight: selection == v ? .semibold : .regular)).foregroundColor(selection == v ? Theme.text : Theme.muted).padding(.horizontal, 14).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(selection == v ? Theme.selected : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selection == v ? Color.white.opacity(0.10) : Color.clear))
                }.buttonStyle(.plain).accessibilityAddTraits(selection == v ? .isSelected : [])
            }
        }.padding(2).background(RoundedRectangle(cornerRadius: 9).fill(Color(red: 0.05, green: 0.07, blue: 0.10))).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
    }
}
