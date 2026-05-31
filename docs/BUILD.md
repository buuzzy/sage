# Sage 打包发布流程

> 本文档是桌面端（macOS）和 iOS 端的打包发布快速参考。  
> 桌面端完整细节见 `docs/RELEASE.md`，iOS 端以本文为准。

---

## 一、iOS 端（TestFlight / App Store）

### 1. 版本号管理

iOS 版本号在两处，**必须同步**：

| 位置 | 字段 | 说明 |
|------|------|------|
| `sage-ios/Sage.xcodeproj/project.pbxproj` | `CURRENT_PROJECT_VERSION` | Build number（每次上传递增） |
| `sage-ios/Sage/Info.plist` | `CFBundleVersion` | **同上，必须与 pbxproj 一致**（Info.plist 优先级更高） |
| `sage-ios/Sage.xcodeproj/project.pbxproj` | `MARKETING_VERSION` | 用户可见版本号（如 1.0.0） |
| `sage-ios/Sage/Info.plist` | `CFBundleShortVersionString` | **同上** |

⚠️ **关键教训**：`Info.plist` 里的值会覆盖 `project.pbxproj` 的 build settings。两处必须同步修改，否则 Archive 出来的包仍是旧版本号。

### 2. 递增 Build Number

每次上传 TestFlight 前必须递增 build number：

```bash
cd sage-ios

# 方法 1：用 PlistBuddy（推荐）
NEW_BUILD=20  # 改成你要的数字
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" Sage/Info.plist
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = $NEW_BUILD/g" Sage.xcodeproj/project.pbxproj

# 验证
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Sage/Info.plist
grep "CURRENT_PROJECT_VERSION" Sage.xcodeproj/project.pbxproj
```

### 3. 前置条件

- Xcode 已登录 Apple Developer 账号
- `sage-ios/Sage/Config/Secrets.xcconfig` 已填入 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY`
- Signing & Capabilities 配置正确（Team: YIYANG CAI, Bundle ID: com.sage.app）

### 4. 打包上传流程

```bash
# 1. 确保代码最新
cd "/Users/nakocai/Documents/Projects/项目/Sage/sage"
git pull origin main

# 2. 递增 build number（见上方）

# 3. 提交版本号变更
git add -A
git commit -m "chore(ios): bump build number to <N>"
git push origin main

# 4. 在 Xcode 中 Archive
#    - 打开 sage-ios/Sage.xcodeproj
#    - 选择 target device 为 "Any iOS Device (arm64)"
#    - Product → Archive（⌘⇧B 不行，必须 Archive）

# 5. Archive 完成后 Organizer 自动弹出
#    - 选择最新的 archive（确认版本号正确）
#    - 点击 "Distribute App"
#    - 选择 "App Store Connect" → "Upload"
#    - 等待上传完成

# 6. 等待 Apple 处理（通常 5-30 分钟）
#    - App Store Connect → TestFlight 会出现新 build
#    - 首次提交需要填写出口合规信息（选"否"即可）
```

### 5. 常见错误

| 错误 | 原因 | 解决 |
|------|------|------|
| `Redundant Binary Upload (90189)` | Build number 未递增 | 递增 Info.plist + pbxproj 的 build number |
| Archive 后版本号仍是旧的 | Info.plist 覆盖了 pbxproj | 确保两处同步 |
| `No signing certificate` | 证书过期或未安装 | Xcode → Settings → Accounts → 下载证书 |
| `Missing Compliance` | 出口合规未填 | App Store Connect → TestFlight → 点击 build → 填写 |

### 6. TestFlight 分发

上传成功后：
1. 打开 [App Store Connect](https://appstoreconnect.apple.com)
2. 我的 App → Sage → TestFlight
3. 新 build 出现后，点击进入 → 管理 → 添加测试员组
4. 测试员会收到 TestFlight 通知

---

## 二、桌面端（macOS DMG / 应用内更新）

> 完整流程见 `docs/RELEASE.md`，以下是快速参考。

### 1. 版本号管理

四处文件必须一致：

```bash
./scripts/version.sh          # 查看当前版本
./scripts/version.sh 1.5.7    # 一次性同步所有文件
```

同步的文件：`package.json`、`src-api/package.json`、`src-tauri/tauri.conf.json`、`src-tauri/Cargo.toml`

### 2. 标准发布流程（CI 自动）

```bash
# 1. 同步版本号
./scripts/version.sh 1.5.7

# 2. 提交
git add -A && git commit -m "chore: bump version to 1.5.7"

# 3. 打 tag 推送（触发 CI 自动构建 + GitHub Release）
git tag -a v1.5.7 -m "v1.5.7"
git push origin main
git push origin v1.5.7
```

CI 会自动：构建双平台（ARM + Intel）→ 签名 → 生成 DMG + updater payload → 创建 GitHub Release

### 3. 本地手动打包（调试/内测）

```bash
# 前置：编译后端
pnpm build:api
pnpm build:api:binary:mac-arm   # 或 mac-intel

# 打包
pnpm tauri:build:mac-arm        # 或 mac-intel

# 产物位置
# src-tauri/target/aarch64-apple-darwin/release/bundle/dmg/Sage_*.dmg
```

### 4. 带签名 + 公证的发布包

```bash
# 需要 Apple Developer ID 证书 + API Key
./scripts/build-signed.sh mac-arm
```

详见 `docs/RELEASE.md` 第 5-6 节。

### 5. 发布后必做

1. 更新 Railway `SAGE_UPDATER_MANIFEST_JSON` 环境变量
2. Redeploy Railway
3. 验证 `https://sage-production-28e1.up.railway.app/updater/latest.json` 返回新版本

---

## 三、注意事项

- **iOS 和桌面端版本号独立管理**：iOS 用 `CFBundleVersion`（纯数字递增），桌面端用 semver
- **不要在同一次提交里同时 bump 两端版本**：分开提交，避免混淆
- **TestFlight 每次上传 build number 必须严格递增**：不能回退，不能重复
- **桌面端 tag 命名影响 CI 行为**：`v1.5.7` 是正式版，`v1.5.7-rc.1` 是预发布
