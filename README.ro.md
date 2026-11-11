<p align="center">
  <a href="https://gordas.dev/foto-asist-gc/"><img src="https://gordas.dev/foto-asist-gc/assets/hero-laborator.jpg" alt="Imagine ilustrativă: automobil sport conceptual într-un laborator alb" width="100%"></a>
</p>

<h1 align="center">FotoAsist GC</h1>

<p align="center">
  <b>Totul pornește de la fotografie.</b><br>
  Aplicație macOS pentru developarea și editarea fotografiilor, cu motor de culoare propriu.<br>Gratuită și cu sursă deschisă. Fără cont, fără activare, fără perioadă de probă.
</p>

<p align="center"><a href="README.md">English</a> &nbsp;·&nbsp; <b>Română</b> &nbsp;·&nbsp; <a href="README.es.md">Español</a></p>

<p align="center"><a href="https://github.com/gordasgdc/fotoasist-gc/releases/latest"><img alt="release" src="https://img.shields.io/github/v/release/gordasgdc/fotoasist-gc?label=release&color=202628"></a> <a href="LICENSE"><img alt="GPL-3.0-or-later" src="https://img.shields.io/badge/license-GPL--3.0--or--later-202628"></a> <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-202628?logo=apple&logoColor=white"> <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-202628?logo=swift&logoColor=white"> <img alt="RO EN ES" src="https://img.shields.io/badge/interfață-RO%20%C2%B7%20EN%20%C2%B7%20ES-202628"> <a href="https://github.com/gordasgdc/fotoasist-gc/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/gordasgdc/fotoasist-gc/actions/workflows/ci.yml/badge.svg"></a></p>

<p align="center">
  <a href="https://github.com/gordasgdc/fotoasist-gc/releases/latest"><b>Descarcă pentru Mac ↓</b></a> &nbsp;·&nbsp;
  <a href="https://gordas.dev/foto-asist-gc/">Pagina produsului</a> &nbsp;·&nbsp;
  <a href="BUILDING.md">Construiește din sursă</a> &nbsp;·&nbsp;
  <a href="CONTRIBUTING.md">Contribuie</a>
</p>

---

## Pe scurt

<table>
<tr>
<td width="33%" valign="top"><b>Fotografiile rămân ale tale</b><br><sub>Originalele se deschid doar în citire. Nu se scrie nimic în ele sau lângă ele și nu se încarcă nimic nicăieri.</sub></td>
<td width="33%" valign="top"><b>Un singur loc, de la RAW la export</b><br><sub>Import, selecție, developare, retuș, revizuire și export în lot, într-o singură fereastră.</sub></td>
<td width="33%" valign="top"><b>Un motor pe care îl poți citi</b><br><sub>Lanțul de culoare este deschis: spații de lucru liniare și logaritmice, documentat etapă cu etapă, acoperit de teste.</sub></td>
</tr>
</table>

## Un tur al aplicației

<table>
<tr>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-biblioteca.jpg" alt="FotoAsist GC — Bibliotecă" width="100%"><br><b>Bibliotecă</b><br><sub>Surse și albume organizate, fără mutarea originalelor.</sub></td>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-selectie.jpg" alt="FotoAsist GC — Selecție" width="100%"><br><b>Selecție</b><br><sub>Păstrează, respinge, compară și inspectează la 100%.</sub></td>
</tr>
<tr>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-editare.jpg" alt="FotoAsist GC — Editare" width="100%"><br><b>Editare</b><br><sub>Expunere, balans de alb, tonuri, măști și geometrie.</sub></td>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-profil.jpg" alt="FotoAsist GC — Profil personal" width="100%"><br><b>Profil personal</b><br><sub>Flux local din perechi original–final aprobate de tine.</sub></td>
</tr>
</table>

<sub>Capturi reale ale aplicației (versiunea 0.9), cu imagini sintetice demonstrative, nu fișiere RAW.</sub>

## Mai aproape de imagine

Fotografia ocupă centrul; instrumentele rămân la îndemână.

<p align="center">
  <img src="https://gordas.dev/foto-asist-gc/assets/editor-concept.jpg" alt="Planșă de concept FotoAsist GC cu portret sintetic și instrumente de culoare" width="100%">
  <br><sub>Direcție vizuală aprobată, prezentată ca planșă de concept. Nu este o captură a versiunii curente.</sub>
</p>

## Lumină, culoare, materiale

Un portret trăiește prin lumină și expresie. Un obiect, prin textură și reflexii. Instrumentele trebuie să lase loc fiecăruia.

<table>
<tr>
<td width="42%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/A01_portret-lumina-naturala.jpg" alt="Portret sintetic în lumină naturală" width="100%"><br><sub><b>Portret / lumină naturală</b><br>Textură, nuanțe și lumină discretă.</sub></td>
<td width="58%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/A07_produs-sticla-ambra.jpg" alt="Fotografie sintetică de produs: sticlă ambră pe travertin" width="100%"><br><sub><b>Produs / detaliu</b><br>Reflexii, transparență și materiale.</sub></td>
</tr>
</table>

<sub>Imagini sintetice de prezentare, realizate separat. Nu sunt fișiere RAW și nu demonstrează rezultate înainte/după.</sub>

## Ce face

Tot ce urmează merge independent, fără alt program instalat.

| Zonă | Ce primești |
|---|---|
| **Bibliotecă și import** | Fișiere RAW (prin LibRaw) și imagini redate (JPEG, PNG, TIFF). Surse și albume fără mutarea originalelor. |
| **Selecție** | Decizii păstrează / respinge, albume și indicii: lumini sau umbre posibil tăiate, cadre întunecate sau luminoase, cadre mai puțin clare într-o rafală, posibile clipiri. Indiciile nu decid nimic singure. |
| **Developare RAW** | Nivel de negru, politica luminilor, compensare de expunere, familii de lucru: DaVinci Wide Gamut / Intermediate, ACES AP1 / ACEScct, ARRI LogC3, ARRI LogC4. |
| **Ton și culoare** | Expunere, balans de alb, umbre și lumini, contrast cu pivot, saturație, lift / gamma / gain, roți de culoare, ASC CDL, balans tonal, lumini de imprimare, mixer de canale, șase vectori de nuanță, lumini și gamă. |
| **Geometrie** | Decupare, îndreptare, perspectivă. |
| **Chart de culoare** | Corecție cu ColorChecker Classic, din patru colțuri. |
| **Detaliu** | Reducere de zgomot și claritate. |
| **Retuș** | Clonă, vindecare, corecție manuală de ochi roșii. |
| **Corecții locale** | Măști pensulă, liniară, radială și de luminanță; mască de subiect găsită local cu Apple Vision (macOS 14 sau mai nou). |
| **Obiectiv și aspect** | Distorsiune, aberație cromatică laterală, vinietă; un aspect pelicular simplu și grăunte. |
| **Analiză** | Vectorscop, RGB parade, diferență de reducere a zgomotului, în inspector sau în ferestre separate. |
| **Profil din exemple** | Estimează reglajele tale din perechi original + fotografie editată. Local, fără învățare automată. |
| **Lot** | Copiere și lipire de reglaje, aplicare pe o selecție, revizuire, export cu presetări (ieșire sRGB). |
| **Diagnostic** | Jurnal local redactat și pachet de diagnostic pe care îl exporți tu. |

Limbile interfeței: română, engleză, spaniolă.

## Independent, cu sau fără DaVinci Resolve

Nimic din această ediție nu cere DaVinci Resolve. Masca de subiect se poate exporta ca matte PNG și importa în Resolve ca fișier. Acțiunea «predare în Resolve» are nevoie de componenta FotoAsist OFX, care nu face parte din această ediție; fără ea, acțiunea spune acest lucru și nu schimbă nimic.

## Ediția cu sursă deschisă și ediția completă

FotoAsist GC există și într-o ediție completă, cu module GDC care nu sunt cu sursă deschisă. Aici ele lipsesc, panourile lor sunt ascunse, iar restul aplicației funcționează fără ele.

| Nu este inclus aici | Ce ai în loc |
|---|---|
| GDC DRT, transformarea de redare a ediției complete | O transformare de afișare deschisă spre sRGB: compresie de gamă, curbă de ton cu păstrarea raporturilor, desaturare progresivă în lumini |
| Culoare selectivă și piele | Vectori de nuanță, saturație, roți de culoare, CDL |
| Difuzie și bloom | — |
| Emulație fotochimică de film, biblioteca de look-uri, biblioteca de stiluri cinema | Aspectul pelicular simplu și grăuntele |
| Pluginul OFX FotoAsist pentru Resolve | Procesare și export independente |

Editările salvate de ediția completă se deschid aici. Valorile modulelor absente rămân în fișier, fără efect, iar imaginea se redă cu transformarea de afișare deschisă, deci poate arăta diferit.

## Instalare

Descarcă <code>FotoAsistGC-&lt;versiune&gt;.pkg</code> din <a href="https://github.com/gordasgdc/fotoasist-gc/releases/latest">Releases</a> și deschide-l. Pachetele oficiale sunt semnate cu Developer ID și notarizate de Apple, iar fiecare este construit din sursa etichetată cu aceeași versiune în acest depozit.

Cerințe: macOS 13 sau mai nou. Masca de subiect cere macOS 14.

## Construire din sursă

```bash
git clone https://github.com/gordasgdc/fotoasist-gc.git
cd fotoasist-gc
scripts/swift.sh test      # construiește LibRaw la prima rulare, apoi compilează și testează
scripts/make_app.sh        # «FotoAsist GC.app», semnătură ad-hoc, rulează pe acest Mac
```

Ai nevoie de macOS 13 sau mai nou și de Xcode command line tools. Nu e necesar niciun alt depozit, nicio cheie și niciun serviciu. Detalii: [BUILDING.md](BUILDING.md).

## Starea proiectului

Proiectul este **deschis contribuțiilor** prin Issues și Pull Requests și are **mentenanță ocazională**: răspunsurile și reviziile pot întârzia și nu există un angajament de suport. Dacă depinzi de o corecție, un pull request este calea cea mai rapidă. Începe cu [CONTRIBUTING.md](CONTRIBUTING.md).

## Licență și credite

Copyright © 2026 **Dumitru Cristinel Gordas (GDC)**.

FotoAsist GC este program liber: îl poți redistribui și modifica în condițiile GNU General Public License publicate de Free Software Foundation, versiunea 3 sau (la alegerea ta) orice versiune ulterioară. Este distribuit FĂRĂ NICIO GARANȚIE. Vezi [LICENSE](LICENSE).

Componentele terțe și licențele lor: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Oamenii care au scris codul: [AUTHORS.md](AUTHORS.md).

Numele «FotoAsist GC», simbolul lui și imaginile de prezentare din această pagină identifică proiectul original și nu sunt acoperite de GPL. Dacă distribui o versiune modificată, te rog să îi dai alt nume și alt simbol.

Apare și în [GDC Plugin Manager](https://github.com/gordasgdc/gdc-plugin-manager).
