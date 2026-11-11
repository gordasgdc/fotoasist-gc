import SwiftUI
import PhotoCore

/// Organizarea bibliotecii: cele patru lucruri se păstrează distincte — foldere sursă (pe disc, neatinse), fotografii importate (în catalog), albume (colecții virtuale) și coada de editare (selecția curentă).
/// Scoaterea din catalog afișează înainte ce se pierde (reglaje, albume, decizii, exporturi) și NU șterge niciun fișier de pe disc.
struct LibraryManageSheet: View {
    @ObservedObject var model: AppModel; @ObservedObject var session: SelectionSession; @Environment(\.dismiss) var dismiss
    @ObservedObject private var ed: EditingModel
    @State private var health: [Int64: FileHealth]?; @State private var checking = false; @State private var checked = 0
    @State private var pending: (title: String, ids: [Int64])?; @State private var impact = Catalog.RemovalImpact(); @State private var note = ""
    var body: some View {
        let folders = (try? model.catalog.sourceFolders()) ?? []; let c = session.counts
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(L("Organizează biblioteca")).font(Theme.f(18, weight: .semibold)); Spacer(); Button(L("Închide")) { dismiss() }.buttonStyle(SoftButtonStyle()) }
            Text(L("Scoaterea din catalog nu șterge fișierele originale și nu atinge exporturile deja făcute. Aplicația nu șterge niciodată fotografii de pe disc.")).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                Box(title: L("Fotografii importate (în catalog)")) {
                    HStack(spacing: 8) { Badge(text: LF("păstrate %@", c.keep), color: Theme.keep); Badge(text: LF("respinse %@", c.reject), color: Theme.reject); Badge(text: LF("nedecise / de verificat %@", c.check), color: Theme.check) }
                    Text(LF("Total %@. «Nedecise» = încă neanalizate de tine; nu sunt nici păstrate, nici respinse.", c.total)).font(Theme.f(11)).foregroundColor(Theme.faint)
                    HStack { Button(L("Scoate respinsele din catalog…")) { ask("Scoate respinsele", session.photos.filter { $0.decision == .reject }.map { $0.id }) }.buttonStyle(SoftButtonStyle()).disabled(c.reject == 0)
                        Button(L("Golește catalogul (sesiune nouă)…")) { ask(L("Golește catalogul"), session.photos.map { $0.id }) }.buttonStyle(SoftButtonStyle()).disabled(c.total == 0) }
                }
                Box(title: L("Verificarea fișierelor"), auto: true) {
                    Text(L("Verifică existența, volumul, citirea, stabilitatea (două citiri la interval) și semnătura fiecărui fișier. Nu atinge fișierele și nu scoate nimic din catalog fără alegerea ta. Un fișier nu e numit «corupt» doar după nume sau dimensiune.")).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    HStack { Button { runHealthCheck() } label: { Label(checking ? L("Se verifică…") : "Verifică fișierele (\(session.photos.count))", systemImage: "checkmark.shield").lineLimit(1) }.buttonStyle(SoftButtonStyle()).disabled(checking)
                        if checking { ProgressView(value: Double(checked), total: Double(max(1, session.photos.count))).frame(width: 120) } }
                    if let h = health {
                        let bad = h.filter { $0.value.kind != .ok }; let okN = h.count - bad.count
                        Text(LF("%@ în regulă · %@ cu probleme · %@ cu eroare de decodor în sesiunea curentă", okN, bad.count, ed.failedPhotos.count)).font(Theme.f(11.5, weight: .semibold))
                        ForEach(Array(Dictionary(grouping: bad.map { ($0.key, $0.value) }, by: { $0.1.kind }).sorted { $0.key.rawValue < $1.key.rawValue }), id: \.key) { kind, items in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Badge(text: "\(kind.label): \(items.count)", color: Theme.check); Spacer()
                                    Button(L("Scoate din catalog…")) { ask("Scoate: \(kind.label)", items.map { $0.0 }) }.buttonStyle(SoftButtonStyle()) }
                                let byFolder = Dictionary(grouping: items, by: { folderOf($0.0) })
                                ForEach(byFolder.sorted { $0.key < $1.key }, id: \.key) { f, xs in Text("\(f.isEmpty ? "—" : f): \(xs.count)").font(Theme.f(10.5)).foregroundColor(Theme.faint).lineLimit(1).truncationMode(.middle) }
                                if let ex = items.first { Text(LF("Dovadă (exemplu): %@", ex.1.evidence)).font(Theme.f(10.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                            }.padding(.vertical, 2)
                        }
                    }
                    if !ed.failedPhotos.isEmpty { Text(L("Eroare de decodor (fișier citit, decodare eșuată): ") + ed.failedPhotos.prefix(3).map { ($0.key == 0 ? "" : "#\($0.key) ") + $0.value }.joined(separator: " · ")).font(Theme.f(10.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                }
                Box(title: L("Foldere sursă (pe disc, neatinse)")) {
                    if folders.isEmpty { Text(L("Niciun folder în catalog.")).font(Theme.f(12)).foregroundColor(Theme.muted) }
                    ForEach(folders) { f in HStack { Image(systemName: "folder"); Text(f.path).font(Theme.f(11.5)).lineLimit(1).truncationMode(.middle); Spacer(); Text("\(f.count)").font(Theme.f(11.5)).foregroundColor(Theme.muted)
                        Button(L("Scoate din catalog…")) { ask(L("Scoate folderul din catalog"), session.photos.filter { ($0.path as NSString).deletingLastPathComponent == f.path }.map { $0.id }) }.buttonStyle(SoftButtonStyle()) } }
                }
                Box(title: L("Albume (colecții virtuale)")) {
                    if session.albums.isEmpty { Text(L("Niciun album.")).font(Theme.f(12)).foregroundColor(Theme.muted) }
                    ForEach(session.albums) { a in HStack { Image(systemName: "rectangle.stack"); Text(a.name).font(Theme.f(12)); Spacer(); Text("\(a.count)").font(Theme.f(11.5)).foregroundColor(Theme.muted)
                        Button(L("Șterge albumul")) { try? session.deleteAlbum(a.id); note = LF("Albumul «%@» a fost șters; fotografiile rămân în catalog.", a.name) }.buttonStyle(SoftButtonStyle()).help(L("Șterge doar albumul; fotografiile, reglajele și fișierele rămân")) } }
                }
                Box(title: L("Coada de editare")) { Text(LF("%@ fotografii (%@). Coada e doar o selecție: scoaterea din coadă nu scoate din catalog și nu șterge nimic.", model.editQueue.count, model.editLabel.isEmpty ? "—" : model.editLabel)).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            } }
            if !note.isEmpty { Text(note).font(Theme.f(11.5)).foregroundColor(Theme.check) }
        }.padding(20).frame(minWidth: 620, minHeight: 540).background(Theme.app).foregroundColor(Theme.text)
        .alert(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(L("Scoate din catalog"), role: .destructive) { if let p = pending { let n = model.removeFromLibrary(ids: p.ids); note = LF("%@ fotografii scoase din catalog. Fișierele de pe disc nu au fost atinse.", n) }; pending = nil }
            Button(L("Renunță"), role: .cancel) { pending = nil }
        } message: { Text(LF("%@ fotografii: %@ cu reglaje salvate (se pierd), %@ în albume, %@ cu decizie păstrat/respins, %@ cu exporturi înregistrate (fișierele exportate rămân).\n\nFișierele originale NU se șterg.", impact.photos, impact.withEdits, impact.inAlbums, impact.decided, impact.exported)) }
    }
    init(model: AppModel, session: SelectionSession) { _model = ObservedObject(wrappedValue: model); _session = ObservedObject(wrappedValue: session); _ed = ObservedObject(wrappedValue: model.editing) }
    private func folderOf(_ id: Int64) -> String { session.photos.first { $0.id == id }.map { (($0.path as NSString).deletingLastPathComponent as NSString).lastPathComponent } ?? "" }
    private func runHealthCheck() {
        checking = true; checked = 0; let photos = session.photos
        DispatchQueue.global(qos: .utility).async {
            var out: [Int64: FileHealth] = [:]; var n = 0
            for p in photos { autoreleasepool { out[p.id] = FileHealth.inspect(path: p.path, recordedSize: p.size, stabilityDelay: p.size == 0 || p.size < 200_000 ? 0.4 : 0) }; n += 1; if n % 10 == 0 { let c = n; DispatchQueue.main.async { checked = c } } }
            DispatchQueue.main.async { health = out; checking = false; checked = photos.count }
        }
    }
    private func ask(_ title: String, _ ids: [Int64]) { impact = (try? model.catalog.removalImpact(photoIds: ids)) ?? Catalog.RemovalImpact(photos: ids.count); pending = (title, ids) }
}
