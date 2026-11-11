<p align="center">
  <a href="https://gordas.dev/foto-asist-gc/"><img src="https://gordas.dev/foto-asist-gc/assets/hero-laborator.jpg" alt="Imagen ilustrativa: un deportivo conceptual en un laboratorio blanco" width="100%"></a>
</p>

<h1 align="center">FotoAsist GC</h1>

<p align="center">
  <b>Todo empieza con la fotografía.</b><br>
  Aplicación de revelado y edición de fotografías para macOS, con motor de color propio.<br>Gratuita y de código abierto. Sin cuenta, sin activación, sin periodo de prueba.
</p>

<p align="center"><a href="README.md">English</a> &nbsp;·&nbsp; <a href="README.ro.md">Română</a> &nbsp;·&nbsp; <b>Español</b></p>

<p align="center"><a href="https://github.com/gordasgdc/fotoasist-gc/releases/latest"><img alt="release" src="https://img.shields.io/github/v/release/gordasgdc/fotoasist-gc?label=release&color=202628"></a> <a href="LICENSE"><img alt="GPL-3.0-or-later" src="https://img.shields.io/badge/license-GPL--3.0--or--later-202628"></a> <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-202628?logo=apple&logoColor=white"> <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-202628?logo=swift&logoColor=white"> <img alt="RO EN ES" src="https://img.shields.io/badge/interfaz-RO%20%C2%B7%20EN%20%C2%B7%20ES-202628"> <a href="https://github.com/gordasgdc/fotoasist-gc/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/gordasgdc/fotoasist-gc/actions/workflows/ci.yml/badge.svg"></a></p>

<p align="center">
  <a href="https://github.com/gordasgdc/fotoasist-gc/releases/latest"><b>Descargar para Mac ↓</b></a> &nbsp;·&nbsp;
  <a href="https://gordas.dev/foto-asist-gc/">Página del producto</a> &nbsp;·&nbsp;
  <a href="BUILDING.md">Compilar desde el código</a> &nbsp;·&nbsp;
  <a href="CONTRIBUTING.md">Contribuir</a>
</p>

---

## De un vistazo

<table>
<tr>
<td width="33%" valign="top"><b>Tus fotografías siguen siendo tuyas</b><br><sub>Los originales se abren solo en lectura. No se escribe nada en ellos ni junto a ellos, y no se sube nada a ningún sitio.</sub></td>
<td width="33%" valign="top"><b>Un solo lugar, del RAW a la exportación</b><br><sub>Importación, selección, revelado, retoque, revisión y exportación por lotes, en una sola ventana.</sub></td>
<td width="33%" valign="top"><b>Un motor que puedes leer</b><br><sub>La cadena de color es abierta: espacios de trabajo lineales y logarítmicos, documentada etapa por etapa y cubierta por pruebas.</sub></td>
</tr>
</table>

## Un recorrido por la aplicación

<table>
<tr>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-biblioteca-1.0.0.jpg" alt="FotoAsist GC — Biblioteca" width="100%"><br><b>Biblioteca</b><br><sub>Fuentes y álbumes organizados, sin mover los originales.</sub></td>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-selectie-1.0.0.jpg" alt="FotoAsist GC — Selección" width="100%"><br><b>Selección</b><br><sub>Conserva, descarta, compara e inspecciona al 100%.</sub></td>
</tr>
<tr>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-editare-1.0.0.jpg" alt="FotoAsist GC — Edición" width="100%"><br><b>Edición</b><br><sub>Exposición, balance de blancos, tonos, máscaras y geometría.</sub></td>
<td width="50%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/app-profil-1.0.0.jpg" alt="FotoAsist GC — Perfil personal" width="100%"><br><b>Perfil personal</b><br><sub>Flujo local a partir de pares original–final que tú apruebas.</sub></td>
</tr>
</table>

<sub>Capturas reales de la aplicación (versión 1.0.0), con imágenes sintéticas de demostración, no archivos RAW.</sub>

## Más cerca de la imagen

La fotografía ocupa el centro; las herramientas quedan a mano.

<p align="center">
  <img src="https://gordas.dev/foto-asist-gc/assets/editor-concept.jpg" alt="Lámina de concepto de FotoAsist GC con un retrato sintético y herramientas de color" width="100%">
  <br><sub>Dirección visual aprobada, presentada como lámina de concepto. No es una captura de la versión actual.</sub>
</p>

## Luz, color, materiales

Un retrato vive de la luz y la expresión. Un objeto, de la textura y los reflejos. Las herramientas deben dejar espacio a ambos.

<table>
<tr>
<td width="42%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/A01_portret-lumina-naturala.jpg" alt="Retrato sintético con luz natural" width="100%"><br><sub><b>Retrato / luz natural</b><br>Textura, matices y luz discreta.</sub></td>
<td width="58%" valign="top"><img src="https://gordas.dev/foto-asist-gc/assets/A07_produs-sticla-ambra.jpg" alt="Fotografía sintética de producto: vidrio ámbar sobre travertino" width="100%"><br><sub><b>Producto / detalle</b><br>Reflejos, transparencia y materiales.</sub></td>
</tr>
</table>

<sub>Imágenes sintéticas de presentación, creadas por separado. No son archivos RAW y no demuestran resultados de antes/después.</sub>

## Qué hace

Todo lo siguiente funciona por sí solo, sin ningún otro programa instalado.

| Área | Qué obtienes |
|---|---|
| **Biblioteca e importación** | Archivos RAW (mediante LibRaw) e imágenes renderizadas (JPEG, PNG, TIFF). Fuentes y álbumes sin mover los originales. |
| **Selección** | Decisiones de conservar / descartar, álbumes e indicios: luces o sombras posiblemente recortadas, tomas oscuras o claras, tomas menos nítidas en una ráfaga, posibles parpadeos. Los indicios nunca deciden por sí solos. |
| **Revelado RAW** | Nivel de negro, política de luces, compensación de exposición, familias de trabajo: DaVinci Wide Gamut / Intermediate, ACES AP1 / ACEScct, ARRI LogC3, ARRI LogC4. |
| **Tono y color** | Exposición, balance de blancos, sombras y luces, contraste con pivote, saturación, lift / gamma / gain, ruedas de color, ASC CDL, balance tonal, luces de impresión, mezclador de canales, seis vectores de tono, luces y gama. |
| **Geometría** | Recorte, enderezado, perspectiva. |
| **Carta de color** | Corrección con ColorChecker Classic a partir de cuatro esquinas. |
| **Detalle** | Reducción de ruido y nitidez. |
| **Retoque** | Clonar, corregir, corrección manual de ojos rojos. |
| **Correcciones locales** | Máscaras de pincel, lineal, radial y de luminancia; máscara de sujeto detectada localmente con Apple Vision (macOS 14 o posterior). |
| **Objetivo y aspecto** | Distorsión, aberración cromática lateral, viñeteo; un aspecto de película sencillo y grano. |
| **Análisis** | Vectorscopio, RGB parade, diferencia de reducción de ruido, en el inspector o en ventanas separadas. |
| **Perfil a partir de ejemplos** | Estima tus propios ajustes a partir de pares de fotografía original y editada. En local, sin aprendizaje automático. |
| **Lotes** | Copiar y pegar ajustes, aplicar a una selección, revisar, exportar con ajustes predefinidos (salida sRGB). |
| **Diagnóstico** | Un registro local anonimizado y un paquete de diagnóstico que exportas tú. |

Idiomas de la interfaz: rumano, inglés, español.

## Por sí sola, con o sin DaVinci Resolve

Nada en esta edición requiere DaVinci Resolve. La máscara de sujeto se puede exportar como matte PNG e importar en Resolve como archivo. La acción «entregar a Resolve» necesita el componente FotoAsist OFX, que no forma parte de esta edición; sin él, la acción lo indica y no cambia nada.

## La edición de código abierto y la edición completa

FotoAsist GC existe también en una edición completa, con módulos GDC que no son de código abierto. Aquí no están, sus paneles se ocultan y el resto de la aplicación funciona sin ellos.

| No incluido aquí | Lo que tienes en su lugar |
|---|---|
| GDC DRT, la transformación de salida de la edición completa | Una transformación de salida abierta a sRGB: compresión de gama, curva de tono que conserva las proporciones, desaturación progresiva en las luces |
| Color selectivo y piel | Vectores de tono, saturación, ruedas de color, CDL |
| Difusión y bloom | — |
| Emulación fotoquímica de película, biblioteca de looks, biblioteca de estilos de cine | El aspecto de película sencillo y el grano |
| Plugin OFX de FotoAsist para Resolve | Procesamiento y exportación independientes |

Las ediciones guardadas por la edición completa se abren aquí. Los valores de los módulos ausentes se conservan en el archivo, sin efecto, y la imagen se renderiza con la transformación de salida abierta, por lo que puede verse distinta.

## Instalación

Descarga <code>FotoAsistGC-&lt;versión&gt;.pkg</code> desde <a href="https://github.com/gordasgdc/fotoasist-gc/releases/latest">Releases</a> y ábrelo. Los paquetes oficiales están firmados con Developer ID y notarizados por Apple, y cada uno se compila a partir del código etiquetado con la misma versión en este repositorio.

Requisitos: macOS 13 o posterior. La máscara de sujeto requiere macOS 14.

## Compilar desde el código

```bash
git clone https://github.com/gordasgdc/fotoasist-gc.git
cd fotoasist-gc
scripts/swift.sh test      # compila LibRaw la primera vez; después compila y ejecuta las pruebas
scripts/make_app.sh        # «FotoAsist GC.app», firma ad-hoc, se ejecuta en este Mac
```

Necesitas macOS 13 o posterior y las herramientas de línea de comandos de Xcode. No hace falta ningún otro repositorio, clave ni servicio. Detalles: [BUILDING.md](BUILDING.md) (en inglés).

## Estado del proyecto

El proyecto está **abierto a contribuciones** mediante Issues y Pull Requests y tiene **mantenimiento ocasional**: las respuestas y revisiones pueden tardar y no hay compromiso de soporte. Si dependes de una corrección, un pull request es la vía más rápida. Empieza por [CONTRIBUTING.md](CONTRIBUTING.md) (en inglés).

## Licencia y créditos

Copyright © 2026 **Dumitru Cristinel Gordas (GDC)**.

FotoAsist GC es software libre: puedes redistribuirlo y modificarlo según los términos de la GNU General Public License publicada por la Free Software Foundation, versión 3 o (a tu elección) cualquier versión posterior. Se distribuye SIN NINGUNA GARANTÍA. Consulta [LICENSE](LICENSE).

Componentes de terceros y sus licencias: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Las personas que escribieron el código: [AUTHORS.md](AUTHORS.md).

El nombre «FotoAsist GC», su símbolo y las imágenes de presentación de esta página identifican el proyecto original y no están cubiertos por la GPL. Si distribuyes una versión modificada, dale otro nombre y otro símbolo.

También aparece en [GDC Plugin Manager](https://github.com/gordasgdc/gdc-plugin-manager).
