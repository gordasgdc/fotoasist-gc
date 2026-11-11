import SwiftUI
import PhotoCore
import PhotoResolve

/// Optică · Peliculă · Grain (efecte proprii; modele și contract: CPhotoCore/photo_fx.hpp). Ordinea controalelor = ordinea aplicării. Neutre implicit; module activabile; resetare pe secțiune.
struct OpticsBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        Box(title: L("Optică"), panel: "optics", summary: ed.adjustments.effects.opticsIsNeutral ? nil : L("activ"), module: ed.moduleBinding("optics"),
            reset: SectionReset(help: L("Resetează secțiunea «Optică»; poți anula"), isNeutral: ed.adjustments.effects.opticsIsNeutral) { ed.resetSection(L("Optică")) { $0.effects.resetOptics() } }) {
            SliderRow(label: L("Distorsiune"), help: L("+ butoi / − pernuță"), value: $ed.adjustments.effects.distortion, range: -100...100, fmt: "%+.0f")
            SliderRow(label: L("Aberație cromatică · roșu"), value: $ed.adjustments.effects.caRed, range: -100...100, fmt: "%+.0f")
            SliderRow(label: L("Aberație cromatică · albastru"), value: $ed.adjustments.effects.caBlue, range: -100...100, fmt: "%+.0f")
            SliderRow(label: L("Vinietă de obiectiv"), help: L("Corecție"), value: $ed.adjustments.effects.lensVignette, range: -100...100, fmt: "%+.0f")
            SliderRow(label: L("Vinietă creativă"), help: L("− întunecă"), value: $ed.adjustments.effects.vignette, range: -100...100, fmt: "%+.0f")
            if ed.adjustments.effects.vignette != 0 { SliderRow(label: L("Vinietă · început"), help: L("% din rază"), value: $ed.adjustments.effects.vignetteMid, range: 0...100, neutral: 50, fmt: "%.0f") }
            Details { Text(L("Corecțiile de distorsiune și aberație lucrează la eșantionarea sursei (o singură reeșantionare, împreună cu geometria); măștile rămân ancorate pe fotografie. Sunt modele cu un parametru, nu profiluri măsurate ale obiectivului. Dacă marginile rămân goale, nimic nu e inventat: decupează explicit.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct FilmBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        Box(title: L("Aspect pelicular (simplu)"), panel: "film", summary: ed.adjustments.effects.filmIsNeutral ? nil : L("activ"), module: ed.moduleBinding("film"),
            reset: SectionReset(help: L("Resetează secțiunea «Peliculă»; poți anula"), isNeutral: ed.adjustments.effects.filmIsNeutral) { ed.resetSection(L("Peliculă")) { $0.effects.resetFilm() } }) {
            SliderRow(label: L("Halație · prag"), help: L("Stopuri peste gri"), value: $ed.adjustments.effects.halThreshold, range: 0...4, neutral: 1.5, fmt: "%.1f")
            SliderRow(label: L("Halație · rază"), value: $ed.adjustments.effects.halRadius, range: 1...10, neutral: 5, fmt: "%.1f")
            SliderRow(label: L("Halație · căldură"), help: L("0 = alb"), value: $ed.adjustments.effects.halWarm, range: 0...1, neutral: 0.8, fmt: "%.2f")
            SliderRow(label: L("Halație · cantitate"), value: $ed.adjustments.effects.halAmount, range: 0...100, fmt: "%.0f")
            SliderRow(label: L("Diafonie coloranți"), value: $ed.adjustments.effects.filmCrosstalk, range: 0...0.3, fmt: "%.2f")
            SliderRow(label: L("Contrast"), value: $ed.adjustments.effects.filmContrast, range: -0.5...0.5, fmt: "%+.2f")
            SliderRow(label: "Toe", help: L("Umbre"), value: $ed.adjustments.effects.filmToe, range: 0...1, neutral: 0.4, fmt: "%.2f")
            SliderRow(label: "Shoulder", help: L("Lumini"), value: $ed.adjustments.effects.filmShoulder, range: 0...1, neutral: 0.5, fmt: "%.2f")
            SliderRow(label: L("Saturație în densitate"), value: $ed.adjustments.effects.filmSat, range: 0.5...1.5, neutral: 1, fmt: "%.2f")
            SliderRow(label: L("Cantitate"), help: "Mix", value: $ed.adjustments.effects.filmAmount, range: 0...100, fmt: "%.0f")
            Details { Text(L("Răspuns în stopuri față de gri 18% cu toe/shoulder asimptotice (gri 18% rămâne fix), diafonie între straturi și saturație în densitate; se aplică după corecțiile locale, înaintea DRT-ului. Strat SIMPLIFICAT propriu, NU GDC Film (lanț fotochimic, grăunte în densitate, MTF): va fi înlocuit de portul Film V3. Halația adaugă strălucirea estompată a luminilor (în liniar, înaintea curbei; raza e relativă la înălțimea livrabilului). Cantitate 0 = oprit.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct GrainBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        Box(title: L("Grăunte (simplu)"), panel: "grain", summary: ed.adjustments.effects.grainIsNeutral ? nil : L("activ"), module: ed.moduleBinding("grain"),
            reset: SectionReset(help: L("Resetează secțiunea «Grain»; poți anula"), isNeutral: ed.adjustments.effects.grainIsNeutral && ed.adjustments.effects.grainSeed == 1) { ed.resetSection("Grain") { $0.effects.resetGrain() } }) {
            SliderRow(label: L("Mărime"), help: L("Px la 2160 linii"), value: $ed.adjustments.effects.grainSize, range: 0.5...6, neutral: 1.5, fmt: "%.1f")
            SliderRow(label: L("Asperitate"), value: $ed.adjustments.effects.grainRough, range: 0...1, neutral: 0.5, fmt: "%.2f")
            SliderRow(label: L("Culoare"), help: L("0 = monocrom"), value: $ed.adjustments.effects.grainChroma, range: 0...1, neutral: 0.3, fmt: "%.2f")
            SliderRow(label: L("Umbre"), value: $ed.adjustments.effects.grainShadows, range: 0...2, neutral: 1, fmt: "%.2f")
            SliderRow(label: L("Lumini"), value: $ed.adjustments.effects.grainHighlights, range: 0...2, neutral: 1, fmt: "%.2f")
            SliderRow(label: L("Cantitate"), value: $ed.adjustments.effects.grainAmount, range: 0...100, fmt: "%.0f")
            HStack { Text(LF("Sămânță %@", ed.adjustments.effects.grainSeed)).font(Theme.f(12)).foregroundColor(Theme.muted); Spacer(); Button(L("Alt model")) { ed.adjustments.effects.grainSeed += 1 }.buttonStyle(SoftButtonStyle()) }
            Details { Text(L("Mărimea e relativă la înălțimea livrabilului (aceeași privire la 2160 de linii indiferent de rezoluție) și se calculează după decupare, la rezoluția exportului. Previzualizarea la rezoluție mică arată statistica corectă, dar nu pixelii exacți ai exportului: verifică la 100%. Negrul adânc rămâne curat; media luminii se păstrează. Model simplificat propriu (multiplicativ în stopuri), NU grăuntele GDC Film (aditiv în densitate), care îl va înlocui.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Film V3: lanț fotochimic (negativ Kodak → print), cu MTF, halație și grăunte în densitate. Port din motorul GDC (CPhotoCore/film3, MANIFEST.md); paritate numerică cu referința verificată (≤ 6e-8). Ordinea controalelor = ordinea procesului.
struct Film3Box: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        let f = Binding(get: { ed.adjustments.effects.film3 }, set: { ed.adjustments.effects.film3 = $0 })
        Box(title: L("Film (fotochimic)"), panel: "film3", summary: f.wrappedValue.on ? Film3.stockLabels[min(f.wrappedValue.negStock, 3)] : nil, module: ed.moduleBinding("film3"),
            reset: SectionReset(help: L("Resetează secțiunea «Film (fotochimic)»; poți anula"), isNeutral: !f.wrappedValue.on && f.wrappedValue == { var d = Film3(); d.on = false; return d }()) { ed.resetSection(L("Film (fotochimic)")) { $0.effects.film3 = Film3() } }) {
            Toggle(L("Folosește filmul fotochimic"), isOn: f.on).toggleStyle(.switch).controlSize(.small).font(Theme.f(12.5))
            Text(L("Domeniu: după toate ajustările, înaintea GDC DRT (coduri log ale familiei active). Nu intră în profilul personal; în Resolve se transferă ca intermediar «BAKED».")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            if f.wrappedValue.on {
                Picker(L("Stoc negativ"), selection: f.negStock) { ForEach(Array(Film3.stockLabels.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) } }.font(Theme.f(12))
                Text(Film3.stockInfos[min(f.wrappedValue.negStock, 3)]).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                SliderRow(label: L("Separare de culoare"), help: L("Spectrală"), value: f.colourSeparation, range: 0...1, fmt: "%.2f")
                SliderRow(label: L("Expunere"), help: L("Stopuri"), value: f.exposure, range: -4...4, fmt: "%+.2f")
                SliderRow(label: L("Contrast negativ"), help: L("Developare"), value: f.negContrast, range: 0.5...1.6, neutral: 1, fmt: "%.2f")
                Picker(L("Format"), selection: Binding(get: { f.wrappedValue.format }, set: { var v = f.wrappedValue; v.applyFormat($0); f.wrappedValue = v })) { ForEach(Array(Film3.formatLabels.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) } }.font(Theme.f(12))
                Text(String(format: L("Poartă %.2f mm. Formatul mută controalele legate la valorile lui de pornire; le poți edita apoi."), f.wrappedValue.gateMm)).font(Theme.f(10.5)).foregroundColor(Theme.faint)
                Toggle(L("Softness / MTF"), isOn: f.mtfOn).toggleStyle(.switch).controlSize(.small).font(Theme.f(12))
                if f.wrappedValue.mtfOn { SliderRow(label: "Softness", help: "× Super 35", value: f.softness, range: 0...12, neutral: 1, fmt: "%.2f") }
                Toggle(L("Halație"), isOn: f.halOn).toggleStyle(.switch).controlSize(.small).font(Theme.f(12))
                if f.wrappedValue.halOn { SliderRow(label: L("Halație · cantitate"), value: f.halAmount, range: 0...4, neutral: 1, fmt: "%.2f"); SliderRow(label: L("Halație · mărime"), help: L("% din lățimea cadrului"), value: f.halSizePct, range: 0.1...20, neutral: 1.6, fmt: "%.1f") }
                Toggle(L("Grăunte (în densitate)"), isOn: f.grainOn).toggleStyle(.switch).controlSize(.small).font(Theme.f(12))
                if f.wrappedValue.grainOn {
                    SliderRow(label: L("Grăunte · cantitate"), help: L("1 = granularitatea Kodak"), value: f.grainAmount, range: 0...2, neutral: 0.5, fmt: "%.2f")
                    SliderRow(label: L("Grăunte · mărime"), help: "× Super 35", value: f.grainSizeHuman, range: 0.1...12, neutral: 1, fmt: "%.2f")
                    SliderRow(label: L("Grăunte în umbre"), value: f.grainShadows, range: 0...3, neutral: 1, fmt: "%.2f")
                    SliderRow(label: L("Grăunte în lumini"), value: f.grainHighlights, range: 0...3, neutral: 1, fmt: "%.2f")
                    HStack { Text(LF("Sămânță %@", f.wrappedValue.grainSeed)).font(Theme.f(12)).foregroundColor(Theme.muted); Spacer(); Button(L("Alt model")) { var v = f.wrappedValue; v.grainSeed += 1; f.wrappedValue = v }.buttonStyle(SoftButtonStyle()) }
                }
                Picker(L("Stoc print"), selection: f.printStock) { ForEach(Array(Film3.printLabels.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) } }.font(Theme.f(12))
                SliderRow(label: L("Lumini de imprimare"), help: L("Puncte"), value: f.lightsMaster, range: -12...12, fmt: "%+.1f")
                SliderRow(label: L("Lumină roșu"), value: f.lightsR, range: -12...12, fmt: "%+.1f"); SliderRow(label: L("Lumină verde"), value: f.lightsG, range: -12...12, fmt: "%+.1f"); SliderRow(label: L("Lumină albastru"), value: f.lightsB, range: -12...12, fmt: "%+.1f")
                SliderRow(label: L("Contrast print"), help: L("Developare"), value: f.printContrast, range: 0.5...1.6, neutral: 1, fmt: "%.2f")
                SliderRow(label: "Mix", value: f.mix, range: 0...1, neutral: 1, fmt: "%.2f")
            }
            Details { Text(L("Curbele, granularitatea și MTF vin din fișele tehnice publice Kodak (VISION3 5219/5207/5213/5203; print 2383/2393). Colorantul de print și halația sunt aproximări necalibrate; developarea (contrast negativ/print) e MODELATĂ, nu măsurată. Calculul se face pe tot cadrul la rezoluția livrabilului: previzualizarea la rezoluție mică arată MTF/grăunte diferit de exportul final. Stratul simplu «Aspect pelicular»/«Grăunte (simplu)» rămâne separat, pentru reglajele existente.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// GDC Cinema Style: patru straturi (proces chimic · stoc de film · răspuns de contrast · culoare și piele) cu stil și mix, trim-uri, textură opțională după format. Port din biblioteca GDC (CPhotoCore/docs/ADAPTATION_MANIFEST.md); paritate cu referința verificată.
struct CinemaBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        let c = Binding(get: { ed.adjustments.effects.cinema }, set: { ed.adjustments.effects.cinema = $0 })
        let ready = CinemaLibrary.ensureLoaded()
        Box(title: L("Stiluri cinema (bibliotecă)"), panel: "cinema", summary: c.wrappedValue.on ? L("activ") : nil, module: ed.moduleBinding("cinema"),
            reset: SectionReset(help: L("Resetează secțiunea «Stiluri cinema»; poți anula"), isNeutral: !c.wrappedValue.on && c.wrappedValue == { var d = CinemaStyle(); d.on = false; return d }()) { ed.resetSection("Stiluri cinema") { $0.effects.cinema = CinemaStyle() } }) {
            if !ready { Text(L("Modelele de film lipsesc din aplicație: biblioteca nu poate fi folosită.")).font(Theme.f(11)).foregroundColor(Theme.reject) }
            Toggle(L("Folosește un stil cinema"), isOn: c.on).toggleStyle(.switch).controlSize(.small).font(Theme.f(12.5)).disabled(!ready)
            Text(L("86 de stiluri în 4 straturi, sub numele lor originale; numele producătorilor indică referința creativă, fără afiliere. Aplicat după ajustări, înaintea filmului fotochimic și a GDC DRT.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            if c.wrappedValue.on && ready {
                ForEach(0..<4, id: \.self) { s in
                    let list = CinemaLibrary.entries(ofLayer: s)
                    Toggle(CinemaLibrary.layerLabels[s], isOn: Binding(get: { c.wrappedValue.slots[s].on }, set: { var v = c.wrappedValue; v.slots[s].on = $0; c.wrappedValue = v })).toggleStyle(.switch).controlSize(.small).font(Theme.f(12))
                    if c.wrappedValue.slots[s].on {
                        Picker(L("Stil"), selection: Binding(get: { c.wrappedValue.slots[s].style }, set: { var v = c.wrappedValue; v.slots[s].style = $0; c.wrappedValue = v })) { ForEach(Array(list.enumerated()), id: \.offset) { Text($0.element.displayName).tag($0.offset) } }.font(Theme.f(12))
                        SliderRow(label: L("Mix strat"), value: Binding(get: { c.wrappedValue.slots[s].mix }, set: { var v = c.wrappedValue; v.slots[s].mix = $0; c.wrappedValue = v }), range: 0...1, neutral: 1, fmt: "%.2f")
                    }
                }
                Text(L("Trim-uri")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
                SliderRow(label: L("Expunere stil"), help: L("Stopuri"), value: c.exposure, range: -4...4, fmt: "%+.2f"); SliderRow(label: L("Contrast"), value: c.contrast, range: 0.5...1.6, neutral: 1, fmt: "%.2f")
                SliderRow(label: L("Densitate"), help: L("Stopuri"), value: c.density, range: -2...2, fmt: "%+.2f"); SliderRow(label: L("Căldură"), value: c.warmth, range: -1...1, fmt: "%+.2f")
                SliderRow(label: L("Tentă"), value: c.tint, range: -1...1, fmt: "%+.2f"); SliderRow(label: L("Saturație"), help: L("În densitate"), value: c.saturation, range: 0...2, neutral: 1, fmt: "%.2f")
                Text(L("Textură film (opțională, înaintea stilului pe expunere; grăuntele după stil)")).font(Theme.f(11.5, weight: .semibold)).foregroundColor(Theme.muted)
                Picker(L("Format"), selection: Binding(get: { c.wrappedValue.format }, set: { var v = c.wrappedValue; v.applyFormat($0); c.wrappedValue = v })) { ForEach(Array(Film3.formatLabels.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) } }.font(Theme.f(12))
                Picker(L("Model de textură"), selection: c.textureModel) { ForEach(Array(Film3.stockLabels.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) } }.font(Theme.f(12))
                Toggle(L("Softness / MTF"), isOn: c.mtfOn).toggleStyle(.switch).controlSize(.small).font(Theme.f(12)); if c.wrappedValue.mtfOn { SliderRow(label: "Softness", help: "× Super 35", value: c.softness, range: 0...12, neutral: 1, fmt: "%.2f") }
                Toggle(L("Halație"), isOn: c.halOn).toggleStyle(.switch).controlSize(.small).font(Theme.f(12)); if c.wrappedValue.halOn { SliderRow(label: L("Halație · cantitate"), value: c.halAmount, range: 0...4, neutral: 1, fmt: "%.2f"); SliderRow(label: L("Halație · mărime"), help: L("% cadru"), value: c.halSizePct, range: 0.1...20, neutral: 1.6, fmt: "%.1f") }
                Toggle(L("Grăunte (după stil)"), isOn: c.grainOn).toggleStyle(.switch).controlSize(.small).font(Theme.f(12))
                if c.wrappedValue.grainOn { SliderRow(label: L("Grăunte · cantitate"), value: c.grainAmount, range: 0...2, neutral: 0.5, fmt: "%.2f"); SliderRow(label: L("Grăunte · mărime"), help: "× Super 35", value: c.grainSizeHuman, range: 0.1...12, neutral: 1, fmt: "%.2f"); SliderRow(label: L("Grăunte în umbre"), value: c.grainShadows, range: 0...3, neutral: 1, fmt: "%.2f"); SliderRow(label: L("Grăunte în lumini"), value: c.grainHighlights, range: 0...3, neutral: 1, fmt: "%.2f")
                    HStack { Text(LF("Sămânță %@", c.wrappedValue.grainSeed)).font(Theme.f(12)).foregroundColor(Theme.muted); Spacer(); Button(L("Alt model")) { var v = c.wrappedValue; v.grainSeed += 1; c.wrappedValue = v }.buttonStyle(SoftButtonStyle()) } }
                SliderRow(label: L("Amount stil"), value: c.amount, range: 0...1, neutral: 1, fmt: "%.2f"); SliderRow(label: "Mix", value: c.mix, range: 0...1, neutral: 1, fmt: "%.2f")
            }
            Details { Text(L("Stilurile sunt modele hibride (matrice + curbe + reziduu 3D 17³, interpolare tetraedrică) potrivite pe LUT-urile colecției GDC; aspectul lor are verdict doar de la colorist, pe cadre reale. Calculul rulează pe tot cadrul la rezoluția livrabilului.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
