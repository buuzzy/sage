# Sage — TODO & Feature Roadmap

> 本文件是项目唯一权威 TODO。只保留真实待解决项、明确产品规划和暂不做事项；已完成内容通过 git commit / release 记录追溯。
> 最后更新：2026-05-16（v1.4.11，已按真实代码审查校准）

---

## 当前决策

- 不再单独维护 MiniMax 相关分支或特殊兜底。模型问题通过通用协议适配、错误可见性、工具输出后处理来解决。
- 暂不发布 Windows 版本。
- 桌面端维护 macOS Apple Silicon 与 macOS Intel。
- SDK 不是 Sage 产品能力的归属地；工具输出拦截、artifact 生成、tool output 压缩等能力最终应属于 Sage adapter / wrapper。
- `session-sync` 当前只同步 session 元数据；`message_count` 语义暂不作为线上 bug 处理，等云端会话 UI 使用前统一。

---

## P0 / P1 — 已收口

2026-05-16 已完成 P0/P1 的最小可交付闭环：

- `SDK patch 去产品化`：`PostToolUse` hook 组装已迁入 `src-api/src/extensions/agent/codeany/tool-output-interceptor.ts`。westock artifact、summary、artifact queue 等 Sage 产品逻辑保留在 adapter；`pnpm patch` 只短期承载 SDK 通用 `modifiedOutput` 传输能力和 provider/tool 兼容 shim。
- `macOS Intel release manifest 闭环`：`updater.ts`、`docs/RELEASE.md`、`CLAUDE.md` 已支持 `darwin-aarch64` + `darwin-x86_64` 双平台 manifest/env/校验流程。
- `复杂多标的查询体验` + `意图识别驱动的执行策略分层`：`useAgent.ts` 已引入统一执行策略分类器，识别多标的 / 图片 / OpenAI-compatible provider / 低风险直跑 / 显式 plan，并为多标的直跑路径追加批量聚合约束。
- `结构化错误分类器`：Agent fetch 错误已分类为 `auth`、`rate_limit`、`timeout`、`network`、`context_overflow`、`model_empty_response`、`server_error`、`tool_loop_limit`、`unknown`，并写入错误消息 metadata。
- `Provider token usage 与费用追踪`：任务完成时记录 SDK result 的 `cost_usd` / `duration_ms` 快照到本地 `tasks.provider_usage`，并同步到云端 `tasks.provider_usage`。逐 provider 的 input/output token 账本仍取决于 SDK/provider 是否暴露 usage 事件，不再作为 P1 阻塞项。
- `数据导入功能补齐`：`DataSettings` 已支持导入 `sessions`、`tasks`、`messages`、`files`、`settings`，保留导出 ID，导入时重写 `user_id`，并避免走普通 `createMessage()` 的云同步副作用。
- `完整消息跨设备恢复`：新增云端恢复入口，拉取 `sessions` / `tasks` / `messages` / `files` 并复用本地导入路径；后续新建 `tasks` / `files` 也会进入云端同步队列。
- `Skills 从 GitHub 导入`：前端入口已恢复，后端 `/files/import-skill` 支持公开 GitHub repo/subdir 导入，校验目标路径、`SKILL.md`、文件数量和体积上限。

**仍需 release / 环境验证**：

- 下次 release 验证 GitHub assets 和 Railway manifest 都含 `darwin-aarch64` / `darwin-x86_64`。
- 在 Intel Mac 上验证 DMG 安装和应用内更新。
- 在已应用 Supabase migration 的环境验证云端 `tasks.provider_usage`、`tasks` / `files` upsert 与云端恢复。
- 用真实公开 GitHub skill repo 验证 `/files/import-skill`。

---

## P2 — 产品规划

### OKX 全链路交易集成

**真实现状**：仓库内未发现 OKX skill、API 或前端入口，属于新产品能力。

| 阶段 | Skill | 说明 |
|---|---|---|
| 第一阶段 | `okx-market` | 行情与数据，只读 |
| 第二阶段 | `okx-account` | 账户与持仓，只读，需要 API Key |
| 第三阶段 | `okx-trade` | 下单执行，必须有确认卡片 |

核心原则：AI 只负责计算和提案，执行权始终在用户手中。

---

### 会话搜索

**真实现状**：

- 本地 SQLite 尚未实现 FTS5 / trigram 的会话搜索。
- 云端已有 Pgroonga / RPC 记忆搜索链路，但那是记忆召回，不是本地会话列表搜索。

**目标**：

- 本地 SQLite 对 `messages.content` 建全文索引。
- 支持按历史问题、股票名、文件名、关键词搜索会话。

---

### iOS Phase 1 UI 适配

**真实现状**：

- Phase 0 可登录和进入主界面。
- 共享 `src/` 仍主要是桌面布局，未完成移动端专项 UI。

**待做**：

- 侧边栏改为移动端导航。
- Safe Area 适配。
- 虚拟键盘弹出时输入框位置修正。
- 图表触摸交互：长按 tooltip、缩放、滑动。
- 移动端会话列表与任务详情布局。

---

### iOS OAuth 与数据层适配

**真实现状**：

- `auth-provider.tsx` 有桌面 / 非桌面分叉。
- 邮箱密码登录可用；OAuth 在 iOS deep-link 场景未闭环。
- 非 Tauri 有 IndexedDB 分支，但文件系统、附件、桌面本地能力还未完整等价。

**待做**：

- GitHub / Google OAuth deep-link 回调。
- 文件系统 API 替换。
- 桌面本地 SQLite 能力在 iOS 的等价方案或降级策略。

---

### 隐私政策与 TOS

**真实现状**：

- 仓库已有 `PRIVACY.md`。
- 应用内页面、TOS、App Store Connect 隐私声明、数据删除 / 账号注销说明未完整实现。

---

### 启动加载 UX

**真实现状**：

- `main.tsx` 已有 settings 初始化、error queue、provider 挂载等基础流程。
- 没有品牌化启动动画、分阶段启动提示、sidecar / DB / auth 状态可视化。

---

## P3 — 探索项

### 记忆冻结快照

**方案**：会话开始时冻结 system prompt / persona / recent threads 快照，会话内保持稳定。

**收益**：提升 prompt prefix cache 命中率，减少延迟和成本。

---

### 上下文压缩保护头尾

**方案**：压缩时保护首轮上下文和最近 N 轮，只压缩中间内容。

**收益**：长对话中减少“忘记当前讨论重点”的概率。

---

### 技能渐进式披露

**真实现状**：

- `predictor.ts` 当前更接近 full-set 注册，完整 `SKILL.md` 仍会进入上下文。
- “已有 intent predictor，每次只注册约 5 个技能”的旧说法已不准确。

**方案**：

- system prompt 只注入技能摘要。
- agent 需要时通过 tool call 加载完整 `SKILL.md`。

**收益**：减少系统提示 token，降低上下文压力。

---

## 语义待定但暂不修

### 云同步 session `message_count`

**真实现状**：

- `session-sync` 同步 session 元数据。
- `message_count` 当前统计 `user + text` 可见气泡数。
- 当前云端 session UI 尚未正式依赖该字段展示关键业务含义。

**决策**：当前不作为 bug 立即修改。

**待云端 session UI 使用前确认**：

- 如果展示“对话轮次”，统计 `user`。
- 如果展示“消息数”，统计 `user + text`，但过滤 artifact-only text。
- 文档和字段命名需要与最终语义一致。

---

## 暂不做

- Windows 版本发布。
- 单独为 MiniMax 做模型专属路由、prompt 或硬编码兜底。
- 维护 SDK fork，或为 Sage 专属 artifact 能力向 SDK 上游提 PR。
