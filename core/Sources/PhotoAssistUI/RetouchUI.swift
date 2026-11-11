import SwiftUI
import PhotoCore
import PhotoResolve

/// Retuș punctual (clone / vindecare): panoul din inspector + ghidajele de pe imagine. Operațiile se salvează cu reglajele fotografiei, apar în Bază/După (baza nu le conține), se exportă și se integrează în predarea BAKED.
struct RetouchBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        let spots = ed.adjustments.retouch
        Box(title: L("Retuș (clonă și vindecare)"), panel: "retouch", summary: spots.isEmpty ? nil : "\(spots.filter { $0.enabled }.count) active", module: ed.moduleBinding("retouch"),
            reset: SectionReset(help: L("Șterge toate retușurile fotografiei; poți anula"), isNeutral: spots.isEmpty) { ed.resetSection(L("Retuș")) { $0.retouch = [] } }) {
            Button { ed.selectTool(.retouch) } label: { Label(ed.activeTool == .retouch ? L("Apasă pe imagine pentru a pune un punct") : L("Pune puncte pe imagine"), systemImage: "bandage").lineLimit(1) }.buttonStyle(ed.activeTool == .retouch ? SoftButtonStyle(active: true) : SoftButtonStyle()).disabled(ed.current == nil || ed.engine != .own)
            HStack(spacing: 10) {
                Button { ed.undoRetouch() } label: { Label(L("Anulează"), systemImage: "arrow.uturn.backward").lineLimit(1) }.buttonStyle(.plain).disabled(ed.retouchUndo.isEmpty).foregroundColor(ed.retouchUndo.isEmpty ? Theme.faint : Theme.muted).help(L("Anulează ultima schimbare de retuș"))
                Button { ed.redoRetouch() } label: { Label(L("Refă"), systemImage: "arrow.uturn.forward").lineLimit(1) }.buttonStyle(.plain).disabled(ed.retouchRedo.isEmpty).foregroundColor(ed.retouchRedo.isEmpty ? Theme.faint : Theme.muted).help(L("Refă schimbarea anulată"))
                Spacer(minLength: 0) }.font(Theme.f(11.5))
            HStack(spacing: 8) { Text(L("Mod nou")).font(Theme.f(11.5)).foregroundColor(Theme.muted)
                Picker("", selection: $ed.retouchNewMode) { ForEach(RetouchSpot.Mode.allCases, id: \.rawValue) { Text($0.label).tag($0) } }.pickerStyle(.segmented).labelsHidden().controlSize(.small) }
            SliderRow(label: L("Rază implicită"), help: L("‰ din înălțime"), value: Binding(get: { ed.retouchNewRadius * 1000 }, set: { ed.retouchNewRadius = $0 / 1000 }), range: 4...80, neutral: 20, fmt: "%.0f")
            if ed.retouchNewMode == .redEye { Text(L("Ochi roșii: pune cercul peste pupilă. Se corectează doar pixelii puternic roșii (manual, nu detecție automată); iris, piele și reflexe rămân. Ajustează raza și intensitatea.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
            if spots.isEmpty { Text(L("Niciun punct. Alege «Pune puncte», apasă pe un fir de praf sau pe un defect; sursa (cerc întrerupt) se trage pe o zonă curată.")).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            ForEach(Array(spots.enumerated()), id: \.element.id) { i, sp in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Button { ed.adjustments.retouch[i].enabled.toggle() } label: { MiniSwitch(on: sp.enabled) }.buttonStyle(.plain).accessibilityLabel("Punct \(i + 1): \(sp.enabled ? L("activ") : L("dezactivat"))")
                        Button { ed.selectedRetouch = sp.id; ed.selectTool(.retouch) } label: { Text(LF("Punct %@", i + 1)).font(Theme.f(12, weight: ed.selectedRetouch == sp.id ? .semibold : .regular)).foregroundColor(ed.selectedRetouch == sp.id ? Theme.accent : Theme.text) }.buttonStyle(.plain)
                        Spacer(minLength: 4)
                        Picker("", selection: Binding(get: { sp.mode }, set: { ed.adjustments.retouch[i].mode = $0 })) { ForEach(RetouchSpot.Mode.allCases, id: \.rawValue) { Text($0.label).tag($0) } }.pickerStyle(.segmented).labelsHidden().controlSize(.mini).frame(width: Theme.px(130))
                        Button { ed.resetSection("Retuș") { $0.retouch.removeAll { $0.id == sp.id } } } label: { Image(systemName: "trash").font(Theme.f(11)) }.buttonStyle(.plain).foregroundColor(Theme.faint).help(L("Șterge punctul"))
                    }
                    SliderRow(label: L("Rază"), help: "‰", value: Binding(get: { sp.radius * 1000 }, set: { ed.adjustments.retouch[i].radius = $0 / 1000 }), range: 4...80, neutral: 20, fmt: "%.0f")
                    if sp.mode == .redEye { SliderRow(label: L("Intensitate"), value: Binding(get: { sp.strength ?? 1 }, set: { ed.adjustments.retouch[i].strength = $0 }), range: 0...1, neutral: 1, fmt: "%.2f") }
                    SliderRow(label: L("Margine moale"), value: Binding(get: { sp.feather }, set: { ed.adjustments.retouch[i].feather = $0 }), range: 0...1, neutral: 0.5, fmt: "%.2f")
                }.padding(.vertical, 2)
            }
            Details { VStack(alignment: .leading, spacing: 4) {
                Text(L("Clonă: copiază zona-sursă peste destinație, cu margine moale. Vindecare: copiază sursa potrivind iluminarea (raportul mediilor pe inelul din jurul destinației), apoi amestecă moale. Retușul se aplică pe imaginea liniară înaintea oricărui instrument și a geometriei, deci rămâne corect la decupare/rotire și la orice rezoluție (raza e fracție din înălțime).")).font(Theme.f(11)).foregroundColor(Theme.faint)
                Text(L("Nu există detecție automată de praf/obiecte (ar cere ML; ML e permis doar pentru culling). Retușurile se integrează în predarea «BAKED» către Resolve; la «fără corecții locale» se pierd explicit.")).font(Theme.f(11)).foregroundColor(Theme.faint)
            }.fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct RetouchOverlay: View {
    @ObservedObject var ed: EditingModel; let r: CGRect
    var body: some View {
        let m = GeoMap(r: CGRect(x: 0, y: 0, width: r.width, height: r.height), geo: ed.adjustments.geometry, source: ed.sourceSize, effects: ed.adjustments.effective.effects)
        ZStack {
            Color.clear.contentShape(Rectangle()).frame(width: r.width, height: r.height)
                .gesture(SpatialTapGesture().onEnded { v in guard ed.viewer.accepts(v.location, in: r) else { return }; let p = m.inv(v.location); if p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1 { ed.addRetouch(nx: Double(p.x), ny: Double(p.y)) } })
                .onHover { inside in if inside { NSCursor.crosshair.set() } else { NSCursor.arrow.set() } }
            ForEach(ed.adjustments.retouch) { sp in
                let d = m.fwd(sp.x, sp.y), s = m.fwd(sp.sx, sp.sy); let rad = max(6, CGFloat(sp.radius) * r.height); let sel = ed.selectedRetouch == sp.id
                ZStack {
                    if sp.mode != .redEye { Path { p in p.move(to: d); p.addLine(to: s) }.stroke(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
                    Circle().stroke(Color.black.opacity(0.5), lineWidth: 3).frame(width: rad * 2, height: rad * 2).position(d)
                    Circle().stroke(sp.enabled ? (sel ? Theme.accent : Color.white) : Theme.faint, lineWidth: 1.5).frame(width: rad * 2, height: rad * 2).contentShape(Circle()).position(d)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in ed.selectedRetouch = sp.id; if let i = ed.adjustments.retouch.firstIndex(where: { $0.id == sp.id }) { let q = m.inv(v.location); ed.adjustments.retouch[i].x = min(1, max(0, Double(q.x))); ed.adjustments.retouch[i].y = min(1, max(0, Double(q.y))) } })
                    if sp.mode != .redEye {
                    Circle().stroke(Color.black.opacity(0.5), lineWidth: 3).frame(width: rad * 2, height: rad * 2).position(s)
                    Circle().stroke(sp.enabled ? (sel ? Theme.accent : Color.white.opacity(0.85)) : Theme.faint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(width: rad * 2, height: rad * 2).contentShape(Circle()).position(s)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in ed.selectedRetouch = sp.id; if let i = ed.adjustments.retouch.firstIndex(where: { $0.id == sp.id }) { let q = m.inv(v.location); ed.adjustments.retouch[i].sx = min(1, max(0, Double(q.x))); ed.adjustments.retouch[i].sy = min(1, max(0, Double(q.y))) } })
                    }
                }
            }
        }.frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
    }
}
