# ios/ — Capacitor iOS 项目

Capacitor 8 生成的 iOS 原生壳，WebView 加载 `dist/` 中的前端构建产物。

## 目录结构

```
ios/
├── App/
│   ├── App/
│   │   ├── Info.plist          ← Bundle 配置（URL Scheme 等）
│   │   ├── App.entitlements    ← 应用权限
│   │   ├── public/             ← pnpm build:ios 同步的 web 资源（gitignore）
│   │   └── capacitor.config.json ← 运行时 Capacitor 配置
│   ├── App.xcodeproj/          ← Xcode 项目文件
│   └── Podfile                 ← CocoaPods（如有）
├── CapApp-SPM/
│   └── Package.swift           ← Capacitor 插件 Swift Package 清单
```

## 构建流程

```bash
pnpm build:ios          # 1. vite build --mode ios  2. npx cap sync ios
pnpm open:ios           # 打开 Xcode 项目
# Xcode 里 ▶️ 运行到模拟器或真机
```

## 关键配置

| 项 | 值 | 文件 |
|----|-----|------|
| App ID | `ai.sage.app` | capacitor.config.ts |
| URL Scheme | `ai.sage.app://` | Info.plist → CFBundleURLTypes |
| API 地址 | `https://sage-production-28e1.up.railway.app` | .env.ios → VITE_API_URL |
| iOS Scheme | `https` | capacitor.config.ts → iosScheme |

## 已安装 Capacitor 插件

| 插件 | 用途 |
|------|------|
| @capacitor/app | 监听 appUrlOpen（OAuth 回调） |
| @capacitor/browser | 打开 OAuth 浏览器 |

## OAuth 登录流程

1. 前端调 `signInWithProvider('google')` → `skipBrowserRedirect: true`
2. 用 `@capacitor/browser` 打开 Supabase OAuth URL
3. 用户完成登录 → Supabase redirect 到 `ai.sage.app://auth/callback?code=...`
4. iOS 系统把 URL 交给 App → `@capacitor/app` 触发 `appUrlOpen`
5. 前端 `Browser.close()` 关闭浏览器 + `exchangeCodeForSession(code)` 完成登录

## 注意事项

- **不要手动编辑 `ios/App/App/public/`** — 它由 `cap sync` 自动生成
- **证书/签名** — 在 Xcode → Signing & Capabilities 里管理
- **TestFlight** — Archive → Distribute → Upload（需要有效 App Store Connect 账号）
- **模拟器调试** — Safari → Develop → Simulator 可以 inspect WebView
- **真机调试** — Xcode Console 看 WebView 日志 + Safari Web Inspector
