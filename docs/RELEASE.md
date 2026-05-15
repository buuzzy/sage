# Sage 发布流程

本文档描述 Sage 桌面端从「写完代码」到「用户拿到新版本」的完整流程。iOS 端走 Capacitor + Railway，详见 `docs/ios/IOS_PLAN.md`。

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

> Windows x64 暂未启用，恢复方式见 `release.yml` 注释（取消 matrix include 注释 + Tauri build 加 `--bundles nsis`）。

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

产物位置（以 mac-arm 为例）：

```
src-tauri/target/aarch64-apple-darwin/release/bundle/
├── dmg/Sage_<version>_aarch64.dmg
├── macos/Sage.app.tar.gz         ← updater payload
└── macos/Sage.app.tar.gz.sig     ← updater 签名
```

> macOS 上无法交叉编译 Windows（缺 MSVC 工具链），Windows 必须走 CI。

### 本地手动 GitHub Release（CI 未跑时）

当需要手动发一个完整 GitHub Release 时，必须完成四件事：

1. 版本号同步并提交推送。
2. 生成签名后的 `.app.tar.gz` 和 `.sig`。
3. 创建 GitHub tag + Release 并上传 DMG / updater payload / 签名。
4. 更新 Railway 的 `SAGE_UPDATER_MANIFEST_JSON`，让 `/updater/latest.json`
   返回稳定 manifest。

> v1.4.6 起，客户端 updater endpoint 是 Railway：
> `https://sage-production-28e1.up.railway.app/updater/latest.json`。
> 不要把 GitHub `releases/latest/download/latest.json` 作为客户端 endpoint；
> 它会 302 到临时 `release-assets.githubusercontent.com` URL，Tauri updater
> 偶发拿到 504/HTML 时会报 `Could not fetch a valid release JSON from the remote`。
> 服务端会优先读取 `SAGE_UPDATER_MANIFEST_JSON`，缺失时使用代码内置的当前稳定 manifest 兜底；每次发布后仍应更新 Railway env，避免长期依赖内置值。

推荐流程（以 `1.4.3` / mac-arm 为例）：

```bash
# 1. 同步版本
./scripts/version.sh 1.4.3
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
```

> 不要把私钥或密码打印到终端，不要提交任何 `.env/` 文件。

手工创建 Release：

```bash
git tag v1.4.3
git push origin v1.4.3

gh release create v1.4.3 \
  "src-tauri/target/aarch64-apple-darwin/release/bundle/dmg/Sage_1.4.3_aarch64.dmg" \
  "src-tauri/target/aarch64-apple-darwin/release/bundle/macos/Sage.app.tar.gz" \
  "src-tauri/target/aarch64-apple-darwin/release/bundle/macos/Sage.app.tar.gz.sig" \
  --target main \
  --latest \
  --title "v1.4.3" \
  --notes "Release notes here"
```

手工生成 manifest（单 mac-arm 包），并写入 Railway env：

```bash
python3 - <<'PY'
import json
from datetime import datetime, timezone
from pathlib import Path

version = '1.4.3'
signature = Path(
    'src-tauri/target/aarch64-apple-darwin/release/bundle/macos/Sage.app.tar.gz.sig'
).read_text().strip()

latest = {
    'version': version,
    'notes': 'See release notes.',
    'pub_date': datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z'),
    'platforms': {
        'darwin-aarch64': {
            'signature': signature,
            'url': f'https://github.com/buuzzy/sage/releases/download/v{version}/Sage.app.tar.gz',
        },
    },
}

Path('/tmp/latest.json').write_text(json.dumps(latest, indent=2) + '\n')
PY

RAILWAY_CALLER="manual-release" railway variable set \
  SAGE_UPDATER_MANIFEST_JSON="$(python3 - <<'PY'
from pathlib import Path
print(Path('/tmp/latest.json').read_text())
PY
)" --service sage

RAILWAY_CALLER="manual-release" railway up --detach -m "update updater manifest"
```

仍建议把 `latest.json` 同步上传到 GitHub Release 作为人工审计备份，但客户端不再依赖它：

```bash
gh release upload v1.4.3 /tmp/latest.json --clobber
```

注意：`gh release upload /tmp/latest.json#latest.json` 里的 `#latest.json` 只是 label，不会改资产真实文件名。若上传 GitHub 备份，Release 资产名必须真的叫 `latest.json`。

发布后必须校验：

```bash
gh release view v1.4.3 --json assets,url

python3 - <<'PY'
import json, urllib.request
url = 'https://sage-production-28e1.up.railway.app/updater/latest.json'
with urllib.request.urlopen(url, timeout=20) as response:
    data = json.loads(response.read().decode('utf-8'))
    print('status', response.status)
    print('version', data.get('version'))
    print('platforms', ','.join(sorted((data.get('platforms') or {}).keys())))
    print('has_signature', bool(data.get('platforms', {}).get('darwin-aarch64', {}).get('signature')))
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
| Windows x64 暂缓 | 历史原因为中文产品名走 WiX `light.exe` 编码 bug；产品已改名 Sage 后理论上可恢复，需要 CI matrix 解注释 + 加 `--bundles nsis` | TODO.md P3 |
| 暂未公证 | macOS Gatekeeper 首次启动需右键打开 | 待 Apple Developer 账号 |
| Tauri 默认 `targets: "all"` 会同时打 NSIS + MSI | Windows 恢复时务必加 `--bundles nsis` 跳过 MSI | release.yml 注释 |

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
