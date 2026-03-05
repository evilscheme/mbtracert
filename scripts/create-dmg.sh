#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODEPROJ="${PROJECT_DIR}/MenubarTracert/MenubarTracert.xcodeproj"
SCHEME="MenubarTracert"
ARCHIVE_DIR="${PROJECT_DIR}/build/archive"
ARCHIVE_PATH="${ARCHIVE_DIR}/MenubarTracert.xcarchive"
EXPORT_DIR="${PROJECT_DIR}/build/export"
DIST_DIR="${PROJECT_DIR}/dist"
EXPORT_PLIST="${PROJECT_DIR}/build/export-options.plist"
KEYCHAIN_PROFILE="notarytool-profile"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# ── Helpers ──────────────────────────────────────────────────────────────────
info()  { printf "\033[1;34m==> %s\033[0m\n" "$*"; }
error() { printf "\033[1;31mERROR: %s\033[0m\n" "$*" >&2; exit 1; }

# ── Extract marketing version ────────────────────────────────────────────────
info "Resolving MARKETING_VERSION..."
MARKETING_VERSION=$(
    xcodebuild -project "${XCODEPROJ}" \
               -scheme "${SCHEME}" \
               -showBuildSettings \
               -configuration Release 2>/dev/null \
    | grep '^\s*MARKETING_VERSION' \
    | head -1 \
    | sed 's/.*= //'
)
[ -n "${MARKETING_VERSION}" ] || error "Could not determine MARKETING_VERSION from build settings"
info "Version: ${MARKETING_VERSION}"

# ── Clean previous artifacts ─────────────────────────────────────────────────
rm -rf "${ARCHIVE_DIR}" "${EXPORT_DIR}"
mkdir -p "${ARCHIVE_DIR}" "${EXPORT_DIR}" "${DIST_DIR}"

# ── 1. Build Release archive ────────────────────────────────────────────────
info "Building Release archive..."
xcodebuild archive \
    -project "${XCODEPROJ}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    CODE_SIGN_STYLE=Manual \
    | tail -1

[ -d "${ARCHIVE_PATH}" ] || error "Archive failed — ${ARCHIVE_PATH} not found"
info "Archive created at ${ARCHIVE_PATH}"

# ── 2. Export with Developer ID ──────────────────────────────────────────────
info "Exporting archive (developer-id)..."

cat > "${EXPORT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportOptionsPlist "${EXPORT_PLIST}" \
    -exportPath "${EXPORT_DIR}" \
    | tail -1

APP_PATH="${EXPORT_DIR}/MenubarTracert.app"
[ -d "${APP_PATH}" ] || error "Export failed — ${APP_PATH} not found"
info "Exported app at ${APP_PATH}"

# ── 3. Notarize (optional) ──────────────────────────────────────────────────
if [ "${SKIP_NOTARIZE}" = "1" ]; then
    info "Skipping notarization (SKIP_NOTARIZE=1)"
else
    info "Submitting for notarization..."

    # Create a temporary zip for notarytool submission
    NOTARIZE_ZIP="${EXPORT_DIR}/MenubarTracert-notarize.zip"
    ditto -c -k --keepParent "${APP_PATH}" "${NOTARIZE_ZIP}"

    xcrun notarytool submit "${NOTARIZE_ZIP}" \
        --keychain-profile "${KEYCHAIN_PROFILE}" \
        --wait

    rm -f "${NOTARIZE_ZIP}"

    # ── 4. Staple ────────────────────────────────────────────────────────────
    info "Stapling notarization ticket..."
    xcrun stapler staple "${APP_PATH}"
fi

# ── 5. Create DMG ───────────────────────────────────────────────────────────
DMG_NAME="MenubarTracert-${MARKETING_VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
DMG_STAGING="${EXPORT_DIR}/dmg-staging"
DMG_BACKGROUND="${PROJECT_DIR}/scripts/dmg-background.png"

info "Creating DMG: ${DMG_NAME}..."

rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_PATH}" "${DMG_STAGING}/"

rm -f "${DMG_PATH}"
create-dmg \
    --volname "MenubarTracert" \
    --background "${DMG_BACKGROUND}" \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "MenubarTracert.app" 165 200 \
    --app-drop-link 495 200 \
    --hide-extension "MenubarTracert.app" \
    --no-internet-enable \
    "${DMG_PATH}" \
    "${DMG_STAGING}"

rm -rf "${DMG_STAGING}"
info "DMG created at ${DMG_PATH}"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
info "Build complete!"
echo "  Archive : ${ARCHIVE_PATH}"
echo "  App     : ${APP_PATH}"
echo "  DMG     : ${DMG_PATH}"
echo ""

if [ "${SKIP_NOTARIZE}" = "1" ]; then
    echo "──────────────────────────────────────────────────────────────"
    echo "  Notarization was skipped. To notarize the DMG separately:"
    echo ""
    echo "    xcrun notarytool submit '${DMG_PATH}' \\"
    echo "        --keychain-profile ${KEYCHAIN_PROFILE} --wait"
    echo "    xcrun stapler staple '${DMG_PATH}'"
    echo "──────────────────────────────────────────────────────────────"
    echo ""
fi

echo "──────────────────────────────────────────────────────────────"
echo "  Notarization credentials setup (one-time):"
echo ""
echo "    xcrun notarytool store-credentials \"${KEYCHAIN_PROFILE}\" \\"
echo "        --apple-id <APPLE_ID> \\"
echo "        --team-id 4PX677GC4R \\"
echo "        --password <APP_SPECIFIC_PASSWORD>"
echo ""
echo "  Generate an app-specific password at https://appleid.apple.com"
echo "──────────────────────────────────────────────────────────────"
