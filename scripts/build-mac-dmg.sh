#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
APP_BUNDLE="$DIST_DIR/PipiBot.app"

if [[ "${PIPIBOT_SKIP_APP_BUILD:-0}" != "1" ]]; then
  echo "==> Building signed PipiBot.app first..."
  bash "$SCRIPT_DIR/build-mac-app.sh"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: $APP_BUNDLE not found." >&2
  exit 1
fi

VERSION="${PIPIBOT_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || echo "0.10.0")}"
ARCH="${PIPIBOT_ARCH:-$(uname -m)}"
DMG_NAME="PiPiBot-${VERSION}-${ARCH}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
SHA_PATH="${DMG_PATH}.sha256"
VOL_NAME="PiPiBot ${VERSION}"

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pipibot-dmg-stage.XXXXXX")"
cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

echo "==> Staging DMG contents for $DMG_NAME..."
ditto "$APP_BUNDLE" "$STAGE_DIR/PiPiBot.app"
ln -s /Applications "$STAGE_DIR/Applications"

if [[ -f "$REPO_ROOT/assets/icons/AppIcon.icns" ]]; then
  cp "$REPO_ROOT/assets/icons/AppIcon.icns" "$STAGE_DIR/.VolumeIcon.icns"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$STAGE_DIR" 2>/dev/null || true
    SetFile -a V "$STAGE_DIR/.VolumeIcon.icns" 2>/dev/null || true
  fi
fi

cat > "$STAGE_DIR/安装与权限说明.txt" <<'EOF'
PiPiBot macOS 安装与系统权限说明
================================

1. 安装步骤
   将「PiPiBot.app」拖入右侧的「Applications（应用程序）」文件夹即可完成安装。
   如果此前曾安装过旧版本，请选择「替换」覆盖旧版应用。

2. 首次启动与引导式配置
   打开「应用程序」中的 PiPiBot，应用将提供 4 步引导式配置向导：
   - 第 1 步：欢迎与概览
   - 第 2 步：连接云端模型或本地模型引擎
   - 第 3 步：按需逐步授予系统权限（每项均标明用途，可随时跳过）
   - 第 4 步：选择默认助手开始对话

   若初次跳过配置，可随时点击主界面左下角「引导式配置」或「设置 → 通用」重新进入。

3. 关于 macOS「完全磁盘访问」权限（用于读取本机短信摘要）
   macOS 系统安全策略禁止任何应用自动弹出完全磁盘访问授权框：
   - 点击应用内「打开系统设置并定位应用」
   - 将访达中选中的 /Applications/PiPiBot.app 拖入「完全磁盘访问权限」列表并开启开关
   - 如列表中存在旧版本残留条目，请先点击下方「-」移除后再重新拖入
   - 点击应用内「重启以生效」即可启用
EOF

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH" "$SHA_PATH"

echo "==> Creating compressed UDZO disk image: $DMG_PATH..."
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

echo "==> Verifying disk image integrity..."
hdiutil verify "$DMG_PATH"

echo "==> Generating SHA-256 checksum..."
(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME" > "$(basename "$SHA_PATH")")

echo "==> Release DMG ready:"
ls -lh "$DMG_PATH" "$SHA_PATH"
cat "$SHA_PATH"
