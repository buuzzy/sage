# src-api/src/shared/ — 后端共享子系统

被路由层、Agent 适配器、jobs 等多处依赖的基础设施模块。

## 子模块依赖关系

```
utils/        ← 被所有模块依赖（日志、路径、URL）
supabase/     ← 被 memory, sync, jobs 依赖
provider/     ← 被所有需要 LLM 的模块依赖（manager 单例）
skills/       ← 被 agent adapter 依赖
memory/       ← 被 codeany adapter + mcp-memory 依赖
context/      ← 被 agent service 依赖
cron/         ← 被 jobs/ 和 app/api/cron.ts 依赖
services/     ← 被 app/api/ 路由层依赖
init/         ← 启动时一次性运行（迁移、首次初始化）
llm/          ← MiMo 蒸馏专用 client
mcp/          ← MCP server 配置加载
types/        ← 类型定义
```

## 模块清单

| 目录 | 文件 | 职责 | 稳定度 |
|------|------|------|--------|
| context/ | assembler.ts, compaction.ts, compaction-store.ts, session-store.ts | 对话上下文组装 + 压缩 | 详见 context/CLAUDE.md |
| memory/ | provider.ts, supabase-rpc-provider.ts, index.ts | 四层记忆系统 | 详见 memory/CLAUDE.md |
| provider/ | manager.ts, registry.ts, loader.ts, types.ts | 模型 Provider 管理（多模型切换） | 🔒 接口稳定 |
| skills/ | loader.ts, register.ts, predictor.ts, config.ts, index.ts | 技能加载、注册、意图预测 | 🔧 |
| supabase/ | client.ts | Supabase client（双模式：service-role / user-JWT） | 🔒 |
| cron/ | scheduler.ts, store.ts, types.ts | Cron 任务调度（用户定时任务） | 🔧 |
| services/ | agent.ts, chat.ts, channel-store.ts, preview.ts | 业务服务层 | 🔧 |
| init/ | first-run.ts, migration.ts, sandbox-migration.ts | 启动初始化 + 数据迁移 | 🔧 |
| llm/ | mimo.ts | MiMo API client（蒸馏专用） | 🔒 |
| mcp/ | loader.ts | MCP 配置加载（~/.sage/mcp.json + ~/.claude/settings.json） | 🔒 |
| utils/ | logger.ts, paths.ts, url.ts, config.ts, trace-logger.ts, sandbox.ts | 通用工具 | 🔒 |
| types/ | agent.ts, persona-memory.ts | 类型定义 | 🔒 |

## provider/ 核心概念

- `ProviderManager` 是全局单例（`getProviderManager()`）
- 支持多 provider 类型：Anthropic, OpenAI-compatible, MiniMax
- 运行时可切换（前端设置面板 → POST /providers → manager.setConfig()）
- 默认模型：`claude-sonnet-4-20250514`

## skills/ 核心概念

- 加载路径：内置 `resources/skills/` → 用户 `~/.sage/skills/`
- `predictor.ts`：当前接近 full-set 注册，完整 SKILL.md 进入上下文
- `register.ts`：将技能注册为 MCP tools 供 SDK 调用

## services/ 核心概念

- `agent.ts`：`getAgent()` 获取/创建全局 Agent 实例 + plan store
- `chat.ts`：标题生成（`generateTitle()`）
- `channel-store.ts`：渠道配置持久化

## 不变量

- `supabase/client.ts` 必须支持双模式（service-role vs user-JWT）
- `provider/manager.ts` 的 `getProviderManager()` 是全局单例，不要创建第二个
- skills 加载顺序：内置 resources → 用户 ~/.sage/skills/（用户可覆盖内置）
- 新增子模块必须在此文件注册
- utils/ 不能依赖任何其他 shared 子模块（最底层）
