#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Finder shows this bundle as Dev Servers. The SwiftPM executable is DevServers.
APP_NAME="Dev Servers"
BINARY_NAME="DevServers"
APP_DIR=".build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"

if [[ "${1:-}" != "" && "${1:-}" != "--release" ]]; then
    echo "Usage: $0 [--release]" >&2
    exit 1
fi
if [[ -f update-config.env ]]; then
    source update-config.env
fi
export WTP_VERSION="${WTP_VERSION:-}"
export WTP_BUILD="${WTP_BUILD:-}"

python3 scripts/configure-updates.py Info.plist .build/configured-Info.plist
swift build -c release --product DevServers
BIN_DIR="$(swift build -c release --product DevServers --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"
cp "${BIN_DIR}/${BINARY_NAME}" "${CONTENTS_DIR}/MacOS/"
cp .build/configured-Info.plist "${CONTENTS_DIR}/Info.plist"
cp -R "Resources/Fonts" "${CONTENTS_DIR}/Resources/"
cp "Resources/AppIcon.icns" "${CONTENTS_DIR}/Resources/"
ditto "${BIN_DIR}/WhatThePort_DevServers.bundle" "${CONTENTS_DIR}/Resources/WhatThePort_DevServers.bundle"

IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGN_OPTIONS=(--force --sign "${IDENTITY}")
if [[ "${IDENTITY}" == "-" ]]; then
    SIGN_OPTIONS+=(--timestamp=none)
else
    SIGN_OPTIONS+=(--options runtime --timestamp)
fi
codesign "${SIGN_OPTIONS[@]}" "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

echo "Built ${APP_DIR}"
echo "Run with: open ${APP_DIR}"
