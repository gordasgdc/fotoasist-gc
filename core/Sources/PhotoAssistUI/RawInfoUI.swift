import SwiftUI
import PhotoCore
import PhotoRaw
import PhotoResolve

/// «RAW și cameră»: ce a citit decodorul din fișier și ce transformări se aplică până la imaginea finală. Doar informare; nu schimbă nicio valoare și nu se exportă.
struct RawInfoBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        Box(title: L("RAW și cameră (informații)"), panel: "rawinfo", summary: ed.decodeInfo.map { "\($0.make) \($0.model)" }) {
            if let d = ed.decodeInfo {
                KV(k: "Aparat", v: "\(d.make) \(d.model)")
                KV(k: L("Decodor"), v: LF("LibRaw %@ (decodare RAW → liniar, fără demosaic proprietar)", d.libRawVersion))
                KV(k: L("Balans de alb din cameră (R : G : B)"), v: d.wbMultipliers.map { String(format: "%.3f", $0) }.joined(separator: " : "))
                KV(k: L("Nivel negru · alb · maxim fabricant"), v: "\(d.whitePlan.black) · \(d.whitePlan.white) · \(d.whitePlan.vendorWhite)")
                KV(k: L("Politică lumini"), v: d.highlight.rawValue)
                KV(k: L("Canale peste alb după balans"), v: String(format: L("%.2f%% din pixeli"), d.fracChannelOverWhiteAfterWB * 100))
                KV(k: L("Orientare aplicată"), v: "\(d.orientationFlip)")
                Details(title: L("Traseul de culoare, pas cu pas")) {
                    Text(L("RAW (valori senzor) → scădere negru + alb de referință → balans de alb al camerei → matrice cameră → DaVinci Wide Gamut LINIAR → instrumente liniare (expunere, umbre/lumini, balans) → [familie de lucru: DaVinci Intermediate sau log ACES/ARRI] → instrumente în log (ton, saturație, culoare, piele, Look) → efecte → GDC DRT (singura conversie spre afișaj) → sRGB. Imaginea finală pe care o vezi, o analizezi și o exporți este ultima.")).font(Theme.f(11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    Text(L("Aplicația importă acum doar fișiere RAW. Nu există un al doilea DRT: un JPEG/TIFF nu ar primi tone mapping suplimentar (importul lor nu există încă; controalele specifice RAW nu au ce dezactiva până atunci).")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                }
            } else { Text(L("Alege o fotografie: informațiile apar după prima previzualizare.")).font(Theme.f(12)).foregroundColor(Theme.muted) }
        }
    }
}

/// «Dezvoltare RAW»: compensarea dezvoltării (separată de «Expunere») și revizia decodării. Implicit «Oprit» (0 EV); valoarea camerei se arată și se aplică NUMAI la alegerea fotografului. Valoarea aplicată e vizibilă; totul e anulabil și persistă cu reglajele.
struct RawDevelopmentBox: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        let dev = ed.adjustments.rawDev; let d = ed.decodeInfo; let shift = d?.cameraExposureShift
        let applied = dev.appliedEV(cameraShift: shift)
        Box(title: L("Dezvoltare RAW"), panel: "rawdev", summary: applied == 0 ? nil : String(format: "%+.2f EV", applied)) {
            KV(k: L("Compensarea camerei (RawExposureBias)"), v: shift.map { String(format: L("%+.2f EV (fișierul RAW e mai întunecat decât redarea camerei)"), $0) } ?? L("nedeclarată de cameră"))
            HStack { Text(L("Compensare")).font(Theme.f(12)).foregroundColor(Theme.muted); Spacer()
                Segmented(options: [(RawDevelopment.Baseline.off, L("Oprit")), (.camera, L("Cameră")), (.manual, L("Manual"))], selection: Binding(get: { ed.adjustments.rawDev.baseline }, set: { v in if v != ed.adjustments.rawDev.baseline { ed.registerReset(L("Compensarea dezvoltării RAW a fost schimbată (poți anula)")); ed.adjustments.rawDev.baseline = v } })) }
            if dev.baseline == .manual { SliderRow(label: L("Compensare manuală (EV)"), value: $ed.adjustments.rawDev.manualEV, range: RawDevelopment.manualRange, fmt: "%+.2f") }
            KV(k: L("Aplicat acum"), v: String(format: L("%+.2f EV, câștig liniar la dezvoltare"), applied))
            Text(L("Implicit «Oprit» (0 EV). «Cameră» aplică valoarea declarată de aparat în fișier; semnificația ei nu e confirmată oficial de producător pentru acest model, de aceea alegerea îți aparține. Compensarea e un câștig liniar aplicat la citirea RAW, înaintea oricărui reglaj (nu înlocuiește «Expunere»). În modul automat de expunere estimarea compensează, deci rezultatul total e același."))
                .font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            if dev.isLegacyDecode, d?.make.uppercased().contains("FUJI") == true {
                let blockers = ed.rawUpdateBlockers()
                Text(L("Dezvoltare RAW anterioară")).font(Theme.f(12).weight(.semibold))
                Text(L("Această fotografie a fost editată cu dezvoltarea RAW anterioară (negru Fuji pe model de pixeli ignorat și cadru tăiat la 3:2). Aspectul ei nu s-a schimbat. «Actualizează» folosește negrul corect și cadrul 4:3 complet; poți anula (⌘Z) și reveni exact la starea veche."))
                    .font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                if blockers.isEmpty {
                    Button(L("Actualizează dezvoltarea RAW (poți anula)")) { ed.updateRawDevelopment() }.controlSize(.small)
                } else {
                    Text(L("Actualizarea e blocată pentru această fotografie: cadrul se schimbă (3:2 → 4:3), iar editările de mai jos sunt legate de poziții din cadrul vechi și ar fi deplasate. Dezvoltarea veche rămâne neschimbată; scoate sau resetează aceste editări dacă vrei să actualizezi.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                    ForEach(blockers, id: \.self) { b in Text("• " + b).font(Theme.f(10.5)).foregroundColor(Theme.muted) }
                }
            }
        }
    }
}
