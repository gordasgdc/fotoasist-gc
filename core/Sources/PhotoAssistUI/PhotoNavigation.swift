import SwiftUI
import AppKit
import PhotoCore

/// Navigare între fotografiile LOTULUI ACTIV (coada de editare existentă) în «Doar fotografia»: fără galerie paralelă, fără revenire circulară, fără fotografii din afara lotului.
public enum PhotoNav {
    /// Indexul țintă după `delta` (+1 următoarea, −1 precedenta) sau nil la capăt / dacă fotografia curentă nu e în lot.
    public static func target(ids: [Int64], current: Int64?, delta: Int) -> Int? {
        guard let c = current, let i = ids.firstIndex(of: c) else { return nil }
        let j = i + delta; return ids.indices.contains(j) ? j : nil
    }
    public static func position(ids: [Int64], current: Int64?) -> (index: Int, total: Int)? {
        guard let c = current, let i = ids.firstIndex(of: c) else { return nil }; return (i + 1, ids.count)
    }
    /// Săgeată (cod tastă) → pas: dreapta/jos = +1, stânga/sus = −1; fără modificatori (⌘ ⌥ ⌃ ⇧ rezervate altor funcții).
    public static func delta(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Int? {
        guard modifiers.intersection([.command, .option, .control, .shift]).isEmpty else { return nil }
        switch keyCode { case 124, 125: return 1; case 123, 126: return -1; default: return nil }
    }
}

extension EditingModel {
    /// Trece la fotografia vecină din `queue`; `open` confirmă întâi câmpul numeric în curs pe fotografia de origine, salvează, anulează randarea veche și golește istoricul gestului. Întoarce false la capăt.
    @discardableResult public func navigate(_ delta: Int, in queue: [PhotoRecord]) -> Bool {
        guard let j = PhotoNav.target(ids: queue.map { $0.id }, current: current?.id, delta: delta) else { return false }
        open(queue[j]); if queue.indices.contains(j + delta) { prefetchNeighbor(queue[j + delta]) }; return true
    }
}

/// Monitor local de taste, activ DOAR cât «Doar fotografia» e pornit. Nu interceptă când se scrie text, când un control AppKit cu săgeți are focus (slider), într-un dialog/foaie sau când fereastra nu e activă.
struct PhotoNavKeys: NSViewRepresentable {
    var enabled: Bool; var onStep: (Int) -> Void
    func makeNSView(context: Context) -> NSView { let v = V(); v.owner = self; return v }
    func updateNSView(_ v: NSView, context: Context) { (v as? V)?.owner = self }
    final class V: NSView {
        var owner: PhotoNavKeys?; private var monitor: Any?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.handle(e) ?? e } }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
        override func hitTest(_ p: NSPoint) -> NSView? { nil }
        private func handle(_ e: NSEvent) -> NSEvent? {
            // fereastra-cheie e fereastra principală SAU un panou flotant al aplicației (analize, histogramă etc.): săgețile nu au altă funcție acolo
            guard let o = owner, o.enabled, let w = window, let kw = NSApp.keyWindow, (kw === w || kw is NSPanel), e.window === kw, w.attachedSheet == nil, NSApp.modalWindow == nil,
                  let d = PhotoNav.delta(keyCode: e.keyCode, modifiers: e.modifierFlags) else { return e }
            if kw.firstResponder is NSText || kw.firstResponder is NSTextView || kw.firstResponder is NSTextField { return e }
            if let r = kw.firstResponder as? NSView, String(describing: type(of: r)).contains("SliderKey") { return e }
            o.onStep(d); return nil
        }
    }
}

/// Bară discretă (jos, centrat): nume, poziția «3 din 24», precedent/următor; pe fundal translucid mic, mai vizibilă la trecerea mouse-ului; arată încărcarea sau eroarea fotografiei curente.
struct PhotoNavBar: View {
    @ObservedObject var ed: EditingModel; @ObservedObject var viewer: ViewerState; let queue: [PhotoRecord]
    @State private var hover = false
    var body: some View {
        let ids = queue.map { $0.id }; let pos = PhotoNav.position(ids: ids, current: ed.current?.id)
        let canPrev = PhotoNav.target(ids: ids, current: ed.current?.id, delta: -1) != nil, canNext = PhotoNav.target(ids: ids, current: ed.current?.id, delta: 1) != nil
        HStack(spacing: 10) {
            Button { ed.navigate(-1, in: queue) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).disabled(!canPrev).help(L("Fotografia precedentă (←/↑)")).accessibilityLabel(L("Fotografia precedentă"))
            VStack(spacing: 1) {
                Text(ed.current.map { ($0.path as NSString).lastPathComponent } ?? "").font(Theme.f(11.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 5) {
                    if let p = pos { Text(LF("%@ din %@", p.index, p.total)).font(Theme.f(11)).foregroundColor(Theme.muted) }
                    if let c = ed.current, let why = ed.failedPhotos[c.id] { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.check).help(why); Text(L("Nu s-a putut procesa — poți continua")).font(Theme.f(10.5)).foregroundColor(Theme.check) }
                    else if ed.rendering || ed.afterImage == nil { ProgressView().controlSize(.mini); Text(L("Se încarcă…")).font(Theme.f(10.5)).foregroundColor(Theme.muted) }
                }
            }.frame(minWidth: 120)
            if !viewer.isFit { Button { viewer.setFit() } label: { Text(L("Potrivit")).font(Theme.f(10.5, weight: .semibold)) }.buttonStyle(.plain).help(L("Revino la «Potrivit»")) }
            Button { ed.navigate(1, in: queue) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).disabled(!canNext).help(L("Fotografia următoare (→/↓)")).accessibilityLabel(L("Fotografia următoare"))
        }
        .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.black.opacity(hover ? 0.7 : 0.4))).foregroundColor(Theme.text).opacity(hover ? 1 : 0.7)
        .onHover { hover = $0 }.padding(.bottom, 14)
    }
}
