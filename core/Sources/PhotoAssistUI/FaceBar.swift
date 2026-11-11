import SwiftUI
import AppKit
import PhotoCore

/// Bara de fețe și subiect (Selecție): fețele detectate de Vision (sugestii), subiectul prioritar ales de fotograf (față sau zonă manuală, și când nu s-a detectat nicio față), lupă la 100% pe zonă, indicii explicabile și reversibile.
/// Nu schimbă decizii, nu alege cadre, nu respinge nimic. Rezultatele de claritate locală sunt un INDICIU, nu dovada focalizării corecte pe ochi.
struct FaceBar: View {
    @ObservedObject var session: SelectionSession; @ObservedObject var faces: FaceCenter
    @EnvironmentObject var store: ImageStore
    @State private var sharp: [(name: String, p90: Double, noise: Double, current: Bool)] = []
    var body: some View {
        if let c = session.current {
            let res = faces.result(c); let subj = faces.subject(c)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(L("Fețe și subiect")).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted)
                    Badge(text: L("experimental"), color: Theme.check, dashed: true)
                    Spacer()
                    if faces.running { ProgressView(value: Double(faces.done), total: Double(max(1, faces.total))).frame(width: 90).tint(Theme.accent); Text("\(faces.done)/\(faces.total)").font(Theme.f(11, design: .monospaced)).foregroundColor(Theme.muted)
                        Button(L("Anulează")) { faces.cancel() }.buttonStyle(SoftButtonStyle()) }
                    else {
                        let group = session.group(of: c.id).map { g in session.photos.filter { g.memberIds.contains($0.id) } } ?? [c]
                        let pg = faces.pending(group), pa = faces.pending(session.photos)
                        if !pg.isEmpty { Button(faces.done > 0 && faces.done < faces.total ? L("Reia (grup)") : (group.count > 1 ? LF("Analizează grupul (%@)", pg.count) : L("Analizează cadrul"))) { faces.start(group) }.buttonStyle(SoftButtonStyle()) }
                        if !pa.isEmpty && pa.count > pg.count { Button(LF("Analizează toate (%@)", pa.count)) { faces.start(session.photos) }.buttonStyle(SoftButtonStyle()) }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if let r = res { ForEach(Array(r.faces.enumerated()), id: \.offset) { i, f in chip(c, r, i, f, subj) } }
                        if let z = subj.zone, subj.kind == "zone" { zoneChip(c, z) }
                        Button { faces.drawingZone.toggle() } label: { Label(faces.drawingZone ? L("Trage pe fotografie…") : L("Zonă manuală"), systemImage: "viewfinder.rectangular").lineLimit(1) }.buttonStyle(SoftButtonStyle(active: faces.drawingZone)).help(L("Desenează un dreptunghi peste subiectul important; funcționează și când nu se detectează nicio față"))
                        if subj.kind != "none" { Button { faces.setSubject(SubjectState(), c) } label: { Text(L("Fără subiect ales")).lineLimit(1) }.buttonStyle(SoftButtonStyle()).help(L("Anulează alegerea subiectului")) }
                    }
                }
                if !subj.dismissed { ForEach(faces.hints(c)) { h in
                    HStack(alignment: .top, spacing: 6) { Image(systemName: h.symbol).foregroundColor(Theme.auto).frame(width: Theme.px(16)); VStack(alignment: .leading, spacing: 1) { Text(h.title).font(Theme.f(11.5, weight: .semibold)); Text(h.why).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) } }
                } }
                HStack { Button { var s = subj; s.dismissed.toggle(); faces.setSubject(s, c) } label: { Text(subj.dismissed ? L("Arată sugestiile") : L("Ascunde sugestiile pentru acest cadru")).lineLimit(1) }.buttonStyle(SoftButtonStyle()); Spacer() }
                if !sharp.isEmpty { VStack(alignment: .leading, spacing: 2) {
                    Text(L("Claritate locală pe zona subiectului (indiciu, același grup, aceeași zonă):")).font(Theme.f(10.5, weight: .semibold)).foregroundColor(Theme.muted)
                    ForEach(Array(sharp.enumerated()), id: \.offset) { _, s in Text(LF("%@%@ · gradient p90 %@ · zgomot %@", s.current ? "▸ " : "  ", s.name, String(format: "%.1f", s.p90), String(format: "%.1f", s.noise))).font(Theme.f(10.5, design: .monospaced)).foregroundColor(s.current ? Theme.text : Theme.muted) }
                    Text(L("Nu dovedește focalizarea corectă pe ochi; textura fundalului, zgomotul și sharpening-ul pot induce în eroare; nu se alege automat un cadru.")).font(Theme.f(10)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) } }
                if let r = res { Text(LF("Analiză: %@ fețe pe previzualizarea %@×%@ · %@ ms · %@", r.faces.count, r.previewW, r.previewH, String(format: "%.0f", r.seconds * 1000), r.config)).font(Theme.f(10)).foregroundColor(Theme.faint) }
            }.padding(10).background(Theme.panel).task(id: SharpKey(photo: c.id, subj: subj, tick: faces.tick)) { await computeSharp(c, subj, res) }
        }
    }
    struct SharpKey: Hashable { var photo: Int64; var subj: SubjectState; var tick: Int }
    func region(_ subj: SubjectState, _ r: FaceResult?) -> CGRect? {
        if subj.kind == "face", let i = subj.face, let f = r?.faces[safe: i] { return CGRect(x: f.box[0], y: f.box[1], width: f.box[2], height: f.box[3]) }
        if subj.kind == "zone", let z = subj.zone, z.count == 4 { return CGRect(x: z[0], y: z[1], width: z[2], height: z[3]) }; return nil
    }
    func computeSharp(_ c: PhotoRecord, _ subj: SubjectState, _ r: FaceResult?) async {
        guard let rg = region(subj, r) else { sharp = []; return }
        let members = session.group(of: c.id).map { g in session.photos.filter { g.memberIds.contains($0.id) } } ?? [c]; var out: [(String, Double, Double, Bool)] = []
        for m in members { if let ns = await store.image(for: m, kind: .view), let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil), let s = FaceAnalyzer.localSharpness(cg, region: rg) { out.append(((m.path as NSString).lastPathComponent, s.value, s.noise, m.id == c.id)) } }
        sharp = out.map { (name: $0.0, p90: $0.1, noise: $0.2, current: $0.3) }
    }
    func eyeText(_ f: StoredFace) -> String { let b = FaceAnalyzer.blinkSuggestion(FaceAnalyzer.observation(f)); switch b.state { case .closed: return L("✕ posibil închiși"); case .open: return "◉ deschiși"; case .uncertain: return "? incert"; case .notEvaluated: return L("– neevaluat") } }
    func chip(_ c: PhotoRecord, _ r: FaceResult, _ i: Int, _ f: StoredFace, _ subj: SubjectState) -> some View {
        let chosen = subj.kind == "face" && subj.face == i
        return HStack(spacing: 6) {
            FaceThumb(photo: c, box: f.box).frame(width: Theme.px(46), height: Theme.px(46)).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(LF("%@Față %@", chosen ? "★ " : "", i + 1)).font(Theme.f(11.5, weight: .semibold)); Text(L("ochi: ") + eyeText(f)).font(Theme.f(10.5)).foregroundColor(Theme.muted)
                HStack(spacing: 4) {
                    Button { faces.setSubject(chosen ? SubjectState() : .face(i), c) } label: { Text(chosen ? L("Subiect ✓") : L("Alege subiect")).lineLimit(1) }.buttonStyle(SoftButtonStyle(active: chosen))
                    Button { faces.focus = CGRect(x: f.box[0], y: f.box[1], width: f.box[2], height: f.box[3]); session.detail100 = true } label: { Image(systemName: "plus.magnifyingglass") }.buttonStyle(SoftButtonStyle()).help(L("Lupă la 100% pe față"))
                }
            }
        }.padding(6).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chosen ? Theme.accent : Theme.line, lineWidth: chosen ? 2 : 1))
    }
    func zoneChip(_ c: PhotoRecord, _ z: [Double]) -> some View {
        HStack(spacing: 6) { Image(systemName: "viewfinder.rectangular"); VStack(alignment: .leading, spacing: 2) { Text(L("★ Zonă manuală")).font(Theme.f(11.5, weight: .semibold))
            Button { faces.focus = CGRect(x: z[0], y: z[1], width: z[2], height: z[3]); session.detail100 = true } label: { Image(systemName: "plus.magnifyingglass") }.buttonStyle(SoftButtonStyle()).help(L("Lupă la 100% pe zonă")) } }
            .padding(6).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent, lineWidth: 2))
    }
}
extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

struct FaceThumb: View {
    let photo: PhotoRecord; let box: [Double]
    @EnvironmentObject var store: ImageStore; @State private var img: NSImage?
    var body: some View { Group { if let i = img { Image(nsImage: i).resizable().aspectRatio(contentMode: .fill) } else { Rectangle().fill(Theme.panel2) } }.task(id: photo.id) {
        if let ns = await store.image(for: photo, kind: .view), let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let pad = 0.25; let x = max(0, box[0] - box[2] * pad), y = max(0, box[1] - box[3] * pad), w = min(1 - x, box[2] * (1 + 2 * pad)), h = min(1 - y, box[3] * (1 + 2 * pad))
            if let cr = cg.cropping(to: CGRect(x: x * Double(cg.width), y: y * Double(cg.height), width: w * Double(cg.width), height: h * Double(cg.height))) { img = NSImage(cgImage: cr, size: .zero) } } } }
}

/// Suprapunere pe fotografie: dreptunghiuri de față (cu număr, nu doar culoare), subiectul ales cu ★, zona manuală; desenarea unei zone prin tragere.
struct FaceOverlay: View {
    @ObservedObject var faces: FaceCenter; let photo: PhotoRecord
    @State private var start: CGPoint?; @State private var cur: CGPoint?
    var body: some View {
        GeometryReader { g in
            if let r = faces.result(photo), r.previewW > 0 {
                let s = min(g.size.width / CGFloat(r.previewW), g.size.height / CGFloat(r.previewH)); let w = CGFloat(r.previewW) * s, h = CGFloat(r.previewH) * s; let ox = (g.size.width - w) / 2, oy = (g.size.height - h) / 2; let subj = faces.subject(photo)
                ZStack {
                    ForEach(Array(r.faces.enumerated()), id: \.offset) { i, f in
                        let chosen = subj.kind == "face" && subj.face == i
                        Rectangle().stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: chosen ? 2.5 : 1.2, dash: chosen ? [] : [4, 3])).frame(width: CGFloat(f.box[2]) * w, height: CGFloat(f.box[3]) * h)
                            .overlay(alignment: .topLeading) { Text("\(chosen ? "★ " : "")\(i + 1)").font(Theme.f(10.5, weight: .bold)).foregroundColor(.black).padding(.horizontal, 4).background(Color.white.opacity(0.9)).offset(y: -16) }
                            .position(x: ox + (CGFloat(f.box[0]) + CGFloat(f.box[2]) / 2) * w, y: oy + (CGFloat(f.box[1]) + CGFloat(f.box[3]) / 2) * h).allowsHitTesting(false)
                    }
                    if subj.kind == "zone", let z = subj.zone, z.count == 4 { Rectangle().stroke(Color(red: 1, green: 0.85, blue: 0.3), style: StrokeStyle(lineWidth: 2.5)).frame(width: CGFloat(z[2]) * w, height: CGFloat(z[3]) * h).overlay(alignment: .topLeading) { Text(L("★ zonă")).font(Theme.f(10.5, weight: .bold)).foregroundColor(.black).padding(.horizontal, 4).background(Color(red: 1, green: 0.85, blue: 0.3)).offset(y: -16) }.position(x: ox + (CGFloat(z[0]) + CGFloat(z[2]) / 2) * w, y: oy + (CGFloat(z[1]) + CGFloat(z[3]) / 2) * h).allowsHitTesting(false) }
                    if faces.drawingZone {
                        Color.white.opacity(0.001).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 4).onChanged { v in start = v.startLocation; cur = v.location }.onEnded { v in
                            let x0 = min(v.startLocation.x, v.location.x), y0 = min(v.startLocation.y, v.location.y), x1 = max(v.startLocation.x, v.location.x), y1 = max(v.startLocation.y, v.location.y)
                            let nx0 = max(0, (x0 - ox) / w), ny0 = max(0, (y0 - oy) / h), nx1 = min(1, (x1 - ox) / w), ny1 = min(1, (y1 - oy) / h)
                            if nx1 - nx0 > 0.01, ny1 - ny0 > 0.01 { faces.setSubject(.zone([Double(nx0), Double(ny0), Double(nx1 - nx0), Double(ny1 - ny0)]), photo) }
                            faces.drawingZone = false; start = nil; cur = nil })
                        if let a = start, let b = cur { Rectangle().stroke(Color(red: 1, green: 0.85, blue: 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(width: abs(b.x - a.x), height: abs(b.y - a.y)).position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2).allowsHitTesting(false) }
                    }
                }
            }
        }
    }
}
