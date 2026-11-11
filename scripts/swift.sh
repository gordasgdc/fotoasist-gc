#!/bin/bash
# Runs SwiftPM for core/ with the LibRaw paths. Usage: scripts/swift.sh build|test|run [swift arguments]
#   scripts/swift.sh test                       all tests (synthetic data only; tests that need your own RAW files are skipped)
#   scripts/swift.sh build -c release           release build
#   scripts/swift.sh run PhotoAssist            run the app from the build directory
set -euo pipefail
source "$(dirname "$0")/env.sh"
[ -f "$LIBRAW_PREFIX/BUILD_MANIFEST.json" ] || "$FOTOASIST_REPO/scripts/build_libraw.sh"
CMD="${1:-build}"; shift || true
# The tests check the Romanian source texts, whatever the system language is.
[ "$CMD" = "test" ] && export GDC_PA_LANG="${GDC_PA_LANG:-ro}"
# FOTOASIST_SWIFT_FLAGS: extra SwiftPM flags, e.g. "--disable-sandbox" when the build already runs inside a sandbox.
# shellcheck disable=SC2086
exec swift "$CMD" ${FOTOASIST_SWIFT_FLAGS:-} --package-path "$FOTOASIST_REPO/core" --scratch-path "$FOTOASIST_BUILD_ROOT/swiftpm" \
  -Xcc "-I$LIBRAW_PREFIX/include" -Xlinker "-L$LIBRAW_PREFIX/lib" -Xlinker -rpath -Xlinker "$LIBRAW_PREFIX/lib" "$@"
