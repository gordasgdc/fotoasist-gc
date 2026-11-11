// FotoAsist GC — efecte fotografice proprii (Optică, Peliculă, Grain). Implementare PROPRIE, din formule/modele simple declarate mai jos; nicio dependență de GDC STYLE.
// Contract: toate efectele sunt neutre la valorile implicite (identitate exactă) și independente de rezoluție (mărimi relative la ÎNĂLȚIMEA livrabilului; grain la rezoluția de livrare, după reeșantionare).
//  OPTICĂ  (liniar, în coordonatele sursei):  corecție de distorsiune radială r_d = r_i·(1 + k1·ρ² + k2·ρ⁴), ρ = r/semi-diagonală sursă; aberație cromatică laterală = scalare radială per canal (R, B) în jurul centrului sursei;
//                                             vinietă de obiectiv (câștig în stopuri ∝ ρ², ρ din poziția eșantionată). [GEOMETRIC / EMPIRIC — modele standard cu un parametru; nu profile de obiectiv măsurate]
//  PELICULĂ (liniar, după corecțiile locale): vinietă creativă (în coordonatele ieșirii) → diafonie de coloranți (matrice cu rânduri însumând 1) → curbă de răspuns în stopuri față de gri 18% (toe/shoulder asimptotice, contrast) → saturație în densitate. [CREATIV — aproximări, nu curbe sensitometrice măsurate]
//  GRAIN    (liniar, după peliculă): zgomot de valoare normalizat la varianță unitară pe rețea de mărime ∝ înălțimea ieșirii, multiplicativ în stopuri cu corecție de medie; mască de luminanță (zero în negru adânc). [STOCHASTIC — model artistic calibrat doar ca ordin de mărime]
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace pcfx {
struct Fx {
    double distortion = 0, caRed = 0, caBlue = 0, lensVignette = 0;                    // −100…100
    double vignette = 0, vignetteMid = 50, vignetteRound = 0;                           // vinietă creativă: −100…100 (negativ = întunecă), început 0…100 (% din rază), —
    double halAmount = 0, halRadius = 5, halThreshold = 1.5, halWarm = 0.8;           // halație: 0…100 · rază (×0.2% din înălțime) 1…10 · prag în stopuri peste gri 18% 0…4 · căldură 0…1
    double filmAmount = 0, filmContrast = 0, filmToe = 0.4, filmShoulder = 0.5, filmSat = 1, filmCrosstalk = 0;   // 0…100; −0.5…0.5; 0…1; 0…1; 0.5…1.5; 0…0.3
    double grainAmount = 0, grainSize = 1.5, grainRough = 0.5, grainChroma = 0.3, grainShadows = 1, grainHighlights = 1; int grainSeed = 1, grainRef = 2160;
    bool opticsActive() const { return distortion != 0 || caRed != 0 || caBlue != 0 || lensVignette != 0; }
    bool geometryActive() const { return distortion != 0 || caRed != 0 || caBlue != 0; }
    bool halationActive() const { return halAmount > 0; }
    bool postActive() const { return halAmount > 0 || vignette != 0 || filmAmount > 0 || grainAmount > 0; }
    bool active() const { return opticsActive() || postActive(); }
};
inline double sstep(double a, double b, double x) { double t = std::min(1.0, std::max(0.0, (x - a) / (b - a))); return t * t * (3 - 2 * t); }

// ---------- OPTICĂ ----------
struct Optics { double k1 = 0, k2 = 0, cx = 0, cy = 0, R = 1, caR = 0, caB = 0, vig = 0; bool geo = false; };
inline Optics prepare_optics(const Fx& f, double SW, double SH) {
    Optics o; o.k1 = -f.distortion / 100.0 * 0.25; o.k2 = 0; o.cx = SW / 2; o.cy = SH / 2; o.R = 0.5 * std::hypot(SW, SH);
    o.caR = f.caRed / 100.0 * 0.004; o.caB = f.caBlue / 100.0 * 0.004; o.vig = f.lensVignette / 100.0 * 2.0; o.geo = f.geometryActive(); return o;
}
/// ideal → eșantionat (sursa reală, distorsionată)
inline void distort(const Optics& o, double x, double y, double& dx, double& dy) {
    const double u = x - o.cx, v = y - o.cy, r2 = (u * u + v * v) / (o.R * o.R), g = 1 + o.k1 * r2 + o.k2 * r2 * r2; dx = o.cx + u * g; dy = o.cy + v * g;
}
/// eșantionat → ideal (Newton pe raza normalizată; folosit de ghidajele măștilor sub optică)
inline void undistort(const Optics& o, double dx, double dy, double& x, double& y) {
    const double u = dx - o.cx, v = dy - o.cy, rd = std::hypot(u, v) / o.R; if (rd < 1e-12 || (o.k1 == 0 && o.k2 == 0)) { x = dx; y = dy; return; }
    double ri = rd; for (int i = 0; i < 24; i++) { const double r2 = ri * ri, g = 1 + o.k1 * r2 + o.k2 * r2 * r2, f = ri * g - rd, d = 1 + 3 * o.k1 * r2 + 5 * o.k2 * r2 * r2; if (std::fabs(d) < 1e-9) break; ri -= f / d; }
    const double s = ri / rd; x = o.cx + u * s; y = o.cy + v * s;
}
inline void scale_about(const Optics& o, double dx, double dy, double k, double& x, double& y) { x = o.cx + (dx - o.cx) * (1 + k); y = o.cy + (dy - o.cy) * (1 + k); }
inline double lens_gain(const Optics& o, double dx, double dy) { if (o.vig == 0) return 1; const double u = dx - o.cx, v = dy - o.cy, r2 = (u * u + v * v) / (o.R * o.R); return std::exp2(o.vig * r2); }

// ---------- PELICULĂ ----------
struct Film { double mix = 0, k = 1, D = 8, H = 8, sat = 1, xt = 0; bool on = false; };
inline Film prepare_film(const Fx& f) {
    Film r; r.on = f.filmAmount > 0; r.mix = f.filmAmount / 100.0; r.k = 1 + f.filmContrast; r.D = 8 - 5 * f.filmToe; r.H = 8 - 5.5 * f.filmShoulder; r.sat = f.filmSat; r.xt = f.filmCrosstalk; return r;
}
inline double softclip(double x, double L) { const double k = 0.45 * L; return x <= k ? x : k + (L - k) * std::tanh((x - k) / (L - k)); }
/// stopuri față de gri 18% → stopuri de ieșire (monoton, C¹, asimptote −D / +H)
inline double film_stops(const Film& f, double s) { const double u = s * f.k; return u >= 0 ? softclip(u, f.H) : -softclip(-u, f.D); }
inline double film_channel(const Film& f, double x) {
    if (x <= 0) return 0; const double s = std::log2(x / 0.18), o = film_stops(f, s), fl = std::exp2(-f.D);
    return 0.18 * (std::exp2(o) - fl) / (1 - fl);
}
inline void film_apply(const Film& f, const double luma[3], double c[3]) {
    double a[3] = {c[0], c[1], c[2]};
    if (f.xt > 0) { const double o = f.xt * 0.5, d = 1 - f.xt; a[0] = d * c[0] + o * (c[1] + c[2]); a[1] = d * c[1] + o * (c[0] + c[2]); a[2] = d * c[2] + o * (c[0] + c[1]); }
    double y[3] = {film_channel(f, a[0]), film_channel(f, a[1]), film_channel(f, a[2])};
    if (f.sat != 1) { const double Y = luma[0] * y[0] + luma[1] * y[1] + luma[2] * y[2]; if (Y > 1e-9) for (int i = 0; i < 3; i++) y[i] = y[i] > 0 ? Y * std::pow(y[i] / Y, f.sat) : y[i]; }
    for (int i = 0; i < 3; i++) c[i] += f.mix * (y[i] - c[i]);
}
inline double vignette_gain(const Fx& f, double nx, double ny, double w, double h) {   // nx,ny ∈ [0,1] în ieșire; raza normalizată la colț
    if (f.vignette == 0) return 1; const double u = (nx - 0.5) * w, v = (ny - 0.5) * h, R = 0.5 * std::hypot(w, h), r = std::hypot(u, v) / R, t = sstep(f.vignetteMid / 100.0 * 0.95, 1.0, r);
    return std::exp2(f.vignette / 100.0 * 2.0 * t);
}

// ---------- GRAIN ----------
inline uint32_t hash_u32(uint32_t x) { x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16; return x; }
inline double lattice(int ix, int iy, int ch, uint32_t seed) {   // [−√3, √3], medie 0, varianță 1
    const uint32_t h = hash_u32((uint32_t)ix * 0x9E3779B1U ^ hash_u32((uint32_t)iy * 0x85EBCA6BU + (uint32_t)ch * 0xC2B2AE35U + seed)); return ((h >> 8) * (1.0 / 16777216.0) * 2 - 1) * 1.7320508075688772;
}
/// zgomot de valoare cu interpolare netedă, normalizat la varianță unitară pe pixel (Σw²)
inline double vnoise(double x, double y, int ch, uint32_t seed) {
    const double fx = std::floor(x), fy = std::floor(y); const int ix = (int)fx, iy = (int)fy; double tx = x - fx, ty = y - fy; tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty);
    const double w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty;
    const double n = w00 * lattice(ix, iy, ch, seed) + w10 * lattice(ix + 1, iy, ch, seed) + w01 * lattice(ix, iy + 1, ch, seed) + w11 * lattice(ix + 1, iy + 1, ch, seed);
    return n / std::sqrt(w00 * w00 + w10 * w10 + w01 * w01 + w11 * w11);
}
struct Grain { bool on = false; double sigma = 0, cell = 1, rough = 0.5, chroma = 0.3, sh = 1, hi = 1; uint32_t seed = 1; };
inline Grain prepare_grain(const Fx& f, double outH) {
    Grain g; g.on = f.grainAmount > 0; g.sigma = 0.45 * f.grainAmount / 100.0; g.cell = std::max(0.5, f.grainSize * outH / std::max(1, f.grainRef)); g.rough = f.grainRough; g.chroma = f.grainChroma; g.sh = f.grainShadows; g.hi = f.grainHighlights; g.seed = (uint32_t)f.grainSeed * 2654435761U; return g;
}
inline void grain_apply(const Grain& g, const double luma[3], int px, int py, double c[3]) {
    const double Y = luma[0] * c[0] + luma[1] * c[1] + luma[2] * c[2]; if (Y <= 0) return;
    const double mask = sstep(0.002, 0.05, Y) * (1 - 0.5 * sstep(1.0, 8.0, Y)) * (Y < 0.18 ? (1 + (g.sh - 1) * (1 - sstep(0.02, 0.18, Y))) : (1 + (g.hi - 1) * sstep(0.18, 2.0, Y)));
    if (mask <= 0) return;
    const double x = (px + 0.5) / g.cell, y = (py + 0.5) / g.cell, a = 1.0 / std::sqrt(1 + g.rough * g.rough);
    const double common = a * (vnoise(x, y, 3, g.seed) + g.rough * vnoise(x * 2.3 + 11.7, y * 2.3 + 5.3, 4, g.seed));
    for (int i = 0; i < 3; i++) {
        const double own = a * (vnoise(x, y, i, g.seed) + g.rough * vnoise(x * 2.3 + 11.7, y * 2.3 + 5.3, 5 + i, g.seed));
        const double n = std::sqrt(1 - g.chroma) * common + std::sqrt(g.chroma) * own; const double s = g.sigma * mask;
        c[i] *= std::exp2(s * n - 0.5 * 0.6931471805599453 * s * s);   // corecție de medie în liniar
    }
}
} // namespace pcfx

// ---------- HALAȚIE (pas spațial, liniar, la rezoluția livrabilului) ----------
// Model: sursa = luminanța pixelilor peste prag (poartă netedă, zero sub prag) → PSF cu coadă lungă (0.7·G(σ) + 0.3·G(3σ), σ = rază·0.2% din înălțime) → adăugat aditiv cu pondere per canal (roșu domină; căldura 0 = alb). Energie conservată de blur; ETICHETĂ: CREATIV (nu reprezintă o măsurătoare de stoc).
namespace pcfx {
struct Halation { bool on = false; double amount = 0, sigma = 1, gateLo = 0.5, w[3] = {1, 1, 1}; };
inline Halation prepare_halation(const Fx& f, double outH) {
    Halation h; h.on = f.halAmount > 0; h.amount = f.halAmount / 100.0 * 0.5; h.sigma = std::max(0.5, f.halRadius * 0.002 * outH); h.gateLo = 0.18 * std::exp2(f.halThreshold);
    h.w[0] = 1; h.w[1] = 1 - 0.7 * f.halWarm; h.w[2] = 1 - 0.95 * f.halWarm; return h;
}
inline double halation_gate(const Halation& h, double Y) { return sstep(h.gateLo, 2 * h.gateLo + 0.25, Y); }
/// Estompare gaussiană separabilă aproximată prin 3 treceri de medie mobilă (O(n), independentă de rază); marginile se prelungesc cu valoarea de margine.
inline void box_blur_1d(const float* in, float* out, int n, int r) {
    if (r <= 0 || n <= 1) { for (int i = 0; i < n; i++) out[i] = in[i]; return; }
    const double inv = 1.0 / (2 * r + 1); double acc = 0; for (int k = -r; k <= r; k++) acc += in[std::min(n - 1, std::max(0, k))];
    for (int i = 0; i < n; i++) { out[i] = (float)(acc * inv); const int a = std::min(n - 1, std::max(0, i + r + 1)), b = std::min(n - 1, std::max(0, i - r)); acc += (double)in[a] - in[b]; }
}
inline int box_radius(double sigma, int pass) {   // 3 casete ≈ gaussian: lățime w ≈ sqrt(12σ²/3 + 1)
    const double wIdeal = std::sqrt(12.0 * sigma * sigma / 3.0 + 1.0); int wl = (int)std::floor(wIdeal); if (wl % 2 == 0) wl--; if (wl < 1) wl = 1; const int wu = wl + 2;
    const double m = std::round((12.0 * sigma * sigma - 3.0 * wl * wl - 12.0 * wl - 9.0) / (-4.0 * wl - 4.0)); const int w = pass < (int)m ? wl : wu; return (w - 1) / 2;
}
} // namespace pcfx
