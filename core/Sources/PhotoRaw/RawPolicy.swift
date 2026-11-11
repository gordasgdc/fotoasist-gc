import Foundation

// Politici PROVIZORII de decodare (2026-10-21), explicite și raportate. Nimic nu elimină informație din fișierul original: decuparea e un parametru, nu o ștergere.
// Dovezi și limite: docs/COLOR_AND_OUTPUT_CONTRACT.md §„Nivel alb” și §„Decupare”.

/// Cum se alege nivelul alb (valoarea care devine 1.0 în scala senzorului). Implicit: valoarea declarată de producător, citită de LibRaw (reproductibil, comparabil cu CoreImage/Resolve).
/// NU se înlocuiește automat cu maximul histogramei: acesta e tăierea ADC, nu un nivel de referință.
public enum WhiteLevelSource: Equatable, Codable { case vendorViaLibRaw, explicit(Int) }

public struct WhiteLevelPlan: Equatable {
    public var black: Int                 // nivel de negru al FIȘIERULUI (variază cu ISO/mod: 6D II 512 la ISO 100, 2048 la ISO 2000)
    public var white: Int                 // valoarea care devine 1.0
    public var vendorWhite: Int           // `maximum` LibRaw (6D II: 14558 = SpecularWhiteLevel Canon; NormalWhiteLevel = 13235)
    public var adcMax: Int                // 2^biți − 1 (6D II: 16383)
    public var source: WhiteLevelSource
    /// Cât din domeniul liniar măsurat rămâne deasupra lui `white` (în stopuri) până la tăierea ADC: informația pe care `clip_white` o aruncă.
    public var headroomStops: Double { white > black && adcMax > white ? log2(Double(adcMax - black) / Double(white - black)) : 0 }
    public var range: Double { Double(white - black) }

    public static func plan(black: Int, vendorWhite: Int, adcMax: Int, source: WhiteLevelSource = .vendorViaLibRaw) -> WhiteLevelPlan {
        let w: Int
        switch source { case .vendorViaLibRaw: w = vendorWhite; case .explicit(let v): w = max(black + 1, min(v, adcMax)) }
        return WhiteLevelPlan(black: black, white: w, vendorWhite: vendorWhite, adcMax: adcMax, source: source)
    }
}

/// Cele patru noțiuni de „decupare”, ținute SEPARAT (nu se confundă și nu se aplică în tăcere):
/// 1. `activeArea`  – ce decodează LibRaw (poate include margini ne-imagine: A7 V = 7168×5120 față de 7008×4672);
/// 2. `defaultCrop` – imaginea definită de producător (marginea de interpolare exclusă); REZULTATUL DE LUCRU implicit;
/// 3. `cameraAspectPreference` – aspectul ales pe cameră la declanșare (A7 III 16:9) – informație, ofertă opțională, NU se aplică automat;
/// 4. decuparea fotografului – parametru normalizat din reglaje (aplicat la ultimul pas geometric), în afara acestui tip.
public struct CropPlan: Equatable {
    public enum Source: String, Codable { case makerDefaultField, libRawInset, derivedNativeAspect, activeAreaFallback }
    public var activeArea: PixelRect
    public var defaultCrop: PixelRect
    public var defaultCropSource: Source
    public var cameraAspectPreference: PixelRect?
    public init(activeArea: PixelRect, defaultCrop: PixelRect, defaultCropSource: Source, cameraAspectPreference: PixelRect?) { self.activeArea = activeArea; self.defaultCrop = defaultCrop; self.defaultCropSource = defaultCropSource; self.cameraAspectPreference = cameraAspectPreference }

    /// Aspectul nativ al senzorului presupus 3:2 (verificat pe 4 modele, 12 fișiere: A7 III/IV/V, 6D II, R6 II); în afara lui, cădere pe zona activă (marcat).
    public static let nativeAspect = 1.5
    public static func resolve(_ g: RawGeometry, legacyAspect: Bool = false) -> CropPlan {
        func contains(_ outer: PixelRect, _ r: PixelRect) -> Bool { r.x >= outer.x && r.y >= outer.y && r.x + r.w <= outer.x + outer.w && r.y + r.h <= outer.y + outer.h }
        let active = PixelRect(x: g.activeArea.x, y: g.activeArea.y, w: g.activeArea.w, h: g.activeArea.h)
        if let m = g.makerDefaultCrop, !m.isEmpty, contains(active, m) {
            return CropPlan(activeArea: active, defaultCrop: m, defaultCropSource: .makerDefaultField, cameraAspectPreference: nil)
        }
        guard let inset = g.insetCrops.first, contains(active, inset) else {
            return CropPlan(activeArea: active, defaultCrop: active, defaultCropSource: .activeAreaFallback, cameraAspectPreference: nil)
        }
        let aspect = Double(inset.w) / Double(inset.h)
        // Aspectul nativ al senzorului = al zonei active (Fuji GFX 4:3, Canon/Sony 3:2). Un inset cu același aspect cu zona activă e imaginea completă, nu o preferință de aspect a camerei.
        let activeAspect = Double(active.w) / Double(active.h)
        if abs(aspect - nativeAspect) < 0.01 || (!legacyAspect && abs(aspect - activeAspect) < 0.01) {
            return CropPlan(activeArea: active, defaultCrop: inset, defaultCropSource: .libRawInset, cameraAspectPreference: nil)
        }
        // Inset-ul nu e 3:2 → preferință de aspect a camerei (A7 III 16:9). Implicit de lucru = 3:2 cu aceeași lățime, centrat pe inset (corespunde DefaultCrop-ului din metadate).
        let h = Int((Double(inset.w) / nativeAspect).rounded())
        let y = inset.y + (inset.h - h) / 2
        let derived = PixelRect(x: inset.x, y: y, w: inset.w, h: h)
        if contains(active, derived) {
            return CropPlan(activeArea: active, defaultCrop: derived, defaultCropSource: .derivedNativeAspect, cameraAspectPreference: inset)
        }
        return CropPlan(activeArea: active, defaultCrop: active, defaultCropSource: .activeAreaFallback, cameraAspectPreference: inset)
    }
}
