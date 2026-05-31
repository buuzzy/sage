# Sage — Claude Code 项目笔记

## 文档分层机制

本项目采用**分层 CLAUDE.md** 架构管理上下文。根文件提供全局概览，各子目录的 CLAUDE.md 提供该模块的详细文档。

**规则**：
- 修改某个模块前，**先读该模块的 CLAUDE.md**（了解文件清单、不变量、扩展步骤）
- 根 CLAUDE.md 只保留全局信息（技术栈、构建命令、环境变量、发布流程、经验教训）
- 模块内部的架构细节、文件职责、接口约定由子目录 CLAUDE.md 负责

**子目录文档索引**：

| 路径 | 覆盖范围 |
|------|---------|
| `src/CLAUDE.md` | 前端架构、页面路由、状态管理、平台分叉 |
| `src/shared/CLAUDE.md` | hooks / db / sync / lib / providers 职责边界 |
| `src/components/htui/CLAUDE.md` | 14 个金融可视化组件协议 + 新增模板 |
| `src-api/CLAUDE.md` | 后端架构、API 路由一览、中间件 |
| `src-api/src/extensions/agent/codeany/CLAUDE.md` | Agent 适配器完整流程 + 拦截机制 |
| `src-api/src/shared/CLAUDE.md` | 后端子系统职责 + 依赖关系 |
| `src-api/src/shared/memory/CLAUDE.md` | 四层记忆系统 + 双模式鉴权 |
| `src-api/src/shared/context/CLAUDE.md` | 上下文组装 + compaction 规则 |
| `src-tauri/CLAUDE.md` | Rust 桌面壳 + sidecar 生命周期 + 不可修改项 |
| `docs/RELEASE.md` | 桌面端 + iOS 端打包发布完整流程 |

---

## 项目概览

Sage 是一个 AI 金融助手（v1.4.16），支持桌面端（macOS ARM/Intel）和移动端（iOS）。桌面端用 Tauri 2，iOS 端用 SwiftUI 原生客户端（`sage-ios/`）。后端是 Hono HTTP sidecar / Railway 云端服务，内嵌 Agent 运行时、17 个金融技能、记忆系统和定时调度器。

## 技术栈

| 层 | 桌面端 | iOS 端 |
|---|---|---|
| 壳 | Tauri 2 (Rust) | SwiftUI 原生 |
| 前端 | React 19 + Vite 7 + TailwindCSS 4 | SwiftUI |
| 后端 | Railway 云端 (`sage-production-28e1.up.railway.app`) | 同左（统一后端） |
| Agent SDK | `@codeany/open-agent-sdk@0.2.1` (+ pnpm patch) | 同左（后端共享） |
| 默认模型 | `claude-sonnet-4-20250514` | 同左 |
| 数据库 | IndexedDB（本地缓存）+ Supabase（云端持久化） | 同左（统一数据源） |
| 图表 | ECharts 6 (柱/线/热力) + TradingView Lightweight Charts v5 (K线/分时) | 同左 |
| UI 库 | Ant Design 6 + Radix UI + shadcn/ui | 同左 |
| 认证 | OAuth (GitHub/Google) via deep-link (`sage://auth/callback`) | 邮箱/密码（OAuth 待适配） |

**运行时要求**: Node.js >= 22.13, pnpm 10.33.0 (`packageManager` 字段锁定)

## 关键目录（详细文件清单见各子目录 CLAUDE.md）

```
sage/                          ← pnpm workspace root
├── src/                       ← React 前端（详见 src/CLAUDE.md）
├── src-api/                   ← Hono 后端（详见 src-api/CLAUDE.md）
├── src-tauri/                 ← Rust 桌面壳（详见 src-tauri/CLAUDE.md）
├── sage-ios/                  ← SwiftUI 原生 iOS 客户端
├── supabase/migrations/       ← Supabase 数据库 migration
├── scripts/                   ← 构建/发布脚本
├── docs/                      ← 项目文档（TODO.md 是唯一权威 TODO）
├── .github/workflows/         ← CI（tag push → 多平台构建）
└── patches/                   ← SDK pnpm patch
```

## 构建与部署

> **打包发布完整流程**（桌面端 + iOS 端）见 `docs/RELEASE.md`。

```bash
# 开发模式
pnpm dev:api                        # 后端 Hono sidecar (tsx --watch)
pnpm dev                            # 前端 Vite dev server (localhost:1420)
pnpm tauri:dev                      # 完整桌面开发（含 sidecar + Tauri）

# 生产构建
pnpm build:api                      # TS→JS 编译（不生成二进制）
pnpm build:api:binary:mac-arm       # 生成 sage-api ARM 独立二进制 (pkg → node18)
pnpm build:api:binary:mac-intel     # 生成 sage-api Intel 独立二进制
pnpm build:app:mac-arm              # 完整 .app 打包（API binary + 前端 + Tauri）
pnpm build:app:mac-arm:release      # 带签名的发布构建
pnpm tauri:build:mac-arm            # Tauri 原生构建（需预编译 API binary）
pnpm tauri:build:mac-intel          # Intel macOS Tauri 构建
pnpm build:ios                      # iOS: xcodebuild 构建 SwiftUI 客户端
pnpm open:ios                       # 打开 sage-ios/Sage.xcodeproj

# 代码质量
pnpm lint                           # ESLint (src/)
pnpm lint:fix                       # ESLint auto-fix
pnpm format                         # Prettier
```

**桌面端注意**: App 运行的是 `.app/Contents/MacOS/sage-api` 二进制，不是 tsx 源码。改了后端代码必须重新生成二进制并打包。

**桌面发布注意**: GitHub Release 里上传 `.dmg` / `.app.tar.gz` / `.sig`；Tauri updater 的 manifest 从 v1.4.6 起主通道走 Railway 稳定 endpoint `https://sage-production-28e1.up.railway.app/updater/latest.json`，GitHub `latest.json` 只作为第二 fallback endpoint。完整手工发布、签名密钥解析、manifest 配置和校验流程见 `docs/RELEASE.md`。

**固定桌面 release 流程**:
1. 只有用户明确要求 release，或改动涉及 `src-tauri/tauri.conf.json` / updater / 桌面 sidecar 行为时，才发布新桌面版本。
2. 先提交功能修复，再用 `./scripts/version.sh <next>` bump 版本并单独提交 `chore: bump version to <next>`。
3. 打 tag 并推送：`git tag -a v<next> -m "v<next>" && git push origin main && git push origin v<next>`
4. 本地构建签名 + 公证包：`pnpm build:app:mac-arm:release`（即 `./scripts/build-signed.sh mac-arm`）。
5. GitHub Release 必须上传每个平台的 DMG、`.app.tar.gz`、`.app.tar.gz.sig`、`latest.json`；二进制下载源保持 GitHub。
6. Railway `SAGE_UPDATER_MANIFEST_JSON` 是 updater manifest 的权威控制面；发布后必须更新 env、redeploy，并校验 Railway endpoint 和 GitHub fallback endpoint 都返回新版本、`darwin-aarch64` / `darwin-x86_64` 平台项与有效签名。
7. `src-api/src/app/api/updater.ts` 的 `BUILT_IN_MANIFEST` 只是 env 缺失时的最后兜底，不要依赖它长期发布。
8. **若 `build-signed.sh` 因 Apple 公证服务 500 失败**，必须手动补完以下步骤（见下方「手动补签名 + 公证流程」）。

**手动补签名 + 公证流程**（当 `build-signed.sh` 因 Apple 500 失败时）:

```bash
# ── 前置变量
BUNDLE_DIR="src-tauri/target/aarch64-apple-darwin/release/bundle"
APP_PATH="$BUNDLE_DIR/macos/Sage.app"
IDENTITY="Developer ID Application: YIYANG CAI (QB576QUT2S)"
ENTITLEMENTS="src-tauri/entitlements.devid.plist"
API_KEY_PATH="/Users/nakocai/Documents/Projects/项目/Sage/.env/AuthKey_QQKFHN5SQ3.p8"

# 1️⃣ 重新签名（hardened runtime + timestamp，公证必需）
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH/Contents/MacOS/sage-api"
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH/Contents/MacOS/sage"
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

# 2️⃣ 清除 extended attributes + 打包 tar.gz（必须用 COPYFILE_DISABLE）
xattr -cr "$APP_PATH"
COPYFILE_DISABLE=1 tar -czf "$BUNDLE_DIR/macos/Sage.app.tar.gz" -C "$BUNDLE_DIR/macos" Sage.app

# 3️⃣ 签名 tar.gz（Tauri updater 验签用）
source configs/env/.env.tauri-signing
pnpm tauri signer sign --private-key "$TAURI_SIGNING_PRIVATE_KEY" --password "$TAURI_SIGNING_PRIVATE_KEY_PASSWORD" "$BUNDLE_DIR/macos/Sage.app.tar.gz"

# 4️⃣ 创建 DMG + 签名
rm -f "$BUNDLE_DIR/dmg/Sage_<version>_aarch64.dmg"
hdiutil create -volname "Sage" -srcfolder "$APP_PATH" -ov -format UDZO "$BUNDLE_DIR/dmg/Sage_<version>_aarch64.dmg"
codesign --force --sign "$IDENTITY" --timestamp "$BUNDLE_DIR/dmg/Sage_<version>_aarch64.dmg"

# 5️⃣ 公证 DMG
xcrun notarytool submit "$BUNDLE_DIR/dmg/Sage_<version>_aarch64.dmg" \
  --key "$API_KEY_PATH" --key-id "QQKFHN5SQ3" --issuer "4fd5778f-6e6d-4fd3-8546-fb36937b3036" --wait
xcrun stapler staple "$BUNDLE_DIR/dmg/Sage_<version>_aarch64.dmg"
```

**打包严重注意事项**:

| 项目 | 说明 |
|------|------|
| `tauri.conf.json` 的 `externalBin` | 只允许 `["../src-api/dist/sage-api"]`。不要加其他二进制（如 codex/claude），否则会报错或膨胀 |
| `tauri.conf.json` 的 `resources` | 只允许 `{"../src-api/resources": "resources"}`。不要加 `cli-bundle` 等大目录，否则 .app 会从 ~85MB 膨胀到 700MB+ |
| `COPYFILE_DISABLE=1` | macOS `tar` 默认会打包 `._` AppleDouble 文件，Tauri updater 解包时会报错 `failed to unpack ._Sage.app`。**必须**用 `COPYFILE_DISABLE=1 tar` |
| `xattr -cr` | 打包前必须清除 extended attributes，否则即使用了 `COPYFILE_DISABLE` 也可能残留问题 |
| `--options runtime --timestamp` | codesign 必须加这两个参数，否则 Apple 公证会拒绝（"hardened runtime not enabled" / "no secure timestamp"） |
| 提交前检查 `git diff` | 确认没有意外的 `tauri.conf.json` 改动被带入（尤其是 `externalBin` 和 `resources` 字段） |

**Apple 签名凭据位置**（不入 git，本地机器持有）:

| 凭据 | 路径 / 值 |
|------|-----------|
| Developer ID Application 证书 | Keychain: `Developer ID Application: YIYANG CAI (QB576QUT2S)` |
| 证书文件备份 | `/Users/nakocai/Documents/Projects/项目/Sage/.env/developerID_application.cer` |
| Apple API Key (.p8) | `/Users/nakocai/Documents/Projects/项目/Sage/.env/AuthKey_QQKFHN5SQ3.p8` |
| API Key ID | `QQKFHN5SQ3` |
| API Issuer ID | `4fd5778f-6e6d-4fd3-8546-fb36937b3036` |
| Team ID | `QB576QUT2S` |
| CSR 文件 | `/Users/nakocai/Documents/Projects/项目/Sage/.env/CertificateSigningRequest.certSigningRequest` |
| Tauri updater 签名密钥 | `configs/env/.env.tauri-signing` (TAURI_SIGNING_PRIVATE_KEY) |
| MAS Provisioning Profile | `/Users/nakocai/Documents/Projects/项目/Sage/.env/Sage_Mac_App_Store.provisionprofile` |

`build-signed.sh` 自动读取以上凭据完成：codesign → Tauri 构建 → notarytool 公证 → staple。产出的 DMG 用户双击即可安装，无需 `xattr -cr`。

**iOS 端注意**: iOS 现在是 `sage-ios/` SwiftUI 原生客户端，不再使用 Capacitor WebView。改 Swift 代码后用 `pnpm open:ios` 打开 `sage-ios/Sage.xcodeproj`，或用 `pnpm build:ios` 走命令行构建。

## 平台差异处理

### API 地址（`src/config/index.ts`）
```typescript
// 所有平台统一连接 Railway 云端后端
const RAILWAY_URL = 'https://sage-production-28e1.up.railway.app';
export const API_BASE_URL = import.meta.env.VITE_API_URL || RAILWAY_URL;

// 本地开发时可设 VITE_API_URL=http://localhost:2026 连接本地 sidecar
```

### 数据存储（`src/config/index.ts` + `src/shared/db/database.ts`）
- **默认**（连接 Railway）：所有平台统一用 IndexedDB + Supabase，会话历史跨设备一致
- **本地开发**（`VITE_USE_LOCAL_SQLITE=1`）：桌面端用 SQLite + Supabase 双写
- 启动时若 IndexedDB 为空，自动从 Supabase 恢复会话历史

### Sidecar（`src-tauri/src/lib.rs`）
- **默认不启动 sidecar**（桌面端直连 Railway）
- 设 `SAGE_USE_LOCAL_SIDECAR=1` 在 `~/.sage/.env` 可恢复本地 sidecar 模式

### 认证（`src/shared/providers/auth-provider.tsx`）
- **桌面端**: OAuth → 系统浏览器 → deep-link (`sage://auth/callback`) 回调
- **iOS 端**: SwiftUI + Supabase Swift 邮箱/密码登录；OAuth 走原生 deep-link 适配
- **Supabase client** (`src/shared/lib/supabase.ts`): `detectSessionInUrl` 和 `flowType` 按 `isTauri` 分叉

### 鉴权（`src/shared/hooks/useAgent.ts` + `src-api/src/app/middleware/local-only.ts`）
- 所有平台统一注入 Supabase JWT Bearer token
- `SAGE_API_TOKEN` 环境变量设置时 → Bearer token 鉴权（Railway 云端）
- 未设置时 → loopback IP 检测（仅本地开发 sidecar 模式）

### Railway 部署
- URL: `https://sage-production-28e1.up.railway.app`
- 环境变量: `SAGE_API_TOKEN`（Bearer auth）
- Dockerfile 在项目根目录，多阶段构建（pnpm bundle → node:22-alpine）
- Builder 强制走 Dockerfile（`RAILWAY_DOCKERFILE_PATH=Dockerfile`），不要让 Railpack 自动检测

## 前端执行策略（概览，详见 `src/shared/CLAUDE.md`）

- `route: 'direct'` → POST `/agent`（跳过 plan 直接执行）
- `route: 'plan'` → POST `/agent/plan` → 用户审批 → POST `/agent/execute`
- 7 种策略分类：image / openai_provider / conversation / memory_recall / simple_lookup / multi_target / complex_task

## 记忆系统（概览，详见 `src-api/src/shared/memory/CLAUDE.md`）

四层架构：Persona 注入 → Active Recall → MCP Tool → Persona 蒸馏

## 工具拦截（概览，详见 `src-api/src/extensions/agent/codeany/CLAUDE.md`）

PostToolUse hook 确定性拦截 API 响应 → summary 替换 + artifact 生成

## SDK 补丁（pnpm patch，可复现）

| 文件 | 改动 |
|------|------|
| `@codeany/open-agent-sdk/dist/hooks.js` | 新增 `modifiedOutput` 字段 |
| `@codeany/open-agent-sdk/dist/engine.js` | PostToolUse 应用 modifiedOutput |
| `@codeany/open-agent-sdk/dist/hooks.d.ts` | 类型声明更新 |

`patches/@codeany__open-agent-sdk@0.2.1.patch` 仍需短期保留：上游 SDK 未提供正式的"替换 tool output 后继续进入模型上下文"扩展点。不要把 westock artifact 映射、summary 或 UI 协议写进 SDK patch。

## iOS 当前状态

- ✅ `sage-ios/` SwiftUI 原生客户端是唯一 iOS 工程
- ✅ Supabase Swift 登录、Railway API 调用、SSE 对话流可用
- ✅ 主界面、设置页、会话列表和基础聊天流程已迁移到原生 UI
- ⚠️ Capacitor `ios/` 遗留工程已移除；不要再运行 `npx cap sync/open ios`
- **下一步**: 继续补齐原生 iOS 的 Skills / MCP / Cron / Persona 管理与金融 artifact 展示

## CI/CD

- **GitHub Actions** (`.github/workflows/`): tag `v*` push → 多平台构建（mac-arm on macos-14, mac-intel on macos-15-intel）→ 自动创建 GitHub Release + 上传 DMG/tar.gz/sig/latest.json
- **Railway**: Dockerfile 自动部署，`SAGE_ENABLE_BACKGROUND_JOBS=true` 启用后台 cron
- **Windows 暂缓**: WiX MSI 中文编码 bug，workflow 里保留代码但注释掉

## 产品哲学

> **Sage 不是 ChatGPT 那样的 chat manager，是有记忆的伙伴。**
>
> **UI 是产品哲学的载体，不是功能的载体。** 每个 UI 元素都在向用户传递信号——保留它就是在告诉用户「Sage 是 X」，删掉它就是在告诉用户「Sage 不是 X」。

### 核心信念：连续性记忆

Sage 后端已经有四层连续记忆能力（详见 `src-api/src/shared/memory/CLAUDE.md`）：

| 层 | 能力 |
|---|---|
| L1 Persona Injection | 每次对话开始注入用户画像（hard rules / preferences / focus） |
| L2 Active Recall | 首轮 user message 主动召回 top-2 相关历史片段塞进 system prompt |
| L3 MCP `search_memory` | Agent 主动调用召回历史 |
| L4 Persona Distill | 每天凌晨 2 点蒸馏画像 |

**这四层加起来 = Agent 视角下没有「新对话」和「旧对话」的边界**——Agent 是带着完整记忆进入每段对话的。用户视角的「新对话」在 Agent 视角是同一段连续对话的下一段。**UI 必须匹配这个真实形态，不能装作 Agent 是失忆的。**

「回到旧对话」在这个语境下反而是不自然的——它把用户拽回 Agent **当时的快照状态**，丢掉了之后所有对话留下的痕迹。**等于跟一个已经过期的 Sage 实例对话。**

### 由此推导出的 UI 决策

| 不要做 | 要做 | 为什么 |
|---|---|---|
| 会话档案搜索框 | 让用户问 Agent「上次咱们聊 X 你怎么说的」 | 搜索框暗示「对话是分段档案」。AI 召回 + 在新对话注入历史片段才符合连续记忆形态 |
| 会话级跳转入口（"打开此会话"按钮） | Agent 引用过去事实并在当下继续推进 | 跳回旧对话 = 跟过期版本的 Sage 对话。"过去的事实"应该流入"现在的对话"，不是把用户拽回去 |
| 主界面工具入口（看行情/读研报快捷按钮） | 一句话需求 → Agent 自主选择技能 | 快捷按钮暗示 Sage 是工具集合，让 Agent 自主决策才符合「对话伙伴」 |
| 邮箱/密码登录 | 仅 OAuth | 传统 SaaS 心智模型 |
| 通用偏好繁琐设置 | 单击循环切换、隐藏复杂项 | 极简感支持「伙伴」心智 |

### 哲学起点（用户原话，2026-05-24）

> "用户回顾对话，就像回顾不同过去时间段的自己和 AI，这是断的。我们做的是连续性。
>
> 用户在新对话中和 AI 聊天，突然想起之前的一个对话，通过 mcp 召回对应段落，
> 这类似于你和好友在对话，你提到了共同做过的某件事，AI 回想后『想起了』这件事，
> 然后插入继续和你交流。这更 make sense。"

### 检验所有产品决策的过滤器

后续每个 UI / 交互决策必须先过这道：

> **"这个元素是在传递『Sage 是 chat manager』，还是『Sage 是有记忆的伙伴』的信号？"**

如果答案是前者，必须有非常硬的理由才能保留；否则就该删掉。

## 经验教训

> **修改 Agent 行为前，先从 `useAgent.ts` 的路由入口追到 `engine.ts` 的 agentic loop，画清完整链路再动手。不要从中间层开始改。**

> **不为单一弱模型加特殊路由 / 兜底**：架构应按"合理强模型"的能力标准设计，模型升级后产品自然受益。如果某个模型表现不佳，方案是**在文档里推荐换模型**，而不是写硬编码的 `if model == 'xxx'` 兜底层。

- Artifact 空壳闪烁有两个原因：① `React.lazy()` Suspense 延迟（已改高频组件为静态 import）；② API 响应格式 ≠ 组件数据格式（需要 `transformForComponent()` 转换）。
- API 错误响应（如 `{"code": -1, "msg": "鉴权失败"}`）也会被结构匹配误拦截，需检查 `parsed.code !== 0 && !parsed.data` 提前退出。
- MiniMax 在 OpenAI-format 下会对简单问题泛滥调用工具（73 次 tool calls），切换到 Anthropic Messages 协议后彻底解决。
- Fast chat 路径看似节省 token，但制造了能力边界问题。移除后所有查询走 Agent + 工具，体验反而更好。
- iwencai API 需要 X-Claw-* 系列 Header。两类端点格式不同：`/v1/query2data`（8 个数据查询技能）vs `/v1/comprehensive/search`（新闻/公告/研报）。
- API Key 不要硬编码在源码中。公共仓库 + 硬编码 = 立即泄露。清理 git 历史用 `git-filter-repo --replace-text`。
- **遇到「时灵时不灵」时**，先把变量列清楚（模型/prompt/输入）做一次干净对照实验，比连续猜代码逻辑高效。
- **低风险短请求不要走显式 plan**：用户问「你好/hi/回顾回测」时跳过 plan 直接执行。
- **模型不可用必须有可见失败语义**：stream 只有 `done` / 空文本时必须 yield `error`，前端补可见错误提示。
- **Running indicator 必须按当前 user turn 计算**：只看最后一条 `user` 之后的工具调用。
- **Plan approval 不能在 planning stream 未结束时可点击**：按钮显示条件必须是 `awaiting_approval && !isRunning`。
- **标题生成结果必须绑定 taskId**：`/agent/title` 是异步请求，不能用全局 `generatedTitle` 驱动。过滤纯数字和低质量标题。
- **Updater 采用混合通道**：Railway → GitHub fallback。GitHub 不放第一，避免 302/504。
- **Node.js sidecar 用 small-icu 编译**，`toLocaleString` 的 locale 参数会 fallback。需要稳定 ISO 时间字符串时用 `padStart` 手动拼。
- **Dockerfile 固定 pnpm 版本**：基镜像 `node:22-alpine`，pnpm 用 `corepack prepare pnpm@<exact-version>`，`packageManager` 字段锁定。
- **Phase 3 蒸馏**：前端存储 `type` 是 `user`（用户）和 `text`（助手），不是 `assistant`。蒸馏过滤必须用 `text`。
- **Context used 指示器**：中文按 chars/4 严重低估 tokens。正确口径要与后端 `assembleContext()` 的 `estimateTokens()` 一致。
- **Agent 工具循环必须有可见终止语义**：`error_max_turns` 不能让 task 继续保持 running。
- **Supabase 列类型必须与前端 ID 生成方式一致**：`createTask()` 用 `Date.now().toString()`（TEXT），新建表的 FK 不要误用 UUID。`PostgrestError` 不是 `Error` 实例，序列化时需要特殊处理。
- **启动体验**：v1.4.15 移除了 blocking startup screen，App 直接进入主 UI，sidecar readiness 异步检查。
- **Tauri updater 解包失败 `._Sage.app`**：macOS `tar` 默认生成 AppleDouble `._` 文件。打包前必须 `xattr -cr` + `COPYFILE_DISABLE=1 tar`。
- **App 从 ~40MB 膨胀到 700MB**：`tauri.conf.json` 的 `resources` 或 `externalBin` 被意外添加了大目录/文件。发布前必须检查 `externalBin` 只有 `sage-api`，`resources` 只有 `resources/`。
- **Apple 公证 500 不影响构建产物**：Tauri 构建 + codesign 已完成，只是公证步骤失败。等 Apple 服务恢复后手动补公证即可，不需要重新构建。
- **提交前必须 `git diff` 检查 `tauri.conf.json`**：避免将其他分支/实验性改动（externalBin、resources）意外带入 release commit。

## 待办事项

`docs/TODO.md` 是项目唯一权威 TODO。不要在 `CLAUDE.md` 里维护第二份 backlog；新增、删除、改优先级都同步到 `docs/TODO.md`。

## API Key 管理

金融数据 API Key 不在源码中硬编码，通过环境变量加载：

| Key | 用途 | 加载方式 |
|-----|------|----------|
| `IWENCAI_API_KEY` | 11 个 iwencai 技能 | `~/.sage/.env` → Tauri sidecar 注入 |
| `WESTOCK_API_KEY` | 4 个 westock 技能 | 同上 |
| `MIMO_API_KEY` | Phase 3 persona 蒸馏 LLM 的 API Key（当前用 DeepSeek） | Railway env only |
| `MIMO_BASE_URL` | 蒸馏 LLM 入口（当前 `https://api.deepseek.com`） | Railway env only |
| `MIMO_MODEL` | 蒸馏模型（当前 `deepseek-v4-flash`） | Railway env only |
| `SAGE_ENABLE_BACKGROUND_JOBS` | 设 `true` 才注册 cron。本地桌面端不设（避免双跑） | Railway env only |
| `SAGE_API_TOKEN` | 云端 Bearer 鉴权（设了走 token check，未设走 loopback IP 白名单） | Railway env only |
| `SAGE_UPDATER_MANIFEST_JSON` | Tauri updater manifest（Railway `/updater/latest.json` 优先返回；缺失时用代码内置兜底） | Railway env only |
| `SAGE_UPDATER_DARWIN_AARCH64_URL` / `..._SIGNATURE` / `..._X86_64_URL` / `..._SIGNATURE` | updater manifest 分项 env fallback | Railway env only |
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_ANON_KEY` | 云端数据 + RLS user-scoped 客户端 | Railway env (service role 仅云端) |
| `SAGE_INJECT_PERSONA` | Phase 3 persona 注入开关（默认 on） | 可选 |
| `SAGE_ENABLE_ACTIVE_RECALL` | Phase 4 主动召回开关（默认 on） | 可选 |
| `SAGE_APP_DIR` | 沙箱环境下覆盖 `~/.sage/` 路径 | Mac App Store sandbox |

Tauri 启动 sidecar 时从 `~/.sage/.env` 读取并传递环境变量（`src-tauri/src/lib.rs` 中的 `load_dotenv()`）。
Railway 部署需在环境变量中单独配置。

**Railway 当前部署**：URL `https://sage-production-28e1.up.railway.app`，项目名 `sage`，service 名 `sage`。Builder 强制走 Dockerfile（`RAILWAY_DOCKERFILE_PATH=Dockerfile`），不要让 Railpack 自动检测。

## Supabase 数据模型

| 表 | 用途 |
|---|---|
| `profiles` | 用户档案（扩展 auth.users） |
| `sessions` | 会话元数据（不含消息体，用于列表和跨设备同步） |
| `user_settings` | 用户偏好备份（不含 API Key） |
| `error_logs` | 客户端报错日志 |
| `messages` | 完整对话消息（按 user_id RLS 隔离） |
| `persona_memory` | Phase 3 蒸馏出的用户画像（profile + recent_threads） |
| `user_behavior` | 用户行为日志（task_id 为 TEXT） |
| `tasks` | 任务元数据（含 `provider_usage` JSON 字段） |

## 敏感凭证保险库

所有 macOS 签名 / Mac App Store 发布相关的私钥与证书统一收纳在 `/Users/nakocai/Documents/Projects/项目/Sage/.env/` 目录里（命名为 `.env` 是为了天然规避 git 跟踪）。当前清单：

| 文件 | 用途 |
|------|------|
| `sage-tauri-signing-key-v2.txt` | Tauri 自动更新签名私钥（对应 env: `TAURI_SIGNING_PRIVATE_KEY` + `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`；需按段落抽取） |
| `AuthKey_*.p8` | Apple Developer Auth Key（App Store Connect API / push） |
| `mac_app.cer` / `mac_installer.cer` | Mac App / Installer distribution 证书 |
| `Sage_Mac_App_Store.provisionprofile` | Mac App Store provisioning profile |
| `CertificateSigningRequest.certSigningRequest` | Apple CSR |
| `github-recovery-codes.txt` | GitHub 账户恢复码 |

新增任何敏感文件都放进这个目录，不要散落在仓库根或 `~/Documents/Projects/`。
