# src-tauri/ — Tauri 2 桌面壳

macOS 桌面应用的原生壳。管理窗口、sidecar 生命周期、deep-link、自动更新。**不含业务逻辑**——业务全在 src-api sidecar 里。

## 文件清单

| 文件 | 职责 | 稳定度 |
|------|------|--------|
| src/lib.rs | sidecar 启动 + `load_dotenv()` 加载 ~/.sage/.env + deep-link 注册 | ⚠️ 核心 |
| src/main.rs | 入口（极简，调用 lib） | 🔒 |
| tauri.conf.json | 主配置（identifier, version, updater, sidecar 路径, plugins） | ⚠️ |
| tauri.appstore.conf.json | Mac App Store 构建专用配置 | 🔧 |
| Cargo.toml | Rust 依赖（version 必须与 package.json 同步） | 🔒 |
| Cargo.lock | 锁定依赖版本 | 🔒 |
| capabilities/default.json | Tauri 权限声明（fs, shell, dialog, deep-link, updater...） | 🔒 除非加新插件 |
| entitlements.plist | macOS 权限（network, jit） | 🔒 |
| entitlements.appstore.plist | Mac App Store sandbox 权限 | 🔧 |
| Info.plist | macOS 应用 metadata | 🔒 |
| binaries/ | 预编译 sidecar 二进制（由 build:binary 生成） | 自动生成 |
| icons/ | 应用图标（多尺寸） | 🔒 |

## sidecar 生命周期

```
Tauri 启动
  → lib.rs: 检查 SAGE_USE_LOCAL_SIDECAR 环境变量（预读 ~/.sage/.env）
  → 默认：跳过 sidecar，桌面端直连 Railway 云端后端
  → SAGE_USE_LOCAL_SIDECAR=1：启动本地 sage-api binary（端口 2026）
  → WebView 加载前端（localhost:1420 dev / dist/ prod）
  → 前端通过 Railway URL 或 127.0.0.1:2026 与后端通信
  → App 退出 → sidecar 进程随之终止（若已启动）
```

## tauri.conf.json 关键配置

| 字段 | 当前值 | 说明 |
|------|--------|------|
| identifier | `ai.sage.desktop` | 不要改（影响 keychain + updater） |
| version | `1.4.16` | 必须与 package.json + Cargo.toml 同步 |
| updater.pubkey | `dW50cnVz...` | 不要改（除非重新生成签名密钥） |
| updater.endpoints | Railway → GitHub fallback | 优先 Railway 稳定 JSON |
| bundle.externalBin | `../src-api/dist/sage-api` | 必须匹配 build:binary 输出路径 |
| plugins.deep-link.schemes | `["sage"]` | `sage://auth/callback` OAuth 回调 |

## 不要做的事

- **不在 Rust 层写业务逻辑**（所有业务在 src-api）
- **不改 identifier**（会破坏 keychain 存储 + updater 校验）
- **不改 updater pubkey**（除非重新生成签名密钥对）
- **不删 externalBin**（sidecar 路径必须匹配 build:binary 输出）
- **不单独改 version**（必须用 `./scripts/version.sh` 三处同步）
- **不手动编辑 Cargo.lock**（让 cargo 自动管理）

## 版本同步规则

改版本时用 `./scripts/version.sh <new-version>`，会同步修改：
1. `package.json` → `"version"`
2. `src-tauri/tauri.conf.json` → `"version"`
3. `src-tauri/Cargo.toml` → `version = "..."`
4. `src-api/package.json` → `"version"`
