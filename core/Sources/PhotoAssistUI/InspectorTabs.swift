import SwiftUI
import PhotoCore
import PhotoResolve

/// Histograma imaginii FINALE (sRGB după GDC DRT), în capul inspectorului; aceleași date ca panoul «Analiză» (nu valori ilustrative). Poate fi ascunsă; starea se păstrează.
struct InspectorHistogram: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        if ed.showHistogram {
            VStack(alignment: .leading, spacing: 4) {
                if let r = ed.analysisResult { HistogramView(h: r.histogram, scale: ed.histogramScale).frame(height: Theme.px(96)) }
                else { RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3)).frame(height: Theme.px(96)).overlay(Text(ed.current == nil ? "" : L("Se calculează histograma…")).font(Theme.f(11)).foregroundColor(Theme.faint)) }
                HStack(spacing: 6) {
                    Text(L("R · G · B · luminanță")).font(Theme.f(10.5)).foregroundColor(Theme.faint).lineLimit(1).help(L("Histograma imaginii finale: R, G, B și luminanță (linie întreruptă), în sRGB după GDC DRT, ca în export."))
                    Spacer(minLength: 4)
                    Menu { Picker(L("Scară verticală"), selection: $ed.histogramScale) { ForEach(HistogramScale.allCases) { Text($0.label).tag($0) } }.pickerStyle(.inline) } label: { Text((ed.currentIsRendered ? L("sRGB · imagine redată · ") : L("sRGB · după DRT · ")) + "\(ed.histogramScale.label) ⌄").font(Theme.f(10.5, weight: .semibold)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("Doar afișare: scara verticală a histogramei. Liniară = valorile reale; Rădăcină/Logaritmică scot în evidență distribuțiile concentrate (ex. fotografii întunecate)."))
                }
            }
        }
    }
}

/// Filele inspectorului: Bază · Culoare · Efecte · Mai mult. Doar organizare; nu schimbă și nu dezactivează nimic.
struct InspectorTabBar: View {
    @ObservedObject var panels: PanelState
    var body: some View {
        HStack(spacing: 2) {
            ForEach(InspectorTab.allCases) { t in
                Button { panels.tab = t } label: {
                    Text(t.label).font(Theme.f(12.5, weight: panels.tab == t ? .semibold : .regular)).foregroundColor(panels.tab == t ? Theme.text : Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(panels.tab == t ? Theme.selected : Color.clear))
                        .overlay(alignment: .bottom) { if panels.tab == t { Capsule().fill(Theme.accent).frame(width: Theme.px(28), height: 2).offset(y: 1) } }
                }.buttonStyle(.plain).accessibilityAddTraits(panels.tab == t ? .isSelected : [])
            }
        }.padding(2).background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel2))
    }
}
