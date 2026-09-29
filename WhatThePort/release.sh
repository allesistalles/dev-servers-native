#!/bin/bash
# Prepare signed update artifacts locally. Does not publish or deploy anything.
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -ne 2 || -z "${1:-}" || -z "${2:-}" ]]; then
    echo "Usage: $0 <version> <build-number>" >&2
    exit 1
fi
if [[ -f update-config.env ]]; then
    source update-config.env
fi
export WTP_VERSION="$1" WTP_BUILD="$2"
export CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
python3 scripts/configure-updates.py Info.plist .build/configured-Info.plist

# Notarize with a stored notarytool profile, or with an App Store Connect API key (used in CI).
NOTARY_AUTH=()
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    NOTARY_AUTH=(--keychain-profile "${NOTARYTOOL_PROFILE}")
elif [[ -n "${NOTARY_API_KEY_PATH:-}" ]]; then
    if [[ -z "${NOTARY_API_KEY_ID:-}" || -z "${NOTARY_API_ISSUER_ID:-}" ]]; then
        echo "NOTARY_API_KEY_PATH also requires NOTARY_API_KEY_ID and NOTARY_API_ISSUER_ID." >&2
        exit 1
    fi
    NOTARY_AUTH=(--key "${NOTARY_API_KEY_PATH}" --key-id "${NOTARY_API_KEY_ID}" --issuer "${NOTARY_API_ISSUER_ID}")
fi
if [[ ${#NOTARY_AUTH[@]} -gt 0 && "${CODE_SIGN_IDENTITY}" == "-" ]]; then
    echo "Notarization requires CODE_SIGN_IDENTITY to be a Developer ID certificate." >&2
    exit 1
fi
if [[ ${#NOTARY_AUTH[@]} -eq 0 && "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    echo "warning: signing without notarization. Gatekeeper will still block first-time downloads." >&2
fi

./build-app.sh --release
APP=".build/Dev Servers.app"

notarize() {
    local SUBMISSION SUBMISSION_ID STATUS
    SUBMISSION="$(xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait --output-format json)"
    echo "${SUBMISSION}"
    read -r SUBMISSION_ID STATUS < <(python3 -c 'import json, sys; s = json.load(sys.stdin); print(s["id"], s["status"])' <<< "${SUBMISSION}")
    if [[ "${STATUS}" != "Accepted" ]]; then
        xcrun notarytool log "${SUBMISSION_ID}" "${NOTARY_AUTH[@]}" >&2 || true
        echo "Notarization of $1 finished with status ${STATUS}." >&2
        exit 1
    fi
}

if [[ ${#NOTARY_AUTH[@]} -gt 0 ]]; then
    ditto -c -k --sequesterRsrc --keepParent "${APP}" .build/notarize.zip
    notarize .build/notarize.zip
    xcrun stapler staple "${APP}"
    xcrun stapler validate "${APP}"
    spctl --assess --type execute --verbose=2 "${APP}"
fi

# The website download: a disk image with the app beside an Applications shortcut.
./make-dmg.sh "${APP}" .build/WhatThePort.dmg
if [[ ${#NOTARY_AUTH[@]} -gt 0 ]]; then
    notarize .build/WhatThePort.dmg
    xcrun stapler staple .build/WhatThePort.dmg
    xcrun stapler validate .build/WhatThePort.dmg
    spctl --assess --type open --context context:primary-signature --verbose=2 .build/WhatThePort.dmg
fi

echo "Prepared .build/WhatThePort.dmg"
echo "Replace the website download with .build/WhatThePort.dmg."
