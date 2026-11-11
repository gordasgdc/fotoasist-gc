import SwiftUI
import AppKit
import Combine
import PhotoCore
import PhotoResolve

/// Panou de analiză reutilizabil (fereastră separată ȘI tablou comun): selector propriu, opțiuni proprii (amplificarea la «Diferență NR»), imagine de analiză, legendă, domeniu și stare (încărcare/eroare/actualizat).
struct AnalysisPaneView: View {
    @ObservedObject var v: AnalysisView; @ObservedObject var ed: EditingModel
    var onRemove: (() -> Void)? = nil
    var body: some View {
        let stale = v.shownPhoto != nil && v.shownPhoto != ed.current?.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(AnalysisMode.allCases.filter { $0 != .off }, id: \.rawValue) { m in Button(m.label) { v.spec.mode = m } }
                } label: { Text(v.spec.mode.label).font(Theme.f(12.5, weight: .semibold)).lineLimit(1) }.menuStyle(.borderlessButton).fixedSize()
                if v.spec.mode == .nrDifference {
                    Picker("", selection: Binding(get: { v.spec.nrGain }, set: { v.spec.nrGain = $0 })) { ForEach([1.0, 2.0, 4.0, 8.0, 16.0], id: \.self) { Text("×" + String(format: "%g", $0)).tag($0) } }.pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(maxWidth: 190)
                        .help(L("Amplificare (doar afișare)"))
                }
                Spacer(minLength: 0)
                if v.busy { ProgressView().controlSize(.mini); Text(L("Se calculează…")).font(Theme.f(10.5)).foregroundColor(Theme.check) }
                else if let at = v.updatedAt { Image(systemName: "checkmark.circle").font(Theme.f(10.5)).foregroundColor(Theme.muted).help(L("Actualizat ") + at.formatted(date: .omitted, time: .standard)) }
                if let rm = onRemove { Button { rm() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundColor(Theme.faint).help(L("Elimină panoul")).accessibilityLabel(L("Elimină panoul")) }
            }
            ZStack {
                Color.black.opacity(0.35)
                if let why = v.error, !stale { VStack(spacing: 6) { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.check); Text(L("Analiza nu s-a putut calcula")).font(Theme.f(11.5, weight: .semibold)); Text(why).font(Theme.f(10.5)).foregroundColor(Theme.muted).lineLimit(4).multilineTextAlignment(.center) }.padding(10) }
                else if let img = v.image, !stale, v.shownPhoto == ed.current?.id { Image(nsImage: img).resizable().interpolation(.none).aspectRatio(contentMode: .fit) }
                else { VStack(spacing: 6) { ProgressView().controlSize(.small); Text(ed.current == nil ? L("Nicio fotografie deschisă.") : L("Se calculează…")).font(Theme.f(11)).foregroundColor(Theme.muted) } }
            }.frame(minHeight: 120).clipShape(RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
            if let r = v.result, v.shownPhoto == ed.current?.id {
                ForEach(Array(r.legend.enumerated()), id: \.offset) { _, it in
                    HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(Color(red: Double(it.r) / 255, green: Double(it.g) / 255, blue: Double(it.b) / 255)).frame(width: 14, height: 11)
                        Text(it.text).font(Theme.f(10.5)).lineLimit(2).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 0); if it.fraction > 0 || !it.text.contains("mai ") { Text(String(format: "%.1f%%", it.fraction * 100)).font(Theme.f(10.5)).foregroundColor(Theme.muted) } }
                }
                ForEach(r.notes, id: \.self) { Text($0).font(Theme.f(10)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                Text(r.domain).font(Theme.f(10)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                if v.spec.mode == .skin { Text(L("Selecție după CULOARE (interval YCbCr), nu detecție de piele.")).font(Theme.f(10)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
            }
            Text(L("Doar vizualizare: nu modifică fotografia, reglajele, profilul sau exportul.")).font(Theme.f(9.5)).foregroundColor(Theme.faint)
        }
    }
}

struct AnalysisWindowRoot: View {
    @ObservedObject var v: AnalysisView; @ObservedObject var ed: EditingModel
    var body: some View {
        ScrollView { AnalysisPaneView(v: v, ed: ed).padding(12) }.frame(minWidth: 260, minHeight: 240).background(Theme.panel).foregroundColor(Theme.text)
    }
}

struct AnalysisDashboardRoot: View {
    @ObservedObject var hub: AnalysisHub; @ObservedObject var ed: EditingModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L("Tablou de analize")).font(Theme.f(13, weight: .semibold)); Text(LF("%@ panouri", hub.dashboard.count)).font(Theme.f(11)).foregroundColor(Theme.muted); Spacer()
                Menu { ForEach(AnalysisMode.allCases.filter { $0 != .off }, id: \.rawValue) { m in Button(m.label) { hub.addPanel(m) } } } label: { Label(L("Adaugă panou"), systemImage: "plus.circle") }.menuStyle(.borderlessButton).fixedSize().disabled(hub.dashboard.count >= 9)
                if let r = hub.lastRun { Text(String(format: "%d analize unice · %.0f ms", r.unique, r.seconds * 1000)).font(Theme.f(10)).foregroundColor(Theme.faint) }
            }.padding(10)
            Divider().overlay(Theme.line)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(hub.dashboard) { v in AnalysisPaneView(v: v, ed: ed, onRemove: hub.dashboard.count > 1 ? { hub.removePanel(v.id) } : nil).padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Theme.app.opacity(0.5))) }
                }.padding(12)
            }
        }.frame(minWidth: 340, minHeight: 300).background(Theme.panel).foregroundColor(Theme.text)
    }
}

extension FloatingPanels {
    static let windowsKey = "gdcpa.analysis.windows"
    private func saved() -> [AnalysisViewSpec] { (UserDefaults.standard.data(forKey: Self.windowsKey)).flatMap { try? JSONDecoder().decode([AnalysisViewSpec].self, from: $0) } ?? [] }
    func persistWindows() { let specs = analysisViews.values.map { $0.spec }.sorted { $0.id.uuidString < $1.id.uuidString }; if let d = try? JSONEncoder().encode(specs) { UserDefaults.standard.set(d, forKey: Self.windowsKey) } }
    /// O fereastră NOUĂ de analiză (se pot deschide oricâte, inclusiv două ale aceleiași analize), cu selector, opțiuni, titlu, redimensionare și închidere proprii.
    @discardableResult public func openAnalysisWindow(_ spec: AnalysisViewSpec = AnalysisViewSpec()) -> AnalysisView? {
        guard let ed = ed else { return nil }
        var sp = spec; sp.id = UUID()
        let v = AnalysisView(spec: sp); analysisViews[v.id] = v
        let slot = (0..<64).first { s in !analysisSlots.values.contains(s) } ?? 0; analysisSlots[v.id] = slot
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: 400, height: 420)), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = v.title; p.isReleasedWhenClosed = false; p.delegate = self; p.becomesKeyOnlyIfNeeded = true; p.minSize = NSSize(width: 260, height: 240)
        p.contentView = NSHostingView(rootView: AnalysisWindowRoot(v: v, ed: ed))
        let name = "gdcpa.float.analysisw.\(slot)"
        if !p.setFrameUsingName(name) { p.center(); p.setFrameOrigin(NSPoint(x: p.frame.origin.x + CGFloat(slot) * 28, y: p.frame.origin.y - CGFloat(slot) * 28)) }
        p.setFrameAutosaveName(name)
        titleSubs[v.id] = v.$spec.sink { [weak self] _ in DispatchQueue.main.async { MainActor.assumeIsolated { self?.retitleAnalysisWindows(); self?.persistWindows() } } }
        applyLevel(p); Self.recover(p); analysisPanels[v.id] = p; ed.analysisHub.register(v); persistWindows(); retitleAnalysisWindows(); p.orderFront(nil); objectWillChange.send()
        return v
    }
    /// «Arată ferestrele de analiză»: aduce în față ferestrele deschise sau, dacă nu există, le redeschide pe cele păstrate (sau una implicită).
    public func showAnalysisWindows() {
        if !analysisPanels.isEmpty || dashboardPanel != nil { analysisPanels.values.forEach { $0.orderFront(nil); Self.recover($0) }; dashboardPanel.map { $0.orderFront(nil); Self.recover($0) }; return }
        let s = saved(); if s.isEmpty && !UserDefaults.standard.bool(forKey: "gdcpa.analysis.dashboardOpen") { openAnalysisWindow(AnalysisViewSpec(mode: .clipping)); return }
        s.forEach { openAnalysisWindow($0) }; if UserDefaults.standard.bool(forKey: "gdcpa.analysis.dashboardOpen") { openAnalysisDashboard() }
    }
    /// «Închide toate analizele»: închide ferestrele de analiză și tabloul; configurația rămâne păstrată pentru «Arată ferestrele de analiză».
    public func closeAllAnalyses() {
        closingAll = true; let wasDash = dashboardPanel != nil
        analysisPanels.values.forEach { $0.close() }; dashboardPanel?.close(); closingAll = false
        UserDefaults.standard.set(wasDash, forKey: "gdcpa.analysis.dashboardOpen")
    }
    public var analysisWindowCount: Int { analysisPanels.count + (dashboardPanel == nil ? 0 : 1) }
    public func openAnalysisDashboard() {
        guard let ed = ed else { return }
        if let p = dashboardPanel { p.makeKeyAndOrderFront(nil); Self.recover(p); return }
        ed.analysisHub.loadDashboard()
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: 980, height: 640)), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = L("Tablou de analize"); p.isReleasedWhenClosed = false; p.delegate = self; p.becomesKeyOnlyIfNeeded = true; p.minSize = NSSize(width: 340, height: 300)
        p.contentView = NSHostingView(rootView: AnalysisDashboardRoot(hub: ed.analysisHub, ed: ed))
        if !p.setFrameUsingName("gdcpa.float.dashboard") { p.center() }
        p.setFrameAutosaveName("gdcpa.float.dashboard"); applyLevel(p); Self.recover(p); dashboardPanel = p; UserDefaults.standard.set(true, forKey: "gdcpa.analysis.dashboardOpen"); p.orderFront(nil); objectWillChange.send()
    }
    func handleAnalysisClose(_ w: NSPanel) -> Bool {
        if let id = analysisPanels.first(where: { $0.value === w })?.key {
            analysisPanels[id] = nil; titleSubs[id] = nil; analysisSlots[id] = nil
            if let v = analysisViews[id] { ed?.analysisHub.unregister(v) }
            if !closingAll { analysisViews[id] = nil; persistWindows() } else { analysisViews[id] = nil }
            retitleAnalysisWindows(); objectWillChange.send(); return true
        }
        if w === dashboardPanel { dashboardPanel = nil; ed?.analysisHub.unloadDashboard(); if !closingAll { UserDefaults.standard.set(false, forKey: "gdcpa.analysis.dashboardOpen") }; objectWillChange.send(); return true }
        return false
    }
    /// Titlu care identifică analiza; dacă există mai multe ferestre cu aceeași analiză, se numerotează (1), (2)… după ordinea deschiderii.
    func retitleAnalysisWindows() {
        let ordered = analysisPanels.keys.sorted { (analysisSlots[$0] ?? 0) < (analysisSlots[$1] ?? 0) }
        var seen: [String: Int] = [:]; let counts = Dictionary(grouping: ordered.compactMap { analysisViews[$0]?.title }, by: { $0 }).mapValues { $0.count }
        for id in ordered { guard let v = analysisViews[id], let p = analysisPanels[id] else { continue }
            if (counts[v.title] ?? 0) > 1 { seen[v.title, default: 0] += 1; p.title = v.title + " (\(seen[v.title]!))" } else { p.title = v.title } }
    }
    func applyLevel(_ p: NSPanel) { p.isFloatingPanel = keepOnTop; p.level = keepOnTop ? .floating : .normal; p.hidesOnDeactivate = keepOnTop }
    func recoverAnalysisPanels() { analysisPanels.values.forEach { Self.recover($0) }; dashboardPanel.map { Self.recover($0) } }
}
