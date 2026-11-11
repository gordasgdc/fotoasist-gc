import SwiftUI
import AppKit

/// Cursor UNITAR pentru uneltele care lucrează pe fotografie: prelevare (pipete), desenare (contur/elipsă/degrade), îndreptare. Pensula își păstrează indicatorul propriu (nu trece pe aici).
/// Mecanism: «cursor rects» AppKit pe suprafața fotografiei (nu `NSCursor.set()` din `onHover`, care e suprascris de AppKit): cursorul se aplică NUMAI în dreptunghiul imaginii și revine singur la ieșire, la anulare, la schimbarea uneltei,
/// la închiderea modului (view-ul dispare ⇒ dreptunghiul dispare) și nu rămâne peste inspector sau alte ferestre. Punctul de prelevare = originea cursorului (hotspot), în puncte (corect și pe Retina).
enum ToolCursor {
    case sample    // pipetă: reticul precis + pictogramă de pipetă; hotspot = centrul reticulului
    case draw      // contur / elipsă / degrade / îndreptare: reticul precis
    /// Dimensiunea imaginii cursorului (puncte) și hotspot-ul (identice pentru testul de precizie).
    static let size = NSSize(width: 32, height: 32)
    static let hotSpot = NSPoint(x: 16, y: 16)

    static let sampleCursor: NSCursor = NSCursor(image: image(withGlyph: true), hotSpot: hotSpot)
    static let drawCursor: NSCursor = NSCursor(image: image(withGlyph: false), hotSpot: hotSpot)
    var cursor: NSCursor { self == .sample ? Self.sampleCursor : Self.drawCursor }

    /// Desenat prin `drawingHandler` ⇒ se rasterizează la rezoluția ecranului (clar pe Retina), hotspot-ul rămâne în puncte.
    static func image(withGlyph: Bool) -> NSImage {
        NSImage(size: size, flipped: false) { _ in
            let c = hotSpot
            func cross(_ color: NSColor, _ lw: CGFloat) {
                color.setStroke(); let p = NSBezierPath(); p.lineWidth = lw; p.lineCapStyle = .butt
                for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {   // brațe cu gol central de 3 pt: se vede punctul exact
                    p.move(to: NSPoint(x: c.x + dx * 3, y: c.y + dy * 3)); p.line(to: NSPoint(x: c.x + dx * 11, y: c.y + dy * 11)) }
                p.stroke() }
            cross(NSColor.black.withAlphaComponent(0.85), 3.4); cross(NSColor.white, 1.4)   // contur negru + linie albă: vizibil pe orice fundal
            NSColor.black.withAlphaComponent(0.85).setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)).fill()
            NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - 0.7, y: c.y - 0.7, width: 1.4, height: 1.4)).fill()
            if withGlyph, let g = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .bold)) {
                let t = g.copy() as! NSImage; t.lockFocus(); NSColor.white.set(); NSRect(origin: .zero, size: t.size).fill(using: .sourceAtop); t.unlockFocus()
                t.draw(in: NSRect(x: 19, y: 19, width: 12, height: 12))   // sus-dreapta: nu acoperă punctul de prelevare
            }
            return true }
    }
}

/// Registrul uneltelor care cer un cursor. Cursor rects pe un view din `.background` NU sunt de încredere sub SwiftUI (view-ul de navigare al fotografiei, mai sus în ierarhie, le acoperă),
/// așa că cursorul se aplică EXPLICIT de `ViewerEvents` la fiecare mișcare a mouse-ului peste fotografie (și se restabilește la ieșire, la anulare, la schimbarea uneltei).
extension Notification.Name { static let gdcCancelTool = Notification.Name("gdcpa.cancelTool") }
@MainActor final class ToolCursorState {
    static let shared = ToolCursorState()
    private var claims: [ObjectIdentifier: ToolCursor] = [:]; private var order: [ObjectIdentifier] = []
    var onChange: (() -> Void)?
    var current: ToolCursor? { order.last.flatMap { claims[$0] } }
    func claim(_ owner: AnyObject, _ kind: ToolCursor) { let k = ObjectIdentifier(owner); if claims[k] == nil { order.append(k) }; claims[k] = kind; onChange?() }
    func release(_ owner: AnyObject) { release(ObjectIdentifier(owner)) }
    func release(_ k: ObjectIdentifier) { claims[k] = nil; order.removeAll { $0 == k }; onChange?() }
}

/// Aplică cursorul uneltei pe dreptunghiul ocupat de view (suprafața fotografiei). Nu primește evenimente (nu schimbă gesturile).
struct ToolCursorArea: NSViewRepresentable {
    let kind: ToolCursor
    func makeNSView(context: Context) -> CursorRectView { let v = CursorRectView(); v.kind = kind; return v }
    func updateNSView(_ v: CursorRectView, context: Context) { if v.kind != kind { v.kind = kind; v.window?.invalidateCursorRects(for: v); MainActor.assumeIsolated { ToolCursorState.shared.claim(v, kind) } } }
    static func dismantleNSView(_ v: CursorRectView, coordinator: ()) { let w = v.window; v.removeFromSuperview(); w?.invalidateCursorRects(for: v); w?.resetCursorRects() }
}
final class CursorRectView: NSView {
    var kind: ToolCursor = .draw
    override func resetCursorRects() { addCursorRect(bounds, cursor: kind.cursor) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // nu interceptează clicuri/glisări
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.invalidateCursorRects(for: self); if window != nil { MainActor.assumeIsolated { ToolCursorState.shared.claim(self, kind) } } else { MainActor.assumeIsolated { ToolCursorState.shared.release(self) } } }
    deinit { let me = ObjectIdentifier(self); DispatchQueue.main.async { MainActor.assumeIsolated { ToolCursorState.shared.release(me) } } }
    override func layout() { super.layout(); window?.invalidateCursorRects(for: self) }
}
extension View {
    /// Cursorul uneltei pe suprafața acestui view (vezi `ToolCursor`).
    func toolCursor(_ kind: ToolCursor) -> some View { background(ToolCursorArea(kind: kind)) }
}
