import SwiftUI
import AppKit
import PhotoCore
import PhotoRaw
import PhotoResolve

/// Cârlig de resetare (mecanismul de anulare): rândul îl cheamă ÎNAINTE de a schimba valoarea; modelul păstrează starea anterioară (⌘Z / „Anulează”).
/// Lățimea inspectorului în puncte (deja scalată cu mărimea textului): rândurile alese aranjarea (pe un rând / pe două) deterministic, fără ViewThatFits (care măsoară ambele variante la fiecare actualizare).
private struct InspectorWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues { var inspectorWidth: CGFloat { get { self[InspectorWidthKey.self] } set { self[InspectorWidthKey.self] = newValue } } }
private struct ResetHookKey: EnvironmentKey { static let defaultValue: (String) -> Void = { _ in } }
extension EnvironmentValues { var resetHook: (String) -> Void { get { self[ResetHookKey.self] } set { self[ResetHookKey.self] = newValue } } }

/// Un parametru: nume (dublu-click = revine la neutrul LUI), valoare editabilă numeric (rezervată, nu se taie), acțiune vizibilă de resetare (tooltip) și slider. Slederul cedează spațiu înaintea valorii. Neutrul vine de la parametru (1 la contrast/saturație, nu 0).
/// Slider fin: pistă subțire (cu repere cromatice opționale) și mâner rotund argintiu; același model de valoare ca `Slider` (reprezentarea de accesibilitate rămâne un slider real).
struct FineSlider: View {
    @Binding var value: Double; let range: ClosedRange<Double>; var track: [Color]? = nil; var onPress: (() -> Void)? = nil
    private let knob: CGFloat = 15
    var body: some View {
        GeometryReader { g in
            let w = max(1, g.size.width - knob); let span = range.upperBound - range.lowerBound; let t = span > 0 ? CGFloat((value - range.lowerBound) / span) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(track.map { AnyShapeStyle(LinearGradient(colors: $0, startPoint: .leading, endPoint: .trailing)) } ?? AnyShapeStyle(Theme.line)).frame(height: 3.5).padding(.horizontal, knob / 2).opacity(track == nil ? 1 : 0.95)
                Circle().fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.72)], startPoint: .top, endPoint: .bottom)).frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 0.8)).shadow(color: .black.opacity(0.4), radius: 1.5, y: 1).offset(x: min(max(t, 0), 1) * w)
            }.frame(height: g.size.height).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in onPress?(); let f = Double(min(max((v.location.x - knob / 2) / w, 0), 1)); value = range.lowerBound + f * span })
        }.frame(height: 20)
            .accessibilityRepresentation { Slider(value: $value, in: range) }
    }
}

struct SliderRow: View {
    let label: String; var help: String? = nil; @Binding var value: Double; let range: ClosedRange<Double>; var neutral: Double = 0; var fmt = "%+.2f"; var tag: String? = nil; var track: [Color]? = nil   // track = reper cromatic de DIRECȚIE (nu simulare exactă a rezultatului)
    @Environment(\.resetHook) private var resetHook; @Environment(\.inspectorWidth) private var inspectorWidth
    @State private var field = NumericFieldModel(fmt: "%+.2f", range: 0...1, value: 0)
    private enum Focus { case text }
    @FocusState private var focus: Focus?
    private var focused: Bool { focus == .text }
    @State private var sliderFocused = false; @State private var keyView: NSView?
    @State private var editing = false; @State private var editPhoto: Int64?; @State private var keyBurst: Task<Void, Never>?
    @Environment(\.numericGesture) private var gesture
    private var text: Binding<String> { Binding(get: { field.text }, set: { field.text = $0 }) }
    private var atNeutral: Bool { abs(value - neutral) < 1e-9 }
    private var neutralText: String { String(format: fmt, neutral) }
    private func reset() { guard !atNeutral else { return }; resetHook(label); value = neutral }
    /// Enter / ieșire din câmp: aplică DOAR un text tastat diferit de cel afișat (un text vechi nu se reaplică după Anulează/resetare).
    private func beginTyping() { editing = true; editPhoto = gesture.photo(); DispatchQueue.main.async { focus = .text; DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) } } }
    private func endTyping() { focus = nil; editing = false }
    /// Tastatura pe slider focalizat: ←/→ cu pasul parametrului, Option = pas fin; o rafală de apăsări = o singură operație de anulare.
    private func keyAdjust(_ dir: Int, fine: Bool) {
        if keyBurst == nil { gesture.begin(label) } else { keyBurst?.cancel() }
        value = NumericDragMath.keyAdjusted(value, direction: dir, range: range, fmt: fmt, fine: fine)
        keyBurst = Task { try? await Task.sleep(nanoseconds: 700_000_000); if !Task.isCancelled { gesture.end(); keyBurst = nil } }
    }
    /// O valoare tastată și confirmată = O singură operație de anulare (același istoric ca tragerea); text neschimbat = fără istoric.
    private func commit() { if let p = editPhoto, p != gesture.photo() { field.finish(value: value); return }   // altă fotografie între timp: nimic nu se aplică pe ea
        if let v = field.pendingValue(current: value) { gesture.begin(label); value = v; gesture.end() }; field.finish(value: value) }
    private var nameView: some View {
        HStack(spacing: 5) {
            Text(label).font(Theme.f(12.5)).lineLimit(2).fixedSize(horizontal: false, vertical: true).contentShape(Rectangle())
                .onTapGesture(count: 2) { reset() }.help((help.map { $0 + "\n" } ?? "") + LF("Dublu-click pe nume: revine la %@ (valoarea neutră)", neutralText))
            if let t = tag { AutoTag(text: t) }
        }
    }
    private var valueField: some View {
        TextField("", text: text).textFieldStyle(.plain).font(Theme.f(12, design: .monospaced)).multilineTextAlignment(.trailing).focused($focus, equals: .text).lineLimit(1)
            .allowsHitTesting(editing).focusable(editing)   // în afara editării, suprafața de tragere primește mouse-ul; cât se editează, selectarea textului funcționează normal
            .foregroundColor(atNeutral ? Theme.faint : Theme.text).frame(minWidth: Theme.px(54), idealWidth: Theme.px(64), maxWidth: Theme.px(80)).padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(focused ? Theme.accent.opacity(0.18) : Color.black.opacity(0.28)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Theme.accent : Theme.line, lineWidth: 1)).layoutPriority(2)
            .overlay { if !editing { NumericDragSurface(label: label, value: { value }, range: range, fmt: fmt, apply: { value = $0 }, onClick: beginTyping) } }
            .onSubmit { commit(); endTyping() }.onChange(of: focus) { f in if f != .text, editing { commit(); editing = false } }
            .onExitCommand { field.finish(value: value); endTyping() }   // Escape în editare: renunță la text
            .help(editing ? L("Scrie un număr exact · Enter confirmă · Esc anulează") : L("Trage stânga/dreapta pentru a regla (Option = fin) · click: scrii un număr exact · Enter confirmă · Esc anulează"))
    }
    private var resetButton: some View {
        Button { reset() } label: { Image(systemName: "arrow.counterclockwise").font(Theme.f(11, weight: .semibold)).frame(width: Theme.px(18), height: Theme.px(18)) }.buttonStyle(.plain)
            .foregroundColor(atNeutral ? Theme.faint.opacity(0.5) : Theme.accent).disabled(atNeutral).help(atNeutral ? LF("Deja la valoarea neutră (%@)", neutralText) : LF("Resetează «%@» la %@", label, neutralText)).accessibilityLabel(LF("Resetează %@", label))
    }
    private var slider: some View {
        FineSlider(value: $value, range: range, track: track, onPress: { if let v = keyView, v.window?.firstResponder !== v { v.window?.makeFirstResponder(v) } }).accessibilityLabel(label)
            .background(SliderKeyCatcher(onKey: { keyAdjust($0, fine: $1) }, onFocus: { sliderFocused = $0 }, onReady: { keyView = $0 }))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.accent, lineWidth: 1.5).padding(-2).opacity(sliderFocused ? 1 : 0).allowsHitTesting(false))
            .help(L("←/→ reglează cu pasul parametrului (Option = fin) când sliderul e focalizat"))
    }
    var body: some View {
        Group {
            if label.count <= 26 && tag == nil && inspectorWidth >= Theme.px(336) + 36 {
                // Aranjare pe un rând (nume · slider · valoare · resetare) când încape (lățimea inspectorului o decide); altfel, cea pe două rânduri — fără micșorarea fonturilor.
                HStack(spacing: 8) { nameView.frame(width: Theme.px(124), alignment: .leading); slider.frame(minWidth: Theme.px(90)); valueField; resetButton }
            } else { stacked }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gdcCommitNumericFields)) { _ in if editing { commit() } }   // înainte de schimbarea fotografiei/etapei: valoarea tastată se confirmă pe fotografia CURENTĂ
        .onAppear { field = NumericFieldModel(fmt: fmt, range: range, value: value) }
        .onChange(of: value) { v in field.fmt = fmt; field.range = range; field.externalChange(to: v) }
    }
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) { nameView; Spacer(minLength: 4); valueField; resetButton }
            slider
        }
    }
}

struct ConnectionBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        Box(title: L("Motor de procesare"), panel: "engine", summary: ed.engine == .own ? (!Edition.full ? L("Redare deschisă → sRGB") : (ed.outputTransform == .gdcDRTNatural ? "GDC DRT Natural" : "DRT p1 (exp.)")) : "Resolve + STYLE") {
            if AppInfo.internalTools { Segmented(options: [(EngineChoice.own, L("Nucleu propriu")), (.resolveStyle, L("Resolve + STYLE (intern)"))], selection: $ed.engine) }
            switch ed.engine {
            case .own: ownState
            case .resolveStyle: resolveState
            }
        }
    }
    @ViewBuilder var ownState: some View { if Edition.full { fullOwnState } else { openOwnState } }
    /// Ediția cu sursă deschisă: o singură transformare de afișare, fără alegere și fără date externe.
    @ViewBuilder var openOwnState: some View {
        HStack(spacing: 6) { Circle().fill(Theme.keep).frame(width: 8, height: 8); Text(L("Redare deschisă → sRGB")).font(Theme.f(12, weight: .semibold)) }
        Details { Text(L("Transformarea de afișare a ediției cu sursă deschisă: compresie de gamă, curbă de ton pe max-RGB cu păstrarea raporturilor, desaturare progresivă în lumini, apoi codificare sRGB. GDC DRT nu face parte din această ediție.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
    }
    @ViewBuilder var fullOwnState: some View {
        let st = GDCDRTData.status
        Segmented(options: [(OutputTransform.gdcDRTNatural, "GDC DRT Natural"), (.p1Experimental, "DRT p1 (exp.)")], selection: $ed.outputTransform)
        switch ed.outputTransform {
        case .gdcDRTNatural:
            switch st {
            case .loaded: HStack(spacing: 6) { Circle().fill(Theme.keep).frame(width: 8, height: 8); Text(L("GDC DRT adaptat · date verificate (SHA-256)")).font(Theme.f(12, weight: .semibold)) }
                Segmented(options: [(0, "Natural"), (1, "Asiatic"), (2, "Cinema Print")], selection: $ed.adjustments.drtProfile)
                if ed.adjustments.drtProfile != 0 { Text(L("Profilul este o alegere de redare a ieșirii (paritate numerică cu referința verificată pe toate 3); aspectul pe fotografii reale îl evaluezi tu. NU există în pluginul Resolve (doar Natural): predarea în Resolve este oprită explicit cât profilul ≠ Natural.")).font(Theme.f(11)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
                Details { Text(L("Algoritm și date ale proprietarului, redare → Rec.709 g2.4, apoi recodare sRGB aplicată o singură dată (nu e schimbare de profil ICC). Paritate cu referința autoritară verificată numeric; comportamentul pe imagini reale rămâne de evaluat de proprietar. Nu folosește Resolve sau STYLE.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
            default: HStack(spacing: 6) { Circle().fill(Theme.reject).frame(width: 8, height: 8); Text(LF("Datele GDC DRT lipsesc sau sunt neașteptate: %@", String(describing: st))).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.reject).fixedSize(horizontal: false, vertical: true) }
                Text(L("Nu se folosește nicio rezervă tăcută. Alege explicit „DRT p1 (exp.)” doar pentru comparație.")).font(Theme.f(11)).foregroundColor(Theme.faint)
            }
        case .p1Experimental:
            HStack(spacing: 6) { Circle().fill(Theme.check).frame(width: 8, height: 8); Text(L("DRT p1 — PROTOTIP EXPERIMENTAL")).font(Theme.f(12, weight: .semibold)) }
            Text(L("NU este GDC DRT, nu e echivalent cu el și nu e o îmbunătățire demonstrată; ajustat doar pe axa neutră măsurată. Păstrat doar pentru comparație explicită.")).font(Theme.f(11)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder var resolveState: some View {
        Details { Text(L("Dependență TEMPORARĂ: modulele STYLE instalate, rulate prin DaVinci Resolve Studio. Transformare de ieșire: GDC DRT (profil Natural) → sRGB. Doar pentru comparație cu prototipul.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        switch ed.connection {
        case .idle: Button(L("Conectează la Resolve")) { ed.connect() }.buttonStyle(PrimaryButtonStyle())
        case .connecting: HStack { ProgressView().controlSize(.small); Text(L("Se conectează la Resolve…")).font(Theme.f(12)).foregroundColor(Theme.muted) }
        case .ready(let s): HStack(spacing: 6) { Circle().fill(Theme.keep).frame(width: 8, height: 8); Text(s).font(Theme.f(12)) }
        case .needsConsent(let p):
            Text(LF("Resolve are deschis proiectul „%@”. Pentru procesare aplicația folosește un proiect propriu și trebuie să îl deschidă (proiectul curent se salvează, nu se șterge).", p)).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Button(L("Permite schimbarea proiectului")) { ed.connect(allowSwitch: true) }.buttonStyle(PrimaryButtonStyle())
        case .unavailable(let m): Text(m).font(Theme.f(12)).foregroundColor(Theme.reject).fixedSize(horizontal: false, vertical: true); Button(L("Reîncearcă")) { ed.connection = .idle; ed.connect() }.buttonStyle(SoftButtonStyle())
        }
    }
}

/// Panoul expunerii, cu cele trei straturi separate: tehnică (decodor, 0), sugestie (statistică, orientativă) și alegere creativă (manual sau automat + corecție).
struct ExposureBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        Box(title: L("Expunere"), panel: "exposure", module: ed.moduleBinding("exposure"), reset: SectionReset(help: L("Resetează secțiunea «Expunere» (expunere, mod automat, corecție); poți anula"), isNeutral: ed.adjustments.exposureGroupIsNeutral && ed.adjustments.tools.isNeutral(.black)) { ed.resetSection(L("Expunere")) { $0.resetExposureGroup(); $0.tools.reset(.black) } }) {
            Toggle(isOn: Binding(get: { ed.adjustments.exposureAuto }, set: { ed.setAutoMode($0) })) { Text(L("Mod automat (estimare + corecție)")).font(Theme.f(12.5)) }.toggleStyle(.switch).controlSize(.small).disabled(ed.suggestion == nil)
            if ed.adjustments.exposureAuto {
                SliderRow(label: L("Corecție față de estimare"), help: L("Stopuri"), value: $ed.adjustments.autoOffset, range: -3...3)
                Text(String(format: L("Efectivă: %+.2f st = estimare %+.2f + corecție %+.2f"), (ed.suggestion?.stops ?? 0) + ed.adjustments.autoOffset, ed.suggestion?.stops ?? 0, ed.adjustments.autoOffset)).font(Theme.f(11)).foregroundColor(Theme.muted)
            } else {
                SliderRow(label: L("Expunere (EV)"), help: L("Stopuri (EV)"), value: $ed.adjustments.exposure, range: -4...8)
            }
            SliderRow(label: L("Negru"), help: "Offset", value: $ed.adjustments.tools.black, range: -0.5...0.5, fmt: "%+.3f")
            Details { SliderRow(label: "Mix", help: L("Modulul Expunere + Balans"), value: $ed.adjustments.tools.ebMix, range: 0...1, neutral: 1, fmt: "%.2f") }
            if let s = ed.suggestion { SuggestionView(s: s, applied: ed.adjustments.exposureAuto || abs(ed.adjustments.exposure - s.stops) < 0.06) { ed.applySuggestion() } }
            else { Text(L("Estimarea apare după prima randare a fotografiei.")).font(Theme.f(11)).foregroundColor(Theme.faint) }
        }
    }
}
struct SuggestionView: View {
    let s: ExposureSuggestion; let applied: Bool; let apply: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) { Text(L("Sugestie")).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted); AutoTag(text: L("statistică · nevalidată")); Spacer()
                Button(LF("Aplică %@", String(format: "%+.1f", s.stops))) { apply() }.buttonStyle(SoftButtonStyle()).disabled(applied) }
            Text(String(format: L("Gri 18%%: %+.1f st · Lumini: %+.1f st"), s.medianToGrey, s.highlightAnchor)).font(Theme.f(11)).foregroundColor(Theme.muted).lineLimit(1).help(String(format: L("Mediană→gri 18%%: %+.1f st · Ancoră lumini (p99→alb de referință): %+.1f st · principală = cea mai mică. Sugestie statistică, nevalidată."), s.medianToGrey, s.highlightAnchor))
            if s.lowKeyWarning { Text(LF("Scenă cu predominant umbre (%@): nu e neapărat subexpusă; sugestia se oprește la ancora luminilor. Decizia e creativă.", s.sceneHint)).font(Theme.f(11)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct StyleScreen: View {
    @ObservedObject var model: AppModel; @ObservedObject var ed: EditingModel; @ObservedObject var panels: PanelState
    @State private var dragStartWidth: Double?
    var body: some View {
        let q = model.editQueue
        GeometryReader { geo in
        let iw = panels.effectiveWidth(windowWidth: geo.size.width)
        HStack(spacing: 0) {
            if !ed.photoOnly { filmstrip(q); Divider().overlay(Theme.line) }
            center
            if !ed.photoOnly { ZStack { Divider().overlay(Theme.line); Color.clear.frame(width: 8).contentShape(Rectangle()).onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { v in if dragStartWidth == nil { dragStartWidth = iw }; panels.userWidth = min(PanelState.widthRange.upperBound, max(PanelState.widthRange.lowerBound, (dragStartWidth ?? iw) - Double(v.translation.width) / Double(Theme.scale))) }.onEnded { _ in dragStartWidth = nil }) }.frame(width: 8).help(L("Trage pentru a schimba lățimea inspectorului"))
            VStack(spacing: 0) { panel; Divider().overlay(Theme.line); approvalRow.padding(14) }.frame(width: Theme.px(CGFloat(iw))).environment(\.inspectorWidth, Theme.px(CGFloat(iw))).background(Theme.panel) }
        }
        .foregroundColor(Theme.text)
        .background(PhotoNavKeys(enabled: ed.photoOnly) { ed.navigate($0, in: q) })
        .overlay(alignment: .bottom) { if ed.photoOnly { PhotoNavBar(ed: ed, viewer: ed.viewer, queue: q) } }
        .overlay(alignment: .topLeading) { if ed.photoOnly { Button { ed.photoOnly = false } label: { Label(L("Ieși din «Doar fotografia»"), systemImage: "arrow.down.right.and.arrow.up.left").lineLimit(1) }.buttonStyle(SoftButtonStyle()).padding(12).keyboardShortcut(.escape, modifiers: []).help(L("Revii la film, inspector și bare, cu aceeași stare (⌘⇧H sau Esc)")) } }
        .onAppear { if ed.engine == .resolveStyle, case .idle = ed.connection { ed.connect() }; if ed.current == nil, let f = q.first { ed.open(f) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.keyWindow?.makeFirstResponder(nil) } }   // primul câmp numeric nu preia focusul la deschidere
        }
    }
    func filmstrip(_ q: [PhotoRecord]) -> some View {
        ScrollView { LazyVStack(spacing: 8) {
            ForEach(q, id: \.id) { p in
                Button { ed.open(p) } label: {
                    PhotoImage(photo: p, kind: .filmstrip).frame(width: 108, height: 108).background(Color.black.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ed.current?.id == p.id ? Theme.accent : Theme.line, lineWidth: ed.current?.id == p.id ? 2 : 1))
                        .overlay(alignment: .bottomTrailing) { if let why = ed.failedPhotos[p.id] { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.check).padding(3).help(LF("Nu s-a putut procesa: %@. Restul cozii continuă; fișierul de pe disc nu a fost atins.", why)) } }
                        .overlay(alignment: .topTrailing) { if ed.isApproved(p.id) { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.keep).padding(3) } }
                }.buttonStyle(.plain)
            }
        }.padding(10) }.frame(width: 132).background(Theme.panel).zIndex(1)
    }
    var compareOptions: [(CompareMode, String)] { [(CompareMode.base, L("Bază")), (.after, L("După")), (.split, L("Împărțit")), (.camera, L("Cameră"))] + (ed.resolveResultImage != nil ? [(CompareMode.resolve, L("Din Resolve"))] : []) }
    /// Potrivit · 100% · procent · «Doar fotografia» (aceleași controale ca înainte; doar grupate ca să încapă pe un rând sau să treacă pe al doilea).
    var zoomCluster: some View {
        HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Button { ed.viewer.setFit() } label: { Text(L("Potrivit")).lineLimit(1).fixedSize() }.buttonStyle(SoftButtonStyle(active: ed.viewer.isFit)).disabled(ed.current == nil).help(L("Întreaga fotografie în vedere. Rotița mouse peste fotografie: zoom pe cursor; Space + tragere sau butonul din mijloc: deplasare"))
                            Button { ed.openDetail() } label: { Text("100%").lineLimit(1).fixedSize() }.buttonStyle(SoftButtonStyle(active: !ed.viewer.isFit && abs(ed.viewer.scale - 1) < 0.005)).disabled(ed.current == nil || !ed.isReady).help(L("Un pixel al imaginii la un pixel fizic al ecranului (rezultatul procesat la rezoluție plină, încărcat la cerere)"))
                            Text("\(ed.viewer.percent)%").font(Theme.f(12, weight: .semibold, design: .monospaced)).foregroundColor(Theme.muted).frame(minWidth: Theme.px(44), alignment: .leading)
                        }
                        Button { ed.photoOnly = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(Theme.f(12, weight: .semibold)).frame(width: Theme.px(24), height: Theme.px(22)) }.buttonStyle(SoftButtonStyle()).disabled(ed.current == nil)
                            .help(L("Doar fotografia (⌘⇧H): ascunde filmul, inspectorul și barele; starea editării se păstrează. Revii cu același buton, ⌘⇧H sau Esc")).accessibilityLabel(L("Doar fotografia"))
        }
    }
    var center: some View {
        VStack(spacing: 0) {
            if !ed.photoOnly {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { Segmented(options: compareOptions, selection: $ed.compare); Spacer(minLength: 8); ToolStrip(ed: ed); Spacer(minLength: 8); zoomCluster }
                    VStack(spacing: 6) {
                        ToolStrip(ed: ed)
                        HStack(spacing: 10) { Segmented(options: compareOptions, selection: $ed.compare); Spacer(minLength: 8); zoomCluster }
                    }
                }.padding(.horizontal, 14).padding(.vertical, 8).zIndex(1)   // barele de deasupra pânzei câștigă clicurile față de stratul de editare care depășește pânza la 100%
            }
            ZStack {
                if ed.compare == .camera, let p = ed.current { PhotoImage(photo: p, kind: .view).padding(10).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.canvas) }
                else {
                    ZoomableCanvas(ed: ed, v: ed.viewer) { r in
                        // ghidajele NU apar în Bază / Împărțit / Cameră / Din Resolve (fotografie curată pentru evaluare) și nici când sunt ascunse; analiza se vede doar în «După»
                        if ed.compare == .after && ed.analysisMode != .off && !ed.floating.isDetached(.analysis), let ai = ed.analysisImage, let res = ed.analysisResult, res.mode == ed.analysisMode { AnalysisCanvas(image: ai, label: ed.analysisMode.label, rect: r) }
                        else if ed.compare == .after && !ed.guidesHidden && ed.geometryMode == .crop { CropOverlay(ed: ed, r: r) }
                        else if ed.compare == .after && !ed.guidesHidden && ed.geometryMode == .straighten { StraightenOverlay(ed: ed, r: r) }
                        else if ed.compare == .after && !ed.guidesHidden && ed.activeTool == .chart { ChartOverlay(ed: ed, r: r) }
                        else if ed.compare == .after && !ed.guidesHidden && ed.activeTool == .retouch { RetouchOverlay(ed: ed, r: r) }
                        else if ed.compare == .after && !ed.guidesHidden && ed.activeTool == .masks { ZoneOverlay(ed: ed, r: r, spaceDown: ed.viewer.spaceDown || ed.viewer.panning) }
                        if ed.compare == .after && !ed.guidesHidden && (ed.selectionKind != nil || ed.wbPicking) { SelectionOverlay(ed: ed, r: r) }
                        if ed.gridVisible && ed.geometryMode == .none && ed.compare != .camera { GridOverlay(rect: r, fine: false) }
                        if ed.loupeOn && ed.compare != .camera { LoupeOverlay(ed: ed, v: ed.viewer, r: r) }
                        ToolActionBar(ed: ed)
                        if ed.afterImage == nil, ed.compare == .after, let p = ed.current {   // decodare la rece: imaginea din cameră apare imediat, marcată clar; înlocuită de rezultatul GDC când e gata
                            ZStack(alignment: .bottom) { PhotoImage(photo: p, kind: .view).padding(10).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.canvas)
                                Badge(text: L("previzualizare din cameră · se decodează RAW-ul"), color: Theme.auto, dashed: true).padding(10).background(Theme.canvas.opacity(0.8)).clipShape(Capsule()).padding(.bottom, 14) }.allowsHitTesting(false)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if !ed.photoOnly {
                HStack(spacing: 8) { Text(ed.current.map { ($0.path as NSString).lastPathComponent } ?? L("Alege o fotografie")).font(Theme.f(12)).foregroundColor(Theme.muted)
                    if ed.rendering { ProgressView().controlSize(.small) }
                    if ed.refining { Badge(text: L("previzualizare rapidă · se rafinează"), color: Theme.auto, dashed: true) }
                    Text(ed.statusLine.isEmpty ? ed.afterInfo : ed.statusLine).font(Theme.f(11)).foregroundColor(ed.statusLine.isEmpty ? Theme.faint : Theme.check).lineLimit(1).truncationMode(.tail)
                    Spacer(); Text(captionFor(ed.compare)).font(Theme.f(11)).foregroundColor(Theme.faint).lineLimit(1).truncationMode(.tail) }.padding(.horizontal, 14).padding(.vertical, 6).zIndex(1)
            }
        }
    }
    func captionFor(_ m: CompareMode) -> String {
        switch m {
        case .base: return L("Bază = aceeași dezvoltare (LibRaw → lanț GDC neutru), fără ajustări. Aceasta e baza comparației.")
        case .after: return L("După = baza + reglajele tale.")
        case .split: return L("Stânga: bază (fără ajustări) · dreapta: după.")
        case .camera: return L("Cameră = previzualizarea JPEG încorporată (altă dezvoltare, reper separat; nu e randare GDC).")
        case .resolve: return L("Din Resolve = rezultatul randat în DaVinci Resolve din versiunea FotoAsist (cu toate nodurile fotografului). Altă cale de randare decât previzualizarea FotoAsist.")
        }
    }
    var panel: some View {
        GeometryReader { g in
            ScrollView(.vertical) { VStack(alignment: .leading, spacing: 10) {
                InspectorHeader(ed: ed, panels: panels)
                InspectorHistogram(ed: ed)
                if ed.currentIsRendered { RenderedPanel(ed: ed) } else {
                InspectorTabBar(panels: panels)
                if !ed.legacyNotice.isEmpty { Text(ed.legacyNotice).font(Theme.f(11.5)).foregroundColor(Theme.check).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.check.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 8)).fixedSize(horizontal: false, vertical: true) }
                RawDevelopmentBox(ed: ed)
                RawInfoBox(ed: ed)
                ExposureBox(ed: ed)
                Box(title: L("Lumină și contrast"), panel: "light", module: ed.moduleBinding("light"), reset: SectionReset(help: L("Resetează secțiunea «Lumină și contrast» (umbre, lumini, contrast); poți anula"), isNeutral: ed.adjustments.lightGroupIsNeutral && ed.adjustments.tools.isNeutral(.midtones) && ed.adjustments.tools.isNeutral(.pivot)) { ed.resetSection(L("Lumină și contrast")) { $0.resetLightGroup(); $0.tools.reset(.midtones); $0.tools.reset(.pivot) } }) {
                    SliderRow(label: L("Umbre (EV)"), help: L("Stopuri (EV)"), value: $ed.adjustments.shadows, range: -2...2)
                    SliderRow(label: L("Mijloc (EV)"), help: L("Stopuri (EV)"), value: $ed.adjustments.tools.midtones, range: -1...1)
                    SliderRow(label: L("Lumini (EV)"), help: L("Stopuri (EV)"), value: $ed.adjustments.highlights, range: -2...2)
                    SliderRow(label: L("Contrast"), value: $ed.adjustments.contrast, range: 0.5...3, neutral: 1, fmt: "%.2f")
                    SliderRow(label: L("Pivot (EV)"), help: L("Stopuri față de gri 18%"), value: $ed.adjustments.tools.pivot, range: -3...3, fmt: "%+.1f")
                }
                Box(title: L("Balans de alb și culoare"), panel: "colour", module: ed.moduleBinding("colour"), reset: SectionReset(help: L("Resetează secțiunea «Culoare» (temperatură, tentă, saturație); poți anula"), isNeutral: ed.adjustments.colourGroupIsNeutral && ed.adjustments.tools.isNeutral(.hue)) { ed.resetSection(L("Culoare")) { $0.resetColourGroup(); $0.tools.reset(.hue) } }) {
                    HStack { Button { ed.wbPicking.toggle(); if ed.wbPicking { ed.colorPicking = false; ed.rangePicking = false; ed.compare = .after } } label: { Label(ed.wbPicking ? L("Apasă pe o zonă gri sau trage un dreptunghi…") : L("Pipetă balans de alb (zonă neutră)"), systemImage: "eyedropper").lineLimit(1) }.buttonStyle(ed.wbPicking ? SoftButtonStyle(active: true) : SoftButtonStyle()).help(L("Alege un gri neutru din imagine; temperatura și tenta se potrivesc ca zona să devină neutră. Pe fotografia curentă, anulabil.")) }
                    if !ed.wbNote.isEmpty { Text(ed.wbNote).font(Theme.f(11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                    HStack { Text(L("Balans de alb")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted); Spacer(); Text(L("Pornește din: balansul camerei")).font(Theme.f(10.5)).foregroundColor(Theme.faint) }
                    SliderRow(label: L("Temperatură (mired)"), help: L("Mired: valori negative = mai rece, pozitive = mai cald"), value: $ed.adjustments.temperature, range: -150...150, fmt: "%+.0f", track: [Color(red: 0.35, green: 0.55, blue: 1.0), Color(white: 0.8), Color(red: 1.0, green: 0.62, blue: 0.25)])
                    SliderRow(label: L("Tentă (verde↔magenta)"), help: L("Unități de tentă (nu Kelvin)"), value: $ed.adjustments.tint, range: -0.05...0.05, fmt: "%+.3f", track: [Color(red: 0.25, green: 0.8, blue: 0.4), Color(white: 0.8), Color(red: 0.9, green: 0.3, blue: 0.75)])
                    Text(L("Culoare · saturație și nuanță (trei metode diferite)")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
                    SliderRow(label: L("Saturație globală"), value: $ed.adjustments.saturation, range: 0...2, neutral: 1, fmt: "%.2f", track: [Color(white: 0.55), Color(red: 0.9, green: 0.45, blue: 0.3), Color(red: 1.0, green: 0.15, blue: 0.25)])
                    Text(L("HSV (model nuanță · saturație · valoare, pe codul log)")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
                    SliderRow(label: L("Nuanță"), help: L("Grade"), value: $ed.adjustments.tools.hueRotate, range: -180...180, fmt: "%+.0f", track: [.red, .yellow, .green, .cyan, .blue, Color(red: 1, green: 0, blue: 1), .red])
                    SliderRow(label: L("Saturație HSV"), value: $ed.adjustments.tools.hsvSat, range: 0...2, neutral: 1, fmt: "%.2f", track: [Color(white: 0.55), Color(red: 1.0, green: 0.2, blue: 0.3)])
                    SliderRow(label: L("Valoare HSV"), value: $ed.adjustments.tools.hsvVal, range: 0...2, neutral: 1, fmt: "%.2f", track: [Color(white: 0.1), Color(white: 0.95)])
                    SliderRow(label: L("Mix saturație/HSV"), value: $ed.adjustments.tools.shMix, range: 0...1, neutral: 1, fmt: "%.2f")
                    Details(title: L("Care e diferența dintre metode?")) { VStack(alignment: .leading, spacing: 4) {
                        Text(L("Saturație globală: păstrează luminanța; scalează distanța față de luminanță, pe canalele codului log (0 = alb-negru). Folosește-o pentru intensitatea generală a culorii.")).font(Theme.f(11)).foregroundColor(Theme.faint)
                        Text(L("Saturație globală: păstrează luminanța (media ponderată a canalelor); schimbă doar cât de departe e culoarea de gri.")).font(Theme.f(11)).foregroundColor(Theme.faint)
                        Text(L("Saturație HSV: scalează raportul dintre canalul maxim și minim; nu păstrează luminanța (albastrul/roșul se luminează sau se întunecă diferit). Valoare HSV: înmulțește canalul maxim al fiecărui pixel — e o scalare multiplicativă pe codul log, NU expunere în stopuri; ridică sau coboară și griurile.")).font(Theme.f(11)).foregroundColor(Theme.faint)
                        Text(L("Alte metode (în alte panouri): Saturație CDL (Tonuri), Saturație/Densitate pe o culoare aleasă (Culoare selectivă), Vivid/Rich pe piele, saturație și vibranță în Look, saturație în densitate la Stiluri cinema. Nu sunt echivalente între ele. Analiza «Saturație» măsoară rezultatul final, nu reglajul.")).font(Theme.f(11)).foregroundColor(Theme.faint)
                    }.fixedSize(horizontal: false, vertical: true) }
                }
                WheelsBox(ed: ed)
                HueVectorsBox(ed: ed)
                if Edition.full {   // module absente din ediția cu sursă deschisă
                    DiffusionBox(ed: ed)
                    ColorBox(ed: ed)
                    SkinBox(ed: ed)
                    LookBox(ed: ed)
                }
                TonalBalanceBox(ed: ed)
                PrinterBox(ed: ed)
                ChannelMixBox(ed: ed)
                HighlightsGamutBox(ed: ed)
                GeometryBox(ed: ed)
                ChartBox(ed: ed, model: model)
                if ed.engine == .own { FamilyBox(ed: ed) }
                DetailBox(ed: ed)
                RetouchBox(ed: ed)
                OpticsBox(ed: ed)
                LocalCorrectionsBox(ed: ed)
                FilmBox(ed: ed)
                if Edition.full {
                    Film3Box(ed: ed)
                    CinemaBox(ed: ed)
                }
                GrainBox(ed: ed)
                AnalysisBox(ed: ed)
                LoupeBox(ed: ed).environmentObject(ed.floating)
                Box(title: L("Presetări de parametri"), panel: "presets") {
                    HStack(spacing: 6) { ForEach(StylePreset.all, id: \.id) { pr in
                        Button(pr.name) { ed.applyPreset(pr.id) }.buttonStyle(SoftButtonStyle(active: ed.adjustments.styleID == pr.id)).disabled(ed.current == nil) } }
                    Text(L("Seturi fixe de contrast și saturație, nu profiluri învățate din editările tale. Le poți regla mai jos.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                }
                PersonalProfileBox(ed: ed)
                ConnectionBox(ed: ed)
                ResolveHandoffBox(ed: ed)
                }
            }.frame(width: max(Theme.px(260), g.size.width - 28), alignment: .leading).padding(14).background(Color.clear.contentShape(Rectangle()).onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }).environment(\.resetHook, { ed.registerReset(LF("«%@» a revenit la valoarea neutră", $0)) }).environment(\.numericGesture, NumericGestureHooks(begin: { ed.beginGesture($0) }, end: { ed.endGesture() }, cancel: { ed.cancelGesture() }, photo: { ed.current?.id })).environmentObject(panels) }   // lățime FIXĂ = viewport: nimic nu poate lărgi coloana și tăia valorile
        }.overlay(alignment: .bottom) { VStack(spacing: 6) { resetBanner }.padding(.horizontal, 12).padding(.bottom, 8).shadow(color: .black.opacity(0.35), radius: 6, y: 2) }   // plutește peste conținut: apariția/dispariția ei nu mută rândurile de sub cursor
    }
    /// „Anulează” ultima resetare (⌘Z): vizibil doar după o resetare.
    @ViewBuilder var resetBanner: some View {
        if ed.lastReset == nil, let r = ed.redoState {
            HStack(spacing: 8) { Image(systemName: "arrow.clockwise").foregroundColor(Theme.accent); Text(r.message).font(Theme.f(11.5)).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 4)
                Button(L("Refă")) { ed.redoLastReset() }.buttonStyle(SoftButtonStyle()).keyboardShortcut("z", modifiers: [.command, .shift]).help(L("Reaplică modificarea anulată (⇧⌘Z)")) }
                .padding(10).background(Theme.toolbar.overlay(Theme.accent.opacity(0.18))).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        if let r = ed.lastReset {
            HStack(spacing: 8) { Image(systemName: "arrow.counterclockwise").foregroundColor(Theme.accent); Text(r.message).font(Theme.f(11.5)).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 4)
                Button(L("Anulează")) { ed.undoLastReset() }.buttonStyle(SoftButtonStyle()).keyboardShortcut("z", modifiers: .command).help(L("Revine la valorile de dinainte de resetare (⌘Z)")) }
                .padding(10).background(Theme.toolbar.overlay(Theme.accent.opacity(0.18))).clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    var approvalRow: some View {
        let cur = ed.current; let ok = cur.map { ed.isApproved($0.id) } ?? false
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(L("Resetează tot")) { ed.resetAdjustments() }.buttonStyle(SoftButtonStyle()).disabled(cur == nil || ed.adjustments.isNeutral).help(L("Resetează TOATE ajustările fotografiei (globale și corecții locale); poți anula"))
                Button(ok ? L("Aprobată ✓") : L("Aprobă")) { ed.toggleApproved() }.buttonStyle(SoftButtonStyle(tint: Theme.keep, active: ok)).disabled(cur == nil)
                Spacer(); Button { model.step = .review } label: { Text(L("Revizuire →")).lineLimit(1).fixedSize() }.buttonStyle(PrimaryButtonStyle())
            }
            if !ed.approvalNote.isEmpty { Text(ed.approvalNote).font(Theme.f(11.5)).foregroundColor(Theme.check) }
        }
    }
}

struct CompareCanvas: View {
    let before: NSImage?, after: NSImage?; let mode: CompareMode; let busy: Bool
    var body: some View {
        GeometryReader { g in
            ZStack {
                switch mode {
                case .base: img(before)
                case .after, .camera, .resolve: img(after)
                case .split:
                    ZStack { img(after); img(before).mask(HStack(spacing: 0) { Rectangle().frame(width: g.size.width / 2); Spacer(minLength: 0) })
                        Rectangle().fill(Color.white.opacity(0.7)).frame(width: 1) }
                }
                if (mode == .base ? before : after) == nil { VStack(spacing: 8) { ProgressView(); Text(busy ? L("Se pregătește imaginea…") : L("Nicio imagine încă")).font(Theme.f(12)).foregroundColor(Theme.muted) } }
            }.frame(width: g.size.width, height: g.size.height)
        }
    }
    @ViewBuilder func img(_ i: NSImage?) -> some View { if let i = i { Image(nsImage: i).resizable().aspectRatio(contentMode: .fit).padding(10) } else { Color.clear } }
}

/// Inspecție a rezultatului procesat la rezoluție plină, la cerere: 100% = un pixel de imagine pe un pixel fizic de ecran; derulare/tragere pentru deplasare. Se eliberează la închidere.
struct DetailInspector: View {
    @ObservedObject var ed: EditingModel
    enum Zoom: Hashable { case fit, one, two }
    @State private var zoom: Zoom = .one; @State private var showBase = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Segmented(options: [(Zoom.fit, L("Potrivit")), (.one, "100%"), (.two, "200%")], selection: $zoom)
                Segmented(options: [(false, L("După")), (true, L("Bază"))], selection: $showBase)
                Spacer(); Text(ed.detailBusy ? L("Se randează la rezoluție plină…") : (ed.detailError.isEmpty ? ed.detailInfo : ed.detailError)).font(Theme.f(11.5)).foregroundColor(ed.detailError.isEmpty ? Theme.muted : Theme.reject).lineLimit(2)
                Button(L("Închide")) { ed.closeDetail() }.buttonStyle(SoftButtonStyle())
            }.padding(.horizontal, 14).padding(.vertical, 8).background(Theme.panel)
            ZStack {
                Theme.canvas
                if let img = (showBase ? ed.detailBase : ed.detailAfter) { content(img) }
                else if ed.detailBusy { ProgressView() }
            }
        }.background(Theme.app)
    }
    @ViewBuilder func content(_ img: NSImage) -> some View {
        let px = img.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? img.size
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let f: CGFloat = zoom == .two ? 2 : 1
        if zoom == .fit { Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(8) }
        else { ScrollView([.horizontal, .vertical]) { Image(nsImage: img).resizable().interpolation(.none).frame(width: px.width / scale * f, height: px.height / scale * f) } }
    }
}

/// Selectorul familiei de lucru (GDC STYLE): gamut + codificare log, coerente de la RAW până la sRGB. RAW-ul camerei, familia internă și ieșirea sRGB rămân trei lucruri distincte. Schimbarea păstrează valorile tale; aspectul se poate schimba.
struct FamilyBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        Box(title: L("Familie de lucru"), panel: "family", summary: ed.adjustments.family.shortLabel) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(WorkingFamily.allCases, id: \.rawValue) { f in
                    Button { ed.setFamily(f) } label: { Text(f.shortLabel).lineLimit(1).minimumScaleFactor(1).frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle(active: ed.adjustments.family == f)).disabled(ed.current == nil)
                        .accessibilityAddTraits(ed.adjustments.family == f ? .isSelected : []).help(f.label)
                }
            }
            Text(ed.adjustments.family.label).font(Theme.f(12, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Details { VStack(alignment: .leading, spacing: 6) {
            Text(ed.adjustments.family.explanation).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            Text(L("Aleasă aici: RAW → liniar în gamutul familiei → expunere/balans/umbre/lumini → cod log → contrast/saturație → GDC DRT → sRGB. Intrarea camerei și ieșirea sRGB nu se schimbă. Valorile tale rămân; aspectul lor poate diferi între familii.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            } }
        }
    }
}


/// Inspectorul unei intrări REDATE (PNG/JPEG/TIFF): spune clar ce se păstrează și ce nu se aplică; singura prelucrare permisă e geometria.
struct RenderedPanel: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { RenderedBadge(); Spacer() }
            Text(L("Intrare redată: disponibile decuparea și geometria; culoarea, tonurile și DRT nu se aplică.")).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Details { VStack(alignment: .leading, spacing: 6) {
                Text(L("Imaginea este deja redată (display-referred) și nu are date de scenă. Expunerea, balansul de alb, tonurile, culoarea, GDC DRT, chartul, retușul și aplicarea profilurilor personale sunt dezactivate pentru ea. Fără normalizare RAW, fără metadate de cameră, fără DRT peste imaginea redată; starea neutră păstrează aspectul sursei în limita conversiei ICC → sRGB.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                if let i = ed.renderedInfo { KV(k: L("Format"), v: i.format); KV(k: L("Dimensiune"), v: "\(i.width)×\(i.height)"); KV(k: L("Culoare"), v: i.summary) }
            } }
            GeometryBox(ed: ed)
            ProfileFlowEntry(ed: ed)
        }.onAppear { if ed.panels.tab != .base { ed.panels.tab = .base } }.onChange(of: ed.panels.tab) { t in if t != .base { ed.panels.tab = .base } }   // fără bara de file pentru imagini redate, panourile aparțin filei «Bază»
    }
}

/// Acces la fluxul «Creează profilul meu» ca ACȚIUNE DE SESIUNE (independentă de imaginea curentă): fluxul lucrează cu perechi RAW + final, nu cu imaginea redată afișată. Aplicarea/estimarea pe o intrare redată rămâne blocată în model.
struct ProfileFlowEntry: View {
    @ObservedObject var ed: EditingModel
    @State private var photographer = "Eu"; @State private var setName = "Set 1"; @State private var profileName = L("Profilul meu"); @State private var flow = false
    var body: some View {
        Box(title: L("Profilul meu (sesiune)"), panel: "rawinfo") {
            Button { flow = true } label: { Label(L("Creează profilul meu…"), systemImage: "wand.and.stars").lineLimit(1) }.buttonStyle(SoftButtonStyle())
                .sheet(isPresented: $flow) { ProfileFlowSheet(ed: ed, photographer: $photographer, setName: $setName, profileName: $profileName).frame(minWidth: 560, idealWidth: 700, maxWidth: 760, minHeight: 520, idealHeight: 660) }
            Text(L("Fluxul folosește perechi RAW + final aprobate de tine; nu se aplică imaginii redate afișate.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
        }
    }
}
