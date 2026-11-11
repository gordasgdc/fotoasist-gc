import SwiftUI
import AppKit
import PhotoCore

/// Marca FotoAsist GC — integrare de PREVIZUALIZARE a conceptului ales de proprietar (author-concept-01; planșa e reperul de proporții și ierarhie). NU e logo final și NU e iconul aplicației.
/// Simbolul se desenează din fișierul vectorial ORIGINAL (copie identică octet cu octet a `FotoAsist-GC_simbol.svg`, SHA în docs/IDENTITY.md), tintat monocrom (șablon): fără umbre, gradient sau efecte.
/// Logotipul = simbol + text în Avenir Next, cu geometria din `FotoAsist-GC_logotip-editabil.svg` (viewBox 110, linia de bază la 78, decalaj text 145, GC la 36/89). Fontul NU se înlocuiește: dacă Avenir Next lipsește, se afișează doar simbolul și se loghează.
/// Parametri măsurați pe planșă (nu din SVG, care nu specifică greutatea): greutate Bold, fără spațiere negativă — de CONFIRMAT de proprietar (SVG-ul ca atare se randează în Regular, vizibil mai subțire decât planșa).
public enum Brand {
    public static let productName = "FotoAsist GC", author = "Cristi Gordaș"
    /// Constantele tipografice ale logotipului (modificabile într-un singur loc).
    public enum Typo { static let wordmarkFont = "AvenirNext-Bold", gcFont = "AvenirNext-Bold"; static let wordmarkSize: CGFloat = 89, gcSize: CGFloat = 36, textOffset: CGFloat = 40, gcGap: CGFloat = 28, baseline: CGFloat = 83, tracking: CGFloat = 0 }
    public static var fontAvailable: Bool { NSFont(name: Typo.wordmarkFont, size: 12) != nil }
    private static var cached: NSImage?
    private static var heroCached: NSImage?
    /// Imaginea ilustrativă aprobată (automobil într-un laborator alb; derivat JPEG 1280 px din `FotoAsist-GC_hero-laborator-v1.png`). Folosită DOAR în starea de bun venit / bibliotecă fără fotografii.
    static func heroImage() -> NSImage? {
        if let c = heroCached { return c }
        let url = Bundle.main.url(forResource: "FotoAsist-GC_hero", withExtension: "jpg", subdirectory: "Brand") ?? Bundle.main.url(forResource: "FotoAsist-GC_hero", withExtension: "jpg")
            ?? ModuleBundle.optional?.url(forResource: "FotoAsist-GC_hero", withExtension: "jpg", subdirectory: "Brand")
        guard let u = url, let img = NSImage(contentsOf: u) else { DiagnosticLog.shared?.log(.warning, "brand", "hero.missing"); return nil }
        heroCached = img; return img
    }
    /// Imaginea șablon a simbolului din SVG-ul original (copiat în Resources/Brand).
    static func symbolImage() -> NSImage? {
        if let c = cached { return c }
        let url = Bundle.main.url(forResource: "FotoAsist-GC_simbol", withExtension: "svg", subdirectory: "Brand") ?? Bundle.main.url(forResource: "FotoAsist-GC_simbol", withExtension: "svg")
            ?? ModuleBundle.optional?.url(forResource: "FotoAsist-GC_simbol", withExtension: "svg", subdirectory: "Brand")
        guard let u = url, let img = NSImage(contentsOf: u) else { DiagnosticLog.shared?.log(.warning, "brand", "symbol.missing"); return nil }
        img.isTemplate = true; cached = img; return img
    }
}

/// Simbolul separat (cadru deschis + F), proporții păstrate (pătrat 110×110 în viewBox), monocrom.
public struct BrandSymbol: View {
    var size: CGFloat; var tint: Color
    public init(size: CGFloat, tint: Color) { self.size = size; self.tint = tint }
    public var body: some View {
        Group { if let i = Brand.symbolImage() { Image(nsImage: i).renderingMode(.template).resizable().interpolation(.high).aspectRatio(1, contentMode: .fit).foregroundColor(tint) } else { Color.clear } }
            .frame(width: size, height: size).accessibilityLabel(Brand.productName)
    }
}

/// Logotipul complet: simbol + „FotoAsist” + „GC” discret. `height` = înălțimea simbolului; restul scalează proporțional (u = height/110).
public struct BrandLockup: View {
    var height: CGFloat; var tint: Color; var showsGC: Bool
    public init(height: CGFloat, tint: Color, showsGC: Bool = true) { self.height = height; self.tint = tint; self.showsGC = showsGC }
    public var body: some View {
        let u = height / 110
        if Brand.fontAvailable {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                BrandSymbol(size: height, tint: tint).alignmentGuide(.firstTextBaseline) { _ in Brand.Typo.baseline * u }
                Spacer().frame(width: Brand.Typo.textOffset * u)
                Text("FotoAsist").font(.custom(Brand.Typo.wordmarkFont, size: Brand.Typo.wordmarkSize * u)).tracking(Brand.Typo.tracking * u).foregroundColor(tint).fixedSize()
                if showsGC { Spacer().frame(width: Brand.Typo.gcGap * u); Text("GC").font(.custom(Brand.Typo.gcFont, size: Brand.Typo.gcSize * u)).foregroundColor(tint).fixedSize() }
            }.accessibilityElement(children: .ignore).accessibilityLabel(Brand.productName)
        } else {
            BrandSymbol(size: height, tint: tint)   // fără înlocuire tăcută a fontului: doar simbolul (se loghează o dată)
                .onAppear { DiagnosticLog.shared?.log(.warning, "brand", "font.missing", Brand.Typo.wordmarkFont) }
        }
    }
}

/// Compoziție de previzualizare a integrării pe suprafață luminoasă SAU întunecată (aplicația are doar tema întunecată): antet + bloc „Despre”. Doar pentru capturi; nu face parte din interfață.
public struct BrandIntegrationPreview: View {
    var light: Bool
    public init(light: Bool) { self.light = light }
    public var body: some View {
        let bg = light ? Color(.sRGB, red: 0.953, green: 0.945, blue: 0.925, opacity: 1) : Theme.app
        let bar = light ? Color(.sRGB, red: 0.925, green: 0.918, blue: 0.898, opacity: 1) : Theme.toolbar
        let ink = light ? Color(.sRGB, red: 0.125, green: 0.149, blue: 0.157, opacity: 1) : Theme.text
        let sub = light ? Color(.sRGB, red: 0.40, green: 0.42, blue: 0.43, opacity: 1) : Theme.muted
        VStack(spacing: 0) {
            HStack { VStack(alignment: .leading, spacing: 3) { BrandLockup(height: 26, tint: ink); Text(L("Procesare locală · originalele rămân nemodificate")).font(Theme.f(11)).foregroundColor(sub) }
                Spacer(); HStack(spacing: 18) { ForEach(["Import", L("Selecție"), L("Stil și ajustări"), L("Revizuire"), L("Export")], id: \.self) { Text($0).font(Theme.f(13)).foregroundColor(sub) } }; Spacer()
                BrandSymbol(size: 22, tint: ink) }.padding(.horizontal, 16).padding(.vertical, 10).background(bar)
            Divider().overlay(sub.opacity(0.3))
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Antet — simbolul separat apare unde nu încape logotipul complet")).font(Theme.f(11, weight: .semibold)).foregroundColor(sub)
                HStack(spacing: 28) { BrandSymbol(size: 28, tint: ink); BrandSymbol(size: 20, tint: ink); BrandSymbol(size: 16, tint: ink); Text("28 · 20 · 16 pt").font(Theme.f(11)).foregroundColor(sub) }
                Divider().overlay(sub.opacity(0.3))
                Text(L("Ecranul Despre")).font(Theme.f(11, weight: .semibold)).foregroundColor(sub)
                BrandLockup(height: 46, tint: ink)
                Text(LF("Versiune de dezvoltare · autor: %@", Brand.author)).font(Theme.f(12)).foregroundColor(sub)
                Text(L("Previzualizare de integrare a conceptului ales — NU e logo final și nu e iconul aplicației.")).font(Theme.f(11)).foregroundColor(sub)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }.background(bg).frame(width: 1100, height: 330)
    }
}


/// Indicator vizibil pentru intrările display-referred: NU sunt RAW și nu poartă date de scenă.
struct RenderedBadge: View {
    var compact = false
    var body: some View {
        Text(compact ? L("Redată · nu RAW") : L("Imagine redată · nu RAW")).font(Theme.f(compact ? 9.5 : 10.5, weight: .semibold)).lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 3).foregroundColor(Theme.accentInk).background(Capsule().fill(Theme.accentHi))
            .help(L("Intrare display-referred (PNG/JPEG/TIFF): nu e RAW și nu e lumină de scenă recuperată. Culoarea: ICC respectat sau sRGB asumat (demonstrație).")).accessibilityLabel(L("Imagine redată, nu RAW"))
    }
}
