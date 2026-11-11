import SwiftUI
import PhotoCore
import AppKit
import PhotoResolve

/// Panoul „Analiză”: instrumente de vizualizare (culoare falsă, tăieri, saturație, ton piele) și histogramă. NU sunt efecte: se afișează în locul fotografiei, doar în aplicație (modul «După»), și NU ajung niciodată în export. Fiecare arată domeniul în care măsoară.
struct AnalysisBox: View {
    @ObservedObject var ed: EditingModel; @ObservedObject private var fp: FloatingPanels
    init(ed: EditingModel) { self.ed = ed; fp = ed.floating }
    var body: some View {
        Box(title: L("Analiză (nu se exportă)"), panel: "analysis", summary: ed.analysisMode == .off ? nil : ed.analysisMode.label) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(AnalysisMode.allCases, id: \.rawValue) { m in
                    Button { ed.analysisMode = m } label: { Text(m.label).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85).frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle(active: ed.analysisMode == m)).disabled(ed.current == nil || ed.engine != .own)
                        .accessibilityAddTraits(ed.analysisMode == m ? .isSelected : [])
                }
            }
            if ed.analysisMode != .off {
                Text(ed.analysisMode.domain).font(Theme.f(11.5, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                if ed.analysisMode == .nrDifference {
                    Picker(L("Amplificare"), selection: $ed.nrDiffGain) { ForEach([1.0, 2.0, 4.0, 8.0, 16.0], id: \.self) { Text("×" + String(format: "%g", $0)).tag($0) } }.pickerStyle(.segmented).font(Theme.f(11))
                }
                Text(ed.analysisMode.explanation).font(Theme.f(11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                if ed.compare != .after { Text(L("Se vede în modul «După».")).font(Theme.f(11)).foregroundColor(Theme.check) }
                if let r = ed.analysisResult, r.mode == ed.analysisMode {
                    ForEach(Array(r.legend.enumerated()), id: \.offset) { _, it in
                        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(Color(red: Double(it.r) / 255, green: Double(it.g) / 255, blue: Double(it.b) / 255)).frame(width: Theme.px(14), height: Theme.px(14)); Text(it.text).font(Theme.f(11)).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 4); Text(String(format: "%.1f%%", it.fraction * 100)).font(Theme.f(11, design: .monospaced)).foregroundColor(Theme.muted) }
                    }
                    ForEach(r.notes, id: \.self) { Text($0).font(Theme.f(10.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                    Text(r.sampled).font(Theme.f(10.5)).foregroundColor(Theme.faint)
                } else if ed.analysisBusy { HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L("Se calculează…")).font(Theme.f(11)).foregroundColor(Theme.muted) } }
            }
            HStack(spacing: 6) {
                Button { fp.toggle(.analysis) } label: { Label(fp.isDetached(.analysis) ? L("Revino în fotografie") : L("Analiză în fereastră"), systemImage: "macwindow.on.rectangle").lineLimit(2).minimumScaleFactor(0.85) }.buttonStyle(SoftButtonStyle(active: fp.isDetached(.analysis))).disabled(ed.analysisMode == .off && !fp.isDetached(.analysis)).help(L("Fereastră flotantă opțională: fotografia principală rămâne normală"))
                Button { fp.toggle(.histogram); if fp.isDetached(.histogram) { ed.showHistogram = true } } label: { Label(fp.isDetached(.histogram) ? L("Histogramă în inspector") : L("Histogramă în fereastră"), systemImage: "macwindow.on.rectangle").lineLimit(2).minimumScaleFactor(0.85) }.buttonStyle(SoftButtonStyle(active: fp.isDetached(.histogram)))
            }
            HStack(spacing: 6) {
                Button { fp.openAnalysisWindow(AnalysisViewSpec(mode: ed.analysisMode == .off ? .clipping : ed.analysisMode, nrGain: ed.nrDiffGain)) } label: { Label(L("Deschide într-o fereastră nouă"), systemImage: "macwindow.badge.plus").lineLimit(1) }.controlSize(.small).disabled(ed.current == nil)
                Button { fp.openAnalysisDashboard() } label: { Label(L("Tablou de analize"), systemImage: "square.grid.2x2").lineLimit(1) }.controlSize(.small).disabled(ed.current == nil)
            }
            Toggle(L("Histogramă (imaginea finală)"), isOn: $ed.showHistogram).toggleStyle(.switch).controlSize(.small).font(Theme.f(12.5)).disabled(ed.current == nil || ed.engine != .own)
            if ed.showHistogram, !fp.isDetached(.histogram), let r = ed.analysisResult { HistogramView(h: r.histogram, scale: ed.histogramScale).frame(height: Theme.px(70)); Text(L("RGB și luminanță pe imaginea finală (sRGB după GDC DRT).")).font(Theme.f(10.5)).foregroundColor(Theme.faint) }
            Toggle(L("Vectorscop (imaginea finală)"), isOn: $ed.showVectorscope).toggleStyle(.switch).controlSize(.small).font(Theme.f(12.5)).disabled(ed.current == nil || ed.engine != .own)
            if ed.showVectorscope {
                Button { fp.toggle(.vectorscope); ed.showVectorscope = true } label: { Label(fp.isDetached(.vectorscope) ? L("Vectorscop în inspector") : L("Vectorscop în fereastră"), systemImage: "macwindow.on.rectangle").lineLimit(2).minimumScaleFactor(0.85) }.buttonStyle(SoftButtonStyle())
                if !fp.isDetached(.vectorscope) { if let r = ed.analysisResult, !r.vectorscope.isEmpty { VectorscopeView(raster: vectorscopeRasterImage(r.vectorscope), compact: true).frame(maxWidth: Theme.px(260)).frame(height: Theme.px(290)) } else if ed.analysisBusy { HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L("Se calculează…")).font(Theme.f(11)).foregroundColor(Theme.muted) } } }
                else { Text(L("Vectorscopul e în fereastră separată (închide-o sau apasă «Vectorscop în inspector» ca să revii aici).")).font(Theme.f(10.5)).foregroundColor(Theme.faint) }
            }
            Toggle(L("RGB Parade (imaginea finală)"), isOn: $ed.showParade).toggleStyle(.switch).controlSize(.small).font(Theme.f(12.5)).disabled(ed.current == nil)
            if ed.showParade {
                Button { fp.toggle(.parade); ed.showParade = true } label: { Label(fp.isDetached(.parade) ? L("Parade în inspector") : L("Parade în fereastră"), systemImage: "macwindow") }.controlSize(.small)
                if !fp.isDetached(.parade), let d = ed.analysisResult?.parade { ParadeView(d: d).frame(height: Theme.px(110)) }
            }
            Text(L("Analiza nu modifică fotografia și nu intră în export; punerea ei în loc de imagine e doar o vedere de lucru.")).font(Theme.f(10.5)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
        }
    }
}

func vectorscopeImage(_ rgba: [UInt8]) -> NSImage? {
    let n = PhotoAnalysis.vectorscopeSize; guard rgba.count == n * n * 4, let p = CGDataProvider(data: Data(rgba) as CFData), let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: p, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: n, height: n))
}

/// Scara verticală a histogramei (etichetată în interfață): liniară (implicit, valorile reale), rădăcină pătrată sau logaritmică — doar afișare; datele nu se schimbă.
public enum HistogramScale: String, CaseIterable, Identifiable {
    case linear, sqrt, log
    public var id: String { rawValue }
    public var label: String { switch self { case .linear: return L("Liniară"); case .sqrt: return L("Rădăcină"); case .log: return L("Logaritmică") } }
    func map(_ v: Float, peak: Float) -> CGFloat {
        let x = max(0, v) / max(peak, 1e-9)
        switch self { case .linear: return CGFloat(min(1, x)); case .sqrt: return CGFloat(min(1, x.squareRoot())); case .log: return CGFloat(min(1, log1p(x * 999) / log1p(999))) }
    }
}

struct HistogramView: View {
    let h: AnalysisHistogram; var scale: HistogramScale = .linear
    var body: some View {
        Canvas { ctx, size in
            let peak = max(1e-9, (h.r + h.g + h.b).max() ?? 1)
            for q in 1..<4 { var g = Path(); let x = size.width * CGFloat(q) / 4; g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: size.height)); ctx.stroke(g, with: .color(Color.white.opacity(0.07)), lineWidth: 1) }
            for q in 1..<3 { var g = Path(); let y = size.height * CGFloat(q) / 3; g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y)); ctx.stroke(g, with: .color(Color.white.opacity(0.05)), lineWidth: 1) }
            func path(_ v: [Float], closed: Bool) -> Path {
                var p = Path(); let n = v.count; guard n > 1 else { return p }
                if closed { p.move(to: CGPoint(x: 0, y: size.height)) }
                for (k, x) in v.enumerated() { let pt = CGPoint(x: size.width * (CGFloat(k) + 0.5) / CGFloat(n), y: size.height * (1 - scale.map(x, peak: peak) * 0.96)); if k == 0 && !closed { p.move(to: pt) } else { p.addLine(to: pt) } }
                if closed { p.addLine(to: CGPoint(x: size.width, y: size.height)); p.closeSubpath() }
                return p
            }
            let cols: [(([Float]), Color)] = [(h.r, Color(red: 1, green: 0.33, blue: 0.33)), (h.g, Color(red: 0.3, green: 0.9, blue: 0.4)), (h.b, Color(red: 0.35, green: 0.6, blue: 1))]
            for (v, c) in cols { ctx.fill(path(v, closed: true), with: .color(c.opacity(0.16))) }
            for (v, c) in cols { ctx.stroke(path(v, closed: false), with: .color(c.opacity(0.95)), lineWidth: 1.2) }
            ctx.stroke(path(h.luma, closed: false), with: .color(Color.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }.background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35))).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
        .accessibilityLabel(LF("Histogramă RGB și luminanță, imaginea finală sRGB, scară verticală %@", scale.label))
    }
}

/// Imaginea de analiză în locul fotografiei (aceeași potrivire ca a canvasului), cu etichetă clară că NU e fotografia.
struct AnalysisCanvas: View {
    let image: NSImage; let label: String; let rect: CGRect
    var body: some View {
        ZStack {
            Image(nsImage: image).resizable().interpolation(.none).frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        }.overlay(alignment: .topLeading) {
            Text(L("ANALIZĂ · ") + label + L(" · nu e fotografia, nu se exportă")).font(Theme.f(11, weight: .semibold)).foregroundColor(Theme.accentInk).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Theme.accentHi)).padding(14).allowsHitTesting(false)
        }.allowsHitTesting(false)
    }
}

extension AnalysisResult {
    /// RGB 8 biți → imagine afișabilă.
    func makeImage() -> NSImage? {
        guard !rgb8.isEmpty, width > 0, height > 0, rgb8.count == width * height * 3 else { return nil }
        var px = [UInt8](repeating: 255, count: width * height * 4); for i in 0..<(width * height) { px[4 * i] = rgb8[3 * i]; px[4 * i + 1] = rgb8[3 * i + 1]; px[4 * i + 2] = rgb8[3 * i + 2] }
        guard let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }
}
