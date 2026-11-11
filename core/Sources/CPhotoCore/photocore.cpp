#include "photocore.h"
#include "photo_develop.hpp"
#include "photo_fx.hpp"
#ifdef GDC_PC_PREMIUM
#include "style_optics.hpp"
#include "film3/film3_frame.hpp"
#include "film3/cinema.hpp"
#endif
#include <cstring>
#include <functional>
#include <thread>
#include <vector>

static pc::Params toParams(const pc_params* p) {
    pc::Params q; q.exposure = p->exposure; q.temperature = p->temperature; q.tint = p->tint; q.shadows = p->shadows; q.highlights = p->highlights; q.contrast = p->contrast; q.pivot = p->pivot; q.saturation = p->saturation;
    q.inputIsLinear = p->inputIsLinear; q.drt = p->drt; q.drtProfile = p->drtProfile; q.drtOutput = p->drtOutput; q.stage = p->stage; q.family = p->family;
    q.black = p->black; q.midtones = p->midtones; q.shadowsTemp = p->shadowsTemp; q.shadowsTint = p->shadowsTint; q.highlightsTemp = p->highlightsTemp; q.highlightsTint = p->highlightsTint; q.printerMaster = p->printerMaster; q.printerR = p->printerR; q.printerG = p->printerG; q.printerB = p->printerB;
    for (int i = 0; i < 9; i++) q.cm[i] = p->cm[i]; q.cmKeepNeutrals = p->cmKeepNeutrals; q.ebMix = p->ebMix; q.hueRotate = p->hueRotate; q.hsvSat = p->hsvSat; q.hsvVal = p->hsvVal; q.shMix = p->shMix;
    q.lift = p->lift; q.gamma = p->gamma; q.gain = p->gain; q.shadowLimit = p->shadowLimit; q.highlightStart = p->highlightStart; for (int i = 0; i < 12; i++) q.wheels[i] = p->wheels[i];
    for (int i = 0; i < 3; i++) { q.slope[i] = p->slope[i]; q.offset[i] = p->offset[i]; q.power[i] = p->power[i]; } q.cdlSat = p->cdlSat; q.toneMix = p->toneMix;
    q.hvWidth = p->hvWidth; q.hvMix = p->hvMix; for (int i = 0; i < 18; i++) q.hv[i] = p->hv[i];
    q.lookOn = p->lookOn; q.lookIndex = p->lookIndex; q.lookStrength = p->lookStrength; q.lookProtect = p->lookProtect; q.lookContrast = p->lookContrast; q.lookBlacks = p->lookBlacks; q.lookRoll = p->lookRoll; q.lookSat = p->lookSat; q.lookWarm = p->lookWarm; q.lookColor = p->lookColor;
    q.colorActive = p->colorActive; q.colorHue = p->colorHue; q.colorC = p->colorC; q.colorL = p->colorL; q.colorRange = p->colorRange; q.colorSoft = p->colorSoft; q.colorSatRange = p->colorSatRange; q.colorLumRange = p->colorLumRange; q.cHue = p->cHue; q.cSat = p->cSat; q.cDensity = p->cDensity; q.cLum = p->cLum; q.cWarm = p->cWarm; q.cSkinProt = p->cSkinProt; q.cNeutralProt = p->cNeutralProt; q.cAmount = p->cAmount; q.skRange = p->skRange; q.skShadows = p->skShadows; q.skEdge = p->skEdge; q.skEven = p->skEven; q.skHue = p->skHue; q.skWarm = p->skWarm; q.skTint = p->skTint; q.skVivid = p->skVivid; q.skRich = p->skRich; q.skBright = p->skBright; q.skAmount = p->skAmount;
    q.opFilter = p->opFilter; q.opStrength = p->opStrength; q.opDiffusion = p->opDiffusion; q.opThreshold = p->opThreshold; q.opSize = p->opSize; q.opBloom = p->opBloom; q.opMix = p->opMix;
    q.chartOn = p->chartOn; for (int i = 0; i < 9; i++) q.chartM[i] = p->chartM[i];
    q.hgPathAmount = p->hgPathAmount; q.hgPathOnset = p->hgPathOnset; q.hgGamutAmount = p->hgGamutAmount; q.hgGamutThreshold = p->hgGamutThreshold; q.hgHlAmount = p->hgHlAmount; q.hgHlKnee = p->hgHlKnee; q.hgMix = p->hgMix; return q;
}
static pc::Zone toZone(const pc_zone& z) { pc::Zone r; r.kind = z.kind; r.x1 = z.x1; r.y1 = z.y1; r.x2 = z.x2; r.y2 = z.y2; r.feather = z.feather; r.invert = z.invert; return r; }
extern "C" {
void pc_default_zone(pc_zone* z) { pc::Zone d; z->kind = d.kind; z->x1 = d.x1; z->y1 = d.y1; z->x2 = d.x2; z->y2 = d.y2; z->feather = d.feather; z->invert = d.invert; }
void pc_default_params(pc_params* p) { pc::Params d; p->exposure = d.exposure; p->temperature = d.temperature; p->tint = d.tint; p->shadows = d.shadows; p->highlights = d.highlights; p->contrast = d.contrast; p->pivot = d.pivot; p->saturation = d.saturation; p->inputIsLinear = d.inputIsLinear; p->drt = d.drt; p->drtProfile = d.drtProfile; p->drtOutput = d.drtOutput;  p->stage = d.stage; p->family = d.family;
    p->black = d.black; p->midtones = d.midtones; p->shadowsTemp = d.shadowsTemp; p->shadowsTint = d.shadowsTint; p->highlightsTemp = d.highlightsTemp; p->highlightsTint = d.highlightsTint; p->printerMaster = d.printerMaster; p->printerR = d.printerR; p->printerG = d.printerG; p->printerB = d.printerB;
    for (int i = 0; i < 9; i++) p->cm[i] = d.cm[i]; p->cmKeepNeutrals = d.cmKeepNeutrals; p->ebMix = d.ebMix; p->hueRotate = d.hueRotate; p->hsvSat = d.hsvSat; p->hsvVal = d.hsvVal; p->shMix = d.shMix;
    p->lift = d.lift; p->gamma = d.gamma; p->gain = d.gain; p->shadowLimit = d.shadowLimit; p->highlightStart = d.highlightStart; for (int i = 0; i < 12; i++) p->wheels[i] = d.wheels[i];
    for (int i = 0; i < 3; i++) { p->slope[i] = d.slope[i]; p->offset[i] = d.offset[i]; p->power[i] = d.power[i]; } p->cdlSat = d.cdlSat; p->toneMix = d.toneMix;
    p->hvWidth = d.hvWidth; p->hvMix = d.hvMix; for (int i = 0; i < 18; i++) p->hv[i] = d.hv[i];
    p->lookOn = d.lookOn; p->lookIndex = d.lookIndex; p->lookStrength = d.lookStrength; p->lookProtect = d.lookProtect; p->lookContrast = d.lookContrast; p->lookBlacks = d.lookBlacks; p->lookRoll = d.lookRoll; p->lookSat = d.lookSat; p->lookWarm = d.lookWarm; p->lookColor = d.lookColor;
    p->colorActive = d.colorActive; p->colorHue = d.colorHue; p->colorC = d.colorC; p->colorL = d.colorL; p->colorRange = d.colorRange; p->colorSoft = d.colorSoft; p->colorSatRange = d.colorSatRange; p->colorLumRange = d.colorLumRange; p->cHue = d.cHue; p->cSat = d.cSat; p->cDensity = d.cDensity; p->cLum = d.cLum; p->cWarm = d.cWarm; p->cSkinProt = d.cSkinProt; p->cNeutralProt = d.cNeutralProt; p->cAmount = d.cAmount; p->skRange = d.skRange; p->skShadows = d.skShadows; p->skEdge = d.skEdge; p->skEven = d.skEven; p->skHue = d.skHue; p->skWarm = d.skWarm; p->skTint = d.skTint; p->skVivid = d.skVivid; p->skRich = d.skRich; p->skBright = d.skBright; p->skAmount = d.skAmount;
    p->opFilter = d.opFilter; p->opStrength = d.opStrength; p->opDiffusion = d.opDiffusion; p->opThreshold = d.opThreshold; p->opSize = d.opSize; p->opBloom = d.opBloom; p->opMix = d.opMix;
    p->chartOn = d.chartOn; for (int i = 0; i < 9; i++) p->chartM[i] = d.chartM[i];
    p->hgPathAmount = d.hgPathAmount; p->hgPathOnset = d.hgPathOnset; p->hgGamutAmount = d.hgGamutAmount; p->hgGamutThreshold = d.hgGamutThreshold; p->hgHlAmount = d.hgHlAmount; p->hgHlKnee = d.hgHlKnee; p->hgMix = d.hgMix; }
void pc_process_pixel_c(const pc_params* p, const float in[3], float out[3]) { const pc::Prepared s = pc::prepare(toParams(p)); pc::process_pixel(s, in, out); }
int pc_process_image(const pc_params* p, const float* in, float* out, int width, int height, int threads) {
    if (p->drt == 2 && !pc::drtReady()) return 2;
    const pc::Prepared s = pc::prepare(toParams(p)); if (width <= 0 || height <= 0) return 0;
    int n = threads > 0 ? threads : (int)std::max(1u, std::thread::hardware_concurrency()); n = std::min(n, height);
    auto work = [&](int y0, int y1) { for (int y = y0; y < y1; y++) { const float* a = in + (size_t)y * width * 3; float* b = out + (size_t)y * width * 3; for (int x = 0; x < width; x++) pc::process_pixel(s, a + 3 * x, b + 3 * x); } };
    if (n <= 1) { work(0, height); return 0; }
    std::vector<std::thread> th; const int step = (height + n - 1) / n;
    for (int t = 0; t < n; t++) { const int y0 = t * step, y1 = std::min(height, y0 + step); if (y0 < y1) th.emplace_back(work, y0, y1); }
    for (auto& t : th) t.join();
    return 0;
}
/// Mască compusă din date plate: [versiune 1, nComp, apoi pe componentă: kind, sub, feather, rot, x1, y1, x2, y2, radius, softness, closed, nPuncte, nPuncte×(x, y, neted)]. Date invalide/goale ⇒ zona simplă rămâne.
static void applyMaskData(pc::Zone& z, const double* d, long n) {
    if (!d || n < 2 || d[0] != 1.0) return; const long nc = (long)d[1]; long o = 2; std::vector<pc::MaskComp> cs;
    for (long k = 0; k < nc; k++) { if (o + 12 > n) return; pc::MaskComp c; c.kind = (int)d[o]; c.sub = (int)d[o + 1]; c.feather = d[o + 2]; c.rot = d[o + 3]; c.x1 = d[o + 4]; c.y1 = d[o + 5]; c.x2 = d[o + 6]; c.y2 = d[o + 7]; c.radius = d[o + 8]; c.softness = d[o + 9]; c.closed = (int)d[o + 10]; const long np = (long)d[o + 11]; o += 12;
        if (np < 0 || o + 3 * np > n) return; c.pts.assign(d + o, d + o + 3 * np); o += 3 * np; cs.push_back(std::move(c)); }
    z.comps = std::move(cs);
}
int pc_process_image_local(const pc_params* g, const pc_local* locals, int n, const float* in, float* out, int width, int height, int threads) { return pc_process_image_masks(g, locals, n, nullptr, nullptr, in, out, width, height, threads); }
int pc_process_image_masks(const pc_params* g, const pc_local* locals, int n, const double* maskData, const long* maskOffsets, const float* in, float* out, int width, int height, int threads) {
    if (n <= 0) return pc_process_image(g, in, out, width, height, threads);
    if (g->drt == 2 && !pc::drtReady()) return 2;
    const pc::Prepared s = pc::prepare(toParams(g)); if (width <= 0 || height <= 0) return 0;
    std::vector<pc::Local> ls; for (int i = 0; i < n; i++) { pc::Local l; l.enabled = locals[i].enabled != 0; l.zone = toZone(locals[i].zone); if (maskData && maskOffsets) applyMaskData(l.zone, maskData + maskOffsets[i], maskOffsets[i + 1] - maskOffsets[i]); l.adj = toParams(&locals[i].adj); ls.push_back(l); }
    const std::vector<pc::PreparedLocal> pl = pc::prepare_locals(ls, width, height);
    int t = threads > 0 ? threads : (int)std::max(1u, std::thread::hardware_concurrency()); t = std::min(t, height);
    auto work = [&](int y0, int y1) { for (int y = y0; y < y1; y++) { const float* a = in + (size_t)y * width * 3; float* b = out + (size_t)y * width * 3; const double ny = (y + 0.5) / height;
        for (int x = 0; x < width; x++) pc::process_pixel_local(s, pl, a + 3 * x, (x + 0.5) / width, ny, width, height, b + 3 * x); } };
    if (t <= 1) { work(0, height); return 0; }
    std::vector<std::thread> th; const int step = (height + t - 1) / t;
    for (int k = 0; k < t; k++) { const int y0 = k * step, y1 = std::min(height, y0 + step); if (y0 < y1) th.emplace_back(work, y0, y1); }
    for (auto& x : th) x.join();
    return 0;
}
static pcfx::Fx toFx(const pc_fx* f) {
    pcfx::Fx r; if (!f) return r;
    r.distortion = f->distortion; r.caRed = f->caRed; r.caBlue = f->caBlue; r.lensVignette = f->lensVignette; r.vignette = f->vignette; r.vignetteMid = f->vignetteMid;
    r.halAmount = f->halAmount; r.halRadius = f->halRadius; r.halThreshold = f->halThreshold; r.halWarm = f->halWarm; r.filmAmount = f->filmAmount; r.filmContrast = f->filmContrast; r.filmToe = f->filmToe; r.filmShoulder = f->filmShoulder; r.filmSat = f->filmSat; r.filmCrosstalk = f->filmCrosstalk;
    r.grainAmount = f->grainAmount; r.grainSize = f->grainSize; r.grainRough = f->grainRough; r.grainChroma = f->grainChroma; r.grainShadows = f->grainShadows; r.grainHighlights = f->grainHighlights; r.grainSeed = f->grainSeed; r.grainRef = f->grainRef; return r;
}
/// Eșantionare comună (geometrie + optică): ieșire → hartă omogenă → ideal → distorsiune → (aberație per canal) → bilinear liniar. Fără optică = exact eșantionatorul anterior (bit-identic). Întoarce false în afara sursei (c = 0). (mx,my) = poziția eșantionată (canalul verde) în coordonatele SURSEI — cea în care se evaluează măștile.
static bool sample_geom(const pc_geom* geo, const double* H, const pcfx::Optics* op, const float* in, int x, int y, float c[3], double& mx, double& my) {
    const int SW = geo->srcW, SH = geo->srcH; const double px = x + 0.5, py = y + 0.5, w = H[6] * px + H[7] * py + H[8];
    double sx = (H[0] * px + H[1] * py + H[2]) / w, sy = (H[3] * px + H[4] * py + H[5]) / w;
    if (op && op->geo) { double dx, dy; pcfx::distort(*op, sx, sy, dx, dy); sx = dx; sy = dy; }
    mx = sx; my = sy; c[0] = c[1] = c[2] = 0; if (!(sx >= 0 && sx <= SW && sy >= 0 && sy <= SH)) return false;   // fără conținut inventat
    auto at = [&](int xx, int yy, int k) { xx = std::min(SW - 1, std::max(0, xx)); yy = std::min(SH - 1, std::max(0, yy)); return in[((size_t)yy * SW + xx) * 3 + k]; };
    for (int k = 0; k < 3; k++) {
        double qx = sx, qy = sy; if (op && op->geo && k != 1) pcfx::scale_about(*op, sx, sy, k == 0 ? op->caR : op->caB, qx, qy);
        const double fx = qx - 0.5, fy = qy - 0.5; int x0 = (int)std::floor(fx), y0i = (int)std::floor(fy); const double ax = fx - x0, ay = fy - y0i;
        c[k] = (float)((1 - ax) * (1 - ay) * at(x0, y0i, k) + ax * (1 - ay) * at(x0 + 1, y0i, k) + (1 - ax) * ay * at(x0, y0i + 1, k) + ax * ay * at(x0 + 1, y0i + 1, k));
    }
    if (op && op->vig != 0) { const double g = pcfx::lens_gain(*op, sx, sy); c[0] = (float)(c[0] * g); c[1] = (float)(c[1] * g); c[2] = (float)(c[2] * g); }
    return true;
}
struct FxPost { bool on = false; pcfx::Fx fx; pcfx::Film film; pcfx::Grain grain; int OW = 1, OH = 1; };
static void pixel_code(const pc::Prepared& g, const std::vector<pc::PreparedLocal>& ls, const FxPost& P, const float in[3], double nx, double ny, int px, int py, double code[3]) {
    pc::adjust_pixel(g, in, code);
    for (const pc::PreparedLocal& l : ls) { const double m = pc::zone_value(l.zone, nx, ny); if (m <= 0) continue; double c2[3]; pc::adjust_code(l.prep, code, c2); for (int i = 0; i < 3; i++) code[i] += m * (c2[i] - code[i]); }
    pc::highlights_gamut(g, code);
    if (P.on) {   // efecte după toate ajustările, ÎNAINTEA DRT-ului, în liniar în gamutul familiei, la rezoluția livrabilului
        double lin[3]; for (int i = 0; i < 3; i++) lin[i] = pc::fam_dec(g.f->curve, code[i]);
        const double ox = (px + 0.5) / P.OW, oy = (py + 0.5) / P.OH, vg = pcfx::vignette_gain(P.fx, ox, oy, P.OW, P.OH); if (vg != 1) for (int i = 0; i < 3; i++) lin[i] *= vg;
        if (P.film.on) pcfx::film_apply(P.film, g.f->luma.data(), lin);
        if (P.grain.on) pcfx::grain_apply(P.grain, g.f->luma.data(), px, py, lin);
        for (int i = 0; i < 3; i++) code[i] = pc::fam_enc(g.f->curve, lin[i]);
    }
}
static void pixel_fx(const pc::Prepared& g, const std::vector<pc::PreparedLocal>& ls, const FxPost& P, const float in[3], double nx, double ny, int px, int py, float out[3]) {
    double code[3]; pixel_code(g, ls, P, in, nx, ny, px, py, code); pc::display_pixel(g, code, out);
}
#ifdef GDC_PC_PREMIUM
static pcfilm::Params toFilm(const pc_film3* f) {
    pcfilm::Params p; p.negStock = f->negStock; p.printStock = f->printStock; p.colourSeparation = f->colourSeparation; p.negContrast = f->negContrast; p.printContrast = f->printContrast; p.exposure = f->exposure;
    p.lightsMaster = f->lightsMaster; p.lightsR = f->lightsR; p.lightsG = f->lightsG; p.lightsB = f->lightsB; p.grainShadows = f->grainShadows; p.grainHighlights = f->grainHighlights; p.grainAmount = f->grainAmount; p.grainSize = f->grainSize;
    p.mtfAmount = f->mtfAmount; p.halationAmount = f->halationAmount; p.halationRadiusMm = f->halationRadiusMm; p.grainAnimate = f->grainAnimate != 0; p.grainSeed = f->grainSeed; p.frame = f->frame; p.formatWidthMm = f->formatWidthMm; p.mix = f->mix;
    p.mtfEnabled = f->mtfEnabled != 0; p.halationEnabled = f->halationEnabled != 0; p.grainEnabled = f->grainEnabled != 0; return p;
}
static pcfilm::CsModel& cinemaModel() { static pcfilm::CsModel m; return m; }
static pcfilm::CinemaParams toCinema(const pc_cinema* c) {
    pcfilm::CinemaParams p; p.layers = c->layers; for (int i = 0; i < 4; i++) { p.layerMix[i] = c->layerMix[i]; p.layerStock[i] = c->layerStock[i]; }
    p.trim.exposure = c->exposure; p.trim.contrast = c->contrast; p.trim.density = c->density; p.trim.warmth = c->warmth; p.trim.tint = c->tint; p.trim.saturation = c->saturation; p.trim.amount = c->amount; p.texture = toFilm(&c->texture); p.mix = c->mix; return p;
}
/// Familia → baza filmului (ACES AP1): matrice familie→AP1 cu Bradford la alb diferit (identitate EXACTĂ pentru AP1), ca `gamutMatrix` din referință.
static pcfilm::FamilyIO filmIO(int fam) {
    const pc::FamilyData& f = pc::family(fam); const pc::FamilyData& a = pc::family(1); pcfilm::FamilyIO io{}; io.dec = [](int c, double v) { return pc::fam_dec(c, v); }; io.enc = [](int c, double v) { return pc::fam_enc(c, v); }; io.curve = f.curve;
    pc::M3 to = {1, 0, 0, 0, 1, 0, 0, 0, 1}, from = to;
    if (fam != 1) { const pc::M3 cat = pc::bradford_cat(f.white[0], f.white[1], a.white[0], a.white[1]); to = pc::mul(pc::inv(a.toXYZ), pc::mul(cat, f.toXYZ)); from = pc::inv(to); }
    for (int i = 0; i < 9; i++) { io.toAp1[i] = to[i]; io.fromAp1[i] = from[i]; }
    return io;
}
#endif
static void parallel_rows(int n, int threads, const std::function<void(int, int)>& body) {
    int t = threads > 0 ? threads : (int)std::max(1u, std::thread::hardware_concurrency()); t = std::min(t, std::max(1, n)); if (t <= 1) { body(0, n); return; }
    std::vector<std::thread> th; const int step = (n + t - 1) / t; for (int k = 0; k < t; k++) { const int a = k * step, b = std::min(n, a + step); if (a < b) th.emplace_back(body, a, b); } for (auto& x : th) x.join();
}
/// Gaussian aproximat (3 treceri de medie mobilă pe orizontală, apoi pe verticală), pe loc.
static void blur2d(std::vector<float>& a, int w, int h, double sigma, int threads) {
    parallel_rows(h, threads, [&](int y0, int y1) { std::vector<float> t(w), u(w); for (int y = y0; y < y1; y++) { float* r = a.data() + (size_t)y * w; for (int p = 0; p < 3; p++) { pcfx::box_blur_1d(r, t.data(), w, pcfx::box_radius(sigma, p)); std::copy(t.begin(), t.end(), r); } } });
    parallel_rows(w, threads, [&](int x0, int x1) { std::vector<float> c(h), t(h); for (int x = x0; x < x1; x++) { for (int y = 0; y < h; y++) c[y] = a[(size_t)y * w + x]; for (int p = 0; p < 3; p++) { pcfx::box_blur_1d(c.data(), t.data(), h, pcfx::box_radius(sigma, p)); std::copy(t.begin(), t.end(), c.begin()); } for (int y = 0; y < h; y++) a[(size_t)y * w + x] = c[y]; } });
}
/// Detalii (claritate + accentuare), pe imaginea FINALĂ sRGB codată (după GDC DRT), doar pe luminanță: se adaugă aceeași diferență pe R, G, B (croma neschimbată).
/// Raze ca fracție din înălțimea cadrului (rezultat independent de rezoluție: aceeași imagine la previzualizare, interactiv și export). Neutru la amount 0 / clarity 0.
///  · accentuare = unsharp mask pe luminanță: Y + amount·soft(Y − blur(σ_s)), soft = prag moale (diferențele sub prag nu se accentuează, deci zgomotul fin rămâne);
///  · claritate = contrast local de scară mare: clarity·4Y(1−Y)·(Y − blur(σ_c)), σ_c = 2% din înălțime, ponderat pe tonuri medii (umbrele și luminile nu se «arde»).
/// Retuș punctual: clone = copiază sursa cu margine moale; heal = copiază sursa corectată cu raportul mediilor pe inelul din jurul destinației (potrivește iluminarea locală), apoi amestec moale.
/// Spoturile se aplică în ordine, fiecare peste rezultatul precedent; sursa se citește dintr-o copie a zonei (fără auto-suprapunere). Eșantioanele din afara imaginii se limitează la margine.
int pc_retouch_apply(const pc_spot* spots, int n, float* rgb, int w, int h) {
    if (!rgb || w <= 0 || h <= 0 || n < 0) return 1;
    for (int k = 0; k < n; k++) {
        const pc_spot& s = spots[k]; if (!s.enabled || s.radius <= 0) continue;
        const double R = std::max(2.0, s.radius * h), cx = s.x * w, cy = s.y * h, dx = s.sx * w - cx, dy = s.sy * h - cy, ringOut = R * 1.3;
        const int x0 = std::max(0, (int)std::floor(cx - ringOut)), x1 = std::min(w - 1, (int)std::ceil(cx + ringOut)), y0 = std::max(0, (int)std::floor(cy - ringOut)), y1 = std::min(h - 1, (int)std::ceil(cy + ringOut));
        if (x1 < x0 || y1 < y0) continue; const int pw = x1 - x0 + 1, ph = y1 - y0 + 1;
        std::vector<float> P((size_t)pw * ph * 3);
        for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) {
            const int sx = std::min(w - 1, std::max(0, (int)std::lround(x + dx))), sy = std::min(h - 1, std::max(0, (int)std::lround(y + dy)));
            for (int c = 0; c < 3; c++) P[((size_t)(y - y0) * pw + (x - x0)) * 3 + c] = rgb[((size_t)sy * w + sx) * 3 + c]; }
        double gain[3] = {1, 1, 1};
        if (s.mode == 1) {
            double dm[3] = {0, 0, 0}, sm[3] = {0, 0, 0}; double cnt = 0;
            for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) { const double d = std::hypot(x - cx, y - cy); if (d < R * 0.92 || d > ringOut) continue;
                for (int c = 0; c < 3; c++) { dm[c] += rgb[((size_t)y * w + x) * 3 + c]; sm[c] += P[((size_t)(y - y0) * pw + (x - x0)) * 3 + c]; } cnt += 1; }
            if (cnt > 8) for (int c = 0; c < 3; c++) gain[c] = sm[c] > 1e-6 ? std::min(2.0, std::max(0.5, dm[c] / sm[c])) : 1.0;
        }
        const double inner = R * (1.0 - std::min(1.0, std::max(0.0, s.feather)));
        for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) {
            const double d = std::hypot(x - cx, y - cy); if (d >= R) continue;
            double m = 1.0; if (d > inner) { const double t = (R - d) / std::max(1e-6, R - inner); m = t * t * (3 - 2 * t); }
            for (int c = 0; c < 3; c++) { float& o = rgb[((size_t)y * w + x) * 3 + c]; const float v = (float)(P[((size_t)(y - y0) * pw + (x - x0)) * 3 + c] * gain[c]); o = (float)(o + (v - o) * m); }
        }
    }
    return 0;
}
/// Reducere de zgomot pe imaginea finală sRGB (înaintea claritate/accentuare): luminanță = filtru ghidat auto-ghidat (păstrează muchiile; eps crește cu cantitatea), culoare = înmoaiere a diferențelor de crominanță (Cb=B−Y, Cr=R−Y) acolo unde luminanța e netedă.
/// Razele sunt fracții din înălțime; croma modificată NU schimbă luminanța (G compensează). Metodă clasică, fără ML.
static void noise_reduce(const pc_detail* d, float* rgb, int w, int h, int threads) {
    const size_t n = (size_t)w * h; const float cr = 0.2126f, cg = 0.7152f, cb = 0.0722f;
    std::vector<float> dR, dG, dB;
    std::vector<float> Y(n);
    parallel_rows(h, threads, [&](int y0, int y1) { for (size_t i = (size_t)y0 * w; i < (size_t)y1 * w; i++) Y[i] = cr * rgb[3 * i] + cg * rgb[3 * i + 1] + cb * rgb[3 * i + 2]; });
    std::vector<float> dY;
    if (d->nrLuma > 0) {
        const double sigma = std::max(1.5, 0.0012 * h); const float eps = (float)std::pow(0.004 + 0.08 * std::min(1.0, d->nrLuma), 2.0);
        std::vector<float> m1 = Y, m2(n); parallel_rows(h, threads, [&](int y0, int y1) { for (size_t i = (size_t)y0 * w; i < (size_t)y1 * w; i++) m2[i] = Y[i] * Y[i]; });
        blur2d(m1, w, h, sigma, threads); blur2d(m2, w, h, sigma, threads);
        std::vector<float> A(n), Bc(n);
        parallel_rows(h, threads, [&](int y0, int y1) { for (size_t i = (size_t)y0 * w; i < (size_t)y1 * w; i++) { const float var = std::max(0.0f, m2[i] - m1[i] * m1[i]); const float a = var / (var + eps); A[i] = a; Bc[i] = (1 - a) * m1[i]; } });
        m1.clear(); m1.shrink_to_fit(); m2.clear(); m2.shrink_to_fit();
        blur2d(A, w, h, sigma, threads); blur2d(Bc, w, h, sigma, threads);
        dY.assign(n, 0.0f); const float mix = (float)std::min(1.0, d->nrLuma * 1.25);
        parallel_rows(h, threads, [&](int y0, int y1) { for (size_t i = (size_t)y0 * w; i < (size_t)y1 * w; i++) dY[i] = mix * ((A[i] * Y[i] + Bc[i]) - Y[i]); });
    }
    std::vector<float> dCb, dCr;
    if (d->nrChroma > 0) {
        const double sigma = std::max(1.5, d->nrChroma * 0.006 * h);
        std::vector<float> Cb(n), Cr(n), Yb = Y;
        parallel_rows(h, threads, [&](int y0, int y1) { for (size_t i = (size_t)y0 * w; i < (size_t)y1 * w; i++) { Cb[i] = rgb[3 * i + 2] - Y[i]; Cr[i] = rgb[3 * i] - Y[i]; } });
        std::vector<float> Cb0 = Cb, Cr0 = Cr; blur2d(Cb, w, h, sigma, threads); blur2d(Cr, w, h, sigma, threads); blur2d(Yb, w, h, std::max(1.0, sigma * 0.5), threads);
        dCb.assign(n, 0.0f); dCr.assign(n, 0.0f); const float k = (float)std::min(1.0, d->nrChroma * 1.2);
        parallel_rows(h, threads, [&](int y0, int y1) { for (size_t i = (size_t)y0 * w; i < (size_t)y1 * w; i++) {
            const float edge = std::fabs(Y[i] - Yb[i]); const float t = k * std::max(0.0f, 1.0f - edge * 20.0f);   // muchii de luminanță (≥5%) opresc înmoierea culorii
            dCb[i] = t * (Cb[i] - Cb0[i]); dCr[i] = t * (Cr[i] - Cr0[i]); } });
    }
    parallel_rows(h, threads, [&](int y0, int y1) { for (size_t i = (size_t)y0 * w; i < (size_t)y1 * w; i++) {
        const float dy = dY.empty() ? 0.0f : dY[i]; const float dcb = dCb.empty() ? 0.0f : dCb[i], dcr = dCr.empty() ? 0.0f : dCr[i];
        const float dg = -(cr * dcr + cb * dcb) / cg;
        float v0 = rgb[3 * i] + dy + dcr, v1 = rgb[3 * i + 1] + dy + dg, v2 = rgb[3 * i + 2] + dy + dcb;
        rgb[3 * i] = v0 < 0 ? 0 : (v0 > 1 ? 1 : v0); rgb[3 * i + 1] = v1 < 0 ? 0 : (v1 > 1 ? 1 : v1); rgb[3 * i + 2] = v2 < 0 ? 0 : (v2 > 1 ? 1 : v2); } });
}
int pc_detail_apply(const pc_detail* d, float* rgb, int w, int h, int threads) {
    if (!d || !rgb || w <= 0 || h <= 0) return 1;
    if (!d->on || (d->sharpAmount == 0 && d->clarity == 0 && d->nrLuma <= 0 && d->nrChroma <= 0)) return 0;
    if (d->nrLuma > 0 || d->nrChroma > 0) noise_reduce(d, rgb, w, h, threads);
    if (d->sharpAmount == 0 && d->clarity == 0) return 0;
    const size_t n = (size_t)w * h; std::vector<float> Y(n); const float cr = 0.2126f, cg = 0.7152f, cb = 0.0722f;
    parallel_rows(h, threads, [&](int y0, int y1) { for (size_t i = (size_t)y0 * w; i < (size_t)y1 * w; i++) Y[i] = cr * rgb[3 * i] + cg * rgb[3 * i + 1] + cb * rgb[3 * i + 2]; });
    std::vector<float> delta(n, 0.0f);
    if (d->sharpAmount != 0) {
        std::vector<float> B = Y; const double sigma = std::max(0.5, d->sharpRadius * 0.001 * h); blur2d(B, w, h, sigma, threads);
        const float amt = (float)d->sharpAmount, thr = (float)d->sharpThreshold;
        parallel_rows(h, threads, [&](int y0, int y1) { for (size_t i = (size_t)y0 * w; i < (size_t)y1 * w; i++) { const float df = Y[i] - B[i]; const float m = std::max(0.0f, std::fabs(df) - thr); delta[i] += amt * (df < 0 ? -m : m); } });
    }
    if (d->clarity != 0) {
        std::vector<float> B = Y; const double sigma = std::max(2.0, 0.02 * h); blur2d(B, w, h, sigma, threads); const float k = (float)d->clarity;
        parallel_rows(h, threads, [&](int y0, int y1) { for (size_t i = (size_t)y0 * w; i < (size_t)y1 * w; i++) { const float yv = std::min(1.0f, std::max(0.0f, Y[i])); delta[i] += k * 4.0f * yv * (1.0f - yv) * (Y[i] - B[i]); } });
    }
    parallel_rows(h, threads, [&](int y0, int y1) { for (size_t i = (size_t)y0 * w; i < (size_t)y1 * w; i++) for (int c = 0; c < 3; c++) { float v = rgb[3 * i + c] + delta[i]; rgb[3 * i + c] = v < 0 ? 0 : (v > 1 ? 1 : v); } });
    return 0;
}
static void map_src(const pc_geom* geo, const double* H, const pcfx::Optics* op, int x, int y, double& mx, double& my) {
    const double px = x + 0.5, py = y + 0.5, w = H[6] * px + H[7] * py + H[8]; double sx = (H[0] * px + H[1] * py + H[2]) / w, sy = (H[3] * px + H[4] * py + H[5]) / w;
    if (op && op->geo) { double dx, dy; pcfx::distort(*op, sx, sy, dx, dy); sx = dx; sy = dy; } mx = sx; my = sy; (void)geo;
}
static int run_geom(const pc_params* g, const pc_local* locals, int n, const double* maskData, const long* maskOffsets, const pc_geom* geo, const pc_fx* fxIn, const pc_film3* film, const pc_cinema* cinema, const float* in, float* out, int threads) {
    if (!geo || geo->srcW <= 0 || geo->srcH <= 0 || geo->outW <= 0 || geo->outH <= 0) return 1;
    if (g->drt == 2 && !pc::drtReady()) return 2;
    const int SW = geo->srcW, SH = geo->srcH, OW = geo->outW, OH = geo->outH; const pc::Prepared s = pc::prepare(toParams(g));
    std::vector<pc::Local> ls; for (int i = 0; i < n; i++) { pc::Local l; l.enabled = locals[i].enabled != 0; l.zone = toZone(locals[i].zone); if (maskData && maskOffsets) applyMaskData(l.zone, maskData + maskOffsets[i], maskOffsets[i + 1] - maskOffsets[i]); l.adj = toParams(&locals[i].adj); ls.push_back(std::move(l)); }
    const std::vector<pc::PreparedLocal> pl = pc::prepare_locals(ls, SW, SH); const double* H = geo->h;
    FxPost P; P.fx = toFx(fxIn); const pcfx::Optics op = pcfx::prepare_optics(P.fx, SW, SH); const bool useOp = P.fx.opticsActive();
    P.on = P.fx.postActive() && g->stage == 0; P.OW = OW; P.OH = OH; P.film = pcfx::prepare_film(P.fx); P.grain = pcfx::prepare_grain(P.fx, OH);
    int t = threads > 0 ? threads : (int)std::max(1u, std::thread::hardware_concurrency()); t = std::min(t, OH);
    const pcfx::Halation hal = pcfx::prepare_halation(P.fx, OH);
#ifdef GDC_PC_PREMIUM
    pc::so::P optp; optp.filter = g->opFilter; optp.strength = g->opStrength; optp.diffusion = g->opDiffusion; optp.thresholdStops = g->opThreshold; optp.size = g->opSize; optp.bloom = g->opBloom; optp.mix = g->opMix;
    const bool optOn = g->stage == 0 && pc::so::active(optp), halOn = hal.on && g->stage == 0;
#else
    const bool optOn = false, halOn = hal.on && g->stage == 0;
#endif
    // Film V3: cadrul de coduri (după ajustări, locale, lumini/gamă și efectele simple) se păstrează într-un buffer, trece prin lanțul fotochimic pe tot cadrul, apoi se afișează (DRT) o singură dată.
#ifdef GDC_PC_PREMIUM
    const bool cinemaOn = cinema && cinema->on && g->stage == 0 && cinemaModel().stocks.size() > 0, filmOn = (film && film->on && g->stage == 0) || cinemaOn; std::vector<float> codeBuf; if (filmOn) codeBuf.assign((size_t)OW * OH * 3, 0.f);
#else
    (void)film; (void)cinema; const bool cinemaOn = false, filmOn = false; std::vector<float> codeBuf;
#endif
    auto emit = [&](const pc::Prepared& pp, const float* inPx, double nx, double ny, int px, int py) {
        if (!filmOn) { pixel_fx(pp, pl, P, inPx, nx, ny, px, py, out + ((size_t)py * OW + px) * 3); return; }
        double code[3]; pixel_code(pp, pl, P, inPx, nx, ny, px, py, code); float* o = codeBuf.data() + ((size_t)py * OW + px) * 3; o[0] = (float)code[0]; o[1] = (float)code[1]; o[2] = (float)code[2]; };
    auto finish = [&](const pc::Prepared& pp) {
        if (!filmOn) return 0;
#ifdef GDC_PC_PREMIUM
        if (cinemaOn) pcfilm::cinemaFrame(codeBuf.data(), OW, OH, toCinema(cinema), cinemaModel(), filmIO(g->family), t);
        if (film && film->on) pcfilm::frame(codeBuf.data(), OW, OH, toFilm(film), filmIO(g->family), t);
#else
        (void)cinemaOn;
#endif
        parallel_rows(OH, t, [&](int y0, int y1) { for (int y = y0; y < y1; y++) for (int x = 0; x < OW; x++) { const float* c = codeBuf.data() + ((size_t)y * OW + x) * 3; const double code[3] = {c[0], c[1], c[2]}; pc::display_pixel(pp, code, out + ((size_t)y * OW + x) * 3); } });
        return 0; };
    if (halOn || optOn) {   // treceri spațiale pe tot cadrul, la rezoluția livrabilului: [halație simplă] → instrumente liniare → [Optics: difuzie + bloom] → restul lanțului
        std::vector<float> lin((size_t)OW * OH * 3), src, big; std::vector<char> valid((size_t)OW * OH); const double* L = s.f->luma.data();
        if (halOn) { src.assign((size_t)OW * OH, 0.f); }
        parallel_rows(OH, t, [&](int y0, int y1) { for (int y = y0; y < y1; y++) for (int x = 0; x < OW; x++) { float c[3]; double mx, my; const bool ok = sample_geom(geo, H, useOp ? &op : nullptr, in, x, y, c, mx, my); const size_t i = (size_t)y * OW + x;
            float* o = lin.data() + i * 3; o[0] = c[0]; o[1] = c[1]; o[2] = c[2]; valid[i] = ok; if (halOn) { const double Y = L[0] * c[0] + L[1] * c[1] + L[2] * c[2]; src[i] = ok && Y > 0 ? (float)(Y * pcfx::halation_gate(hal, Y)) : 0.f; } } });
        if (halOn) { big = src; blur2d(src, OW, OH, hal.sigma, t); blur2d(big, OW, OH, 3 * hal.sigma, t);
            parallel_rows(OH, t, [&](int y0, int y1) { for (int y = y0; y < y1; y++) for (int x = 0; x < OW; x++) { const size_t i = (size_t)y * OW + x; if (!valid[i]) continue; const double gl = hal.amount * (0.7 * src[i] + 0.3 * big[i]); float* o = lin.data() + i * 3; for (int k = 0; k < 3; k++) o[k] = (float)(o[k] + gl * hal.w[k]); } }); }
        pc::Prepared s2 = s;
        if (optOn) {
            parallel_rows(OH, t, [&](int y0, int y1) { for (int y = y0; y < y1; y++) for (int x = 0; x < OW; x++) { float* o = lin.data() + ((size_t)y * OW + x) * 3; double l[3]; pc::input_lin(s, o, l); pc::linear_tools(s, l); o[0] = (float)l[0]; o[1] = (float)l[1]; o[2] = (float)l[2]; } });
#ifdef GDC_PC_PREMIUM
            pc::so::apply(lin, OW, OH, L, optp, t); s2.p.inputIsLinear = 1; s2.skipLinear = true;
#endif
        }
        parallel_rows(OH, t, [&](int y0, int y1) { for (int y = y0; y < y1; y++) for (int x = 0; x < OW; x++) { double mx, my; map_src(geo, H, useOp ? &op : nullptr, x, y, mx, my); emit(s2, lin.data() + ((size_t)y * OW + x) * 3, mx / SW, my / SH, x, y); } });
        return finish(s2);
    }
    auto work = [&](int y0, int y1) { for (int y = y0; y < y1; y++) for (int x = 0; x < OW; x++) {
        float c[3]; double mx, my; sample_geom(geo, H, useOp ? &op : nullptr, in, x, y, c, mx, my);
        emit(s, c, mx / SW, my / SH, x, y); } };
    if (t <= 1) { work(0, OH); return finish(s); }
    std::vector<std::thread> th; const int step = (OH + t - 1) / t;
    for (int k = 0; k < t; k++) { const int y0 = k * step, y1 = std::min(OH, y0 + step); if (y0 < y1) th.emplace_back(work, y0, y1); }
    for (auto& x : th) x.join();
    return finish(s);
}
/// Geometrie nedistructivă: ieșirea w×h se obține dintr-o SINGURĂ reeșantionare bilineară a sursei (liniar), prin harta omogenă 3×3 ieșire→sursă; măștile se evaluează în coordonatele SURSEI (aceeași zonă sub orice geometrie).
int pc_process_image_geom(const pc_params* g, const pc_local* locals, int n, const double* maskData, const long* maskOffsets, const pc_geom* geo, const float* in, float* out, int threads) { return run_geom(g, locals, n, maskData, maskOffsets, geo, nullptr, nullptr, nullptr, in, out, threads); }
/// Ca `pc_process_image_geom`, cu efecte: Optică (distorsiune, aberație cromatică, vinietă de obiectiv) la eșantionare; Peliculă/Grain după corecțiile locale, înainte de DRT, la rezoluția livrabilului. fx = nullptr ⇒ identic bit cu `pc_process_image_geom`.
int pc_process_image_fx(const pc_params* g, const pc_local* locals, int n, const double* maskData, const long* maskOffsets, const pc_geom* geo, const pc_fx* fx, const float* in, float* out, int threads) { return run_geom(g, locals, n, maskData, maskOffsets, geo, fx, nullptr, nullptr, in, out, threads); }
int pc_process_image_fx3(const pc_params* g, const pc_local* locals, int n, const double* maskData, const long* maskOffsets, const pc_geom* geo, const pc_fx* fx, const pc_film3* film, const float* in, float* out, int threads) { return run_geom(g, locals, n, maskData, maskOffsets, geo, fx, film, nullptr, in, out, threads); }
int pc_process_image_fx4(const pc_params* g, const pc_local* locals, int n, const double* maskData, const long* maskOffsets, const pc_geom* geo, const pc_fx* fx, const pc_film3* film, const pc_cinema* cinema, const float* in, float* out, int threads) { return run_geom(g, locals, n, maskData, maskOffsets, geo, fx, film, cinema, in, out, threads); }
#ifdef GDC_PC_PREMIUM
void pc_default_cinema(pc_cinema* c) { *c = pc_cinema{}; c->layers = 0; for (int i = 0; i < 4; i++) { c->layerMix[i] = 1; c->layerStock[i] = -1; } c->contrast = 1; c->saturation = 1; c->amount = 1; c->mix = 1; pc_default_film3(&c->texture); c->texture.mtfEnabled = c->texture.halationEnabled = c->texture.grainEnabled = 0; }
int pc_cinema_load(const char* path) { pcfilm::CsModel m; if (!path || !m.load(path)) return 1; cinemaModel() = std::move(m); return 0; }
int pc_cinema_ready(void) { return cinemaModel().stocks.empty() ? 0 : 1; }
int pc_cinema_style_count(void) { return (int)pcfilm::cinemaLibrary().size(); }
const char* pc_cinema_style_id(int i) { return pcfilm::cinemaLibrary().at(i).id; }
const char* pc_cinema_style_name(int i) { return pcfilm::cinemaLibrary().at(i).name; }
const char* pc_cinema_style_category(int i) { return pcfilm::cinemaLibrary().at(i).category; }
void pc_cinema_style_info(int i, int* layer, int* layerIndex, int* stockIndex) { const auto& e = pcfilm::cinemaLibrary().at(i); *layer = e.layer; *layerIndex = e.layerIndex; *stockIndex = e.stockIndex; }
int pc_cinema_frame(const pc_cinema* c, int family, float* codes, int w, int h, int threads) { if (!c || !codes || w <= 0 || h <= 0 || !pc_cinema_ready()) return 1; pcfilm::cinemaFrame(codes, w, h, toCinema(c), cinemaModel(), filmIO(family), threads); return 0; }
void pc_default_film3(pc_film3* f) { pcfilm::Params d; *f = pc_film3{}; f->negStock = d.negStock; f->printStock = d.printStock; f->colourSeparation = d.colourSeparation; f->negContrast = d.negContrast; f->printContrast = d.printContrast; f->grainShadows = d.grainShadows; f->grainHighlights = d.grainHighlights; f->grainAmount = d.grainAmount; f->grainSize = d.grainSize; f->mtfAmount = d.mtfAmount; f->halationAmount = d.halationAmount; f->halationRadiusMm = d.halationRadiusMm; f->grainAnimate = 1; f->formatWidthMm = d.formatWidthMm; f->mix = 1; f->mtfEnabled = f->halationEnabled = f->grainEnabled = 1; }
int pc_film3_stock_count(void) { return pcfilm::negativeStockCount(); }
const char* pc_film3_stock_label(int i) { return pcfilm::negativeStock(i).label; }
const char* pc_film3_stock_info(int i) { return pcfilm::negativeStock(i).info; }
int pc_film3_print_count(void) { return 2; }
const char* pc_film3_print_label(int i) { return i == 1 ? "Print Classic" : "Print Modern"; }
int pc_film3_format_count(void) { return pcfilm::formatCount(); }
int pc_film3_format_default(void) { return pcfilm::formatDefaultIndex(); }
const char* pc_film3_format_label(int i) { return pcfilm::formatProfile(i).label; }
double pc_film3_format_gate(int i) { return pcfilm::formatProfile(i).gateWidthMm; }
void pc_film3_format_start(int i, double out[5], int set[5]) { const pcfilm::FormatProfile& f = pcfilm::formatProfile(i); const pcfilm::StartValue* v[5] = {&f.grainSize, &f.softness, &f.halationSize, &f.grainAmount, &f.halationAmount}; for (int k = 0; k < 5; k++) { out[k] = v[k]->value; set[k] = v[k]->set ? 1 : 0; } }
void pc_film3_apply_format(pc_film3* p, int format) {   // = filmV3ApplyFormat: valorile UMANE (× Super 35, % cadru) → fizice (÷ mărire, mm pe film)
    const pcfilm::FormatProfile& f = pcfilm::formatProfile(format); const double mag = pcfilm::formatReferenceGateMm() / f.gateWidthMm; p->formatWidthMm = f.gateWidthMm;
    if (f.grainSize.set) p->grainSize = f.grainSize.value / mag; if (f.softness.set) p->mtfAmount = f.softness.value / mag; if (f.halationSize.set) p->halationRadiusMm = f.halationSize.value * f.gateWidthMm / 100.0;
    if (f.grainAmount.set) p->grainAmount = f.grainAmount.value; if (f.halationAmount.set) p->halationAmount = f.halationAmount.value; }
int pc_film3_frame(const pc_film3* f, int family, float* codes, int w, int h, int threads) { if (!f || !codes || w <= 0 || h <= 0) return 1; pcfilm::frame(codes, w, h, toFilm(f), filmIO(family), threads); return 0; }
#else
// Ediția cu sursă deschisă: Film V3 și Cinema Style nu sunt incluse. Interfața C rămâne (aceeași ABI); listele sunt goale, iar aplicarea întoarce «indisponibil» fără să atingă imaginea.
void pc_default_film3(pc_film3* f) { *f = pc_film3{}; f->mix = 1; }
void pc_default_cinema(pc_cinema* c) { *c = pc_cinema{}; for (int i = 0; i < 4; i++) { c->layerMix[i] = 1; c->layerStock[i] = -1; } c->contrast = 1; c->saturation = 1; c->amount = 1; c->mix = 1; pc_default_film3(&c->texture); }
int pc_cinema_load(const char*) { return 1; }
int pc_cinema_ready(void) { return 0; }
int pc_cinema_style_count(void) { return 0; }
const char* pc_cinema_style_id(int) { return ""; }
const char* pc_cinema_style_name(int) { return ""; }
const char* pc_cinema_style_category(int) { return ""; }
void pc_cinema_style_info(int, int* layer, int* layerIndex, int* stockIndex) { *layer = 0; *layerIndex = 0; *stockIndex = -1; }
int pc_cinema_frame(const pc_cinema*, int, float*, int, int, int) { return 1; }
int pc_film3_stock_count(void) { return 0; }
const char* pc_film3_stock_label(int) { return ""; }
const char* pc_film3_stock_info(int) { return ""; }
int pc_film3_print_count(void) { return 0; }
const char* pc_film3_print_label(int) { return ""; }
int pc_film3_format_count(void) { return 0; }
int pc_film3_format_default(void) { return 0; }
const char* pc_film3_format_label(int) { return ""; }
double pc_film3_format_gate(int) { return 0; }
void pc_film3_format_start(int, double out[5], int set[5]) { for (int k = 0; k < 5; k++) { out[k] = 0; set[k] = 0; } }
void pc_film3_apply_format(pc_film3*, int) {}
int pc_film3_frame(const pc_film3*, int, float*, int, int, int) { return 1; }
#endif
void pc_default_fx(pc_fx* f) { pcfx::Fx d; f->distortion = d.distortion; f->caRed = d.caRed; f->caBlue = d.caBlue; f->lensVignette = d.lensVignette; f->vignette = d.vignette; f->vignetteMid = d.vignetteMid;
    f->halAmount = d.halAmount; f->halRadius = d.halRadius; f->halThreshold = d.halThreshold; f->halWarm = d.halWarm; f->filmAmount = d.filmAmount; f->filmContrast = d.filmContrast; f->filmToe = d.filmToe; f->filmShoulder = d.filmShoulder; f->filmSat = d.filmSat; f->filmCrosstalk = d.filmCrosstalk;
    f->grainAmount = d.grainAmount; f->grainSize = d.grainSize; f->grainRough = d.grainRough; f->grainChroma = d.grainChroma; f->grainShadows = d.grainShadows; f->grainHighlights = d.grainHighlights; f->grainSeed = d.grainSeed; f->grainRef = d.grainRef; }
/// Doar reeșantionarea geometrică (liniar, bilinear, fără instrumente) cu optica (distorsiune, aberație, vinietă de obiectiv) dacă `fx` e dat: pentru intermediarul Resolve cu geometria aplicată.
int pc_resample_fx(const pc_geom* geo, const pc_fx* fxIn, const float* in, float* out, int threads) {
    if (!geo || geo->srcW <= 0 || geo->srcH <= 0 || geo->outW <= 0 || geo->outH <= 0) return 1;
    const int SW = geo->srcW, SH = geo->srcH, OW = geo->outW, OH = geo->outH; const double* H = geo->h; const pcfx::Fx fx = toFx(fxIn); const pcfx::Optics op = pcfx::prepare_optics(fx, SW, SH); const bool useOp = fx.opticsActive();
    int t = threads > 0 ? threads : (int)std::max(1u, std::thread::hardware_concurrency()); t = std::min(t, OH);
    auto work = [&](int y0, int y1) { for (int y = y0; y < y1; y++) for (int x = 0; x < OW; x++) { float c[3]; double mx, my; sample_geom(geo, H, useOp ? &op : nullptr, in, x, y, c, mx, my); float* o = out + ((size_t)y * OW + x) * 3; o[0] = c[0]; o[1] = c[1]; o[2] = c[2]; } };
    if (t <= 1) { work(0, OH); return 0; }
    std::vector<std::thread> th; const int step = (OH + t - 1) / t; for (int k = 0; k < t; k++) { const int y0 = k * step, y1 = std::min(OH, y0 + step); if (y0 < y1) th.emplace_back(work, y0, y1); } for (auto& x : th) x.join(); return 0;
}
int pc_resample_geom(const pc_geom* geo, const float* in, float* out, int threads) { return pc_resample_fx(geo, nullptr, in, out, threads); }
/// Hărți optice pe puncte (ghidajele măștilor): ideal → eșantionat și invers, în pixeli ai sursei.
void pc_fx_distort(const pc_fx* fx, int srcW, int srcH, double x, double y, double* ox, double* oy) { const pcfx::Optics o = pcfx::prepare_optics(toFx(fx), srcW, srcH); if (!o.geo) { *ox = x; *oy = y; return; } pcfx::distort(o, x, y, *ox, *oy); }
void pc_fx_undistort(const pc_fx* fx, int srcW, int srcH, double x, double y, double* ox, double* oy) { const pcfx::Optics o = pcfx::prepare_optics(toFx(fx), srcW, srcH); if (!o.geo) { *ox = x; *oy = y; return; } pcfx::undistort(o, x, y, *ox, *oy); }
/// Masca compusă evaluată pe o grilă w×h a VEDERII (ieșirea geometriei): fiecare punct al grilei trece prin harta ieșire→sursă și se evaluează în coordonatele sursei — exact zona procesată, sub orice geometrie, inclusiv perspectivă.
void pc_mask_image_geom_fx(const pc_zone* z, const double* maskData, long count, const pc_geom* geo, const pc_fx* fxIn, float* out, int width, int height) {
    if (!geo || width <= 0 || height <= 0 || geo->srcW <= 0 || geo->srcH <= 0) return; pc::Zone zz = toZone(*z); applyMaskData(zz, maskData, count); const pc::PZone pz = pc::prepare_zone(zz, geo->srcW, geo->srcH); const double* H = geo->h;
    const pcfx::Optics op = pcfx::prepare_optics(toFx(fxIn), geo->srcW, geo->srcH);
    for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) {
        const double px = (x + 0.5) / width * geo->outW, py = (y + 0.5) / height * geo->outH, w = H[6] * px + H[7] * py + H[8]; double sx = (H[0] * px + H[1] * py + H[2]) / w, sy = (H[3] * px + H[4] * py + H[5]) / w;
        if (op.geo) { double dx, dy; pcfx::distort(op, sx, sy, dx, dy); sx = dx; sy = dy; }
        out[(size_t)y * width + x] = (sx < 0 || sx > geo->srcW || sy < 0 || sy > geo->srcH) ? 0.0f : (float)pc::zone_value(pz, sx / geo->srcW, sy / geo->srcH); }
}
void pc_mask_image_geom(const pc_zone* z, const double* maskData, long count, const pc_geom* geo, float* out, int width, int height) { pc_mask_image_geom_fx(z, maskData, count, geo, nullptr, out, width, height); }
void pc_mask_image_data(const pc_zone* z, const double* maskData, long count, float* out, int width, int height) {
    pc::Zone zz = toZone(*z); applyMaskData(zz, maskData, count); if (width <= 0 || height <= 0) return; const pc::PZone pz = pc::prepare_zone(zz, width, height);
    for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) out[(size_t)y * width + x] = (float)pc::zone_value(pz, (x + 0.5) / width, (y + 0.5) / height);
}
void pc_mask_image(const pc_zone* z, float* out, int width, int height) {
    const pc::Zone zz = toZone(*z); for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) out[(size_t)y * width + x] = (float)pc::zone_mask(zz, (x + 0.5) / width, (y + 0.5) / height, width, height);
}
int pc_drt_load(const unsigned char* b, unsigned long n, char* err, int errLen) { std::string e; if (pc::drtLoadBytes(b, n, e)) return 0; if (err && errLen > 0) { std::strncpy(err, e.c_str(), errLen - 1); err[errLen - 1] = 0; } return 1; }
int pc_drt_available(void) { return pc::drtReady() ? 1 : 0; }
#ifdef GDC_PC_PREMIUM
int pc_gdc_drt_core(int profile, const double rgb[3], double out[3]) { if (!pc::drtReady()) return 2; pc::gdcdrt::core(pc::drtData(), profile, rgb, out); return 0; }
double pc_gdc_drt_encode(int output, double code24) { return pc::gdcdrt::encode(output, code24); }
#else
int pc_gdc_drt_core(int, const double[3], double out[3]) { out[0] = out[1] = out[2] = 0; return 2; }
double pc_gdc_drt_encode(int, double code24) { return code24; }
#endif
double pc_di_decode(double c) { return pc::di_decode(c); }
double pc_di_encode(double l) { return pc::di_encode(l); }
double pc_tone_scale(double x) { return pc::tone_scale(x); }
void pc_balance_matrix(double t, double u, double o[9]) { const pc::M3 m = pc::balanceMatrix(t, u, 0); for (int i = 0; i < 9; i++) o[i] = m[i]; }
int pc_family_count(void) { return 4; }
const char* pc_family_id(int f) { return pc::family(f).id; }
const char* pc_family_label(int f) { return pc::family(f).label; }
void pc_convert_dwg_to_family(int f, const float* in, float* out, long n) { const pc::FamilyData& F = pc::family(f); for (long i = 0; i < n; i++) { const double v[3] = {in[3 * i], in[3 * i + 1], in[3 * i + 2]}; double o[3]; pc::apply3(F.fromDwg, v, o); out[3 * i] = (float)o[0]; out[3 * i + 1] = (float)o[1]; out[3 * i + 2] = (float)o[2]; } }
double pc_family_encode(int f, double x) { return pc::fam_enc(pc::family(f).curve, x); }
double pc_family_decode(int f, double y) { return pc::fam_dec(pc::family(f).curve, y); }
void pc_family_luma(int f, double o[3]) { const auto& l = pc::family(f).luma; o[0] = l[0]; o[1] = l[1]; o[2] = l[2]; }
#ifdef GDC_PC_PREMIUM
double pc_color_weight(const pc_params* p, const double code[3]) { const pc::Prepared s = pc::prepare(toParams(p)); return pc::sc::color_weight(s.p.family, s.cp, code); }
double pc_skin_weight(const pc_params* p, const double code[3]) { const pc::Prepared s = pc::prepare(toParams(p)); return pc::sc::skin_weight(s.p.family, s.sp, code); }
void pc_color_pick_range(int family, const double* codes, int n, pc_range_pick* o) { const pc::sc::RangePick r = pc::sc::pick_range(family, codes, n); o->valid = r.valid; o->hasRange = r.hasRange; o->hue = r.hue; o->c = r.c; o->l = r.l; o->range = r.range; o->satRange = r.satRange; o->lumRange = r.lumRange; o->samples = r.samples; o->chromatic = r.chromatic; o->used = r.used; }
int pc_look_count(void) { return (int)pc::lf::lookFieldLibrary().size(); }
const char* pc_look_name(int i) { const auto& l = pc::lf::lookFieldLibrary(); return l.at(i < 0 ? 0 : (i >= (int)l.size() ? l.size() - 1 : i)).tagline.c_str(); }
#else
double pc_color_weight(const pc_params*, const double[3]) { return 0; }
double pc_skin_weight(const pc_params*, const double[3]) { return 0; }
void pc_color_pick_range(int, const double*, int, pc_range_pick* o) { *o = pc_range_pick{}; }
int pc_look_count(void) { return 0; }
const char* pc_look_name(int) { return ""; }
#endif
#ifdef GDC_PC_PREMIUM
int pc_color_pick(int family, const double code[3], double* hue, double* c, double* l) {
    if (!pc::sc::finite3(code)) return 0; pc::sc::Ok o; if (!pc::sc::decompose(family, code, o) || o.Cn < 2.0 * pc::sc::kHueConfCn) return 0;   // regionFromPickV2: sub 2·Cn_conf nuanța e zgomot
    *hue = std::round(std::fmod(o.h0 + 360.0, 360.0) * 10.0) / 10.0; *c = pc::sc::clampD(o.Cn, 0.0, 1.0); *l = pc::sc::clampD(o.st, pc::sc::kStopLo, pc::sc::kStopHi); return 1;
}
#else
int pc_color_pick(int, const double[3], double*, double*, double*) { return 0; }
#endif
static pc::Prepared stagePrep(const pc_params* p) { pc_params q = *p; q.colorActive = 0; q.skAmount = 0; q.lookOn = 0; return pc::prepare(toParams(&q)); }
void pc_color_stage_code(const pc_params* p, const float lin[3], double out[3]) { const pc::Prepared s = stagePrep(p); pc::adjust_pixel(s, lin, out); }
int pc_selection_matte_view(const pc_params* p, int which, const pc_geom* geo, const float* in, float* out, int threads) {
    if (!geo || geo->srcW <= 0 || geo->srcH <= 0 || geo->outW <= 0 || geo->outH <= 0) return 1;
    const pc::Prepared s = stagePrep(p); const pc::Prepared full = pc::prepare(toParams(p)); const int OW = geo->outW, OH = geo->outH; const double* H = geo->h;
    parallel_rows(OH, threads, [&](int y0, int y1) { for (int y = y0; y < y1; y++) for (int x = 0; x < OW; x++) { float c[3]; double mx, my; const bool ok = sample_geom(geo, H, nullptr, in, x, y, c, mx, my); double code[3];
        if (!ok) { out[(size_t)y * OW + x] = 0.f; continue; } pc::adjust_pixel(s, c, code);
#ifdef GDC_PC_PREMIUM
        out[(size_t)y * OW + x] = (float)(which == 0 ? pc::sc::color_weight(full.p.family, full.cp, code) : pc::sc::skin_weight(full.p.family, full.sp, code)); } });
#else
        (void)full; out[(size_t)y * OW + x] = 0.f; } });
#endif
    return 0;
}
/// Teste/instrumente: Optics (difuzie + bloom) pe un buffer RGB float liniar în gamutul familiei, pe loc.
#ifdef GDC_PC_PREMIUM
void pc_optics_apply(const pc_params* p, float* rgb, int w, int h) { pc::so::P o; o.filter = p->opFilter; o.strength = p->opStrength; o.diffusion = p->opDiffusion; o.thresholdStops = p->opThreshold; o.size = p->opSize; o.bloom = p->opBloom; o.mix = p->opMix;
    std::vector<float> v(rgb, rgb + (size_t)w * h * 3); pc::so::apply(v, w, h, pc::family(p->family).luma.data(), o, 1); std::copy(v.begin(), v.end(), rgb); }
#else
void pc_optics_apply(const pc_params*, float*, int, int) {}
#endif
static const double kD50xy[2] = {0.34570291, 0.3585386}, kD65xy[2] = {0.3127, 0.3290};
static void d50White(double w[3]) { const double x = kD50xy[0], y = kD50xy[1]; w[0] = x / y; w[1] = 1.0; w[2] = (1 - x - y) / y; }
void pc_chart_reference_dwg(const double lab[3], double out[3]) {
    double w[3]; d50White(w); const double fy = (lab[0] + 16.0) / 116.0, fx = fy + lab[1] / 500.0, fz = fy - lab[2] / 200.0;
    auto fi = [](double t) { const double d = 6.0 / 29.0; return t > d ? t * t * t : 3 * d * d * (t - 4.0 / 29.0); };
    const double X = w[0] * fi(fx), Y = w[1] * fi(fy), Z = w[2] * fi(fz);
    const pc::M3 cat = pc::bradford_cat(kD50xy[0], kD50xy[1], kD65xy[0], kD65xy[1]); const double v[3] = {X, Y, Z}; double a[3]; pc::apply3(cat, v, a);
    const pc::M3 m = pc::inv(pc::dwgToXYZ()); pc::apply3(m, a, out);
}
void pc_dwg_to_lab_d50(const double dwg[3], double lab[3]) {
    double xyz65[3]; pc::apply3(pc::dwgToXYZ(), dwg, xyz65); const pc::M3 cat = pc::bradford_cat(kD65xy[0], kD65xy[1], kD50xy[0], kD50xy[1]); double x[3]; pc::apply3(cat, xyz65, x);
    double w[3]; d50White(w); auto f = [](double t) { const double e = 216.0 / 24389.0, k = 24389.0 / 27.0; return t > e ? std::cbrt(t) : (k * t + 16.0) / 116.0; };
    const double fx = f(x[0] / w[0]), fy = f(x[1] / w[1]), fz = f(x[2] / w[2]); lab[0] = 116.0 * fy - 16.0; lab[1] = 500.0 * (fx - fy); lab[2] = 200.0 * (fy - fz);
}
int pc_edition_full(void) {
#ifdef GDC_PC_PREMIUM
    return 1;
#else
    return 0;
#endif
}
const char* pc_version(void) { return "photo-develop 0.4.1 (rev3: STYLE V3 fidelity; families; raw-decode r4: pattern black + native aspect)"; }
}
