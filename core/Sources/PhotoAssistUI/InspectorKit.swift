import SwiftUI
import PhotoCore
import PhotoResolve

/// Nivel de experiență = DOAR o vedere a aceleiași sesiuni: filtrează ce panouri se afișează. Nu schimbă, nu resetează și nu dezactivează niciun reglaj; un panou ascuns își păstrează valorile și efectul. Panourile neînregistrate sunt «avansate».
public enum ExperienceLevel: String, CaseIterable, Identifiable {
    case beginner, intermediate, advanced
    public var id: String { rawValue }
    public var label: String { switch self { case .beginner: return L("Începător"); case .intermediate: return L("Intermediar"); case .advanced: return L("Avansat") } }
    public var rank: Int { switch self { case .beginner: return 0; case .intermediate: return 1; case .advanced: return 2 } }
    static let panelLevel: [String: ExperienceLevel] = {
        var m: [String: ExperienceLevel] = [:]
        for k in ["exposure", "light", "colour", "geometry", "presets", "profile"] { m[k] = .beginner }
        for k in ["rawinfo", "detail", "retouch", "tonalbalance", "color", "skin", "look", "film", "grain", "locals", "loupe", "analysis", "chart", "huevectors", "cinema", "highlights"] { m[k] = .intermediate }
        return m
    }()
    public static func level(ofPanel id: String) -> ExperienceLevel { panelLevel[id] ?? .advanced }
}

/// Filele inspectorului (organizare vizuală v4): fiecare panou aparține unei file; nu se elimină nimic, doar se grupează. Panourile neînregistrate merg în «Mai mult».
public enum InspectorTab: String, CaseIterable, Identifiable {
    case base, colour, effects, more
    public var id: String { rawValue }
    public var label: String { switch self { case .base: return L("Bază"); case .colour: return L("Culoare"); case .effects: return L("Efecte"); case .more: return L("Mai mult") } }
    static let panelTab: [String: InspectorTab] = {
        var m: [String: InspectorTab] = [:]
        for k in ["family", "rawinfo", "colour", "exposure", "light", "geometry", "chart", "presets"] { m[k] = .base }
        for k in ["wheels", "tonalbalance", "printer", "channelmix", "huevectors", "color", "skin", "look", "highlights"] { m[k] = .colour }
        for k in ["detail", "retouch", "optics", "diffusion", "film", "film3", "cinema", "grain", "locals"] { m[k] = .effects }
        return m
    }()
    public static func tab(ofPanel id: String) -> InspectorTab { panelTab[id] ?? .more }
}

/// Starea panourilor inspectorului (pliate/deschise, «un singur panou deschis», lățime): păstrată între fotografii și la redeschidere (UserDefaults). Plierea ascunde doar controalele; nu oprește niciun efect.
public final class PanelState: ObservableObject {
    static let openKey = "gdcpa.panels.open", singleKey = "gdcpa.panels.single", widthKey = "gdcpa.inspector.width"
    @Published public private(set) var open: Set<String>
    @Published public var singleOpen: Bool { didSet { UserDefaults.standard.set(singleOpen, forKey: Self.singleKey); if singleOpen, open.count > 1, let f = open.sorted().first { open = [f]; persist() } } }
    @Published public var width: Double { didSet { UserDefaults.standard.set(width, forKey: Self.widthKey) } }       // puncte (la mărimea normală a textului); păstrat pentru compatibilitate
    /// Lățimea aleasă EXPLICIT de utilizator (trasă); fără ea, lățimea e proporțională cu fereastra (≈ 27%, între 380 și 560 puncte la mărimea normală a textului).
    static let userWidthKey = "gdcpa.inspector.userWidth"
    @Published public var userWidth: Double? { didSet { if let w = userWidth { UserDefaults.standard.set(w, forKey: Self.userWidthKey) } else { UserDefaults.standard.removeObject(forKey: Self.userWidthKey) } } }
    public static let widthRange: ClosedRange<Double> = 320...680
    public func effectiveWidth(windowWidth: CGFloat) -> Double {
        if let u = userWidth { return min(Self.widthRange.upperBound, max(Self.widthRange.lowerBound, u)) }
        let scale = Double(max(0.5, Theme.scale)); return min(620, max(380, Double(windowWidth) * 0.27 / scale))
    }
    static let tabKey = "gdcpa.inspector.tab"
    @Published public var tab: InspectorTab { didSet { UserDefaults.standard.set(tab.rawValue, forKey: Self.tabKey) } }
    public func inTab(_ id: String) -> Bool { InspectorTab.tab(ofPanel: id) == tab }
    static let levelKey = "gdcpa.experience.level"
    @Published public var level: ExperienceLevel { didSet { UserDefaults.standard.set(level.rawValue, forKey: Self.levelKey) } }
    public func shows(_ id: String) -> Bool { ExperienceLevel.level(ofPanel: id).rank <= level.rank }
    public static let defaultOpen: Set<String> = []   // spațiu de lucru nou = toate pliate; preferința salvată a fotografului se păstrează
    public init() {
        let d = UserDefaults.standard
        open = Set((d.array(forKey: Self.openKey) as? [String]) ?? Array(Self.defaultOpen)); singleOpen = d.bool(forKey: Self.singleKey)
        tab = d.string(forKey: Self.tabKey).flatMap(InspectorTab.init(rawValue:)) ?? .base
        level = d.string(forKey: Self.levelKey).flatMap(ExperienceLevel.init(rawValue:)) ?? .advanced   // implicit: nimic nu dispare pentru cine are deja un spațiu de lucru
        let w = d.double(forKey: Self.widthKey); width = w >= 300 && w <= 560 ? w : 340
        let uw = d.double(forKey: Self.userWidthKey); userWidth = uw >= 320 && uw <= 680 ? uw : nil
    }
    private func persist() { UserDefaults.standard.set(Array(open).sorted(), forKey: Self.openKey) }
    public func isOpen(_ id: String) -> Bool { open.contains(id) }
    public func toggle(_ id: String) { if open.contains(id) { open.remove(id) } else if singleOpen { open = [id] } else { open.insert(id) }; persist() }
    /// Deschide panoul unei unelte (în modul «un singur panou», îl înlocuiește pe cel deschis).
    public func reveal(_ id: String) { if open.contains(id) { return }; if singleOpen { open = [id] } else { open.insert(id) }; persist() }
    public func collapseAll() { open = []; persist() }
    public func clampWidth() { width = min(560, max(300, width)) }
}

/// Explicații tehnice lungi: ascunse implicit sub «Detalii» (valorile, unitățile și avertismentele care cer o acțiune rămân vizibile în afara lor).
struct Details<Content: View>: View {
    var title = L("Detalii"); @State private var open = false; @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { open.toggle() } label: { HStack(spacing: 4) { Image(systemName: open ? "chevron.down" : "chevron.right").font(Theme.f(9, weight: .bold)); Text(title).font(Theme.f(11, weight: .semibold)) }.foregroundColor(Theme.faint) }.buttonStyle(.plain).accessibilityLabel("\(title): \(open ? L("deschis") : L("închis"))")
            if open { content }
        }
    }
}

/// Secțiune pliabilă a inspectorului: săgeată, nume (+ rezumat), activare/dezactivare (doar module de procesare care o permit), resetare (acțiune separată). Activarea păstrează valorile.
struct CollapsibleBox<Content: View>: View {
    @EnvironmentObject var panels: PanelState
    let id: String; let title: String; var summary: String? = nil; var module: Binding<Bool>? = nil; var reset: SectionReset? = nil; var auto = false; @ViewBuilder var content: Content
    var body: some View {
        let isOpen = panels.isOpen(id); let enabled = module?.wrappedValue ?? true
        if panels.shows(id) && panels.inTab(id) { VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { withAnimation(.easeInOut(duration: 0.12)) { panels.toggle(id) } } label: {
                    HStack(spacing: 6) { Image(systemName: "chevron.right").font(Theme.f(10, weight: .bold)).rotationEffect(.degrees(isOpen ? 90 : 0)).frame(width: Theme.px(12))
                        Text(title).font(Theme.f(12, weight: .semibold)).foregroundColor(enabled ? Theme.text : Theme.faint).lineLimit(1)
                        if let s = summary, !isOpen || !enabled { Text(s).font(Theme.f(11)).foregroundColor(Theme.muted).lineLimit(1) }
                        Spacer(minLength: 4) }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(title): \(isOpen ? L("deschis") : L("închis"))").help(isOpen ? L("Închide panoul (efectul rămâne activ)") : L("Deschide panoul"))
                if let m = module { Button { m.wrappedValue.toggle() } label: { MiniSwitch(on: enabled) }.buttonStyle(.plain)
                    .help(enabled ? L("Modul ACTIV. Click: îl scoate temporar din procesare (valorile se păstrează)") : L("Modul DEZACTIVAT (valorile sunt păstrate). Click: îl reactivează cu aceleași reglaje")).accessibilityLabel("\(title): \(enabled ? L("activ") : L("dezactivat"))").accessibilityAddTraits(.isButton) }
                if let r = reset { Button { r.action() } label: { Image(systemName: "arrow.counterclockwise").font(Theme.f(11, weight: .semibold)) }.buttonStyle(.plain).foregroundColor(r.isNeutral ? Theme.faint : Theme.accent).disabled(r.isNeutral).help(r.help).accessibilityLabel(r.help) }
            }
            if isOpen { VStack(alignment: .leading, spacing: 8) { content }.opacity(enabled ? 1 : 0.55) }
        }
        .padding(.vertical, 10).padding(.horizontal, auto ? 8 : 2).frame(maxWidth: .infinity, alignment: .leading)
        .background(auto ? AnyView(RoundedRectangle(cornerRadius: 8).fill(Theme.auto.opacity(0.06)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.auto.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))) : AnyView(Color.clear))
        .overlay(alignment: .bottom) { if !auto { Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 1) } } }
    }
}

/// Comutator de activare al unui modul (distinct de deschiderea panoului): capsulă mică, verde când modulul rămâne în procesare.
struct MiniSwitch: View {
    var on: Bool
    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? Theme.keep.opacity(0.85) : Theme.c(0x474747)).frame(width: Theme.px(30), height: Theme.px(16))
            Circle().fill(Color.white.opacity(on ? 0.95 : 0.7)).frame(width: Theme.px(12), height: Theme.px(12)).padding(.horizontal, Theme.px(2))
        }.animation(.easeOut(duration: 0.12), value: on)
    }
}

/// Antetul inspectorului: acțiuni de organizare (închide toate, «un singur panou deschis»); nu schimbă nicio valoare.
struct InspectorHeader: View {
    @ObservedObject var ed: EditingModel; @ObservedObject var panels: PanelState
    var body: some View {
        HStack(spacing: 8) {
            if !ed.currentIsRendered, !ed.adjustments.disabledModules.isEmpty { Badge(text: (ed.adjustments.disabledModules.count == 1 ? LF("%@ dezactivat", ed.adjustments.disabledModules.count) : LF("%@ dezactivate", ed.adjustments.disabledModules.count)), color: Theme.check, dashed: true).help(L("Module scoase temporar din procesare (valorile sunt păstrate)")) }
            Spacer()
            Menu { Picker(L("Nivel"), selection: $panels.level) { ForEach(ExperienceLevel.allCases) { Text($0.label).tag($0) } }.pickerStyle(.inline)
                Text(L("Doar vizualizare: reglajele nu se schimbă când schimbi nivelul.")) } label: { Text(panels.level.label).font(Theme.f(11, weight: .semibold)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("Nivelul de experiență alege ce panouri se afișează. Reglajele din panourile ascunse rămân aplicate."))
            AdjustmentSyncMenu(ed: ed)
            Button { panels.collapseAll() } label: { Image(systemName: "chevron.up.chevron.down") }.buttonStyle(.plain).foregroundColor(Theme.accent).help(L("Închide toate panourile (efectele rămân active)"))
            Menu { Toggle(L("Un singur panou deschis"), isOn: $panels.singleOpen); Button(L("Lățime implicită (proporțională cu fereastra)")) { panels.userWidth = nil } } label: { Image(systemName: "slider.horizontal.3") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("Organizare inspector"))
        }.padding(.horizontal, 2)
        if panels.level != .advanced { Text(LF("Nivel %@: panourile mai avansate sunt ascunse; reglajele lor active rămân aplicate și se exportă.", panels.level.label)).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
    }
}

/// Bara de unelte din bara existentă de deasupra fotografiei (nu o a doua bară): deplasare/zoom, decupare și geometrie, măști/corecții locale, analiză. Fiecare are tooltip, nume accesibil și stare selectată vizibilă;
/// uneltele înrudite au meniu compact. Selectarea unei unelte arată opțiunile ei în inspector și NU șterge/dezactivează ajustările existente.
struct ToolStrip: View {
    @ObservedObject var ed: EditingModel
    func chip(_ icon: String, _ tool: EditingModel.EditTool, _ help: String) -> some View {
        let on = ed.activeTool == tool
        return Image(systemName: icon).font(Theme.f(13, weight: .medium)).foregroundColor(on ? Theme.accentInk : Theme.text).frame(width: Theme.px(30), height: Theme.px(26))
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.accentHi : Theme.panel2)).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(on ? Color.white.opacity(0.4) : Theme.line))
            .help(help).accessibilityLabel(help).accessibilityAddTraits(on ? .isSelected : [])
    }
    var body: some View {
        let ok = ed.current != nil && ed.engine == .own
        HStack(spacing: 4) {
            Button { ed.guidesHidden.toggle() } label: { Image(systemName: ed.guidesHidden ? "eye.slash" : "eye").font(Theme.f(13, weight: .medium)).foregroundColor(ed.guidesHidden ? Theme.accentInk : Theme.text).frame(width: Theme.px(30), height: Theme.px(26)).background(RoundedRectangle(cornerRadius: 7).fill(ed.guidesHidden ? Theme.accentHi : Theme.panel2)).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line)) }.buttonStyle(.plain).help(ed.guidesHidden ? L("Ghidajele ASCUNSE (decupare, îndreptare, măști, grilă): click pentru a le arăta; rezultatul nu se schimbă") : L("Ascunde toate ghidajele (decupare, îndreptare, măști, grilă); rezultatul nu se schimbă")).accessibilityLabel(L("Ascunde ghidajele")).disabled(ed.current == nil)
            Button { ed.selectTool(.view) } label: { chip("hand.raised", .view, L("Deplasare și zoom (rotița peste fotografie; Space + tragere sau butonul din mijloc)")) }.buttonStyle(.plain)
            Menu {
                Button(L("Decupare")) { ed.selectTool(.geometry); ed.geometryMode = .crop }
                Button(L("Îndreaptă (2 puncte)")) { ed.selectTool(.geometry); ed.straightenPoints = []; ed.geometryMode = .straighten }
                Button(L("Rotire, perspectivă, scară")) { ed.selectTool(.geometry); ed.panels.reveal("geometry") }
                Divider(); Toggle(L("Grilă de compoziție"), isOn: $ed.showGrid)
            } label: { chip("crop", .geometry, L("Decupare și geometrie")) } primaryAction: { ed.selectTool(.geometry) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(!ok)
            Menu {
                ForEach(ZoneKind.allCases, id: \.rawValue) { k in Button(LF("Corecție locală: %@", k.label)) { ed.selectTool(.masks); ed.addLocal(k) } }
                Divider(); Button(ed.guidesHidden ? L("Arată ghidajele măștii") : L("Ascunde ghidajele măștii")) { ed.guidesHidden.toggle() }
            } label: { chip("scribble.variable", .masks, L("Măști și corecții locale")) } primaryAction: { ed.selectTool(.masks) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(!ok || ed.currentIsRendered).help(ed.currentIsRendered ? L("Indisponibil pentru imagini redate (nu RAW)") : "")
            Button { ed.selectTool(.geometry); ed.straightenPoints = []; ed.geometryMode = .straighten } label: { chip("ruler", .geometry, L("Îndreaptă (2 puncte): trage o linie pe un orizont sau o verticală")) }.buttonStyle(.plain).disabled(!ok)
            Button { ed.selectTool(.chart); ed.guidesHidden = false } label: { chip("checkerboard.rectangle", .chart, L("Chart de culoare: arată grila (ghidaj; corecția se aplică separat, din panoul Chart)")) }.buttonStyle(.plain).disabled(!ok || ed.currentIsRendered)
            Button { ed.loupeOn.toggle(); if ed.loupeOn { ed.panels.reveal("loupe") } } label: { Image(systemName: "magnifyingglass").font(Theme.f(13, weight: .medium)).foregroundColor(ed.loupeOn ? Theme.accentInk : Theme.text).frame(width: Theme.px(30), height: Theme.px(26)).background(RoundedRectangle(cornerRadius: 7).fill(ed.loupeOn ? Theme.accentHi : Theme.panel2)).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ed.loupeOn ? Color.white.opacity(0.4) : Theme.line)).help(L("Lupă de inspecție (nu se exportă)")).accessibilityLabel(L("Lupă de inspecție")).accessibilityAddTraits(ed.loupeOn ? .isSelected : []) }.buttonStyle(.plain).disabled(ed.current == nil)
            Button { ed.selectTool(.retouch) } label: { chip("bandage", .retouch, L("Retuș: clonă și vindecare (pune puncte pe imagine)")) }.buttonStyle(.plain).disabled(!ok || ed.currentIsRendered)
            Menu {
                ForEach(AnalysisMode.allCases, id: \.rawValue) { m in Button { ed.selectTool(m == .off ? .view : .analysis); ed.analysisMode = m } label: { Text(m.label + (ed.analysisMode == m ? "  ✓" : "")) } }
                Divider(); Toggle(L("Histogramă"), isOn: $ed.showHistogram)
            } label: { chip("chart.bar.xaxis", .analysis, L("Instrumente de analiză (nu se exportă)")) } primaryAction: { ed.selectTool(.analysis) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(!ok)
        }
    }
}
