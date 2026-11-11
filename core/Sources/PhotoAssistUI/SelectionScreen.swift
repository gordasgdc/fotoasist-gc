import SwiftUI
import AppKit
import PhotoCore

struct SelectionScreen: View {
    @ObservedObject var session: SelectionSession
    @ObservedObject var faces: FaceCenter
    var onContinue: (_ all: Bool) -> Void
    var onEdit: (_ ids: [Int64], _ label: String) -> Void = { _, _ in }
    var onRemoveFromCatalog: (_ ids: [Int64]) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(session: session).frame(width: 224)
            Divider().overlay(Theme.line)
            VStack(spacing: 0) {
                TopBar(session: session)
                Divider().overlay(Theme.line)
                BatchBar(session: session, faces: faces, onRemoveFromCatalog: onRemoveFromCatalog)
                Divider().overlay(Theme.line)
                Stage(session: session, faces: faces).background(Theme.canvas)     // suprafață neutră; fără efecte peste fotografii
                if session.mode != .grid { Divider().overlay(Theme.line); Filmstrip(session: session) }   // în Grilă dublează aceleași fotografii
            }
            Divider().overlay(Theme.line)
            InfoPanel(session: session, faces: faces, onContinue: onContinue, onEdit: onEdit).frame(width: 300)
        }
        .background(Theme.app)
    }
}

// MARK: bara laterală: filtre; sugestiile apar DOAR când există
private struct Sidebar: View {
    @ObservedObject var session: SelectionSession
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Fotografii")).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted).padding(.leading, 10).padding(.bottom, 2)
                    ForEach([PhotoFilter.all, .check, .keep, .reject, .favorites], id: \.rawValue) { f in FilterRow(session: session, filter: f) }
                    CueFilterMenu(session: session).padding(.top, 6)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(L("Albume")).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted); Spacer()
                        Button { if let n = promptText(L("Album nou"), "Numele albumului (colecție virtuală; fotografiile originale nu se mută și nu se copiază):", initial: ""), !n.isEmpty { try? session.createAlbum(n, addTargets: false) } } label: { Image(systemName: "plus.circle") }.buttonStyle(.plain).help(L("Creează un album")) }.padding(.horizontal, 10)
                    if session.albums.isEmpty { Text(L("Niciun album. Albumele sunt colecții virtuale; o fotografie poate fi în mai multe.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).padding(.horizontal, 10) }
                    ForEach(session.albums) { a in
                        HStack(spacing: 6) {
                            Button { session.albumFilter = session.albumFilter == a.id ? nil : a.id } label: { HStack { Image(systemName: session.albumFilter == a.id ? "rectangle.stack.fill" : "rectangle.stack"); Text(a.name).lineLimit(1); Spacer(); Text("\(a.count)").font(Theme.f(11, design: .monospaced)).foregroundColor(Theme.muted) } }.buttonStyle(.plain)
                            Menu { Button(L("Redenumește…")) { if let n = promptText(L("Redenumește albumul"), L("Noul nume:"), initial: a.name), !n.isEmpty { try? session.renameAlbum(a.id, n) } }
                                   Button(L("Șterge albumul…"), role: .destructive) { if confirm("Ștergi albumul «\(a.name)»?", "Se șterge doar albumul. Fotografiile, reglajele, măștile, deciziile și fișierele originale NU se șterg.") { try? session.deleteAlbum(a.id) } } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        }.padding(.vertical, 3).padding(.horizontal, 10).background(session.albumFilter == a.id ? Theme.accent.opacity(0.18) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityAddTraits(session.albumFilter == a.id ? .isSelected : [])
                    }
                }
                if !session.groups.isEmpty { GroupsSection(session: session) }
            }.padding(12)
        }.background(Theme.panel)
    }
}
/// Sugestiile de rafale, grupate pe categorii (pliate implicit): nu o coloană de casete identice. Rândul unui grup selectează cadrele lui (decizia rămâne manuală); detaliile grupului = lista de cadre afișată sub rând.
private struct GroupsSection: View {
    @ObservedObject var session: SelectionSession
    @State private var open: Set<String> = []; @State private var all: Set<String> = []; @State private var expanded: Int?
    private let limit = 24
    var body: some View {
        let cats: [(id: String, title: String, groups: [SuggestedGroup])] = [
            ("burst-likely", L("Rafale probabile"), session.groups.filter { $0.kind == .burst && $0.confidence == .likely }),
            ("burst-weak", L("Rafale (semnal slab)"), session.groups.filter { $0.kind == .burst && $0.confidence != .likely }),
            ("similar", L("Posibil similare"), session.groups.filter { $0.kind != .burst })].filter { !$0.groups.isEmpty }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) { Text(L("Sugestii")).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted); AutoTag(text: L("validare incompletă")) }
            ForEach(cats, id: \.id) { c in
                let isOpen = open.contains(c.id); let frames = c.groups.reduce(0) { $0 + $1.memberIds.count }
                VStack(alignment: .leading, spacing: 4) {
                    Button { if isOpen { open.remove(c.id) } else { open.insert(c.id) } } label: {
                        HStack(spacing: 6) { Image(systemName: isOpen ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)); Text(c.title).font(Theme.f(12.5, weight: .semibold)); Spacer(); Text(LF("%@ · %@ cadre", c.groups.count, frames)).font(Theme.f(11)).foregroundColor(Theme.muted) }
                            .padding(.horizontal, 8).padding(.vertical, 7).background(RoundedRectangle(cornerRadius: 8).fill(Theme.auto.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(white: 0.38), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }.buttonStyle(.plain).foregroundColor(Theme.auto).accessibilityLabel(LF("%@, %@ grupe", c.title, c.groups.count)).accessibilityAddTraits(isOpen ? .isSelected : [])
                    if isOpen {
                        let shown = all.contains(c.id) ? c.groups : Array(c.groups.prefix(limit))
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, g in GroupRow(session: session, group: g) }
                        if c.groups.count > limit { Button(all.contains(c.id) ? L("Arată mai puține") : LF("Arată toate (%@)", c.groups.count)) { if all.contains(c.id) { all.remove(c.id) } else { all.insert(c.id) } }.buttonStyle(.plain).font(Theme.f(11.5)).foregroundColor(Theme.accent).padding(.leading, 8) }
                    }
                }
            }
        }.padding(.horizontal, 4)
    }
}
func filterName(_ f: PhotoFilter) -> String { switch f { case .all: return L("Toate"); case .check: return L("De verificat"); case .keep: return L("Păstrate"); case .reject: return L("Respinse"); case .favorites: return L("Favorite") } }
struct FilterRow: View {
    @ObservedObject var session: SelectionSession; let filter: PhotoFilter; @State private var hover = false
    var body: some View {
        Button { session.filter = filter } label: {
            HStack { Circle().fill(dot).frame(width: 9, height: 9); Text(name); Spacer(); Text("\(session.count(for: filter))").foregroundColor(Theme.muted) }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(session.filter == filter ? Theme.selected : (hover ? Theme.panel2 : Color.clear)))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundColor(Theme.text).font(Theme.f(13)).onHover { hover = $0 }
            .accessibilityLabel("\(name), \(session.count(for: filter))").accessibilityAddTraits(session.filter == filter ? .isSelected : [])
    }
    var name: String { switch filter { case .all: return L("Toate"); case .check: return L("De verificat"); case .keep: return L("Păstrate"); case .reject: return L("Respinse"); case .favorites: return L("Favorite") } }
    var dot: Color { switch filter { case .all: return Theme.faint; case .check: return Theme.check; case .keep: return Theme.keep; case .reject: return Theme.reject; case .favorites: return Color.yellow } }
}
private struct GroupRow: View {
    @ObservedObject var session: SelectionSession; let group: SuggestedGroup
    var body: some View {
        let names = group.memberIds.compactMap { id in session.photos.first { $0.id == id }.map { (($0.path as NSString).lastPathComponent as NSString).deletingPathExtension } }
        let active = !group.memberIds.isEmpty && group.memberIds.allSatisfy { session.selectedIds.contains($0) }
        Button { if let f = group.memberIds.first { session.select(f); session.selectRange(to: group.memberIds.last ?? f) } } label: {
            HStack(spacing: 6) {
                Text(LF("%@ cadre", group.memberIds.count)).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.auto)
                Text(names.first.map { names.count > 1 ? "\($0) … \(names.last ?? "")" : $0 } ?? "").font(Theme.f(11)).foregroundColor(Theme.muted).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.selected : Theme.auto.opacity(0.04)))
        }.buttonStyle(.plain).help(group.reason).accessibilityHint(L("Selectează cadrele grupului"))
    }
}

// MARK: bara de sus: mod, poziție, decizii
private struct TopBar: View {
    @ObservedObject var session: SelectionSession
    private var modePicker: some View { Segmented(options: [(ViewMode.grid, L("Grilă")), (.view, L("Vizualizare")), (.compare, L("Compară"))], selection: $session.mode) }
    private var position: some View {
        Group { if let c = session.current { Text("\((session.visible.firstIndex { $0.id == c.id } ?? 0) + 1) / \(session.visible.count)").font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize()
            .accessibilityLabel(LF("Fotografia %@ din %@", (session.visible.firstIndex { $0.id == c.id } ?? 0) + 1, session.visible.count)) } }
    }
    private var decisions: some View { HStack(spacing: 12) { decide(L("Păstrează"), "P", .keep); decide(L("Respinge"), "X", .reject); decide(L("De verificat"), "U", .check) } }
    private var undoButton: some View {
        Button { _ = try? session.undo() } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(SoftButtonStyle()).keyboardShortcut("z", modifiers: .command).accessibilityLabel(L("Anulează ultima schimbare")).help(L("Anulează ultima schimbare (⌘Z)"))
    }
    var body: some View {
        /* fereastră îngustă: rândul se desparte în două (nimic nu se taie și nicio etichetă nu se rupe pe verticală) */
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { modePicker; position; Spacer(); decisions; undoButton }
            VStack(alignment: .leading, spacing: 8) { HStack(spacing: 12) { modePicker; position; Spacer(); undoButton }; decisions }
        }.padding(.horizontal, 16).padding(.vertical, 10).background(Theme.app)
        .background(Group {   // scurtături fără modificator (invizibile)
            Button("") { session.move(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { session.move(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { session.pinCurrent() }.keyboardShortcut("c", modifiers: [])
            Button("") { session.mode = .grid }.keyboardShortcut("g", modifiers: [])
            Button("") { session.mode = .view }.keyboardShortcut("e", modifiers: [])
        }.frame(width: 0, height: 0).opacity(0).accessibilityHidden(true))
    }
    func decide(_ title: String, _ key: Character, _ d: Decision) -> some View {
        let n = session.targetCount
        return Button { try? session.apply(d) } label: {
            HStack(spacing: 6) { Text(n > 1 ? "\(title) (\(n))" : title).lineLimit(1).fixedSize(); Text(String(key)).font(Theme.f(10.5)).foregroundColor(Theme.muted).padding(.horizontal, 4).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.line)) }.fixedSize()
        }.buttonStyle(SoftButtonStyle(tint: Theme.color(d), active: session.current?.decision == d)).keyboardShortcut(KeyEquivalent(Character(key.lowercased())), modifiers: [])
            .help(n > 1 ? LF("%@: se aplică celor %@ fotografii selectate", title, n) : LF("%@: se aplică cadrului curent", title))
    }
}

// MARK: bara de selecție și acțiuni de lot
/// «1 fotografie» / «N fotografii» (acord corect în română).
func nFoto(_ n: Int) -> String { Localizer.shared.count(n, L("fotografie"), L("fotografii")) }
/// Selecție multiplă VIZIBILĂ (fără taste speciale; Command/Shift rămân valabile) și acțiuni de lot cu numărul țintelor. Acțiunile se aplică NUMAI fotografiilor vizibile; separate: «Respinge» (decizie, reversibilă),
/// «Scoate din album» (rămâne în catalog) și «Scoate din catalog…» (nu șterge originalele). Nu există ștergerea originalelor.
private struct BatchBar: View {
    @ObservedObject var session: SelectionSession; @ObservedObject var faces: FaceCenter
    var onRemoveFromCatalog: ([Int64]) -> Void
    var body: some View {
        let v = session.visibleSummary; let n = session.targetCount; let selN = session.selectedIds.count; let mix = session.targetMix
        let tgt = session.photos.filter { session.albumTargets.contains($0.id) }
        let pendingFaces = faces.pending(tgt).count
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button { session.multiSelect.toggle() } label: { Label(L("Selectare multiplă"), systemImage: session.multiSelect ? "checkmark.square.fill" : "square") }
                    .buttonStyle(SoftButtonStyle(active: session.multiSelect)).help(L("Cu selecția multiplă pornită, un clic pe o fotografie o bifează sau o debifează. Command și Shift funcționează oricând.")).accessibilityAddTraits(session.multiSelect ? .isSelected : [])
                Button(LF("Selectează toate vizibilele (%@)", v.shown)) { session.selectAllVisible() }.buttonStyle(SoftButtonStyle()).disabled(v.shown == 0 || selN == v.shown)
                Button(L("Deselectează tot")) { session.deselectAll() }.buttonStyle(SoftButtonStyle()).disabled(selN == 0)
                Spacer(minLength: 8)
                Text(LF("Se văd %@ din %@ · filtru: %@%@", v.shown, v.total, filterName(v.filter), v.album.map { " · album: \($0)" } ?? "")).font(Theme.f(12)).foregroundColor(Theme.muted).lineLimit(1)
            }
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(selN > 0 ? LF("%@ selectate — acțiunile se aplică acestor %@", selN, nFoto(n)) : LF("Nicio selecție — acțiunile se aplică cadrului curent (%@)", nFoto(n))).font(Theme.f(12.5, weight: .semibold)).lineLimit(1)
                    if n > 0 { Text(LF("Acum: %@ păstrate · %@ respinse · %@ de verificat", mix.keep, mix.reject, mix.check)).font(Theme.f(11)).foregroundColor(Theme.muted) }
                }.fixedSize()
                Spacer(minLength: 8)
                Menu(LF("Adaugă la album (%@)", n)) {
                    ForEach(session.albums) { a in Button(a.name) { try? session.addTargets(toAlbum: a.id) } }
                    Divider(); Button(L("Album nou…")) { if let nm = promptText(L("Album nou"), LF("Numele albumului pentru %@:", nFoto(n)), initial: ""), !nm.isEmpty { try? session.createAlbum(nm, addTargets: true) } }
                }.menuStyle(.borderlessButton).fixedSize().disabled(n == 0)
                if let a = session.albumFilter { Button(LF("Scoate din album (%@)", n)) { try? session.removeTargets(fromAlbum: a) }.buttonStyle(SoftButtonStyle()).disabled(n == 0).help(L("Scoate doar din acest album; fotografiile rămân în catalog și pe disc")) }
                Button(LF("Scoate din catalog… (%@)", n)) { onRemoveFromCatalog(session.albumTargets) }.buttonStyle(SoftButtonStyle()).disabled(n == 0).help(L("Scoate din catalog (reglajele salvate se pierd); fișierele originale NU se șterg"))
                if faces.running { ProgressView(value: Double(faces.done), total: Double(max(1, faces.total))).frame(width: 70).tint(Theme.accent); Button(L("Anulează")) { faces.cancel() }.buttonStyle(SoftButtonStyle()) }
                else {
                    Button(pendingFaces == 0 ? L("Fețe analizate") : LF("Analizează fețele (%@ din %@)", pendingFaces, n)) { faces.start(tgt, label: LF("%@ fotografii-țintă", n)) }.buttonStyle(SoftButtonStyle()).disabled(pendingFaces == 0).help(L("Analiză experimentală de fețe/ochi pe fotografiile-țintă; nu schimbă nicio decizie"))
                    let rej = session.photos.filter { $0.decision == .reject }; let rp = faces.pending(rej).count
                    if !rej.isEmpty { Button(LF("Analizează respinsele (%@ din %@)", rp, rej.count)) { faces.start(rej, label: L("respinse")) }.buttonStyle(SoftButtonStyle()).disabled(rp == 0).help(L("Rulează analiza experimentală pe toate fotografiile respinse, ca să le poți reverifica; nu le schimbă decizia")) }
                }
            } }
            if let a = session.lastAction { Text(a).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.accentHi) }
            if !faces.running, let lr = faces.lastRun { let t = faces.tally(session.photos.filter { lr.ids.contains($0.id) })
                Text(LF("Analiză fețe (%@, experimentală): %@ cu fețe · %@ fără fețe detectate · %@ nu s-au putut evalua (fișier gol, lipsă sau nedecodabil) · %@ neanalizate. Nu schimbă nicio decizie.", lr.label, t.withFaces, t.noFaces, t.failed, t.pending)).font(Theme.f(11)).foregroundColor(t.failed > 0 ? Theme.check : Theme.muted) }
            Text(L("Păstrează / Respinge / De verificat (bara de sus) sunt DECIZII ale tale, reversibile (⌘Z). «Scoate din album» ≠ «Scoate din catalog»; nicio acțiune nu șterge fișierele originale.")).font(Theme.f(10.5)).foregroundColor(Theme.faint)
        }.padding(.horizontal, 16).padding(.vertical, 8).background(Theme.panel2)
    }
}

// MARK: scena
private struct Stage: View {
    @ObservedObject var session: SelectionSession
    @ObservedObject var faces: FaceCenter
    var body: some View {
        Group {
            switch session.mode {
            case .grid:
                ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) { ForEach(session.visible, id: \.id) { p in GridCard(session: session, photo: p) } }.padding(14) }
            case .view:
                if let c = session.current { VStack(spacing: 0) { if session.detail100 { DetailView(session: session, photo: c, faces: faces).padding(14) } else { Figure(photo: c, caption: c.isRendered ? L("Imagine redată · nu RAW (previzualizare din fișierul sursă)") : L("Previzualizare din cameră"), badge: true, zoom: session, faces: faces).padding(14) }; Divider().overlay(Theme.line); FaceBar(session: session, faces: faces) } } else { Text(L("Nicio fotografie în acest filtru")).foregroundColor(Theme.muted) }
            case .compare:
                CompareView(session: session).padding(14)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
/// Comparație între DOUĂ cadre diferite (nu înainte/după): referința fixată vs fotografia curentă, cu acțiuni explicite pentru schimbare/eliminare.
private struct CompareView: View {
    @ObservedObject var session: SelectionSession
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(L("Compari două cadre diferite")).font(Theme.f(12)).foregroundColor(Theme.muted)
                Spacer()
                Button { session.pinCurrent() } label: { Label(L("Fixează curentul ca referință"), systemImage: "pin") }.buttonStyle(SoftButtonStyle()).accessibilityHint(L("Scurtătură C"))
                if session.pinned != nil { Button { session.clearPin() } label: { Label(L("Elimină referința"), systemImage: "xmark") }.buttonStyle(SoftButtonStyle()) }
            }.font(Theme.f(12))
            HStack(spacing: 16) {
                if let p = session.pinned { Figure(photo: p, caption: L("Referință fixată"), badge: true) }
                else { VStack(spacing: 8) { Image(systemName: "pin").font(Theme.f(22)).foregroundColor(Theme.faint); Text(L("Nicio referință fixată")).foregroundColor(Theme.text); Text(L("Fixează cadrul curent (C) pentru a-l compara cu următoarele.")).font(Theme.f(12)).foregroundColor(Theme.muted) }.frame(maxWidth: .infinity, maxHeight: .infinity).background(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))) }
                if let c = session.current { Figure(photo: c, caption: L("Fotografia curentă"), badge: true) }
            }
        }
    }
}
private struct Figure: View {
    let photo: PhotoRecord; let caption: String; var badge = false; var zoom: SelectionSession? = nil; var faces: FaceCenter? = nil
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) { Text("\(caption) · \((photo.path as NSString).lastPathComponent)").font(Theme.f(12)).foregroundColor(Theme.muted).lineLimit(1); Spacer()
                if let z = zoom { Button { z.detail100 = true } label: { Text("100%") }.buttonStyle(SoftButtonStyle()).keyboardShortcut("z", modifiers: []).help(L("Previzualizare la 100% (Z)")).accessibilityLabel(L("Arată la 100%")) }
                if badge { Badge(text: Theme.label(photo.decision), color: Theme.color(photo.decision)) } }
            PhotoImage(photo: photo, kind: .view).frame(maxWidth: .infinity, maxHeight: .infinity).overlay { if let f = faces { FaceOverlay(faces: f, photo: photo) } }
        }
    }
}
/// Lupă: ACEEAȘI navigare ca la editare (zoom pe cursor, Space/buton mijloc pentru deplasare, Potrivit/100%); 100% = un pixel de imagine la un pixel fizic. Sursa e afișată (din cameră, rezoluție completă SAU developare a aplicației); niciuna nu e exportul final.
private struct DetailView: View {
    @ObservedObject var session: SelectionSession; let photo: PhotoRecord; @ObservedObject var faces: FaceCenter
    @EnvironmentObject var store: ImageStore
    @StateObject private var viewer = ViewerState()
    @State private var img: NSImage?; @State private var source: String?; @State private var loading = true
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("\(viewer.isFit ? L("Potrivit") : "")\(viewer.isFit ? " · " : "")\(viewer.percent)% · \((photo.path as NSString).lastPathComponent)\(sourceText)").font(Theme.f(12)).foregroundColor(Theme.muted).lineLimit(1); Spacer()
                Button { viewer.setFit() } label: { Text(L("Potrivit")) }.buttonStyle(SoftButtonStyle(active: viewer.isFit))
                Button { viewer.set100() } label: { Text("100%") }.buttonStyle(SoftButtonStyle(active: !viewer.isFit && abs(viewer.scale - 1) < 0.005))
                Button { faces.focus = nil; session.detail100 = false } label: { Text(L("Închide lupa")) }.buttonStyle(SoftButtonStyle()).keyboardShortcut("z", modifiers: [])
            }
            GeometryReader { g in
                ZStack {
                    Theme.canvas
                    if let img = img { let r = viewer.imageRect(); Image(nsImage: img).resizable().interpolation(viewer.scale >= 1 ? .none : .high).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY) }
                    else if loading { VStack(spacing: 8) { ProgressView(); Text(L("Se încarcă la rezoluție mare…")).font(Theme.f(12)).foregroundColor(Theme.muted) } }
                    else { Text(L("Nu se poate încărca la 100% pentru acest fișier.")).font(Theme.f(12)).foregroundColor(Theme.muted) }
                }.frame(width: g.size.width, height: g.size.height).clipped().background(ViewerEvents(v: viewer)).onAppear { viewer.canvasSize = g.size }.onChange(of: g.size) { n in viewer.canvasSize = n; viewer.revalidate() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: photo.id) {
            loading = true; img = await store.image(for: photo, kind: .detail)
            if let i = img, let rep = i.representations.first { viewer.fullSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh) }
            source = try? session.catalog.cachedPreview(photoId: photo.id, kind: "detail")?.source; loading = false
            if let f = faces.focus { viewer.focus(on: CGPoint(x: f.midX, y: f.midY), scale: 1) } else { viewer.set100() }   // lupa pe zona aleasă, fără deplasări surprinzătoare ale imaginii
        }
    }
    var sourceText: String { switch source { case "camera-full": return L(" · din cameră, rezoluție completă"); case "app-developed-libraw": return L(" · developare a aplicației (nu exportul final)"); default: return "" } }
}

private struct GridCard: View {
    @ObservedObject var session: SelectionSession; let photo: PhotoRecord; @State private var hover = false
    var body: some View {
        Button { session.tap(photo.id, command: NSEvent.modifierFlags.contains(.command), shift: NSEvent.modifierFlags.contains(.shift)) } label: {
            VStack(spacing: 0) {
                PhotoImage(photo: photo, kind: .grid).frame(height: 150).frame(maxWidth: .infinity).background(Color.black.opacity(0.5)).opacity(photo.decision == .reject ? 0.45 : 1)
                    .overlay(alignment: .topLeading) { if session.multiSelect || session.selectedIds.contains(photo.id) { Image(systemName: session.selectedIds.contains(photo.id) ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundColor(session.selectedIds.contains(photo.id) ? Theme.accentHi : Color.white.opacity(0.8)).shadow(radius: 2).padding(8).accessibilityHidden(true) } }
                HStack { Text((photo.path as NSString).lastPathComponent).font(Theme.f(12)).foregroundColor(Theme.muted).lineLimit(1).truncationMode(.middle); if session.group(of: photo.id) != nil { AutoTag().fixedSize() }; Spacer(); Badge(text: Theme.label(photo.decision), color: Theme.color(photo.decision)) }.padding(.horizontal, 10).padding(.vertical, 7)
            }
            .background(hover ? Theme.panel2 : Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(session.currentId == photo.id ? Theme.accent : (session.selectedIds.contains(photo.id) ? Theme.accentHi : Color.clear), lineWidth: 2))
        }.buttonStyle(.plain).onHover { hover = $0 }
            .accessibilityLabel("\((photo.path as NSString).lastPathComponent), \(Theme.label(photo.decision))").accessibilityValue(session.selectedIds.contains(photo.id) ? L("selectată") : L("neselectată"))
    }
}
private struct Filmstrip: View {
    @ObservedObject var session: SelectionSession
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(session.visible, id: \.id) { p in
                    Button { session.tap(p.id, command: NSEvent.modifierFlags.contains(.command), shift: NSEvent.modifierFlags.contains(.shift)); session.detail100 = false } label: {
                        PhotoImage(photo: p, kind: .filmstrip).frame(width: 64, height: 64).background(Color.black.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .bottomTrailing) { Circle().fill(Theme.color(p.decision)).frame(width: 10, height: 10).padding(3) }
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(session.currentId == p.id ? Theme.accent : (session.selectedIds.contains(p.id) ? Theme.accentHi : Color.clear), lineWidth: 2))
                    }.buttonStyle(.plain).accessibilityLabel("\((p.path as NSString).lastPathComponent), \(Theme.label(p.decision))")
                }
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }.background(Theme.app).frame(height: 86)
    }
}

// MARK: inspector: decizie + rating + acțiune principală; restul în „Detalii”
private struct InfoPanel: View {
    @ObservedObject var session: SelectionSession; @ObservedObject var faces: FaceCenter; var onContinue: (Bool) -> Void; var onEdit: ([Int64], String) -> Void
    @State private var detailsOpen = false
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Box(title: L("Starea ta (decizii)")) {
                        let k = session.counts
                        HStack(spacing: 14) { stat(L("Păstrate"), k.keep, Theme.keep); stat(L("Respinse"), k.reject, Theme.reject); stat(L("De verificat"), k.check, Theme.check) }
                        Text(L("Sunt DECIZIILE tale. Nimic nu se păstrează sau respinge automat.")).font(Theme.f(10.5)).foregroundColor(Theme.faint)
                    }
                    if let c = session.current {
                        Box(title: L("Decizia ta")) {
                            HStack { Badge(text: Theme.label(c.decision), color: Theme.color(c.decision)); Spacer() }
                            HStack(spacing: 2) {
                                ForEach(1...5, id: \.self) { n in
                                    Button { try? session.setRating(n) } label: { Image(systemName: c.rating >= n ? "star.fill" : "star").foregroundColor(c.rating >= n ? Color.yellow : Theme.faint) }.buttonStyle(.plain).accessibilityLabel(LF("%@ stele", n))
                                }
                                Spacer()
                                Button { try? session.toggleFavorite() } label: { Image(systemName: c.favorite ? "heart.fill" : "heart").foregroundColor(c.favorite ? Color.yellow : Theme.faint) }.buttonStyle(.plain).keyboardShortcut("f", modifiers: []).accessibilityLabel(L("Favorită (F)")).help(L("Favorită (F)"))
                            }.font(Theme.f(17))
                            if let g = session.group(of: c.id) { HStack(spacing: 6) { AutoTag(text: g.kind == .burst ? L("rafală") : L("posibil similar")); Text(LF("%@ cadre", g.memberIds.count)).font(Theme.f(12)).foregroundColor(Theme.muted) } }
                        }
                        Box(title: L("Indicii automate · experimentale")) {
                            hints(c)
                        }
                        Box(title: L("Albume")) {
                            let n = session.albumTargets.count
                            if session.albums(of: c.id).isEmpty { Text(L("Cadrul nu e în niciun album.")).font(Theme.f(11)).foregroundColor(Theme.faint) }
                            ForEach(session.albums(of: c.id)) { a in HStack { Image(systemName: "rectangle.stack"); Text(a.name).font(Theme.f(12)).lineLimit(1); Spacer(); Button { try? session.removeTargets(fromAlbum: a.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).help(LF("Scoate %@ din albumul «%@» (nu o șterge)", n > 1 ? "cele \(n) fotografii țintă" : "fotografia", a.name)) } }
                            Menu { ForEach(session.albums) { a in Button(a.name) { try? session.addTargets(toAlbum: a.id) } }
                                   Divider(); Button(LF("Album nou cu %@…", n > 1 ? "selecția (\(n))" : L("fotografia curentă"))) { if let nm = promptText(L("Album nou"), "Numele albumului:", initial: ""), !nm.isEmpty { try? session.createAlbum(nm, addTargets: true) } } } label: { Label(LF("Adaugă %@ la album", n > 1 ? "selecția (\(n))" : "fotografia"), systemImage: "plus").lineLimit(1) }.menuStyle(.borderlessButton)
                        }
                        DisclosureGroup(isExpanded: $detailsOpen) {
                            VStack(alignment: .leading, spacing: 8) {
                                KV(k: "Aparat", v: c.camera ?? "—"); KV(k: "Data", v: c.capturedAt.map(roDate) ?? "—")
                                KV(k: L("Previzualizare"), v: c.previewSource == "embedded-camera" ? L("din cameră") : (c.previewSource ?? "—"))
                                if let g = session.group(of: c.id) { Text(g.reason).font(Theme.f(12)).foregroundColor(Theme.muted) }
                                Text(L("Previzualizarea e cea încorporată de cameră (aspectul camerei, nu al exportului final). Decizia e salvată în catalogul sesiunii, nu lângă original, și e reversibilă.")).font(Theme.f(11.5)).foregroundColor(Theme.muted)
                            }.padding(.top, 8)
                        } label: { Text(L("Detalii")).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted) }
                            .padding(12).satin(10, fill: Theme.panel2)
                            .accessibilityLabel(L("Detalii fotografie"))
                    }
                }.padding(12)
            }
            Divider().overlay(Theme.line)
            VStack(alignment: .leading, spacing: 8) {   // acțiunea principală, mereu vizibilă
                let k = session.counts; let selN = session.selectedVisible.count
                Text(L("Continuă la editare cu:")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
                Button { onContinue(false) } label: { Text(LF("Păstratele (%@)", k.keep)).frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle()).disabled(k.keep == 0)
                if selN > 0 { Button { onEdit(session.selectedVisible.map { $0.id }, LF("selecția (%@)", selN)) } label: { Text(LF("Selecția (%@)", selN)).frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle()) }
                if let a = session.albumFilter, let al = session.albums.first(where: { $0.id == a }) { Button { onEdit(session.photos.filter { session.albumMembers.contains($0.id) }.map { $0.id }, LF("albumul «%@»", al.name)) } label: { Text(LF("Albumul «%@» (%@)", al.name, al.count)).frame(maxWidth: .infinity).lineLimit(1) }.buttonStyle(SoftButtonStyle()).disabled(al.count == 0) }
                Button { onContinue(true) } label: { Text(LF("Toate (%@)", k.total)).frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle())
                if k.keep == 0 { Text(L("Nicio fotografie păstrată încă: alege «Selecția», «Albumul» sau «Toate».")).font(Theme.f(10.5)).foregroundColor(Theme.faint) }
            }.padding(12)
        }.background(Theme.panel)
    }
}

extension InfoPanel {
    fileprivate func stat(_ t: String, _ n: Int, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) { Text("\(n)").font(Theme.f(20, weight: .semibold)).foregroundColor(c); Text(t).font(Theme.f(10.5)).foregroundColor(Theme.muted) }.accessibilityElement(children: .combine)
    }
    /// Zona unei fețe în cuvinte (casetă normalizată 0…1, origine sus-stânga).
    fileprivate func zone(_ b: [Double]) -> String {
        guard b.count == 4 else { return L("zonă necunoscută") }
        let cx = b[0] + b[2] / 2, cy = b[1] + b[3] / 2
        let h = cx < 0.34 ? L("stânga") : (cx > 0.66 ? L("dreapta") : L("centru")), v = cy < 0.34 ? L("sus") : (cy > 0.66 ? L("jos") : L("mijloc"))
        return "\(v) \(h) (x \(Int(b[0] * 100))–\(Int((b[0] + b[2]) * 100))%, y \(Int(b[1] * 100))–\(Int((b[1] + b[3]) * 100))%)"
    }
    @ViewBuilder fileprivate func hints(_ c: PhotoRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            AutoTag(text: L("indiciu automat, nu decizie"))
            Text(L("Observații automate explicabile. Nu schimbă decizia ta, nu resping și nu păstrează nimic singure.")).font(Theme.f(11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if let g = session.group(of: c.id) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LF("%@ · %@ cadre · semnal %@", g.kind == .burst ? L("Rafală") : L("Posibil similar"), g.memberIds.count, g.confidence == .likely ? L("probabil") : L("slab"))).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.auto)
                    Text(g.reason).font(Theme.f(10.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            } else { Text(L("Nu face parte dintr-un grup sugerat (rafală/similare).")).font(Theme.f(11)).foregroundColor(Theme.faint) }
            let own = (try? session.catalog.signals(photoId: c.id)) ?? nil
            let grp = session.group(of: c.id).map { g in g.memberIds.compactMap { (try? session.catalog.signals(photoId: $0)) ?? nil } } ?? []
            ForEach(ExposureCues.exposure(own) + (ExposureCues.sharpness(own: own, groupSignals: grp).map { [$0] } ?? [])) { h in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: h.kind == .analysisMissing ? "hourglass" : (h.certainty == .uncertain ? "questionmark.circle" : "info.circle")).foregroundColor(Theme.auto).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) { Text(h.title).font(Theme.f(11.5, weight: .semibold)); Text(h.why).font(Theme.f(10.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                }
            }
            ForEach(faces.hints(c)) { h in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: h.symbol).foregroundColor(Theme.auto).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) { Text(h.title).font(Theme.f(11.5, weight: .semibold)); Text(h.why).font(Theme.f(10.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                }
            }
            if let g = session.group(of: c.id), g.memberIds.count >= 2 {
                let qs: [Int64: Float] = Dictionary(uniqueKeysWithValues: g.memberIds.compactMap { id in session.photos.first { $0.id == id }.flatMap { ph in faces.result(ph).flatMap { FaceQualityCompare.representative($0.faces.map(FaceAnalyzer.observation)) } }.map { (id, $0) } })
                if let best = FaceQualityCompare.promising(qs) {
                    HStack(alignment: .top, spacing: 6) { Image(systemName: "star.leadinghalf.filled").foregroundColor(Theme.auto).frame(width: 16)
                        Text(best.id == c.id ? LF("Variantă mai promițătoare în grup: calitatea feței mai mare cu %@ față de următoarea (indiciu, nu decizie).", String(format: "%.2f", best.lead)) : LF("Alt cadru din grup are calitatea feței mai mare cu %@ (indiciu, nu decizie; verifică-l).", String(format: "%.2f", best.lead))).font(Theme.f(10.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                } else if qs.count >= 2 { Text(L("Calitatea feței nu diferă clar între cadrele grupului (incert).")).font(Theme.f(10.5)).foregroundColor(Theme.faint) }
                else { Text(L("Comparația feței în grup nu e posibilă: analizează cadrele grupului (fețe prea mici sau neanalizate).")).font(Theme.f(10.5)).foregroundColor(Theme.faint) }
            }
            if let r = faces.result(c) { ForEach(Array(r.faces.enumerated()), id: \.offset) { i, f in Text(LF("Față %@: %@ · încrederea detectorului %@%", i + 1, zone(f.box), String(format: "%.0f", Double(f.confidence) * 100))).font(Theme.f(10.5)).foregroundColor(Theme.muted) } }
            if faces.result(c) == nil, !faces.running { Button(L("Analizează cadrul")) { faces.start([c]) }.buttonStyle(SoftButtonStyle()) }
            Text(L("Limită: indicii geometrice experimentale (față/ochi, rafale/similare); nu evaluează focalizarea pe ochi, expresia, compoziția sau calitatea tehnică și nu sunt o probabilitate. Culling-ul automat NU este complet.")).font(Theme.f(10)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
        }
    }
}
fileprivate func roDate(_ d: Date) -> String { Localizer.shared.date(d, time: true) }

/// Dialoguri simple (nume de album, confirmare); fără mutări de fișiere.
@MainActor func promptText(_ title: String, _ message: String, initial: String) -> String? {
    let a = NSAlert(); a.messageText = title; a.informativeText = message; a.addButton(withTitle: "OK"); a.addButton(withTitle: L("Renunță"))
    let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); f.stringValue = initial; a.accessoryView = f
    return a.runModal() == .alertFirstButtonReturn ? f.stringValue : nil
}
@MainActor func confirm(_ title: String, _ message: String, ok: String = L("Șterge albumul")) -> Bool { let a = NSAlert(); a.messageText = title; a.informativeText = message; a.alertStyle = .warning; a.addButton(withTitle: ok); a.addButton(withTitle: L("Renunță")); return a.runModal() == .alertFirstButtonReturn }

/// Filtru pe indicii (experimentale): arată cadrele care merită o verificare; nu schimbă decizii, nu respinge nimic. Combinat cu filtrul de decizii și cu albumul.
private struct CueFilterMenu: View {
    @ObservedObject var session: SelectionSession
    static func label(_ f: CueFilter) -> String {
        switch f { case .none: return L("Fără filtru pe indicii"); case .clipping: return L("Lumini/umbre posibil tăiate"); case .tone: return L("Cadru întunecat/luminos"); case .lessSharp: return L("Posibil mai puțin clare în rafală")
        case .analysisMissing: return L("Analiză neefectuată"); case .possibleBlink: return L("Posibilă clipire"); case .uncertainFace: return L("Față mică sau ochi incerți"); case .noFaceFound: return L("Nicio față detectată (analizate)") }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L("Indicii (experimentale)")).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted).padding(.leading, 10)
            Menu {
                ForEach(CueFilter.allCases, id: \.rawValue) { f in Button(f == .none ? Self.label(f) : "\(Self.label(f)) (\(session.cueCount(f)))") { session.cueFilter = f } }
            } label: { Text(session.cueFilter == .none ? L("Alege un indiciu…") : "\(Self.label(session.cueFilter)) (\(session.cueCount(session.cueFilter)))").lineLimit(1) }.menuStyle(.borderlessButton).padding(.horizontal, 10)
            if session.cueFilter != .none { Text(L("Filtru pe indicii activ: se văd doar cadrele cu indiciul; nu e un verdict și nimic nu se respinge singur. Acțiunile se aplică doar celor vizibile.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).padding(.horizontal, 10).fixedSize(horizontal: false, vertical: true) }
            Text(L("Fețele/ochii apar după «Analizează cadrul»; fără analiză, cadrul nu intră la filtrele de față.")).font(Theme.f(10)).foregroundColor(Theme.faint).padding(.horizontal, 10).fixedSize(horizontal: false, vertical: true)
        }
    }
}
