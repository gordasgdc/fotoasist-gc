#!/bin/bash
# Builds the pinned LibRaw release as a universal (arm64 + x86_64) dynamic library. Idempotent.
# Source: the official archive, checked by SHA-256. No GPL demosaic packs, no lcms, no libjpeg, no OpenMP.
# LibRaw is licensed LGPL-2.1 or CDDL-1.0; it is linked dynamically and never modified. See THIRD_PARTY_NOTICES.md.
set -euo pipefail
source "$(dirname "$0")/env.sh"
DL="$FOTOASIST_BUILD_ROOT/downloads"; SRC="$FOTOASIST_BUILD_ROOT/libraw/src"; PREFIX="$LIBRAW_PREFIX"
if [ -f "$PREFIX/BUILD_MANIFEST.json" ]; then echo "LibRaw $LIBRAW_VERSION already built: $PREFIX"; exit 0; fi
mkdir -p "$DL" "$SRC"
TARBALL="$DL/LibRaw-$LIBRAW_VERSION.tar.gz"
[ -f "$TARBALL" ] || curl -fsSL -o "$TARBALL" "https://www.libraw.org/data/LibRaw-$LIBRAW_VERSION.tar.gz"
GOT="$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)"
[ "$GOT" = "$LIBRAW_SHA256" ] || { echo "SHA-256 mismatch for LibRaw-$LIBRAW_VERSION.tar.gz ($GOT)" >&2; exit 1; }
rm -rf "$SRC/LibRaw-$LIBRAW_VERSION"; tar xzf "$TARBALL" -C "$SRC"; cd "$SRC/LibRaw-$LIBRAW_VERSION"
ARCHS="${FOTOASIST_ARCHS:--arch arm64 -arch x86_64}"
export CFLAGS="-O2 $ARCHS -mmacosx-version-min=13.0" CXXFLAGS="-O2 $ARCHS -mmacosx-version-min=13.0" LDFLAGS="$ARCHS -mmacosx-version-min=13.0"
# LibRaw's configure insists on pkg-config, which a clean Mac does not have. It is only used to locate zlib (system library)
# and lcms (disabled), so the answers are given directly: the build is the same with or without Homebrew installed.
export PKG_CONFIG=/usr/bin/true ZLIB_CFLAGS=" " ZLIB_LIBS="-lz"
./configure --prefix="$PREFIX" --disable-openmp --disable-examples --disable-lcms --disable-jpeg --enable-zlib --enable-shared --disable-static --disable-dependency-tracking > "$SRC/configure.log" 2>&1
make -j"$(sysctl -n hw.ncpu)" > "$SRC/make.log" 2>&1
make install > "$SRC/install.log" 2>&1
REAL="$PREFIX/lib/$(readlink "$PREFIX/lib/libraw_r.dylib")"
install_name_tool -id "@rpath/$(basename "$REAL")" "$REAL"
mkdir -p "$PREFIX/share/doc/LibRaw"; cp COPYRIGHT LICENSE.LGPL LICENSE.CDDL README.md "$PREFIX/share/doc/LibRaw/"
cat > "$PREFIX/BUILD_MANIFEST.json" <<JSON
{"name": "LibRaw", "version": "$LIBRAW_VERSION", "source_url": "https://www.libraw.org/data/LibRaw-$LIBRAW_VERSION.tar.gz", "source_sha256": "$LIBRAW_SHA256",
 "license": "LGPL-2.1-only OR CDDL-1.0", "linking": "dynamic (dylib, @rpath)", "library": "$(basename "$REAL")", "architectures": "$(lipo -archs "$REAL")"}
JSON
echo "LibRaw $LIBRAW_VERSION built: $PREFIX ($(lipo -archs "$REAL"))"
