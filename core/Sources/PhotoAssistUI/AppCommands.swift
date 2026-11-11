import SwiftUI
import PhotoCore
import PhotoResolve

/// Comenzi în bara de meniu pentru acțiunile frecvente pe reglaje: aceleași funcții ca meniul din inspector (nu o a doua implementare), cu scurtături de tastatură și acces din meniul aplicației.
public struct AdjustmentCommands: Commands {
    @ObservedObject var host: AppHost
    public init(host: AppHost) { self.host = host }
    @Environment(\.openWindow) private var openWindow
    private var model: AppModel? { if case .ready(let m) = host.state { return m }; return nil }
    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("Despre FotoAsist GC…")) { openWindow(id: "about") }
            Button(L("Verifică actualizările…")) { openWindow(id: "about"); Task { await UpdateController.shared.check() } }
        }
        CommandGroup(replacing: .help) { ManualMenuItems() }
        CommandGroup(replacing: .appSettings) { Button(L("Setări…")) { model?.showStorage = true }.keyboardShortcut(",", modifiers: .command).disabled(model == nil) }
        CommandMenu(L("Reglaje")) {
            Button(L("Copiază reglajele fotografiei curente")) { if let ed = model?.editing, ed.current != nil { ed.copyAdjustments() } }.keyboardShortcut("c", modifiers: [.command, .shift])
            Button(L("Lipește reglajele (categoriile implicite) pe fotografia curentă")) {
                if let ed = model?.editing, let c = ed.current { ed.pasteAdjustments(Set(AdjustmentCategory.allCases.filter { $0.defaultOn }), to: [c.id]) }
            }.keyboardShortcut("v", modifiers: [.command, .shift])   // starea editării nu e observată de meniu: fără .disabled (rămânea învechit); acțiunea își verifică singură condițiile
            Button(L("Anulează ultima lipire")) { if let ed = model?.editing, ed.canUndoPaste { ed.undoLastPaste() } }
            Divider()
            Menu(L("Nivel de experiență (doar vizualizare)")) {
                ForEach(ExperienceLevel.allCases) { l in Button(l.label) { model?.editing.panels.level = l } }
            }
            Divider()
            Button(L("Deschide analiză într-o fereastră nouă")) { model?.editing.floating.openAnalysisWindow() }
            Button(L("Tablou de analize")) { model?.editing.floating.openAnalysisDashboard() }
            Button(L("Arată ferestrele de analiză")) { model?.editing.floating.showAnalysisWindows() }
            Button(L("Închide toate analizele")) { model?.editing.floating.closeAllAnalyses() }
            Divider()
            Button(L("Doar fotografia (comută)")) { if let ed = model?.editing, ed.current != nil { ed.photoOnly.toggle() } }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button(L("Bibliotecă…")) { model?.showLibrary = true }.disabled(model == nil)
        }
    }
}
