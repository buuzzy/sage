# sage-ios/ — SwiftUI 纯原生 iOS 客户端

对标 DMG 桌面端的完整功能复刻。使用 SwiftUI + URLSession SSE + Supabase Auth。

## 项目结构

```
sage-ios/
├── project.yml              ← xcodegen 配置
├── Sage.xcodeproj/          ← 生成的 Xcode 项目
└── Sage/
    ├── SageApp.swift         ← App 入口（主题切换、Auth 状态路由）
    ├── Info.plist            ← URL Scheme: ai.sage.app://
    ├── Models/
    │   └── Message.swift     ← SSEEvent, AgentRequest, ModelConfig, PlanData, PermissionRequestData
    ├── Services/
    │   ├── APIClient.swift   ← Railway 后端通信（SSE + REST）, Bearer Token 鉴权
    │   ├── AuthService.swift ← Supabase Auth（Google OAuth + email）
    │   └── SettingsService.swift ← 本地设置持久化（8 个 Provider + ModelConfig）
    ├── ViewModels/
    │   ├── ChatViewModel.swift    ← 核心状态机：DisplayGroup 分组 + SSE 事件处理
    │   └── SessionListViewModel.swift ← 会话列表 CRUD
    ├── Views/
    │   ├── MainView.swift         ← 主布局（侧边栏 + 对话 + 输入栏）
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
    │   ├── Sessions/SidebarView.swift   ← 日期分组 + 右滑删除 + 长按重命名
    │   └── Settings/
    │       ├── SettingsView.swift        ← 主设置页（9 类）+ Provider 详情
    │       └── AdvancedSettingsViews.swift ← Persona/Cron/MCP/Skills
    └── Assets.xcassets/         ← AppIcon + SageLogo
```

## 核心架构

### DisplayGroup 消息分组（对标桌面端 TaskMessageGroup）

```swift
enum DisplayGroup: Identifiable {
    case userMessage(id: UUID, content: String)
    case taskGroup(id: UUID, title: String, tools: [ToolCallItem], isComplete: Bool)
    case assistantText(id: UUID, content: String, isStreaming: Bool)
    case plan(id: UUID, data: PlanData)
    case error(id: UUID, message: String)
}
```

状态机逻辑：
- 收到 `text` → 追加到当前 assistantText
- 收到 `tool_use` → 如果有 pendingText，创建 TaskGroup（标题=pendingText）
- 收到 `tool_result` → 更新 TaskGroup 中对应工具状态
- 收到下一个 `text` → 关闭当前 TaskGroup，开始新 assistantText

### SSE 事件类型

| type | iOS 处理 |
|------|---------|
| text / direct_answer | 追加到 assistantText |
| tool_use | 创建或追加到 TaskGroup |
| tool_result | 更新工具完成状态 |
| plan | 显示 PlanApprovalRow |
| permission_request | 弹出系统 Alert |
| session | 保存 backendSessionId |
| error | 显示 ErrorRow |
| done / result | 流结束 |

### API 鉴权

所有请求带 `Authorization: Bearer <SAGE_API_TOKEN>`。
后端 `localOnlyMiddleware` 在云端模式下验证此 token（或 Supabase JWT）。

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

- SAGE_API_TOKEN 不推送到公开仓库（临时硬编码用于开发）
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
