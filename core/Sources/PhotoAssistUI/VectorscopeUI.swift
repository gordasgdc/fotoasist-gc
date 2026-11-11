import SwiftUI
import PhotoCore
import AppKit
import PhotoResolve

/// Vectorscop: raster de densitate (matematica e în `PhotoAnalysis`) + grilă VECTORIALĂ desenată aici: cercuri 50%/100%, axe, centru, linia pielii (orientativă), ținte 75% cu etichete, sursa și domeniul măsurării.
/// Desenul nu calculează nimic despre imagine: pozițiile țintelor vin din `PhotoAnalysis.vectorscopePosition` (aceeași funcție ca densitatea).
func vectorscopeRasterImage(_ rgba: [UInt8]) -> NSImage? {
    let n = PhotoAnalysis.vectorscopeSize; guard rgba.count == n * n * 4, let p = CGDataProvider(data: Data(rgba) as CFData),
        let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: p, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: n, height: n))
}
struct VectorscopeView: View {
    let raster: NSImage?; var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                let side = min(g.size.width, g.size.height); let o = CGPoint(x: (g.size.width - side) / 2, y: (g.size.height - side) / 2)
                ZStack {
                    Rectangle().fill(Color(white: 0.06)).frame(width: side, height: side)
                    if let r = raster { Image(nsImage: r).resizable().interpolation(.none).frame(width: side, height: side).opacity(0.95) }
                    Canvas { ctx, size in
                        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
                        let c = pt(0.5, 0.5); let line = Color(white: 0.55).opacity(0.55)
                        for (rad, label) in [(0.5, "100%"), (0.25, "50%")] as [(CGFloat, String)] {
                            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rad * size.width, y: c.y - rad * size.height, width: 2 * rad * size.width, height: 2 * rad * size.height)), with: .color(line), style: StrokeStyle(lineWidth: 0.8, dash: rad == 0.25 ? [3, 3] : []))
                            if !compact { ctx.draw(Text(label).font(.system(size: 8)).foregroundColor(Color(white: 0.6)), at: CGPoint(x: c.x + rad * size.width * 0.7071 + 12, y: c.y - rad * size.height * 0.7071 - 2)) } }
                        var axes = Path(); axes.move(to: pt(0, 0.5)); axes.addLine(to: pt(1, 0.5)); axes.move(to: pt(0.5, 0)); axes.addLine(to: pt(0.5, 1)); ctx.stroke(axes, with: .color(line), lineWidth: 0.6)
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(.white.opacity(0.9)), lineWidth: 1)   // centru = neutru (Cb = Cr = 0)
                        let a = CGFloat(PhotoAnalysis.vectorscopeSkinAngleDegrees) * .pi / 180; var skin = Path(); skin.move(to: c); skin.addLine(to: CGPoint(x: c.x + 0.5 * size.width * cos(a), y: c.y - 0.5 * size.height * sin(a)))
                        ctx.stroke(skin, with: .color(Color(red: 0.95, green: 0.68, blue: 0.35)), style: StrokeStyle(lineWidth: 1.4))
                        if !compact { ctx.draw(Text(L("piele ~123°")).font(.system(size: 8, weight: .semibold)).foregroundColor(Color(red: 0.95, green: 0.68, blue: 0.35)), at: CGPoint(x: c.x + 0.43 * size.width * cos(a) - 18, y: c.y - 0.43 * size.height * sin(a) - 6)) }
                        for t in PhotoAnalysis.vectorscopeTargets {
                            let q = PhotoAnalysis.vectorscopePosition(r: t.r, g: t.g, b: t.b); let p = pt(CGFloat(q.x), CGFloat(q.y)); let col = Color(red: Double(t.r), green: Double(t.g), blue: Double(t.b)).opacity(0.95)
                            ctx.stroke(Path(CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(col), lineWidth: 1.4)
                            ctx.draw(Text(t.name).font(.system(size: compact ? 8 : 10, weight: .bold)).foregroundColor(.white), at: CGPoint(x: p.x + (q.x < 0.5 ? -12 : 12), y: p.y)) }
                    }.frame(width: side, height: side)
                }.frame(width: side, height: side).position(x: o.x + side / 2, y: o.y + side / 2)
            }.aspectRatio(1, contentMode: .fit)
            Text(L("Sursa: ") + PhotoAnalysis.vectorscopeDomain).font(Theme.f(10)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            if !compact { Text(L("Fiecare punct = pixeli din imaginea finală (densitate pe scară logaritmică). Țintele sunt bare de culoare la 75%; linia pielii e o referință orientativă, nu o țintă de culoare. Centrul = neutru.")).font(Theme.f(10)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
struct VectorscopeFloatView: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Toggle(L("Vectorscop"), isOn: $ed.showVectorscope).toggleStyle(.switch).controlSize(.small); Spacer(); UpdateChip(busy: ed.analysisBusy, at: ed.analysisUpdatedAt) }
            if ed.showVectorscope, let r = ed.analysisResult, !r.vectorscope.isEmpty { VectorscopeView(raster: vectorscopeRasterImage(r.vectorscope)).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { Spacer(); Text(ed.showVectorscope ? L("Se calculează…") : L("Pornește vectorscopul.")).font(Theme.f(12)).foregroundColor(Theme.muted); Spacer() }
            FloatFooter(kind: .vectorscope)
        }.padding(12).frame(minWidth: 220, minHeight: 240).background(Theme.panel).foregroundColor(Theme.text)
    }
}


/// RGB Parade: trei canale separate (R, G, B) alăturate, axa X = coloana imaginii finale, axa Y = valoarea codată sRGB 0…1 (liniar în cod, nu în lumină). Fără filtru high-pass.
struct ParadeView: View {
    let d: PhotoAnalysis.ParadeDensity
    private func img(_ ch: Int) -> Image {
        let r = PhotoAnalysis.paradeRaster(d, channel: ch); let n = d.columns, m = d.rows
        guard let p = CGDataProvider(data: Data(r) as CFData), let cg = CGImage(width: n, height: m, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: p, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return Image(systemName: "xmark") }
        return Image(decorative: cg, scale: 1)
    }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { ch in
                ZStack { Rectangle().fill(Color.black.opacity(0.45)); img(ch).resizable().interpolation(.none)
                    Canvas { ctx, size in for q in 0...4 { var g = Path(); let y = size.height * CGFloat(q) / 4; g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y)); ctx.stroke(g, with: .color(Color.white.opacity(q == 0 || q == 4 ? 0.35 : 0.14)), lineWidth: 0.5) } }
                }.overlay(alignment: .topLeading) { Text(["R", "G", "B"][ch]).font(Theme.f(10, weight: .bold)).foregroundColor([Color.red, .green, .blue][ch]).padding(3) }
            }
        }.accessibilityLabel(L("RGB Parade, imaginea finală sRGB codat, canalele R, G, B separate"))
    }
}

struct ParadeFloatView: View {
    @ObservedObject var ed: EditingModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Toggle(L("RGB Parade"), isOn: $ed.showParade).toggleStyle(.switch).controlSize(.small); Spacer(); UpdateChip(busy: ed.analysisBusy, at: ed.analysisUpdatedAt) }
            if ed.showParade, let r = ed.analysisResult, let d = r.parade { ParadeView(d: d).frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(L("Sursă: imaginea finală (sRGB codat după GDC DRT), eșantion ≤ 1400 px. Scală verticală: valoare codată 0…1 (sus = 1,0), densitate logaritmică.")).font(Theme.f(10.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            } else { Spacer(); Text(ed.showParade ? L("Se calculează…") : L("Pornește RGB Parade.")).font(Theme.f(12)).foregroundColor(Theme.muted); Spacer() }
            FloatFooter(kind: .parade)
        }.padding(12).frame(minWidth: 300, minHeight: 200).background(Theme.panel).foregroundColor(Theme.text)
    }
}
