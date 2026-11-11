import SwiftUI
import PhotoCore
import AppKit
import PhotoResolve

/// Secțiunea „Decupare și geometrie”: decupare (liberă / raport fix), rotire fină, rotire 90°, oglindire, îndreptare cu două puncte, grilă, decupare automată EXPLICITĂ a marginilor. Nedistructiv; dimensiunile finale în pixeli se arată mereu.
struct GeometryBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        let g = ed.adjustments.geometry
        Box(title: L("Decupare și geometrie"), panel: "geometry", summary: ed.adjustments.geometry.isNeutral ? nil : L("activ"), module: ed.moduleBinding("geometry"), reset: SectionReset(help: L("Resetează decuparea, rotirea și oglindirea; poți anula"), isNeutral: g.isNeutral) { ed.resetGeometry() }) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach([("free", "Liber"), ("original", "Original"), ("1:1", "1:1"), ("4:5", "4:5"), ("3:2", "3:2"), ("16:9", "16:9"), ("custom", "Personalizat")], id: \.0) { a in
                    Button { ed.setAspect(a.0) } label: { Text(a.1).lineLimit(1).frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle(active: g.aspect == a.0)).disabled(ed.current == nil || ed.engine != .own)
                }
            }
            if g.aspect == "custom" { SliderRow(label: L("Raport personalizat · lățime"), value: Binding(get: { g.customW }, set: { ed.adjustments.geometry.customW = $0; ed.setAspect("custom") }), range: 1...32, neutral: 3, fmt: "%.1f"); SliderRow(label: L("Raport personalizat · înălțime"), value: Binding(get: { g.customH }, set: { ed.adjustments.geometry.customH = $0; ed.setAspect("custom") }), range: 1...32, neutral: 2, fmt: "%.1f") }
            HStack(spacing: 6) {
                Button { if ed.geometryMode == .crop { ed.finishEditing() } else if g.crop == CropRect() { ed.selectTool(.geometry); ed.geometryMode = .crop; ed.guidesHidden = false } else { ed.editCrop() } } label: { Label(ed.geometryMode == .crop ? L("Gata") : (g.crop == CropRect() ? L("Decupează") : L("Editează decuparea")), systemImage: ed.geometryMode == .crop ? "checkmark" : "crop").lineLimit(1) }.buttonStyle(SoftButtonStyle(active: ed.geometryMode == .crop)).disabled(ed.current == nil || ed.engine != .own).help(L("Arată cadrul întreg cu suprapunerea de decupare: trage cadrul sau mânerele"))
                Button { ed.swapAspectOrientation() } label: { Label(L("Orientare"), systemImage: "arrow.left.arrow.right").lineLimit(1) }.buttonStyle(SoftButtonStyle()).disabled(g.aspect == "free" || g.aspect == "original" || g.aspect == "1:1").help(L("Schimbă orientarea raportului (de ex. 3:2 ↔ 2:3)"))
            }
            SliderRow(label: L("Unghi de rotire"), help: "°", value: Binding(get: { g.angle }, set: { ed.adjustments.geometry.angle = $0; ed.pulseGrid() }), range: -45...45, neutral: 0, fmt: "%+.2f")
            HStack(spacing: 6) {
                Button { ed.rotate90(-1) } label: { Image(systemName: "rotate.left") }.buttonStyle(SoftButtonStyle()).help(L("Rotire 90° antiorar")).disabled(ed.current == nil)
                Button { ed.rotate90(1) } label: { Image(systemName: "rotate.right") }.buttonStyle(SoftButtonStyle()).help(L("Rotire 90° orar")).disabled(ed.current == nil)
                Button { ed.flip(h: true) } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }.buttonStyle(SoftButtonStyle(active: g.flipH)).help(L("Oglindire orizontală")).disabled(ed.current == nil)
                Button { ed.flip(h: false) } label: { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }.buttonStyle(SoftButtonStyle(active: g.flipV)).help(L("Oglindire verticală")).disabled(ed.current == nil)
            }
            HStack(spacing: 6) {
                Button { ed.straightenPoints = []; if ed.geometryMode == .straighten { ed.finishEditing() } else { ed.selectTool(.geometry); ed.geometryMode = .straighten; ed.guidesHidden = false } } label: { Label(L("Îndreaptă (2 puncte)"), systemImage: "level").lineLimit(1) }.buttonStyle(SoftButtonStyle(active: ed.geometryMode == .straighten)).disabled(ed.current == nil || ed.engine != .own).help(L("Apasă două puncte pe o linie care trebuie să devină orizontală sau verticală"))
                Toggle(L("Grilă"), isOn: $ed.showGrid).toggleStyle(.switch).controlSize(.small).font(Theme.f(12.5))
            }
            Text(L("Perspectivă și cadrare")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
            SliderRow(label: L("Corecție verticală"), value: Binding(get: { g.keystoneV }, set: { ed.adjustments.geometry.keystoneV = $0; ed.pulseGrid() }), range: -100...100, neutral: 0, fmt: "%+.0f")
            SliderRow(label: L("Corecție orizontală"), value: Binding(get: { g.keystoneH }, set: { ed.adjustments.geometry.keystoneH = $0; ed.pulseGrid() }), range: -100...100, neutral: 0, fmt: "%+.0f")
            SliderRow(label: L("Scară"), value: Binding(get: { g.scale }, set: { ed.adjustments.geometry.scale = $0 }), range: 0.5...2, neutral: 1, fmt: "%.3f")
            SliderRow(label: L("Deplasare orizontală"), value: Binding(get: { g.shiftX }, set: { ed.adjustments.geometry.shiftX = $0 }), range: -0.5...0.5, neutral: 0, fmt: "%+.3f")
            SliderRow(label: L("Deplasare verticală"), value: Binding(get: { g.shiftY }, set: { ed.adjustments.geometry.shiftY = $0 }), range: -0.5...0.5, neutral: 0, fmt: "%+.3f")
            Button { ed.resetPerspective() } label: { Text(L("Resetează perspectiva")).lineLimit(1) }.buttonStyle(SoftButtonStyle()).disabled(g.isPerspectiveNeutral)
            let empty = ed.sourceSize.width > 0 ? g.emptyFraction(srcW: Int(ed.sourceSize.width), srcH: Int(ed.sourceSize.height)) : 0
            if empty > 0.0005 { Text(LF("Marginile goale rămân (%@% din cadru): rotirea fină le lasă; nu se umple nimic. «Decupare automată» le elimină, explicit.", String(format: "%.1f", empty * 100))).font(Theme.f(11)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
            Button { ed.autoCropEdges() } label: { Label(L("Decupare automată a marginilor"), systemImage: "crop.rotate").lineLimit(1) }.buttonStyle(SoftButtonStyle()).disabled(g.angle == 0 || ed.current == nil)
            if let f = ed.finalPixelSize { Text(LF("Dimensiune finală: %@ × %@ px%@", f.w, f.h, ed.fullResolutionIsCurrent ? "" : L(" (estimare din previzualizare)"))).font(Theme.f(12, weight: .semibold, design: .monospaced)).foregroundColor(Theme.text) }
            Details { Text(L("Ordine: rotire 90° → oglindire → rotire fină → decupare, cu o singură reeșantionare. Măștile rămân pe aceeași zonă a fotografiei. Nedistructiv: originalul nu se atinge; previzualizarea și exportul au același cadru. În «Continuă în Resolve» geometria se aplică în intermediar (fișier marcat «GEO»), nu se aplică a doua oară și nu e editabilă în Resolve.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Grilă de compoziție (treimi) sau fină (în timpul îndreptării) peste dreptunghiul dat.
struct GridOverlay: View {
    let rect: CGRect; var fine = false
    var body: some View {
        Path { p in let n = fine ? 12 : 3; for i in 1..<n { let x = rect.minX + rect.width * CGFloat(i) / CGFloat(n), y = rect.minY + rect.height * CGFloat(i) / CGFloat(n); p.move(to: CGPoint(x: x, y: rect.minY)); p.addLine(to: CGPoint(x: x, y: rect.maxY)); p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y)) } }
            .stroke(Color.white.opacity(fine ? 0.35 : 0.55), lineWidth: 0.8).allowsHitTesting(false)
    }
}

/// Suprapunerea de decupare (pe cadrul întreg S′): cadru mutabil/redimensionabil, treimi, raport fix; gesturile lucrează cu deplasarea față de începutul gestului.
struct CropOverlay: View {
    @ObservedObject var ed: EditingModel; let r: CGRect
    @State private var snap: CropRect?
    var body: some View {
        let c = ed.adjustments.geometry.crop; let rc = CGRect(x: r.minX + c.x * r.width, y: r.minY + c.y * r.height, width: c.w * r.width, height: c.h * r.height)
        ZStack {
            Path { p in p.addRect(r); p.addRect(rc) }.fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true)).allowsHitTesting(false)
            Rectangle().stroke(Color.white, lineWidth: 1.5).frame(width: rc.width, height: rc.height).position(x: rc.midX, y: rc.midY).allowsHitTesting(false)
            GridOverlay(rect: rc)
            Rectangle().fill(Color.white.opacity(0.001)).frame(width: rc.width, height: rc.height).position(x: rc.midX, y: rc.midY)
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("crop")).onChanged { v in
                    if snap == nil { snap = ed.adjustments.geometry.crop }; guard let s = snap else { return }
                    var n = s; n.x = min(1 - s.w, max(0, s.x + Double((v.location.x - v.startLocation.x) / r.width))); n.y = min(1 - s.h, max(0, s.y + Double((v.location.y - v.startLocation.y) / r.height))); ed.adjustments.geometry.crop = n }.onEnded { _ in snap = nil })
            ForEach(0..<8, id: \.self) { i in
                let hx = [-1, 0, 1, -1, 1, -1, 0, 1][i], hy = [-1, -1, -1, 0, 0, 1, 1, 1][i]
                let pos = CGPoint(x: rc.minX + rc.width * CGFloat(hx + 1) / 2, y: rc.minY + rc.height * CGFloat(hy + 1) / 2)
                ZStack { Rectangle().fill(Color.white).frame(width: 11, height: 11).shadow(radius: 2) }.frame(width: 30, height: 30).contentShape(Rectangle()).position(pos)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("crop")).onChanged { v in
                        if snap == nil { snap = ed.adjustments.geometry.crop }; guard let s = snap else { return }
                        ed.adjustments.geometry.crop = resized(s, hx, hy, Double((v.location.x - v.startLocation.x) / r.width), Double((v.location.y - v.startLocation.y) / r.height)) }.onEnded { _ in snap = nil })
            }
            Text("\(finalText)").font(Theme.f(11, weight: .semibold, design: .monospaced)).foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Color.black.opacity(0.6)).position(x: rc.midX, y: max(r.minY + 12, rc.minY - 12)).allowsHitTesting(false)
        }.coordinateSpace(name: "crop")
    }
    var finalText: String { ed.finalPixelSize.map { "\($0.w) × \($0.h) px" } ?? "" }
    func resized(_ s: CropRect, _ hx: Int, _ hy: Int, _ dx: Double, _ dy: Double) -> CropRect {
        var x0 = s.x, x1 = s.x + s.w, y0 = s.y, y1 = s.y + s.h
        if hx < 0 { x0 += dx } else if hx > 0 { x1 += dx }; if hy < 0 { y0 += dy } else if hy > 0 { y1 += dy }
        x0 = min(max(0, x0), x1 - 0.02); x1 = max(min(1, x1), x0 + 0.02); y0 = min(max(0, y0), y1 - 0.02); y1 = max(min(1, y1), y0 + 0.02)
        var w = x1 - x0, h = y1 - y0
        let o = ed.orientedSize
        if let ar = ed.aspectValue(ed.adjustments.geometry), o.width > 0 {   // raport fix în PIXELI: (w·W′)/(h·H′) = ar
            let k = ar * Double(o.height / o.width)                          // w/h normalizat = k
            if hy == 0 { h = w / k } else if hx == 0 { w = h * k } else { h = w / k }
            if hx < 0 { x0 = x1 - w } else if hx > 0 { x1 = x0 + w } else { let cx = (x0 + x1) / 2; x0 = cx - w / 2; x1 = cx + w / 2 }
            if hy < 0 { y0 = y1 - h } else if hy > 0 { y1 = y0 + h } else { let cy = (y0 + y1) / 2; y0 = cy - h / 2; y1 = cy + h / 2 }
            if x0 < 0 { let sc = (x1 - 0) / (x1 - x0); x0 = 0; w = x1 * 1; h = w / k; _ = sc }
            x0 = max(0, x0); x1 = min(1, x1); w = x1 - x0; h = w / k; if hy < 0 { y0 = y1 - h } else { y1 = y0 + h }
            if y0 < 0 { y0 = 0; h = y1; w = h * k; if hx < 0 { x0 = x1 - w } else { x1 = x0 + w } }; if y1 > 1 { y1 = 1; h = y1 - y0; w = h * k; if hx < 0 { x0 = x1 - w } else { x1 = x0 + w } }
        }
        return CropRect(x: max(0, x0), y: max(0, y0), w: max(0.02, min(1, x1) - max(0, x0)), h: max(0.02, min(1, y1) - max(0, y0)))
    }
}

/// Îndreptare cu două puncte: primul click = capătul 1, al doilea = capătul 2; linia devine orizontală/verticală (rotirea cea mai mică), cu grilă fină vizibilă.
struct StraightenOverlay: View {
    @ObservedObject var ed: EditingModel; let r: CGRect
    var body: some View {
        ZStack {
            GridOverlay(rect: r, fine: true)
            Color.clear.frame(width: r.width, height: r.height).contentShape(Rectangle()).toolCursor(.draw).position(x: r.midX, y: r.midY)
                .gesture(SpatialTapGesture().onEnded { t in
                    guard ed.viewer.accepts(canvasPoint: t.location) else { return }
                    let n = CGPoint(x: (t.location.x - r.minX) / r.width, y: (t.location.y - r.minY) / r.height)
                    if ed.straightenPoints.count >= 1 { let a = ed.straightenPoints[0]; ed.straighten(from: a, to: n, imageSize: r.size); ed.straightenPoints = []; ed.geometryMode = .none } else { ed.straightenPoints = [n] } })
            ForEach(Array(ed.straightenPoints.enumerated()), id: \.offset) { _, p in Circle().stroke(Color.yellow, lineWidth: 2).frame(width: 14, height: 14).position(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height).allowsHitTesting(false) }
            Text(ed.straightenPoints.isEmpty ? L("Îndreptare: apasă primul punct al liniei") : L("Apasă al doilea punct al liniei")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(.black).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.yellow)).position(x: r.midX, y: r.minY + 20).allowsHitTesting(false)
        }
    }
}

/// Bara comună a interacțiunii în curs (geometrie sau măști): numele uneltei, «Gata» (încheie editarea; rezultatul și măștile rămân, dispar doar ghidajele uneltei) și «Ascunde ghidajele» (vizibilitate, fără a schimba rezultatul sau unealta).
struct ToolActionBar: View {
    @ObservedObject var ed: EditingModel
    var label: String? {
        if ed.activeTool == .chart { return L("Chart de culoare") }
        if ed.activeTool == .retouch { return L("Retuș") }
        if ed.geometryMode == .crop { return L("Decupare") }; if ed.geometryMode == .straighten { return L("Îndreptare") }
        if ed.activeTool == .masks, ed.localIndex(ed.selectedLocal) != nil { switch ed.maskTool { case .drawPath: return L("Contur"); case .brushAdd: return L("Pensulă · adaugă"); case .brushErase: return L("Pensulă · șterge"); case .select: return L("Mască") } }
        return nil
    }
    var body: some View {
        if ed.compare != .camera, let l = label {
            VStack { HStack(spacing: 6) {
                Text(ed.activeTool == .chart ? l : "Editezi: \(l)").font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.text)
                if ed.activeTool == .chart && ed.compare == .after { Text(L("Opacitate")).font(Theme.f(11.5)).foregroundColor(Theme.muted); Slider(value: $ed.chartOverlayOpacity, in: 0...1).controlSize(.small).frame(width: Theme.px(110)).tint(Theme.accent); Text("\(Int((ed.chartOverlayOpacity * 100).rounded()))%").font(Theme.f(11.5, design: .monospaced)).foregroundColor(Theme.text).frame(minWidth: Theme.px(38), alignment: .trailing) }
                Button { ed.guidesHidden.toggle() } label: { Label(ed.guidesHidden ? L("Arată ghidajele") : L("Ascunde ghidajele"), systemImage: ed.guidesHidden ? "eye" : "eye.slash").lineLimit(1) }.buttonStyle(SoftButtonStyle(active: ed.guidesHidden))
                Button { ed.finishEditing(); ed.activeTool = .view } label: { Label(L("Gata"), systemImage: "checkmark").lineLimit(1) }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.return, modifiers: []).help(L("Încheie editarea: rezultatul rămâne aplicat, ghidajele dispar (Enter)"))
            }.padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.6))).padding(10); Spacer() }.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
