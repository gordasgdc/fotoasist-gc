import SwiftUI
import Combine
import PhotoCore
import AppKit
import PhotoResolve

public enum FloatKind: String, CaseIterable {
    case analysis, histogram, vectorscope, parade, loupe
    var title: String { switch self { case .analysis: return L("Analiză (nu se exportă)"); case .histogram: return L("Histogramă"); case .vectorscope: return L("Vectorscop"); case .parade: return L("RGB Parade"); case .loupe: return L("Lupă de inspecție") } }
    var defaultSize: NSSize { switch self { case .analysis: return NSSize(width: 520, height: 420); case .histogram: return NSSize(width: 360, height: 220); case .vectorscope: return NSSize(width: 360, height: 440); case .parade: return NSSize(width: 520, height: 300); case .loupe: return NSSize(width: 320, height: 340) } }
}

/// Ferestre flotante OPȚIONALE pentru analiză/histogramă/lupă. Conținutul citește același `EditingModel` (aceeași procesare și cache); închiderea ferestrei nu oprește editarea.
/// «Deasupra FotoAsist» = panou care plutește doar cât aplicația e activă (nu blochează alte aplicații). Poziția se salvează și se readuce pe ecran la redeschidere sau la schimbarea monitoarelor.
@MainActor public final class FloatingPanels: NSObject, ObservableObject, NSWindowDelegate {
    @Published public private(set) var detached: Set<FloatKind> = []
    @Published public var keepOnTop: Bool { didSet { UserDefaults.standard.set(keepOnTop, forKey: "gdcpa.float.top"); panels.values.forEach(apply); analysisPanels.values.forEach(applyLevel); dashboardPanel.map(applyLevel) } }
    weak var ed: EditingModel?
    private var panels: [FloatKind: NSPanel] = [:]
    // ferestre de analiză independente (AnalysisWindows.swift)
    var analysisPanels: [UUID: NSPanel] = [:]; var analysisViews: [UUID: AnalysisView] = [:]; var analysisSlots: [UUID: Int] = [:]; var titleSubs: [UUID: AnyCancellable] = [:]
    var dashboardPanel: NSPanel?; var closingAll = false
    private var screenObserver: NSObjectProtocol?
    public override init() {
        keepOnTop = (UserDefaults.standard.object(forKey: "gdcpa.float.top") as? Bool) ?? true
        super.init()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.panels.values.forEach { Self.recover($0) }; self?.recoverAnalysisPanels() } }
    }
    deinit { if let o = screenObserver { NotificationCenter.default.removeObserver(o) } }
    public func isDetached(_ k: FloatKind) -> Bool { detached.contains(k) }
    public func toggle(_ k: FloatKind) { isDetached(k) ? attach(k) : detach(k) }
    public func detach(_ k: FloatKind) {
        guard let ed = ed else { return }
        if let p = panels[k] { p.makeKeyAndOrderFront(nil); Self.recover(p); return }
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: k.defaultSize), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = k.title; p.isReleasedWhenClosed = false; p.delegate = self; p.becomesKeyOnlyIfNeeded = true; p.minSize = NSSize(width: 220, height: 160)
        p.contentView = NSHostingView(rootView: Self.content(k, ed))
        if !p.setFrameUsingName("gdcpa.float." + k.rawValue) { p.center() }
        p.setFrameAutosaveName("gdcpa.float." + k.rawValue)
        apply(p); Self.recover(p); panels[k] = p; detached.insert(k); p.orderFront(nil)
    }
    /// Revenire în inspector: fereastra se închide, editarea continuă.
    public func attach(_ k: FloatKind) { panels[k]?.close() }
    public func closeAll() { FloatKind.allCases.forEach(attach) }
    public func windowWillClose(_ n: Notification) {
        guard let w = n.object as? NSPanel else { return }
        if handleAnalysisClose(w) { return }
        guard let k = panels.first(where: { $0.value === w })?.key else { return }
        panels[k] = nil; detached.remove(k)
    }
    private func apply(_ p: NSPanel) { applyLevel(p) }
    private func applyOLD(_ p: NSPanel) { p.isFloatingPanel = keepOnTop; p.level = keepOnTop ? .floating : .normal; p.hidesOnDeactivate = keepOnTop }
    /// Dacă fereastra nu mai atinge niciun ecran vizibil (monitor deconectat), o aduce pe ecranul principal.
    static func recover(_ p: NSPanel) {
        let vis = NSScreen.screens.map { $0.visibleFrame }
        if !vis.contains(where: { $0.intersection(p.frame).width >= 80 && $0.intersection(p.frame).height >= 60 }) {
            var f = p.frame; let s = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
            f.size.width = min(f.width, s.width); f.size.height = min(f.height, s.height)
            f.origin = NSPoint(x: s.midX - f.width / 2, y: s.midY - f.height / 2); p.setFrame(f, display: true)
        }
    }
    static func content(_ k: FloatKind, _ ed: EditingModel) -> AnyView {
        switch k {
        case .analysis: return AnyView(AnalysisFloatView(ed: ed).environmentObject(ed.floating))
        case .histogram: return AnyView(HistogramFloatView(ed: ed).environmentObject(ed.floating))
        case .vectorscope: return AnyView(VectorscopeFloatView(ed: ed).environmentObject(ed.floating))
        case .parade: return AnyView(ParadeFloatView(ed: ed).environmentObject(ed.floating))
        case .loupe: return AnyView(LoupeView(ed: ed).environmentObject(ed.floating))
        }
    }
}

struct UpdateChip: View {
    let busy: Bool; let at: Date?
    var body: some View {
        HStack(spacing: 5) { if busy { ProgressView().controlSize(.mini); Text(L("Se actualizează…")) } else if let at = at { Image(systemName: "checkmark.circle"); Text(L("Actualizat ") + at.formatted(date: .omitted, time: .standard)) } else { Text(L("Fără date")) } }
            .font(Theme.f(10.5)).foregroundColor(busy ? Theme.check : Theme.muted)
    }
}

/// Vizualizarea de analiză într-o fereastră separată: imaginea de analiză cu domeniu și legendă; fotografia principală rămâne neschimbată.
struct AnalysisFloatView: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Menu(ed.analysisMode == .off ? "Alege analiza" : ed.analysisMode.label) { ForEach(AnalysisMode.allCases, id: \.rawValue) { m in Button(m.label) { ed.analysisMode = m } } }.fixedSize(); Spacer(); UpdateChip(busy: ed.analysisBusy, at: ed.analysisUpdatedAt) }
            if ed.analysisMode == .off { Text(L("Alege o analiză. Fotografia principală nu se modifică.")).font(Theme.f(12)).foregroundColor(Theme.muted); Spacer() }
            else {
                Text(L("Domeniu: ") + ed.analysisMode.domain).font(Theme.f(11.5, weight: .semibold))
                if let ai = ed.analysisImage, let r = ed.analysisResult, r.mode == ed.analysisMode {
                    Image(nsImage: ai).resizable().interpolation(.none).aspectRatio(contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.4)).overlay(alignment: .topLeading) { Text(L("ANALIZĂ · nu e fotografia, nu se exportă")).font(Theme.f(10.5, weight: .semibold)).foregroundColor(Theme.accentInk).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Theme.accentHi)).padding(6) }
                    ForEach(Array(r.legend.enumerated()), id: \.offset) { _, it in HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(Color(red: Double(it.r) / 255, green: Double(it.g) / 255, blue: Double(it.b) / 255)).frame(width: 14, height: 14); Text(it.text).font(Theme.f(11)) } }
                    Text(r.sampled).font(Theme.f(10.5)).foregroundColor(Theme.faint)
                } else { Spacer(); HStack { Spacer(); ProgressView(); Spacer() }; Spacer() }
            }
            footer
        }.padding(12).frame(minWidth: 220, minHeight: 160).background(Theme.panel).foregroundColor(Theme.text)
    }
    var footer: some View { FloatFooter(kind: .analysis) }
}
struct HistogramFloatView: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Toggle(L("Histogramă"), isOn: $ed.showHistogram).toggleStyle(.switch).controlSize(.small); Spacer(); UpdateChip(busy: ed.analysisBusy, at: ed.analysisUpdatedAt) }
            if let r = ed.analysisResult, ed.showHistogram { HistogramView(h: r.histogram).frame(maxWidth: .infinity, maxHeight: .infinity); Text(L("RGB și luminanță pe imaginea finală (sRGB după GDC DRT).")).font(Theme.f(10.5)).foregroundColor(Theme.faint) }
            else { Spacer(); Text(ed.showHistogram ? L("Se calculează…") : L("Pornește histograma.")).font(Theme.f(12)).foregroundColor(Theme.muted); Spacer() }
            FloatFooter(kind: .histogram)
        }.padding(12).frame(minWidth: 220, minHeight: 160).background(Theme.panel).foregroundColor(Theme.text)
    }
}
struct FloatFooter: View {
    @EnvironmentObject var fp: FloatingPanels; let kind: FloatKind
    var body: some View {
        HStack { Toggle(L("Deasupra FotoAsist"), isOn: $fp.keepOnTop).toggleStyle(.checkbox).font(Theme.f(11)).help(L("Plutește peste fereastra FotoAsist; nu stă deasupra altor aplicații"))
            Spacer(); Button(L("Revino în inspector")) { fp.attach(kind) }.buttonStyle(SoftButtonStyle()) }
    }
}
