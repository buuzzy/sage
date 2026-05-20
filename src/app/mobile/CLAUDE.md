# src/app/mobile/ — iOS 移动端 UI

移动端独立 UI 层，通过 `router.tsx` 的 `isMobile` 分流进入。共享所有业务逻辑（`src/shared/`），只有 UI 展示不同。

## 文件清单

| 文件 | 职责 |
|------|------|
| MobileApp.tsx | 根 Shell：导航状态（home/chat/settings）、useAgent 集成、drawer 控制 |
| MobileHeader.tsx | 顶栏：汉堡菜单 + 标题 + 返回按钮 |
| MobileHomePage.tsx | 首页：欢迎文字 + 首条消息输入框 + 未配置模型提示 |
| MobileChatPage.tsx | 对话页：MessageList + RunningIndicator + 底部输入栏 |
| MobileDrawer.tsx | 左侧抽屉：对话历史列表 + 新对话 + 设置入口 |
| MobileSettings.tsx | 设置页：模型配置 + 主题 + 语言 + 账号/登出 |

## 共享依赖（从 src/shared/ 导入，不要在 mobile/ 里重新实现）

- `useAgent` — Agent 通信
- `@/shared/db` — 本地数据 CRUD
- `@/shared/providers/*` — Auth, Theme, Language context
- `@/shared/db/settings` — 设置读写
- `@/app/pages/task-detail/*` — MessageList, TextMessageItem, RunningIndicator, ErrorMessage, UserMessage
- `@/components/task/PlanApproval` — 计划审批 UI
- `@/components/task/QuestionInput` — Agent 提问 UI
- `@/components/htui/ArtifactRenderer` — 图表/Artifact 渲染

## 不变量

- **不直接 fetch** — 统一走 `useAgent` hook
- **不用 Tauri API** — 所有 `@tauri-apps/*` 在 mobile 里必须 `try/catch` 或不调用
- **不写 IndexedDB 逻辑** — db/ 层已自动区分 Tauri(SQLite) vs non-Tauri(IndexedDB)
- **Safe Area** — 所有页面必须用 `pt-[var(--safe-area-top)]` 和 `pb-[var(--safe-area-bottom)]`
- **触控目标** — 按钮/链接最小 44×44pt

## 与桌面端的区别

| 方面 | 桌面端 | 移动端 |
|------|--------|--------|
| 导航 | 左侧栏常驻 | 抽屉覆盖（手动打开） |
| 对话 | 双栏（消息+右侧栏） | 全屏单栏 |
| Artifact | RightSidebar 列表 | 内联渲染（ArtifactRenderer） |
| 输入 | 侧面板内 ChatInput | 底部固定输入栏 |
| 设置 | Modal 弹窗 10 个 tab | 全屏页面 4 个 section |
| 文件浏览 | RightSidebar 文件树 | 不适用（iOS 无工作目录） |
