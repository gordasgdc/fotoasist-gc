import SwiftUI
import PhotoCore
import PhotoResolve

/// Secțiuni pentru instrumentele adaptate din STYLE V3 (SPEC §23). Ordinea = ordinea de calcul (Regula 47): liniar (expunere → negru → zone → Tonal Balance → balans → Printer Lights → Channel Mix) apoi log (LGG → Roți → CDL → contrast/pivot → saturație → Hue/HSV). Toate pliabile, cu modul activabil și reset pe secțiune.
@MainActor func toolReset(_ ed: EditingModel, _ g: ToolSet.Group, _ title: String) -> SectionReset {
    SectionReset(help: LF("Resetează secțiunea «%@»; poți anula", title), isNeutral: ed.adjustments.tools.isNeutral(g)) { ed.resetSection(title) { $0.tools.reset(g) } }
}
struct TonalBalanceBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        Box(title: L("Balans tonal (umbre / lumini)"), panel: "tonalbalance", summary: ed.adjustments.tools.isNeutral(.tonalBalance) ? nil : L("activ"), module: ed.moduleBinding("tonalbalance"), reset: toolReset(ed, .tonalBalance, "Balans tonal")) {
            SliderRow(label: L("Umbre · temperatură"), help: L("Mired"), value: $ed.adjustments.tools.shadowsTemp, range: -60...60, fmt: "%+.0f")
            SliderRow(label: L("Umbre · tentă"), help: L("Verde ↔ magenta"), value: $ed.adjustments.tools.shadowsTint, range: -0.02...0.02, fmt: "%+.3f")
            SliderRow(label: L("Lumini · temperatură"), help: L("Mired"), value: $ed.adjustments.tools.highlightsTemp, range: -60...60, fmt: "%+.0f")
            SliderRow(label: L("Lumini · tentă"), help: L("Verde ↔ magenta"), value: $ed.adjustments.tools.highlightsTint, range: -0.02...0.02, fmt: "%+.3f")
            Details { Text(L("Mută balansul de alb doar în umbre sau doar în lumini (aceleași ferestre ca «Umbre» și «Lumini»), în liniar, înaintea balansului global. Ex.: umbre reci + lumini calde.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
struct PrinterBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        Box(title: L("Lumini de imprimare (printer lights)"), panel: "printer", summary: ed.adjustments.tools.isNeutral(.printer) ? nil : L("activ"), module: ed.moduleBinding("printer"), reset: toolReset(ed, .printer, L("Lumini de imprimare"))) {
            SliderRow(label: "Master", help: L("Puncte"), value: $ed.adjustments.tools.printerMaster, range: -50...50, fmt: "%+.1f")
            SliderRow(label: L("Roșu"), help: L("Puncte"), value: $ed.adjustments.tools.printerR, range: -50...50, fmt: "%+.1f")
            SliderRow(label: L("Verde"), help: L("Puncte"), value: $ed.adjustments.tools.printerG, range: -50...50, fmt: "%+.1f")
            SliderRow(label: L("Albastru"), help: L("Puncte"), value: $ed.adjustments.tools.printerB, range: -50...50, fmt: "%+.1f")
            Details { Text(L("1 punct = 1/8 de stop pe canal, în liniar (timing de laborator). Master se adună peste fiecare canal. Plus = mai luminos.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
struct ChannelMixBox: View {
    @ObservedObject var ed: EditingModel
    func cell(_ i: Int) -> some View { SliderRow(label: ["R←R", "R←G", "R←B", "G←R", "G←G", "G←B", "B←R", "B←G", "B←B"][i], value: Binding(get: { ed.adjustments.tools.cm[i] }, set: { ed.adjustments.tools.cm[i] = $0 }), range: -2...2, neutral: [1, 0, 0, 0, 1, 0, 0, 0, 1][i], fmt: "%.2f") }
    var body: some View {
        Box(title: L("Mixer de canale"), panel: "channelmix", summary: ed.adjustments.tools.isNeutral(.channelMix) ? nil : L("activ"), module: ed.moduleBinding("channelmix"), reset: toolReset(ed, .channelMix, L("Mixer de canale"))) {
            ForEach(0..<9, id: \.self) { cell($0) }
            Toggle(isOn: $ed.adjustments.tools.cmKeep) { Text(L("Păstrează neutrele (fiecare rând împărțit la suma lui)")).font(Theme.f(12)) }.toggleStyle(.switch).controlSize(.small)
            Details { Text(L("Matrice 3×3 în liniar, după balans. Ex. alb-negru: fiecare rând 0.30 / 0.59 / 0.11. «Păstrează neutrele» menține griurile neutre când rândurile nu însumează 1.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
/// Trei operații DISTINCTE în aceeași secțiune: LGG (Lift/Gamma/Gain), roți pe zone (cu praguri) și ASC CDL. Selectorul schimbă doar AFIȘAREA; toate valorile rămân aplicate, indiferent de ce e afișat.
enum ToneView: String, CaseIterable, Identifiable { case lgg, zones, cdl
    var id: String { rawValue }; var label: String { switch self { case .lgg: return L("Lift · Gamma · Gain"); case .zones: return L("Roți pe zone"); case .cdl: return L("ASC CDL") } }
}
struct WheelsBox: View {
    @ObservedObject var ed: EditingModel
    @AppStorage("gdcpa.tone.view") private var viewRaw = ToneView.zones.rawValue
    func w(_ i: Int, _ label: String) -> some View { SliderRow(label: label, value: Binding(get: { ed.adjustments.tools.wheels[i] }, set: { ed.adjustments.tools.wheels[i] = $0 }), range: -0.5...0.5, fmt: "%+.3f") }
    func triple(_ name: String, _ a: Int) -> some View { VStack(alignment: .leading, spacing: 2) { Text(name).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted); w(a, "R"); w(a + 1, "G"); w(a + 2, "B"); w(a + 3, "Master") } }
    func c(_ arr: WritableKeyPath<ToolSet, [Double]>, _ i: Int, _ label: String, _ r: ClosedRange<Double>, neutral: Double) -> some View { SliderRow(label: label, value: Binding(get: { ed.adjustments.tools[keyPath: arr][i] }, set: { ed.adjustments.tools[keyPath: arr][i] = $0 }), range: r, neutral: neutral, fmt: "%.3f") }
    private var tv: ToneView { ToneView(rawValue: viewRaw) ?? .zones }
    private func changed(_ g: ToolSet.Group) -> Bool { switch g { default: return false } }
    var body: some View {
        Box(title: L("Tonuri: LGG · roți · CDL"), panel: "wheels", summary: ed.adjustments.tools.isNeutral(.wheels) ? nil : L("activ"), module: ed.moduleBinding("wheels"), reset: toolReset(ed, .wheels, L("LGG, roți, CDL"))) {
            Picker("", selection: $viewRaw) { ForEach(ToneView.allCases) { Text($0.label).tag($0.rawValue) } }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
                .help(L("Alege ce operație vezi. Doar afișare: valorile celorlalte rămân aplicate și se păstrează."))
            switch tv {
            case .lgg:
                SliderRow(label: "Lift", help: L("Umbre"), value: $ed.adjustments.tools.lift, range: -0.5...0.5, fmt: "%+.3f")
                SliderRow(label: "Gamma", help: L("Mijloc"), value: $ed.adjustments.tools.gamma, range: 0.1...4, neutral: 1, fmt: "%.3f")
                SliderRow(label: "Gain", help: L("Lumini"), value: $ed.adjustments.tools.gain, range: 0...4, neutral: 1, fmt: "%.3f")
            case .zones:
                ZoneWheelsRow(ed: ed)
                Details(title: L("Praguri și valori R/G/B pe zone")) {
                    SliderRow(label: L("Umbrele se sting la"), help: L("Stopuri"), value: $ed.adjustments.tools.shadowLimit, range: -4...2, fmt: "%+.1f")
                    SliderRow(label: L("Luminile încep la"), help: L("Stopuri"), value: $ed.adjustments.tools.highlightStart, range: 1...7, neutral: 3.5, fmt: "%.1f")
                    triple(L("Umbre"), 0); triple(L("Mijloc"), 4); triple(L("Lumini"), 8)
                }
            case .cdl:
                ForEach(0..<3, id: \.self) { i in c(\.slope, i, "Slope " + ["R", "G", "B"][i], 0...4, neutral: 1) }
                ForEach(0..<3, id: \.self) { i in c(\.offset, i, "Offset " + ["R", "G", "B"][i], -0.5...0.5, neutral: 0) }
                ForEach(0..<3, id: \.self) { i in c(\.power, i, "Power " + ["R", "G", "B"][i], 0.1...4, neutral: 1) }
                SliderRow(label: L("Saturație CDL"), value: $ed.adjustments.tools.cdlSat, range: 0...4, neutral: 1, fmt: "%.2f")
            }
            SliderRow(label: "Mix", help: L("Modulul Tonuri"), value: $ed.adjustments.tools.toneMix, range: 0...1, neutral: 1, fmt: "%.2f")
            Details { VStack(alignment: .leading, spacing: 4) {
                Text(L("Cele trei operații sunt distincte și se aplică în ordine: LGG → roți pe zone → ASC CDL, pe codul log al familiei active (aceleași legi ca instrumentul GDC STYLE «Tone»; pragurile zonelor sunt în stopuri față de gri 18% al profilului, deci identice între familii). Roțile controlează aceleași valori ca sliderele R/G/B din «Praguri și valori pe zone»; selectorul de sus schimbă doar ce vezi, nu ce se aplică.")).font(Theme.f(11)).foregroundColor(Theme.faint)
            }.fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct HighlightsGamutBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        Box(title: L("Lumini și gamă"), panel: "highlights", summary: ed.adjustments.tools.isNeutral(.highlights) ? nil : L("activ"), module: ed.moduleBinding("highlights"), reset: toolReset(ed, .highlights, L("Lumini și gamă"))) {
            SliderRow(label: L("Cale spre alb · cantitate"), value: $ed.adjustments.tools.hgPathAmount, range: 0...1, fmt: "%.2f")
            SliderRow(label: L("Cale spre alb · început"), help: L("Stopuri peste gri 18%"), value: $ed.adjustments.tools.hgPathOnset, range: 0...8, neutral: 3, fmt: "%.1f")
            SliderRow(label: L("Compresie de gamă · cantitate"), value: $ed.adjustments.tools.hgGamutAmount, range: 0...1, fmt: "%.2f")
            SliderRow(label: L("Compresie de gamă · prag"), value: $ed.adjustments.tools.hgGamutThreshold, range: 0.5...0.99, neutral: 0.85, fmt: "%.2f")
            SliderRow(label: L("Rotunjirea luminilor · cantitate"), value: $ed.adjustments.tools.hgHlAmount, range: 0...1, fmt: "%.2f")
            SliderRow(label: L("Rotunjirea luminilor · genunchi"), help: L("Stopuri"), value: $ed.adjustments.tools.hgHlKnee, range: 0...6, neutral: 2.5, fmt: "%.1f")
            SliderRow(label: "Mix", value: $ed.adjustments.tools.hgMix, range: 0...1, neutral: 1, fmt: "%.2f")
            Details { Text(L("Pregătește luminile înaintea efectelor și a DRT-ului, în liniar real (curba familiei active): luminile tind spre alb fără a schimba luminanța; culorile din afara gamei se comprimă păstrând nuanța; luminile peste genunchi se rotunjesc uniform pe canale. Pragurile sunt în stopuri, deci identice pe toate familiile. Util la RAW-uri cu lumini aproape de tăiere.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct DiffusionBox: View {
    @ObservedObject var ed: EditingModel
    static let filters = ["Dark Mist", "Bright Mist", "Ember Mist", "Clear Mist", "Soft Veil", "Amber Veil", "Soft Detail"], strengths = ["1/8", "1/4", "1/2", "1", "2"]
    func s(_ label: String, _ kp: WritableKeyPath<ToolSet, Double>, _ r: ClosedRange<Double>, _ n: Double, _ f: String = "%.2f") -> some View { SliderRow(label: label, value: Binding(get: { ed.adjustments.tools[keyPath: kp] }, set: { ed.adjustments.tools[keyPath: kp] = $0 }), range: r, neutral: n, fmt: f) }
    var body: some View {
        Box(title: L("Difuzie și bloom (filtru de obiectiv)"), panel: "diffusion", summary: ed.adjustments.tools.isNeutral(.diffusion) ? nil : L("activ"), module: ed.moduleBinding("diffusion"), reset: toolReset(ed, .diffusion, L("Difuzie și bloom"))) {
            Picker(L("Filtru"), selection: Binding(get: { Int(ed.adjustments.tools.opFilter) }, set: { ed.adjustments.tools.opFilter = Double($0) })) { ForEach(0..<7, id: \.self) { Text(Self.filters[$0]).tag($0) } }.font(Theme.f(12))
            Picker(L("Treaptă"), selection: Binding(get: { Int(ed.adjustments.tools.opStrength) }, set: { ed.adjustments.tools.opStrength = Double($0) })) { ForEach(0..<5, id: \.self) { Text(Self.strengths[$0]).tag($0) } }.pickerStyle(.segmented).font(Theme.f(12))
            s("Difuzie · cantitate", \.opDiffusion, 0...1, 0)
            s("Bloom · prag (stopuri peste gri 18%)", \.opThreshold, 0...8, 2.5, "%.1f"); s(L("Bloom · mărime (fracție din înălțime)"), \.opSize, 0...1, 0.5); s("Bloom · cantitate", \.opBloom, 0...1, 0)
            s("Mix", \.opMix, 0...1, 1)
            Details { Text(L("Simulează un filtru de difuzie în fața obiectivului (energia se redistribuie, nu se adaugă) urmat de bloom-ul luminilor, în liniar, înaintea conversiei în log. Razele sunt relative la înălțimea fotografiei, deci aspectul e același la orice rezoluție. Port din «Optics» GDC STYLE (aproximări de comportament, nu măsurători ale unor filtre reale).")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Vectori de nuanță (230): șase culori (roșu, galben, verde, cyan, albastru, magenta); pentru fiecare, deplasare de nuanță, saturație și luminanță (în modelul HSV, pe codul log). Gri și negru rămân neatinse; fără limitare numerică a rezultatului.
struct HueVectorsBox: View {
    @ObservedObject var ed: EditingModel
    static let names = [L("Roșu"), L("Galben"), L("Verde"), "Cyan", L("Albastru"), "Magenta"]
    static let colors: [Color] = [Color(red: 1, green: 0.2, blue: 0.2), Color(red: 1, green: 0.85, blue: 0.1), Color(red: 0.2, green: 0.8, blue: 0.3), Color(red: 0.1, green: 0.85, blue: 0.9), Color(red: 0.25, green: 0.4, blue: 1), Color(red: 0.95, green: 0.2, blue: 0.85)]
    func hv(_ k: Int) -> Binding<Double> { Binding(get: { ed.adjustments.tools.hv[k] }, set: { var t = ed.adjustments.tools; t.hv[k] = $0; ed.adjustments.tools = t }) }
    var body: some View {
        Box(title: L("Vectori de nuanță (6 culori)"), panel: "huevectors", summary: ed.adjustments.tools.isNeutral(.hueVectors) ? nil : L("activ"), module: ed.moduleBinding("huevectors"), reset: toolReset(ed, .hueVectors, L("Vectori de nuanță"))) {
            Text(L("Ajustează fiecare familie de culoare separat: nuanță, saturație și luminanță. Griurile nu sunt afectate.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            SliderRow(label: L("Lățimea vectorului"), help: L("Grade"), value: Binding(get: { ed.adjustments.tools.hvWidth }, set: { ed.adjustments.tools.hvWidth = $0 }), range: 30...120, neutral: 60, fmt: "%.0f")
            ForEach(0..<6, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) { Circle().fill(Self.colors[i]).frame(width: 10, height: 10); Text(Self.names[i]).font(Theme.f(12, weight: .semibold)) }
                    SliderRow(label: L("Nuanță"), help: L("Grade"), value: hv(3 * i), range: -60...60, fmt: "%+.0f", track: [Self.colors[(i + 5) % 6], Self.colors[i], Self.colors[(i + 1) % 6]])
                    SliderRow(label: L("Saturație"), value: hv(3 * i + 1), range: 0...2, neutral: 1, fmt: "%.2f", track: [Color(white: 0.55), Self.colors[i]])
                    SliderRow(label: L("Luminanță"), help: L("Înmulțire HSV"), value: hv(3 * i + 2), range: 0...2, neutral: 1, fmt: "%.2f", track: [Color(white: 0.1), Color(white: 0.95)])
                }
            }
            SliderRow(label: "Mix", value: Binding(get: { ed.adjustments.tools.hvMix }, set: { ed.adjustments.tools.hvMix = $0 }), range: 0...1, neutral: 1, fmt: "%.2f")
        }
    }
}
