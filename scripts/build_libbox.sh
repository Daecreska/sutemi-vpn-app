#!/usr/bin/env bash
set -euo pipefail

# Builds libbox.aar (Android) and Libbox.xcframework (iOS) from SagerNet/sing-box
# License: GPL-3.0-or-later (sing-box). Ensure attribution notices are bundled in releases.
# Pinned versions match sing-box v1.10.7/go.mod to prevent gomobile/API drift.

SING_BOX_TAG="${SING_BOX_TAG:-v1.10.7}"
GOMOBILE_VERSION="${GOMOBILE_VERSION:-v0.1.4}"
BUILD_TAGS="with_gvisor,with_quic,with_wireguard,with_utls,with_reality_server,with_clash_api"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

for cmd in git go; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is required but not installed in PATH." >&2
    exit 1
  fi
done

GO_VERSION="$(go version | awk '{print $3}' | sed 's/go//')"
echo "Using Go $GO_VERSION | sing-box $SING_BOX_TAG | sagernet/gomobile $GOMOBILE_VERSION"

if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
  echo "WARNING: ANDROID_HOME / ANDROID_SDK_ROOT is not set; Android AAR bind may fail." >&2
fi
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  echo "WARNING: ANDROID_NDK_HOME is not set; gomobile needs NDK r26+ for Android C/CGO compilation." >&2
fi

echo "Installing pinned sagernet/gomobile ($GOMOBILE_VERSION) and gobind..."
go install "github.com/sagernet/gomobile/cmd/gomobile@${GOMOBILE_VERSION}"
go install "github.com/sagernet/gomobile/cmd/gobind@${GOMOBILE_VERSION}"

export PATH="$(go env GOPATH)/bin:${PATH}"

echo "Cloning SagerNet/sing-box @ $SING_BOX_TAG..."
git clone --depth 1 --branch "$SING_BOX_TAG" https://github.com/SagerNet/sing-box.git "$WORK_DIR/sing-box"
cd "$WORK_DIR/sing-box"

gomobile init

mkdir -p "$MOBILE_ROOT/android/app/libs"
echo "Building Android libbox.aar (package io.nekohasekai.libbox)..."
gomobile bind -v \
  -androidapi 24 \
  -javapkg=io.nekohasekai \
  -tags "$BUILD_TAGS" \
  -o "$MOBILE_ROOT/android/app/libs/libbox.aar" \
  ./experimental/libbox

if [[ ! -s "$MOBILE_ROOT/android/app/libs/libbox.aar" ]]; then
  echo "ERROR: Failed to generate non-empty android/app/libs/libbox.aar" >&2
  exit 1
fi
echo "OK: $MOBILE_ROOT/android/app/libs/libbox.aar ($(du -h "$MOBILE_ROOT/android/app/libs/libbox.aar" | cut -f1))"

if [[ "$(uname -s)" == "Darwin" ]]; then
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "ERROR: xcodebuild not found on macOS." >&2
    exit 1
  fi
  mkdir -p "$MOBILE_ROOT/ios/Frameworks"
  echo "Building Apple Libbox.xcframework (ios + iossimulator)..."
  gomobile bind -v \
    -target ios,iossimulator \
    -tags "$BUILD_TAGS" \
    -o "$MOBILE_ROOT/ios/Frameworks/Libbox.xcframework" \
    ./experimental/libbox

  if [[ ! -d "$MOBILE_ROOT/ios/Frameworks/Libbox.xcframework" ]]; then
    echo "ERROR: Failed to generate ios/Frameworks/Libbox.xcframework" >&2
    exit 1
  fi
  echo "OK: $MOBILE_ROOT/ios/Frameworks/Libbox.xcframework"
else
  echo "Skipping Libbox.xcframework on $(uname -s) (requires macOS + Xcode)."
fi

echo "Done."
