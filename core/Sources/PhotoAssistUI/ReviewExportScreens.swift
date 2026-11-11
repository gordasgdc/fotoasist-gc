import SwiftUI
import AppKit
import PhotoCore
import PhotoResolve

// MARK: Revizuire — evaluarea rezultatului. Grilă adaptivă; fiecare miniatură e rezultatul randat cu reglajele salvate ACTUALE sau e marcată ca depășită/neprocesată (nimic depășit nu apare drept final).

struct ReviewScreen: View {
    @ObservedObject var model: AppModel; @ObservedObject var ed: EditingModel
    enum Filter: String, CaseIterable { case all, approved, toCheck, processing, failed }
    @State private var filter: Filter = .all
    @State private var preview: PhotoRecord?

    var body: some View {
        let q = model.editQueue
        let status = Dictionary(uniqueKeysWithValues: q.map { ($0.id, ed.reviewStatus($0.id)) })
        let count: (Filter) -> Int = { f in switch f { case .all: return q.count; case .approved: return status.values.filter { $0 == .approved }.count; case .toCheck: return status.values.filter { $0 == .toCheck }.count; case .processing: return status.values.filter { $0 == .processing }.count; case .failed: return status.values.filter { $0 == .failed }.count } }
        let shown = q.filter { p in switch filter { case .all: return true; case .approved: return status[p.id] == .approved; case .toCheck: return status[p.id] == .toCheck; case .processing: return status[p.id] == .processing; case .failed: return status[p.id] == .failed } }
        let stale = q.filter { status[$0.id] == .toCheck && !ed.thumbIsFresh($0.id) }.count
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                header(q, count, stale)
                Segmented(options: Filter.allCases.map { f in (f, label(f) + " (\(count(f)))") }, selection: $filter)
                if !ed.statusLine.isEmpty && ed.current == nil { Text(ed.statusLine).font(Theme.f(12)).foregroundColor(Theme.check) }
                if shown.isEmpty { emptyState(count(.all)) }
                else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 620), spacing: 14, alignment: .top)], spacing: 14) { ForEach(shown, id: \.id) { p in tile(p, status[p.id] ?? .toCheck) } }.padding(.bottom, 8) } }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let p = preview { ReviewPreview(model: model, ed: ed, photo: p) { preview = nil }.transition(.opacity) }
        }.foregroundColor(Theme.text).onAppear { ed.reviewEnqueueAll(q) }
    }
    func label(_ f: Filter) -> String { switch f { case .all: return L("Toate"); case .approved: return L("Aprobate"); case .toCheck: return L("De verificat"); case .processing: return L("În procesare"); case .failed: return L("Eșuate") } }
    func header(_ q: [PhotoRecord], _ count: (Filter) -> Int, _ stale: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Revizuire")).font(Theme.f(24, weight: .semibold))
                Text(L("Rezultatele sunt randate cu reglajele salvate ale fiecărei fotografii. Aprobarea se acordă doar pe un rezultat actual; orice schimbare de reglaj o anulează.")).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let b = ed.batchProgress { ProgressView(value: Double(min(b.done, b.total)), total: Double(max(b.total, 1))).frame(width: 150).tint(Theme.accent); Text("\(min(b.done, b.total))/\(b.total)").font(Theme.f(12)).foregroundColor(Theme.muted)
                Button(L("Oprește")) { ed.reviewCancel() }.buttonStyle(SoftButtonStyle()) }
            else if stale > 0 { Button(LF("Procesează %@ depășite", stale)) { ed.reviewEnqueueAll(q) }.buttonStyle(SoftButtonStyle()).disabled(!ed.isReady) }
            if count(.failed) > 0 && ed.batchProgress == nil { Button(LF("Reîncearcă eșuatele (%@)", count(.failed))) { ed.reviewEnqueueAll(q, retryFailed: true) }.buttonStyle(SoftButtonStyle()) }
            Button(L("Înapoi la Stil")) { model.step = .style }.buttonStyle(SoftButtonStyle())
            Button(L("Continuă la Export")) { model.step = .export }.buttonStyle(PrimaryButtonStyle())
        }
    }
    func emptyState(_ total: Int) -> some View {
        VStack(spacing: 6) { Text(total == 0 ? L("Nicio fotografie în coada de editare.") : L("Nicio fotografie în această categorie.")).font(Theme.f(14, weight: .semibold)); Text(total == 0 ? L("Alege fotografiile în Selecție sau Bibliotecă.") : L("Schimbă filtrul de mai sus.")).font(Theme.f(12)).foregroundColor(Theme.muted) }
            .frame(maxWidth: .infinity, minHeight: 200)
    }
    func tile(_ p: PhotoRecord, _ st: EditingModel.ReviewStatus) -> some View {
        let fresh = ed.thumbIsFresh(p.id); let hasThumb = ed.thumbs[p.id] != nil
        return VStack(spacing: 0) {
            ZStack {
                Theme.canvas
                if let t = ed.thumbs[p.id] { Image(nsImage: t).resizable().aspectRatio(contentMode: .fit).opacity(fresh ? 1 : 0.4) }
                else { PhotoImage(photo: p, kind: .grid).opacity(0.35) }
                if st == .processing { ProgressView().controlSize(.regular) }
                if st == .failed { VStack(spacing: 4) { Image(systemName: "exclamationmark.triangle").foregroundColor(Theme.reject); Text(ed.reviewFailures[p.id] ?? "eroare").font(Theme.f(10.5)).foregroundColor(Theme.muted).lineLimit(3).multilineTextAlignment(.center) }.padding(10) }
                else if st != .processing && !fresh { Text(hasThumb ? L("rezultat depășit") : L("neprocesată · previzualizare din cameră")).font(Theme.f(11)).foregroundColor(Theme.muted).padding(5).background(Capsule().fill(Color.black.opacity(0.5))) }
            }.aspectRatio(1.5, contentMode: .fit).clipped().contentShape(Rectangle()).onTapGesture { preview = p }.onAppear { ed.reviewEnqueue(p) }
            HStack(spacing: 6) {
                Text((p.path as NSString).lastPathComponent).font(Theme.f(12)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                badge(st)
            }.padding(.horizontal, 8).padding(.top, 7)
            HStack(spacing: 6) {
                if st == .approved { Button(L("Retrage aprobarea")) { ed.setApproval(p.id, false) }.buttonStyle(SoftButtonStyle()) }
                else { Button(L("Aprobă")) { ed.setApproval(p.id, true) }.buttonStyle(SoftButtonStyle()).disabled(!fresh || st == .failed).help(fresh ? L("Aprobă rezultatul afișat") : L("Aprobarea cere un rezultat actual")) }
                Button(L("Editează")) { ed.open(p); model.step = .style }.buttonStyle(SoftButtonStyle())
                Spacer()
            }.padding(8)
        }.satin(10)
    }
    @ViewBuilder func badge(_ st: EditingModel.ReviewStatus) -> some View {
        switch st { case .approved: Badge(text: L("aprobată"), color: Theme.keep); case .toCheck: Badge(text: L("de verificat"), color: Theme.check); case .processing: Badge(text: L("în procesare"), color: Theme.accent); case .failed: Badge(text: L("eșuată"), color: Theme.reject) }
    }
}

/// Rezultatul mare, cu aceleași acțiuni ca în grilă (aprobare doar pe rezultat actual).
struct ReviewPreview: View {
    @ObservedObject var model: AppModel; @ObservedObject var ed: EditingModel
    let photo: PhotoRecord; let close: () -> Void
    var body: some View {
        let fresh = ed.thumbIsFresh(photo.id); let st = ed.reviewStatus(photo.id)
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Text((photo.path as NSString).lastPathComponent).font(Theme.f(15, weight: .semibold))
                    Text(st == .approved ? L("aprobată") : st == .failed ? L("eșuată") : st == .processing ? L("în procesare") : fresh ? L("rezultat actual · de verificat") : L("rezultat depășit/neprocesat")).font(Theme.f(12)).foregroundColor(st == .approved ? Theme.keep : Theme.muted)
                    Spacer()
                    if st == .approved { Button(L("Retrage aprobarea")) { ed.setApproval(photo.id, false) }.buttonStyle(SoftButtonStyle()) }
                    else { Button(L("Aprobă")) { ed.setApproval(photo.id, true) }.buttonStyle(PrimaryButtonStyle()).disabled(!fresh) }
                    Button(L("Editează")) { ed.open(photo); model.step = .style; close() }.buttonStyle(SoftButtonStyle())
                    Button(L("Închide")) { close() }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction)
                }
                ZStack {
                    Theme.canvas
                    if let t = ed.thumbs[photo.id] { Image(nsImage: t).resizable().aspectRatio(contentMode: .fit).opacity(fresh ? 1 : 0.5) } else { ProgressView() }
                    if let f = ed.reviewFailures[photo.id] { Text(f).font(Theme.f(12)).foregroundColor(Theme.reject).padding(12) }
                }.clipShape(RoundedRectangle(cornerRadius: 10))
                Text(L("Previzualizare randată cu reglajele salvate (nu rezoluția exportului). Aprobarea se leagă de acest rezultat.")).font(Theme.f(11)).foregroundColor(Theme.faint)
            }.padding(18).background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel)).padding(40)
        }.onAppear { ed.reviewEnqueue(photo) }
    }
}

// MARK: Export — configurare (stânga) și rezumat/progres (dreapta). Lotul, destinația și politica pentru nume existente sunt vizibile înainte de pornire.

struct ExportScreen: View {
    @ObservedObject var model: AppModel; @ObservedObject var ed: EditingModel
    var body: some View {
        let q = model.editQueue; let targets = ed.exportTargets(q)
        GeometryReader { g in
            let wide = g.size.width >= 980
            let content = Group {
                config(q, targets).frame(minWidth: 380, maxWidth: wide ? 600 : 720, alignment: .topLeading)
                summary(targets).frame(minWidth: 340, maxWidth: wide ? 900 : 720, alignment: .topLeading)
            }
            ScrollView { if wide { HStack(alignment: .top, spacing: 36) { content }.padding(32).frame(maxWidth: 1640, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .top) } else { VStack(alignment: .leading, spacing: 20) { content }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading) } }
        }.foregroundColor(Theme.text)
    }
    func config(_ q: [PhotoRecord], _ targets: [PhotoRecord]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Export")).font(Theme.f(24, weight: .semibold))
            Text(L("Originalele nu se ating și nu se scrie nimic în folderul lor. ") + (!targets.isEmpty && targets.allSatisfy { $0.isRendered } ? L("Intrări redate (PNG/JPEG/TIFF, nu RAW): fără DRT și fără normalizare RAW; culoarea ICC → sRGB; singura prelucrare aplicată este decuparea/geometria.") : LF("Motor: %@. Ieșire: %@", ed.engineName, ed.outputTransformName))).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            scopeBox(q, targets); formatBox; folderBox; collisionBox
        }
    }
    func scopeBox(_ q: [PhotoRecord], _ targets: [PhotoRecord]) -> some View {
        Box(title: L("Ce se exportă")) {
            Segmented(options: [(ExportScope.approved, LF("Aprobate (%@)", ed.approvedCount(in: q))), (.current, L("Fotografia curentă")), (.queue, LF("Toată coada (%@)", q.count))], selection: $ed.exportScope)
            if targets.isEmpty {
                Text(ed.exportScope == .approved ? L("Nicio fotografie aprobată. Aprobă fotografii în Revizuire sau alege altă variantă; nimic nu se exportă automat în locul lor.") : L("Nicio fotografie curentă deschisă în editor.")).font(Theme.f(12.5)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true)
            } else { Text(LF("%@ fotografii în lot.", targets.count)).font(Theme.f(12.5)) }
        }
    }
    var formatBox: some View {
        Box(title: L("Format și rezoluție")) {
            Segmented(options: [(false, L("TIFF 16 biți")), (true, "JPEG")], selection: $ed.exportFormatJPEG)
            if ed.exportFormatJPEG { SliderRow(label: L("Calitate JPEG"), value: $ed.jpegQuality, range: 0.7...1, neutral: 0.95, fmt: "%.2f") }
            KV(k: L("Rezoluție"), v: L("plină (după decupare și geometrie)")); KV(k: L("Profil de culoare"), v: L("sRGB IEC 61966-2.1, încorporat"))
        }
    }
    var folderBox: some View {
        Box(title: L("Destinație")) {
            HStack(alignment: .top) { Image(systemName: "folder").foregroundColor(Theme.accent); Text(ed.exportFolder?.path ?? "Niciun folder ales").foregroundColor(ed.exportFolder == nil ? Theme.muted : Theme.text).font(Theme.f(12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
            if let f = ed.exportFolder { let h = StorageConfig.checkExportDestination(f, needed: 1); if !h.isOK { Text(h.message).font(Theme.f(11.5)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) } }
            Button(L("Alege folderul…")) { ed.chooseExportFolder() }.buttonStyle(SoftButtonStyle())
            Text(L("Se alege pentru fiecare lot; ultima alegere se reține. Poate fi pe alt disc decât biblioteca.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
        }
    }
    var collisionBox: some View {
        Box(title: L("Dacă numele există deja")) {
            Segmented(options: ExportCollision.allCases.map { ($0, $0 == .unique ? L("Păstrează ambele") : $0 == .skip ? L("Omite") : L("Suprascrie")) }, selection: $ed.exportCollision)
            Text(ed.exportCollision.label + (ed.exportCollision == .unique ? L(": fișierul nou primește sufix (nume-2); cel existent rămâne neatins.") : ed.exportCollision == .skip ? L(": fotografia se omite și apare în rezumat; fișierul existent rămâne neatins.") : L(": fișierul existent este ÎNLOCUIT definitiv."))).font(Theme.f(12)).foregroundColor(ed.exportCollision == .overwrite ? Theme.check : Theme.muted).fixedSize(horizontal: false, vertical: true)
            if ed.exportCollision == .overwrite { Toggle(L("Confirm: fișierele existente cu același nume vor fi înlocuite"), isOn: $ed.exportOverwriteConfirmed).font(Theme.f(12)).toggleStyle(.checkbox) }
        }
    }
    func summary(_ targets: [PhotoRecord]) -> some View {
        let plan = ed.exportPlan(targets); let ext = ed.exportFormatJPEG ? "JPEG" : L("TIFF 16 biți")
        let existing: Int = { if case .idle = ed.exportState { return plan.filter { $0.planned.exists }.count }; return ed.exportItems.filter { if case .skipped = $0.state { return true }; return false }.count }()
        return VStack(alignment: .leading, spacing: 12) {
            Text(L("Rezumat")).font(Theme.f(16, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                KV(k: "Lot", v: targets.isEmpty ? "—" : LF("%@ fotografii", targets.count)); KV(k: L("Format"), v: ext); KV(k: L("Destinație"), v: ed.exportFolder?.path ?? "neales")
                KV(k: L("Nume existente"), v: ed.exportFolder == nil ? "—" : { if case .idle = ed.exportState { return existing == 0 ? L("niciunul") : "\(existing) — \(ed.exportCollision.label.lowercased())" }; return LF("%@ omise (fișierul exista deja)", existing) }())
                KV(k: L("Spațiu estimat"), v: targets.isEmpty ? "—" : StorageFormat.bytes(Int64(targets.count) * (ed.exportFormatJPEG ? 12 : 120) * 1_048_576))
            }.padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
            actions(targets); progress
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Fișiere")).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted)
                if plan.isEmpty { Text(ed.exportFolder == nil ? L("Alege destinația ca să vezi numele exacte.") : L("Niciun fișier în lot.")).font(Theme.f(12)).foregroundColor(Theme.faint) }
                ForEach(Array(plan.enumerated()), id: \.offset) { _, row in itemRow(row.photo, row.planned) }
            }
        }
    }
    func itemRow(_ p: PhotoRecord, _ pl: PlannedOutput) -> some View {
        let st = ed.exportItems.first { $0.id == p.id }?.state
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group { switch st { case .running: ProgressView().controlSize(.small); case .done: Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.keep); case .skipped: Image(systemName: "arrow.uturn.right.circle").foregroundColor(Theme.check); case .failed: Image(systemName: "xmark.octagon.fill").foregroundColor(Theme.reject); default: Image(systemName: "circle").foregroundColor(Theme.faint) } }.frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                let finalName: String = { if let st = st, case .done(let n) = st { return n }; return pl.url.lastPathComponent }()
                Text((p.path as NSString).lastPathComponent + "  →  " + finalName).font(Theme.f(12)).lineLimit(1).truncationMode(.middle)
                if let st = st, case .skipped(let m) = st { Text(m).font(Theme.f(11)).foregroundColor(Theme.check) }
                else if let st = st, case .failed(let m) = st { Text(m).font(Theme.f(11)).foregroundColor(Theme.reject).lineLimit(3) }
                else if let st = st, case .done = st { EmptyView() }
                else if pl.skipped { Text(L("există deja — va fi omisă")).font(Theme.f(11)).foregroundColor(Theme.check) }
                else if pl.exists { Text(ed.exportCollision == .overwrite ? L("există deja — va fi înlocuit") : L("numele există — se folosește sufix")).font(Theme.f(11)).foregroundColor(Theme.check) }
            }
        }
    }
    func actions(_ targets: [PhotoRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !ed.featureGate(.exportImages) { Text(L("Exportul e oprit: nu există un drept foto valid (vezi «Drept» din antet). Originalele, editările salvate și fișierele deja exportate rămân neatinse.")).font(Theme.f(12)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button(L("Înapoi la Revizuire")) { model.step = .review }.buttonStyle(SoftButtonStyle())
                Button(LF("Exportă %@", targets.count)) { ed.runExport(model.editQueue) }.buttonStyle(PrimaryButtonStyle()).disabled(!ed.featureGate(.exportImages) || !ed.isReady || ed.exportFolder == nil || ed.exportState != .idle || targets.isEmpty || !ed.exportCanStart)
            }
        }
    }
    @ViewBuilder var progress: some View {
        switch ed.exportState {
        case .idle: EmptyView()
        case .running(let d, let t): VStack(alignment: .leading, spacing: 6) { ProgressView(value: Double(d), total: Double(max(t, 1))).tint(Theme.accent); Text(LF("Se exportă %@/%@…", d, t)).font(Theme.f(12)).foregroundColor(Theme.muted) }
        case .finished(let n, let f): VStack(alignment: .leading, spacing: 6) {
            HStack { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.keep); Text(LF("%@ fotografii exportate în %@", n, f)).font(Theme.f(12.5)).fixedSize(horizontal: false, vertical: true) }
            let skipped = ed.exportItems.filter { if case .skipped = $0.state { return true }; return false }.count
            if skipped > 0 { Text(LF("%@ omise: fișierul exista deja (politica aleasă).", skipped)).font(Theme.f(12)).foregroundColor(Theme.check) }
            if !ed.exportFailures.isEmpty { Text(LF("%@ eșuate (originalele neatinse) — motivul e pe rândul fotografiei.", ed.exportFailures.count)).font(Theme.f(12)).foregroundColor(Theme.reject) }
            HStack { Button(L("Arată în Finder")) { NSWorkspace.shared.open(URL(fileURLWithPath: f)) }.buttonStyle(SoftButtonStyle()); Button(L("Export nou")) { ed.resetExport() }.buttonStyle(SoftButtonStyle()) } }
        case .failed(let m): VStack(alignment: .leading, spacing: 6) { Text(m).font(Theme.f(12)).foregroundColor(Theme.reject).fixedSize(horizontal: false, vertical: true); Button(L("Închide")) { ed.resetExport() }.buttonStyle(SoftButtonStyle()) }
        }
    }
}
