# FotoAsist GC

A macOS application for developing and editing photographs: RAW development, culling, colour and tone tools, local corrections, retouching and batch export. Everything runs locally on your Mac.

FotoAsist GC is free and open source. It needs **no account, no activation, no trial and no licensing server**.

- Author: **Dumitru Cristinel Gordas (GDC)**
- Licence: **GPL-3.0-or-later** (see [LICENSE](LICENSE))
- Product page: https://gordas.dev/foto-asist-gc/
- Also listed in GDC Plugin Manager: https://github.com/gordasgdc/gdc-plugin-manager

Română: [README.ro.md](README.ro.md)

## Project status

The project is **open to contributions** through Issues and Pull Requests and is **maintained occasionally**: answers and reviews can take a while, and there is no support commitment. If you depend on a fix, a pull request is the fastest way to get it. See [CONTRIBUTING.md](CONTRIBUTING.md).

## What it does

All of the following work standalone, with no other software installed:

- **Library and import**: reads RAW files (through LibRaw) and rendered images (JPEG, PNG, TIFF); your originals are never modified and nothing is written next to them.
- **Selection (culling)**: keep / reject decisions, albums, and hints (possibly clipped highlights or shadows, dark or bright frames, less sharp frames in a burst, possible blinks). Hints never decide anything on their own.
- **RAW development**: black level, highlight policy, exposure compensation, working colour space families (DaVinci Wide Gamut / Intermediate, ACES AP1 / ACEScct, ARRI LogC3, ARRI LogC4).
- **Tone and colour**: exposure, white balance, shadows and highlights, contrast with pivot, saturation, lift / gamma / gain, colour wheels, ASC CDL, tonal balance, printer lights, channel mixer, six hue vectors, highlight and gamut handling.
- **Geometry**: crop, straighten, perspective.
- **Colour chart**: ColorChecker Classic correction from four corner points.
- **Detail**: noise reduction and sharpening.
- **Retouching**: clone, heal, manual red-eye correction.
- **Local corrections**: brush, linear, radial and luminance masks; subject mask found locally with Apple Vision (macOS 14 or later).
- **Lens and look**: distortion, lateral chromatic aberration, lens vignette; a simple film look and grain.
- **Analysis**: vectorscope, RGB parade, noise-reduction difference, in the inspector or in separate windows.
- **Profile from examples**: estimates your own adjustments from pairs of original and edited photographs, locally, without machine learning.
- **Batch**: copy and paste adjustments, apply to a selection, review, export with presets (sRGB output).
- **Diagnostics**: a local, redacted log and a diagnostic package you export yourself. Nothing is uploaded.

Interface languages: Romanian, English, Spanish.

### What needs DaVinci Resolve

Nothing in this edition requires DaVinci Resolve. The subject mask can be exported as a matte PNG and imported into Resolve as a file.

The "hand over to Resolve" action is present but needs the FotoAsist OFX component, which is **not part of this edition**; without it the action reports that the component is missing and changes nothing.

### What is not in the open-source edition

FotoAsist GC also exists as a full edition that contains GDC modules which are not open source. They are absent here, their panels are hidden, and the rest of the application works without them:

| Not included | What you have instead |
|---|---|
| GDC DRT (the display rendering transform of the full edition) | An open display transform to sRGB: gamut compression, a ratio-preserving tone curve, progressive highlight desaturation |
| Selective colour and skin tools | Hue vectors, saturation, colour wheels, CDL |
| Diffusion and bloom (optics filter) | — |
| Photochemical film emulation, look library, cinema style library | The simple film look and grain |
| FotoAsist OFX plug-in for Resolve | Standalone processing and export |

Edits saved by the full edition open here; the values of the missing modules are kept in the file but have no effect, and the output is rendered with the open display transform.

## Install

Download `FotoAsistGC-<version>.pkg` from the [Releases](https://github.com/gordasgdc/fotoasist-gc/releases) page and open it. Official packages are signed with a Developer ID and notarized by Apple. Requirements: macOS 13 or later.

Each release package is built from the source tagged with the same version in this repository.

## Build from source

```bash
git clone https://github.com/gordasgdc/fotoasist-gc.git
cd fotoasist-gc
scripts/swift.sh test          # builds LibRaw on first use, then builds and tests
scripts/make_app.sh            # "FotoAsist GC.app" (ad-hoc signed, runs on this Mac)
```

You need macOS 13 or later and the Xcode command line tools. No other repository, key or service is required. Details: [BUILDING.md](BUILDING.md).

## Licence and credits

Copyright © 2026 Dumitru Cristinel Gordas (GDC).

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY; see [LICENSE](LICENSE).

Third-party components and their licences: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). People who wrote the code: [AUTHORS.md](AUTHORS.md).

The name "FotoAsist GC" and its symbol identify the original project. If you distribute a modified version, please give it a different name and symbol.
