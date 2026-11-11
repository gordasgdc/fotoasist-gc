import SwiftUI
import PhotoCore
import PhotoResolve

/// «Creează profilul meu»: fluxul ghidat peste mecanismele existente (registru de perechi, estimator, evaluare pe perechi reținute). Pașii arată starea reală; nimic nu pornește fără confirmarea drepturilor.
/// Estimarea e locală și deterministă (nu ML, nu cloud). Un preset nu e profil: eticheta de încredere vine din numărul de perechi și din evaluarea pe perechi reținute.
struct ProfileFlowSheet: View {
    @ObservedObject var ed: EditingModel; @EnvironmentObject var model: AppModel; @Environment(\.dismiss) var dismiss
    @Binding var photographer: String; @Binding var setName: String; @Binding var profileName: String
    @State private var chosen = Set<Int64>()
    var body: some View {
        let reg = ed.profileRegistry
        let confirmed = reg.confirmedPairs(photographer: photographer, setName: setName)
        let proposed = reg.pairs.filter { $0.state == .proposed }
        let sp = ProfileRegistry.split(confirmed.filter { $0.learningApproved })
        let profile = reg.profiles.last(where: { $0.photographer == photographer && $0.setName == setName })
        ScrollView { VStack(alignment: .leading, spacing: 14) {
            HStack { Text(L("Creează profilul meu")).font(Theme.f(18, weight: .semibold)); Spacer(); Button(L("Închide")) { dismiss() }.buttonStyle(SoftButtonStyle()) }
            pathHeader(done: [!confirmed.isEmpty, proposed.isEmpty && !confirmed.isEmpty, profile?.status == .estimated, (profile?.heldOutPairIDs?.isEmpty == false), profile?.status == .estimated, false])
            Text(L("Profilul se învață local din exemplele tale (RAW + finalul tău editat). Nu folosește cloud și nu antrenează un model de stil. Un preset nu e un profil.")).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            step(1, L("Exemple"), done: !confirmed.isEmpty) {
                HStack(spacing: 6) { TextField(L("Fotograf"), text: $photographer).textFieldStyle(.roundedBorder); TextField(L("Set"), text: $setName).textFieldStyle(.roundedBorder) }.font(Theme.f(12))
                Button { ed.addExamplePair(photographer: photographer, setName: setName) } label: { Label(L("Adaugă pereche RAW + final"), systemImage: "plus.circle") }.buttonStyle(SoftButtonStyle())
                ForEach(reg.pairs.filter { $0.photographer == photographer && $0.setName == setName }) { p in
                    HStack(spacing: 6) { Badge(text: p.state == .confirmed ? L("confirmată") : (p.state == .rejected ? L("respinsă") : L("propusă")), color: p.state == .confirmed ? Theme.keep : (p.state == .rejected ? Theme.reject : Theme.check))
                        if p.state == .proposed { Button(L("Confirmă")) { ed.confirmPair(p.id) }.buttonStyle(SoftButtonStyle()).help(ProfileRegistry.confirmationText) }
                        Text((p.rawPath as NSString).lastPathComponent + " ↔ " + (p.finalPath as NSString).lastPathComponent).font(Theme.f(11.5)).lineLimit(1).truncationMode(.middle); Spacer()
                        Button { ed.removePair(p.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).help(L("Scoate perechea din registru (fișierele tale nu se șterg)")) }
                }
                Text(LF("Confirmate: %@. Profil EXPERIMENTAL de set mic: de la %@ perechi (evaluare doar indicativă). Evaluare cu dispersie: de la %@. Eticheta «evaluat» descrie un protocol (perechi reținute, câștig, consistență), nu doar un număr: vezi pasul 5. Cadrul: raportul de aspect RAW/final trebuie să coincidă (diferență < 1%); NU există încă aliniere pentru crop-uri diferite — astfel de perechi se omit din estimare cu motivul afișat, nu se resping la înregistrare.", confirmed.count, ProfileRegistry.minimumPairs, ProfileRegistry.experimentalMinPairs)).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            }
            Box(title: L("Câte exemple și ce fel")) {
                Text(LF("Recomandat: cel puțin %@ perechi de ajustare + %@ reținute pentru evaluare (%@ în total) pentru un profil EXPERIMENTAL; peste %@ + %@ perechi (%@ în total) pentru eticheta «evaluat». Minimul tehnic: %@ perechi confirmate. Sunt recomandări de protocol, nu garanții de calitate.", ProfileRegistry.experimentalFit, ProfileRegistry.experimentalHeldOut, ProfileRegistry.experimentalMinPairs, ProfileRegistry.evaluatedFit, ProfileRegistry.evaluatedHeldOut, ProfileRegistry.evaluatedMinPairs, ProfileRegistry.minimumPairs)).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Text(L("Diversitate necesară: lumini diferite (cel puțin 3 situații), subiecte și expuneri variate, același fotograf și același set; fotografii cu aceeași editare repetată nu aduc informație nouă. Profilul estimează doar câțiva parametri globali; nu înlocuiește editarea fiecărei fotografii.")).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Text(L("Timpul rămas apare după primele perechi și este doar media măsurată pe acest calculator; nu e o promisiune. Vezi progresul, oprește sau reia oricând.")).font(Theme.f(11)).foregroundColor(Theme.faint)
            }
            step(2, L("Drepturi și confirmare"), done: proposed.isEmpty && !confirmed.isEmpty) {
                Text("«\(ProfileRegistry.confirmationText)»").font(Theme.f(12)).fixedSize(horizontal: false, vertical: true)
                Button(LF("Confirm toate perechile propuse (%@)", proposed.count)) { for p in proposed { ed.confirmPair(p.id) } }.buttonStyle(SoftButtonStyle()).disabled(proposed.isEmpty)
            }
            step(3, L("Ce se ajustează și ce se evaluează"), done: !sp.fit.isEmpty) {
                Text(L("Parametri estimați: ") + ProfileEstimator.parameterNames.joined(separator: ", ") + L(". NU intră: corecții locale, retușuri, efecte, geometrie, curbe arbitrare.")).font(Theme.f(12)).fixedSize(horizontal: false, vertical: true)
                Text(LF("Separare deterministă: %@ perechi pentru AJUSTARE, %@ REȚINUTE pentru EVALUARE (nu intră niciodată în ajustare). Estimatorul e local, determinist (Nelder–Mead, mediană robustă).", sp.fit.count, sp.heldOut.count)).font(Theme.f(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            step(4, L("Estimare"), done: profile?.status == .estimated) {
                TextField(L("Nume profil"), text: $profileName).textFieldStyle(.roundedBorder).font(Theme.f(12))
                HStack { Button(L("Creează ciorna")) { ed.createDraftProfile(name: profileName, photographer: photographer, setName: setName) }.buttonStyle(SoftButtonStyle()).disabled(confirmed.isEmpty)
                    if let pr = profile {
                        if ed.profileBusy { Button(L("Oprește")) { ed.stopProfileEstimation() }.buttonStyle(SoftButtonStyle()) }
                        else if let b = reg.estimationBlocker(for: pr), pr.status != .estimated { Text(b).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
                        else { Button(ed.profileStopped ? L("Reia") : (pr.status == .estimated ? L("Re-estimează") : L("Estimează"))) { ed.estimateProfile(pr.id) }.buttonStyle(PrimaryButtonStyle()) } } }
                if ed.profileBusy { HStack(spacing: 6) { ProgressView().controlSize(.small); Text(ed.profileProgress).font(Theme.f(11.5)).foregroundColor(Theme.muted) } }
                if !ed.profileMessage.isEmpty { Text(ed.profileMessage).font(Theme.f(11.5)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
            }
            if let pr = profile, pr.status == .estimated {
                step(5, L("Rezultat"), done: true) {
                    HStack { Badge(text: ed.profileTrustLabel(pr), color: pr.heldOutPairIDs?.isEmpty == false ? Theme.keep : Theme.check); Text("«\(pr.name)» v\(pr.version)").font(Theme.f(12, weight: .semibold)) }
                    if let ev = pr.evaluation { Text(ev).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                    if pr.engineVersion != ProfileEstimator.engineIdentity { Text(L("Motorul sau setul de parametri s-a schimbat de la estimare: re-evaluează înainte de a te baza pe profil.")).font(Theme.f(11)).foregroundColor(Theme.check).fixedSize(horizontal: false, vertical: true) }
                    Text(L("Validat doar pe date sintetice și pe exemplele tale aprobate; nu se promite reproducerea exactă a editărilor tale.")).font(Theme.f(11)).foregroundColor(Theme.faint)
                }
                Box(title: L("Schimb de profil")) {
                    HStack { Button(L("Exportă profilul…")) { ed.exportProfile(pr.id) }.buttonStyle(SoftButtonStyle()); Button(L("Importă profil…")) { ed.importProfile(photographer: photographer, setName: setName) }.buttonStyle(SoftButtonStyle()) }
                    Text(L("Fișierul conține doar parametrii estimați și datele tehnice de compatibilitate: fără fotografiile de antrenare, căi, nume sau date personale. Un profil importat nu devine «evaluat»: transferabilitatea între camere și iluminări rămâne de evaluat.")).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                }
                step(6, L("Compară și aplică"), done: false) {
                    HStack { Button(ed.profileCompareActive ? L("Revino la reglajele mele") : L("Compară pe fotografia curentă")) { ed.toggleProfileCompare(pr.id) }.buttonStyle(SoftButtonStyle()).disabled(ed.current == nil)
                        Button(L("Aplică fotografiei curente")) { ed.applyProfile(pr.id) }.buttonStyle(SoftButtonStyle()).disabled(ed.current == nil) }
                    let photos = model.editQueue
                    HStack { Button(LF("Toată coada (%@)", photos.count)) { chosen = Set(photos.map { $0.id }) }.buttonStyle(SoftButtonStyle()); Button(L("Deselectează")) { chosen = [] }.buttonStyle(SoftButtonStyle())
                        Button(LF("Aplică la %@ fotografii", chosen.count)) { ed.applyProfileToBatch(pr.id, ids: photos.filter { chosen.contains($0.id) }.map { $0.id }) }.buttonStyle(PrimaryButtonStyle()).disabled(chosen.isEmpty) }
                    Text(chosen.isEmpty ? L("Alege lotul: toată coada de editare sau fotografii individuale. Nimic nu se aplică până nu apeși butonul.") : LF("Lot ales: %@ din %@ fotografii din coada de editare. Se schimbă doar parametrii profilului (contrast, saturație, umbre, lumini, temperatură, tentă, expunere); geometria, corecțiile locale, retușurile și efectele rămân neatinse.", chosen.count, photos.count)).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    HStack { Button(L("Anulează ultima aplicare")) { ed.undoLastPaste() }.buttonStyle(SoftButtonStyle()).disabled(!ed.canUndoPaste); Text(L("Aplicarea în lot se poate anula imediat (și din meniul «Reglaje»).")).font(Theme.f(11)).foregroundColor(Theme.faint) }
                    if !ed.syncMessage.isEmpty { Text(ed.syncMessage).font(Theme.f(11.5)).foregroundColor(Theme.muted) }
                }
            }
        }.padding(20) }.frame(minWidth: 640, minHeight: 560).background(Theme.app).foregroundColor(Theme.text)
    }
    /// Parcursul într-o privire: aleg exemplele → confirm perechile și drepturile → estimez → verific pe exemple reținute → salvez profilul → îl aplic unui lot ales.
    @ViewBuilder private func pathHeader(done: [Bool]) -> some View {
        let labels = [L("aleg exemplele"), L("confirm perechile și drepturile"), L("estimez"), L("verific pe exemple reținute"), L("salvez profilul"), L("îl aplic unui lot ales")]
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, t in HStack(spacing: 6) { Image(systemName: done[i] ? "checkmark.circle.fill" : "\(i + 1).circle").foregroundColor(done[i] ? Theme.keep : Theme.muted); Text(t).font(Theme.f(12)).foregroundColor(done[i] ? Theme.text : Theme.muted) } }
            Text(L("Profilul estimat se salvează automat în biblioteca ta. «Verific» = evaluare pe perechile reținute (nu intră niciodată în estimare).")).font(Theme.f(10.5)).foregroundColor(Theme.faint)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel2))
    }
    @ViewBuilder private func step<C: View>(_ n: Int, _ title: String, done: Bool, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) { Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle").foregroundColor(done ? Theme.keep : Theme.muted); Text(title).font(Theme.f(13.5, weight: .semibold)) }
            content()
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
    }
}
