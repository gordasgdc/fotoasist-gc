#!/bin/bash
# Builds the installer package from the app made by scripts/make_app.sh. Unsigned by default.
# The installer always shows the licence step. Nothing is installed by this script.
# Maintainer only (official release): FOTOASIST_SIGN_INSTALLER="Developer ID Installer: …" signs the package;
# notarization and stapling are done afterwards with the maintainer's own credentials (see BUILDING.md).
# Output: $FOTOASIST_BUILD_ROOT/pkg/FotoAsistGC-<version>.pkg (+ SHA256SUMS.txt)
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$FOTOASIST_REPO"
APP="$FOTOASIST_BUILD_ROOT/app/FotoAsist GC.app"; [ -d "$APP" ] || scripts/make_app.sh
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="$FOTOASIST_BUILD_ROOT/pkg"; rm -rf "$OUT"; mkdir -p "$OUT/stage" "$OUT/res"
ditto "$APP" "$OUT/stage/FotoAsist GC.app"
cp packaging/INSTALLER_LICENSE.txt "$OUT/res/license.txt"
cat > "$OUT/component.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><array><dict>
<key>BundleIsRelocatable</key><false/><key>BundleIsVersionChecked</key><false/><key>BundleHasStrictIdentifier</key><true/>
<key>RootRelativeBundlePath</key><string>FotoAsist GC.app</string>
</dict></array></plist>
PL
pkgbuild --root "$OUT/stage" --component-plist "$OUT/component.plist" --install-location /Applications --identifier "dev.gordas.photoassist.pkg.app" --version "$VER" "$OUT/FotoAsistGC-app.pkg" >/dev/null
cat > "$OUT/Distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>FotoAsist GC $VER</title>
  <license file="license.txt" mime-type="text/plain"/>
  <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
  <domains enable_localSystem="true"/>
  <choices-outline><line choice="app"/></choices-outline>
  <choice id="app" title="FotoAsist GC $VER"><pkg-ref id="dev.gordas.photoassist.pkg.app"/></choice>
  <pkg-ref id="dev.gordas.photoassist.pkg.app" version="$VER">FotoAsistGC-app.pkg</pkg-ref>
</installer-gui-script>
XML
PKG="$OUT/FotoAsistGC-$VER.pkg"
SIGN=(); [ -n "${FOTOASIST_SIGN_INSTALLER:-}" ] && SIGN=(--sign "$FOTOASIST_SIGN_INSTALLER" --timestamp)
productbuild --distribution "$OUT/Distribution.xml" --resources "$OUT/res" --package-path "$OUT" ${SIGN[@]+"${SIGN[@]}"} "$PKG" >/dev/null
rm -rf "$OUT/stage" "$OUT/FotoAsistGC-app.pkg"
( cd "$OUT" && shasum -a 256 "FotoAsistGC-$VER.pkg" > SHA256SUMS.txt && cat SHA256SUMS.txt )
echo "$PKG  ($([ ${#SIGN[@]} -gt 0 ] && echo signed || echo UNSIGNED))"
