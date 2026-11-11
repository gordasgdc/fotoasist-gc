#ifndef PHOTOCORE_H
#define PHOTOCORE_H
#ifdef __cplusplus
extern "C" {
#endif
/// GDC Photo Develop — interfața C a nucleului fotografic propriu (vezi photo_develop.hpp pentru contract).
typedef struct {
    double exposure, temperature, tint, shadows, highlights, contrast, pivot, saturation;
    int inputIsLinear;  // 0 = cod log al familiei, 1 = scene-liniar în gamutul familiei, 2 = scene-liniar DWG (convertit în gamutul familiei)
    int drt;            // 0 = cod DI · 1 = DRT p1 (PROTOTIP experimental, NU GDC DRT) · 2 = GDC DRT adaptat (date încărcate cu pc_drt_load)
    int drtProfile;     // drt = 2: 0 Natural
    int drtOutput;      // drt = 2: codificarea ieșirii 0 g2.4 · 1 g2.2 · 2 sRGB
    int family;         // familia de lucru: 0 DWG/DI (implicit) · 1 ACES AP1/ACEScct · 2 ARRI AWG3/LogC3 EI800 · 3 ARRI AWG4/LogC4
    int stage;          // 0 traseu complet · 1 doar liniar (→ cod DI) · 2 doar log (cod DI → cod DI) · 3 doar afișare (cod DI → GDC DRT → cod)
    /// Exposure + Balance V3 (referința STYLE ComposedToolsV3; SPEC §23): negru, mijloc (+gardă), Tonal Balance, Printer Lights, Channel Mix, Mix.
    double black, midtones, shadowsTemp, shadowsTint, highlightsTemp, highlightsTint, printerMaster, printerR, printerG, printerB;
    double cm[9]; int cmKeepNeutrals; double ebMix;
    /// Saturation + Hue V3 (Hue/HSV, Mix) și Tone V3 (LGG → Wheels → CDL; contrast/pivot sunt câmpurile de mai sus).
    double hueRotate, hsvSat, hsvVal, shMix;
    double hvWidth, hv[18], hvMix;   // Hue Vectors (230)
    double lift, gamma, gain, shadowLimit, highlightStart; double wheels[12]; double slope[3], offset[3], power[3]; double cdlSat; double toneMix;
    /// Highlights + Gamut V3 (HighlightsGamutV3): Path to White (amount, onset st), Gamut Compression (amount, threshold), Highlight Roll-off (amount, knee st), Mix.
    /// Color (ColorV3) și Skin (SkinV3): selecție din culoare în OKLab (LogViaLinear), pe codul log al familiei.
    double colorActive, colorHue, colorC, colorL, colorRange, colorSoft, colorSatRange, colorLumRange, cHue, cSat, cDensity, cLum, cWarm, cSkinProt, cNeutralProt, cAmount;
    double skRange, skShadows, skEdge, skEven, skHue, skWarm, skTint, skVivid, skRich, skBright, skAmount;
    int lookOn, lookIndex; double lookStrength, lookProtect, lookContrast, lookBlacks, lookRoll, lookSat, lookWarm, lookColor;   // Look (FIELD): rețetă + trims + protecție + strength; cod log, după Color/Skin
    /// Optics V3 (difuzie + bloom): filtru 0…6, treaptă 0…4, cantitate difuzie, prag bloom (stopuri), mărime, cantitate bloom, Mix.
    double opFilter, opStrength, opDiffusion, opThreshold, opSize, opBloom, opMix;
    /// Corecție tehnică după chart: matrice 3×3 rând-major în DWG liniar (identitate când chartOn = 0), aplicată la intrarea lanțului (doar inputIsLinear = 2).
    int chartOn; double chartM[9];
    double hgPathAmount, hgPathOnset, hgGamutAmount, hgGamutThreshold, hgHlAmount, hgHlKnee, hgMix;
} pc_params;
void pc_default_params(pc_params* p);
/// Referință ColorChecker → DWG liniar (D65): Lab D50 (2°) → XYZ D50 → Bradford D50→D65 → DaVinci Wide Gamut liniar. `pc_dwg_to_lab_d50` e inversa (pentru ΔE).
void pc_chart_reference_dwg(const double lab[3], double out[3]);
void pc_dwg_to_lab_d50(const double dwg[3], double lab[3]);
/// Ponderea de selecție [0,1] a unui pixel (cod log al familiei) pentru Color / Skin (ce arată «Evidențiere»/«Matte»); 0 dacă selecția nu e activă.
double pc_color_weight(const pc_params* p, const double code[3]);
double pc_skin_weight(const pc_params* p, const double code[3]);
/// Pick: culoarea din pixelul eșantionat (cod log al familiei) → centrul selecției (nuanță°, croma relativă, luminanță în stopuri). 1 = valid; 0 = gri/non-finit (nuanța e zgomot).
typedef struct { int valid, hasRange; double hue, c, l, range, satRange, lumRange; int samples, chromatic, used; } pc_range_pick;
/// Pick Range: `codes` = n×3 coduri log ale familiei (≤512 folosite). Port din ColorV3 (mean-shift + MAD + percentile 5–95).
void pc_color_pick_range(int family, const double* codes, int n, pc_range_pick* out);
int pc_look_count(void);
const char* pc_look_name(int i);
int pc_color_pick(int family, const double code[3], double* hue, double* c, double* l);
/// Codul log al familiei al unui pixel scene-liniar (DWG) DUPĂ toate instrumentele globale, FĂRĂ Color/Skin (intrarea lor) — de aici se face Pick-ul și matte-ul.
void pc_color_stage_code(const pc_params* p, const float linDwg[3], double out[3]);
/// Zonă manuală pentru corecții locale (coordonate normalizate 0…1). kind 0 = elipsă (x1,y1 centru; x2,y2 semiaxe ca fracții din lățime/înălțime) · 1 = degrade liniar (x1,y1 început, efect complet; x2,y2 sfârșit, fără efect). feather 0…1; invert 0/1.
typedef struct { int kind; double x1, y1, x2, y2, feather; int invert; } pc_zone;
/// Corecție locală: zonă + reglaje (aceleași instrumente ca cele globale; `adj.inputIsLinear`/`drt` sunt ignorate) + activare.
typedef struct { int enabled; pc_zone zone; pc_params adj; } pc_local;
void pc_default_zone(pc_zone* z);
/// Procesează o imagine RGB float32 intercalată (în → out; pot fi același buffer). `threads` ≤ 0 = automat.
/// Întoarce 0 la succes; 2 dacă drt = 2 și datele GDC DRT nu sunt încărcate (nu se scrie nimic).
int pc_process_image(const pc_params* p, const float* in, float* out, int width, int height, int threads);
/// Ca `pc_process_image`, cu corecții locale: ajustare globală → fiecare zonă amestecă în domeniul cod DI (ambele ajustate) → GDC DRT o singură dată. n = 0 ⇒ identic bit cu `pc_process_image`.
int pc_process_image_local(const pc_params* global, const pc_local* locals, int n, const float* in, float* out, int width, int height, int threads);
/// Ca `pc_process_image_local`, cu MĂȘTI COMPUSE: `maskData` = date plate (vezi `pc_mask_image_data`) pentru toate corecțiile, concatenate; `maskOffsets` (n+1 valori) = începutul datelor fiecărei corecții (interval gol ⇒ zona simplă din `zone`). Pentru o componentă elipsă fără rotație rezultatul e identic bit cu bit cu zona simplă.
int pc_process_image_masks(const pc_params* global, const pc_local* locals, int n, const double* maskData, const long* maskOffsets, const float* in, float* out, int width, int height, int threads);
/// Geometrie: `h` = hartă omogenă 3×3 (rând-major) ieșire→sursă în PIXELI (centre de pixel); ieșirea outW×outH; sursa srcW×srcH (RGB float32 liniar). Returnează 0 / 1 (parametri invalizi) / 2 (DRT neîncărcat).
typedef struct { double h[9]; int srcW, srcH, outW, outH; } pc_geom;
int pc_process_image_geom(const pc_params* global, const pc_local* locals, int n, const double* maskData, const long* maskOffsets, const pc_geom* geo, const float* in, float* out, int threads);
void pc_mask_image_geom(const pc_zone* z, const double* maskData, long count, const pc_geom* geo, float* out, int width, int height);
int pc_resample_geom(const pc_geom* geo, const float* in, float* out, int threads);
/// Efecte fotografice (Optică, Peliculă, Grain) — vezi photo_fx.hpp pentru contract și modele. Toate neutre la `pc_default_fx` (identitate exactă).
typedef struct {
    double distortion, caRed, caBlue, lensVignette;                    // Optică: −100…100 (distorsiune: + corectează butoi / − pernuță)
    double vignette, vignetteMid, vignetteRound;                       // vinietă creativă: −100…100 (− întunecă), început 0…100 % din rază
    double halAmount, halRadius, halThreshold, halWarm;                // halație (SPEC §22): 0…100 · 1…10 · 0…4 stopuri · 0…1
    double filmAmount, filmContrast, filmToe, filmShoulder, filmSat, filmCrosstalk;   // 0…100 · −0.5…0.5 · 0…1 · 0…1 · 0.5…1.5 · 0…0.3
    double grainAmount, grainSize, grainRough, grainChroma, grainShadows, grainHighlights; int grainSeed, grainRef;   // 0…100 · px la înălțimea de referință · 0…1 · 0…1 (0 = monocrom) · 0…2 · 0…2 · sămânță · înălțime de referință (2160)
} pc_fx;
/// Matte-ul selecției Color (which = 0) sau Skin (which = 1) pe grila ieșirii geometriei (vedere): aceeași hartă ca procesarea. out = outW×outH valori [0,1].
int pc_selection_matte_view(const pc_params* p, int which, const pc_geom* geo, const float* in, float* out, int threads);
void pc_default_fx(pc_fx* f);
void pc_optics_apply(const pc_params* p, float* rgb, int w, int h);
int pc_process_image_fx(const pc_params* global, const pc_local* locals, int n, const double* maskData, const long* maskOffsets, const pc_geom* geo, const pc_fx* fx, const float* in, float* out, int threads);
/// Film V3 (port din GDC STYLE, motor fotochimic partajat; vezi docs/ADAPTATION_MANIFEST.md): lanț la nivel de CADRU, după toate ajustările și înaintea DRT. `on` = 0 ⇒ identic bit cu fără film.
typedef struct {
    int on, negStock, printStock;
    double colourSeparation, negContrast, printContrast, exposure, lightsMaster, lightsR, lightsG, lightsB;
    double grainShadows, grainHighlights, grainAmount, grainSize, mtfAmount, halationAmount, halationRadiusMm;
    int grainAnimate; double grainSeed, frame, formatWidthMm, mix; int mtfEnabled, halationEnabled, grainEnabled;
} pc_film3;
void pc_default_film3(pc_film3* f);
int pc_film3_stock_count(void); const char* pc_film3_stock_label(int i); const char* pc_film3_stock_info(int i);
int pc_film3_print_count(void); const char* pc_film3_print_label(int i);
int pc_film3_format_count(void); int pc_film3_format_default(void); const char* pc_film3_format_label(int i); double pc_film3_format_gate(int i);
/// Valorile de pornire ale formatului: out[5] = grăunte (×S35), softness (×S35), halație (% cadru), grăunte amount, halație amount; set[5] = 1 dacă formatul le mută.
void pc_film3_format_start(int i, double out[5], int set[5]);
/// Aplică formatul pe parametri (poartă + valorile de pornire legate), ca `filmV3ApplyFormat`.
void pc_film3_apply_format(pc_film3* f, int format);
/// Cadru de coduri log ale familiei (RGB float, pe loc), pentru teste și instrumente. 0 = ok.
int pc_film3_frame(const pc_film3* f, int family, float* codes, int w, int h, int threads);
/// GDC Cinema Style (86 de stiluri în 4 straturi + textură opțională): modelele se încarcă o dată din `film_models.gdcfilm` (resursă). Aplicat înaintea Film V3, după ajustări, înaintea DRT.
typedef struct { int on, layers; double layerMix[4]; int layerStock[4]; double exposure, contrast, density, warmth, tint, saturation, amount; pc_film3 texture; double mix; } pc_cinema;
void pc_default_cinema(pc_cinema* c);
int pc_cinema_load(const char* path);                       // 0 = ok
int pc_cinema_ready(void);
int pc_cinema_style_count(void);
const char* pc_cinema_style_id(int i); const char* pc_cinema_style_name(int i); const char* pc_cinema_style_category(int i);
void pc_cinema_style_info(int i, int* layer, int* layerIndex, int* stockIndex);
int pc_cinema_frame(const pc_cinema* c, int family, float* codes, int w, int h, int threads);
int pc_process_image_fx4(const pc_params* global, const pc_local* locals, int n, const double* maskData, const long* maskOffsets, const pc_geom* geo, const pc_fx* fx, const pc_film3* film, const pc_cinema* cinema, const float* in, float* out, int threads);
int pc_process_image_fx3(const pc_params* global, const pc_local* locals, int n, const double* maskData, const long* maskOffsets, const pc_geom* geo, const pc_fx* fx, const pc_film3* film, const float* in, float* out, int threads);
int pc_resample_fx(const pc_geom* geo, const pc_fx* fx, const float* in, float* out, int threads);
void pc_mask_image_geom_fx(const pc_zone* z, const double* maskData, long count, const pc_geom* geo, const pc_fx* fx, float* out, int width, int height);
void pc_fx_distort(const pc_fx* fx, int srcW, int srcH, double x, double y, double* ox, double* oy);
void pc_fx_undistort(const pc_fx* fx, int srcW, int srcH, double x, double y, double* ox, double* oy);
/// Valorile măștii compuse [0,1] pe o grilă. Date: [1 (versiune), nComp, apoi pe componentă: kind (0 elipsă, 1 degrade, 2 contur închis, 3 pensulă), sub (0 adaugă, 1 scade), feather, rot (grade, sens orar), x1, y1, x2, y2, radius (pensulă; fracție din înălțime), softness, closed, nPuncte, nPuncte×(x, y, neted 0/1)]; `z->invert` se aplică întregii măști. Aceeași funcție ca la procesare.
void pc_mask_image_data(const pc_zone* z, const double* maskData, long count, float* out, int width, int height);
/// Valorile măștii [0,1] pe o grilă width×height (pentru afișarea zonei).
void pc_mask_image(const pc_zone* z, float* out, int width, int height);
/// Încarcă datele GDC DRT (conținutul fișierului drt_1.bin). 0 = ok. Stratul Swift verifică SHA-256 înainte.
int pc_drt_load(const unsigned char* bytes, unsigned long size, char* err, int errLen);
int pc_drt_available(void);
/// Teste: nucleul GDC DRT (DWG-liniar → cod g2.4) și funcția de codificare a ieșirii.
int pc_gdc_drt_core(int profile, const double rgb[3], double out[3]);
double pc_gdc_drt_encode(int output, double code24);
void pc_process_pixel_c(const pc_params* p, const float in[3], float out[3]);
/// Etape izolate (testare / comparații): S1 decodare DI, S3 codare DI, curba neutră a DRT-ului, balans (matrice 3×3 rând-major în DWG liniar).
double pc_di_decode(double code);
double pc_di_encode(double lin);
double pc_tone_scale(double x);
void pc_balance_matrix(double temperatureMired, double tint, double out9[9]);
const char* pc_version(void);
/// 1 = ediția completă GDC; 0 = ediția cu sursă deschisă (fără GDC DRT, Color/Skin selectiv, Optics, Film V3, Look, Cinema Style).
int pc_edition_full(void);
/// Familii de lucru (inventar STYLE): număr, identificator tehnic și etichetă; conversii pe valori scene-liniare/cod (teste, intermediar EXR).
int pc_family_count(void);
const char* pc_family_id(int family);
const char* pc_family_label(int family);
/// Convertește `count` pixeli RGB scene-liniari DWG → scene-liniari în gamutul familiei (float32 intercalat; pot fi același buffer).
void pc_convert_dwg_to_family(int family, const float* in, float* out, long count);
/// Cod log al familiei ↔ scene-liniar în gamutul familiei (pe un canal).
double pc_family_encode(int family, double linear);
double pc_family_decode(int family, double code);
/// Coeficienții de luminanță ai familiei (rândul Y al RGB→XYZ).
void pc_family_luma(int family, double out3[3]);
typedef struct { int on; double sharpAmount, sharpRadius, sharpThreshold, clarity, nrLuma, nrChroma; } pc_detail;   // radius în ‰ din înălțime; nrLuma/nrChroma 0…1
int pc_detail_apply(const pc_detail* d, float* rgb, int w, int h, int threads);
/// Retuș punctual (clone / heal) pe imaginea liniară DWG, ÎNAINTE de orice instrument și de geometrie (coordonate normalizate ale sursei; rază = fracție din înălțime).
typedef struct { int mode; int enabled; double x, y, sx, sy, radius, feather; } pc_spot;   // mode 0 = clone, 1 = heal
int pc_retouch_apply(const pc_spot* spots, int n, float* rgb, int w, int h);
#ifdef __cplusplus
}
#endif
#endif
