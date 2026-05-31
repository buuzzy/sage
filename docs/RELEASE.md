# Sage 发布流程

本文档描述 Sage 桌面端（macOS Apple Silicon / Intel）和 iOS 端的完整打包发布流程。桌面端通过 Tauri updater + GitHub Release 分发，iOS 端通过 TestFlight / App Store 分发。

---

## 0. 发布渠道一览

| 渠道 | 触发方式 | 用途 |
|---|---|---|
| **GitHub Release（CI 自动）** | `git push --tags` | 老用户应用内更新的来源；公开版本归档 |
| **本地手动打包** | `pnpm tauri:build:signed:<arch>` | 调试 / 内测期间私下分发完整安装包 |
| **本地手动 GitHub Release** | `pnpm tauri:build:<arch>` + `gh release create/upload` | CI 不跑或需要立即补发包 / 补发 `latest.json` |
| **Mac App Store** | 单独走 `tauri:build:mas`，详见 `docs/MAS.md`（如存在） | 正式公开后的主分发渠道 |

> 内测期间以私下渠道分发完整 DMG；GitHub Release 主要作为已安装用户的应用内更新通道。

---

## 1. 版本号管理

四处文件的版本号必须保持一致：

- `package.json`
- `src-api/package.json`
- `src-tauri/tauri.conf.json`（用户可见的应用版本）
- `src-tauri/Cargo.toml`

用 `scripts/version.sh` 一次性同步：

```bash
./scripts/version.sh              # 查看当前版本
./scripts/version.sh 1.0.7        # 把所有文件改成 1.0.7
```

格式遵循 semver：`MAJOR.MINOR.PATCH` 或 `1.0.7-rc.1` / `1.0.7-beta.2`。

---

## 2. 标准发布流程（CI 自动）

```bash
# 1. 同步版本号
./scripts/version.sh 1.0.7

# 2. 提交版本变更
git add -A && git commit -m "chore: bump version to 1.0.7"

# 3. 打 tag 并推送（触发 CI）
git tag -a v1.0.7 -m "v1.0.7"
git push origin main
git push origin v1.0.7
```

**Tag 命名规则**（影响 CI 行为）：

- `v1.0.7` → 正式版，会更新 `latest.json`，老用户的客户端会检测到更新
- `v1.0.7-rc.1` / `v1.0.7-beta.1` / `v1.0.7-alpha.1` → prerelease，**不会**更新 `latest.json`，老用户不会被推送，只能手动下载

---

## 3. CI 工作流（`.github/workflows/release.yml`）

### Build matrix

| platform_name | runner | rust_target | 产物 |
|---|---|---|---|
| `mac-arm` | macos-14 | aarch64-apple-darwin | DMG + .app.tar.gz + .sig |
| `mac-intel` | macos-15-intel | x86_64-apple-darwin | DMG + .app.tar.gz + .sig |

> 当前发布策略只维护 macOS Apple Silicon 与 macOS Intel；Windows 暂不发布。

### CI 必需的 Secrets

在 GitHub 仓库 Settings → Secrets and variables → Actions 配置：

| Secret | 用途 |
|---|---|
| `TAURI_SIGNING_PRIVATE_KEY` | Tauri updater Ed25519 签名私钥（base64） |
| `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | 上述私钥的密码（生成时无密码就留空） |
| `VITE_SUPABASE_URL` | 前端编译时注入的 Supabase 项目 URL |
| `VITE_SUPABASE_ANON_KEY` | 前端编译时注入的 Supabase anon key |

### 产物文件命名

CI 会把 Tauri 默认产物重命名为 ASCII 兼容名（GitHub 不支持非 ASCII asset 文件名）：

- `sage-<version>-<triple>.dmg` — 安装包
- `sage-<version>-<triple>.app.tar.gz` — updater payload
- `sage-<version>-<triple>.app.tar.gz.sig` — updater 签名
- `latest.json` — 仅正式版生成，updater endpoint

---

## 4. 应用内更新机制（Tauri Updater）

### 配置

`src-tauri/tauri.conf.json`：

```json
"updater": {
  "pubkey": "...(Ed25519 公钥, base64)...",
  "endpoints": [
    "https://github.com/buuzzy/sage/releases/latest/download/latest.json"
  ]
}
```

### 工作流程

1. 用户客户端启动时（或定时）请求 `endpoints[0]`
2. CI 在每次正式发布时通过 `scripts/gen-latest-json.sh` 生成新的 `latest.json`，覆盖到 `latest` release tag 下
3. `latest.json` 内含每个平台的 `.app.tar.gz` 下载地址 + Ed25519 签名
4. 客户端比对版本号，若有新版则下载并用公钥验签，验签通过后替换 `.app`
5. 用户重启 App 即生效

### `latest.json` 生成

由 CI 自动调用：

```bash
./scripts/gen-latest-json.sh \
  <version> \
  ./artifacts \
  https://github.com/buuzzy/sage/releases/download/v<version>
```

`<artifacts_dir>` 必须按 rust target triple 命名子目录（CI 已经处理好），脚本会拼接出每个平台的下载 URL 并校验 jq。

---

## 5. 本地手动打包

调试或私下分发时使用。所有命令从仓库根目录运行：

```bash
# Apple Silicon
pnpm tauri:build:mac-arm

# Intel Mac
pnpm tauri:build:mac-intel
```

当前推荐用 `TAURI_SIGNING_PRIVATE_KEY` / `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` 环境变量显式注入签名密钥，再调用 `pnpm tauri:build:<arch>`。历史脚本 `tauri:build:signed:*` 等价于 `./scripts/build-signed.sh`，但它仍期望旧路径 `configs/env/.env.tauri-signing`，当前仓库没有该目录；除非先恢复该 gitignored env 文件，否则不要依赖它。

`scripts/build-signed.sh` 的设计意图是：

1. 自动加载 `configs/env/.env.tauri-signing`（签名密钥）
2. 自动加载 `configs/env/.env.production`（前端 Supabase 配置）
3. 调用对应平台的 `tauri:build:<arch>`

产物位置（以 mac-arm 为例；mac-intel 对应 `x86_64-apple-darwin`）：

```
src-tauri/target/aarch64-apple-darwin/release/bundle/
├── dmg/Sage_<version>_aarch64.dmg
├── macos/Sage.app.tar.gz         ← updater payload
└── macos/Sage.app.tar.gz.sig     ← updater 签名
```

> 当前不发布 Windows；若未来恢复，macOS 上也无法交叉编译 Windows（缺 MSVC 工具链），必须走 CI。

### 本地手动 GitHub Release（CI 未跑时）

当需要手动发一个完整 GitHub Release 时，必须完成四件事：

1. 版本号同步并提交推送。
2. 生成签名后的 `.app.tar.gz` 和 `.sig`。
3. 创建 GitHub tag + Release 并上传 DMG / updater payload / 签名。
4. 更新 Railway 的 `SAGE_UPDATER_MANIFEST_JSON`，让 `/updater/latest.json`
   返回稳定 manifest。

> v1.4.6 起，客户端 updater 主 endpoint 是 Railway：
> `https://sage-production-28e1.up.railway.app/updater/latest.json`。
> GitHub `releases/latest/download/latest.json` 可作为第二 fallback endpoint，但不要放第一；
> 它会 302 到临时 `release-assets.githubusercontent.com` URL，Tauri updater
> 偶发拿到 504/HTML 时会报 `Could not fetch a valid release JSON from the remote`。
> 二进制产物（DMG / `.app.tar.gz` / `.sig`）仍放在 GitHub Release，保证用户手动下载和应用内更新下载都走 GitHub。
> 服务端会优先读取 `SAGE_UPDATER_MANIFEST_JSON`，缺失时使用代码内置的当前稳定 manifest 兜底；每次发布后仍应更新 Railway env，避免长期依赖内置值。

推荐流程（以 `1.4.3` / mac-arm 为例）：

```bash
# 1. 同步版本
VERSION=1.4.3
./scripts/version.sh "$VERSION"
cargo metadata --manifest-path "src-tauri/Cargo.toml" --format-version 1 >/tmp/sage-cargo-metadata.json

# 2. 验证
pnpm build:api
pnpm build

# 3. 提交和推送
git add package.json src-api/package.json src-tauri/tauri.conf.json \
  src-tauri/Cargo.toml src-tauri/Cargo.lock <changed-files>
git commit -m "fix(...): ..."
git push origin main

# 4. 打包。若 Cargo 报旧绝对路径缓存，可先 cargo clean。
pnpm tauri:build:mac-arm
pnpm tauri:build:mac-intel
```

`pnpm tauri:build:mac-arm` 如果缺少 `TAURI_SIGNING_PRIVATE_KEY` 会先生成 `.app` / `.dmg` / `.app.tar.gz`，最后签名失败。此时需要按「签名密钥管理」章节设置环境变量后重跑。

本地凭证文件 `sage-tauri-signing-key-v2.txt` 是说明文档格式，不是 `.env`，**不能直接 `source`**。临时注入方式：

```bash
TAURI_SIGNING_PRIVATE_KEY="$(python3 - <<'PY'
from pathlib import Path
import re
lines = Path('/Users/nakocai/Documents/Projects/项目/Sage/.env/sage-tauri-signing-key-v2.txt').read_text().splitlines()
in_private = False
for line in lines:
    if '【私钥 PRIVATE KEY】' in line:
        in_private = True
        continue
    if in_private and line.startswith('【'):
        break
    value = line.strip()
    if in_private and len(value) > 80 and re.fullmatch(r'[A-Za-z0-9+/=]+', value):
        print(value)
        raise SystemExit
raise SystemExit('private key not found')
PY
)" TAURI_SIGNING_PRIVATE_KEY_PASSWORD="$(python3 - <<'PY'
from pathlib import Path
lines = Path('/Users/nakocai/Documents/Projects/项目/Sage/.env/sage-tauri-signing-key-v2.txt').read_text().splitlines()
in_password = False
for line in lines:
    if '【密码 PASSPHRASE】' in line:
        in_password = True
        continue
    if in_password and line.startswith('【'):
        break
    value = line.strip()
    if in_password and value and all(ord(ch) < 128 for ch in value) and not set(value) <= {'═','─'}:
        print(value)
        raise SystemExit
raise SystemExit('password not found')
PY
)" pnpm tauri:build:mac-arm

# Intel 包同理，把最后的 build 命令换成：
# pnpm tauri:build:mac-intel
```

> 不要把私钥或密码打印到终端，不要提交任何 `.env/` 文件。

手工暂存双平台 release 资产并生成 manifest：

```bash
VERSION=1.4.3
rm -rf /tmp/sage-release-assets
rm -rf /tmp/sage-release-artifacts
mkdir -p /tmp/sage-release-assets
mkdir -p /tmp/sage-release-artifacts/aarch64-apple-darwin
mkdir -p /tmp/sage-release-artifacts/x86_64-apple-darwin

cp src-tauri/target/aarch64-apple-darwin/release/bundle/dmg/Sage_${VERSION}_aarch64.dmg \
  "/tmp/sage-release-assets/sage-${VERSION}-aarch64-apple-darwin.dmg"
cp src-tauri/target/x86_64-apple-darwin/release/bundle/dmg/Sage_${VERSION}_x64.dmg \
  "/tmp/sage-release-assets/sage-${VERSION}-x86_64-apple-darwin.dmg"
cp src-tauri/target/aarch64-apple-darwin/release/bundle/macos/Sage.app.tar.gz \
  "/tmp/sage-release-artifacts/aarch64-apple-darwin/sage-${VERSION}-aarch64-apple-darwin.app.tar.gz"
cp src-tauri/target/aarch64-apple-darwin/release/bundle/macos/Sage.app.tar.gz.sig \
  "/tmp/sage-release-artifacts/aarch64-apple-darwin/sage-${VERSION}-aarch64-apple-darwin.app.tar.gz.sig"
cp src-tauri/target/x86_64-apple-darwin/release/bundle/macos/Sage.app.tar.gz \
  "/tmp/sage-release-artifacts/x86_64-apple-darwin/sage-${VERSION}-x86_64-apple-darwin.app.tar.gz"
cp src-tauri/target/x86_64-apple-darwin/release/bundle/macos/Sage.app.tar.gz.sig \
  "/tmp/sage-release-artifacts/x86_64-apple-darwin/sage-${VERSION}-x86_64-apple-darwin.app.tar.gz.sig"

LATEST_JSON_NOTES="See release notes." ./scripts/gen-latest-json.sh \
  "$VERSION" \
  /tmp/sage-release-artifacts \
  "https://github.com/buuzzy/sage/releases/download/v${VERSION}"

cp latest.json /tmp/latest.json
cp /tmp/sage-release-artifacts/aarch64-apple-darwin/* /tmp/sage-release-assets/
cp /tmp/sage-release-artifacts/x86_64-apple-darwin/* /tmp/sage-release-assets/
cp /tmp/latest.json /tmp/sage-release-assets/latest.json
```

手工创建 Release：

```bash
git tag v1.4.3
git push origin v1.4.3

gh release create v1.4.3 /tmp/sage-release-assets/* \
  --target main \
  --latest \
  --title "v1.4.3" \
  --notes "Release notes here"
```

将同一份 manifest 写入 Railway env：

```bash
RAILWAY_CALLER="manual-release" railway variable set \
  SAGE_UPDATER_MANIFEST_JSON="$(python3 - <<'PY'
from pathlib import Path
print(Path('/tmp/latest.json').read_text())
PY
)" --service sage

RAILWAY_CALLER="manual-release" railway up --detach -m "update updater manifest"
```

如果 Release 已存在，更新资产时使用：

```bash
gh release upload v1.4.3 /tmp/sage-release-assets/* --clobber
```

注意：`gh release upload /tmp/latest.json#latest.json` 里的 `#latest.json` 只是 label，不会改资产真实文件名。若上传 GitHub 备份，Release 资产名必须真的叫 `latest.json`。

发布后必须校验：

```bash
gh release view v1.4.3 --json assets,url

python3 - <<'PY'
import json, urllib.request
for url in [
    'https://sage-production-28e1.up.railway.app/updater/latest.json',
    'https://github.com/buuzzy/sage/releases/latest/download/latest.json',
]:
    with urllib.request.urlopen(url, timeout=20) as response:
        data = json.loads(response.read().decode('utf-8'))
    platforms = data.get('platforms') or {}
    print(url)
    print('  status', response.status)
    print('  version', data.get('version'))
    print('  platforms', ','.join(sorted(platforms.keys())))
    print('  darwin-aarch64', bool(platforms.get('darwin-aarch64', {}).get('signature')))
    print('  darwin-x86_64', bool(platforms.get('darwin-x86_64', {}).get('signature')))
PY
```

`status 200` 且版本号正确后，已升级到 v1.4.6+ 的客户端 About 页「重试」才会稳定检测到新版。v1.4.5 及更早客户端仍使用旧 GitHub endpoint，必要时让用户手动安装一次 v1.4.6 过渡。

---

## 6. 签名密钥管理

### Tauri Updater 签名（必需）

- **CI 用**：GitHub Secrets 里的 `TAURI_SIGNING_PRIVATE_KEY` + `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`
- **本地用**：`/Users/nakocai/Documents/Projects/项目/Sage/.env/sage-tauri-signing-key-v2.txt`
- **旧脚本期望**：`configs/env/.env.tauri-signing`，但当前仓库没有该目录；若要恢复 `scripts/build-signed.sh` 的一键体验，需要重新创建 gitignored env 文件或更新脚本读取当前保险库路径。

公钥已固化在 `tauri.conf.json` 的 `updater.pubkey` 字段。私钥**永不能丢**——丢了就再也无法发布老客户端能验证通过的更新，所有现有用户必须手动重装。

当前本机凭证保险库路径：

```text
/Users/nakocai/Documents/Projects/项目/Sage/.env/
```

里面的 `sage-tauri-signing-key-v2.txt` 是人工阅读格式，包含「【私钥 PRIVATE KEY】」和「【密码 PASSPHRASE】」两个段落。自动化脚本必须按段落抽取 base64 私钥和密码，不要直接 `source`。

### 重新生成签名密钥（紧急情况）

```bash
pnpm exec tauri signer generate --ci --password '' --write-keys ~/.sage-updater.key
```

把私钥内容写入 `configs/env/.env.tauri-signing`，把公钥替换到 `tauri.conf.json` 的 `pubkey`。**所有老用户的更新会失败一次**，需要他们手动重装新版本一次以替换公钥，之后才能继续应用内更新。

### macOS 公证签名（可选，非 MAS 渠道）

当前 release.yml 不做公证（apple notarization）。用户首次安装时会看到「无法验证开发者」提示，需要右键→打开。如要消除此提示，未来需要：

1. Apple Developer ID 证书
2. notarytool 凭据
3. 在 release.yml 里加 `xcrun notarytool submit ... --wait`

---

## 7. 回滚 / 撤回 release

```bash
# 删除 GitHub Release（保留 tag）
gh release delete v1.0.7 --yes

# 同时删除 tag
git push origin :refs/tags/v1.0.7
git tag -d v1.0.7
```

如果错误版本已经被部分用户更新拿到，唯一补救方式是立刻发布 `v1.0.8` 修复版本。Updater 不支持降级。

---

## 8. 已知限制

| 限制 | 说明 | 跟踪 |
|---|---|---|
| 暂未公证 | macOS Gatekeeper 首次启动需右键打开 | 待 Apple Developer 账号 |
| Windows 暂不发布 | 当前只维护 macOS Apple Silicon 与 macOS Intel；如未来恢复 Windows，需要重新设计发布矩阵和安装包策略 | 产品决策 |

---

## 9. 故障排查

### CI build 失败：`Failed to bundle project: Failed to sign updater`

→ 检查 `TAURI_SIGNING_PRIVATE_KEY` Secret 是否正确（base64，无换行/空格）。

### CI build 失败：`error: linking with 'cc' failed`（Intel runner）

→ macos-15-intel runner 偶发，重跑一次 workflow 通常能过。

### 用户应用内更新不弹提示

→ 按以下顺序排查：
1. `latest.json` 是否被生成（CI release job 日志）
2. `latest.json` URL 是否能匿名访问
3. 客户端的 `tauri.conf.json` 里 `pubkey` 是否跟当前签名私钥配对
4. 客户端版本号是否真的旧于 `latest.json` 里的版本

### About 页显示：`Could not fetch a valid release JSON from the remote`

→ v1.4.6+ 通常是 Railway updater endpoint 配置错误：

1. 打开 `https://sage-production-28e1.up.railway.app/updater/latest.json`，必须返回 `200` JSON，不是 401/404/500。
2. Railway `SAGE_UPDATER_MANIFEST_JSON` 必须是完整 JSON，包含 `version`、`platforms.darwin-aarch64.url` 和 `signature`。
3. `url` 必须指向 GitHub Release 里的 `Sage.app.tar.gz`，`signature` 必须来自同名 `.sig` 文件。
4. 若用户仍在 v1.4.5 或更早版本，客户端还 baked 旧 GitHub endpoint；旧 endpoint 可能因 GitHub release asset 302/504 失败，必要时手动安装 v1.4.6 过渡。

### 本地 Tauri build 失败：`failed to read plugin permissions`，路径指向旧目录

→ `src-tauri/target` 中可能缓存了旧绝对路径。执行：

```bash
cargo clean --manifest-path "src-tauri/Cargo.toml"
pnpm tauri:build:mac-arm
```

### 本地签名失败：`A public key has been found, but no private key`

→ 没有设置 `TAURI_SIGNING_PRIVATE_KEY`。从 `/Users/nakocai/Documents/Projects/项目/Sage/.env/sage-tauri-signing-key-v2.txt` 按段落抽取后作为环境变量传给 `pnpm tauri:build:mac-arm`。

### 本地签名失败：`Invalid symbol 226, offset 0`

→ 把中文分隔线或说明文字误当成私钥了。私钥必须是 base64 长行，使用上文 Python 正则 `r'[A-Za-z0-9+/=]+'` 过滤。

### 用户安装后双击「无响应/闪退」

→ 大概率是 macOS Gatekeeper 拦截。指引用户**右键点 Sage → 选「打开」**，弹窗里点「打开」确认一次即可，之后正常双击。

### CI 产物文件名包含中文导致上传失败

→ 不应再发生。`release.yml` 的 stage 步骤已经把所有产物重命名为 ASCII（`sage-<ver>-<triple>.*`）。如果仍出现，检查 staging 步骤的 `cp` 是否漏掉某个产物。

---

## 10. 参考文件

| 文件 | 作用 |
|---|---|
| `.github/workflows/release.yml` | CI 工作流定义 |
| `scripts/build-signed.sh` | 本地签名打包入口 |
| `scripts/gen-latest-json.sh` | updater manifest 生成 |
| `scripts/version.sh` | 多文件版本同步 |
| `src-tauri/tauri.conf.json` | Tauri 配置（含 updater pubkey + endpoints） |
| `configs/env/.env.tauri-signing` | 本地签名密钥（gitignore） |
| `configs/env/.env.production` | 本地 Supabase 生产配置（gitignore） |

---

## 11. iOS 端发布（TestFlight / App Store）

iOS 客户端是独立的 SwiftUI 工程（`sage-ios/`），通过 Xcode Archive → App Store Connect → TestFlight 分发，不走 Tauri updater 通道。

### 11.1 版本号管理

iOS 版本号在两处，**必须同步**：

| 位置 | 字段 | 说明 |
|------|------|------|
| `sage-ios/Sage.xcodeproj/project.pbxproj` | `CURRENT_PROJECT_VERSION` | Build number（每次上传递增） |
| `sage-ios/Sage/Info.plist` | `CFBundleVersion` | **同上，必须与 pbxproj 一致** |
| `sage-ios/Sage.xcodeproj/project.pbxproj` | `MARKETING_VERSION` | 用户可见版本号（如 1.0.0） |
| `sage-ios/Sage/Info.plist` | `CFBundleShortVersionString` | **同上** |

⚠️ **关键教训**：`Info.plist` 里的值会覆盖 `project.pbxproj` 的 build settings。两处必须同步修改，否则 Archive 出来的包仍是旧版本号。

### 11.2 递增 Build Number

每次上传 TestFlight 前必须递增 build number：

```bash
cd sage-ios

# 用 PlistBuddy 修改 Info.plist
NEW_BUILD=20  # 改成目标数字
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" Sage/Info.plist

# 同步 pbxproj
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = $NEW_BUILD/g" Sage.xcodeproj/project.pbxproj

# 验证
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Sage/Info.plist
grep "CURRENT_PROJECT_VERSION" Sage.xcodeproj/project.pbxproj
```

### 11.3 前置条件

- Xcode 已登录 Apple Developer 账号
- `sage-ios/Sage/Config/Secrets.xcconfig` 已填入 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY`
- Signing & Capabilities 配置正确（Team: YIYANG CAI (QB576QUT2S), Bundle ID: com.sage.app）

### 11.4 打包上传流程

```bash
# 1. 确保代码最新
cd "/Users/nakocai/Documents/Projects/项目/Sage/sage"
git pull origin main

# 2. 递增 build number（见 11.2）

# 3. 提交版本号变更
git add -A
git commit -m "chore(ios): bump build number to <N>"
git push origin main

# 4. 在 Xcode 中 Archive
#    - 打开 sage-ios/Sage.xcodeproj
#    - 选择 target device 为 "Any iOS Device (arm64)"
#    - Product → Archive

# 5. Archive 完成后 Organizer 自动弹出
#    - 选择最新的 archive（确认版本号正确！）
#    - 点击 "Distribute App"
#    - 选择 "App Store Connect" → "Upload"
#    - 等待上传完成

# 6. 等待 Apple 处理（通常 5-30 分钟）
#    - App Store Connect → TestFlight 会出现新 build
#    - 首次提交需要填写出口合规信息（选"否"即可）
```

### 11.5 常见错误

| 错误 | 原因 | 解决 |
|------|------|------|
| `Redundant Binary Upload (90189)` | Build number 未递增，或 Info.plist 未同步 | 递增 Info.plist + pbxproj 的 build number，重新 Archive |
| Archive 后版本号仍是旧的 | Info.plist 覆盖了 pbxproj | 确保两处同步修改 |
| `No signing certificate` | 证书过期或未安装 | Xcode → Settings → Accounts → 下载证书 |
| `Missing Compliance` | 出口合规未填 | App Store Connect → TestFlight → 点击 build → 填写 |
| 上传成功但 TestFlight 无新版 | Apple 处理中 | 等 5-30 分钟；检查邮箱是否有 Apple 拒绝通知 |

### 11.6 TestFlight 分发

上传成功后：
1. 打开 [App Store Connect](https://appstoreconnect.apple.com)
2. 我的 App → Sage → TestFlight
3. 新 build 出现后，添加到测试员组
4. 测试员会收到 TestFlight 推送通知

### 11.7 注意事项

- iOS 和桌面端版本号**独立管理**：iOS 用纯数字递增的 build number，桌面端用 semver
- TestFlight 每次上传 build number **必须严格递增**：不能回退，不能重复
- 同一个 `MARKETING_VERSION`（如 1.0.0）下可以上传多个 build（19, 20, 21...）
- 改完代码后必须**重新 Archive**，不能复用旧的 archive 包
