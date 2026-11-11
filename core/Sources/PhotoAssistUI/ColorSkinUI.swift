import SwiftUI
import PhotoCore
import PhotoResolve

/// Selecția vizibilă pe imagine (Color: familia de culori aleasă; Skin: ce consideră piele detectorul din culoare) + Pick Color prin clic. Peste fotografia transformată (geometria activă).
struct SelectionOverlay: View {
    @ObservedObject var ed: EditingModel; let r: CGRect
    @State private var image: NSImage?
    var body: some View {
        let kind = ed.selectionKind ?? 0; let w = 640, h = max(8, Int((640.0 * Double(r.height / max(r.width, 1))).rounded()))
        ZStack {
            if let i = image { Image(nsImage: i).resizable().interpolation(.medium).frame(width: r.width, height: r.height).allowsHitTesting(false) }
            if (kind == 0 && ed.rangePicking) || ed.wbPicking { RangeDragLayer(ed: ed, r: r) }
            if kind == 0 && ed.colorPicking {
                Color.clear.contentShape(Rectangle()).frame(width: r.width, height: r.height).gesture(SpatialTapGesture().onEnded { v in
                    guard ed.viewer.accepts(v.location, in: r) else { return }
                    let m = GeoMap(r: CGRect(x: 0, y: 0, width: r.width, height: r.height), geo: ed.adjustments.geometry, source: ed.sourceSize, effects: ed.adjustments.effective.effects); let p = m.inv(v.location)
                    ed.pickColor(nx: min(1, max(0, p.x)), ny: min(1, max(0, p.y))) }).toolCursor(.sample)
            }
        }.frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
        .task(id: "\(kind)|\(ed.adjustments.tools.fingerprint)|\(ed.adjustments.geometry.fingerprint)|\(ed.current?.id ?? 0)|\(w)x\(h)|\(ed.adjustments.exposure)|\(ed.adjustments.temperature)|\(ed.adjustments.contrast)|\(ed.adjustments.saturation)") { try? await Task.sleep(nanoseconds: 150_000_000); if Task.isCancelled { return }; image = await ed.selectionImage(kind: kind, width: w, height: h) }
    }
}

struct ColorBox: View {
    @ObservedObject var ed: EditingModel
    func s(_ label: String, _ kp: WritableKeyPath<ToolSet, Double>, _ r: ClosedRange<Double>, _ n: Double, _ f: String = "%.2f") -> some View { SliderRow(label: label, value: Binding(get: { ed.adjustments.tools[keyPath: kp] }, set: { ed.adjustments.tools[keyPath: kp] = $0 }), range: r, neutral: n, fmt: f) }
    var body: some View {
        Box(title: L("Culoare selectivă"), panel: "color", summary: ed.adjustments.tools.colorOn ? L("activ") : nil, module: ed.moduleBinding("color"), reset: toolReset(ed, .color, L("Culoare selectivă"))) {
            HStack { Button { ed.colorPicking.toggle(); if ed.colorPicking { ed.selectionKind = 0 } } label: { Label(ed.colorPicking ? L("Apasă pe imagine…") : L("Alege culoarea din imagine"), systemImage: "eyedropper").lineLimit(1) }.buttonStyle(ed.colorPicking ? SoftButtonStyle(active: true) : SoftButtonStyle())
                Button { ed.rangePicking.toggle(); if ed.rangePicking { ed.colorPicking = false; ed.selectionKind = 0 } } label: { Label(ed.rangePicking ? L("Trage peste o zonă…") : "Alege gama (trage)", systemImage: "rectangle.dashed").lineLimit(1) }.buttonStyle(ed.rangePicking ? SoftButtonStyle(active: true) : SoftButtonStyle()).help("Pick Range: tragi un dreptunghi peste o zonă; aplicația deduce familia de culori (mod dominant, fără obiecte străine) și intervalele")
                Toggle(L("Arată selecția"), isOn: Binding(get: { ed.selectionKind == 0 }, set: { ed.selectionKind = $0 ? 0 : nil })).toggleStyle(.switch).controlSize(.small).font(Theme.f(11.5)) }
            Text(ed.colorPickNote.isEmpty ? (ed.adjustments.tools.colorOn ? String(format: L("Selectat: nuanță %.0f° · croma %.2f · %+.1f st"), ed.adjustments.tools.colorHue, ed.adjustments.tools.colorC, ed.adjustments.tools.colorL) : L("Nicio culoare aleasă: fără ea nimic nu se schimbă.")) : ed.colorPickNote).font(Theme.f(11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Text(L("Rafinare")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
            s(L("Interval de nuanță"), \.colorRange, 0...1, 0.25); s("Moliciunea marginilor", \.colorSoft, 0...1, 0.5); s(L("Interval de saturație"), \.colorSatRange, 0...1, 0.5); s(L("Interval de luminanță"), \.colorLumRange, 0...1, 0.4)
            Text(L("Schimbare")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
            s(L("Nuanță (grade)"), \.cHue, -180...180, 0, "%+.0f"); s(L("Saturație"), \.cSat, -1...1, 0, "%+.2f"); s(L("Densitate"), \.cDensity, -1...1, 0, "%+.2f"); s(L("Luminanță (stopuri)"), \.cLum, -2...2, 0, "%+.2f"); s("Cald ↔ rece", \.cWarm, -1...1, 0, "%+.2f")
            Text(L("Protejare")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
            s(L("Protejează pielea"), \.cSkinProt, 0...1, 0); s(L("Protejează neutrele"), \.cNeutralProt, 0...1, 0.5)
            s(L("Cantitate"), \.cAmount, 0...1.5, 1)
            Details(title: L("Avansat")) { s(L("Centru nuanță (°)"), \.colorHue, 0...360, 250, "%.0f"); s("Centru croma", \.colorC, 0...1, 0.5); s(L("Centru luminanță (st)"), \.colorL, -12...8, 0, "%+.1f")
                Text(L("Lucrează pe codul log al familiei, prin liniar real și OKLab (aceleași legi ca «Color» din GDC STYLE). Selecția se face pe valorile de INTRARE ale pixelului; gri-urile nu au nuanță definită și nu se selectează.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
struct SkinBox: View {
    @ObservedObject var ed: EditingModel
    func s(_ label: String, _ kp: WritableKeyPath<ToolSet, Double>, _ r: ClosedRange<Double>, _ n: Double, _ f: String = "%.2f") -> some View { SliderRow(label: label, value: Binding(get: { ed.adjustments.tools[keyPath: kp] }, set: { ed.adjustments.tools[keyPath: kp] = $0 }), range: r, neutral: n, fmt: f) }
    var body: some View {
        Box(title: L("Piele (după culoare)"), panel: "skin", summary: ed.adjustments.tools.isNeutral(.skin) ? nil : L("activ"), module: ed.moduleBinding("skin"), reset: toolReset(ed, .skin, "Piele")) {
            Toggle(L("Arată pielea detectată"), isOn: Binding(get: { ed.selectionKind == 1 }, set: { ed.selectionKind = $0 ? 1 : nil })).toggleStyle(.switch).controlSize(.small).font(Theme.f(11.5))
            Text(L("Pielea se găsește automat din culoare. NU e recunoaștere de persoană: lemn, nisip sau bej pot fi tratate ca piele (verifică selecția).")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            Text(L("Rafinare")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
            s("Interval piele", \.skRange, 0...1, 0.5); s("Include umbrele", \.skShadows, 0...1, 0.5); s("Moliciunea marginilor", \.skEdge, 0...1, 0.5)
            Text(L("Aspect")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
            s("Uniformizare", \.skEven, 0...1, 0); s("Cald ↔ rece", \.skWarm, -1...1, 0, "%+.2f"); s(L("Verde ↔ magenta"), \.skTint, -1...1, 0, "%+.2f"); s(L("Saturație"), \.skVivid, -1...1, 0, "%+.2f"); s(L("Densitate"), \.skRich, -1...1, 0, "%+.2f"); s("Luminozitate (st)", \.skBright, -1...1, 0, "%+.2f"); s(L("Nuanță (grade)"), \.skHue, -30...30, 0, "%+.0f")
            s(L("Cantitate"), \.skAmount, 0...1, 1)
        }
    }
}

/// Pick Range: dreptunghi tras peste fotografie → până la 512 eșantioane regulate, mapate în coordonatele sursei (GeoMap); minim 6 px pe fiecare axă ca să conteze.
struct RangeDragLayer: View {
    @ObservedObject var ed: EditingModel; let r: CGRect
    @State private var a: CGPoint?; @State private var b: CGPoint?
    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle()).frame(width: r.width, height: r.height)
                .gesture(DragGesture(minimumDistance: 4).onChanged { d in guard ed.viewer.accepts(d.startLocation, in: r) else { return }; a = d.startLocation; b = d.location }.onEnded { d in
                    guard a != nil else { return }
                    let p0 = d.startLocation, p1 = d.location; a = nil; b = nil; guard abs(p1.x - p0.x) > 6, abs(p1.y - p0.y) > 6 else { return }
                    let m = GeoMap(r: CGRect(x: 0, y: 0, width: r.width, height: r.height), geo: ed.adjustments.geometry, source: ed.sourceSize, effects: ed.adjustments.effective.effects)
                    let nx = 24, ny = 21; var pts: [(x: Double, y: Double)] = []
                    for j in 0..<ny { for i in 0..<nx { let v = CGPoint(x: min(p0.x, p1.x) + abs(p1.x - p0.x) * (Double(i) + 0.5) / Double(nx), y: min(p0.y, p1.y) + abs(p1.y - p0.y) * (Double(j) + 0.5) / Double(ny)); let q = m.inv(v); if q.x >= 0, q.x <= 1, q.y >= 0, q.y <= 1 { pts.append((Double(q.x), Double(q.y))) } } }
                    if ed.wbPicking { ed.pickNeutral(points: pts) } else { ed.pickRange(points: pts) } })
                .simultaneousGesture(SpatialTapGesture().onEnded { v in
                    guard ed.wbPicking, ed.viewer.accepts(v.location, in: r) else { return }
                    let m = GeoMap(r: CGRect(x: 0, y: 0, width: r.width, height: r.height), geo: ed.adjustments.geometry, source: ed.sourceSize, effects: ed.adjustments.effective.effects); var pts: [(x: Double, y: Double)] = []
                    for j in -4...4 { for i in -4...4 { let q = m.inv(CGPoint(x: v.location.x + Double(i), y: v.location.y + Double(j))); if q.x >= 0, q.x <= 1, q.y >= 0, q.y <= 1 { pts.append((Double(q.x), Double(q.y))) } } }
                    if !pts.isEmpty { ed.pickNeutral(points: pts) } })
                .toolCursor(.sample)
            if let a = a, let b = b { Rectangle().stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])).background(Theme.accent.opacity(0.1)).frame(width: abs(b.x - a.x), height: abs(b.y - a.y)).position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2).allowsHitTesting(false) }
        }.frame(width: r.width, height: r.height)
    }
}

/// Look (generația FIELD): 37 de rețete cu caracter propriu + trims + protecția pielii + intensitate. Rețetele sunt date versionate (indexul salvat e înghețat); designul are verdict doar de la colorist, pe cadre reale.
struct LookBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        let l = Binding(get: { ed.adjustments.look }, set: { ed.adjustments.look = $0 })
        Box(title: L("Look (caracter)"), panel: "look", summary: l.wrappedValue.on ? LookSettings.names[min(l.wrappedValue.look, LookSettings.names.count - 1)] : nil, module: ed.moduleBinding("look"),
            reset: SectionReset(help: L("Resetează secțiunea «Look»; poți anula"), isNeutral: !l.wrappedValue.on && l.wrappedValue == LookSettings()) { ed.resetSection(L("Look")) { $0.look = LookSettings() } }) {
            Toggle(L("Folosește un look"), isOn: l.on).toggleStyle(.switch).controlSize(.small).font(Theme.f(12.5))
            Text(L("Rețetă de caracter (ton, relații de paletă, densitate, cast), aplicată în cod log după Culoare/Piele și înaintea Lumini și gamă și a GDC DRT. Nu e profilul tău personal.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            if l.wrappedValue.on {
                Picker(L("Look"), selection: l.look) { ForEach(Array(LookSettings.names.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) } }.font(Theme.f(12))
                Text(L("Caracter")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
                SliderRow(label: L("Contrast"), value: l.contrast, range: -1...1, fmt: "%+.2f"); SliderRow(label: L("Negruri"), help: L("Turtite / ridicate"), value: l.blacks, range: -1...1, fmt: "%+.2f"); SliderRow(label: L("Roll-off lumini"), value: l.roll, range: -1...1, fmt: "%+.2f")
                SliderRow(label: L("Culoarea look-ului"), value: l.color, range: 0...1.5, neutral: 1, fmt: "%.2f"); SliderRow(label: L("Saturație"), value: l.sat, range: -1...1, fmt: "%+.2f"); SliderRow(label: L("Căldură"), help: L("Rece ↔ cald"), value: l.warm, range: -1...1, fmt: "%+.2f")
                SliderRow(label: L("Protejează pielea"), value: l.protectSkin, range: 0...1, neutral: 0.5, fmt: "%.2f")
                SliderRow(label: L("Intensitate"), value: l.strength, range: 0...1.5, neutral: 1, fmt: "%.2f")
            }
            Details { Text(L("Intensitatea scalează parametrii rețetei (nu un amestec de imagini): 0 = original, 1 = ca la proiectare, peste 1 = mai departe, la jumătate de viteză. Pielea (detectată din culoare, nu din persoană) primește doar partea tonală a look-ului.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
