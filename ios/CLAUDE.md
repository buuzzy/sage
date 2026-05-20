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

---

## Phase 4: Chart & Artifact Optimization (In Progress)

**Status**: 🔄 Testing Ready (2026-05-20)  
**Build**: ✅ Successfully builds, no TypeScript errors  
**Key Commits**: 
- `dd25cc4` - Security fix: Railway token handling with Supabase JWT fallback
- `7b1dff7` - MobileArtifactPreview bottom-sheet component
- `f257c55` - Fix cn utility import in MobileArtifactPreview

### What's New

1. **Security**: Removed hardcoded Railway API token
   - Now uses Supabase JWT when available (user-scoped auth)
   - Falls back to `VITE_RAILWAY_API_TOKEN` env variable for testing
   - Prevents token exposure in public GitHub repository

2. **Mobile Artifact Preview**: Created `MobileArtifactPreview.tsx`
   - Bottom-sheet style modal (not centered overlay)
   - Swipe gestures to adjust height (peek/mid/full)
   - Touch-friendly download/share buttons
   - Infrastructure ready for future integration

3. **Mobile UI Improvements** (from previous session)
   - Fixed iOS textarea styling (WebKit appearance)
   - Added MobileErrorBoundary for better error debugging
   - Capacitor scheme changed from https to capacitor:// with allowNavigation

### Phase 4 Acceptance Criteria

**PASS when ALL are true**:
- ✅ 12/14 charts render on iPhone 15 without overflow
- ✅ Touch interactions work (tap for tooltips, scroll for time-series)
- ✅ Console clean of resize/rendering errors
- ✅ Memory < 100MB peak, FPS >= 55
- ✅ Data accuracy verified

### 14 Chart Types to Test

| # | Type | Component | Status |
|---|------|-----------|--------|
| 1 | LineChart | LineChart.tsx | ⏳ Testing |
| 2 | BarChart | BarChart.tsx | ⏳ Testing |
| 3 | Candlestick | KLineChart.tsx (TradingView) | ⏳ Testing |
| 4 | DataTable | DataTable.tsx | ⏳ Testing |
| 5 | Scatter | ScatterChart.tsx | ⏳ Testing |
| 6 | Heatmap | SectorHeatmap.tsx | ⏳ Testing |
| 7 | QuoteCard | QuoteCard.tsx | ⏳ Testing |
| 8 | StockSnapshot | StockSnapshot.tsx | ⏳ Testing |
| 9 | NewsCard | NewsCard.tsx | ⏳ Testing |
| 10 | ResearchConsensus | ResearchConsensus.tsx | ⏳ Testing |
| 11 | FinanceBreakfast | FinanceBreakfast.tsx | ⏳ Testing |
| 12 | FinancialHealth | FinancialHealth.tsx | ⏳ Testing |
| 13 | AIHotNews | AIHotNews.tsx | ⏳ Testing |
| 14 | NewsFeed | NewsFeed.tsx | ⏳ Testing |

### Testing Workflow

```bash
# 1. Build latest code
pnpm build:ios

# 2. Open Xcode
pnpm open:ios

# 3. Select iPhone 15 Pro Simulator
# Product > Destination > iPhone 15 Pro Simulator

# 4. Run (⌘R)

# 5. Monitor console
# Safari > Develop > Simulator > App WebView
```

### Next Steps

1. **Immediate (Today)**: Execute Phase 4 testing on simulator
   - Verify all 14 chart types render
   - Check console for errors
   - Profile memory and frame rate
   - Document results in test template

2. **Short-term (Phase 5)**: API & Auth Testing
   - Verify Supabase JWT token handling
   - Test error scenarios (401, timeout, 500)
   - Profile token refresh cycles

3. **Medium-term (Phase 6)**: Stability & Performance
   - Long session stress test (100+ messages)
   - Memory leak detection
   - Accessibility audit (font sizes, contrast)

### Development Resources

- **Phase 4 Testing Plan**: `docs/ios/PHASE_4_TESTING_PLAN.md` (detailed matrix, 14 queries)
- **Phase 4 Execution Guide**: `docs/ios/PHASE_4_EXECUTION_GUIDE.md` (step-by-step with results template)
- **Current Status Report**: `docs/ios/CURRENT_STATUS_2026_05_20.md` (full status overview)
- **Mobile Component Docs**: `src/app/mobile/CLAUDE.md` (mobile UI layer)
- **Shared Module Docs**: `src/shared/CLAUDE.md` (business logic layer)
- **HTUI Chart Docs**: `src/components/htui/CLAUDE.md` (14 chart components)

### Known Issues

1. **ECharts Text Overflow (320px viewport)**
   - Charts auto-reduce label font size on narrow screens
   - Workaround: Already implemented in chart components

2. **KLineChart Tooltip Off-Screen**
   - TradingView Lightweight Charts may position tooltip outside viewport
   - Workaround: Components handle viewport bounds (in progress)

3. **DataTable Column Overflow**
   - Wide tables may not scroll properly
   - Workaround: Auto-set column widths based on viewport

### Performance Targets

| Metric | Target | Status |
|--------|--------|--------|
| Idle memory | <80MB | ✅ Expected |
| Peak memory | <100MB | ⏳ Testing |
| FPS (rendering) | 55-60fps | ⏳ Testing |
| Render time | 200-500ms | ⏳ Testing |
| No memory leaks | - | ⏳ Testing |

---

**Last Updated**: 2026-05-20  
**Phase 4 Progress**: Ready for simulator testing
