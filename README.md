<p align="center">
  <a href="https://gordas.dev/foto-asist-gc/"><img src="https://gordas.dev/foto-asist-gc/assets/hero-laborator.jpg" alt="Illustrative image: a concept sports car in a white laboratory" width="100%"></a>
</p>

<h1 align="center">FotoAsist GC</h1>

<p align="center">
  <b>Everything starts with the photograph.</b><br>
  A photo development and editing app for macOS, with its own colour engine.<br>Free and open source. No account, no activation, no trial.
</p>

<p align="center"><b>English</b> &nbsp;·&nbsp; <a href="README.ro.md">Română</a> &nbsp;·&nbsp; <a href="README.es.md">Español</a></p>

<p align="center"><a href="https://github.com/gordasgdc/fotoasist-gc/releases/latest"><img alt="release" src="https://img.shields.io/github/v/release/gordasgdc/fotoasist-gc?label=release&color=202628"></a> <a href="LICENSE"><img alt="GPL-3.0-or-later" src="https://img.shields.io/badge/license-GPL--3.0--or--later-202628"></a> <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-202628?logo=apple&logoColor=white"> <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-202628?logo=swift&logoColor=white"> <img alt="RO EN ES" src="https://img.shields.io/badge/interface-RO%20%C2%B7%20EN%20%C2%B7%20ES-202628"> <a href="https://github.com/gordasgdc/fotoasist-gc/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/gordasgdc/fotoasist-gc/actions/workflows/ci.yml/badge.svg"></a></p>

<p align="center">
  <a href="https://github.com/gordasgdc/fotoasist-gc/releases/latest"><b>Download for Mac ↓</b></a> &nbsp;·&nbsp;
  <a href="https://gordas.dev/foto-asist-gc/">Product page</a> &nbsp;·&nbsp;
  <a href="BUILDING.md">Build from source</a> &nbsp;·&nbsp;
  <a href="CONTRIBUTING.md">Contribute</a>
</p>

---

## At a glance

<table>
<tr>
<td width="33%" valign="top"><b>Your photographs stay yours</b><br><sub>Originals are opened read-only. Nothing is written into them or next to them, and nothing is uploaded.</sub></td>
<td width="33%" valign="top"><b>One place, from RAW to export</b><br><sub>Import, cull, develop, retouch, review and export in batches, in a single window.</sub></td>
<td width="33%" valign="top"><b>An engine you can read</b><br><sub>The colour pipeline is open: scene-linear and log working spaces, documented stage by stage, covered by tests.</sub></td>
</tr>
</table>

## A tour of the app

<table>
<tr>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-biblioteca.jpg" alt="FotoAsist GC — Library" width="100%"><br><b>Library</b><br><sub>Organised sources and albums, without moving the originals.</sub></td>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-selectie.jpg" alt="FotoAsist GC — Selection" width="100%"><br><b>Selection</b><br><sub>Keep, reject, compare and inspect at 100%.</sub></td>
</tr>
<tr>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-editare.jpg" alt="FotoAsist GC — Editing" width="100%"><br><b>Editing</b><br><sub>Exposure, white balance, tones, masks and geometry.</sub></td>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-profil.jpg" alt="FotoAsist GC — Personal profile" width="100%"><br><b>Personal profile</b><br><sub>A local workflow from original–final pairs you approve.</sub></td>
</tr>
</table>

<sub>Real captures of the application (version 0.9), with synthetic demonstration images, not RAW files.</sub>

## A closer look

The photograph takes the centre; the tools stay within reach.

<p align="center">
  <img src="https://gordas.dev/foto-asist-gc/assets/editor-concept.jpg" alt="FotoAsist GC concept board with a synthetic portrait and colour tools" width="100%">
  <br><sub>Approved visual direction, shown as a concept board. It is not a capture of the current version.</sub>
</p>

## Light, colour, materials

A portrait lives through light and expression. An object, through texture and reflections. The tools should leave room for both.

<table>
<tr>
<td width="42%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/A01_portret-lumina-naturala.jpg" alt="Synthetic portrait in natural light" width="100%"><br><sub><b>Portrait / natural light</b><br>Texture, nuance and quiet light.</sub></td>
<td width="58%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/A07_produs-sticla-ambra.jpg" alt="Synthetic product photograph: amber glass on travertine" width="100%"><br><sub><b>Product / detail</b><br>Reflections, transparency and materials.</sub></td>
</tr>
</table>

<sub>Synthetic presentation images, made separately. They are not RAW files and do not demonstrate before/after results.</sub>

## What it does

Everything below works on its own, with no other software installed.

| Area | What you get |
|---|---|
| **Library and import** | RAW files (through LibRaw) and rendered images (JPEG, PNG, TIFF). Sources and albums without moving the originals. |
| **Selection** | Keep / reject decisions, albums, and hints: possibly clipped highlights or shadows, dark or bright frames, softer frames in a burst, possible blinks. Hints never decide on their own. |
| **RAW development** | Black level, highlight policy, exposure compensation, working families: DaVinci Wide Gamut / Intermediate, ACES AP1 / ACEScct, ARRI LogC3, ARRI LogC4. |
| **Tone and colour** | Exposure, white balance, shadows and highlights, contrast with pivot, saturation, lift / gamma / gain, colour wheels, ASC CDL, tonal balance, printer lights, channel mixer, six hue vectors, highlight and gamut handling. |
| **Geometry** | Crop, straighten, perspective. |
| **Colour chart** | ColorChecker Classic correction from four corner points. |
| **Detail** | Noise reduction and sharpening. |
| **Retouching** | Clone, heal, manual red-eye correction. |
| **Local corrections** | Brush, linear, radial and luminance masks; subject mask found locally with Apple Vision (macOS 14 or later). |
| **Lens and look** | Distortion, lateral chromatic aberration, lens vignette; a simple film look and grain. |
| **Analysis** | Vectorscope, RGB parade, noise-reduction difference, in the inspector or in separate windows. |
| **Profile from examples** | Estimates your own adjustments from pairs of original and edited photographs. Locally, without machine learning. |
| **Batch** | Copy and paste adjustments, apply to a selection, review, export with presets (sRGB output). |
| **Diagnostics** | A local, redacted log and a diagnostic package you export yourself. |

Interface languages: Romanian, English, Spanish.

## On its own, with or without DaVinci Resolve

Nothing in this edition requires DaVinci Resolve. The subject mask can be exported as a matte PNG and imported into Resolve as a file. The "hand over to Resolve" action needs the FotoAsist OFX component, which is not part of this edition; without it the action says so and changes nothing.

## The open-source edition and the full edition

FotoAsist GC also exists as a full edition with GDC modules that are not open source. Here they are absent, their panels are hidden, and the rest of the application works without them.

| Not included here | What you have instead |
|---|---|
| GDC DRT, the display rendering transform of the full edition | An open display transform to sRGB: gamut compression, a ratio-preserving tone curve, progressive highlight desaturation |
| Selective colour and skin tools | Hue vectors, saturation, colour wheels, CDL |
| Diffusion and bloom | — |
| Photochemical film emulation, look library, cinema style library | The simple film look and grain |
| FotoAsist OFX plug-in for Resolve | Standalone processing and export |

Edits saved by the full edition open here. The values of the missing modules are kept in the file but have no effect, and the image is rendered with the open display transform, so it can look different.

## Install

Download <code>FotoAsistGC-&lt;version&gt;.pkg</code> from <a href="https://github.com/gordasgdc/fotoasist-gc/releases/latest">Releases</a> and open it. Official packages are signed with a Developer ID and notarized by Apple, and each one is built from the source tagged with the same version in this repository.

Requirements: macOS 13 or later. The subject mask needs macOS 14.

## Build from source

```bash
git clone https://github.com/gordasgdc/fotoasist-gc.git
cd fotoasist-gc
scripts/swift.sh test      # builds LibRaw on first use, then builds and tests
scripts/make_app.sh        # "FotoAsist GC.app", ad-hoc signed, runs on this Mac
```

You need macOS 13 or later and the Xcode command line tools. No other repository, key or service is required. Details: [BUILDING.md](BUILDING.md).

## Project status

The project is **open to contributions** through Issues and Pull Requests and is **maintained occasionally**: replies and reviews can take a while, and there is no support commitment. If you depend on a fix, a pull request is the fastest way to get it. Start with [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence and credits

Copyright © 2026 **Dumitru Cristinel Gordas (GDC)**.

FotoAsist GC is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY. See [LICENSE](LICENSE).

Third-party components and their licences: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The people who wrote the code: [AUTHORS.md](AUTHORS.md).

The name "FotoAsist GC", its symbol and the presentation images on this page identify the original project and are not covered by the GPL. If you distribute a modified version, please give it a different name and symbol.

Also listed in [GDC Plugin Manager](https://github.com/gordasgdc/gdc-plugin-manager).
