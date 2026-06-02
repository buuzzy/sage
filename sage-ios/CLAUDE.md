# sage-ios/ — SwiftUI 纯原生 iOS 客户端

SwiftUI + URLSession + Supabase Auth 原生客户端。

当前主线已从「桌面聊天体验移动复刻」转向「iOS 投资对讲机」：资产 / 行动横向分页，首页消费 `/mobile/dashboard` 产品 API；分身归档为设置中的功能入口。旧聊天 UI、会话侧栏与 `ChatViewModel` 已全部移出 target 并删除；旧本地会话读写收敛到 `Message.swift` 里的 `LegacySessionStore`（仅供登出清理 + cron 兼容）。仍复用 `NativeKLineChartView.swift` 等通用组件。

## 项目结构

```
sage-ios/
├── project.yml              ← xcodegen 配置
├── Sage.xcodeproj/          ← 生成的 Xcode 项目
└── Sage/
    ├── SageApp.swift         ← App 入口（主题切换、Auth 状态路由；不再持有 ChatViewModel）
    ├── Info.plist            ← URL Scheme: ai.sage.app://
    ├── DesignSystem/
    │   └── SageTheme.swift   ← Gemini 风格设计 token + 共享 SwiftUI 组件
    ├── Models/
    │   └── Message.swift     ← SSEEvent, AgentRequest, ModelConfig, PlanData, PermissionRequestData
    ├── Services/
    │   ├── APIClient.swift   ← Railway 后端通信（SSE + REST）, Bearer Token 鉴权
    │   ├── AuthService.swift ← Supabase Auth（Google OAuth + email）
    │   └── SettingsService.swift ← 本地设置持久化（8 个 Provider + ModelConfig）
    ├── ViewModels/
    │   └── InvestmentDashboardViewModel.swift ← 投资对讲机首页状态 + AvatarProfileViewModel（分身画像）
    ├── Views/
    │   ├── MainView.swift         ← 新主壳（投资对讲机入口）
    │   ├── InvestmentWalkieView.swift ← 资产 / 行动横向分页 + 全局对讲机浮层
    │   ├── Auth/LoginView.swift   ← 登录（Google OAuth）
    │   ├── Chat/
    │   │   ├── AssistantTextRow.swift   ← AI 文本 + Artifact 解析 + 操作栏
    │   │   ├── TaskGroupRow.swift       ← 可折叠工具组（对标桌面 TaskGroupComponent）
    │   │   ├── ToolItemRow.swift        ← 单个工具项 + 详情 Sheet
    │   │   ├── UserMessageRow.swift     ← 用户消息气泡
    │   │   ├── RunningIndicatorView.swift ← 橙色旋转圆弧 + 动态文字
    │   │   ├── ArtifactView.swift       ← WKWebView + ECharts 图表渲染
    │   │   ├── InputBarView.swift       ← 底部输入栏
    │   │   └── MarkdownContentView.swift ← 自定义 .sage 主题 Markdown
    │   └── Settings/
    │       ├── SettingsView.swift        ← 主设置页（9 类）+ Provider 详情
    │       └── AdvancedSettingsViews.swift ← Persona/Cron/MCP/Skills
    └── Assets.xcassets/         ← AppIcon + SageLogo
```

## 核心架构

### 投资对讲机主壳

- `InvestmentWalkieView` 是当前 iOS 主界面。
- 主界面不再使用底部 Tab；资产 / 行动通过横向滑动分页切换。
- 分身不再占主 Tab，归档到设置页中的「分身」入口。
- 资产首页通过 `APIClient.getMobileDashboard()` 读取 `/mobile/dashboard`；后端预先返回 `assetTrend`（基于持仓昨收/现价推导的一日资产变化）和按持仓聚合的 `todayPoints` 资讯卡。App 前台每 5 分钟自动刷新 dashboard/持仓行情/资讯，恢复 active 时也立即刷新。
- 左上角为设置入口，设置页保留原有模型/画像/定时任务/MCP/技能等功能，并新增「分身」；设置页右上角提供日夜间快速切换。
- 底部对讲机按钮为全局固定纯图标浮层：点击开始录音 → 再次点击结束 → `VoiceRecorder`(AVFoundation 录 16kHz mono m4a) → `APIClient.transcribe()` multipart 上传 `/mobile/transcribe`(SenseVoice) → 真实 transcript 生成想法卡。麦克风权限走 Info.plist `NSMicrophoneUsageDescription`。
- 顶部固定区域使用 `GeometryReader.safeAreaInsets.top`：背景/蒙层忽略 top safe area 画到灵动岛区域，按钮和资产/行动 Tab 仅自身按 `topInset` 下移。不要再用普通 `padding(.top)` 试图修灵动岛留白。
- 资产卡隐藏金额使用 `MaskableAmountText`：真实数字始终参与布局，隐藏时 `opacity(0)`，遮罩点 overlay 覆盖，避免点击眼睛后卡片尺寸变化。`eye/eye.slash` 也固定 frame。
- 资产卡参考富途账户卡：账户名 + 总资产/币种/眼睛 + 今日盈亏；不强调“模拟盘”。持仓摘要参考 OKX/Futu 行情列表：不放左侧 icon，不给每行白底，市场代码浅色展示，右侧保留涨跌幅胶囊。
- 语音想法卡的 symbol/intent + 任务类型由后端分类器自动判断；抽不出时留空，前端隐藏空标签（不伪造）。
- **想法分三类，「行动」Tab 按 kind 分流**（`ActionCenterView.route(for:)`）：
  - `idea_confirmation`（待确认）→ `OrderConfirmationFlowView` 两步确认下单（Step1 确认逻辑 `confirmIdeaNote` → Step2 调整草稿 `/order-draft` → 提交 `/orders` → Step3 回执）
  - `analysis_task` → `AnalysisDetailView`（`POST /notes/:id/analyze` 拉 Sage 结合持仓的结构化判断；建议下单时可一键进入两步确认）
  - `price_watch` → `WatchDetailView`（展示现价 vs 目标价 + 监控状态；「模拟触发」`POST /notes/:id/trigger` 或后台自动触发后进入两步确认）
- **行动卡流程用 `fullScreenCover` 模态呈现**（不是 NavigationLink push）：避免在流程中切到资产 Tab、再切回行动时残留上一张卡的旧流程页。`onDismiss` 统一 `reloadActions()`。
- 想法卡预览弹窗（资产页）按任务类型给出「Sage 接下来做什么」提示，只负责导航到行动 Tab，不就地确认。
- 持仓详情以 Kline 为核心，已接 `/broker/positions/:code/kline` 的富途语义 mock 数据。
- 对讲机按钮 → `/mobile/notes` → 想法卡 → `/mobile/actions` → 行动 Tab 已有产品状态闭环（已落 Supabase，按 userId 隔离）。行动 Tab 按后端 `groupKey/groupTitle/groupOrder` 分为「待处理 / 等你确认 / 进行中 / 异常 / 已完成」，已完成默认折叠；同组内保持后端顺序，不做客户端重排。
- 想法卡 / 行动中心调用（`getMobileActions` / `createIdeaNote` / `confirmIdeaNote`）必须带用户 Supabase JWT（`APIClient.userToken()` 取自 `AuthService`），不能用共享 token。
- 分身页（`AvatarProfileView` + `AvatarProfileViewModel`）读 `/persona/memory` 真实蒸馏画像，身份摘要优先；画像为空时回退到引导文案（不再硬编码假画像）。
- `CronResultPoller` 只负责定时结果到达时发本地推送；结果的 UI 落地由后端写入 `mobile_actions` → 行动 Tab 承载，poller 不再写本地会话存储。

### 迁移规则

- 新功能默认落在投资对讲机主线，不要继续扩展旧聊天壳。
- 旧 Chat 目录只允许保留被新主线复用的通用组件（当前为 `NativeKLineChartView.swift`）。
- 旧聊天 UI（消息行、输入框、工具组、artifact、sidebar）已删除；不要恢复会话列表/聊天输入框作为主入口。
- `ChatViewModel` 已删除；旧本地会话读写统一走 `LegacySessionStore`。不要为了恢复聊天主界面而重建 ViewModel。
- 设置入口位于主壳左上角，打开 `SettingsView`；分身作为设置功能入口，不再作为主导航 Tab。
- 日夜快速切换在 `SettingsView` 右上角提供，并写 `@AppStorage("sage_theme")`，由 `SageApp.applyTheme` 即时应用到 UIKit 层。
- `ErrorReportService` 已接线：投资对讲机 ViewModel 的产品级失败（dashboard/想法卡/画像加载）经 `reportMobileError()` 异步写 Supabase `error_logs`。
- `CLAUDE.md` 是当前结构说明书；每次移动主入口、数据流或模块职责后必须同步更新。
- 用户已明确要求后续逐项验收都必须装真机：即使只有 iOS 前端改动，也要 `pnpm build:ios` + `xcodebuild -destination 'id=<device-id>' build` + `xcrun devicectl device install app ...` + `xcrun devicectl device process launch ...`。若真机是 `unavailable`，先说明并用模拟器仅作临时验证，真机恢复后必须补装。

### 预留代码（Agent 流式层 / CloudSync 同步）—— 勿当冗余删除

以下代码当前**没有调用方**，但为「对讲机语音 → Agent」路线图预留，不要当死代码清掉：

- `APIClient` 的 `streamAgent / streamPlan / streamExecute / generateTitle / stopSession / respondToPermission / getTaskEvents / getTaskStatus` 及 SSE 解析实现
- 配套模型 `SSEEvent / SSEEventType / PlanData / PlanStep / PermissionRequestData / AgentRequest / ConversationMessage / ImageAttachment / Sandbox|Skills|MCPConfig / AnyCodable`
- `CloudSyncService` 的 `syncSession / syncMessage / restoreSessions`（`clearAllConversationData` 仍被登出清理使用）

复用它们前，先确认数据流（SSE 事件 → 新产品 UI 卡片），不要直接套回旧聊天分组逻辑。

### API 鉴权（双轨）

- 共享 `SAGE_API_TOKEN`（exact-match）：`/agent` `/cron` `/skills` `/mobile/dashboard` `/broker/*` 等无用户态接口
- 用户 Supabase JWT（`APIClient.userToken()` 取自 `AuthService`）：`/mobile/actions` `/mobile/notes*` `/persona/memory` 等按 user_id 隔离的接口
- 后端 `localOnlyMiddleware` 云端模式先验 `SAGE_API_TOKEN`，再 fallback 校验 JWT 并注入 `userId`

## 构建命令

```bash
cd sage-ios
xcodegen generate          # 从 project.yml 生成 .xcodeproj
xcodebuild -scheme Sage -destination 'generic/platform=iOS Simulator' build
```

## 依赖（Swift Package Manager）

- supabase-swift ^2.0.0 — Auth + Supabase 查询
- swift-markdown-ui ^2.4.0 — Markdown 渲染

## 不变量

- SAGE_API_TOKEN / SUPABASE_* 不入源码：统一放 `Config/Secrets.xcconfig`（.gitignore）→ Info.plist substitution → `APIClient.loadAPIToken()` / `SupabaseConfig` 运行时读 Bundle。禁止再 hardcode
- Bundle ID: ai.sage.app, Team: YIYANG CAI
- 最低部署目标: iOS 16.0
- 所有网络请求通过 APIClient actor（线程安全）
- 设置通过 SettingsService 单例管理（UserDefaults 持久化）
- 主题切换通过 @AppStorage("sage_theme") 全局响应

## 待实现（按优先级）

1. 后端异步化 — 任务不依赖 SSE 连接存活
2. 图片附件发送 — PhotosPicker + base64
3. 云端数据同步 — 对话/设置同步到 Supabase
4. iOS Push 通知 — Cron 任务完成推送
5. 流式光标动画 — 打字效果
