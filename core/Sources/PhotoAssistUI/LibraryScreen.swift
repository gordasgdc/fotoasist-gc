import SwiftUI
import AppKit
import PhotoCore

/// Biblioteca ca spațiu de organizare: lateral (toate, surse, albume, stări), central grilă adaptivă cu miniaturi reglabile, sus acțiuni (adaugă, căutare, mărime), contextual (editează selecția, albume, administrare).
/// Catalogul și albumele sunt cele existente. Nimic nu mută și nu șterge originale; «Scoate din album» ≠ «Scoate din catalog».
struct LibraryScreen: View {
    @ObservedObject var model: AppModel; @ObservedObject var session: SelectionSession
    @AppStorage("gdcpa.library.thumb") private var thumb: Double = 190
    @State private var query = ""; @State private var source: String?; @State private var showSummary = true

    private var shown: [PhotoRecord] {
        var v = session.visible
        if let s = source { v = v.filter { ($0.path as NSString).deletingLastPathComponent == s } }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { v = v.filter { ($0.path as NSString).lastPathComponent.lowercased().contains(q) || ($0.camera ?? "").lowercased().contains(q) } }
        return v
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 236)
            Divider().overlay(Theme.line)
            VStack(spacing: 0) {
                topBar
                Divider().overlay(Theme.line)
                importBanner
                if !session.selectedIds.isEmpty { contextBar; Divider().overlay(Theme.line) }
                grid
            }
        }.background(Theme.app).foregroundColor(Theme.text).onChange(of: shown.map { $0.id }) { ids in session.restrictSelection(to: Set(ids)) }
    }

    // MARK: lateral
    private var sidebar: some View {
        let folders = (try? model.catalog.sourceFolders()) ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Button { session.filter = .all; session.albumFilter = nil; source = nil } label: {
                        HStack { Image(systemName: "photo.on.rectangle"); Text(L("Toate fotografiile")); Spacer(); Text("\(session.counts.total)").foregroundColor(Theme.muted) }
                            .padding(.horizontal, 10).padding(.vertical, 7).background(RoundedRectangle(cornerRadius: 8).fill(session.filter == .all && session.albumFilter == nil && source == nil ? Theme.selected : Color.clear)).contentShape(Rectangle())
                    }.buttonStyle(.plain).font(Theme.f(13))
                    ForEach([PhotoFilter.check, .keep, .reject, .favorites], id: \.rawValue) { f in FilterRow(session: session, filter: f) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Surse (foldere, neatinse)")).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted).padding(.leading, 10)
                    if folders.isEmpty { Text(L("Nicio sursă.")).font(Theme.f(11)).foregroundColor(Theme.faint).padding(.leading, 10) }
                    ForEach(folders) { f in
                        Button { source = source == f.path ? nil : f.path } label: {
                            HStack { Image(systemName: "folder"); Text((f.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle); Spacer(); Text("\(f.count)").foregroundColor(Theme.muted) }
                                .padding(.horizontal, 10).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 8).fill(source == f.path ? Theme.accent.opacity(0.18) : Color.clear)).contentShape(Rectangle())
                        }.buttonStyle(.plain).font(Theme.f(12.5)).help(f.path).accessibilityLabel(LF("Folder sursă %@, %@ fotografii", (f.path as NSString).lastPathComponent, f.count)).accessibilityAddTraits(source == f.path ? .isSelected : [])
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(L("Albume")).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted); Spacer()
                        Button { if let n = promptText(L("Album nou"), "Numele albumului (colecție virtuală; fotografiile originale nu se mută și nu se copiază):", initial: ""), !n.isEmpty { try? session.createAlbum(n, addTargets: false) } } label: { Image(systemName: "plus") }.buttonStyle(.plain).help(L("Album nou")) }.padding(.horizontal, 10)
                    if session.albums.isEmpty { Text(L("Niciun album. Albumele sunt colecții virtuale.")).font(Theme.f(11)).foregroundColor(Theme.faint).padding(.horizontal, 10) }
                    ForEach(session.albums) { a in
                        Button { session.albumFilter = session.albumFilter == a.id ? nil : a.id } label: {
                            HStack(spacing: 8) { AlbumCover(session: session, albumId: a.id, count: a.count, selected: session.albumFilter == a.id); Text(a.name).lineLimit(1); Spacer(); Text("\(a.count)").foregroundColor(Theme.muted) }
                                .padding(.horizontal, 10).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 8).fill(session.albumFilter == a.id ? Theme.accent.opacity(0.18) : Color.clear)).contentShape(Rectangle())
                        }.buttonStyle(.plain).font(Theme.f(12.5)).accessibilityLabel(LF("Album %@, %@ fotografii", a.name, a.count)).accessibilityAddTraits(session.albumFilter == a.id ? .isSelected : [])
                    }
                }
            }.padding(12)
        }.background(Theme.panel)
    }

    // MARK: sus
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.chooseAndImport() } label: { Label(L("Adaugă fotografii"), systemImage: "plus").lineLimit(1).fixedSize() }.buttonStyle(SoftButtonStyle()).disabled(model.isBusy)
            HStack(spacing: 6) { Image(systemName: "magnifyingglass").foregroundColor(Theme.muted)
                TextField(L("Caută după nume sau cameră"), text: $query).textFieldStyle(.plain).font(Theme.f(12.5)).frame(minWidth: 140, maxWidth: 280)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundColor(Theme.muted) } }
                .padding(.horizontal, 8).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.28))).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line))
            Text(LF("%@ din %@", shown.count, session.counts.total)).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize()
            Spacer(minLength: 8)
            Image(systemName: "square.grid.3x3").foregroundColor(Theme.muted).help(L("Mărimea miniaturilor"))
            Slider(value: $thumb, in: 110...360).frame(width: 130).controlSize(.small).tint(Theme.accent).accessibilityLabel(L("Mărimea miniaturilor"))
            Button(L("Administrează colecția…")) { model.showLibrary = true }.buttonStyle(SoftButtonStyle()).help(L("Verificare fișiere, scoatere din catalog, albume, coada de editare"))
            Button(L("Continuă la Selecție")) { model.goToSelection() }.buttonStyle(PrimaryButtonStyle())
        }.padding(.horizontal, 16).padding(.vertical, 10).background(Theme.app)
    }
    @ViewBuilder private var importBanner: some View {
        switch model.phase {
        case .scanning: banner { HStack { ProgressView().controlSize(.small); Text(L("Se citește folderul…")) } }
        case .previews(let d, let t): banner { HStack { ProgressView(value: Double(d), total: Double(max(t, 1))).frame(width: 160).tint(Theme.accent); Text(LF("Previzualizări din cameră: %@/%@", d, t)) } }
        case .analyzing(let d, let t): banner { HStack { ProgressView(value: Double(d), total: Double(max(t, 1))).frame(width: 160).tint(Theme.accent); Text(LF("Analiză clasică (sugestii): %@/%@", d, t)) } }
        case .failed(let m): banner { Text(LF("Eroare la import: %@", m)).foregroundColor(Theme.reject) }
        case .done:
            if showSummary, let s = model.importSummary { banner { HStack { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.keep); Text(LF("Import încheiat: adăugate %@, neschimbate %@, fără previzualizare %@", s.added, s.unchanged, s.withoutPreview) + (s.skipped.isEmpty ? "" : ", omise \(s.skipped.count) (originalele neatinse)")); Spacer(); Button(L("Închide")) { showSummary = false }.buttonStyle(.plain).foregroundColor(Theme.muted) } } }
        default: EmptyView()
        }
    }
    private func banner<C: View>(@ViewBuilder _ c: () -> C) -> some View { c().font(Theme.f(12)).padding(.horizontal, 16).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading).background(Theme.panel) }

    // MARK: contextual
    private var contextBar: some View {
        let ids = shown.map { $0.id }.filter { session.selectedIds.contains($0) }.isEmpty ? session.photos.map { $0.id }.filter { session.selectedIds.contains($0) } : shown.map { $0.id }.filter { session.selectedIds.contains($0) }
        return HStack(spacing: 10) {
            Text(LF("%@ selectate", session.selectedIds.count)).font(Theme.f(12.5, weight: .semibold))
            Button(L("Editează selecția")) { model.proceedToEditing(ids: ids, label: LF("selecția din bibliotecă (%@)", ids.count)) }.buttonStyle(PrimaryButtonStyle())
            Menu(L("Adaugă la album")) {
                ForEach(session.albums) { a in Button(a.name) { try? session.addTargets(toAlbum: a.id) } }
                Divider(); Button(L("Album nou…")) { if let n = promptText(L("Album nou"), L("Numele albumului pentru selecție:"), initial: ""), !n.isEmpty { try? session.createAlbum(n, addTargets: true) } }
            }.menuStyle(.borderlessButton).fixedSize()
            if let a = session.albumFilter { Button(L("Scoate din album")) { try? session.removeTargets(fromAlbum: a) }.buttonStyle(SoftButtonStyle()).help(L("Scoate doar din acest album; fotografiile rămân în catalog și pe disc")) }
            Button(L("Scoate din catalog…")) { removeFromCatalog(ids) }.buttonStyle(SoftButtonStyle()).help(L("Scoate din catalog (reglajele salvate se pierd); fișierele de pe disc NU se șterg"))
            Spacer()
            Button(L("Deselectează")) { session.clearSelection() }.buttonStyle(.plain).foregroundColor(Theme.muted)
        }.padding(.horizontal, 16).padding(.vertical, 8).background(Theme.panel2)
    }
    private func removeFromCatalog(_ ids: [Int64]) {
        let imp = (try? model.catalog.removalImpact(photoIds: ids)) ?? Catalog.RemovalImpact(photos: ids.count)
        let msg = LF("%@: %@ cu reglaje salvate (se pierd), %@ în albume, %@ cu decizie păstrat/respins. Fișierele originale și exporturile NU se șterg.", nFoto(imp.photos), imp.withEdits, imp.inAlbums, imp.decided)
        if confirm(LF("Scoți %@ din catalog?", nFoto(ids.count)), msg, ok: L("Scoate din catalog")) { _ = model.removeFromLibrary(ids: ids) }
    }

    // MARK: grilă
    private var grid: some View {
        let v = shown
        return Group {
            if v.isEmpty { emptyState.frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: CGFloat(thumb), maximum: CGFloat(thumb) * 1.8), spacing: 12, alignment: .top)], spacing: 14) { ForEach(v, id: \.id) { p in cell(p) } }.padding(16) } }
        }.background(Theme.canvas)
    }
    /// Stări goale DISTINCTE: album fără fotografii · căutare fără rezultate · sursă/filtru fără fotografii. Nu ascund erori: fișierele invalide apar ca celule cu motivul lor, nu aici.
    @ViewBuilder private var emptyState: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            VStack(spacing: 8) { Image(systemName: "magnifyingglass").font(Theme.f(26)).foregroundColor(Theme.faint)
                Text(LF("Nicio potrivire pentru «%@»", q)).font(Theme.f(14, weight: .semibold)); Text(L("Căutarea ține cont de nume și cameră, în filtrul curent.")).font(Theme.f(12)).foregroundColor(Theme.muted)
                Button(L("Șterge căutarea")) { query = "" }.buttonStyle(SoftButtonStyle()) }
        } else if let aid = session.albumFilter, let a = session.albums.first(where: { $0.id == aid }) {
            VStack(spacing: 8) { Image(systemName: "rectangle.stack").font(Theme.f(30)).foregroundColor(Theme.faint)
                Text(LF("Albumul «%@» este gol", a.name)).font(Theme.f(14, weight: .semibold)); Text(L("Albumele sunt colecții virtuale. Selectează fotografii în «Toate fotografiile» și adaugă-le aici; originalele nu se mută.")).font(Theme.f(12)).foregroundColor(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 360)
                Button(L("Arată toate fotografiile")) { session.albumFilter = nil; session.filter = .all; source = nil }.buttonStyle(SoftButtonStyle()) }
        } else if let src = source {
            VStack(spacing: 8) { Image(systemName: "folder").font(Theme.f(30)).foregroundColor(Theme.faint)
                Text(LF("Nicio fotografie potrivită în sursa «%@»", (src as NSString).lastPathComponent)).font(Theme.f(14, weight: .semibold)); Text(session.filter == .all ? L("Folderul sursă nu a fost modificat.") : L("Niciuna din fotografiile sursei nu corespunde filtrului de stare ales; folderul nu a fost modificat.")).font(Theme.f(12)).foregroundColor(Theme.muted)
                Button(L("Arată toate fotografiile")) { source = nil }.buttonStyle(SoftButtonStyle()) }
        } else {
            VStack(spacing: 6) { Text(L("Nicio fotografie pentru filtrele alese.")).font(Theme.f(14, weight: .semibold)); Text(L("Schimbă filtrul de stare (Păstrate, Respinse, Favorite).")).font(Theme.f(12)).foregroundColor(Theme.muted)
                Button(L("Arată toate fotografiile")) { session.filter = .all }.buttonStyle(SoftButtonStyle()) }
        }
    }
    private func cell(_ p: PhotoRecord) -> some View {
        let sel = session.selectedIds.contains(p.id)
        return VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                PhotoImage(photo: p, kind: .grid, compact: true).aspectRatio(1.5, contentMode: .fit).background(Theme.panel2).clipShape(RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 4) { Circle().fill(p.decision == .keep ? Theme.keep : p.decision == .reject ? Theme.reject : Theme.check).frame(width: 8, height: 8); if p.favorite { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundColor(.yellow) } }.padding(6)
            }.overlay(alignment: .bottomLeading) { if p.isRendered { RenderedBadge(compact: true).padding(5) } }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(sel ? Theme.accent : Color.clear, lineWidth: 2))
            Text((p.path as NSString).lastPathComponent).font(Theme.f(11)).lineLimit(1).truncationMode(.middle).foregroundColor(sel ? Theme.text : Theme.muted)
        }.contentShape(Rectangle())
        .onTapGesture(count: 2) { session.select(p.id); session.mode = .view; model.goToSelection() }
        .onTapGesture { click(p) }
        .accessibilityLabel((p.path as NSString).lastPathComponent).accessibilityAddTraits(sel ? .isSelected : [])
    }
    private func click(_ p: PhotoRecord) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) { session.toggleSelected(p.id); session.select(p.id) }
        else if mods.contains(.shift) { session.selectRange(to: p.id) }
        else { session.clearSelection(); session.select(p.id); session.toggleSelected(p.id) }
    }
}


/// Reprezentarea ALBUMULUI (colecție virtuală): copertă din prima fotografie, cu un strat ușor decalat în spate (mai multe fotografii), spre deosebire de folderul sursă (pictogramă de folder, „neatins”). Doar afișare; nu schimbă operațiile existente.
struct AlbumCover: View {
    @ObservedObject var session: SelectionSession; let albumId: Int64; let count: Int; let selected: Bool
    @State private var cover: PhotoRecord?
    var body: some View {
        ZStack {
            if count > 1 { RoundedRectangle(cornerRadius: 4).fill(Theme.line).frame(width: 22, height: 22).offset(x: 3, y: -3) }
            Group {
                if let c = cover { PhotoImage(photo: c, kind: .filmstrip, fill: true).frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 4)) }
                else { RoundedRectangle(cornerRadius: 4).fill(Theme.panel2).frame(width: 22, height: 22).overlay(Image(systemName: selected ? "rectangle.stack.fill" : "rectangle.stack").font(Theme.f(11)).foregroundColor(Theme.muted)) }
            }.overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: 1))
        }.frame(width: 28, height: 26).accessibilityHidden(true)
            .onAppear(perform: load).onChange(of: count) { _ in load() }
    }
    private func load() { if let id = (try? session.catalog.albumPhotoIds(albumId))?.sorted().first { cover = session.photos.first { $0.id == id } } else { cover = nil } }
}
