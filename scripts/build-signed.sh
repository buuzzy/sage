#!/usr/bin/env bash
# Sage release build wrapper — signed + notarized updater artifacts
#
# 用法：
#   ./scripts/build-signed.sh                         # arm64 dmg (signed + notarized)
#   ./scripts/build-signed.sh mac-arm                 # 同上
#   ./scripts/build-signed.sh mac-intel               # x86_64 dmg (signed + notarized)
#
# 作用：
#   1. 加载 configs/env/.env.tauri-signing（TAURI_SIGNING_PRIVATE_KEY / PASSWORD）
#   2. 加载 configs/env/.env.production（VITE_SUPABASE_URL/KEY，走 prod project）
#   3. 设置 Apple 签名环境变量（APPLE_SIGNING_IDENTITY / notarytool API Key）
#   4. 执行对应的 pnpm 脚本，Tauri 自动 codesign
#   5. 构建后对 DMG 进行公证（notarization）
#
# 产物位置（以 mac-arm 为例）：
#   src-tauri/target/aarch64-apple-darwin/release/bundle/
#     ├── dmg/Sage_<version>_aarch64.dmg      ← 签名 + 公证
#     ├── macos/Sage.app.tar.gz               ← updater artifact
#     └── macos/Sage.app.tar.gz.sig           ← Ed25519 signature

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TARGET="${1:-mac-arm}"

# ── 0. 平台拦截：Mac 上不能交叉编译 Windows ────────────────────────────────
if [[ "$TARGET" == "windows" || "$TARGET" == "win" ]] && [[ "$(uname -s)" == "Darwin" ]]; then
  echo "❌ Windows 构建无法在 macOS 上跑（缺 MSVC 工具链）。"
  echo "   正式发版请走 CI：git tag -a v<version> && git push origin v<version>"
  exit 2
fi

# ── 1. 加载签名密钥（configs/env/.env.tauri-signing）────────────────────────
if [ ! -f configs/env/.env.tauri-signing ]; then
  echo "❌ configs/env/.env.tauri-signing 不存在。请先生成更新签名密钥："
  echo "   pnpm exec tauri signer generate --ci --password '' --write-keys ~/.sage-updater.key"
  echo "   然后把 ~/.sage-updater.key 内容写入 configs/env/.env.tauri-signing"
  exit 1
fi

# shellcheck disable=SC1091
set -a
source configs/env/.env.tauri-signing
set +a

if [ -z "${TAURI_SIGNING_PRIVATE_KEY:-}" ]; then
  echo "❌ .env.tauri-signing 里 TAURI_SIGNING_PRIVATE_KEY 为空。"
  exit 1
fi

echo "✅ Loaded TAURI_SIGNING_PRIVATE_KEY (length: ${#TAURI_SIGNING_PRIVATE_KEY})"

# ── 2. 加载 prod 环境变量（若有 configs/env/.env.production）────────────────
if [ -f configs/env/.env.production ]; then
  set -a
  # shellcheck disable=SC1091
  source configs/env/.env.production
  set +a
  echo "✅ Loaded configs/env/.env.production (VITE_SUPABASE_URL=${VITE_SUPABASE_URL:-<unset>})"
else
  echo "⚠️  configs/env/.env.production 不存在，将使用 supabase.ts 里硬编码的 prod fallback。"
fi

# ── 3. Apple 代码签名配置 ──────────────────────────────────────────────────
# Tauri 在 macOS 上会自动读取 APPLE_SIGNING_IDENTITY 进行 codesign
export APPLE_SIGNING_IDENTITY="Developer ID Application: YIYANG CAI (QB576QUT2S)"

# Apple Notarization via API Key (faster & more reliable than password)
APPLE_API_KEY_ID="QQKFHN5SQ3"
APPLE_API_ISSUER="4fd5778f-6e6d-4fd3-8546-fb36937b3036"
APPLE_API_KEY_PATH="/Users/nakocai/Documents/Projects/项目/Sage/.env/AuthKey_${APPLE_API_KEY_ID}.p8"

if [ ! -f "$APPLE_API_KEY_PATH" ]; then
  echo "⚠️  Apple API Key not found at $APPLE_API_KEY_PATH — notarization will be skipped"
  SKIP_NOTARIZE=1
else
  SKIP_NOTARIZE=0
  echo "✅ Apple signing: ${APPLE_SIGNING_IDENTITY}"
  echo "✅ Apple API Key: ${APPLE_API_KEY_ID} (for notarization)"
fi

# ── 4. 执行打包（Tauri 自动 codesign）─────────────────────────────────────
case "$TARGET" in
  mac-arm|darwin-arm|arm64)
    RUST_TARGET="aarch64-apple-darwin"
    pnpm tauri:build:mac-arm
    ;;
  mac-intel|darwin-intel|x86_64)
    RUST_TARGET="x86_64-apple-darwin"
    pnpm tauri:build:mac-intel
    ;;
  linux)
    pnpm tauri:build:linux
    echo "✅ 打包完成（Linux 无需签名/公证）。"
    exit 0
    ;;
  windows|win)
    pnpm tauri:build:windows
    echo "✅ 打包完成（Windows 无需 Apple 签名）。"
    exit 0
    ;;
  *)
    echo "❌ Unknown target: $TARGET"
    echo "   支持: mac-arm / mac-intel / linux / windows"
    exit 1
    ;;
esac

# ── 5. Apple 公证（Notarization）──────────────────────────────────────────
BUNDLE_DIR="src-tauri/target/${RUST_TARGET}/release/bundle"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo ""
  echo "⚠️  跳过公证（API Key 未找到）。DMG 已签名但未公证，用户可能需要 xattr -cr。"
  exit 0
fi

echo ""
echo "🔏 开始公证 DMG..."

# Find the DMG file
DMG_FILE=$(find "$BUNDLE_DIR/dmg" -name "*.dmg" | head -1)
if [ -z "$DMG_FILE" ]; then
  echo "❌ 未找到 DMG 文件。"
  exit 1
fi

echo "   提交: $DMG_FILE"

# Submit for notarization
xcrun notarytool submit "$DMG_FILE" \
  --key "$APPLE_API_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER" \
  --wait

# Staple the notarization ticket to the DMG
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$DMG_FILE"

echo ""
echo "✅ 打包 + 签名 + 公证完成！"
echo "   DMG: $DMG_FILE"
echo "   用户可直接双击安装，不会出现「已损坏」警告。"
echo ""
echo "   下一步：上传到 GitHub Releases（详见 docs/RELEASE.md）"
