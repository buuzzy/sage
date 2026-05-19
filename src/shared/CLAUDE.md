# src/shared/ — 前端共享模块

跨页面/组件复用的核心逻辑。hooks、数据库、云同步、工具函数、Context Providers。

## 模块边界

| 目录 | 职责 | 谁调用 | 它依赖谁 |
|------|------|--------|---------|
| hooks/ | Agent 通信 + Provider 配置 + 频道同步 | pages, components | db, sync, lib, config |
| db/ | 本地 SQLite CRUD（tasks, messages, sessions, files, settings） | hooks, sync, pages | - |
| sync/ | 云端同步队列（Supabase） | hooks（写入时触发） | db, lib/supabase |
| lib/ | 工具函数（路径、格式化、token 估算、artifact 解析） | 任何模块 | - |
| providers/ | React Context（auth, theme, language, antd-theme, update） | App.tsx 包裹 | lib/supabase |
| types/ | TypeScript 类型定义（artifact, persona-memory） | 任何模块 | - |
| config/ | artifactMapping（URL→组件类型映射） | htui/ArtifactRenderer | - |

## hooks/ 文件清单

| 文件 | 职责 | 稳定度 |
|------|------|--------|
| useAgent.ts | Agent 请求路由核心（~3000 行）。策略分类 + SSE stream + 标题生成 + 错误分类 | ⚠️ 核心 |
| useProviders.ts | 读取/切换模型 Provider 配置 | 🔧 |
| useChannelSync.ts | 渠道（微信/飞书）消息同步 | 🔧 |
| useVitePreview.ts | Vite 预览模式检测 | 🔒 |

## useAgent.ts 核心概念（修改前必读）

1. **classifyAgentExecutionStrategy()** — 7 种执行路由：
   - `image` / `openai_provider` / `conversation` / `memory_recall` / `simple_lookup` → direct
   - `multi_target` / `complex_task` → plan
2. **SSE stream 事件类型**: `text` / `tool` / `plan` / `error` / `done` / `direct_answer`
3. **标题生成**: 异步 POST `/agent/title`，结果绑定 taskId，过滤低质量标题
4. **错误分类器**: 8 类结构化错误 → `ClassifiedAgentError`
5. **背景任务**: `addBackgroundTask()` / `removeBackgroundTask()` / `subscribeToBackgroundTasks()`

## db/ 文件清单

| 文件 | 职责 |
|------|------|
| database.ts | SQLite 连接初始化 + user binding |
| index.ts | CRUD 函数导出（createTask, createMessage, getMessagesByTaskId...） |
| settings.ts | 本地设置读写（getSettings / updateSettings） |
| types.ts | DB 实体类型定义 |

## sync/ 文件清单

| 文件 | 职责 |
|------|------|
| sync-queue.ts | 通用同步队列（fire-and-forget, 重试 + 去重） |
| messages-sync.ts | 消息同步到 Supabase |
| session-sync.ts / session-sync-provider.tsx | 会话元数据同步 |
| settings-sync.ts / settings-sync-provider.tsx | 用户设置同步 |
| profile-sync.ts / profile-provider.tsx | 用户档案同步 |
| behavior-sync.ts | 用户行为日志同步 |
| error-sync.ts | 错误日志上报 |
| cloud-restore.ts | 云端数据恢复（拉取 sessions/tasks/messages/files） |
| cloud-cleanup.ts | 云端数据清理 |
| sync-status.ts | 同步状态管理 |
| session-dirty-queue.ts | session 脏标记队列 |

## lib/ 关键文件

| 文件 | 职责 |
|------|------|
| supabase.ts | Supabase client 初始化（isTauri 分叉 detectSessionInUrl/flowType） |
| attachments.ts | 附件存储/加载 |
| background-tasks.ts | 背景任务生命周期管理 |
| context-usage.ts | 上下文 token 估算（前端侧） |
| artifactParser.ts | 从消息文本解析 artifact blocks |
| toolMetadataExtractor.ts | 从 tool_use 消息提取元数据 |
| paths.ts / user-scoped-paths.ts | 文件路径工具 |

## 不变量

- `useAgent` 是唯一的 Agent 通信入口，不在其他地方 fetch `/agent`
- db/ CRUD 函数必须幂等（支持 upsert 语义）
- sync/ 入队后不阻塞主流程（fire-and-forget）
- providers/ 的 Context 不能有副作用（pure context value）
- 新增 sync 模块必须注册到 `sync/index.ts`
