#!/bin/bash
# Shared settings for the build scripts. Source it: `source scripts/env.sh`.
# Everything generated (LibRaw, SwiftPM scratch, the app bundle, the package) goes under FOTOASIST_BUILD_ROOT.
# Default: <repository>/.build-out (ignored by Git). Point it anywhere else, e.g. an external disk.
FOTOASIST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
FOTOASIST_BUILD_ROOT="${FOTOASIST_BUILD_ROOT:-$FOTOASIST_REPO/.build-out}"
FOTOASIST_VERSION="$(tr -d ' \n' < "$FOTOASIST_REPO/VERSION")"
LIBRAW_VERSION=0.22.1
LIBRAW_SHA256=a789dc4e2409e2901d93793a4e0b80c7b49d0d97cf6ad71c850eb7616acfd786
LIBRAW_PREFIX="$FOTOASIST_BUILD_ROOT/libraw/$LIBRAW_VERSION"
export FOTOASIST_REPO FOTOASIST_BUILD_ROOT FOTOASIST_VERSION LIBRAW_VERSION LIBRAW_SHA256 LIBRAW_PREFIX
mkdir -p "$FOTOASIST_BUILD_ROOT"
