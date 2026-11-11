import SwiftUI
import AppKit
import PhotoCore

extension EditingModel {
    /// Dreptunghiul lupei în coordonate normalizate ale imaginii de ieșire: dimensiunea panoului în pixeli fizici împărțită la mărire (1 = 100% = un pixel al imaginii la un pixel fizic).
    var loupeRectNorm: CGRect {
        let back = viewer.backing; let full = detailAfter?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { CGSize(width: $0.width, height: $0.height) } ?? viewer.fullSize
        guard full.width > 0, full.height > 0 else { return .zero }
        let w = min(1, loupeViewPts.width * back / loupeMag / full.width), h = min(1, loupeViewPts.height * back / loupeMag / full.height)
        let cx = min(1 - w / 2, max(w / 2, loupeCenter.x)), cy = min(1 - h / 2, max(h / 2, loupeCenter.y))
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }
    /// Ținte alese EXPLICIT din analiza de fețe existentă (rezultate din catalog). Nu există urmărire între cadre: la schimbarea fotografiei selecția se pierde.
    func loupeTargets() -> [(label: String, center: CGPoint)] {
        guard let p = current, faceFrameVerdict[p.id]?.isOK == true, let r = catalog.faceResult(for: p), sourceSize.width > 0 else { return [] }
        let map = GeoMap(r: CGRect(x: 0, y: 0, width: 1, height: 1), geo: adjustments.geometry, source: sourceSize, effects: adjustments.effects)
        func c(_ b: [Double]) -> CGPoint { map.fwd(b[0] + b[2] / 2, b[1] + b[3] / 2) }
        var out: [(String, CGPoint)] = []
        for (i, f) in r.faces.enumerated() {
            out.append((LF("Față %@", i + 1), c(f.box)))
            if let e = f.left { out.append((LF("Față %@ · ochi stâng", i + 1), c(e.box))) }
            if let e = f.right { out.append((LF("Față %@ · ochi drept", i + 1), c(e.box))) }
        }
        return out
    }
    func loupeSetCenter(_ n: CGPoint) { loupeCenter = CGPoint(x: min(1, max(0, n.x)), y: min(1, max(0, n.y))) }
}

/// Conținutul lupei: decupaj din rezultatul procesat la REZOLUȚIE PLINĂ (nu o previzualizare mărită). Fără rezoluție plină la zi afișează starea și o cere.
struct LoupeView: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                ZStack {
                    Color.black
                    if ed.fullResolutionIsCurrent, let img = ed.loupeBase ? (ed.detailBase ?? ed.detailAfter) : ed.detailAfter, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let back = ed.viewer.backing; let w = Int((g.size.width * back / ed.loupeMag).rounded()), h = Int((g.size.height * back / ed.loupeMag).rounded())
                        let cw = min(cg.width, max(8, w)), ch = min(cg.height, max(8, h))
                        let x = min(cg.width - cw, max(0, Int(ed.loupeCenter.x * Double(cg.width)) - cw / 2)), y = min(cg.height - ch, max(0, Int(ed.loupeCenter.y * Double(cg.height)) - ch / 2))
                        if let crop = cg.cropping(to: CGRect(x: x, y: y, width: cw, height: ch)) {
                            Image(decorative: crop, scale: back / ed.loupeMag).interpolation(.none).frame(width: g.size.width, height: g.size.height)
                        }
                    } else {
                        VStack(spacing: 6) { ProgressView(); Text(ed.detailError.isEmpty ? L("Se încarcă rezoluția plină…") : ed.detailError).font(Theme.f(11.5)).foregroundColor(Theme.muted) }
                    }
                }.frame(width: g.size.width, height: g.size.height).clipped()
                .onAppear { sizeChanged(g.size) }.onChange(of: g.size) { sizeChanged($0) }
            }
            HStack(spacing: 6) {
                Text(percentLabel).font(Theme.f(11.5, weight: .semibold, design: .monospaced))
                Text(ed.loupeTarget.isEmpty ? L("zonă manuală") : ed.loupeTarget).font(Theme.f(11)).foregroundColor(Theme.muted).lineLimit(1)
                Spacer(); FloatFooter(kind: .loupe)
            }
        }.padding(8).frame(minWidth: 220, minHeight: 180).background(Theme.panel).foregroundColor(Theme.text)
        .onAppear { ed.requestFullResolution() }.onChange(of: ed.fullResolutionIsCurrent) { if !$0 { ed.requestFullResolution() } }
    }
    var percentLabel: String { "\(Int((ed.loupeMag * 100).rounded()))%" }
    func sizeChanged(_ s: CGSize) { DispatchQueue.main.async { if s.width > 20, s.height > 20 { ed.loupeViewPts = s } } }
}

/// Dreptunghiul lupei pe fotografie. Interactiv doar cu unealta Deplasare/Analiză (nu interferează cu masca, chartul sau decuparea); Space+tragere și rotița rămân ale vederii.
struct LoupeOverlay: View {
    @ObservedObject var ed: EditingModel; @ObservedObject var v: ViewerState; let r: CGRect
    var body: some View {
        let n = ed.loupeRectNorm; let canMove = ed.activeTool == .view || ed.activeTool == .analysis
        ZStack {
            if n.width > 0 {
                let rect = CGRect(x: r.minX + n.minX * r.width, y: r.minY + n.minY * r.height, width: n.width * r.width, height: n.height * r.height)
                Rectangle().stroke(Color.black.opacity(0.7), lineWidth: 3).frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY).allowsHitTesting(false)
                Rectangle().stroke(Theme.check, lineWidth: 1.5).frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY).allowsHitTesting(false)
                Rectangle().fill(Color.white.opacity(0.001)).frame(width: max(rect.width, 24), height: max(rect.height, 24)).position(x: rect.midX, y: rect.midY).allowsHitTesting(canMove && !v.spaceDown && !v.panning)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { d in ed.loupeFollow = false; ed.loupeTarget = ""; ed.loupeSetCenter(v.normalized(d.location)) })
                    .help(L("Trage dreptunghiul pentru a muta zona inspectată"))
            }
            if ed.loupeFollow { LoupeHover(ed: ed, v: v).allowsHitTesting(false) }
        }.frame(width: v.canvasSize.width, height: v.canvasSize.height)
    }
}
/// Urmărirea cursorului (opțională, doar când e cerută explicit): centrează lupa pe punctul de sub cursor.
struct LoupeHover: NSViewRepresentable {
    let ed: EditingModel; let v: ViewerState
    func makeNSView(context: Context) -> NSView { let n = HoverView(); n.ed = ed; n.v = v; return n }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class HoverView: NSView {
        weak var ed: EditingModel?; var v: ViewerState?; private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            guard let w = window else { return }; w.acceptsMouseMovedEvents = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in
                guard let self = self, let v = self.v, let ed = self.ed, e.window === self.window else { return e }
                let p = self.convert(e.locationInWindow, from: nil); if self.bounds.contains(p) { MainActor.assumeIsolated { ed.loupeSetCenter(v.normalized(p)); ed.loupeTarget = L("urmărește cursorul") } }; return e }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

/// Secțiunea «Lupă» din inspector: pornire, mărire, urmărire/fixare, ținte din analiza de fețe (selecție explicită), desprindere în fereastră.
struct LoupeBox: View {
    @ObservedObject var ed: EditingModel; @EnvironmentObject var fp: FloatingPanels; @EnvironmentObject var store: ImageStore
    var body: some View {
        Box(title: L("Lupă de inspecție (nu se exportă)"), panel: "loupe", summary: ed.loupeOn ? "\(Int((ed.loupeMag * 100).rounded()))%" : nil) {
            Toggle(L("Arată lupa"), isOn: $ed.loupeOn).toggleStyle(.switch).controlSize(.small).font(Theme.f(12.5)).disabled(ed.current == nil)
                .onChange(of: ed.loupeOn) { on in if on { ed.requestFullResolution() } else { fp.attach(.loupe) } }
            if ed.loupeOn {
                HStack(spacing: 6) { Text(L("Mărire")).font(Theme.f(12)); Segmented(options: [(CGFloat(1), "100%"), (2, "200%"), (3, "300%"), (4, "400%")], selection: $ed.loupeMag) }
                Text(L("100% = un pixel al imaginii la un pixel fizic, din rezultatul procesat la rezoluție plină.")).font(Theme.f(10.5)).foregroundColor(Theme.faint)
                HStack(spacing: 6) {
                    Button { ed.loupeFollow.toggle(); if ed.loupeFollow { ed.loupeTarget = "urmărește cursorul" } } label: { Label(ed.loupeFollow ? L("Fixează zona") : L("Urmărește cursorul"), systemImage: ed.loupeFollow ? "pin" : "cursorarrow.motionlines").lineLimit(1) }.buttonStyle(SoftButtonStyle(active: ed.loupeFollow))
                    Button { ed.loupeBase.toggle() } label: { Text(ed.loupeBase ? L("Bază") : L("După")) }.buttonStyle(SoftButtonStyle()).help(L("Comută între rezultat și bază în lupă"))
                    Button { fp.toggle(.loupe) } label: { Label(fp.isDetached(.loupe) ? L("Revino în inspector") : L("Fereastră separată"), systemImage: "macwindow.on.rectangle").lineLimit(1) }.buttonStyle(SoftButtonStyle(active: fp.isDetached(.loupe)))
                }
                let targets = ed.loupeTargets()
                if let p = ed.current, let v = ed.faceFrameVerdict[p.id], !v.isOK { Text(v.message).font(Theme.f(10.5)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
                Menu(L("Ținte din analiza de fețe")) { if targets.isEmpty { Text(L("Nicio față analizată pentru acest cadru")) } else { ForEach(Array(targets.enumerated()), id: \.offset) { _, t in Button(t.label) { ed.loupeFollow = false; ed.loupeTarget = t.label; ed.loupeSetCenter(t.center) } } } }.fixedSize()
                Text(L("Selecție explicită: la schimbarea cadrului nu se presupune aceeași persoană sau același ochi (corespondența nu e demonstrată). Fără detecție, lupa manuală funcționează oricum: trage dreptunghiul pe fotografie.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                Color.clear.frame(height: 0).task(id: ed.current?.id) { if let p = ed.current, ed.catalog.faceResult(for: p) != nil { await ed.verifyFaceFrame(preview: await store.image(for: p, kind: .view)) } }
                if !fp.isDetached(.loupe) { LoupeView(ed: ed).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 6)) }
                else { Text(L("Lupa este în fereastra separată.")).font(Theme.f(11)).foregroundColor(Theme.muted) }
            }
        }
    }
}
