#!/bin/bash
# Assembles "FotoAsist GC.app" from a release build. Ad-hoc signed by default: enough to run it on the Mac that built it.
# Official releases are signed with a Developer ID and notarized by the maintainer (scripts/make_pkg.sh, see BUILDING.md);
# that step needs credentials that are not, and must never be, in this repository.
# Output: $FOTOASIST_BUILD_ROOT/app/FotoAsist GC.app
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$FOTOASIST_REPO"
VER="$FOTOASIST_VERSION"
BUILD="$(git rev-parse --short HEAD 2>/dev/null || echo source)$(git diff --quiet HEAD -- . 2>/dev/null || echo '+modified')"
ARCH_FLAGS=(); for a in ${FOTOASIST_APP_ARCHS:-}; do ARCH_FLAGS+=(--arch "$a"); done   # e.g. FOTOASIST_APP_ARCHS="arm64 x86_64" for a universal binary
scripts/swift.sh build -c release --product PhotoAssist ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} | tail -1
BIN="$(scripts/swift.sh build -c release --product PhotoAssist ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/PhotoAssist"
APP="$FOTOASIST_BUILD_ROOT/app/FotoAsist GC.app"; R="$APP/Contents/Resources"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$R/charts" "$R/Brand" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/GDCPhotoAssist"
LIBRAW_DYLIB="$LIBRAW_PREFIX/lib/$(readlink "$LIBRAW_PREFIX/lib/libraw_r.dylib")"
cp "$LIBRAW_DYLIB" "$APP/Contents/Frameworks/"
cp core/Sources/PhotoResolve/Resources/resolve_worker.py core/Sources/PhotoResolve/Resources/drx_chain.py "$R/"
cp core/Sources/PhotoResolve/Resources/charts/colorchecker_classic.json "$R/charts/"
cp core/Sources/PhotoAssistUI/Resources/Brand/FotoAsist-GC_simbol.svg "$R/Brand/"
cp packaging/AppIcon.icns "$R/FotoAsist-GC_app-icon.icns"
# Licence texts travel with the binary: GPL for the app, LGPL/CDDL for LibRaw, plus the notices.
cp LICENSE "$R/LICENSE.txt"; cp THIRD_PARTY_NOTICES.md AUTHORS.md "$R/"
mkdir -p "$R/licenses/LibRaw"; cp "$LIBRAW_PREFIX/share/doc/LibRaw/"{COPYRIGHT,LICENSE.LGPL,LICENSE.CDDL} "$R/licenses/LibRaw/"
install_name_tool -delete_rpath "$LIBRAW_PREFIX/lib" "$APP/Contents/MacOS/GDCPhotoAssist" 2>/dev/null || true
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/GDCPhotoAssist"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GDCPhotoAssist</string>
<key>CFBundleIconFile</key><string>FotoAsist-GC_app-icon</string>
<key>CFBundleIdentifier</key><string>${FOTOASIST_BUNDLE_ID:-dev.gordas.photoassist}</string>
<key>CFBundleName</key><string>FotoAsist GC</string>
<key>CFBundleDisplayName</key><string>FotoAsist GC</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VER</string>
<key>CFBundleVersion</key><string>$VER</string>
<key>GDCPABuild</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSSupportsAutomaticTermination</key><false/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Dumitru Cristinel Gordas (GDC). GPL-3.0-or-later.</string>
<key>NSAppleEventsUsageDescription</key><string>Used only when you hand a photo over to DaVinci Resolve: the app talks to Resolve through its local scripting interface.</string>
</dict></plist>
PL
SIGN_ID="${FOTOASIST_SIGN_APP:--}"   # "-" = ad-hoc; the maintainer passes a Developer ID Application identity for official releases
SIGN_OPTS=(--force --sign "$SIGN_ID"); [ "$SIGN_ID" = "-" ] || SIGN_OPTS+=(--options runtime --timestamp)
codesign "${SIGN_OPTS[@]}" "$APP/Contents/Frameworks/$(basename "$LIBRAW_DYLIB")"
codesign "${SIGN_OPTS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP  (version $VER, build $BUILD, signature: $([ "$SIGN_ID" = "-" ] && echo ad-hoc || echo "$SIGN_ID"))"
