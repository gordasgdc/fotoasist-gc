import SwiftUI
import AppKit
import PhotoCore

public struct RootView: View {
    @ObservedObject var model: AppModel
    var host: AppHost?
    @AppStorage(Theme.scaleKey) private var textLevel = 0
    @ObservedObject private var loc = Localizer.shared   // schimbarea limbii reconstruiește interfața
    public init(model: AppModel, host: AppHost? = nil) { self.model = model; self.host = host }
    @ViewBuilder private func topBar(compact: Bool) -> some View {
        HStack {
            if !compact { BrandLockup(height: 28, tint: Theme.text).help(L("FotoAsist GC · procesare locală, originalele rămân nemodificate")) }
            Button { model.showAbout = true } label: { Text("v\(AppInfo.version)").font(Theme.f(10.5)).foregroundColor(Theme.faint) }.buttonStyle(.plain).help(LF("FotoAsist GC %@ · build %@ — deschide Despre", AppInfo.version, AppInfo.build)).accessibilityLabel(LF("Versiunea aplicației %@", AppInfo.version))
                Spacer(); StepBar(current: model.step, canOpen: { model.canOpen($0) }, onSelect: { model.navigate(to: $0) }); Spacer()
                HStack(spacing: 8) {
                    AccessChip(access: model.access, compact: compact)
                    TextSizeMenu(level: $textLevel)
                    Button { model.showStorage = true } label: { Image(systemName: "gearshape").font(Theme.f(15)) }.buttonStyle(.plain).accessibilityLabel(L("Setări…")).help(L("Setări: limba aplicației, stocare și aspect (⌘,)"))
                    DiagnosticMenu(model: model)
                    if model.isBusy { ProgressView().controlSize(.small) }
                    if model.step != .imp { Menu { Button(L("Adaugă RAW…")) { model.chooseAndImport() }; Button(L("Adaugă imagini redate (PNG/JPEG/TIFF)…")) { model.chooseAndImportRendered() } } label: { Label(L("Adaugă"), systemImage: "plus").lineLimit(1).fixedSize() } primaryAction: { model.chooseAndImport() }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 10).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel2)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line)).disabled(model.isBusy).help(L("Adaugă fotografii RAW (⌘O); meniul: imagini redate")).keyboardShortcut("o", modifiers: .command) }
                    if model.session.counts.total > 0 { Button { model.showLibrary = true } label: { Text(L("Bibliotecă…")).lineLimit(1).fixedSize() }.buttonStyle(SoftButtonStyle()).help(L("Organizează biblioteca: scoate din catalog (fără a șterge originalele), albume, sesiune nouă")) }
                    if model.step == .selection { Button { model.proceedToEditing(all: true) } label: { Text(L("Sari peste selecție")).lineLimit(1).fixedSize() }.buttonStyle(SoftButtonStyle()) }
                }.frame(minWidth: 150, alignment: .trailing)
        }
    }
    public var body: some View {
        let _ = Theme.setLevelForTesting(textLevel)   /* sincronizat înainte ca vizualizările să-și citească mărimea; `id` de mai jos le reconstruiește la schimbare */
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                topBar(compact: false)
                topBar(compact: true)
                        }.padding(.horizontal, 16).padding(.vertical, 10).background(Theme.toolbar).foregroundColor(Theme.text).zIndex(2)   // peste pânză: un strat de editare mai mare decât pânza (100%) nu prinde clicurile barei de file
            Divider().overlay(Theme.line)
            StorageBanner(model: model)
            Group {
                switch model.step {
                case .imp: if model.session.photos.isEmpty { ImportScreen(model: model) } else { LibraryScreen(model: model, session: model.session) }
                case .selection: SelectionScreen(session: model.session, faces: model.faces, onContinue: { all in model.proceedToEditing(all: all) }, onEdit: { ids, label in model.proceedToEditing(ids: ids, label: label) }, onRemoveFromCatalog: { ids in
                    let imp = (try? model.catalog.removalImpact(photoIds: ids)) ?? Catalog.RemovalImpact(photos: ids.count)
                    let msg = LF("%@: %@ cu reglaje salvate (se pierd), %@ în albume, %@ cu decizie păstrat/respins. Fișierele originale și exporturile NU se șterg.", nFoto(imp.photos), imp.withEdits, imp.inAlbums, imp.decided)
                    if confirm(LF("Scoți %@ din catalog?", nFoto(ids.count)), msg, ok: L("Scoate din catalog")) { _ = model.removeFromLibrary(ids: ids) } })
                case .style: StyleScreen(model: model, ed: model.editing, panels: model.editing.panels)
                case .review: ReviewScreen(model: model, ed: model.editing)
                case .export: ExportScreen(model: model, ed: model.editing)
                }
            }
        }
        .id("\(textLevel)-\(loc.resolved.rawValue)").environmentObject(model.store).background(Theme.app).preferredColorScheme(.dark).tint(Theme.accent).sheet(isPresented: $model.showAbout) { AboutSheet(model: model) }.sheet(isPresented: $model.showLibrary) { LibraryManageSheet(model: model, session: model.session) }.sheet(isPresented: $model.showStorage) { StorageSettingsSheet(model: model, host: host) }
    }
}

struct ImportScreen: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Importă fotografii")).font(Theme.f(24, weight: .semibold))
                Text(L("Alege un folder cu RAW-uri. Aplicația îl citește fără să scrie nimic în el; catalogul, miniaturile și analizele merg într-o bibliotecă separată.")).font(Theme.f(13.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Image(systemName: "folder").foregroundColor(Theme.accent); Text(model.sourceFolder?.path ?? "Niciun folder ales").foregroundColor(model.sourceFolder == nil ? Theme.muted : Theme.text).lineLimit(1).truncationMode(.middle); Spacer() }
                    HStack { Button { model.chooseAndImport() } label: { Label(L("Adaugă fotografii"), systemImage: "plus").lineLimit(1).fixedSize() }.buttonStyle(PrimaryButtonStyle()); Text(L("Formate: ARW, CR2, CR3, DNG, NEF, RAF, RW2, ORF")).font(Theme.f(12)).foregroundColor(Theme.muted) }
                    HStack { Button(L("Imagini redate (demonstrație)…")) { model.chooseAndImportRendered() }.buttonStyle(SoftButtonStyle()).help(L("Cale separată de RAW: PNG, JPEG sau TIFF deja redate. Nu sunt RAW-uri; nu primesc DRT; singura prelucrare permisă e decuparea/geometria.")); Text(L("PNG · JPEG · TIFF, nu RAW")).font(Theme.f(11)).foregroundColor(Theme.faint) }
                    phaseView
                }.padding(16).background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
                if model.phase == .done { Button(L("Continuă la Selecție")) { model.goToSelection() }.buttonStyle(PrimaryButtonStyle()) }
                Spacer()
            }.frame(width: 560)
            VStack(alignment: .leading, spacing: 12) {
                if model.session.photos.isEmpty, let hero = Brand.heroImage() {
                    // Bun venit: imaginea aprobată, discretă, pe suprafață dedicată (nu în spatele fotografiilor și nu în editor); decor, fără rol de informare.
                    Image(nsImage: hero).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
                        .accessibilityLabel(L("Imagine ilustrativă: automobil sport conceptual într-un laborator alb")).accessibilityAddTraits(.isImage)
                    Text(L("Imagine ilustrativă · metaforă vizuală")).font(Theme.f(10.5)).foregroundColor(Theme.faint)
                }
                Text(L("Ce se întâmplă la import")).font(Theme.f(12, weight: .semibold)).foregroundColor(Theme.muted)
                Box(title: L("Previzualizări")) { Text(L("Se folosește previzualizarea încorporată de cameră (rapid, fără a developa RAW-ul). Nu e aspectul exportului final.")).font(Theme.f(12)).foregroundColor(Theme.muted) }
                Box(title: L("Analiză clasică"), auto: true, tag: L("sugestii")) { Text(L("Gruparea sugerată folosește timpul și similitudinea cadrelor; pe fețe: indiciu de ochi și claritate locală. Nu sunt verdicte; decizia rămâne a ta.")).font(Theme.f(12)).foregroundColor(Theme.muted) }
                if let s = model.importSummary {
                    Box(title: L("Rezultat import")) { KV(k: L("Adăugate"), v: "\(s.added)"); KV(k: "Actualizate", v: "\(s.updated)"); KV(k: L("Neschimbate (cache păstrat)"), v: "\(s.unchanged)"); KV(k: L("Cu previzualizare din cameră"), v: "\(s.withPreview)"); KV(k: L("Fără previzualizare"), v: "\(s.withoutPreview)"); KV(k: "Aparate", v: s.cameras.joined(separator: ", ")) }
                    if !s.skipped.isEmpty { Box(title: LF("Fișiere omise (%@)", s.skipped.count)) {
                        Text(L("Importul a continuat cu restul; originalele nu au fost modificate.")).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(s.skipped.prefix(8).enumerated()), id: \.offset) { _, k in VStack(alignment: .leading, spacing: 1) { Text(k.path).font(Theme.f(11, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled); Text(k.reason).font(Theme.f(11)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) } }
                        if s.skipped.count > 8 { Text(LF("… și încă %@ (vezi jurnalul).", s.skipped.count - 8)).font(Theme.f(11)).foregroundColor(Theme.faint) } } }
                }
                Spacer()
            }.frame(maxWidth: 380)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).foregroundColor(Theme.text)
    }
    @ViewBuilder var phaseView: some View {
        switch model.phase {
        case .idle: Text(L("Gata de import.")).font(Theme.f(12)).foregroundColor(Theme.muted)
        case .scanning: HStack { ProgressView().controlSize(.small); Text(L("Se citește folderul…")).font(Theme.f(12)).foregroundColor(Theme.muted) }
        case .previews(let d, let t): VStack(alignment: .leading, spacing: 6) { ProgressView(value: Double(d), total: Double(max(t, 1))).tint(Theme.accent); Text(LF("Previzualizări din cameră: %@/%@", d, t)).font(Theme.f(12)).foregroundColor(Theme.muted) }
        case .analyzing(let d, let t): VStack(alignment: .leading, spacing: 6) { ProgressView(value: Double(d), total: Double(max(t, 1))).tint(Theme.accent); Text(LF("Analiză clasică (sugestii): %@/%@", d, t)).font(Theme.f(12)).foregroundColor(Theme.muted) }
        case .done: HStack { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.keep); Text(LF("Import încheiat · %@ fotografii în catalog", model.session.counts.total)).font(Theme.f(12.5)) }
        case .failed(let m): Text(LF("Eroare: %@", m)).font(Theme.f(12)).foregroundColor(Theme.reject)
        }
    }
}

/// Preferința de mărime a textului și controalelor (Normal / Mărit / Mare), persistentă între sesiuni; se aplică imediat, în toată aplicația.
struct TextSizeMenu: View {
    @Binding var level: Int
    var body: some View {
        Menu {
            ForEach(Theme.scaleOptions, id: \.level) { o in Button { level = o.level } label: { Text(o.label + (o.level == level ? "  ✓" : "")) } }
        } label: { Text(L("Aa")).font(Theme.f(14, weight: .semibold)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("Mărimea textului și a controalelor (Normal / Mărit / Mare); se păstrează între sesiuni"))
    }
}
