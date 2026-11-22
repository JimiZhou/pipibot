#!/usr/bin/env bash
# Builds an unsigned arm64 iOS Device (.ipa) for real-device sideloading
# (AltStore / SideStore / Sideloadly / TrollStore / Xcode re-signing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APPLE_DIR="$REPO_ROOT/apps/apple"
DIST_DIR="$REPO_ROOT/dist"
BUILD_CONFIG="${PIPIBOT_IOS_BUILD_CONFIG:-Release}"
DERIVED_DIR="${PIPIBOT_IOS_DEVICE_DERIVED_DATA:-$APPLE_DIR/.build/ios-device-derived}"
VERSION="0.12.0"
IPA_PATH="$DIST_DIR/PiPiBot-${VERSION}-iOS-unsigned.ipa"
STAGE_DIR="$DIST_DIR/.ipa-stage"
APP_BUNDLE="$STAGE_DIR/Payload/PipiBotIOS.app"

echo "==> Building PipiBotIOSApp ($BUILD_CONFIG for arm64 iOS Device / iphoneos)..."
cd "$APPLE_DIR"
mkdir -p "$DERIVED_DIR"

xcodebuild \
  -scheme PipiBotIOSApp \
  -destination 'generic/platform=iOS' \
  -configuration "$BUILD_CONFIG" \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

PRODUCTS_DIR="$DERIVED_DIR/Build/Products/${BUILD_CONFIG}-iphoneos"
BUILT_BINARY=""
if [[ -x "$PRODUCTS_DIR/PipiBotIOSApp.app/PipiBotIOSApp" ]]; then
  BUILT_BINARY="$PRODUCTS_DIR/PipiBotIOSApp.app/PipiBotIOSApp"
elif [[ -x "$PRODUCTS_DIR/PipiBotIOSApp" ]]; then
  BUILT_BINARY="$PRODUCTS_DIR/PipiBotIOSApp"
else
  echo "Error: Could not find built arm64 iphoneos PipiBotIOSApp binary in $PRODUCTS_DIR" >&2
  exit 1
fi

if [[ ! -f "$REPO_ROOT/assets/icons/ios/AppIcon60x60@3x.png" ]]; then
  swift "$REPO_ROOT/scripts/generate-app-icons.swift"
fi

echo "==> Packaging real-device IPA: $IPA_PATH..."
rm -rf "$STAGE_DIR" "$IPA_PATH"
mkdir -p "$APP_BUNDLE"

cp "$BUILT_BINARY" "$APP_BUNDLE/PipiBotIOSApp"
chmod +x "$APP_BUNDLE/PipiBotIOSApp"
cp "$REPO_ROOT/assets/icons/ios/"*.png "$APP_BUNDLE/"

if [[ -d "$PRODUCTS_DIR/PipiBotIOSUI.appintents" ]]; then
  mkdir -p "$APP_BUNDLE/Metadata.appintents"
  cp -R "$PRODUCTS_DIR/PipiBotIOSUI.appintents/"* "$APP_BUNDLE/Metadata.appintents/" 2>/dev/null || true
fi

cat > "$APP_BUNDLE/Info.plist" <<'PLIST'
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
  <string>PipiBot</string>
  <key>CFBundleExecutable</key>
  <string>PipiBotIOSApp</string>
  <key>CFBundleIconFiles</key>
  <array>
    <string>AppIcon60x60</string>
    <string>AppIcon76x76</string>
  </array>
  <key>CFBundleIcons</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFiles</key>
      <array>
        <string>AppIcon60x60</string>
      </array>
      <key>UIPrerenderedIcon</key>
      <true/>
    </dict>
  </dict>
  <key>CFBundleIcons~ipad</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFiles</key>
      <array>
        <string>AppIcon60x60</string>
        <string>AppIcon76x76</string>
      </array>
      <key>UIPrerenderedIcon</key>
      <true/>
    </dict>
  </dict>
  <key>CFBundleIdentifier</key>
  <string>ai.pipibot.ios</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PipiBot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.12.0</string>
  <key>CFBundleVersion</key>
  <string>12</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>iPhoneOS</string>
  </array>
  <key>DTPlatformName</key>
  <string>iphoneos</string>
  <key>LSRequiresIPhoneOS</key>
  <true/>
  <key>MinimumOSVersion</key>
  <string>17.0</string>
  <key>UIDeviceFamily</key>
  <array>
    <integer>1</integer>
    <integer>2</integer>
  </array>
  <key>UILaunchScreen</key>
  <dict/>
  <key>NSSupportsLiveActivities</key>
  <true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>ai.pipibot.ios.deeplink</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>pipibot</string>
      </array>
    </dict>
  </array>
  <key>NSMicrophoneUsageDescription</key>
  <string>PiPiBot uses your microphone for on-device-first daily voice dictation and voice chat.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>PiPiBot uses Apple on-device Speech Recognition for private daily voice input.</string>
</dict>
</plist>
PLIST

cd "$STAGE_DIR"
zip -qry "$IPA_PATH" Payload
rm -rf "$STAGE_DIR"

shasum -a 256 "$IPA_PATH" > "${IPA_PATH}.sha256"
echo "==> Real-device unsigned IPA ready:"
ls -lh "$IPA_PATH" "${IPA_PATH}.sha256"
cat "${IPA_PATH}.sha256"
