import SwiftUI
import PhotoCore
import PhotoResolve

/// Lab D50 → sRGB (afișare) pentru mostrele de referință; Bradford D50→D65, curba sRGB. Doar pentru interfață (nu intră în calcul).
func chartSwatchColor(lab: [Double]) -> Color {
    let fy = (lab[0] + 16) / 116, fx = fy + lab[1] / 500, fz = fy - lab[2] / 200; func fi(_ t: Double) -> Double { t > 6.0 / 29 ? t * t * t : 3 * pow(6.0 / 29, 2) * (t - 4.0 / 29) }
    let X = 0.9642 * fi(fx), Y = fi(fy), Z = 0.8249 * fi(fz)
    let x = 0.9555766 * X - 0.0230393 * Y + 0.0631636 * Z, y = -0.0282895 * X + 1.0099416 * Y + 0.0210077 * Z, z = 0.0122982 * X - 0.0204830 * Y + 1.3299098 * Z
    let r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z, g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z, b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
    func e(_ c: Double) -> Double { let v = min(1, max(0, c)); return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }
    return Color(red: e(r), green: e(g), blue: e(b))
}

/// Grila chartului peste fotografie: 4 colțuri trase cu mouse-ul (perspectivă), mutare a întregii grile prin tragere în interior; numere 1–24, mostre de referință, marcaj «SUS» și colțuri A–D ca orientarea să fie lipsită de ambiguitate. Doar ghidaj: nu apare în export.
struct ChartOverlay: View {
    @ObservedObject var ed: EditingModel; let r: CGRect
    @State private var dragStart: [CGPoint]?
    var map: GeoMap { GeoMap(r: CGRect(x: 0, y: 0, width: r.width, height: r.height), geo: ed.adjustments.geometry, source: ed.sourceSize, effects: ed.adjustments.effective.effects) }
    func v(_ p: CGPoint) -> CGPoint { map.fwd(Double(p.x), Double(p.y)) }
    func src(_ p: CGPoint) -> CGPoint { let q = map.inv(p); return CGPoint(x: min(1.5, max(-0.5, q.x)), y: min(1.5, max(-0.5, q.y))) }
    func vp(_ lx: Double, _ ly: Double) -> CGPoint { v(ed.chartGrid.imagePoint(logicalX: lx, logicalY: ly)) }
    var body: some View {
        let g = ed.chartGrid; let patches = ChartReference.load(ed.chartModel)?.patches ?? []; let bad = ed.chartValidation?.issues ?? [:]
        ZStack {
            if !g.isValid {   // stare INVALIDĂ: doar conturul roșu al colțurilor, fără celule/numere/ferestre de eșantionare (nu se desenează haotic, nu se poate valida)
                Canvas { ctx, _ in
                    var q = Path(); q.move(to: v(g.corners[0])); for i in 1..<4 { q.addLine(to: v(g.corners[i])) }; q.closeSubpath()
                    ctx.stroke(q, with: .color(Color.black.opacity(0.6)), lineWidth: 4); ctx.stroke(q, with: .color(Theme.reject), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }.allowsHitTesting(false)
                VStack(spacing: 4) {
                    Text(LF("Grilă nevalidă: %@", g.invalidReason ?? "")).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    Button(L("Revino la ultima grilă validă")) { ed.chartRestoreLastValid() }.buttonStyle(SoftButtonStyle())
                }.padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.75))).position(x: r.width / 2, y: 60)
            }
            else { Canvas { ctx, _ in
                var field = Path(); field.move(to: vp(0, 0)); field.addLine(to: vp(6, 0)); field.addLine(to: vp(6, 4)); field.addLine(to: vp(0, 4)); field.closeSubpath()
                ctx.fill(field, with: .color(Color.black.opacity(0.10)))
                for i in 0..<min(24, patches.count) {   // cele 24 de petice, în culoarea de referință, semitransparente (opacitate reglabilă) cu contur dublu lizibil pe orice fundal
                    let c = Double(i % 6), rr = Double(i / 6); var q = Path(); q.move(to: vp(c + 0.04, rr + 0.04)); q.addLine(to: vp(c + 0.96, rr + 0.04)); q.addLine(to: vp(c + 0.96, rr + 0.96)); q.addLine(to: vp(c + 0.04, rr + 0.96)); q.closeSubpath()
                    ctx.fill(q, with: .color(chartSwatchColor(lab: patches[i].lab).opacity(ed.chartOverlayOpacity)))
                    ctx.stroke(q, with: .color(Color.black.opacity(0.55)), lineWidth: 2.5); ctx.stroke(q, with: .color(Color.white.opacity(0.9)), lineWidth: 1)
                }
                ctx.stroke(field, with: .color(Theme.accent), lineWidth: 2)
                for c in 1..<6 { var l = Path(); l.move(to: vp(Double(c), 0)); l.addLine(to: vp(Double(c), 4)); ctx.stroke(l, with: .color(Theme.accent.opacity(0.55)), lineWidth: 1) }
                for rr in 1..<4 { var l = Path(); l.move(to: vp(0, Double(rr))); l.addLine(to: vp(6, Double(rr))); ctx.stroke(l, with: .color(Theme.accent.opacity(0.55)), lineWidth: 1) }
                for i in 1...24 {   // fereastra de eșantionare (50% centrală) + stare
                    let c = Double((i - 1) % 6) + 0.5, rr = Double((i - 1) / 6) + 0.5, h = ChartSampler.windowFraction / 2; var w = Path(); w.move(to: vp(c - h, rr - h)); w.addLine(to: vp(c + h, rr - h)); w.addLine(to: vp(c + h, rr + h)); w.addLine(to: vp(c - h, rr + h)); w.closeSubpath()
                    ctx.stroke(w, with: .color(bad[i] == nil ? Color.white.opacity(0.85) : Theme.reject), lineWidth: bad[i] == nil ? 1 : 2) }
            }.allowsHitTesting(false) }
            if g.isValid { ForEach(0..<patches.count, id: \.self) { i in
                let c = Double(i % 6) + 0.5, rr = Double(i / 6) + 0.5; let p = vp(c, rr)
                Text("\(i + 1)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.white).shadow(color: .black, radius: 1.5).shadow(color: .black, radius: 1).position(p).allowsHitTesting(false)
            }
            // orientare: «SUS» la mijlocul marginii superioare logice + colțuri A–D (A = stânga-sus logic)
            Text(L("▲ SUS")).font(.system(size: 11, weight: .heavy)).foregroundColor(.black).padding(.horizontal, 5).background(Capsule().fill(Theme.check)).position(x: vp(3, -0.25).x, y: vp(3, -0.25).y).allowsHitTesting(false)
            ForEach(Array([("A", 0.0, 0.0), ("B", 6.0, 0.0), ("C", 6.0, 4.0), ("D", 0.0, 4.0)].enumerated()), id: \.offset) { _, t in
                Text(t.0).font(.system(size: 10, weight: .heavy)).foregroundColor(.black).frame(width: 16, height: 16).background(Circle().fill(Theme.check)).position(vp(t.1 == 0 ? -0.35 : 6.35, t.2 == 0 ? -0.35 : 4.35)).allowsHitTesting(false) }
            }
            // mutare a întregii grile prin tragere în interior
            Path { p in p.move(to: vp(0, 0)); p.addLine(to: vp(6, 0)); p.addLine(to: vp(6, 4)); p.addLine(to: vp(0, 4)); p.closeSubpath() }.fill(Color.clear).contentShape(Path { p in p.move(to: vp(0.4, 0.4)); p.addLine(to: vp(5.6, 0.4)); p.addLine(to: vp(5.6, 3.6)); p.addLine(to: vp(0.4, 3.6)); p.closeSubpath() })
                .gesture(DragGesture(minimumDistance: 2).onChanged { d in
                    guard dragStart != nil || ed.viewer.accepts(d.startLocation, in: r) else { return }
                    if dragStart == nil { dragStart = ed.chartGrid.corners }; guard let s0 = dragStart else { return }
                    let a = map.inv(CGPoint(x: d.startLocation.x, y: d.startLocation.y)), b = map.inv(CGPoint(x: d.location.x, y: d.location.y)); let dx = b.x - a.x, dy = b.y - a.y
                    ed.chartGrid.corners = s0.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }; ed.chartValidation = nil; ed.chartProposal = nil }.onEnded { _ in dragStart = nil })
            // cele 4 colțuri (în ordinea imaginii TL, TR, BR, BL)
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(Theme.accent).overlay(Circle().stroke(Color.white, lineWidth: 2)).frame(width: 16, height: 16).position(v(g.corners[i]))
                    .gesture(DragGesture(minimumDistance: 0).onChanged { d in ed.chartGrid.corners[i] = src(d.location); ed.chartValidation = nil; ed.chartProposal = nil }).help(LF("Colț %@ al câmpului de petice", [L("stânga-sus"), L("dreapta-sus"), L("dreapta-jos"), L("stânga-jos")][i]))
            }
        }.frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
    }
}

struct ChartBox: View {
    @ObservedObject var ed: EditingModel; @ObservedObject var model: AppModel
    @State private var groupOpen = false
    var body: some View {
        Box(title: L("Chart de culoare (ColorChecker)"), panel: "chart", summary: ed.adjustments.chart == nil ? nil : L("activ"), module: ed.moduleBinding("chart"),
            reset: SectionReset(help: L("Elimină corecția chartului de la această fotografie; poți anula"), isNeutral: ed.adjustments.chart == nil) { ed.chartRemove() }) {
            Text(L("Corecție TEHNICĂ după un chart fotografiat în aceeași lumină. Se aplică la intrarea lanțului (după decodare, înaintea expunerii, a stilizării și a transformării de afișare); nu e profilul tău artistic și nu e un efect creativ.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            NominalReferenceNote()
            ChartReferenceStrip(ed: ed)
            Picker(L("Model"), selection: $ed.chartModel) { ForEach(ChartModelID.allCases) { Text($0.label).tag($0) } }.font(Theme.f(11.5)).onChange(of: ed.chartModel) { _ in ed.chartValidation = nil; ed.chartProposal = nil; ed.saveChartSession() }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], alignment: .leading, spacing: 6) {
                Button { ed.activeTool = ed.activeTool == .chart ? .view : .chart; if ed.activeTool == .chart { ed.guidesHidden = false } } label: { Label(ed.activeTool == .chart ? "Ascunde grila" : L("Arată grila"), systemImage: "grid").lineLimit(1) }.buttonStyle(SoftButtonStyle(active: ed.activeTool == .chart))
                Button { ed.chartRotate() } label: { Label(L("Rotește 90°"), systemImage: "rotate.right").lineLimit(1) }.buttonStyle(SoftButtonStyle()).help(L("Rotește orientarea logică a chartului (SUS, A–D) fără a muta colțurile"))
                Button { ed.chartMirror() } label: { Label(L("Oglindește"), systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right").lineLimit(1) }.buttonStyle(SoftButtonStyle(active: ed.chartGrid.mirrored))
                Button(L("Resetează grila")) { ed.chartResetGrid() }.buttonStyle(SoftButtonStyle())
            }
            Text(L("Trage cele 4 colțuri (puncte albastre) peste câmpul de petice, inclusiv în perspectivă; trage în interior pentru a muta grila. Chenarul de sus marchează SUS al chartului (rândul neutru 19–24 e jos); A–D sunt colțurile chartului. Petice numerotate 1–24 cu mostra de referință.")).font(Theme.f(11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Button { ed.chartValidate() } label: { Label(ed.chartBusy ? "Validez…" : L("Validează"), systemImage: "checkmark.seal").lineLimit(1) }.buttonStyle(PrimaryButtonStyle()).disabled(ed.chartBusy || ed.current == nil || !ed.isReady || !ed.chartGrid.isValid).help(ed.chartGrid.isValid ? L("Eșantionează peticele și propune corecția") : "Grila e nevalidă: \(ed.chartGrid.invalidReason ?? "")")
            if !ed.chartMessage.isEmpty { Text(ed.chartMessage).font(Theme.f(11.5)).foregroundColor(ed.chartValidation?.ok == false ? Theme.reject : Theme.text).fixedSize(horizontal: false, vertical: true) }
            if let v = ed.chartValidation { PatchStatusGrid(validation: v, model: ed.chartModel) }
            if let c = ed.chartProposal { Proposal(ed: ed, c: c, model: model, groupOpen: $groupOpen) }
            else if let a = ed.adjustments.chart { AppliedInfo(ed: ed, c: a, model: model, groupOpen: $groupOpen) }
            Details(title: L("Modele, date și limite")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Modele susținute (geometrie + date de referință verificate): X-Rite ColorChecker Classic — ediția după noiembrie 2014 și ediția Legacy (înainte de noiembrie 2014), ca în DaVinci Resolve. Datele: valori publicate de producător (CIE 1931 2°, D50), nu valorile spectrale ale exemplarului tău; un chart vechi sau murdar poate devia.")).font(Theme.f(11)).foregroundColor(Theme.faint)
                    Text(L("ColorChecker Passport (Video / Photo): panoul inscripționat «Classic» are aranjamentul Classic de 24 de petice; se poate folosi cu modelul Classic ALES DE TINE, ca REFERINȚĂ NOMINALĂ (valori publicate pentru Classic; fără confirmarea producătorului pentru exemplarul tău). Celelalte panouri ale Passport, Datacolor SpyderCheckr 24, DSC Labs ChromaDuMonde 24+4 și SMPTE OneShot rămân nesusținute (fără geometrie și valori de referință verificate).")).font(Theme.f(11)).foregroundColor(Theme.faint)
                    Text(L("Validarea marchează peticele tăiate, prea întunecate, neuniforme sau cu reflexii și refuză corecția dacă datele nu sunt suficiente (minimum 18 petice utilizabile, 4 neutre). Eroarea se raportează în CIEDE2000 (Lab D50); «leave-one-out» arată predicția pe un petic neutilizat la calcul. Reducerea erorii pe peticele folosite NU garantează acuratețea întregii fotografii.")).font(Theme.f(11)).foregroundColor(Theme.faint)
                }.fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $groupOpen) { ChartGroupSheet(ed: ed, model: model) }
    }
}
/// Referința chartului, separată de imagine: cele 24 de petice ale modelului ales, cu numerele lor (valori din datele de referință verificate, nu ilustrative).
struct ChartReferenceStrip: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        let ref = ChartReference.load(ed.chartModel)?.patches ?? []
        if !ref.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(LF("Referința modelului (%@)", ed.chartModel.label)).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 6), spacing: 2) {
                    ForEach(0..<min(24, ref.count), id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(chartSwatchColor(lab: ref[i].lab)).frame(height: Theme.px(18)).overlay(Text("\(i + 1)").font(Theme.f(8.5, weight: .bold, design: .monospaced)).foregroundColor(Color.white.opacity(0.9)).shadow(color: .black, radius: 1))
                    }
                }
                HStack(spacing: 6) { Text(L("Opacitate în imagine")).font(Theme.f(11)).foregroundColor(Theme.muted); Slider(value: $ed.chartOverlayOpacity, in: 0...1).controlSize(.small).tint(Theme.accent); Text("\(Int((ed.chartOverlayOpacity * 100).rounded()))%").font(Theme.f(11, design: .monospaced)).foregroundColor(Theme.text).frame(minWidth: Theme.px(36), alignment: .trailing) }
            }
        }
    }
}
struct PatchStatusGrid: View {
    let validation: ChartValidation; let model: ChartModelID
    var body: some View {
        let ref = ChartReference.load(model)?.patches ?? []
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<4, id: \.self) { r in HStack(spacing: 3) { ForEach(0..<6, id: \.self) { c in let i = r * 6 + c + 1; let iss = validation.issues[i]
                ZStack { RoundedRectangle(cornerRadius: 3).fill(ref.indices.contains(i - 1) ? chartSwatchColor(lab: ref[i - 1].lab) : Color.gray); Text("\(i)").font(.system(size: 10, weight: .bold)).foregroundColor(.white).shadow(radius: 1)
                    if iss != nil { RoundedRectangle(cornerRadius: 3).stroke(Theme.reject, lineWidth: 2); Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundColor(Theme.reject) } }
                    .frame(height: 26).help(iss.map { "\(i) \(ref.indices.contains(i - 1) ? ref[i - 1].name : ""): " + $0.map { $0.label }.joined(separator: ", ") } ?? "\(i): utilizabil") } } }
            ForEach(validation.issues.keys.sorted(), id: \.self) { i in Text("\(i) \(ref.indices.contains(i - 1) ? ref[i - 1].name : ""): " + (validation.issues[i] ?? []).map { $0.label }.joined(separator: ", ")).font(Theme.f(10.5)).foregroundColor(Theme.check) }
        }
    }
}
struct Proposal: View {
    @ObservedObject var ed: EditingModel; let c: ChartCorrection; @ObservedObject var model: AppModel; @Binding var groupOpen: Bool
    var body: some View {
        let ref = ChartReference.load(c.model)?.patches ?? []; let m = c.metrics
        VStack(alignment: .leading, spacing: 5) {
            Text(L("Corecție propusă · pe referință nominală")).font(Theme.f(12, weight: .semibold))
            Text(String(format: L("CIEDE2000 (Lab D50, 2°) pe cele %d petice folosite: medie %.2f → %.2f, maxim %.2f → %.2f."), m.patches, m.meanBefore, m.meanAfter, m.maxBefore, m.maxAfter)).font(Theme.f(11.5))
            Text(String(format: L("Predicție pe petic neutilizat (leave-one-out): medie %.2f, maxim %.2f — estimare mai onestă decât cifra de pe peticele folosite; nu garantează restul fotografiei."), m.looMean, m.looMax)).font(Theme.f(11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Text(String(format: L("Neutrele sunt cu %+.2f EV față de nivelul de referință (informativ: expunerea NU se modifică)."), c.exposureOffsetEV)).font(Theme.f(10.5)).foregroundColor(Theme.faint)
            Text(L("Înainte / după (mostre; sus: referință):")).font(Theme.f(10.5)).foregroundColor(Theme.faint)
            HStack(spacing: 2) { ForEach(0..<ref.count, id: \.self) { i in chartSwatchColor(lab: ref[i].lab).frame(height: 8) } }
            HStack(spacing: 8) {
                Button(L("Aplică corecția")) { ed.chartApply() }.buttonStyle(PrimaryButtonStyle())
                if ed.adjustments.chart != nil { Button(L("Compară fără (dezactivează)")) { ed.adjustments.disabledModules.insert("chart") }.buttonStyle(SoftButtonStyle()) }
            }
            Text(L("Comparație vizuală: comută modulul din antetul secțiunii (activ/inactiv) sau folosește «Anulează» din banner după aplicare.")).font(Theme.f(10.5)).foregroundColor(Theme.faint)
        }.padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel2))
    }
}
struct AppliedInfo: View {
    @ObservedObject var ed: EditingModel; let c: ChartCorrection; @ObservedObject var model: AppModel; @Binding var groupOpen: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LF("Corecția chartului e aplicată acestei fotografii%@", ed.adjustments.isModuleEnabled("chart") ? "" : L(" (DEZACTIVATĂ)"))).font(Theme.f(12, weight: .semibold))
            Text(String(format: L("Calculată din %d petice (%@); CIEDE2000 %.2f → %.2f, leave-one-out %.2f. Cameră: %@."), c.metrics.patches, c.model.label, c.metrics.meanBefore, c.metrics.meanAfter, c.metrics.looMean, c.cameraKey ?? L("necunoscută"))).font(Theme.f(11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) { Button(L("Aplică unui grup ales…")) { groupOpen = true }.buttonStyle(SoftButtonStyle()); Button(L("Elimină corecția")) { ed.chartRemove() }.buttonStyle(SoftButtonStyle()) }
        }.padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel2))
    }
}
/// Grupul se alege EXPLICIT (nimic preselectat). Fotografiile cu altă cameră decât sursa chartului sunt marcate și cer confirmare separată.
struct ChartGroupSheet: View {
    @ObservedObject var ed: EditingModel; @ObservedObject var model: AppModel; @Environment(\.dismiss) var dismiss
    @State private var chosen = Set<Int64>(); @State private var allowOtherCamera = false; @State private var result = ""
    var body: some View {
        let src = ed.adjustments.chart ?? ed.chartProposal; let cam = src?.cameraKey; let photos = model.editQueue
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(L("Aplică corecția unui grup")).font(Theme.f(17, weight: .semibold)); Spacer(); Button(L("Închide")) { dismiss() }.buttonStyle(SoftButtonStyle()) }
            Text(LF("Corecția e valabilă pentru aceeași cameră și aceeași lumină. Nu se propagă automat: alege fotografiile (coada de editare). Camera sursei: %@.", cam ?? L("necunoscută"))).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack { Button(L("Selectează aceeași cameră")) { chosen = Set(photos.filter { $0.camera == cam }.map { $0.id }) }.buttonStyle(SoftButtonStyle()).disabled(cam == nil); Button(L("Deselectează")) { chosen = [] }.buttonStyle(SoftButtonStyle()) }
            ScrollView { VStack(alignment: .leading, spacing: 3) { ForEach(photos, id: \.id) { p in
                let other = p.camera != cam
                Toggle(isOn: Binding(get: { chosen.contains(p.id) }, set: { if $0 { chosen.insert(p.id) } else { chosen.remove(p.id) } })) {
                    HStack { Text((p.path as NSString).lastPathComponent).font(Theme.f(12)); Text(p.camera ?? "—").font(Theme.f(11)).foregroundColor(other ? Theme.check : Theme.faint); if other { Text(L("altă cameră")).font(Theme.f(10.5)).foregroundColor(Theme.check) } } }.toggleStyle(.checkbox) } } }.frame(minHeight: 160, maxHeight: 320)
            let mism = photos.filter { chosen.contains($0.id) && $0.camera != cam }.count
            if mism > 0 { Toggle(LF("Confirm explicit: %@ fotografii au altă cameră decât chartul și le includ oricum", mism), isOn: $allowOtherCamera).font(Theme.f(11.5)).foregroundColor(Theme.check) }
            HStack { Button(LF("Aplică la %@ fotografii", chosen.count)) { let ids = photos.filter { chosen.contains($0.id) && (allowOtherCamera || $0.camera == cam) }.map { $0.id }; let r = ed.chartApplyToGroup(ids); result = LF("Aplicat %@; omise %@ (altă cameră neconfirmată).", r.applied, r.skipped + (chosen.count - ids.count)) }.buttonStyle(PrimaryButtonStyle()).disabled(chosen.isEmpty)
                Text(result).font(Theme.f(11.5)).foregroundColor(Theme.muted) }
        }.padding(20).frame(minWidth: 560, minHeight: 420).background(Theme.app).foregroundColor(Theme.text)
    }
}

/// Eticheta permanentă a corecției pe referință NOMINALĂ: ediția e PRESUPUSĂ, valorile sunt cele publicate pentru Classic, nu cele măsurate pe exemplarul fotografiat.
struct NominalReferenceNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) { Image(systemName: "info.circle").foregroundColor(Theme.auto); Text(L("Corecție pe referință NOMINALĂ")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.auto) }
            Text(L("Ediția chartului e presupusă din modelul ales; valorile sunt cele PUBLICATE pentru ColorChecker Classic, nu valori măsurate pe exemplarul tău (un chart real poate devia: lot, vechime, murdărie). Rezultatul e o corecție utilă și verificabilă, nu o garanție de acuratețe absolută.")).font(Theme.f(11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.auto.opacity(0.06))).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
