# shared/memory/ — 记忆系统核心

提供「记忆召回」抽象，让 Agent 能按需检索用户历史对话。

## 四层记忆架构（本模块负责底层 Provider）

| 层 | 触发时机 | 实现位置 | 本模块参与 |
|---|---|---|---|
| L1 Persona 注入 | 每次对话开始 | extensions/.../persona-injector.ts | ❌ |
| L2 Active Recall | 首轮 user message | extensions/.../active-recall.ts | ✅ 调用 Provider |
| L3 MCP Tool | Agent 主动 search_memory | app/api/mcp-memory.ts | ✅ 调用 Provider |
| L4 Distill | 每天凌晨 2 点 cron | jobs/distill-persona.ts | ❌ |

## 文件清单

| 文件 | 职责 | 稳定度 |
|------|------|--------|
| provider.ts | `MemoryProvider` 接口 + `SearchOptions` + `MemoryRequestContext` 类型 | 🔒 不改接口签名 |
| supabase-rpc-provider.ts | Supabase RPC 实现（调用 `search_messages` 数据库函数） | 🔧 可扩展 |
| index.ts | `getMemoryProvider()` 单例工厂 | 🔒 |

## MemoryProvider 接口

```typescript
interface MemoryProvider {
  search(
    query: string,
    ctx: MemoryRequestContext,  // { userId, accessToken? }
    options?: SearchOptions     // { limit?, daysBack?, timeStart?, timeEnd?, roleFilter? }
  ): Promise<MemoryRecord[]>;
}
```

## 双模式鉴权（贯穿所有记忆操作）

| 模式 | 条件 | Supabase client | 数据隔离 |
|------|------|----------------|---------|
| 桌面端 sidecar | accessToken 必传 | anon + JWT | RLS 强制隔离 |
| Railway 服务器 | accessToken 可选 | service-role | 应用层 user_id 过滤 |

## Supabase RPC 函数

- `search_messages(p_user_id, p_query, p_limit, p_days_back, p_time_start, p_time_end, p_role_filter)`
  - 底层用 PostgreSQL full-text search
  - 前端消息 type: `user`（用户）和 `text`（助手），不是 `assistant`

## 不变量

- MemoryProvider 是**只读抽象**，不加 write 方法（写入由 sync 模块负责）
- 任何记忆操作失败必须**静默返回空数组**，不阻塞主对话
- search 结果的 content 必须 trim 到 `SNIPPET_TRUNC`（200 字符）
- 不在本模块做 persona 蒸馏（那是 `jobs/distill-persona.ts` 的职责）
- 新增 Provider 实现必须满足双模式鉴权要求
