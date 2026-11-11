# Third-party notices

FotoAsist GC (open-source edition) is licensed under GPL-3.0-or-later. It uses the components below. Their notices must be kept when the application or its source is redistributed.

## Distributed with the application

### LibRaw 0.22.1

- Copyright © 2008–2025 LibRaw LLC (info@libraw.org). LibRaw uses code from dcraw.c, © 1997–2018 Dave Coffin; see the `COPYRIGHT` file of the LibRaw distribution for the complete list of notices.
- Licence: GNU Lesser General Public License version 2.1 **or** Common Development and Distribution License version 1.0, at the recipient's choice. FotoAsist GC uses it under the LGPL-2.1.
- Source: the unmodified official archive https://www.libraw.org/data/LibRaw-0.22.1.tar.gz (SHA-256 `a789dc4e2409e2901d93793a4e0b80c7b49d0d97cf6ad71c850eb7616acfd786`), built by `scripts/build_libraw.sh` without the GPL demosaic packs, lcms, libjpeg or OpenMP.
- Linking: dynamic. The library is a separate file, `FotoAsist GC.app/Contents/Frameworks/libraw_r.*.dylib`, found through `@rpath`, so you can replace it with your own build of LibRaw.
- The licence texts (`LICENSE.LGPL`, `LICENSE.CDDL`) and `COPYRIGHT` are installed in `FotoAsist GC.app/Contents/Resources/licenses/LibRaw/`.

## Used from the operating system (not distributed)

SQLite, zlib, ImageIO, Core Graphics, Core Image, Vision, Security, AppKit, SwiftUI, Combine, CryptoKit and the Swift runtime are part of macOS and are used under Apple's terms as system libraries.

## Reference data

- **ColorChecker Classic reference values** (`core/Sources/PhotoResolve/Resources/charts/colorchecker_classic.json`): colorimetric values published by X-Rite ("New color specifications for ColorChecker SG and Classic charts", 2016) for the edition made after November 2014 and for the legacy edition made before it, taken through the datasets of the Colour library 0.4.7 (colour-science, BSD-3-Clause, © Colour Developers), which is used only as the carrier of the numbers. The file records the source of each edition. These are measurements, used as reference numbers.

## Published formulas implemented here

The implementations are original; the definitions come from public documents:

- DaVinci Intermediate and DaVinci Wide Gamut — Blackmagic Design, "DaVinci Resolve 17 Wide Gamut Intermediate".
- ACEScct and ACES AP1 — Academy of Motion Picture Arts and Sciences, S-2016-001.
- ARRI LogC3 (EI 800), ARRI Wide Gamut 3, LogC4 and ARRI Wide Gamut 4 — ARRI technical documentation.
- sRGB — IEC 61966-2-1. Rec.709 primaries — ITU-R BT.709.
- Bradford chromatic adaptation; correlated colour temperature after McCamy (1992); Planckian locus approximation after Kang et al. (2002); ASC CDL — American Society of Cinematographers.
- OpenEXR file layout (scanline, ZIP) — Academy Software Foundation specification; the writer here is original code.

## Methods studied, no code taken

- The manual red-eye correction follows the idea documented in LightCraft's `redeye.rs` (MIT OR Apache-2.0, https://github.com/storytold/lightcraft). The implementation is original Swift code; nothing was copied.

## Trademarks

DaVinci Resolve, DaVinci Wide Gamut and DaVinci Intermediate are trademarks of Blackmagic Design Pty Ltd. ColorChecker is a trademark of X-Rite / Calibrite. ARRI, LogC and ARRI Wide Gamut are trademarks of Arnold & Richter Cine Technik GmbH & Co. Betriebs KG. ACES is a trademark of the Academy of Motion Picture Arts and Sciences. Apple, macOS and Vision are trademarks of Apple Inc. These names are used only to describe compatibility; FotoAsist GC is not affiliated with or endorsed by their owners.

"FotoAsist GC" and its symbol identify the original project by Dumitru Cristinel Gordas (GDC). The GPL covers the code; it does not grant the right to present a modified version as the original.
