import SwiftUI
import PhotoCore
import PhotoResolve

/// Meniul «Reglaje» (în antetul inspectorului): Copiază · Lipește/Sincronizează… · Anulează ultima lipire. Nu e legat de butonul mijlociu (rezervat deplasării imaginii).
struct AdjustmentSyncMenu: View {
    @ObservedObject var ed: EditingModel; @State private var sheet = false
    var body: some View {
        Menu {
            Button(L("Copiază reglajele acestei fotografii")) { ed.copyAdjustments() }.disabled(ed.current == nil)
            Button(L("Lipește / sincronizează…")) { sheet = true }.disabled(ed.clipboard == nil)
            Divider(); Button(L("Anulează ultima lipire")) { ed.undoLastPaste() }.disabled(!ed.canUndoPaste)
        } label: { Image(systemName: "doc.on.clipboard") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("Copiază și lipește reglaje pe categorii, către una sau mai multe fotografii alese"))
        .sheet(isPresented: $sheet) { AdjustmentSyncSheet(ed: ed) }
    }
}

struct AdjustmentSyncSheet: View {
    @ObservedObject var ed: EditingModel; @EnvironmentObject var model: AppModel; @Environment(\.dismiss) var dismiss
    @State private var cats = Set(AdjustmentCategory.allCases.filter { $0.defaultOn }); @State private var chosen = Set<Int64>()
    var body: some View {
        let photos = model.editQueue
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(L("Lipește / sincronizează reglaje")).font(Theme.f(17, weight: .semibold)); Spacer(); Button(L("Închide")) { dismiss() }.buttonStyle(SoftButtonStyle()) }
            Text(LF("Sursa: %@. Se înlocuiesc DOAR categoriile bifate; restul fotografiei țintă rămâne neschimbat. Geometria, măștile, chart-ul și corecțiile de lentilă nu se copiază implicit.", ed.clipboard?.from ?? "—")).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(AdjustmentCategory.allCases, id: \.rawValue) { c in
                Toggle(c.label, isOn: Binding(get: { cats.contains(c) }, set: { if $0 { cats.insert(c) } else { cats.remove(c) } })).toggleStyle(.checkbox).font(Theme.f(12))
            }
            Divider()
            Text(L("Țintă (nimic preselectat în afară de fotografia curentă dacă o alegi):")).font(Theme.f(12, weight: .semibold))
            HStack { Button(L("Fotografia curentă")) { if let c = ed.current { chosen = [c.id] } }.buttonStyle(SoftButtonStyle()); Button(LF("Toată coada (%@)", photos.count)) { chosen = Set(photos.map { $0.id }) }.buttonStyle(SoftButtonStyle()); Button(L("Deselectează")) { chosen = [] }.buttonStyle(SoftButtonStyle()) }
            ScrollView { VStack(alignment: .leading, spacing: 3) { ForEach(photos, id: \.id) { p in
                Toggle(isOn: Binding(get: { chosen.contains(p.id) }, set: { if $0 { chosen.insert(p.id) } else { chosen.remove(p.id) } })) { HStack { Text((p.path as NSString).lastPathComponent).font(Theme.f(12)); Text(p.camera ?? "—").font(Theme.f(11)).foregroundColor(Theme.faint) } }.toggleStyle(.checkbox) } } }.frame(minHeight: 120, maxHeight: 240)
            HStack { Button(LF("Aplică la %@ fotografii", chosen.count)) { ed.pasteAdjustments(cats, to: photos.filter { chosen.contains($0.id) }.map { $0.id }) }.buttonStyle(PrimaryButtonStyle()).disabled(chosen.isEmpty || cats.isEmpty)
                Text(ed.syncMessage).font(Theme.f(11.5)).foregroundColor(Theme.muted) }
        }.padding(20).frame(minWidth: 620, minHeight: 520).background(Theme.app).foregroundColor(Theme.text)
    }
}
