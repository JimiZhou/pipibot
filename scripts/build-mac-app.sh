#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APPLE_DIR="$REPO_ROOT/apps/apple"
DIST_DIR="$REPO_ROOT/dist"
APP_BUNDLE="$DIST_DIR/PiPiBot.app"
# Remove legacy lowercase bundle if present to prevent duplicate app bundles
rm -rf "$DIST_DIR/PipiBot.app"
BUILD_CONFIG="${PIPIBOT_BUILD_CONFIG:-release}"

echo "==> Building PipiBotMacApp ($BUILD_CONFIG)..."
cd "$APPLE_DIR"
swift build -c "$BUILD_CONFIG" --product PipiBotMacApp

BIN_DIR="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"
BUILT_BINARY="$BIN_DIR/PipiBotMacApp"

if [[ ! -x "$BUILT_BINARY" ]]; then
  echo "Error: Expected binary not found at $BUILT_BINARY" >&2
  exit 1
fi

if [[ ! -f "$REPO_ROOT/assets/icons/AppIcon.icns" ]]; then
  echo "==> Generating app icons..."
  swift "$REPO_ROOT/scripts/generate-app-icons.swift"
fi

echo "==> Packaging $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILT_BINARY" "$APP_BUNDLE/Contents/MacOS/PipiBotMacApp"
chmod +x "$APP_BUNDLE/Contents/MacOS/PipiBotMacApp"
cp "$REPO_ROOT/assets/icons/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
  </array>
  <key>CFBundleDisplayName</key>
  <string>PiPiBot</string>
  <key>CFBundleExecutable</key>
  <string>PipiBotMacApp</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>ai.pipibot.mac</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PiPiBot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.13.2</string>
  <key>CFBundleVersion</key>
  <string>15</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>ai.pipibot.mac.url</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>pipibot</string>
      </array>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSDesktopFolderUsageDescription</key>
  <string>PiPiBot optionally reads workspace git status when pointed to a Desktop project.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>PiPiBot reads upcoming Apple Calendar events on-device to Prepare read-only context briefings before your day starts.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>PiPiBot reads upcoming Apple Calendar events on-device to Prepare read-only context briefings.</string>
  <key>NSRemindersFullAccessUsageDescription</key>
  <string>PiPiBot reads Apple Reminders on-device so your proactive assistant can surface due items without fatigue.</string>
  <key>NSRemindersUsageDescription</key>
  <string>PiPiBot reads Apple Reminders on-device to surface upcoming due items.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>PiPiBot uses your microphone for on-device-first daily voice dictation, hands-free voice calls, and echo-gated barge-in.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>PiPiBot uses Apple on-device Speech Recognition to transcribe your daily voice dictation privately without leaving your Mac.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>PiPiBot optionally collaborates with local macOS apps (Mail, Messages, Finder) during user-approved assistant tasks.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>PiPiBot captures screenshots and short screen recordings when requested by the user across Mac, Remote PWA, or WeChat.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
  </dict>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSUIElement</key>
  <false/>
</dict>
</plist>
PLIST

if [[ -f "$REPO_ROOT/LICENSE" ]]; then
  cp "$REPO_ROOT/LICENSE" "$APP_BUNDLE/Contents/Resources/LICENSE"
fi
if [[ -f "$REPO_ROOT/NOTICE" ]]; then
  cp "$REPO_ROOT/NOTICE" "$APP_BUNDLE/Contents/Resources/NOTICE"
fi

if [[ -d "$REPO_ROOT/design-system" ]]; then
  cp -R "$REPO_ROOT/design-system" "$APP_BUNDLE/Contents/Resources/design-system"
fi
if [[ -d "$REPO_ROOT/apps/ios-web" ]]; then
  cp -R "$REPO_ROOT/apps/ios-web" "$APP_BUNDLE/Contents/Resources/ios-web"
fi

# Bundle self-contained embedded HTTP/SSE bridge runtime inside Contents/Resources/runtime
RUNTIME_DIR="$APP_BUNDLE/Contents/Resources/runtime"
mkdir -p "$RUNTIME_DIR/packages" "$RUNTIME_DIR/apps"
for pkg in protocol core daemon; do
  if [[ -d "$REPO_ROOT/packages/$pkg" ]]; then
    cp -R "$REPO_ROOT/packages/$pkg" "$RUNTIME_DIR/packages/$pkg"
  fi
done
if [[ -d "$REPO_ROOT/design-system" ]]; then
  cp -R "$REPO_ROOT/design-system" "$RUNTIME_DIR/design-system"
fi
if [[ -d "$REPO_ROOT/apps/ios-web" ]]; then
  cp -R "$REPO_ROOT/apps/ios-web" "$RUNTIME_DIR/apps/ios-web"
fi

ENTITLEMENTS_FILE="$SCRIPT_DIR/PipiBotMacApp.entitlements"
CODESIGN_ID="${PIPIBOT_CODESIGN_IDENTITY:--}"
BUNDLE_ID="ai.pipibot.mac"

if [[ "$CODESIGN_ID" == "-" ]]; then
  echo "==> Ad-hoc code signing $APP_BUNDLE with stable designated requirement ($BUNDLE_ID)..."
  codesign --force --deep \
    --sign - \
    --identifier "$BUNDLE_ID" \
    --entitlements "$ENTITLEMENTS_FILE" \
    -r="designated => identifier \"$BUNDLE_ID\"" \
    "$APP_BUNDLE"
else
  echo "==> Code signing $APP_BUNDLE with identity: $CODESIGN_ID..."
  codesign --force --deep \
    --options runtime \
    --timestamp \
    --sign "$CODESIGN_ID" \
    --identifier "$BUNDLE_ID" \
    --entitlements "$ENTITLEMENTS_FILE" \
    "$APP_BUNDLE"
fi

echo "==> Verifying code signature..."
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> Successfully packaged $APP_BUNDLE"
ls -la "$APP_BUNDLE/Contents/MacOS/PipiBotMacApp"
