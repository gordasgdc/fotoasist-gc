import SwiftUI
import AppKit
import PhotoResolve
import PhotoCore

/// Panoul „Corecții locale”: o corecție = o MASCĂ (componente care adaugă sau scad: elipsă rotită, degrade, contur cu puncte, pensulă) + reglajele aplicate în ea. Construirea măștii e separată de reglaje. Aceleași instrumente ca cele globale, fiecare în domeniul lui; transformarea finală se aplică o singură dată, după toate corecțiile.
struct LocalCorrectionsBox: View {
    @ObservedObject var ed: EditingModel
    @State private var addOp: MaskOp = .add
    var body: some View {
        Box(title: L("Corecții locale"), panel: "locals", summary: ed.adjustments.locals.isEmpty ? nil : "\(ed.adjustments.locals.count)") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(ZoneKind.allCases, id: \.rawValue) { k in
                    Button { ed.addLocal(k) } label: { Label(k.label, systemImage: "plus.circle").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(SoftButtonStyle()).disabled(ed.current == nil || ed.engine != .own)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button { ed.addSubjectMask() } label: { Label(L("Subiect (Vision)"), systemImage: "person.crop.rectangle").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(SoftButtonStyle()).disabled(ed.current == nil || ed.engine != .own || ed.subjectBusy || !SubjectMask.isAvailable)
                        .help(L("Contur de prim-plan găsit local de Vision, cu puncte editabile. Nu e hartă de adâncime și nu e identificare de persoane."))
                    Button { ed.exportSubjectMatte() } label: { Label(L("Matte PNG"), systemImage: "square.and.arrow.up").lineLimit(1) }.buttonStyle(SoftButtonStyle()).disabled(ed.current == nil || ed.engine != .own || ed.subjectBusy || !SubjectMask.isAvailable)
                        .help(L("Scrie un matte PNG (alb = subiect) pentru import ca fișier în Resolve; nu creează noduri automat."))
                    if ed.subjectBusy { ProgressView().controlSize(.small) }
                }
                if !SubjectMask.isAvailable { Text(L("Selecția subiectului cere macOS 14 sau mai nou; pe această versiune folosește elipsa, conturul sau pensula.")).font(Theme.f(10.5)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
                if !ed.subjectNote.isEmpty { Text(ed.subjectNote).font(Theme.f(10.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                Text(L("Masca de subiect separă prim-planul de fundal după aspect. Nu e hartă de adâncime, nu măsoară distanța și nu simulează profunzimea de câmp.")).font(Theme.f(10)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            }
            if ed.engine != .own { Text(L("Disponibile doar cu motorul „Nucleu propriu”.")).font(Theme.f(11)).foregroundColor(Theme.check) }
            if !ed.adjustments.geometry.isNeutral { Toggle(L("Arată cadrul sursă (opțional)"), isOn: $ed.sourceFrameView).toggleStyle(.switch).controlSize(.small).font(Theme.f(12)); Text(L("Geometria (decupare/rotire/perspectivă) e activă: masca se editează direct pe fotografia transformată; sub perspectivă forma desenată e o aproximare locală, iar procesarea rămâne exactă. «Cadrul sursă» e doar o vedere opțională.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
            ForEach(ed.adjustments.locals) { l in row(l) }
            if let i = ed.localIndex(ed.selectedLocal) { editor(i) }
            else if ed.adjustments.locals.isEmpty { Text(L("Alege o formă, apoi definește zona pe fotografie. Zona e manuală (fără detecție automată), cu margine estompată, inversare, adunare și scădere de componente.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
    func icon(_ k: ZoneKind) -> String { switch k { case .ellipse: return "circle.dashed"; case .gradient: return "rectangle.bottomhalf.filled"; case .path: return "scribble.variable"; case .brush: return "paintbrush.pointed" } }
    func row(_ l: LocalCorrection) -> some View {
        HStack(spacing: 6) {
            Button { ed.selectedLocal = l.id; ed.selectedComponent = nil; ed.selectedPoint = nil; ed.maskTool = .select; ed.endMaskEdit(); ed.activeTool = .masks; ed.geometryMode = .none; ed.guidesHidden = false } label: { HStack { Image(systemName: icon(l.kind)); Text(l.name).font(Theme.f(12.5, weight: ed.selectedLocal == l.id ? .semibold : .regular)).lineLimit(1); if l.components.count > 1 { Text("\(l.components.count)").font(Theme.f(10.5)).foregroundColor(Theme.faint) }; Spacer() } }.buttonStyle(.plain)
            Button { if let i = ed.localIndex(l.id) { ed.adjustments.locals[i].enabled.toggle() } } label: { Image(systemName: l.enabled ? "eye" : "eye.slash") }.buttonStyle(.plain).help(l.enabled ? L("Corecție ACTIVĂ: efectul se aplică. Click: o dezactivează (zona și valorile se păstrează)") : L("Corecție INACTIVĂ: efectul nu se aplică. Click: o activează"))
            Button { ed.deleteLocal(l.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).help(L("Șterge corecția"))
        }.padding(.vertical, 3).padding(.horizontal, 6).background(ed.selectedLocal == l.id ? Theme.accent.opacity(0.18) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 6))
    }
    @ViewBuilder func editor(_ i: Int) -> some View {
        Divider().overlay(Theme.line)
        TextField("Nume", text: $ed.adjustments.locals[i].name).textFieldStyle(.roundedBorder).font(Theme.f(12))
        maskBuilder(i)
        // trei lucruri SEPARATE: (1) corecția activă/inactivă = ochiul din listă; (2) umplerea măștii; (3) ghidajele de editare (contur + puncte)
        Toggle(L("Arată umplerea zonei"), isOn: $ed.showZone).toggleStyle(.switch).controlSize(.small).font(Theme.f(12.5)).disabled(ed.guidesHidden).help(L("Umplere roșie translucidă peste zonă (doar în editare)"))
        Toggle(L("Inversează zona (întreaga mască)"), isOn: $ed.adjustments.locals[i].invert).toggleStyle(.switch).controlSize(.small).font(Theme.f(12.5)).help(L("Inversează masca compusă: efectul se aplică în afara ei"))
        Button { ed.guidesHidden.toggle() } label: { Label(ed.guidesHidden ? L("Editează masca") : L("Ascunde ghidajele"), systemImage: ed.guidesHidden ? "pencil.and.outline" : "eye.slash").lineLimit(1) }.buttonStyle(SoftButtonStyle()).help(ed.guidesHidden ? L("Readuce umplerea (dacă e pornită), conturul și punctele de control") : L("Ascunde umplerea, conturul și punctele; corecția rămâne activă și masca neschimbată"))
        HStack { Text(L("Ajustările corecției")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted); Spacer(minLength: 4)
            Button { ed.resetLocalAdjustments(ed.adjustments.locals[i].id) } label: { Image(systemName: "arrow.counterclockwise").font(Theme.f(11, weight: .semibold)) }.buttonStyle(.plain).foregroundColor(ed.adjustments.locals[i].adjustmentIsNeutral ? Theme.faint : Theme.accent).disabled(ed.adjustments.locals[i].adjustmentIsNeutral).help(L("Resetează ajustările corecției (masca rămâne); poți anula")) }
        SliderRow(label: L("Expunere (EV)"), help: L("Stopuri (EV)"), value: $ed.adjustments.locals[i].exposure, range: -4...4)
        SliderRow(label: L("Umbre (EV)"), help: L("Stopuri (EV)"), value: $ed.adjustments.locals[i].shadows, range: -2...2)
        SliderRow(label: L("Lumini"), help: L("Stopuri"), value: $ed.adjustments.locals[i].highlights, range: -2...2)
        SliderRow(label: L("Contrast"), value: $ed.adjustments.locals[i].contrast, range: 0.5...2, neutral: 1, fmt: "%.2f")
        SliderRow(label: L("Temperatură (mired)"), help: L("Mired"), value: $ed.adjustments.locals[i].temperature, range: -150...150, fmt: "%+.0f")
        SliderRow(label: L("Tentă"), help: L("Verde ↔ magenta"), value: $ed.adjustments.locals[i].tint, range: -0.05...0.05, fmt: "%+.3f")
        SliderRow(label: L("Saturație"), value: $ed.adjustments.locals[i].saturation, range: 0...2, neutral: 1, fmt: "%.2f")
        Details { Text(L("Se aplică după ajustările globale, doar în mască (expunerea, balansul, umbrele și luminile în domeniul liniar; contrastul și saturația în domeniul log). Transformarea finală GDC DRT → sRGB se aplică o singură dată, peste întreaga imagine. „Bază” și „Împărțit” arată comparația cu și fără corecții. Masca e definită în coordonatele fotografiei și se evaluează la fel în previzualizare și în export. Corecțiile locale rămân în FotoAsist: NU se transferă în Resolve ca obiecte editabile.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
    }

    // MARK: construirea măștii
    @ViewBuilder func maskBuilder(_ i: Int) -> some View {
        let l = ed.adjustments.locals[i]; let ci = ed.componentIndex(i)
        HStack { Text(L("Masca")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted); Spacer(minLength: 4)
            Button { ed.undoMaskEdit() } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(.plain).disabled(ed.maskUndo.isEmpty).foregroundColor(ed.maskUndo.isEmpty ? Theme.faint : Theme.accent).help(L("Anulează ultima editare a măștii (puncte, componente, tușe)")).keyboardShortcut("z", modifiers: .command)
            Button { ed.redoMaskEdit() } label: { Image(systemName: "arrow.uturn.forward") }.buttonStyle(.plain).disabled(ed.maskRedo.isEmpty).foregroundColor(ed.maskRedo.isEmpty ? Theme.faint : Theme.accent).help(L("Refă editarea de mască anulată")).keyboardShortcut("z", modifiers: [.command, .shift]) }
        ForEach(Array(l.components.enumerated()), id: \.element.id) { idx, c in
            HStack(spacing: 6) {
                if idx == 0 { Text("+").font(Theme.f(12, weight: .bold)).foregroundColor(Theme.keep).frame(width: Theme.px(18)).help(L("Zona de bază (se adaugă întotdeauna)")) }
                else { Button { ed.setComponentOp(c.id, c.op == .add ? .subtract : .add) } label: { Text(c.op == .add ? "+" : "−").font(Theme.f(13, weight: .bold)).foregroundColor(c.op == .add ? Theme.keep : Theme.reject).frame(width: Theme.px(18)) }.buttonStyle(.plain).help(c.op == .add ? L("Adaugă la mască. Click: o face scădere") : L("Scade din mască. Click: o face adăugare")) }
                Button { ed.selectComponent(c.id) } label: { HStack { Image(systemName: icon(c.kind)); Text(c.kind.label + (c.kind == .path && !c.closed ? " (deschis)" : "")).font(Theme.f(12, weight: idx == ci ? .semibold : .regular)).lineLimit(1); Spacer() } }.buttonStyle(.plain)
                if l.components.count > 1 { Button { ed.deleteComponent(c.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).help(L("Șterge componenta")) }
            }.padding(.vertical, 2).padding(.horizontal, 6).background(idx == ci ? Theme.accent.opacity(0.14) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 5))
        }
        Segmented(options: [(MaskOp.add, L("Adaugă")), (.subtract, L("Scade"))], selection: $addOp)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(ZoneKind.allCases, id: \.rawValue) { k in Button { ed.addComponent(k, op: addOp) } label: { Text((addOp == .add ? "+ " : "− ") + k.label).lineLimit(1).frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle()) }
        }
        componentTools(i, ci)
    }
    @ViewBuilder func componentTools(_ i: Int, _ ci: Int) -> some View {
        let c = ed.adjustments.locals[i].components[ci]
        switch c.kind {
        case .ellipse:
            SliderRow(label: L("Unghi elipsă"), help: "°", value: $ed.adjustments.locals[i].components[ci].rotation, range: -180...180, neutral: 0, fmt: "%+.0f")
            SliderRow(label: L("Estompare margine"), value: $ed.adjustments.locals[i].components[ci].feather, range: 0...1, neutral: 0.35, fmt: "%.2f")
            Text(L("Mutare: trage elipsa sau crucea din centru. Dimensiune: mânerele de pe axe. Rotire: mânerul separat de deasupra.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
        case .gradient:
            SliderRow(label: L("Estompare margine"), value: $ed.adjustments.locals[i].components[ci].feather, range: 0...1, neutral: 0.6, fmt: "%.2f")
        case .path:
            SliderRow(label: L("Estompare margine"), value: $ed.adjustments.locals[i].components[ci].feather, range: 0...1, neutral: 0.25, fmt: "%.2f")
            HStack(spacing: 6) {
                if c.closed { Button(L("Redeschide")) { ed.reopenPath() }.buttonStyle(SoftButtonStyle()).help(L("Revine la desenarea punctelor (conturul deschis nu are efect)")) }
                else { Button(L("Închide conturul")) { ed.closePath() }.buttonStyle(SoftButtonStyle()).disabled(c.points.count < 3).help(L("Unește ultimul punct cu primul (sau click pe primul punct)")) }
                Button(L("Șterge punctul")) { ed.deleteSelectedPoint() }.buttonStyle(SoftButtonStyle()).disabled(ed.selectedPoint == nil).keyboardShortcut(.delete, modifiers: [])
            }
            if let pi = ed.selectedPoint, pi < c.points.count { Button(c.points[pi].smooth ? L("Punct: curbă → colț") : L("Punct: colț → curbă")) { ed.toggleSmooth(pi) }.buttonStyle(SoftButtonStyle()).help(L("Punctele netede fac segmentele din jur curbe (tangentă automată)")) }
            Text(c.closed ? L("Contur închis. Trage punctele; dublu-click pe un segment adaugă un punct; dublu-click pe un punct îl face curbă/colț.") : L("Click pe fotografie pentru puncte; click pe primul punct (sau «Închide conturul») îl închide. Contur poligonal sau cu puncte netede: nu e o unealtă finală pentru margini complexe (păr, blană).")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
        case .brush:
            HStack(spacing: 6) {
                Button { ed.maskTool = .brushAdd } label: { Label(L("Adaugă"), systemImage: "paintbrush.pointed").lineLimit(1) }.buttonStyle(SoftButtonStyle(active: ed.maskTool == .brushAdd))
                Button { ed.maskTool = .brushErase } label: { Label(L("Șterge"), systemImage: "eraser").lineLimit(1) }.buttonStyle(SoftButtonStyle(tint: Theme.reject, active: ed.maskTool == .brushErase))
                Button { ed.maskTool = .select } label: { Text(L("Gata")).lineLimit(1) }.buttonStyle(SoftButtonStyle(active: ed.maskTool == .select))
            }
            if ed.maskTool == .select {
                SliderRow(label: L("Mărime tușă"), value: $ed.adjustments.locals[i].components[ci].radius, range: 0.005...0.25, neutral: 0.03, fmt: "%.3f")
                SliderRow(label: L("Margine moale"), value: $ed.adjustments.locals[i].components[ci].softness, range: 0...1, neutral: 0.5, fmt: "%.2f")
            } else {
                SliderRow(label: L("Mărime pensulă"), value: $ed.brushRadius, range: 0.005...0.25, neutral: 0.04, fmt: "%.3f")
                SliderRow(label: L("Margine moale"), value: $ed.brushSoftness, range: 0...1, neutral: 0.5, fmt: "%.2f")
            }
            Text(L("Pictează pe fotografie. «Adaugă» extinde masca, «Șterge» scoate din mască. Mărimea e fracție din înălțimea fotografiei (la fel în previzualizare și în export). Fiecare tușă e o componentă a măștii și se poate șterge sau schimba separat.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Corespondența dintre coordonatele SURSEI (în care e definită masca) și vederea transformată (geometrie activă: rotire, oglindire, decupare, perspectivă): masca se editează direct pe fotografia transformată.
/// `fwd` = punct normalizat al sursei → punct al vederii; `inv` = invers. Fără geometrie e identitatea (aceeași ca înainte). Sub perspectivă forma desenată e o aproximare locală (aparat de editare); procesarea rămâne exactă.
struct GeoMap {
    let r: CGRect; let srcW: Double, srcH: Double; let plan: Geometry.Plan; let geo: Geometry; let identity: Bool; let fx: Effects?
    init(r: CGRect, geo: Geometry, source: CGSize, effects: Effects = Effects()) {
        self.r = r; self.geo = geo; srcW = Double(max(1, source.width)); srcH = Double(max(1, source.height)); fx = effects.framingIsNeutral ? nil : effects; identity = (geo.isNeutral && fx == nil) || source.width <= 0
        plan = geo.plan(srcW: Int(srcW), srcH: Int(srcH))
    }
    func fwd(_ x: Double, _ y: Double) -> CGPoint {
        if identity { return CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var sx = x * srcW, sy = y * srcH; if let f = fx { let u = f.undistort(sx, sy, srcW: Int(srcW), srcH: Int(srcH)); sx = u.x; sy = u.y }   // eșantionat → ideal (optica), apoi geometria
        guard let o = geo.sourceToOutput(sx, sy, srcW: Int(srcW), srcH: Int(srcH)) else { return .zero }
        return CGPoint(x: r.minX + o.x / Double(plan.outW) * r.width, y: r.minY + o.y / Double(plan.outH) * r.height)
    }
    /// Punctul vederii → coordonate normalizate ale sursei (nelimitate; apelantul le limitează dacă e cazul).
    func inv(_ p: CGPoint) -> (x: Double, y: Double) {
        let nx = Double((p.x - r.minX) / r.width), ny = Double((p.y - r.minY) / r.height)
        if identity { return (nx, ny) }
        let h = plan.h; let px = nx * Double(plan.outW), py = ny * Double(plan.outH); let w = h[6] * px + h[7] * py + h[8]
        var sx = (h[0] * px + h[1] * py + h[2]) / w, sy = (h[3] * px + h[4] * py + h[5]) / w; if let f = fx { let d = f.distort(sx, sy, srcW: Int(srcW), srcH: Int(srcH)); sx = d.x; sy = d.y }
        return (sx / srcW, sy / srcH)
    }
    /// Pixeli de vedere pe un pixel al sursei (scara locală).
    var scale: Double { identity ? Double(r.width) / srcW : Double(r.width) / Double(plan.outW) }
    /// Vectorul vederii pentru un vector al sursei (în pixeli ai sursei) în jurul unui punct normalizat.
    func vec(from x: Double, _ y: Double, dxPx: Double, dyPx: Double) -> CGVector { let a = fwd(x, y), b = fwd(x + dxPx / srcW, y + dyPx / srcH); return CGVector(dx: b.x - a.x, dy: b.y - a.y) }
}

/// Ghidajele măștii peste fotografie (ancorate în coordonatele fotografiei, nu ale ferestrei; cu geometrie activă prin `GeoMap`): contururile tuturor componentelor (alb = adaugă, roșu = scade), mânere pe componenta selectată, unelte de contur/pensulă.
/// Toate gesturile lucrează cu DEPLASAREA față de începutul gestului, calculată în coordonatele SURSEI (fără salturi). Mânerele au zonă de apucare mărită; pe o elipsă îngustă mânerele se afișează la cel puțin 16 pt de centru.
struct ZoneOverlay: View {
    @ObservedObject var ed: EditingModel
    /// Dreptunghiul imaginii afișate (cu zoom/deplasare): TOATE coordonatele ghidajelor derivă din el și din geometrie; geometria măștii rămâne în coordonate normalizate ale sursei.
    let r: CGRect
    /// Space apăsat / deplasare în curs: ghidajele nu primesc evenimente (vederea se mișcă, masca nu).
    var spaceDown = false
    @State private var snap: MaskComponent?; @State private var snapQ: (x: Double, y: Double)?
    @State private var brushPts: [CGPoint] = []; @State private var hover: CGPoint?
    var body: some View {
        GeometryReader { g in
            if let i = ed.localIndex(ed.selectedLocal), let img = ed.afterImage, img.size.width > 0, img.size.height > 0 {
                let l = ed.adjustments.locals[i]; let ci = ed.componentIndex(i); let m = GeoMap(r: r, geo: ed.sourceFrameView ? Geometry() : ed.adjustments.geometry, source: ed.sourceSize, effects: ed.sourceFrameView ? Effects() : ed.adjustments.effective.effects)
                ZStack {
                    if ed.showZone, let mk = ed.zoneOverlayImage(l, aspect: m.identity ? CGFloat(m.srcW / m.srcH) : CGFloat(r.width / r.height), zoom: ed.viewer.scale, geometry: m.identity ? nil : m.geo, effects: m.fx ?? Effects(), source: ed.sourceSize) { Image(nsImage: mk).resizable().interpolation(.high).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY).allowsHitTesting(false) }
                    capture(i, ci, m)
                    ForEach(Array(l.components.enumerated()), id: \.element.id) { idx, c in outline(c, idx == ci, l.enabled, m) }
                    if ed.maskTool == .select || ed.maskTool == .drawPath { handles(i, ci, l.components[ci], m) }
                    brushLayer(i, ci, m)
                }.frame(width: g.size.width, height: g.size.height).coordinateSpace(name: "zone").allowsHitTesting(!spaceDown)
            }
        }
    }
    /// Umplerea măștii (raster în coordonatele sursei) așezată pe vedere: la geometrie neutră = dreptunghiul imaginii; altfel ca imagine transformată afin prin colțurile sursei.
    @ViewBuilder func fillImage(_ mk: NSImage, _ m: GeoMap) -> some View {
        if m.identity { Image(nsImage: mk).resizable().interpolation(.high).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY).allowsHitTesting(false) }
        else {
            let c0 = m.fwd(0, 0), c1 = m.fwd(1, 0), c2 = m.fwd(0, 1); let ux = c1.x - c0.x, uy = c1.y - c0.y, vx = c2.x - c0.x, vy = c2.y - c0.y
            Color.clear.overlay(alignment: .topLeading) { Image(nsImage: mk).resizable().interpolation(.high).frame(width: 1, height: 1).transformEffect(CGAffineTransform(a: ux, b: uy, c: vx, d: vy, tx: c0.x, ty: c0.y)) }.allowsHitTesting(false)
        }
    }
    func pathOf(_ c: MaskComponent, _ m: GeoMap) -> Path {
        Path { p in for seg in MaskGeometry.flatten(c.points, closed: c.closed, sx: m.srcW, sy: m.srcH, steps: 12) { guard let f = seg.first else { continue }; p.move(to: m.fwd(f.x / m.srcW, f.y / m.srcH)); for q in seg.dropFirst() { p.addLine(to: m.fwd(q.x / m.srcW, q.y / m.srcH)) } } }
    }
    /// Marginea elipsei din sursă, eșantionată și trecută EXACT prin harta geometriei (fidelă zonei procesate, inclusiv sub perspectivă).
    func ellipseBoundary(_ c: MaskComponent, _ m: GeoMap) -> Path {
        let a = c.x2 * m.srcW, b = c.y2 * m.srcH, ph = c.rotation * .pi / 180
        return Path { p in for k in 0...96 { let t = Double(k) / 96 * 2 * .pi; let x = c.x1 + (a * cos(t) * cos(ph) - b * sin(t) * sin(ph)) / m.srcW, y = c.y1 + (a * cos(t) * sin(ph) + b * sin(t) * cos(ph)) / m.srcH; let pt = m.fwd(x, y); if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) } } }
    }
    func ellipseVecs(_ c: MaskComponent, _ m: GeoMap) -> (u: CGVector, v: CGVector) {
        let a = c.x2 * m.srcW, b = c.y2 * m.srcH, ph = c.rotation * .pi / 180
        return (m.vec(from: c.x1, c.y1, dxPx: a * cos(ph), dyPx: a * sin(ph)), m.vec(from: c.x1, c.y1, dxPx: -b * sin(ph), dyPx: b * cos(ph)))
    }
    // contururi (doar afișare)
    @ViewBuilder func outline(_ c: MaskComponent, _ selected: Bool, _ enabled: Bool, _ m: GeoMap) -> some View {
        let col: Color = c.op == .add ? .white : Color(red: 1, green: 0.42, blue: 0.4); let op = (enabled ? (selected ? 0.95 : 0.5) : 0.35)
        let st = StrokeStyle(lineWidth: selected ? 1.6 : 1.1, dash: [5, 3])
        switch c.kind {
        case .ellipse: let ev = ellipseVecs(c, m); let ctr = m.fwd(c.x1, c.y1)
            if m.identity { Ellipse().stroke(col.opacity(op), style: st).frame(width: 2 * hypot(ev.u.dx, ev.u.dy), height: 2 * hypot(ev.v.dx, ev.v.dy)).rotationEffect(.radians(atan2(ev.u.dy, ev.u.dx))).position(ctr).allowsHitTesting(false) }
            else { ellipseBoundary(c, m).stroke(col.opacity(op), style: st).allowsHitTesting(false) }   // margine EXACTĂ (puncte ale marginii din sursă prin harta geometriei), nu o elipsă aproximată
        case .gradient: Path { p in p.move(to: m.fwd(c.x1, c.y1)); p.addLine(to: m.fwd(c.x2, c.y2)) }.stroke(col.opacity(op), style: st).allowsHitTesting(false)
        case .path: pathOf(c, m).stroke(col.opacity(op), style: st).allowsHitTesting(false)
        case .brush: Path { p in for (k, q) in c.points.enumerated() { let pt = m.fwd(q.x, q.y); if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) } } }.stroke(col.opacity(op * 0.8), style: StrokeStyle(lineWidth: 1, dash: [2, 3])).allowsHitTesting(false)
        }
    }
    func setC(_ i: Int, _ ci: Int, _ f: (inout MaskComponent) -> Void) { guard i < ed.adjustments.locals.count, ci < ed.adjustments.locals[i].components.count else { return }; var c = ed.adjustments.locals[i].components[ci]; f(&c); ed.adjustments.locals[i].components[ci] = c }
    /// Mâner: la începutul gestului păstrează componenta și punctul SURSEI de sub cursor; mișcarea primește deplasarea în coordonatele sursei.
    func grab(_ at: CGPoint, shape: Int = 0, tint: Color = .white, filled: Bool = true, i: Int, ci: Int, _ m: GeoMap, onStart: (() -> Void)? = nil, _ move: @escaping (_ q: (x: Double, y: Double), _ q0: (x: Double, y: Double), _ s: MaskComponent) -> Void) -> some View {
        ZStack {
            if shape == 1 { Rectangle().fill(filled ? tint : Color.clear).overlay(Rectangle().stroke(tint, lineWidth: 2)).frame(width: 11, height: 11) }
            else { Circle().fill(filled ? tint : Color.clear).overlay(Circle().stroke(tint, lineWidth: 2)).frame(width: 12, height: 12) }
        }.shadow(radius: 2).frame(width: 30, height: 30).contentShape(Circle()).position(at)
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("zone")).onChanged { v in
            if snap == nil { ed.beginMaskEdit(); snap = ed.adjustments.locals[i].components[ci]; snapQ = m.inv(v.startLocation); onStart?() }
            if let s = snap, let q0 = snapQ { move(m.inv(v.location), q0, s) } }.onEnded { _ in ed.endMaskEdit(); snap = nil; snapQ = nil })
    }
    @ViewBuilder func handles(_ i: Int, _ ci: Int, _ c: MaskComponent, _ m: GeoMap) -> some View {
        switch c.kind {
        case .ellipse: ellipseHandles(i, ci, c, m)
        case .gradient:
            let a = m.fwd(c.x1, c.y1), b = m.fwd(c.x2, c.y2)
            grab(a, i: i, ci: ci, m) { q, q0, s in setC(i, ci) { $0.x1 = min(1, max(0, s.x1 + q.x - q0.x)); $0.y1 = min(1, max(0, s.y1 + q.y - q0.y)) } }
            grab(b, filled: false, i: i, ci: ci, m) { q, q0, s in setC(i, ci) { $0.x2 = min(1, max(0, s.x2 + q.x - q0.x)); $0.y2 = min(1, max(0, s.y2 + q.y - q0.y)) } }
            Text(L("efect complet")).font(Theme.f(10)).foregroundColor(.white).padding(2).background(Color.black.opacity(0.5)).position(x: a.x, y: a.y - 18).allowsHitTesting(false)
            Text(L("fără efect")).font(Theme.f(10)).foregroundColor(.white).padding(2).background(Color.black.opacity(0.5)).position(x: b.x, y: b.y + 18).allowsHitTesting(false)
        case .path:
            ForEach(Array(c.points.enumerated()), id: \.offset) { k, p in
                grab(m.fwd(p.x, p.y), shape: p.smooth ? 0 : 1, tint: ed.selectedPoint == k ? Color(red: 0.55, green: 0.8, blue: 1) : (k == 0 && !c.closed ? Color(red: 1, green: 0.85, blue: 0.3) : .white), i: i, ci: ci, m, onStart: { ed.selectedPoint = k }) { q, q0, s in
                    guard k < s.points.count else { return }; setC(i, ci) { $0.points[k].x = min(1, max(0, s.points[k].x + q.x - q0.x)); $0.points[k].y = min(1, max(0, s.points[k].y + q.y - q0.y)) } }
                .simultaneousGesture(TapGesture(count: 2).onEnded { ed.toggleSmooth(k) })
            }
        case .brush: EmptyView()
        }
    }
    func ellipseHandles(_ i: Int, _ ci: Int, _ c: MaskComponent, _ m: GeoMap) -> some View {
        let ctr = m.fwd(c.x1, c.y1); let ev = ellipseVecs(c, m)
        let la = max(hypot(ev.u.dx, ev.u.dy), 1e-6), lb = max(hypot(ev.v.dx, ev.v.dy), 1e-6)
        let ud = CGVector(dx: ev.u.dx / la, dy: ev.u.dy / la), vd = CGVector(dx: ev.v.dx / lb, dy: ev.v.dy / lb)
        let phr = c.rotation * .pi / 180; let aS = c.x2 * m.srcW, bS = c.y2 * m.srcH
        // mânere pe marginea EXACTĂ (capetele axelor din sursă trecute prin harta geometriei); pe o elipsă îngustă se afișează la ≥ 16 pt de centru
        func edge(_ dx: Double, _ dy: Double) -> CGPoint { let p = m.fwd(c.x1 + dx / m.srcW, c.y1 + dy / m.srcH); let d = hypot(p.x - ctr.x, p.y - ctr.y); if d >= 16 || d < 1e-6 { return p }; return CGPoint(x: ctr.x + (p.x - ctr.x) / d * 16, y: ctr.y + (p.y - ctr.y) / d * 16) }
        let pU = edge(aS * cos(phr), aS * sin(phr)), pUm = edge(-aS * cos(phr), -aS * sin(phr)), pV = edge(-bS * sin(phr), bS * cos(phr)), pVm = edge(bS * sin(phr), -bS * cos(phr))
        let dTop = CGVector(dx: pVm.x - ctr.x, dy: pVm.y - ctr.y); let lt = max(hypot(dTop.dx, dTop.dy), 1e-6); let rotPos = CGPoint(x: pVm.x + dTop.dx / lt * 30, y: pVm.y + dTop.dy / lt * 30)
        let ph = phr
        let uS = (x: cos(ph), y: sin(ph)), vS = (x: -sin(ph), y: cos(ph))      // axele elipsei în pixeli ai SURSEI
        func axis(_ ax: (x: Double, y: Double), sign: Double, horizontal: Bool) -> (_ q: (x: Double, y: Double), _ q0: (x: Double, y: Double), _ s: MaskComponent) -> Void {
            { q, q0, s in let t = ((q.x - q0.x) * m.srcW) * ax.x + ((q.y - q0.y) * m.srcH) * ax.y
                setC(i, ci) { if horizontal { $0.x2 = min(1, max(0.003, s.x2 + sign * t / m.srcW)) } else { $0.y2 = min(1, max(0.003, s.y2 + sign * t / m.srcH)) } } }
        }
        return ZStack {
            Path { p in p.move(to: pVm); p.addLine(to: rotPos) }.stroke(Color.white.opacity(0.6), lineWidth: 1).allowsHitTesting(false)
            // corp: mutare prin deplasare (fără salt)
            Ellipse().fill(Color.white.opacity(0.001)).frame(width: 2 * la, height: 2 * lb).rotationEffect(.radians(atan2(ev.u.dy, ev.u.dx))).position(ctr)
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("zone")).onChanged { g in if snap == nil { ed.beginMaskEdit(); snap = c; snapQ = m.inv(g.startLocation) }; if let s = snap, let q0 = snapQ { let q = m.inv(g.location); setC(i, ci) { $0.x1 = min(1, max(0, s.x1 + q.x - q0.x)); $0.y1 = min(1, max(0, s.y1 + q.y - q0.y)) } } }.onEnded { _ in ed.endMaskEdit(); snap = nil; snapQ = nil })
            grab(pU, shape: 1, i: i, ci: ci, m, axis(uS, sign: 1, horizontal: true))
            grab(pUm, shape: 1, i: i, ci: ci, m, axis(uS, sign: -1, horizontal: true))
            grab(pV, i: i, ci: ci, m, axis(vS, sign: 1, horizontal: false))
            grab(pVm, i: i, ci: ci, m, axis(vS, sign: -1, horizontal: false))
            grab(ctr, tint: Color(white: 1, opacity: 0.9), filled: false, i: i, ci: ci, m) { q, q0, s in setC(i, ci) { $0.x1 = min(1, max(0, s.x1 + q.x - q0.x)); $0.y1 = min(1, max(0, s.y1 + q.y - q0.y)) } }
            // rotire: unghiul în coordonatele SURSEI, relativ la începutul gestului
            grab(rotPos, tint: Color(red: 0.55, green: 0.8, blue: 1), i: i, ci: ci, m) { q, q0, s in
                let cx = s.x1 * m.srcW, cy = s.y1 * m.srcH; let a0 = atan2(q0.y * m.srcH - cy, q0.x * m.srcW - cx), a1 = atan2(q.y * m.srcH - cy, q.x * m.srcW - cx); var d = (a1 - a0) * 180 / .pi; while d > 180 { d -= 360 }; while d < -180 { d += 360 }
                setC(i, ci) { var rot = s.rotation + d; while rot > 180 { rot -= 360 }; while rot < -180 { rot += 360 }; $0.rotation = (rot * 10).rounded() / 10 } }
        }
    }
    // stratul care primește click-uri/tușe (sub mânere)
    @ViewBuilder func capture(_ i: Int, _ ci: Int, _ m: GeoMap) -> some View {
        switch ed.maskTool {
        case .drawPath:
            Color.clear.frame(width: r.width, height: r.height).contentShape(Rectangle()).toolCursor(.draw).position(x: r.midX, y: r.midY)
                .gesture(SpatialTapGesture().onEnded { t in
                    guard ed.viewer.accepts(t.location, in: r) else { return }
                    let c = ed.adjustments.locals[i].components[ci]
                    if c.points.count >= 3, let f = c.points.first { let fp = m.fwd(f.x, f.y); if hypot(fp.x - t.location.x, fp.y - t.location.y) <= 16 { ed.closePath(); return } }
                    let n = m.inv(t.location); ed.addPathPoint(min(1, max(0, n.x)), min(1, max(0, n.y))) })
        case .brushAdd, .brushErase:
            Color.clear.frame(width: r.width, height: r.height).contentShape(Rectangle()).position(x: r.midX, y: r.midY)
                .onContinuousHover(coordinateSpace: .named("zone")) { ph in switch ph { case .active(let p): hover = p; case .ended: hover = nil } }
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("zone")).onChanged { v in guard brushPts.isEmpty ? ed.viewer.accepts(canvasPoint: v.startLocation) : true else { return }; brushPts.append(v.location); hover = v.location }.onEnded { _ in
                    guard !brushPts.isEmpty else { return }   // gest respins de poarta pânzei: nicio tușă
                    let rpx = ed.brushRadius * m.srcH * m.scale; let dec = MaskGeometry.decimate(brushPts.map { (x: Double($0.x), y: Double($0.y)) }, minDistance: max(1.5, rpx * 0.3))
                    let pts = dec.map { m.inv(CGPoint(x: $0.x, y: $0.y)) }
                    ed.addBrushStroke(pts, erase: ed.maskTool == .brushErase); brushPts = [] })
        case .select:
            let c = ed.adjustments.locals[i].components[ci]
            if c.kind == .path { Color.clear.frame(width: r.width, height: r.height).contentShape(Rectangle()).position(x: r.midX, y: r.midY)
                .gesture(SpatialTapGesture(count: 2).onEnded { t in guard ed.viewer.accepts(t.location, in: r) else { return }; let n = m.inv(t.location); ed.insertPathPoint(near: n.x, n.y, sx: m.srcW, sy: m.srcH, maxDistance: 12 / max(m.scale, 1e-6)) }) }
        }
    }
    @ViewBuilder func brushLayer(_ i: Int, _ ci: Int, _ m: GeoMap) -> some View {
        if ed.maskTool == .brushAdd || ed.maskTool == .brushErase {
            let rpx = CGFloat(ed.brushRadius * m.srcH * m.scale); let col: Color = ed.maskTool == .brushErase ? Color(red: 1, green: 0.42, blue: 0.4) : .white
            if brushPts.count > 1 { Path { p in p.move(to: brushPts[0]); for q in brushPts.dropFirst() { p.addLine(to: q) } }.stroke(col.opacity(0.4), style: StrokeStyle(lineWidth: 2 * rpx, lineCap: .round, lineJoin: .round)).allowsHitTesting(false) }
            if let h = hover { ZStack { Circle().stroke(col, lineWidth: 1.5).frame(width: 2 * rpx, height: 2 * rpx); Circle().stroke(col.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: 2 * rpx * CGFloat(1 - ed.brushSoftness), height: 2 * rpx * CGFloat(1 - ed.brushSoftness)) }.position(h).allowsHitTesting(false) }
        }
    }
}

/// „Continuă în Resolve” (opțional): lanț de 3 noduri-etapă în pagina Color, într-o versiune de culoare proprie; fără Fusion. Necesită DaVinci Resolve Studio; restul aplicației nu.
struct ResolveHandoffBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        Box(title: L("Resolve (opțional)"), panel: "resolve") {
            Text(L("Pentru intervenții avansate în pagina Color (de ex. măști Resolve). Fotografia se pregătește cu 3 noduri: 1 Liniar · 2 Log · 3 GDC DRT, într-o versiune de culoare nouă; nu e nevoie de Fusion. Necesită DaVinci Resolve Studio.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            if ed.adjustments.locals.contains(where: { $0.isActiveLocal }) { Text(LF("Corecțiile locale FotoAsist active (%@) NU se transferă în Resolve ca obiecte editabile: rămân în FotoAsist și în exportul FotoAsist. Pregătirea în Resolve conține doar lanțul global; măștile din Resolve se fac acolo.", ed.adjustments.locals.filter { $0.isActiveLocal }.count)).font(Theme.f(11)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
            if !ed.adjustments.effective.tools.isNeutral { Text(L("Instrumentele avansate de ton/culoare (negru, mijloc, balans tonal, lumini de imprimare, mixer, LGG/roți/CDL, nuanță/HSV, pivot) NU au corespondent pe nodurile pluginului din Resolve: se pot INTEGRA în intermediar (alegerea de mai jos) sau lăsa afară explicit.")).font(Theme.f(11)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
            if !ed.adjustments.effective.detail.isNeutral { Text(L("Detaliile (claritate/accentuare) se aplică pe imaginea finală FotoAsist și NU se transferă în Resolve.")).font(Theme.f(11.5)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
            if ed.adjustments.effective.effects.hasPostEffects { Text(L("Vinieta creativă, pelicula și grain-ul NU se transferă în Resolve ca obiecte editabile: se pot INTEGRA în intermediar (la alegerea de mai jos) sau lăsa afară explicit. Optica (distorsiune, aberație, vinietă de obiectiv) intră în intermediar.")).font(Theme.f(11)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
            if !ed.adjustments.geometry.isNeutral { Text(L("Cadrul ales (decupare, rotire, perspectivă) se aplică în INTERMEDIARUL trimis în Resolve (fișier marcat «GEO», dimensiunea finală); nu se aplică a doua oară și nu e editabil în Resolve. Corecțiile locale FotoAsist nu se transferă.")).font(Theme.f(11)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
            VStack(alignment: .leading, spacing: 6) {
                Button { ed.beginResolveHandoff() } label: { Label(L("Continuă în Resolve"), systemImage: "arrow.up.forward.app").lineLimit(1) }.buttonStyle(PrimaryButtonStyle()).disabled(ed.current == nil || ed.engine != .own || isWorking)
                Button { ed.refreshFromResolve() } label: { Text(L("Actualizează din Resolve")).lineLimit(1) }.buttonStyle(SoftButtonStyle()).disabled(isWorking)
            }
            if ed.resolveResultURL != nil { Button { ed.exportResolveResult() } label: { Text(L("Exportă rezultatul din Resolve")).lineLimit(1) }.buttonStyle(SoftButtonStyle()).help(L("Exportă TIFF-ul randat de Resolve (cu măștile și nodurile adăugate acolo), cu profil sRGB")) }
            if !ed.resolveExportNote.isEmpty { Text(ed.resolveExportNote).font(Theme.f(11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            Text(ed.ofxStatus).font(Theme.f(11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            switch ed.handoff {
            case .idle: EmptyView()
            case .working(let m): HStack(spacing: 6) { ProgressView().controlSize(.small); Text(m).font(Theme.f(11.5)).foregroundColor(Theme.muted) }
            case .done(let m): Text(m).font(Theme.f(11.5)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
            case .needsLocalsChoice(let n): VStack(alignment: .leading, spacing: 6) {
                Text(LF("Ai %@ elemente FotoAsist active (corecții locale / vinietă, peliculă, grain). Nu se pot transfera editabil în Resolve, iar exportul din Resolve nu trebuie să le piardă în tăcere. Alege:", n)).font(Theme.f(11.5)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true)
                Button(L("Predă cu corecțiile INTEGRATE (recomandat)")) { ed.continueInResolve(locals: .bake) }.buttonStyle(PrimaryButtonStyle()).help(L("Intermediarul conține corecțiile globale și locale (cod înainte de DRT); în Resolve nodurile 1–2 devin neutre; masca nu e editabilă acolo"))
                Button(L("Predă FĂRĂ corecțiile locale (le pierd în Resolve)")) { ed.continueInResolve(locals: .drop) }.buttonStyle(SoftButtonStyle())
                Text(L("Integrate: rezultatul lor se păstrează, dar ajustările globale se fac în FotoAsist, nu în Resolve (altfel s-ar aplica de două ori). Fără ele: rămân doar în FotoAsist.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
            case .needsConsent(let p): VStack(alignment: .leading, spacing: 6) { Text(LF("Resolve are deschis proiectul „%@”. Pentru a pregăti fotografia, FotoAsist trebuie să deschidă proiectul propriu „FOTOASIST_GC_COLOR” (proiectul curent se salvează, nu se șterge).", p)).font(Theme.f(11.5)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true)
                Button(L("Permite schimbarea proiectului")) { ed.continueInResolve(allowSwitch: true) }.buttonStyle(SoftButtonStyle()) }
            case .failed(let m): Text(m).font(Theme.f(11.5)).foregroundColor(Theme.reject).fixedSize(horizontal: false, vertical: true)
            }
            if !ed.resolveReadback.isEmpty { VStack(alignment: .leading, spacing: 2) { ForEach(ed.resolveReadback, id: \.self) { Text($0).font(Theme.f(11, design: .monospaced)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) } } }
            Text(L("Reîntoarcerea: reglajele pluginului (doar cele schimbate) și rezultatul randat din Resolve. Măștile, keyframe-urile și alte efecte adăugate în Resolve rămân în proiectul Resolve; NU se citesc în FotoAsist ca obiecte editabile. Ajung în exportul final doar prin „Exportă rezultatul din Resolve”; exportul obișnuit FotoAsist nu le include.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
        }
    }
    var isWorking: Bool { if case .working = ed.handoff { return true }; return false }
}

/// „Profilul meu” — infrastructură: perechile RAW–final se înregistrează ca PROPUSE și devin exemple DOAR după confirmarea explicită; se pot crea ciorne de profil (fără estimare încă). Presetările nu sunt profil.
struct PersonalProfileBox: View {
    @ObservedObject var ed: EditingModel
    @State private var photographer = "Eu"; @State private var setName = "Set 1"; @State private var profileName = L("Profilul meu"); @State private var flow = false
    var body: some View {
        let reg = ed.profileRegistry
        Box(title: L("Profilul meu"), panel: "profile") {
            Button { flow = true } label: { Label(L("Creează profilul meu…"), systemImage: "wand.and.stars").lineLimit(1) }.buttonStyle(PrimaryButtonStyle()).sheet(isPresented: $flow) { ProfileFlowSheet(ed: ed, photographer: $photographer, setName: $setName, profileName: $profileName).frame(minWidth: 560, idealWidth: 700, maxWidth: 760, minHeight: 520, idealHeight: 660) }
            Text(L("Profilul se creează local din exemple proprii APROBATE (RAW + finalul tău editat). Nu e cloud și nu e ML. Presetările de mai sus nu sunt un profil învățat. Estimarea reală începe după ce aprobi exemplele; până atunci se pregătește doar evidența.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) { TextField(L("Fotograf"), text: $photographer).textFieldStyle(.roundedBorder).frame(minWidth: 0, maxWidth: .infinity); TextField(L("Set"), text: $setName).textFieldStyle(.roundedBorder).frame(minWidth: 0, maxWidth: .infinity) }.font(Theme.f(12))
            Button { ed.addExamplePair(photographer: photographer, setName: setName) } label: { Label(L("Adaugă pereche RAW + final"), systemImage: "plus.circle").lineLimit(1) }.buttonStyle(SoftButtonStyle())
            ForEach(reg.pairs) { p in
                VStack(alignment: .leading, spacing: 3) {
                    Text(((p.rawPath as NSString).lastPathComponent) + "  ↔  " + ((p.finalPath as NSString).lastPathComponent)).font(Theme.f(11.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 6) { Badge(text: p.state == .confirmed ? L("confirmată") : (p.state == .rejected ? L("respinsă") : L("propusă")), color: p.state == .confirmed ? Theme.keep : (p.state == .rejected ? Theme.reject : Theme.check)); Text("\(p.photographer) · \(p.setName)").font(Theme.f(10.5)).foregroundColor(Theme.faint); Spacer()
                        if p.state != .confirmed { Button(L("Confirmă")) { ed.confirmPair(p.id) }.buttonStyle(SoftButtonStyle()).help(ProfileRegistry.confirmationText) }
                        if p.state != .rejected { Button(L("Respinge")) { ed.rejectPair(p.id) }.buttonStyle(SoftButtonStyle()) }
                        Button { ed.removePair(p.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain) }
                }.padding(.vertical, 2)
            }
            if reg.pairs.contains(where: { $0.state == .proposed }) { Text(LF("Confirmarea înseamnă: „%@”", ProfileRegistry.confirmationText)).font(Theme.f(10.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            TextField(L("Nume profil"), text: $profileName).textFieldStyle(.roundedBorder).font(Theme.f(12)).frame(minWidth: 0, maxWidth: .infinity)
            Button(L("Creează ciornă")) { ed.createDraftProfile(name: profileName, photographer: photographer, setName: setName) }.buttonStyle(SoftButtonStyle()).disabled(reg.confirmedPairs(photographer: photographer, setName: setName).isEmpty)
            ForEach(reg.profiles) { pr in
                VStack(alignment: .leading, spacing: 3) {
                    Text("«\(pr.name)» v\(pr.version) · \(pr.photographer)/\(pr.setName) · \(pr.pairIDs.count) perechi · " + (pr.status == .estimated ? "ESTIMAT (experimental)" : L("ciornă, fără estimare"))).font(Theme.f(11)).foregroundColor(Theme.muted)
                    if pr.status == .estimated {
                        if let ev = pr.evaluation { Text(ev).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
                        if pr.engineVersion != ProfileEstimator.engineIdentity { Text(L("Motorul sau setul de parametri s-a schimbat de la estimare: profilul NU a fost modificat; re-evaluează-l înainte de a te baza pe el.")).font(Theme.f(10.5)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
                        Text(L("Parametri estimați: ") + (pr.paramSet ?? []).joined(separator: ", ") + L(". Neestimați: restul modulelor, corecții locale, efecte, geometrie.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                        Button(L("Aplică profilul fotografiei curente")) { ed.applyProfile(pr.id) }.buttonStyle(SoftButtonStyle()).disabled(ed.current == nil)
                    }
                    if let b = reg.estimationBlocker(for: pr), pr.status != .estimated { Text(b).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
                    else { Button(pr.status == .estimated ? L("Re-estimează") : L("Estimează profilul")) { ed.estimateProfile(pr.id) }.buttonStyle(SoftButtonStyle()).disabled(ed.profileBusy) }
                    if ed.profileBusy { Text(ed.profileProgress).font(Theme.f(10.5)).foregroundColor(Theme.muted) }
                }
            }
            if !ed.profileMessage.isEmpty { Text(ed.profileMessage).font(Theme.f(11.5)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
            Text(L("Intră în profil doar parametri globali repetabili (contrast, saturație, umbre, lumini, deplasări de balans, adaptarea expunerii). NU intră: corecții locale, retușuri, efecte, curbe arbitrare. Nu se promite reproducerea exactă a unei editări.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
        }
    }
}
