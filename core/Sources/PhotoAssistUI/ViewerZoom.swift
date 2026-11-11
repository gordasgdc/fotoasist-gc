import SwiftUI
import PhotoCore
import AppKit

/// Navigarea fotografiei: zoom progresiv pe cursor (rotița mouse), deplasare (Space + tragere sau butonul din mijloc), Potrivit / 100%. O SINGURĂ vedere pentru toate comparațiile și pentru editarea măștilor (nu există un al doilea editor la 100%).
/// Unități: `scale` = pixeli FIZICI de ecran pe pixel al imaginii cu rezoluție plină (1 = 100%: un pixel al imaginii la un pixel fizic al ecranului). Imaginea e ancorată prin centrul ei (`offset`, în puncte, față de centrul vederii); geometria măștilor rămâne în coordonate normalizate ale fotografiei.
public final class ViewerState: ObservableObject {
    public static let maxScale: CGFloat = 4          // 400%
    public static let margin: CGFloat = 10           // spațiu în jurul imaginii la „Potrivit”
    @Published public private(set) var isFit = true
    @Published public private(set) var custom: CGFloat = 1
    @Published public private(set) var offset: CGSize = .zero
    @Published public var canvasSize: CGSize = .zero
    /// Un punct în coordonatele locale ale unui strat de imagine (originea = colțul imaginii `r`, în spațiul pânzei) cade în PÂNZA vizibilă? La 100% imaginea depășește pânza, iar stratul ei transparent prinde clicuri și în afara pânzei (bara de file, instrumente): gesturile de plasare trebuie să le ignore.
    public func canvasContains(_ local: CGPoint, in r: CGRect) -> Bool { canvasContains(CGPoint(x: r.minX + local.x, y: r.minY + local.y)) }
    /// Punct în coordonatele PÂNZEI (originea = colțul pânzei).
    public func canvasContains(_ p: CGPoint) -> Bool { p.x >= 0 && p.y >= 0 && p.x <= canvasSize.width && p.y <= canvasSize.height }
    /// Poarta UNICĂ a gesturilor de plasare/trasare pe fotografie: în pânza vizibilă și nu în timpul deplasării (Space+tragere / pan). Barele și inspectorul stau peste pânză (zIndex), deci nu mai ajung la straturile de editare.
    public var placementAllowed: Bool { !spaceDown && !panning }
    public func accepts(_ local: CGPoint, in r: CGRect) -> Bool { placementAllowed && canvasContains(local, in: r) }
    public func accepts(canvasPoint p: CGPoint) -> Bool { placementAllowed && canvasContains(p) }
    /// Dimensiunea imaginii cu rezoluție plină în pixeli (estimată din previzualizare până se încarcă rezultatul plin).
    @Published public var fullSize: CGSize = .zero
    @Published public var spaceDown = false
    /// Poziția separatorului «Împărțit» ca fracție a LĂȚIMII IMAGINII (0…1); doar vedere, nu intră în reglaje sau export.
    @Published public var splitFraction: CGFloat = 0.5
    @Published public var panning = false
    public var backing: CGFloat = NSScreen.main?.backingScaleFactor ?? 2

    public init() {}
    public var fitScale: CGFloat {
        guard fullSize.width > 0, fullSize.height > 0, canvasSize.width > 0 else { return 1 }
        return min((canvasSize.width - 2 * Self.margin) * backing / fullSize.width, (canvasSize.height - 2 * Self.margin) * backing / fullSize.height)
    }
    public var scale: CGFloat { isFit ? fitScale : custom }
    public var percent: Int { Int((scale * 100).rounded()) }
    /// Cât din rezoluția plină se vede efectiv: peste ~½ previzualizarea (jumătate de rezoluție) nu mai ajunge.
    public var wantsFullResolution: Bool { scale > 0.5 }
    /// Dreptunghiul imaginii în coordonatele vederii (puncte, origine sus-stânga). La 100% se aliniază la pixelii fizici.
    public func imageRect() -> CGRect {
        let w = fullSize.width * scale / backing, h = fullSize.height * scale / backing
        var cx = canvasSize.width / 2 + offset.width, cy = canvasSize.height / 2 + offset.height
        if abs(scale - 1) < 1e-6 { cx = (cx * backing).rounded() / backing; cy = (cy * backing).rounded() / backing }
        var r = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        if abs(scale - 1) < 1e-6 { r.origin.x = (r.origin.x * backing).rounded() / backing; r.origin.y = (r.origin.y * backing).rounded() / backing }
        return r
    }
    /// Limite: imaginea nu iese din zona de lucru (marginile ei nu trec de marginea vederii); pe o axă mai mică decât vederea rămâne centrată.
    private func clamped(_ o: CGSize, scale s: CGFloat) -> CGSize {
        let w = fullSize.width * s / backing, h = fullSize.height * s / backing; let lx = max(0, (w - (canvasSize.width - 2 * Self.margin)) / 2), ly = max(0, (h - (canvasSize.height - 2 * Self.margin)) / 2)
        return CGSize(width: min(lx, max(-lx, o.width)), height: min(ly, max(-ly, o.height)))
    }
    /// Arată un punct normalizat al fotografiei la scara dată (lupă pe zonă), centrat în vedere.
    public func focus(on n: CGPoint, scale s: CGFloat) {
        guard canvasSize.width > 0 else { return }; let new = min(Self.maxScale, max(fitScale, s)); if new <= fitScale + 1e-6 { setFit(); return }
        let w = fullSize.width * new / backing, h = fullSize.height * new / backing
        isFit = false; custom = new; offset = clamped(CGSize(width: -(n.x - 0.5) * w, height: -(n.y - 0.5) * h), scale: new)
    }
    public func setFit() { isFit = true; offset = .zero }
    /// Zoom fix al fotografiei anterioare, aplicat o singură dată când noua imagine își cunoaște dimensiunea (Potrivit rămâne Potrivit; zoomul fix se păstrează, cu deplasarea recentrată și limitată).
    public var carriedZoom: CGFloat?
    public func applyCarriedZoom() { guard let z = carriedZoom, fullSize.width > 0, canvasSize.width > 0 else { return }; carriedZoom = nil; setScale(z) }
    /// 100% (un pixel al imaginii la un pixel fizic), în jurul unui punct al vederii (implicit centrul).
    public func set100(around p: CGPoint? = nil) { setScale(1, around: p) }
    public func setScale(_ s: CGFloat, around p: CGPoint? = nil) {
        guard canvasSize.width > 0 else { return }
        let old = scale; let new = min(Self.maxScale, max(fitScale, s)); if new <= fitScale + 1e-6 { setFit(); return }
        let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2); let q = p ?? c; let f = new / old
        let v = CGSize(width: q.x - (c.x + offset.width), height: q.y - (c.y + offset.height))                // vectorul centru-imagine → cursor
        let target = CGSize(width: q.x - c.x - v.width * f, height: q.y - c.y - v.height * f)                // punctul din imagine de sub cursor rămâne sub cursor
        isFit = false; custom = new; offset = clamped(target, scale: new)
    }
    /// Zoom multiplicativ pe cursor (progresiv, fără salturi).
    public func zoom(by factor: CGFloat, around p: CGPoint) { setScale(scale * factor, around: p) }
    public func pan(by d: CGSize) { guard !isFit else { return }; offset = clamped(CGSize(width: offset.width + d.width, height: offset.height + d.height), scale: custom) }
    /// După o schimbare a mărimii vederii sau a imaginii: păstrează starea în limite.
    public func revalidate() { if !isFit { if custom <= fitScale + 1e-6 { setFit() } else { offset = clamped(offset, scale: custom) } } }
    /// Partea din fotografie vizibilă în vedere, normalizată 0…1 (pentru navigator).
    public var visibleNormalized: CGRect {
        let r = imageRect(); guard r.width > 0, r.height > 0, canvasSize.width > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let x0 = max(0, -r.minX / r.width), y0 = max(0, -r.minY / r.height), x1 = min(1, (canvasSize.width - r.minX) / r.width), y1 = min(1, (canvasSize.height - r.minY) / r.height)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
    /// Punct normalizat al fotografiei (0…1) sub un punct al vederii.
    public func normalized(_ p: CGPoint) -> CGPoint { let r = imageRect(); return CGPoint(x: (p.x - r.minX) / r.width, y: (p.y - r.minY) / r.height) }
}

/// Prinde evenimentele de navigare DOAR când cursorul e deasupra vederii fotografiei (restul — inspector, liste — derulează normal): rotița = zoom pe cursor, trackpad: pinch = zoom, două degete = deplasare,
/// Space + tragere sau butonul din mijloc = deplasare (evenimentele sunt consumate: masca nu se mută și nu se pictează). Space nu e interceptat cât se scrie într-un câmp de text.
struct ViewerEvents: NSViewRepresentable {
    let v: ViewerState
    func makeNSView(context: Context) -> NSView { let n = TrackingView(); n.v = v; return n }
    func updateNSView(_ nsView: NSView, context: Context) { (nsView as? TrackingView)?.v = v }
    final class TrackingView: NSView {
        var v: ViewerState?; private var monitor: Any?; private var dragging = false; private var cursorApplied = false
        override var isFlipped: Bool { true }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window != nil { install() } else { remove() } }
        deinit { remove() }
        private func remove() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }
        private func inside(_ e: NSEvent) -> CGPoint? { guard let w = window, e.window === w else { return nil }; let p = convert(e.locationInWindow, from: nil); return bounds.contains(p) ? p : nil }
        private var textEditing: Bool { window?.firstResponder is NSTextView }
        private func install() {
            remove(); window?.acceptsMouseMovedEvents = true
            MainActor.assumeIsolated { ToolCursorState.shared.onChange = { [weak self] in self?.refreshToolCursor() } }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .scrollWheel, .magnify, .keyDown, .keyUp, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp]) { [weak self] e in self?.handle(e) ?? e }
        }
        /// Aplică cursorul uneltei active doar peste fotografie (nu peste inspector, bare sau alte ferestre) și îl restabilește la ieșire / anulare / schimbarea uneltei.
        private func refreshToolCursor() {
            guard let w = window else { return }
            let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            let kind = MainActor.assumeIsolated { ToolCursorState.shared.current }
            let want: ToolCursor? = (bounds.contains(p) && w.isKeyWindow && !(v?.spaceDown ?? false) && !(v?.panning ?? false)) ? kind : nil
            DispatchQueue.main.async { [weak self] in   // după actualizarea cursor-rect-urilor AppKit, care altfel suprascriu
                guard let self = self else { return }
                if let k = want { k.cursor.set(); self.cursorApplied = true }
                else if self.cursorApplied { NSCursor.arrow.set(); self.cursorApplied = false }
                #if GDC_PA_DEV_OPEN   /* sondă de diagnostic doar în build-ul de dezvoltare; absentă din producție */
                if let path = ProcessInfo.processInfo.environment["GDC_PA_CURSOR_PROBE"] {   // doar diagnostic de dezvoltare
                    let name = want == nil ? "none" : (want == .sample ? "sample" : "draw"); let ok = want.map { NSCursor.current === $0.cursor } ?? (NSCursor.current === NSCursor.arrow)
                    let line = "\(Date().timeIntervalSince1970) want=\(name) applied=\(ok) inside=\(self.bounds.contains(p)) pt=\(Int(p.x)),\(Int(p.y)) scale=\(Double(self.v?.scale ?? 0))\n"
                    if let h = FileHandle(forWritingAtPath: path) ?? { FileManager.default.createFile(atPath: path, contents: nil); return FileHandle(forWritingAtPath: path) }() { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
                }
                #endif
            }
        }
        private func handle(_ e: NSEvent) -> NSEvent? {
            guard let v = v else { return e }
            switch e.type {
            case .mouseMoved: refreshToolCursor(); return e
            case .scrollWheel:
                guard let p = inside(e) else { return e }
                let dy = e.isDirectionInvertedFromDevice ? -e.scrollingDeltaY : e.scrollingDeltaY
                if e.hasPreciseScrollingDeltas {   // trackpad: două degete = deplasare (cu ⌘/⌃ = zoom)
                    if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) { v.zoom(by: exp(0.01 * dy), around: p) }
                    else { v.pan(by: CGSize(width: e.scrollingDeltaX, height: e.scrollingDeltaY)) }
                } else { v.zoom(by: exp(0.09 * max(-8, min(8, dy))), around: p) }   // rotița: ~9% pe treaptă
                return nil
            case .magnify:
                guard let p = inside(e) else { return e }; v.zoom(by: 1 + e.magnification, around: p); return nil
            case .keyDown:
                if e.keyCode == 53, MainActor.assumeIsolated({ ToolCursorState.shared.current != nil }) { NotificationCenter.default.post(name: .gdcCancelTool, object: nil); return nil }
                guard e.keyCode == 49, !e.isARepeat, !textEditing, let w = window, w.isKeyWindow else { return e }
                let p = convert(w.mouseLocationOutsideOfEventStream, from: nil); guard bounds.contains(p) else { return e }
                v.spaceDown = true; NSCursor.openHand.set(); return nil
            case .keyUp:
                if e.keyCode == 49 && v.spaceDown { v.spaceDown = false; NSCursor.arrow.set(); return nil }; return e
            case .leftMouseDown:
                guard v.spaceDown, inside(e) != nil else { return e }; dragging = true; v.panning = true; NSCursor.closedHand.set(); return nil
            case .otherMouseDown:
                guard inside(e) != nil else { return e }; dragging = true; v.panning = true; NSCursor.closedHand.set(); return nil
            case .leftMouseDragged, .otherMouseDragged:
                guard dragging else { return e }; v.pan(by: CGSize(width: e.deltaX, height: e.deltaY)); return nil
            case .leftMouseUp, .otherMouseUp:
                guard dragging else { return e }; dragging = false; v.panning = false; (v.spaceDown ? NSCursor.openHand : NSCursor.arrow).set(); return nil
            default: return e
            }
        }
    }
}

/// Vederea comună a fotografiei: același canvas pentru Bază / După / Împărțit / Din Resolve, cu zoom și deplasare; imaginea cu rezoluție plină se folosește când zoomul o cere (încărcare la cerere, stare vizibilă).
struct ZoomableCanvas<Overlay: View>: View {
    @ObservedObject var ed: EditingModel; @ObservedObject var v: ViewerState
    @ViewBuilder let overlay: (CGRect) -> Overlay
    var body: some View {
        GeometryReader { g in
            let r = v.imageRect()
            ZStack {
                Theme.canvas
                if v.fullSize.width > 0 {
                    switch ed.compare {
                    case .base: layer(ed.viewBefore(v), r)
                    case .after: layer(ed.viewAfter(v), r)
                    case .resolve: layer(ed.resolveResultImage, r)
                    case .split:
                        let sx = min(max(r.minX + v.splitFraction * r.width, 0), g.size.width)
                        ZStack { layer(ed.viewAfter(v), r); layer(ed.viewBefore(v), r).mask(HStack(spacing: 0) { Rectangle().frame(width: sx); Spacer(minLength: 0) }) }
                    case .camera: EmptyView()
                    }
                    overlay(r)
                    if ed.compare == .split { SplitHandle(v: v, r: r, canvasWidth: g.size.width, height: g.size.height) }
                }
                if ed.afterImage == nil {
                    if let c = ed.current, let why = ed.failedPhotos[c.id], !ed.rendering { VStack(spacing: 8) { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.check).font(.system(size: 22)); Text(L("Fotografia nu s-a putut procesa")).font(Theme.f(12, weight: .semibold)); Text(why).font(Theme.f(11)).foregroundColor(Theme.muted).lineLimit(3).multilineTextAlignment(.center).frame(maxWidth: 360) } }
                    else { VStack(spacing: 8) { ProgressView(); Text(ed.rendering ? L("Se pregătește imaginea…") : L("Nicio imagine încă")).font(Theme.f(12)).foregroundColor(Theme.muted) } } }
                statusChip
                if !v.isFit, v.fullSize.width > 0, let thumb = ed.afterImage { Navigator(v: v, image: thumb) }
            }
            .frame(width: g.size.width, height: g.size.height).clipped()
            .coordinateSpace(name: "splitCanvas")
            .background(ViewerEvents(v: v))
            .onAppear { v.canvasSize = g.size }.onChange(of: g.size) { s in v.canvasSize = s; v.revalidate() }
        }
    }
    @ViewBuilder func layer(_ img: NSImage?, _ r: CGRect) -> some View {
        if let img = img { Image(nsImage: img).resizable().interpolation(v.scale >= 1 ? .none : .high).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY) }
    }
    /// Starea vederii: procent, sursa (previzualizare / rezoluție plină) și încărcarea la cerere.
    var statusChip: some View {
        VStack { Spacer(); HStack { Spacer(); HStack(spacing: 6) {
            if ed.fullResolutionBusy { ProgressView().controlSize(.mini) }
            Text(chipText).font(Theme.f(11, weight: .semibold)).foregroundColor(Theme.text)
        }.padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(Color.black.opacity(0.55))).padding(12) } }.allowsHitTesting(false)
    }
    var chipText: String {
        let p = v.isFit ? LF("Potrivit · %@%", v.percent) : "\(v.percent)%"
        if v.wantsFullResolution && ed.compare != .resolve { return p + " · " + (ed.fullResolutionIsCurrent ? L("rezoluție plină") : (ed.fullResolutionBusy ? L("se încarcă rezoluția plină…") : L("previzualizare mărită"))) }
        if ed.previewSimplified { return p + L(" · previzualizare SIMPLIFICATĂ (fără reducere de zgomot) · se rafinează la eliberare") }
        return p + (ed.refining ? L(" · se rafinează…") : L(" · rezultat final gata"))
    }
}

/// Separatorul mobil Înainte/După: bară + mâner vizibil, zonă de prindere de 28 pt, cursor ↔, dublu-click = 50%. Se mișcă DOAR fracția `splitFraction` (nu mută fotografia, nu editează masca); fracția e relativă la imagine, deci rămâne aliniată la același zoom/deplasare.
struct SplitHandle: View {
    @ObservedObject var v: ViewerState; let r: CGRect; let canvasWidth: CGFloat; let height: CGFloat
    var body: some View {
        let x = min(max(r.minX + v.splitFraction * r.width, 0), canvasWidth)
        ZStack {
            Rectangle().fill(Color.white.opacity(0.85)).frame(width: 2, height: height).shadow(color: .black.opacity(0.5), radius: 1)
            ZStack { Circle().fill(Theme.accent).overlay(Circle().stroke(Color.white, lineWidth: 2)); Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .bold)).foregroundColor(.white) }.frame(width: 30, height: 30).shadow(radius: 2)
            Rectangle().fill(Color.clear).frame(width: 28, height: height).contentShape(Rectangle())
                .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("splitCanvas")).onChanged { d in
                    guard r.width > 0 else { return }; v.splitFraction = min(1, max(0, (d.location.x - r.minX) / r.width)) })
                .simultaneousGesture(TapGesture(count: 2).onEnded { v.splitFraction = 0.5 })
        }.frame(width: 28, height: height).position(x: x, y: height / 2)
            .help(L("Trage pentru a compara aceeași zonă; dublu-click = 50%"))
            .accessibilityLabel(L("Separator Înainte/După")).accessibilityValue("\(Int((v.splitFraction * 100).rounded()))%")
    }
}

/// Navigator: miniatura întregii fotografii cu dreptunghiul zonei vizibile când imaginea principală e mărită. Click/tragere = mută vederea (aceeași stare ca deplasarea); doar vedere, nu intră în export.
struct Navigator: View {
    @ObservedObject var v: ViewerState; let image: NSImage
    var body: some View {
        let ar = max(0.2, v.fullSize.width / max(1, v.fullSize.height)); let w: CGFloat = ar >= 1 ? 150 : 150 * ar, h: CGFloat = ar >= 1 ? 150 / ar : 150
        VStack { HStack { ZStack(alignment: .topLeading) {
            Image(nsImage: image).resizable().frame(width: w, height: h)
            let vis = v.visibleNormalized
            Rectangle().stroke(Theme.accent, lineWidth: 2).background(Theme.accent.opacity(0.12)).frame(width: max(3, vis.width * w), height: max(3, vis.height * h)).offset(x: vis.minX * w, y: vis.minY * h)
        }.frame(width: w, height: h).overlay(Rectangle().stroke(Color.black.opacity(0.6), lineWidth: 1)).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { d in v.focus(on: CGPoint(x: min(1, max(0, d.location.x / w)), y: min(1, max(0, d.location.y / h))), scale: v.scale) })
        .help(L("Navigator: trage pentru a muta zona vizibilă")).padding(12); Spacer() }; Spacer() }
    }
}
