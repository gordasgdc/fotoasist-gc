import SwiftUI
import PhotoCore
import PhotoResolve

/// Detalii: claritate + accentuare, pe luminanța imaginii finale. Metodă clasică (fără ML); radii relative la înălțimea cadrului.
struct DetailBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        let d = ed.adjustments.detail
        Box(title: L("Detalii (zgomot, claritate, accentuare)"), panel: "detail", summary: d.isNeutral ? nil : L("activ"), module: ed.moduleBinding("detail"),
            reset: SectionReset(help: L("Resetează «Detalii»; poți anula"), isNeutral: d.isNeutral) { ed.resetSection(L("Detalii")) { $0.detail.reset() } }) {
            SliderRow(label: L("Zgomot · luminanță"), value: $ed.adjustments.detail.nrLuma, range: DetailSettings.ranges["nr"]!, fmt: "%.2f")
            SliderRow(label: L("Zgomot · culoare"), value: $ed.adjustments.detail.nrChroma, range: DetailSettings.ranges["nr"]!, fmt: "%.2f")
            if d.nrLuma > 0 || d.nrChroma > 0 {
                Toggle(L("Preview rapid în timpul gestului"), isOn: $ed.fastGesturePreview).toggleStyle(.switch).controlSize(.small).font(Theme.f(12))
                    .help(L("Cât tragi o zonă sau un contur, previzualizarea nu aplică reducerea de zgomot (cadre mai rapide); rafinarea o aplică după eliberare. Nu schimbă reglajul salvat, aprobarea sau exportul."))
                Text(ed.autoSimplified ? L("Automat: pe acest Mac calculul cu reducere de zgomot e lent în gest, deci previzualizarea din timpul gestului e simplificată; rezultatul final o aplică.") : (ed.fastGesturePreview ? L("Previzualizarea din timpul gestului e simplificată (fără reducere de zgomot); rezultatul final o aplică la eliberare.") : L("Reducerea de zgomot se vede și în timpul gestului (măsurat: costă puțin pe acest Mac).")))
                    .font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            }
            SliderRow(label: L("Claritate"), help: L("Contrast local"), value: $ed.adjustments.detail.clarity, range: DetailSettings.ranges["clarity"]!, fmt: "%+.2f")
            SliderRow(label: L("Accentuare"), help: L("Cantitatea accentuării (0 = oprit)"), value: $ed.adjustments.detail.sharpAmount, range: DetailSettings.ranges["amount"]!, fmt: "%.2f")
            SliderRow(label: L("Rază accentuare"), help: L("‰ din înălțime"), value: $ed.adjustments.detail.sharpRadius, range: DetailSettings.ranges["radius"]!, neutral: 0.3, fmt: "%.2f")
            SliderRow(label: L("Prag"), help: L("Zgomotul fin nu se accentuează"), value: $ed.adjustments.detail.sharpThreshold, range: DetailSettings.ranges["threshold"]!, fmt: "%.3f")
            Details { VStack(alignment: .leading, spacing: 4) {
                Text(L("Ordinea: reducere de zgomot → claritate → accentuare, ultima etapă, pe imaginea finală sRGB (după GDC DRT). Zgomot luminanță = filtru ghidat care păstrează muchiile; zgomot culoare = înmoaie crominanța doar în zone de luminanță netedă, fără a schimba luminanța. Claritatea/accentuarea lucrează pe luminanța imaginii finale sRGB (după GDC DRT): aceeași diferență pe R, G, B, deci culoarea rămâne neschimbată. Claritatea = contrast local de scară mare (2% din înălțime), ponderat pe tonuri medii. Accentuarea = unsharp mask cu prag moale.")).font(Theme.f(11)).foregroundColor(Theme.faint)
                Text(L("Razele sunt fracții din înălțimea cadrului: aceeași imagine la previzualizare, zoom și export. Accentuarea ridică zgomotul când pragul e 0; reducerea de zgomot rulează înaintea ei. Detaliile NU se transferă în Resolve (se aplică pe imaginea finală FotoAsist).")).font(Theme.f(11)).foregroundColor(Theme.faint)
            }.fixedSize(horizontal: false, vertical: true) }
        }
    }
}
