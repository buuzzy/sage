# src-api/ — Hono HTTP 后端

独立 pnpm workspace 包（`"sage-api"`）。桌面端作为 Tauri sidecar 运行在 localhost:2026，Railway 作为云端服务运行。

## 架构分层

```
index.ts (Hono server 入口)
  → app/api/        HTTP 路由层（薄，不含业务逻辑）
  → app/middleware/  中间件（CORS, local-only 鉴权）
  → shared/services/ 业务服务层（组装 agent/chat/preview 逻辑）
  → core/           抽象接口层（agent/channel/sandbox 的 interface + registry）
  → extensions/     具体实现层（codeany adapter, feishu channel, sandbox providers）
  → shared/         基础设施（context, memory, provider, skills, supabase, utils）
  → jobs/           后台 cron 任务
  → config/         常量 + 配置加载
```

## API 路由一览（app/api/）

| 路由 | 文件 | 方法 | 说明 |
|------|------|------|------|
| /agent | agent.ts | POST | Agent 直接执行（SSE stream） |
| /agent/plan | agent.ts | POST | Agent 规划阶段（SSE stream） |
| /agent/execute | agent.ts | POST | 执行已批准计划（SSE stream） |
| /agent/title | agent.ts | POST | 异步生成对话标题 |
| /v1/chat/completions | completions.ts | POST | OpenAI 兼容端点（WeClaw 对接） |
| /mcp/memory | mcp-memory.ts | POST | MCP search_memory 工具 |
| /persona/memory | persona.ts | GET | 当前用户 persona_memory 读取 |
| /updater/latest.json | updater.ts | GET | Tauri updater manifest |
| /channels | channels.ts | GET/POST | 渠道 CRUD |
| /feishu/event | feishu.ts | POST | 飞书事件回调 |
| /health | health.ts | GET | 健康检查 |
| /mobile/dashboard | mobile.ts | GET | iOS 投资对讲机资产首页产品 API |
| /mobile/actions | mobile.ts | GET | iOS 行动中心产品状态（按 userId 隔离，需 JWT） |
| /mobile/notes | mobile.ts | POST | 创建想法卡：分类任务类型并生成对应行动项（落 Supabase，需 JWT） |
| /mobile/notes/:id | mobile.ts | GET | 想法卡详情（任务类型/条件/监控状态/分析缓存 + 条件单现价，需 JWT） |
| /mobile/notes/:id/confirm | mobile.ts | POST | 确认想法卡（按 userId 隔离，需 JWT） |
| /mobile/notes/:id/analyze | mobile.ts | POST | 分析任务：惰性生成并缓存 Sage 结构化判断（需 JWT） |
| /mobile/notes/:id/trigger | mobile.ts | POST | 手动模拟触发条件单 → 转待确认下单卡（demo 用，需 JWT） |
| /mobile/transcribe | mobile.ts | POST | 对讲机语音转文字（multipart 音频 → SenseVoice，需 JWT） |
| /mobile/notes/:id/order-draft | mobile.ts | GET | 两步确认 Step2：按想法卡生成模拟盘订单草稿（需 JWT） |
| /mobile/orders | mobile.ts | POST | 两步确认 Step3：提交模拟盘订单 + 记成交行动卡（需 JWT） |
| /broker/accounts | broker.ts | GET | Broker 账户列表（当前 mock 富途模拟盘） |
| /broker/positions | broker.ts | GET | Broker 持仓列表（当前 mock 富途模拟盘） |
| /broker/positions/:code/kline | broker.ts | GET | 持仓 Kline 数据（富途语义 mock） |
| /broker/orders/simulated | broker.ts | POST | 提交模拟盘订单（富途语义 mock） |
| /skills | skills.ts | GET/POST | 技能管理 |
| /providers | providers.ts | GET/POST | 模型 provider 配置（旧，本地模式） |
| /user-providers | user-providers.ts | GET/POST/PATCH/DELETE | 云端 provider CRUD + Vault 加密 |
| /user-providers/:id/default | user-providers.ts | POST | 设为默认 provider |
| /user-providers/:id/test | user-providers.ts | POST | 服务端代测连通性 |
| /cron | cron.ts | GET/POST/DELETE | 定时任务管理 |
| /files | files.ts | GET/POST | 文件管理 + GitHub skill 导入 |
| /sandbox | sandbox.ts | POST | 沙箱执行 |
| /preview | preview.ts | GET | Vite 预览 |
| /internal/distill | internal-distill.ts | POST | 手动触发蒸馏 |
| /wechat | wechat.ts | POST | 微信消息回调 |
| /mcp | mcp.ts | POST | 通用 MCP 端点 |

## 子目录详细文档

| 目录 | 详见 |
|------|------|
| extensions/agent/codeany/ | `extensions/agent/codeany/CLAUDE.md` |
| shared/ | `shared/CLAUDE.md` |

## 构建命令

```bash
pnpm dev:api                    # tsx --watch 开发模式
pnpm build                      # tsc 编译 → dist/
pnpm bundle                     # esbuild 打包 → dist/bundle.cjs
pnpm build:binary:mac-arm       # pkg 生成独立二进制
pnpm build:binary:mac-intel     # Intel macOS 二进制
```

## 中间件链路

```
请求 → CORS → local-only（SAGE_API_TOKEN 或 loopback 检测） → 路由 handler
```

## 不变量

- 所有路由必须经过 local-only 中间件
- SSE stream 格式：`data: {type, ...}\n\n`，最后必须有 `{type: "done"}`
- 路由层不写业务逻辑，委托给 `shared/services/`
- 新增路由必须注册到 `app/api/index.ts`
- 不在后端硬编码 API Key，全走环境变量
- 桌面端和 Railway 共用同一套代码，通过环境变量区分行为
- iOS 投资对讲机主界面消费 `/mobile/*` 产品 API；不要让 iOS 直接拼接底层 Agent / Skills / Cron / Persona 接口
- `/mobile/notes` / `/mobile/actions` 已落 Supabase（`idea_notes` / `mobile_actions` 表），按 `user_id` RLS 隔离：iOS 调用必须带用户 Supabase JWT（不是共享 `SAGE_API_TOKEN`）。`localOnlyMiddleware` 校验 JWT 后把 `userId` 注入 `c.get('userId')`，路由用 `createUserScopedSupabase(jwt)` 走 RLS
- 系统默认行动卡（如富途连接提示）在 `mobile-actions.ts` 代码层生成，不入库，保证新用户也可见；只有动态条目（想法确认、定时任务结果）才落表
- `/mobile/transcribe`：iOS push-to-talk 录音（m4a multipart）→ `shared/services/transcribe.ts` 调 SiliconFlow `FunAudioLLM/SenseVoiceSmall` → 返回 `{ text }`。Key 走 Railway env `SILICONFLOW_API_KEY`，绝不下发客户端；需用户 JWT 防止共享 token 滥用 ASR 配额
- 两步确认下单：`order-draft.ts`（经 `broker.resolveInstrument` 解析标的身份 + 持仓匹配 + `broker.getQuote` 取价 + 意图→方向，生成富途语义订单草稿）→ `GET /mobile/notes/:id/order-draft`；`POST /mobile/orders` 经 `getBrokerAdapter().submitSimulatedOrder` 提交，再 `recordOrderResult` 写成交行动卡并把想法卡标「已下单」。当前 broker 为 mock，接富途模拟盘只替换 adapter
- **想法不等于「立刻下单」**：`createIdeaNote` 先调 `idea-intent.ts` 的 `classifyIdea`（SiliconFlow Qwen + 确定性正则兜底，复用 `SILICONFLOW_API_KEY`）把 transcript 分成三类任务，写 `idea_notes.task_type` 并生成对应 kind 的行动卡：
  - `order`（「现在买 100 股」）→ `idea_confirmation` 卡 → 两步确认下单
  - `analysis`（「宁德时代要不要止盈」）→ `analysis_task` 卡 → `POST /notes/:id/analyze` 惰性调 `idea-analysis.ts`（LLM 结合**真实持仓上下文**：成本/现价/浮盈）出结构化判断并缓存 `idea_notes.analysis`；建议下单时可一键进入两步确认
  - `conditional`（「比亚迪回调到 230 加仓」）→ 解析 `condition{op,price}` 存表，`price_watch` 卡（监控中）；Railway 后台 `price-watch.ts` 的 `sweepPriceWatches` 每分钟扫描活跃监控、`broker.getQuote` 比对阈值，命中调 `triggerWatch` 转「待确认」下单卡。`POST /notes/:id/trigger` 供 demo 手动模拟触发
- 标的身份 + 实时报价统一下沉到 `shared/broker` adapter（`resolveInstrument` / `getQuote`），`order-draft` / `idea-analysis` / `price-watch` 共用，避免标的字典散落多处。接富途后只换 adapter
- 条件单监控 cron 在 `jobs/scheduler.ts` 注册，只依赖 `SAGE_ENABLE_BACKGROUND_JOBS` + service-role（不需 `MIMO_API_KEY`），独立于 persona 蒸馏
- Cron 执行成功后除写 `sessions`/`messages` 外，还通过 `appendCronAction()`（service-role）插一条 `mobile_actions`，让定时结果出现在 iOS「行动」Tab
- `/mobile/dashboard` 与 `/broker/*` 当前是富途 OpenAPI 语义全局 mock（无 userId）；后续接富途模拟盘时优先替换 `shared/broker` adapter，并补 userId/account 维度，不改 iOS contract
