# src/ — React 前端

桌面端 + iOS 端共享的 React 19 SPA。Vite 7 构建，TailwindCSS 4 样式，无全局状态库。

## 子目录职责

| 目录 | 职责 | 稳定度 |
|------|------|--------|
| app/pages/ | 5 个页面组件 | 🔧 可修改 |
| app/pages/task-detail/ | TaskDetail 子组件（MessageList, ErrorMessage, AgentActionBar 等） | 🔧 |
| components/htui/ | 14 个金融可视化组件 | 详见 htui/CLAUDE.md |
| components/ui/ | shadcn/ui 基础组件（button, dialog, sheet, tooltip...） | 🔒 不改接口 |
| components/task/ | 任务渲染（PlanApproval, ToolExecutionItem, QuestionInput） | 🔧 |
| components/settings/ | 设置面板（10 个 tab） | 🔧 |
| components/layout/ | 布局（左侧栏, 右侧栏, 头像状态徽章） | 🔧 |
| components/common/ | 通用小组件 | 🔧 |
| components/home/ | 首页子组件 | 🔧 |
| shared/ | hooks, db, sync, lib, providers, types | 详见 shared/CLAUDE.md |
| config/ | API 地址 + i18n 多语言 | 🔒 |

## 页面路由（app/router.tsx）

| 路径 | 页面 | 说明 |
|------|------|------|
| `/` | Home.tsx | 新对话首页 |
| `/task/:id` | TaskDetail.tsx | 会话详情（消息 + artifact 渲染） |
| `/library` | Library.tsx | 历史会话列表 |
| `/login` | Login.tsx | 登录 |
| `/setup` | Setup.tsx | 初始化设置 |

## 状态管理约定

- **无全局状态库**（不用 Redux/Zustand/Jotai）
- 页面级状态用 `useState` / `useRef`
- 跨组件共享用 Context Provider（auth, theme, language, update, sidebar）
- Agent 通信统一走 `shared/hooks/useAgent.ts`，不在其他地方直接 fetch

## 平台分叉逻辑

```typescript
// src/config/index.ts
const isTauri = '__TAURI_INTERNALS__' in window;
export const API_BASE_URL = isTauri
  ? 'http://127.0.0.1:2026'        // 桌面 sidecar
  : import.meta.env.VITE_API_URL;   // iOS/Web → Railway
```

- 桌面：OAuth deep-link (`sage://auth/callback`)
- iOS：邮箱/密码登录
- sidecar 就绪状态：`useSidecarReadiness()` 后台轮询 + 头像绿/红点

## 不变量

- 不引入全局状态库
- 组件不直接调 `fetch`，统一走 `useAgent` hook
- 组件不直接读 `import.meta.env`，走 `config/index.ts`
- 新增页面必须注册到 `app/router.tsx`
- 新增 Context Provider 必须包裹在 `main.tsx` 或 `App.tsx`
