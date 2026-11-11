// GDC Photo Develop — nucleul fotografic PROPRIU (matematică, o singură sursă pentru aplicație și OFX). C++17, fără dependențe.
// Contract (INPUT DOMAIN → OPERATION → OUTPUT DOMAIN):
//   intrare: cod DaVinci Intermediate (DI) al unei imagini în DaVinci Wide Gamut (DWG), SAU DWG scene-liniar (1.0 = alb de referință; valori negative și > 1.0 admise);
//   S1 decodare DI → liniar DWG                         [COLORIMETRIC, formula publică Blackmagic]
//   S2 instrumente LINIARE în DWG (ordinea STYLE Exposure + Balance): expunere → umbre/lumini → balans (temperatură/tentă)   [balans: COLORIMETRIC (CAT Bradford, adaptare STYLE 120); expunere: COLORIMETRIC; umbre/lumini: CREATIVE, ferestre netede, STYLE ExposureZoneModel]
//   S3 liniar → cod DI (OETF Blackmagic)                [COLORIMETRIC]
//   S4 instrumente LOG pe codul DI: contrast în jurul unui pivot → saturație în jurul luminanței codului     [CREATIVE / HEURISTIC]
//   S5 „DRT p1” — PROTOTIP EXPERIMENTAL, NU este GDC DRT și nu îl echivalează (opțional): cod DI → liniar DWG → Rec.709 liniar → compresie de gamă → tone scale pe max-RGB cu păstrarea raporturilor + desaturare progresivă în lumini → sRGB OETF
//        [curba neutră: EMPIRICALLY_FITTED pe răspunsul neutru măsurat al DRT-ului STYLE existent (rms 0.006 în cod sRGB, max 0.013); restul: HEURISTIC, de reglat pe materiale reale]
//   ieșire: cod sRGB display-referred în [0,1] (DRT activ) SAU cod DI (DRT oprit).
// ETAPE: ajustare (S1–S4, `adjust_*`) → [corecții locale: aceleași instrumente pe cod DI, amestec cu mască manuală în domeniul DI] → afișare (S5, `display_pixel`, o singură dată).
// Valorile neutre (toate implicite) dau identitate numerică în S1–S4 (decodare + recodare DI; eroare float ≈ 1e-6). NaN/Inf la intrare se tratează ca 0 (documentat).
#pragma once
#include <cmath>
#include <algorithm>
#include <array>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>
// EDIȚII: sursa deschisă se compilează cu GDC_PC_OPEN_EDITION. Modulele GDC care nu fac parte din ea (GDC DRT, Color/Skin selectiv, Optics, Film V3, Look, Cinema Style)
// sunt excluse la compilare; restul nucleului e identic în ambele ediții, iar valorile salvate ale modulelor absente rămân în fișiere, fără efect.
#ifndef GDC_PC_OPEN_EDITION
#define GDC_PC_PREMIUM 1
#endif
#ifdef GDC_PC_PREMIUM
#include "gdc_drt.hpp"
#endif

namespace pc {

struct Params {
    double exposure = 0;        // stopuri, înmulțire liniară 2^exposure (neutru 0)
    double temperature = 0;     // mired; pozitiv = imagine mai caldă (neutru 0)
    double tint = 0;            // Δuv CIE 1960; pozitiv = imagine mai magenta (neutru 0)
    double shadows = 0;         // stopuri în fereastra umbrelor (neutru 0)
    double highlights = 0;      // stopuri în fereastra luminilor (neutru 0)
    double contrast = 1;        // factor în codul DI, în jurul pivotului (neutru 1)
    double pivot = 0;           // stopuri față de gri 18% (neutru 0)
    double saturation = 1;      // factor în codul DI, în jurul luminanței codului (neutru 1)
    int family = 0;             // familia de lucru (gamut + codificare log + adaptor DRT): 0 DaVinci Wide Gamut / DaVinci Intermediate (implicit, revenire) · 1 ACES AP1 / ACEScct · 2 ARRI AWG3 / LogC3 EI800 · 3 ARRI AWG4 / LogC4
    int inputIsLinear = 0;      // 0 = cod log AL FAMILIEI (implicit), 1 = scene-liniar în gamutul familiei, 2 = scene-liniar DWG (se convertește în gamutul familiei)
    int drt = 1;                // 0 = ieșire cod DI · 1 = DRT p1 (PROTOTIP experimental, NU GDC DRT) → sRGB · 2 = GDC DRT adaptat (algoritm + date ale proprietarului; gdc_drt.hpp) → cod conform `drtOutput`
    int drtProfile = 0;         // doar drt = 2: 0 Natural (reperul inițial)
    int stage = 0;              // rolul nodului: 0 = traseu complet (ajustare + afișare) · 1 = doar instrumentele LINIARE (cod DI → cod DI) · 2 = doar instrumentele LOG (cod DI → cod DI) · 3 = doar afișarea (cod DI → GDC DRT → codificare). Lanțul 1→2→3 ≡ 0 (aceeași matematică, fără duplicare).
    int drtOutput = 2;          // doar drt = 2: funcția de codificare a ieșirii: 0 g2.4 · 1 g2.2 · 2 sRGB (implicit sRGB pentru produsul fotografic)
    // ---- Exposure + Balance V3 (110/120/140): negru, zone Mi, Tonal Balance, Printer Lights, Channel Mix, Mix (SPEC §23; referința: ComposedToolsV3) ----
    double black = 0;                            // offset de negru (liniar, după expunere: x' = gain·(x + black)); ±0.5
    double midtones = 0;                         // stopuri în zona mijlocie (±1; complement exact al umbrelor/luminilor); garda de monotonie se aplică
    double shadowsTemp = 0, shadowsTint = 0, highlightsTemp = 0, highlightsTint = 0;   // Tonal Balance: mired ±60 / Duv ±0.02 pe zonele umbrelor / luminilor
    double printerMaster = 0, printerR = 0, printerG = 0, printerB = 0;                // Printer Lights, puncte (1 punct = 1/8 stop); Master se adună peste fiecare canal
    double cm[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1}; int cmKeepNeutrals = 0;               // Channel Mix 3×3 rând-major (liniar), după Balance; Keep Neutrals = fiecare rând împărțit la suma lui
    double ebMix = 1;                            // Mix-ul modulului Exposure + Balance
    // ---- Saturation + Hue V3 (210/215) ----
    double hvWidth = 60, hv[18] = {0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1}, hvMix = 1;   // Hue Vectors (230): lățime ° · [roșu, galben, verde, cyan, albastru, magenta] × (nuanță °, saturație ×, luminanță ×) · Mix
    double hueRotate = 0, hsvSat = 1, hsvVal = 1, shMix = 1;                           // grade; scalări HSV; Mix-ul modulului
    // ---- Tone V3 (220 + 300): Lift/Gamma/Gain → Wheels → ASC CDL → Contrast (contrast/pivot sunt câmpurile de mai sus), pe codul log al familiei ----
    double lift = 0, gamma = 1, gain = 1;        // master
    double shadowLimit = 0, highlightStart = 3.5; // Wheels: praguri în STOPURI față de gri 18% al profilului activ
    double wheels[12] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};                          // [zonă 0 umbre/1 mijloc/2 lumini][R,G,B,Master]
    double slope[3] = {1, 1, 1}, offset[3] = {0, 0, 0}, power[3] = {1, 1, 1}; double cdlSat = 1;   // ASC CDL
    double toneMix = 1;                          // Mix-ul modulului Tone
    // ---- Highlights + Gamut V3 (250; HighlightsGamutV3): Path to White → Gamut Compression → Highlight Roll-off, în scene-linear decodat cu curba REALĂ a familiei; Mix în cod ----
    // ---- Color (231/ColorV3) și Skin (235/SkinV3): selecție din culoare, OKLab prin LogViaLinear, pe codul log al familiei (style_color.hpp) ----
    double colorActive = 0, colorHue = 250, colorC = 0.5, colorL = 0, colorRange = 0.25, colorSoft = 0.5, colorSatRange = 0.5, colorLumRange = 0.4, cHue = 0, cSat = 0, cDensity = 0, cLum = 0, cWarm = 0, cSkinProt = 0, cNeutralProt = 0.5, cAmount = 1;
    double skRange = 0.5, skShadows = 0.5, skEdge = 0.5, skEven = 0, skHue = 0, skWarm = 0, skTint = 0, skVivid = 0, skRich = 0, skBright = 0, skAmount = 1;
    // ---- Optics V3 (OpticsV3: difuzie 7 filtre × 5 trepte + bloom), liniar în gamutul familiei, după instrumentele liniare ----
    // ---- Look (generația FIELD, lookfield.hpp): rețetă + trims + protecție + strength; cod log, după Color/Skin ----
    int lookOn = 0, lookIndex = 0; double lookStrength = 1, lookProtect = 0.5, lookContrast = 0, lookBlacks = 0, lookRoll = 0, lookSat = 0, lookWarm = 0, lookColor = 1;
    double opFilter = 0, opStrength = 2, opDiffusion = 0, opThreshold = 2.5, opSize = 0.5, opBloom = 0, opMix = 1;
    // ---- Corecție TEHNICĂ după chart (ColorChecker): matrice 3×3 în DWG liniar scene-referred, aplicată imediat după decodare, ÎNAINTEA instrumentelor liniare, a stilizării și a DRT-ului (doar pentru intrare liniară DWG) ----
    int chartOn = 0; double chartM[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1};
    double hgPathAmount = 0, hgPathOnset = 3, hgGamutAmount = 0, hgGamutThreshold = 0.85, hgHlAmount = 0, hgHlKnee = 2.5, hgMix = 1;
};

using M3 = std::array<double, 9>;
inline M3 mul(const M3& a, const M3& b) { M3 r{}; for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) { double s = 0; for (int k = 0; k < 3; k++) s += a[3 * i + k] * b[3 * k + j]; r[3 * i + j] = s; } return r; }
inline M3 inv(const M3& m) {
    const double a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8];
    const double det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    return {(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det, (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det, (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det};
}
inline std::array<double, 3> xyY(double x, double y) { return {x / y, 1.0, (1 - x - y) / y}; }
inline M3 rgbToXYZ(const double p[3][2], const double w[2]) {
    auto r = xyY(p[0][0], p[0][1]), g = xyY(p[1][0], p[1][1]), b = xyY(p[2][0], p[2][1]), wh = xyY(w[0], w[1]);
    M3 P = {r[0], g[0], b[0], r[1], g[1], b[1], r[2], g[2], b[2]}; M3 Pi = inv(P);
    double S[3]; for (int i = 0; i < 3; i++) S[i] = Pi[3 * i] * wh[0] + Pi[3 * i + 1] * wh[1] + Pi[3 * i + 2] * wh[2];
    return {P[0] * S[0], P[1] * S[1], P[2] * S[2], P[3] * S[0], P[4] * S[1], P[5] * S[2], P[6] * S[0], P[7] * S[1], P[8] * S[2]};
}
constexpr double kD65[2] = {0.3127, 0.3290};

// ---------- DaVinci Intermediate (constantele publicate Blackmagic) ----------
constexpr double DI_A = 0.0075, DI_B = 7.0, DI_C = 0.07329248, DI_M = 10.44426855, DI_LIN_CUT = 0.00262409, DI_LOG_CUT = 0.02740668;
inline double di_encode(double x) { return x <= DI_LIN_CUT ? x * DI_M : (std::log2(x + DI_A) + DI_B) * DI_C; }   // x ≥ −A nu e cerut: ramura liniară acoperă și negativele
inline double di_decode(double y) { return y <= DI_LOG_CUT ? y / DI_M : std::exp2(y / DI_C - DI_B) - DI_A; }

// ---------- luminanță DWG (Y al primarelor), ferestre ----------
inline double smoothstep(double a, double b, double x) { double t = std::min(1.0, std::max(0.0, (x - a) / (b - a))); return t * t * (3 - 2 * t); }

// ---------- temperatură / tentă → matrice 3×3 în DWG liniar (CAT Bradford) ----------
inline void kim_xy(double T, double& x, double& y) {   // locusul Planckian, aproximarea Kim et al. (2002), 1667–25000 K
    T = std::min(25000.0, std::max(1667.0, T)); const double t1 = 1e3 / T, t2 = t1 * t1, t3 = t2 * t1;
    x = T <= 4000 ? -0.2661239 * t3 - 0.2343589 * t2 + 0.8776956 * t1 + 0.179910 : -3.0258469 * t3 + 2.1070379 * t2 + 0.2226347 * t1 + 0.240390;
    const double x2 = x * x, x3 = x2 * x;
    y = T <= 2222 ? -1.1063814 * x3 - 1.34811020 * x2 + 2.18555832 * x - 0.20219683 : (T <= 4000 ? -0.9549476 * x3 - 1.37418593 * x2 + 2.09137015 * x - 0.16748867 : 3.0817580 * x3 - 5.87338670 * x2 + 3.75112997 * x - 0.37001483);
}
inline void xy_to_uv(double x, double y, double& u, double& v) { const double d = -2 * x + 12 * y + 3; u = 4 * x / d; v = 6 * y / d; }
inline void uv_to_xy(double u, double v, double& x, double& y) { const double d = 2 * u - 8 * v + 4; x = 3 * u / d; y = 2 * v / d; }

inline const M3& dwgToXYZ() { static const M3 m = [] { const double p[3][2] = {{0.8000, 0.3130}, {0.1682, 0.9877}, {0.0790, -0.1155}}; return rgbToXYZ(p, kD65); }(); return m; }
inline const M3& rec709ToXYZ() { static const M3 m = [] { const double p[3][2] = {{0.64, 0.33}, {0.30, 0.60}, {0.15, 0.06}}; return rgbToXYZ(p, kD65); }(); return m; }
/// Coeficienții de luminanță ai DaVinci Wide Gamut = rândul Y al matricei RGB→XYZ (SMPTE RP 177) din primarele DWG; ca în STYLE (`WorkingSpaceProfile::lumaY`): 0.27412 · 0.87363 · −0.14775 (albastrul are coeficient NEGATIV: primara lui are y < 0).
/// (O valoare anterioară 0.2949/0.6254/0.0797 NU era rândul Y al DWG; corectată 2026-10-21 după comparația cu referința STYLE.)
inline const std::array<double, 3>& lumaY() { static const std::array<double, 3> y = [] { const M3& m = dwgToXYZ(); return std::array<double, 3>{m[3], m[4], m[5]}; }(); return y; }
inline M3 dwgToRec709() { return mul(inv(rec709ToXYZ()), dwgToXYZ()); }

// ---------- FAMILII DE LUCRU (gamut + codificare log), din inventarul autoritar GDC STYLE `workingSpaceProfiles` ----------
// ap1-acescct „ACES AP1 / ACEScct” · dwg-davinci-intermediate „DaVinci WG / Intermediate” · awg3-logc3-ei800 „ARRI AWG3 / LogC3 EI800” · awg4-logc4 „ARRI AWG4 / LogC4”. Gama, albul și curbele = ColorSpace.cpp (STYLE v2.10.0), portate cu aceleași constante;
// numele curbei NU alege gamutul: perechea e fixă pe familie. Instrumentele își calculează cu luminanța (rândul Y al matricei RGB→XYZ), albul și 18% gri codat ALE FAMILIEI; GDC DRT primește DWG liniar prin adaptorul familiei (Bradford alb familie → D65, ca `gamutConversion`).
constexpr double kAcesW[2] = {0.32168, 0.33767};
constexpr double CCT_A = 10.5402377416545, CCT_B = 0.0729055341958355, CCT_LIN_CUT = 0.0078125, CCT_LOG_CUT = 0.155251141552511;
inline double acescct_enc(double x) { return x <= CCT_LIN_CUT ? CCT_A * x + CCT_B : (std::log2(x) + 9.72) / 17.52; }
inline double acescct_dec(double y) { return y <= CCT_LOG_CUT ? (y - CCT_B) / CCT_A : std::exp2(y * 17.52 - 9.72); }
constexpr double LC3_CUT = 0.010591, LC3_A = 5.555556, LC3_B = 0.052272, LC3_C = 0.247190, LC3_D = 0.385537, LC3_E = 5.367655, LC3_F = 0.092809;
inline double logc3_enc(double x) { return x > LC3_CUT ? LC3_C * std::log10(LC3_A * x + LC3_B) + LC3_D : LC3_E * x + LC3_F; }
inline double logc3_dec(double y) { return y > LC3_E * LC3_CUT + LC3_F ? (std::pow(10.0, (y - LC3_D) / LC3_C) - LC3_B) / LC3_A : (y - LC3_F) / LC3_E; }
struct LogC4K { double a, b, c, s, t; LogC4K() { a = (std::pow(2.0, 18.0) - 16.0) / 117.45; b = (1023.0 - 95.0) / 1023.0; c = 95.0 / 1023.0; s = (7.0 * std::log(2.0) * std::pow(2.0, 7.0 - 14.0 * c / b)) / (a * b); t = (std::pow(2.0, 14.0 * (-c / b) + 6.0) - 64.0) / a; } };
inline const LogC4K& logc4k() { static const LogC4K k; return k; }
inline double logc4_enc(double x) { const LogC4K& k = logc4k(); return x >= k.t ? (std::log2(k.a * x + 64.0) - 6.0) / 14.0 * k.b + k.c : (x - k.t) / k.s; }
inline double logc4_dec(double y) { const LogC4K& k = logc4k(); return y >= 0 ? (std::exp2(14.0 * (y - k.c) / k.b + 6.0) - 64.0) / k.a : y * k.s + k.t; }
/// curve: 0 DaVinci Intermediate · 1 ACEScct · 2 LogC3 EI800 · 3 LogC4.
inline double fam_enc(int curve, double x) { switch (curve) { case 1: return acescct_enc(x); case 2: return logc3_enc(x); case 3: return logc4_enc(x); default: return di_encode(x); } }
inline double fam_dec(int curve, double y) { switch (curve) { case 1: return acescct_dec(y); case 2: return logc3_dec(y); case 3: return logc4_dec(y); default: return di_decode(y); } }
inline M3 bradford_cat(double fx, double fy, double tx, double ty) {
    if (std::fabs(fx - tx) < 1e-9 && std::fabs(fy - ty) < 1e-9) return {1, 0, 0, 0, 1, 0, 0, 0, 1};
    const M3 B = {0.8951, 0.2664, -0.1614, -0.7502, 1.7135, 0.0367, 0.0389, -0.0685, 1.0296}; auto src = xyY(fx, fy), dst = xyY(tx, ty);
    double s[3], d[3]; for (int i = 0; i < 3; i++) { s[i] = B[3 * i] * src[0] + B[3 * i + 1] * src[1] + B[3 * i + 2] * src[2]; d[i] = B[3 * i] * dst[0] + B[3 * i + 1] * dst[1] + B[3 * i + 2] * dst[2]; }
    return mul(inv(B), mul({d[0] / s[0], 0, 0, 0, d[1] / s[1], 0, 0, 0, d[2] / s[2]}, B));
}
struct FamilyData {
    const char* id; const char* label; int curve; double prim[3][2]; double white[2];
    M3 toXYZ{}, fromXYZ{}, toDwg{}, fromDwg{}; std::array<double, 3> luma{}; double grey18Code = 0;
};
inline const FamilyData& family(int id) {
    static const std::array<FamilyData, 4> F = [] {
        std::array<FamilyData, 4> a{};
        a[0] = {"dwg-davinci-intermediate", "DaVinci WG / Intermediate", 0, {{0.8000, 0.3130}, {0.1682, 0.9877}, {0.0790, -0.1155}}, {kD65[0], kD65[1]}};
        a[1] = {"ap1-acescct", "ACES AP1 / ACEScct", 1, {{0.713, 0.293}, {0.165, 0.830}, {0.128, 0.044}}, {kAcesW[0], kAcesW[1]}};
        a[2] = {"awg3-logc3-ei800", "ARRI AWG3 / LogC3 EI800", 2, {{0.6840, 0.3130}, {0.2210, 0.8480}, {0.0861, -0.1020}}, {kD65[0], kD65[1]}};
        a[3] = {"awg4-logc4", "ARRI AWG4 / LogC4", 3, {{0.7347, 0.2653}, {0.1424, 0.8576}, {0.0991, -0.0308}}, {kD65[0], kD65[1]}};
        const M3 dwg = dwgToXYZ();
        for (int i = 0; i < 4; i++) {
            FamilyData& f = a[i]; f.toXYZ = i == 0 ? dwg : rgbToXYZ(f.prim, f.white); f.fromXYZ = inv(f.toXYZ); f.luma = {f.toXYZ[3], f.toXYZ[4], f.toXYZ[5]}; f.grey18Code = fam_enc(f.curve, 0.18);
            if (i == 0) { f.toDwg = f.fromDwg = {1, 0, 0, 0, 1, 0, 0, 0, 1}; }   // identitate EXACTĂ pe familia de revenire
            else { f.toDwg = mul(inv(dwg), mul(bradford_cat(f.white[0], f.white[1], kD65[0], kD65[1]), f.toXYZ)); f.fromDwg = inv(f.toDwg); }
        }
        return a; }();
    return F[id < 0 ? 0 : (id > 3 ? 3 : id)];
}
inline void apply3(const M3& m, const double v[3], double o[3]) { o[0] = m[0] * v[0] + m[1] * v[1] + m[2] * v[2]; o[1] = m[3] * v[0] + m[4] * v[1] + m[5] * v[2]; o[2] = m[6] * v[0] + m[7] * v[1] + m[8] * v[2]; }

/// McCamy (1992): CCT din cromaticitatea xy (aproximație, ca în STYLE `mccamy1992CCT`).
inline double mccamy_cct(double x, double y) { const double n = (x - 0.3320) / (y - 0.1858); return -449.0 * n * n * n + 3525.0 * n * n - 6823.3 * n + 5520.33; }
/// Deplasare Δuv perpendiculară pe locusul Planckian (CIE 1960), tangenta numerică la ±5 K în jurul CCT-ului punctului (STYLE `applyDuvTint`; duv > 0 ⇒ ținta se mută spre verde ⇒ IMAGINEA devine mai magenta).
inline void apply_duv(double& x, double& y, double duv) {
    if (duv == 0.0) return;
    const double t = mccamy_cct(x, y); double x1, y1, x2, y2, u0, v0, u1, v1, u2, v2; kim_xy(t - 5.0, x1, y1); kim_xy(t + 5.0, x2, y2);
    xy_to_uv(x, y, u0, v0); xy_to_uv(x1, y1, u1, v1); xy_to_uv(x2, y2, u2, v2);
    double tu = u2 - u1, tv = v2 - v1; const double tl = std::sqrt(tu * tu + tv * tv); if (tl < 1e-12) return; tu /= tl; tv /= tl;
    uv_to_xy(u0 - duv * tv, v0 + duv * tu, x, y);
}
/// Balans de alb în DWG liniar — ADAPTAREA fotografică a lui STYLE `v2-120-white-balance` (aceeași formulare: ținta = albul D65 al gamei deplasat cu `shift` mired pe locusul Planckian (Kang/Kim 2002) + Δuv; Bradford de la albul D65 la țintă; matricea în gama DWG).
/// Pozitiv ⇒ imagine mai caldă (temperatură) / mai magenta (tentă). Neutru la 0/0 (identitate exactă). Paritate cu referința STYLE verificată numeric pe fotografii reale (scripts/dev/style_ref_compare).
inline M3 balanceMatrix(double temperatureMired, double tint, int fam = 0) {
    if (temperatureMired == 0 && tint == 0) return {1, 0, 0, 0, 1, 0, 0, 0, 1};
    const FamilyData& F = family(fam);   // 120: ținta = albul GAMEI FAMILIEI (D65; D60 la ACES AP1) deplasat pe locus; Bradford de la alb la țintă; matricea în gamutul familiei
    const double t0 = mccamy_cct(F.white[0], F.white[1]); const double targetMired = 1e6 / t0 + temperatureMired;
    double tx, ty; kim_xy(1e6 / std::max(targetMired, 40.0), tx, ty); apply_duv(tx, ty, tint);
    return mul(F.fromXYZ, mul(bradford_cat(F.white[0], F.white[1], tx, ty), F.toXYZ));
}

#ifdef GDC_PC_PREMIUM
#include "style_color.hpp"
#include "film3/lookfield.hpp"
#endif

// ---------- DRT propriu ----------
constexpr double kTmA = 1.34, kTmK = 0.362, kTmP = 1.5;   // curba neutră (EMPIRICALLY_FITTED, vezi antetul)
inline double tone_scale(double x) { if (x <= 0) return 0; const double xa = std::pow(x, kTmA); return std::pow(xa / (xa + kTmK), kTmP); }
inline double srgb_oetf(double v) { v = std::min(1.0, std::max(0.0, v)); return v <= 0.0031308 ? 12.92 * v : 1.055 * std::pow(v, 1 / 2.4) - 0.055; }

// ---------- datele GDC DRT (încărcate o singură dată, din fișier; NU sunt în git) ----------
#ifdef GDC_PC_PREMIUM
inline gdcdrt::Data& drtData() { static gdcdrt::Data d; return d; }
inline std::mutex& drtMutex() { static std::mutex m; return m; }
inline bool drtReady() { return drtData().ok; }
inline bool drtLoadBytes(const unsigned char* b, size_t n, std::string& err) { std::lock_guard<std::mutex> l(drtMutex()); gdcdrt::Data d; if (!gdcdrt::parse(b, n, d)) { err = d.error; return false; } drtData() = std::move(d); return true; }
#else
inline bool drtReady() { return false; }
inline bool drtLoadBytes(const unsigned char*, size_t, std::string& err) { err = "GDC DRT is not part of the open-source edition"; return false; }
#endif

// ---------- etapele pe un pixel (float32 în/out, calcul intern double pentru referință) ----------
struct Prepared {
    Params p; const FamilyData* f = nullptr; M3 balance{}; bool hasBalance = false; double gain = 1; M3 toRec709{}; double pivotCode = 0.3360;
    // Exposure + Balance V3
    bool hasExpo = false;                                   // gain ≠ 1 sau negru ≠ 0
    double zSh = 0, zMi = 0, zHi = 0; bool zonesOn = false;  // câștiguri EFECTIVE (după garda de monotonie)
    M3 dS{}, dH{}; bool tb = false, sAct = false, hAct = false;   // Tonal Balance: (M_z − I)
    M3 cmM{}; bool hasCm = false;                           // Channel Mix efectiv
    // Tone V3
    bool toneOn = false, wheelsOn = false, cdlOn = false, lggOn = false, contrastOn = false;
    double lowThr = 0, lowEdge = 0, highThr = 0, highEdge = 0;
    bool satHueOn = false, hueOn = false, satOn = false, hvOn = false;
    bool skipLinear = false;                              // instrumentele liniare au fost deja aplicate (calea cu Optics)
#ifdef GDC_PC_PREMIUM
    bool colorOn = false, skinOn = false; sc::ColorP cp; sc::SkinP sp;
    bool lookOn = false; double lookProtect = 0.5; lf::LookFieldEffective look;
#endif
};
// ---- model comun de zone de expunere (ExposureZoneModelV3): ws, wh = 1.1.0; wm = complementul exact; garda de monotonie ----
inline double zsmooth(double a, double b, double x) { double t = (x - a) / (b - a); t = t != t ? t : (t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t)); return t * t * (3.0 - 2.0 * t); }
struct ZoneW { double sh, mi, hi; };
inline ZoneW zone_weights_stops(double e) { ZoneW w; w.sh = 1.0 - zsmooth(-4.0, -0.5, e); w.hi = zsmooth(0.5, 4.0, e); const double wm = 1.0 - w.sh - w.hi; w.mi = wm < 0.0 ? 0.0 : wm; return w; }
inline ZoneW zone_weights_luma(double y) { const double yy = y != y ? y : (y > 1e-6 ? y : 1e-6); return zone_weights_stops(std::log2(yy / 0.18)); }
inline double zone_softcap(double d) { const double w = 0.2; return 2.0 + w * std::tanh((d - 2.0) / w); }
inline void zone_guard(double& sh, double mi, double& hi) { const double ds = sh - mi; if (ds > 2.0) sh = mi + zone_softcap(ds); const double dh = mi - hi; if (dh > 2.0) hi = mi - zone_softcap(dh); }
inline M3 balance_affine(const Params& p, double temp, double tint, double pr, double pg, double pb) {
    const M3 cat = balanceMatrix(temp, tint, p.family); const double g[3] = {std::exp2(pr / 8.0), std::exp2(pg / 8.0), std::exp2(pb / 8.0)}; M3 m{};
    for (int r = 0; r < 3; r++) for (int c = 0; c < 3; c++) m[3 * r + c] = g[r] * cat[3 * r + c];
    return m;
}
inline Prepared prepare(const Params& p) {
    Prepared r; r.p = p; r.f = &family(p.family); r.balance = balanceMatrix(p.temperature, p.tint, p.family); r.gain = std::exp2(p.exposure);
    r.toRec709 = dwgToRec709(); r.pivotCode = fam_enc(r.f->curve, 0.18 * std::exp2(p.pivot));
    // Exposure + Balance
    r.hasExpo = (r.gain != 1 || p.black != 0);
    r.zSh = p.shadows; r.zMi = p.midtones; r.zHi = p.highlights; zone_guard(r.zSh, r.zMi, r.zHi); r.zonesOn = !(p.shadows == 0 && p.midtones == 0 && p.highlights == 0);
    r.tb = p.shadowsTemp != 0 || p.shadowsTint != 0 || p.highlightsTemp != 0 || p.highlightsTint != 0;
    if (r.tb) { const M3 a = balanceMatrix(p.shadowsTemp, p.shadowsTint, p.family), b = balanceMatrix(p.highlightsTemp, p.highlightsTint, p.family);
        for (int i = 0; i < 9; i++) { const double id = (i % 4 == 0) ? 1.0 : 0.0; r.dS[i] = a[i] - id; r.dH[i] = b[i] - id; r.sAct |= r.dS[i] != 0; r.hAct |= r.dH[i] != 0; } }
    const bool printer = p.printerMaster != 0 || p.printerR != 0 || p.printerG != 0 || p.printerB != 0;
    r.hasBalance = (p.temperature != 0 || p.tint != 0 || printer);
    if (r.hasBalance) r.balance = balance_affine(p, p.temperature, p.tint, p.printerR + p.printerMaster, p.printerG + p.printerMaster, p.printerB + p.printerMaster);
    for (int i = 0; i < 9; i++) r.cmM[i] = p.cm[i];
    if (p.cmKeepNeutrals) for (int k = 0; k < 3; k++) { const double sum = r.cmM[3 * k] + r.cmM[3 * k + 1] + r.cmM[3 * k + 2]; if (sum > 1e-6 || sum < -1e-6) for (int c = 0; c < 3; c++) r.cmM[3 * k + c] /= sum; }
    for (int i = 0; i < 9; i++) { const double id = (i % 4 == 0) ? 1.0 : 0.0; if (r.cmM[i] != id) r.hasCm = true; }
    // Tone V3
    r.lggOn = !(p.lift == 0 && p.gamma == 1 && p.gain == 1);
    r.wheelsOn = false; for (int i = 0; i < 12; i++) if (p.wheels[i] != 0) r.wheelsOn = true;
    r.cdlOn = !(p.slope[0] == 1 && p.slope[1] == 1 && p.slope[2] == 1 && p.offset[0] == 0 && p.offset[1] == 0 && p.offset[2] == 0 && p.power[0] == 1 && p.power[1] == 1 && p.power[2] == 1 && p.cdlSat == 1);
    r.contrastOn = p.contrast != 1; r.toneOn = r.lggOn || r.wheelsOn || r.cdlOn || r.contrastOn;
    { const double lowSt = p.shadowLimit, highSt = std::max(p.highlightStart, p.shadowLimit + 0.25), span = 4.0; const int cv = r.f->curve;
      r.lowThr = fam_enc(cv, 0.18 * std::exp2(lowSt)); r.highThr = fam_enc(cv, 0.18 * std::exp2(highSt)); r.lowEdge = fam_enc(cv, 0.18 * std::exp2(lowSt - span)); r.highEdge = fam_enc(cv, 0.18 * std::exp2(highSt + span)); }
#ifdef GDC_PC_PREMIUM
    r.cp.active = p.colorActive != 0; r.cp.centerHue = p.colorHue; r.cp.centerC = p.colorC; r.cp.centerL = p.colorL; r.cp.range = p.colorRange; r.cp.soft = p.colorSoft; r.cp.satRange = p.colorSatRange; r.cp.lumRange = p.colorLumRange; r.cp.hue = p.cHue; r.cp.sat = p.cSat; r.cp.density = p.cDensity; r.cp.lum = p.cLum; r.cp.warm = p.cWarm; r.cp.skin = p.cSkinProt; r.cp.neutral = p.cNeutralProt; r.cp.amount = p.cAmount; r.colorOn = !sc::color_neutral(r.cp);
    r.sp.range = p.skRange; r.sp.shadows = p.skShadows; r.sp.edge = p.skEdge; r.sp.even = p.skEven; r.sp.hue = p.skHue; r.sp.warmth = p.skWarm; r.sp.tint = p.skTint; r.sp.vivid = p.skVivid; r.sp.rich = p.skRich; r.sp.bright = p.skBright; r.sp.amount = p.skAmount; r.skinOn = !sc::skin_neutral(r.sp);
    if (p.lookOn) { const auto& lib = lf::lookFieldLibrary(); const int idx = p.lookIndex < 0 ? 0 : (p.lookIndex >= (int)lib.size() ? (int)lib.size() - 1 : p.lookIndex);
        lf::LookFieldTrims t; t.contrast = p.lookContrast; t.blacks = p.lookBlacks; t.roll = p.lookRoll; t.sat = p.lookSat; t.warm = p.lookWarm; t.color = p.lookColor;
        r.look = lf::resolveLookField(lib[(size_t)idx], t, p.lookStrength); r.lookProtect = lf::clampD(p.lookProtect, 0.0, 1.0); r.lookOn = !r.look.identity; }
#endif
    { bool nn = false; for (int i = 0; i < 6; i++) nn = nn || p.hv[3 * i] != 0 || p.hv[3 * i + 1] != 1 || p.hv[3 * i + 2] != 1; r.hvOn = nn; }
    r.satOn = p.saturation != 1; r.hueOn = !(p.hueRotate == 0 && p.hsvSat == 1 && p.hsvVal == 1); r.satHueOn = r.satOn || r.hueOn;
    return r;
}
inline double fin(double v) { return std::isfinite(v) ? v : 0.0; }

/// S2: instrumente liniare (în gamutul familiei), în ordinea STYLE V3 „Exposure + Balance”: Exposure + Black (110) → zone Sh/Mi/Hi (+ Tonal Balance) pe luma profilului DUPĂ expunere → Balance + Printer Lights (120) → Channel Mix (140) → Mix.
inline void linear_tools(const Prepared& s, double c[3]) {
    if (s.skipLinear) return;
    const Params& p = s.p; const double in0 = c[0], in1 = c[1], in2 = c[2];
    if (s.hasExpo) { const double off = s.gain * p.black; c[0] = off + s.gain * c[0]; c[1] = off + s.gain * c[1]; c[2] = off + s.gain * c[2]; }
    if (s.zonesOn || s.tb) {
        const double Y = s.f->luma[0] * c[0] + s.f->luma[1] * c[1] + s.f->luma[2] * c[2];
        const ZoneW w = zone_weights_luma(Y);
        const double stops = s.zMi == 0.0 ? s.zSh * w.sh + s.zHi * w.hi : s.zSh * w.sh + s.zMi * w.mi + s.zHi * w.hi; const double f = std::exp2(stops);
        if (s.tb) { double o[3]; for (int r = 0; r < 3; r++) { const double ds = s.dS[3 * r] * c[0] + s.dS[3 * r + 1] * c[1] + s.dS[3 * r + 2] * c[2], dh = s.dH[3 * r] * c[0] + s.dH[3 * r + 1] * c[1] + s.dH[3 * r + 2] * c[2];
                o[r] = f * (c[r] + (s.sAct && w.sh != 0.0 ? w.sh * ds : 0.0) + (s.hAct && w.hi != 0.0 ? w.hi * dh : 0.0)); } c[0] = o[0]; c[1] = o[1]; c[2] = o[2]; }
        else { c[0] *= f; c[1] *= f; c[2] *= f; }
    }
    if (s.hasBalance) { const double r = c[0], g = c[1], b = c[2]; c[0] = s.balance[0] * r + s.balance[1] * g + s.balance[2] * b; c[1] = s.balance[3] * r + s.balance[4] * g + s.balance[5] * b; c[2] = s.balance[6] * r + s.balance[7] * g + s.balance[8] * b; }
    if (s.hasCm) { const double r = c[0], g = c[1], b = c[2]; c[0] = s.cmM[0] * r + s.cmM[1] * g + s.cmM[2] * b; c[1] = s.cmM[3] * r + s.cmM[4] * g + s.cmM[5] * b; c[2] = s.cmM[6] * r + s.cmM[7] * g + s.cmM[8] * b; }
    if (p.ebMix != 1.0) { c[0] = p.ebMix * c[0] + (1.0 - p.ebMix) * in0; c[1] = p.ebMix * c[1] + (1.0 - p.ebMix) * in1; c[2] = p.ebMix * c[2] + (1.0 - p.ebMix) * in2; }
}
inline double tone_smooth(double a, double b, double x) { if (b <= a) return x != x ? std::nan("") : (x >= b ? 1.0 : 0.0); const double t0 = (x - a) / (b - a); const double t = t0 < 0.0 ? 0.0 : (t0 > 1.0 ? 1.0 : t0); return t * t * (3.0 - 2.0 * t); }
inline double cdl_clamp(double x) { return x != x ? x : (x > 0.0 ? x : 0.0); }
// ---- Hue/HSV (215): rgb → hsv → rotație/scalări → rgb (referința: HueToolsV2) ----
inline void rgb_to_hsv(const double c[3], double h[3]) {
    const double mx = std::max(c[0], std::max(c[1], c[2])), mn = std::min(c[0], std::min(c[1], c[2])), d = mx - mn; double hh = 0.0;
    if (d > 0.0) { if (mx == c[0]) hh = 60.0 * (c[1] - c[2]) / d; else if (mx == c[1]) hh = 60.0 * (2.0 + (c[2] - c[0]) / d); else hh = 60.0 * (4.0 + (c[0] - c[1]) / d); if (hh < 0.0) hh += 360.0; }
    h[0] = hh; h[1] = mx == 0.0 ? 0.0 : d / mx; h[2] = mx;
}
inline void hsv_to_rgb(const double hsv[3], double o[3]) {
    const double s = hsv[1], v = hsv[2]; if (s == 0.0) { o[0] = o[1] = o[2] = v; return; }
    double h = std::fmod(hsv[0], 360.0); if (h < 0.0) h += 360.0; const double sector = h / 60.0; int i = (int)sector; if (i > 5) i = 5; if (i < 0) i = 0; const double f = sector - i;
    const double pp = v * (1.0 - s), q = v * (1.0 - s * f), t = v * (1.0 - s * (1.0 - f));
    switch (i) { case 0: o[0] = v; o[1] = t; o[2] = pp; break; case 1: o[0] = q; o[1] = v; o[2] = pp; break; case 2: o[0] = pp; o[1] = v; o[2] = t; break; case 3: o[0] = pp; o[1] = q; o[2] = v; break; case 4: o[0] = t; o[1] = pp; o[2] = v; break; default: o[0] = v; o[1] = pp; o[2] = q; }
}
/// S4: instrumente log (cod log al familiei → cod log al familiei), în ordinea STYLE V3: Tone (Lift/Gamma/Gain → Wheels → ASC CDL → Contrast+Pivot, Mix) → Saturation + Hue (Saturation → Hue/HSV, Mix).
inline void log_tools(const Prepared& s, double c[3]) {
    const Params& p = s.p; const double* L = s.f->luma.data();
    if (s.toneOn) {
        const double in0 = c[0], in1 = c[1], in2 = c[2];
        if (s.lggOn || s.wheelsOn || s.cdlOn) {
            double x1[3]; for (int i = 0; i < 3; i++) { const double v = p.gain * (c[i] * (1.0 - p.lift) + p.lift); x1[i] = std::pow(v, 1.0 / p.gamma); }
            const double pos = L[0] * x1[0] + L[1] * x1[1] + L[2] * x1[2];
            const double ws = 1.0 - tone_smooth(s.lowEdge, s.lowThr, pos), wh = tone_smooth(s.highThr, s.highEdge, pos); double wm = 1.0 - ws - wh; if (wm < 0.0) wm = 0.0;
            double x2[3]; for (int k = 0; k < 3; k++) x2[k] = x1[k] + (ws * (p.wheels[k] + p.wheels[3]) + wm * (p.wheels[4 + k] + p.wheels[7]) + wh * (p.wheels[8 + k] + p.wheels[11]));
            double x3[3] = {x2[0], x2[1], x2[2]};
            if (s.cdlOn) { for (int k = 0; k < 3; k++) { x3[k] = cdl_clamp(x2[k] * p.slope[k] + p.offset[k]); if (p.power[k] != 1.0) x3[k] = std::pow(x3[k], p.power[k]); }
                if (p.cdlSat != 1.0) { const double y = L[0] * x3[0] + L[1] * x3[1] + L[2] * x3[2]; for (int k = 0; k < 3; k++) x3[k] = y + (x3[k] - y) * p.cdlSat; } }
            c[0] = x3[0]; c[1] = x3[1]; c[2] = x3[2];
        }
        if (s.contrastOn) for (int i = 0; i < 3; i++) c[i] = s.pivotCode + (c[i] - s.pivotCode) * p.contrast;
        if (p.toneMix != 1.0) { c[0] = p.toneMix * c[0] + (1.0 - p.toneMix) * in0; c[1] = p.toneMix * c[1] + (1.0 - p.toneMix) * in1; c[2] = p.toneMix * c[2] + (1.0 - p.toneMix) * in2; }
    }
    if (s.satHueOn) {
        const double in0 = c[0], in1 = c[1], in2 = c[2];
        if (s.satOn) { const double Y = L[0] * c[0] + L[1] * c[1] + L[2] * c[2]; for (int i = 0; i < 3; i++) c[i] = Y + p.saturation * (c[i] - Y); }
        if (s.hueOn) { double h[3], o[3]; rgb_to_hsv(c, h); h[0] += p.hueRotate; h[1] *= p.hsvSat; h[2] *= p.hsvVal; hsv_to_rgb(h, o); c[0] = o[0]; c[1] = o[1]; c[2] = o[2]; }
        if (p.shMix != 1.0) { c[0] = p.shMix * c[0] + (1.0 - p.shMix) * in0; c[1] = p.shMix * c[1] + (1.0 - p.shMix) * in1; c[2] = p.shMix * c[2] + (1.0 - p.shMix) * in2; }
    }
    if (s.hvOn) {   // Hue Vectors (230): 6 vectori de nuanță (fereastră smoothstep circulară), nuanță/saturație/luminanță în HSV; gri/negru neatinse; S și V NU se limitează (negativele se păstrează)
        const double in0 = c[0], in1 = c[1], in2 = c[2]; double h[3]; rgb_to_hsv(c, h);
        if (h[2] > 0.0 && h[1] > 0.0) {
            double shift = 0, sat = 0, lum = 0; const double width = p.hvWidth > 0.05 ? p.hvWidth : 0.05;
            for (int i = 0; i < 6; i++) { double d = std::fabs(h[0] - i * 60.0); if (d > 180.0) d = 360.0 - d; const double w = 1.0 - d / width; if (w <= 0.0) continue; const double ws = w * w * (3.0 - 2.0 * w); shift += ws * p.hv[3 * i]; sat += ws * (p.hv[3 * i + 1] - 1.0); lum += ws * (p.hv[3 * i + 2] - 1.0); }
            if (shift != 0.0 || sat != 0.0 || lum != 0.0) { double o[3], q[3] = {h[0] + shift, h[1] * (1.0 + sat), h[2] * (1.0 + lum)}; hsv_to_rgb(q, o); c[0] = o[0]; c[1] = o[1]; c[2] = o[2]; }
        }
        if (p.hvMix != 1.0) { c[0] = p.hvMix * c[0] + (1.0 - p.hvMix) * in0; c[1] = p.hvMix * c[1] + (1.0 - p.hvMix) * in1; c[2] = p.hvMix * c[2] + (1.0 - p.hvMix) * in2; }
    }
#ifdef GDC_PC_PREMIUM
    if (s.colorOn) sc::color_apply(p.family, s.cp, c);
    if (s.skinOn) sc::skin_apply(p.family, s.sp, c);
    if (s.lookOn) lf::applyLookField(p.family, s.look, s.lookProtect, c);
#endif
}
/// S5: DRT propriu (cod DI → cod sRGB).
inline void drt(const Prepared& s, const double code[3], double out[3]) {
    double lf[3], lin[3]; for (int i = 0; i < 3; i++) lf[i] = fam_dec(s.f->curve, code[i]); apply3(s.f->toDwg, lf, lin);
    double c[3]; for (int i = 0; i < 3; i++) c[i] = s.toRec709[3 * i] * lin[0] + s.toRec709[3 * i + 1] * lin[1] + s.toRec709[3 * i + 2] * lin[2];
    const double Y = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; const double mn = std::min(c[0], std::min(c[1], c[2]));
    if (Y <= 0) { out[0] = out[1] = out[2] = 0; return; }
    if (mn < 0) { const double t = -mn / (Y - mn); for (int i = 0; i < 3; i++) c[i] += t * (Y - c[i]); }   // compresie de gamă: continuă la mn→0, aduce minimul la 0
    const double n = std::max(c[0], std::max(c[1], c[2]));
    if (n <= 0) { out[0] = out[1] = out[2] = 0; return; }
    const double tn = tone_scale(n), k = 0.5 * smoothstep(1.0, 16.0, n);   // desaturare progresivă în lumini (HEURISTIC)
    for (int i = 0; i < 3; i++) { const double colored = c[i] * tn / n; out[i] = srgb_oetf(colored + k * (tn - colored)); }
}
/// ETAPA DE AJUSTARE (S1–S4): DWG liniar → instrumente liniare → cod DI → instrumente log → cod DI (fără DRT). Fiecare reglaj își calculează operația în domeniul lui, indiferent de grupare.
inline void adjust_lin(const Prepared& s, double lin[3], double code[3]) {
    linear_tools(s, lin);
    for (int i = 0; i < 3; i++) code[i] = fam_enc(s.f->curve, lin[i]);
    log_tools(s, code);
}
/// Intrarea unui pixel → scene-liniar în gamutul familiei (0: cod log al familiei · 1: liniar în gamutul familiei · 2: liniar DWG, convertit prin adaptorul familiei).
inline void input_lin(const Prepared& s, const float in[3], double lin[3]) {
    if (s.p.inputIsLinear == 2) { double v[3] = {fin(in[0]), fin(in[1]), fin(in[2])};
        if (s.p.chartOn) { const double* m = s.p.chartM; const double a = v[0], b = v[1], c = v[2]; v[0] = m[0] * a + m[1] * b + m[2] * c; v[1] = m[3] * a + m[4] * b + m[5] * c; v[2] = m[6] * a + m[7] * b + m[8] * c; }
        apply3(s.f->fromDwg, v, lin); }
    else if (s.p.inputIsLinear) for (int i = 0; i < 3; i++) lin[i] = fin(in[i]); else for (int i = 0; i < 3; i++) lin[i] = fam_dec(s.f->curve, fin(in[i]));
}
inline void input_code(const Prepared& s, const float in[3], double code[3]) {
    if (s.p.inputIsLinear) { double lin[3]; input_lin(s, in, lin); for (int i = 0; i < 3; i++) code[i] = fam_enc(s.f->curve, lin[i]); } else for (int i = 0; i < 3; i++) code[i] = fin(in[i]);
}
/// Ajustarea unui pixel de intrare (cod DI sau DWG liniar, conform Params::inputIsLinear) → cod DI ajustat.
inline void adjust_pixel(const Prepared& s, const float in[3], double code[3]) {
    double lin[3]; input_lin(s, in, lin);
    adjust_lin(s, lin, code);
}
/// Ajustare aplicată pe un cod DI deja ajustat (corecții locale): cod DI → liniar → aceleași instrumente → cod DI.
inline void adjust_code(const Prepared& s, const double in[3], double code[3]) {
    double lin[3]; for (int i = 0; i < 3; i++) lin[i] = fam_dec(s.f->curve, in[i]);
    adjust_lin(s, lin, code);
}
/// ETAPA DE AFIȘARE (S5): cod DI ajustat → GDC DRT (sau DRT p1 / cod DI) → codificare. Se aplică O SINGURĂ DATĂ, la capătul traseului, după toate ajustările (globale și locale).
inline void display_pixel(const Prepared& s, const double code[3], float out[3]) {
    if (s.p.drt == 2) {   // GDC DRT adaptat: cod DI → liniar DWG → nucleu autoritar (negativ → 0 la intrarea DRT) → recodare (o singură dată)
        double lf[3], l2[3], o[3]; for (int i = 0; i < 3; i++) lf[i] = fam_dec(s.f->curve, code[i]); apply3(s.f->toDwg, lf, l2);   // adaptorul de intrare al DRT: liniar familie → DWG liniar
#ifdef GDC_PC_PREMIUM
        if (drtReady()) { gdcdrt::core(drtData(), s.p.drtProfile, l2, o); for (int i = 0; i < 3; i++) out[i] = (float)gdcdrt::encode(s.p.drtOutput, o[i]); }
        else for (int i = 0; i < 3; i++) out[i] = std::nanf("");   // date indisponibile: fără rezervă tăcută (apelantul verifică drtReady() înainte)
#else
        (void)l2; (void)o; for (int i = 0; i < 3; i++) out[i] = std::nanf("");   // GDC DRT absent: apelantul verifică drtReady() înainte
#endif
    }
    else if (s.p.drt) { double o[3]; drt(s, code, o); for (int i = 0; i < 3; i++) out[i] = (float)o[i]; }
    else for (int i = 0; i < 3; i++) out[i] = (float)code[i];
}
/// Highlights + Gamut (V3): peste codul log al familiei (după toate instrumentele și corecțiile locale, ÎNAINTE de efecte și DRT). Legile din HighlightsGamutV3 (onset în stopuri față de 18%, nuanța păstrată, continuitate la identitate).
inline double hg_smooth(double a, double b, double x) { double t = (x - a) / (b - a); t = t != t ? t : (t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t)); return t * t * (3.0 - 2.0 * t); }
inline double hg_max(double x, double y) { return x != x ? x : (y != y ? y : (x > y ? x : y)); }
inline double hg_min(double x, double y) { return x != x ? x : (y != y ? y : (x < y ? x : y)); }
inline void highlights_gamut(const Prepared& s, double code[3]) {
    const Params& p = s.p; if (p.hgMix == 0 || (p.hgPathAmount == 0 && p.hgGamutAmount == 0 && p.hgHlAmount == 0)) return;
    const int cv = s.f->curve; const double* L = s.f->luma.data(); double r = fam_dec(cv, code[0]), g = fam_dec(cv, code[1]), b = fam_dec(cv, code[2]); bool changed = false;
    if (p.hgPathAmount > 0.0) { const double y = L[0] * r + L[1] * g + L[2] * b; const double st = y > 0.0 ? std::log2(y / 0.18) : -1.0e9; const double w = p.hgPathAmount * hg_smooth(p.hgPathOnset, p.hgPathOnset + 4.0, st);
        if (w > 0.0) { r += (y - r) * w; g += (y - g) * w; b += (y - b) * w; changed = true; } }
    if (p.hgGamutAmount > 0.0) { const double ach = hg_max(r, hg_max(g, b)), mn = hg_min(r, hg_min(g, b)); const double sc = hg_max(std::fabs(ach), 1.0 / 131072.0); const double d = (ach - mn) / sc, thr = p.hgGamutThreshold;
        if (d > thr) { const double cFull = thr + (d - thr) / (1.0 + (d - thr) / (1.0 - thr)); const double dOut = d + p.hgGamutAmount * (cFull - d), kappa = dOut / d; r = ach - kappa * (ach - r); g = ach - kappa * (ach - g); b = ach - kappa * (ach - b); changed = true; } }
    if (p.hgHlAmount > 0.0) { const double k = 0.18 * std::exp2(p.hgHlKnee); const double mx = hg_max(r, hg_max(g, b));
        if (mx > k) { const double over = mx - k; const double f = (k + over / (1.0 + p.hgHlAmount * over / (0.25 * k))) / mx; r *= f; g *= f; b *= f; changed = true; } }
    if (!changed) return;
    const double er = fam_enc(cv, r), eg = fam_enc(cv, g), eb = fam_enc(cv, b);
    code[0] = p.hgMix * er + (1.0 - p.hgMix) * code[0]; code[1] = p.hgMix * eg + (1.0 - p.hgMix) * code[1]; code[2] = p.hgMix * eb + (1.0 - p.hgMix) * code[2];
}
/// Pixel după rolul nodului (`Params::stage`): 0 complet · 1 liniar (→ cod DI) · 2 log (cod DI → cod DI) · 3 afișare (cod DI → GDC DRT → cod). Etapele 1–2 nu aplică niciodată DRT-ul; etapa 3 nu aplică nicio ajustare.
inline void process_pixel(const Prepared& s, const float in[3], float out[3]) {
    double code[3];
    switch (s.p.stage) {
    case 1: { double lin[3]; input_lin(s, in, lin);
              linear_tools(s, lin); for (int i = 0; i < 3; i++) out[i] = (float)fam_enc(s.f->curve, lin[i]); return; }
    case 2: input_code(s, in, code); log_tools(s, code); for (int i = 0; i < 3; i++) out[i] = (float)code[i]; return;
    case 3: input_code(s, in, code); display_pixel(s, code, out); return;
    default: adjust_pixel(s, in, code); highlights_gamut(s, code); display_pixel(s, code, out); }
}

// ---------- zone (mască manuală) pentru corecții locale ----------
/// Mască manuală în coordonate normalizate ale FOTOGRAFIEI (0…1 pe lățime/înălțime), definită vectorial (nu raster): aceeași definiție se evaluează la orice rezoluție (previzualizare, export), indiferent de zoom sau fereastră.
/// Zona simplă (legacy, `comps` gol): kind 0 = elipsă (x1,y1 = centru; x2,y2 = semiaxe ca fracții din lățime/înălțime), kind 1 = degrade liniar (x1,y1 = început, efect complet; x2,y2 = sfârșit, fără efect); feather 0…1; invert = complementul.
/// Mască compusă (`comps` nevid): componente aplicate ÎN ORDINE — adaugă (sub=0: m += (1−m)·c) sau scade (sub=1: m *= 1−c) — apoi `invert` pe întreaga mască. Componente: 0 elipsă (cu rotație `rot`, grade, sens orar pe ecran), 1 degrade, 2 contur închis (puncte x,y,neted; segmente
/// curbe Catmull-Rom→Bézier între puncte netede; margine estompată în pixeli, proporțională cu ÎNĂLȚIMEA imaginii), 3 pensulă (polilinie cu rază = fracție din înălțime și moliciune 0…1).
struct MaskComp { int kind = 0, sub = 0; double feather = 0.35, rot = 0, x1 = 0.5, y1 = 0.5, x2 = 0.25, y2 = 0.25, radius = 0.03, softness = 0.5; int closed = 0; std::vector<double> pts; };
struct Zone { int kind = 0; double x1 = 0.5, y1 = 0.5, x2 = 0.25, y2 = 0.25, feather = 0.35; int invert = 0; std::vector<MaskComp> comps; };
inline double edge_smooth(double a, double b, double x) { if (b - a < 1e-4) return x < 0.5 * (a + b) ? 0.0 : 1.0; return smoothstep(a, b, x); }
constexpr double kPathFeatherFrac = 0.12;   // feather = 1 ⇒ tranziție de 12% din înălțimea imaginii (contur/pensulă), în jurul marginii
inline double zone_mask(const Zone& z, double nx, double ny, double w, double h) {   // zona simplă (legacy), neschimbată
    const double f = std::min(1.0, std::max(0.0, z.feather)); double m;
    if (z.kind == 0) {   // elipsă: marginea desenată la d = 1, tranziția centrată pe ea
        const double rx = std::max(1e-4, z.x2), ry = std::max(1e-4, z.y2), dx = (nx - z.x1) / rx, dy = (ny - z.y1) / ry, d = std::sqrt(dx * dx + dy * dy);
        m = 1.0 - edge_smooth(1.0 - 0.5 * f, 1.0 + 0.5 * f, d);
    } else {             // degrade: t = 0 la început, 1 la sfârșit (în pixeli, izotrop); tranziția centrată la jumătatea segmentului
        const double ex = (z.x2 - z.x1) * w, ey = (z.y2 - z.y1) * h, L2 = ex * ex + ey * ey;
        const double t = L2 > 0 ? ((nx - z.x1) * w * ex + (ny - z.y1) * h * ey) / L2 : 0.0;
        m = 1.0 - edge_smooth(0.5 - 0.5 * f, 0.5 + 0.5 * f, t);
    }
    return z.invert ? 1.0 - m : m;
}
/// Componentă pregătită pentru o imagine w×h (geometria vectorială → segmente în pixeli, o singură dată per apel, apoi evaluare per pixel).
struct PComp { int kind = 0, sub = 0; double feather = 0, cosr = 1, sinr = 0, rot = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0, fpx = 0, r = 0, soft = 0, bx0 = 0, by0 = 0, bx1 = 0, by1 = 0; bool valid = true; std::vector<double> seg; };
struct PZone { Zone z; double w = 1, h = 1; std::vector<PComp> pc; };
inline void seg_push(std::vector<double>& s, double ax, double ay, double bx, double by) { s.push_back(ax); s.push_back(ay); s.push_back(bx); s.push_back(by); }
inline PComp prepare_comp(const MaskComp& c, double w, double h) {
    PComp p; p.kind = c.kind; p.sub = c.sub; p.feather = std::min(1.0, std::max(0.0, c.feather)); p.rot = c.rot; p.x1 = c.x1; p.y1 = c.y1; p.x2 = c.x2; p.y2 = c.y2;
    const double rr = c.rot * 3.14159265358979323846 / 180.0; p.cosr = std::cos(rr); p.sinr = std::sin(rr);
    const size_t n = c.pts.size() / 3;
    if (c.kind == 2) {
        if (!c.closed || n < 3) { p.valid = false; return p; }
        auto X = [&](size_t i) { return c.pts[3 * (i % n)] * w; }; auto Y = [&](size_t i) { return c.pts[3 * (i % n) + 1] * h; }; auto S = [&](size_t i) { return c.pts[3 * (i % n) + 2] > 0.5; };
        auto T = [&](size_t i, double& tx, double& ty) { if (!S(i)) { tx = ty = 0; return; } const size_t pr = (i + n - 1) % n, nx = (i + 1) % n; tx = (X(nx) - X(pr)) / 6.0; ty = (Y(nx) - Y(pr)) / 6.0; };
        for (size_t i = 0; i < n; i++) {
            const size_t j = (i + 1) % n;
            if (!S(i) && !S(j)) { seg_push(p.seg, X(i), Y(i), X(j), Y(j)); continue; }
            double t0x, t0y, t1x, t1y; T(i, t0x, t0y); T(j, t1x, t1y);
            const double c1x = X(i) + t0x, c1y = Y(i) + t0y, c2x = X(j) - t1x, c2y = Y(j) - t1y; double px = X(i), py = Y(i);
            for (int k = 1; k <= 16; k++) { const double t = k / 16.0, u = 1 - t, b0 = u * u * u, b1 = 3 * u * u * t, b2 = 3 * u * t * t, b3 = t * t * t;
                const double qx = b0 * X(i) + b1 * c1x + b2 * c2x + b3 * X(j), qy = b0 * Y(i) + b1 * c1y + b2 * c2y + b3 * Y(j); seg_push(p.seg, px, py, qx, qy); px = qx; py = qy; }
        }
        p.fpx = p.feather * kPathFeatherFrac * h;
    } else if (c.kind == 3) {
        if (n < 1) { p.valid = false; return p; }
        p.r = std::max(0.0, c.radius) * h; p.soft = std::min(1.0, std::max(0.0, c.softness));
        if (n == 1) seg_push(p.seg, c.pts[0] * w, c.pts[1] * h, c.pts[0] * w, c.pts[1] * h);
        for (size_t i = 0; i + 1 < n; i++) seg_push(p.seg, c.pts[3 * i] * w, c.pts[3 * i + 1] * h, c.pts[3 * (i + 1)] * w, c.pts[3 * (i + 1) + 1] * h);
        p.fpx = 0;
    }
    if (!p.seg.empty()) { p.bx0 = p.bx1 = p.seg[0]; p.by0 = p.by1 = p.seg[1]; for (size_t i = 0; i < p.seg.size(); i += 2) { p.bx0 = std::min(p.bx0, p.seg[i]); p.bx1 = std::max(p.bx1, p.seg[i]); p.by0 = std::min(p.by0, p.seg[i + 1]); p.by1 = std::max(p.by1, p.seg[i + 1]); } }
    return p;
}
inline PZone prepare_zone(const Zone& z, double w, double h) { PZone r; r.z = z; r.w = w; r.h = h; for (const MaskComp& c : z.comps) r.pc.push_back(prepare_comp(c, w, h)); return r; }
inline double comp_value(const PComp& c, double nx, double ny, double w, double h) {
    if (!c.valid) return 0.0;
    const double f = c.feather;
    if (c.kind == 0) {
        if (c.rot == 0.0) { const double rx = std::max(1e-4, c.x2), ry = std::max(1e-4, c.y2), dx = (nx - c.x1) / rx, dy = (ny - c.y1) / ry, d = std::sqrt(dx * dx + dy * dy); return 1.0 - edge_smooth(1.0 - 0.5 * f, 1.0 + 0.5 * f, d); }
        const double dx = (nx - c.x1) * w, dy = (ny - c.y1) * h, u = dx * c.cosr + dy * c.sinr, v = -dx * c.sinr + dy * c.cosr;   // axele elipsei în pixeli (izotrop): rotația nu depinde de raportul fotografiei
        const double a = std::max(1e-4, c.x2 * w), b = std::max(1e-4, c.y2 * h), d = std::sqrt((u / a) * (u / a) + (v / b) * (v / b)); return 1.0 - edge_smooth(1.0 - 0.5 * f, 1.0 + 0.5 * f, d);
    }
    if (c.kind == 1) {
        const double ex = (c.x2 - c.x1) * w, ey = (c.y2 - c.y1) * h, L2 = ex * ex + ey * ey; const double t = L2 > 0 ? ((nx - c.x1) * w * ex + (ny - c.y1) * h * ey) / L2 : 0.0; return 1.0 - edge_smooth(0.5 - 0.5 * f, 0.5 + 0.5 * f, t);
    }
    const double px = nx * w, py = ny * h; const double pad = c.kind == 2 ? 0.5 * c.fpx : c.r;
    if (px < c.bx0 - pad || px > c.bx1 + pad || py < c.by0 - pad || py > c.by1 + pad) return 0.0;
    double d2 = 1e300; bool inside = false;
    for (size_t i = 0; i < c.seg.size(); i += 4) {
        const double ax = c.seg[i], ay = c.seg[i + 1], bx = c.seg[i + 2], by = c.seg[i + 3], ex = bx - ax, ey = by - ay, L2 = ex * ex + ey * ey;
        double t = L2 > 0 ? ((px - ax) * ex + (py - ay) * ey) / L2 : 0.0; t = std::min(1.0, std::max(0.0, t)); const double qx = ax + t * ex - px, qy = ay + t * ey - py; d2 = std::min(d2, qx * qx + qy * qy);
        if (c.kind == 2 && ((ay > py) != (by > py)) && px < ex * (py - ay) / (by - ay) + ax) inside = !inside;
    }
    const double d = std::sqrt(d2);
    if (c.kind == 3) return 1.0 - edge_smooth(c.r * (1.0 - c.soft), c.r, d);
    const double sd = inside ? -d : d; if (c.fpx < 1e-6) return inside ? 1.0 : 0.0; return 1.0 - edge_smooth(-0.5 * c.fpx, 0.5 * c.fpx, sd);
}
inline double zone_value(const PZone& z, double nx, double ny) {
    if (z.pc.empty()) return zone_mask(z.z, nx, ny, z.w, z.h);
    double m = 0.0;
    for (const PComp& c : z.pc) { const double v = comp_value(c, nx, ny, z.w, z.h); if (c.sub == 0) m = m + (1.0 - m) * v; else m = m * (1.0 - v); }
    return z.z.invert ? 1.0 - m : m;
}
/// Corecție locală = zonă + un set de reglaje (aceleași instrumente ca cele globale, în aceleași domenii) + activare. Se aplică pe codul DI ajustat; DRT-ul NU intră aici.
struct Local { bool enabled = true; Zone zone; Params adj; };
struct PreparedLocal { PZone zone; Prepared prep; };
inline std::vector<PreparedLocal> prepare_locals(const std::vector<Local>& ls, double w, double h) {
    std::vector<PreparedLocal> r;
    for (const Local& l : ls) { if (!l.enabled) continue; Params q = l.adj; q.inputIsLinear = 0; q.drt = 0; r.push_back({prepare_zone(l.zone, w, h), prepare(q)}); }
    return r;
}
/// Pixel cu corecții locale: ajustare globală → pentru fiecare zonă: cod += m·(cod_local − cod) în domeniul DI (ambele ajustate, niciodată pixeli neprocesați amestecați cu pixeli redați) → afișare o singură dată.
inline void process_pixel_local(const Prepared& g, const std::vector<PreparedLocal>& ls, const float in[3], double nx, double ny, double /*w*/, double /*h*/, float out[3]) {
    double code[3]; adjust_pixel(g, in, code);
    for (const PreparedLocal& l : ls) {
        const double m = zone_value(l.zone, nx, ny); if (m <= 0) continue;
        double c2[3]; adjust_code(l.prep, code, c2); for (int i = 0; i < 3; i++) code[i] += m * (c2[i] - code[i]);
    }
    highlights_gamut(g, code);
    display_pixel(g, code, out);
}

} // namespace pc

namespace pc {
/// Rând RGBA float32 (alfa copiat neschimbat; RGB = intrarea în domeniul declarat de Params::inputIsLinear). Folosit de OFX; aceeași matematică ca `process_pixel`.
inline void process_rgba_row(const Prepared& s, const float* in, float* out, int count) {
    for (int x = 0; x < count; x++) { float o[3]; process_pixel(s, in + 4 * x, o); out[4 * x] = o[0]; out[4 * x + 1] = o[1]; out[4 * x + 2] = o[2]; out[4 * x + 3] = in[4 * x + 3]; }
}
inline bool extras_neutral(const Params& p) {
    Params d; if (p.black != d.black || p.midtones != d.midtones || p.shadowsTemp != 0 || p.shadowsTint != 0 || p.highlightsTemp != 0 || p.highlightsTint != 0 || p.printerMaster != 0 || p.printerR != 0 || p.printerG != 0 || p.printerB != 0 || p.cmKeepNeutrals != 0) return false;
    for (int i = 0; i < 18; i++) if (p.hv[i] != d.hv[i]) return false;
    for (int i = 0; i < 9; i++) if (p.cm[i] != d.cm[i]) return false; if (p.ebMix != 1 || p.hueRotate != 0 || p.hsvSat != 1 || p.hsvVal != 1 || p.shMix != 1 || p.lift != 0 || p.gamma != 1 || p.gain != 1 || p.toneMix != 1 || p.cdlSat != 1 || p.hgPathAmount != 0 || p.hgGamutAmount != 0 || p.hgHlAmount != 0 || p.hgMix != 1 || p.chartOn != 0 || p.opDiffusion != 0 || p.opBloom != 0 || p.colorActive != 0 || p.cAmount != 1 || p.skAmount != 1 || p.skEven != 0 || p.skHue != 0 || p.skWarm != 0 || p.skTint != 0 || p.skVivid != 0 || p.skRich != 0 || p.skBright != 0) return false;
    for (int i = 0; i < 12; i++) if (p.wheels[i] != 0) return false; for (int i = 0; i < 3; i++) if (p.slope[i] != 1 || p.offset[i] != 0 || p.power[i] != 1) return false; return true;
}
inline bool is_identity(const Params& p) {
    if (!extras_neutral(p)) return false;   // DRT oprit (ieșire cod DI) + totul neutru + intrare DI ⇒ ieșire = intrare
    if (p.inputIsLinear) return false;
    if (p.stage == 1) return p.exposure == 0 && p.temperature == 0 && p.tint == 0 && p.shadows == 0 && p.highlights == 0;
    if (p.stage == 2) return p.contrast == 1 && p.saturation == 1;
    if (p.stage == 3) return p.drt == 0;
    return p.drt == 0 && p.exposure == 0 && p.temperature == 0 && p.tint == 0 && p.shadows == 0 && p.highlights == 0 && p.contrast == 1 && p.saturation == 1;
}
} // namespace pc
