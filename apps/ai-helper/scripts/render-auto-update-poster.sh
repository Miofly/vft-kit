#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/mascot-export"
EXECUTABLE_PATH="${BUILD_DIR}/auto-update-poster-export"
ARCH="$(uname -m)"

mkdir -p "${BUILD_DIR}"
cd "${ROOT_DIR}"

xcrun swiftc \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target "${ARCH}-apple-macos14.0" \
  -parse-as-library \
  -o "${EXECUTABLE_PATH}" \
  "${ROOT_DIR}/scripts/mascot-export/AutoUpdatePosterExporterMain.swift"

"${EXECUTABLE_PATH}" "$@"
