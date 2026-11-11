# FotoAsist GC

Aplicație macOS pentru developarea și editarea fotografiilor: developare RAW, selecție, instrumente de ton și culoare, corecții locale, retuș și export în lot. Totul rulează local, pe Mac-ul tău.

FotoAsist GC este gratuit și cu sursă deschisă. **Nu cere cont, activare, perioadă de probă sau server de licențiere.**

- Autor: **Dumitru Cristinel Gordas (GDC)**
- Licență: **GPL-3.0-or-later** (vezi [LICENSE](LICENSE))
- Pagina produsului: https://gordas.dev/foto-asist-gc/
- Apare și în GDC Plugin Manager: https://github.com/gordasgdc/gdc-plugin-manager

English: [README.md](README.md)

## Starea proiectului

Proiectul este **deschis contribuțiilor** prin Issues și Pull Requests și are **mentenanță ocazională**: răspunsurile și reviziile pot întârzia și nu există un angajament de suport. Dacă depinzi de o corecție, un pull request este calea cea mai rapidă. Vezi [CONTRIBUTING.md](CONTRIBUTING.md).

## Ce face

Toate funcțiile de mai jos merg independent, fără alt program instalat:

- **Bibliotecă și import**: citește fișiere RAW (prin LibRaw) și imagini redate (JPEG, PNG, TIFF); originalele nu sunt modificate și nu se scrie nimic lângă ele.
- **Selecție**: decizii păstrează / respinge, albume și indicii (lumini sau umbre posibil tăiate, cadre întunecate sau luminoase, cadre mai puțin clare într-o rafală, posibile clipiri). Indiciile nu decid nimic singure.
- **Developare RAW**: nivel de negru, politica luminilor, compensare de expunere, familii de lucru (DaVinci Wide Gamut / Intermediate, ACES AP1 / ACEScct, ARRI LogC3, ARRI LogC4).
- **Ton și culoare**: expunere, balans de alb, umbre și lumini, contrast cu pivot, saturație, lift / gamma / gain, roți de culoare, ASC CDL, balans tonal, lumini de imprimare, mixer de canale, șase vectori de nuanță, lumini și gamă.
- **Geometrie**: decupare, îndreptare, perspectivă.
- **Chart de culoare**: corecție cu ColorChecker Classic, din patru colțuri.
- **Detaliu**: reducere de zgomot și claritate.
- **Retuș**: clonă, vindecare, corecție manuală de ochi roșii.
- **Corecții locale**: măști pensulă, liniară, radială și de luminanță; mască de subiect găsită local cu Apple Vision (macOS 14 sau mai nou).
- **Obiectiv și aspect**: distorsiune, aberație cromatică laterală, vinietă; un aspect pelicular simplu și grăunte.
- **Analiză**: vectorscop, RGB parade, diferență de reducere a zgomotului, în inspector sau în ferestre separate.
- **Profil din exemple**: estimează local reglajele tale din perechi original + fotografie editată, fără învățare automată.
- **Lot**: copiere și lipire de reglaje, aplicare pe o selecție, revizuire, export cu presetări (ieșire sRGB).
- **Diagnostic**: jurnal local redactat și pachet de diagnostic pe care îl exporți tu. Nu se încarcă nimic nicăieri.

Limbile interfeței: română, engleză, spaniolă.

### Ce cere DaVinci Resolve

Nimic din această ediție nu cere DaVinci Resolve. Masca de subiect se poate exporta ca matte PNG și importa în Resolve ca fișier.

Acțiunea «predare în Resolve» există, dar are nevoie de componenta FotoAsist OFX, care **nu face parte din această ediție**; fără ea, acțiunea spune că lipsește componenta și nu schimbă nimic.

### Ce nu este în ediția cu sursă deschisă

FotoAsist GC există și într-o ediție completă, cu module GDC care nu sunt cu sursă deschisă. Aici ele lipsesc, panourile lor sunt ascunse, iar restul aplicației funcționează fără ele:

| Nu este inclus | Ce ai în loc |
|---|---|
| GDC DRT (transformarea de redare a ediției complete) | O transformare de afișare deschisă spre sRGB: compresie de gamă, curbă de ton cu păstrarea raporturilor, desaturare progresivă în lumini |
| Culoare selectivă și piele | Vectori de nuanță, saturație, roți de culoare, CDL |
| Difuzie și bloom (filtru de obiectiv) | — |
| Emulație fotochimică de film, biblioteca de look-uri, biblioteca de stiluri cinema | Aspectul pelicular simplu și grăuntele |
| Pluginul OFX FotoAsist pentru Resolve | Procesare și export independente |

Editările salvate de ediția completă se deschid aici; valorile modulelor absente rămân în fișier, fără efect, iar imaginea se redă cu transformarea de afișare deschisă.

## Instalare

Descarcă `FotoAsistGC-<versiune>.pkg` din pagina [Releases](https://github.com/gordasgdc/fotoasist-gc/releases) și deschide-l. Pachetele oficiale sunt semnate cu Developer ID și notarizate de Apple. Cerințe: macOS 13 sau mai nou.

Fiecare pachet publicat este construit din sursa etichetată cu aceeași versiune în acest depozit.

## Construire din sursă

```bash
git clone https://github.com/gordasgdc/fotoasist-gc.git
cd fotoasist-gc
scripts/swift.sh test          # construiește LibRaw la prima rulare, apoi compilează și testează
scripts/make_app.sh            # «FotoAsist GC.app» (semnătură ad-hoc, rulează pe acest Mac)
```

Ai nevoie de macOS 13 sau mai nou și de Xcode command line tools. Nu e necesar niciun alt depozit, nicio cheie și niciun serviciu. Detalii: [BUILDING.md](BUILDING.md).

## Licență și credite

Copyright © 2026 Dumitru Cristinel Gordas (GDC).

Program liber: îl poți redistribui și modifica în condițiile GNU General Public License, versiunea 3 sau (la alegerea ta) orice versiune ulterioară. Este distribuit FĂRĂ NICIO GARANȚIE; vezi [LICENSE](LICENSE).

Componentele terțe și licențele lor: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Oamenii care au scris codul: [AUTHORS.md](AUTHORS.md).

Numele «FotoAsist GC» și simbolul lui identifică proiectul original. Dacă distribui o versiune modificată, te rog să îi dai alt nume și alt simbol.
