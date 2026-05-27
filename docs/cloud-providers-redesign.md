# Sage 模型配置云端化重构方案

> 制定日期：2026-05-27  
> 责任人：nakocai  
> 状态：方案已确认，进入实施

## 背景

Sage 是纯云端产品，但模型配置（providers / API Key / 默认模型）目前散落在三个地方：

- **macOS 端**：localStorage + SQLite，部分非敏感字段同步到 `user_settings`
- **iOS 端**：UserDefaults（v3 schema），未上云
- **Railway 后端**：Cron 调度时用全局 `DEEPSEEK_API_KEY` env 兜底

历史问题：
- iOS 与 macOS 配置不互通
- API Key 项目原则上不上云（"宁可漏，不可泄漏"）
- iOS testConnection 加的 `chatCompletionsPath` 字段对真实聊天无效（后端有自己的 `buildEndpointUrl`）
- DeepSeek 等厂商频繁踩 baseUrl/path 拼接坑

## 目标

1. **云端为唯一真相源**：所有模型配置（含 API Key）由 Supabase 管理
2. **多端一致**：iOS / macOS 行为完全对齐
3. **后端按用户拉配置**：Cron / Channel / 直接对话都走同一份用户 provider
4. **路径处理一劳永逸**：每个 provider 显式声明 base_url + endpoint_path，告别启发式拼接
5. **删除冗余**：iOS 的 `chatCompletionsPath` / `messagesPath` 字段下线

## 用户决策（已确认）

| 决定 | 选择 |
|---|---|
| 加密策略 | 服务端 KMS 加密（非 E2EE） |
| 离线策略 | 纯云端，无网不可改配置 |
| 多端冲突 | LWW + 字段级 patch upsert |
| 协议支持 | OpenAI + Anthropic 双协议（每厂商按官方推荐） |
| API Key 上云 | ✅，由后端 KMS 加密 |
| 后端可解密 | ✅，Cron / Channel 必需 |
| 内置厂商 | DeepSeek / MiniMax / SiliconFlow / Kimi / 通义千问 / 智谱 / 字节方舟 + 自定义 |
| emoji 复杂名 | ✅ 支持 |

## 数据模型

### Supabase 新表 `user_providers`

```sql
CREATE TABLE public.user_providers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  provider_kind   TEXT NOT NULL,   -- 'deepseek'|'minimax'|...|'custom'
  display_name    TEXT NOT NULL,   -- "DeepSeek" 或用户起的别名（支持 emoji）
  api_type        TEXT NOT NULL CHECK (api_type IN ('anthropic-messages','openai-completions')),
  base_url        TEXT NOT NULL,   -- 主机根 URL
  endpoint_path   TEXT NOT NULL,   -- 完整路径，如 /v1/chat/completions、/api/coding/v3/chat/completions
  models          JSONB NOT NULL DEFAULT '[]'::jsonb,  -- string[]
  default_model   TEXT,
  api_key_secret_id UUID,          -- 引用 vault.secrets，由 pgsodium 自动加密
  enabled         BOOLEAN NOT NULL DEFAULT TRUE,
  is_default      BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order      INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_user_providers_user_id ON user_providers (user_id, sort_order);
CREATE UNIQUE INDEX uniq_user_default_provider ON user_providers (user_id) WHERE is_default = TRUE;

-- 触发器：自动更新 updated_at
CREATE TRIGGER trg_user_providers_updated_at
  BEFORE UPDATE ON user_providers
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- RLS
ALTER TABLE user_providers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_providers: owner only"
  ON user_providers FOR ALL
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
```

### API Key 加密存储

- 使用 Supabase **Vault**（基于 pgsodium）
- `api_key_secret_id` 引用 `vault.secrets(id)`
- 后端 service_role 可通过 `vault.decrypted_secrets` 视图解密
- 客户端**无法**直接读取明文（不在 RLS 视图内）

### 客户端写入流程

```
客户端 → POST /providers (Authorization: Bearer <user_jwt>)
       → 后端把 api_key 存 vault → 拿到 secret_id
       → 后端 INSERT user_providers { api_key_secret_id }
       → 返回不含 api_key 的 provider 对象
```

### 客户端读取流程

```
客户端 → SELECT * FROM user_providers WHERE user_id = auth.uid()
       (RLS 自动过滤；api_key_secret_id 是 UUID，没有明文 key)
```

### 后端调用 LLM 流程

```
Cron/Channel → 用 service_role 查 user_providers + vault.decrypted_secrets JOIN
             → 拿到明文 api_key
             → 拼 base_url + endpoint_path
             → SDK 调用 LLM
```

## API 路由设计（后端）

### 替代旧 `/providers/settings/sync`：

```
GET    /providers           → 列出当前用户所有 provider（不含 key）
POST   /providers           → 新建（apiKey 写入 vault）
PATCH  /providers/:id       → 字段级更新（含 apiKey 替换）
DELETE /providers/:id       → 删除（同时 vault.delete_secret）
POST   /providers/:id/default → 设为默认（取消其他 is_default）
POST   /providers/:id/test  → 服务端代测连通性
```

### 内置 provider 元数据（写在客户端代码 + 后端代码各一份，作为常量）

> 端点信息已逐家核对官方文档（2026-05-27），以下为最终版本。

```ts
const BUILTIN_PROVIDERS: ProviderTemplate[] = [
  // —— Anthropic 协议优先 ——
  { kind: 'deepseek', name: 'DeepSeek',
    apiType: 'anthropic-messages',
    baseUrl: 'https://api.deepseek.com',
    endpointPath: '/anthropic/v1/messages',
    models: ['deepseek-v4-flash', 'deepseek-v4-pro'],
    defaultModel: 'deepseek-v4-flash' },

  { kind: 'minimax', name: 'MiniMax',
    apiType: 'anthropic-messages',
    baseUrl: 'https://api.minimaxi.com',
    endpointPath: '/anthropic/v1/messages',
    models: ['MiniMax-M2', 'MiniMax-M2.5', 'MiniMax-M2.7'],
    defaultModel: 'MiniMax-M2.7' },

  { kind: 'zhipu', name: '智谱 BigModel',
    apiType: 'anthropic-messages',          // 智谱原生支持 Anthropic 协议
    baseUrl: 'https://open.bigmodel.cn',
    endpointPath: '/api/anthropic/v1/messages',
    models: ['glm-5.1', 'glm-5-turbo', 'glm-4.7'],
    defaultModel: 'glm-5.1' },

  { kind: 'volcengine', name: '火山方舟',
    apiType: 'anthropic-messages',          // Coding Plan Anthropic 入口
    baseUrl: 'https://ark.cn-beijing.volces.com',
    endpointPath: '/api/coding/v1/messages',
    models: ['ark-code-latest'],
    defaultModel: 'ark-code-latest' },

  // —— OpenAI 协议（厂商不支持 Anthropic 或代价过高）——
  { kind: 'siliconflow', name: 'SiliconFlow',
    apiType: 'openai-completions',
    baseUrl: 'https://api.siliconflow.cn',
    endpointPath: '/v1/chat/completions',
    models: ['MiniMaxAI/MiniMax-M2.1', 'zai-org/GLM-4.7'],
    defaultModel: 'zai-org/GLM-4.7' },

  { kind: 'kimi', name: 'Kimi (Moonshot)',
    apiType: 'openai-completions',
    baseUrl: 'https://api.moonshot.cn',
    endpointPath: '/v1/chat/completions',
    models: ['kimi-k2.6', 'moonshot-v1-32k', 'moonshot-v1-128k'],
    defaultModel: 'kimi-k2.6' },

  { kind: 'qwen', name: '通义千问',
    apiType: 'openai-completions',
    baseUrl: 'https://dashscope.aliyuncs.com',
    endpointPath: '/compatible-mode/v1/chat/completions',
    models: ['qwen3.6-plus', 'qwen-plus', 'qwen-turbo'],
    defaultModel: 'qwen3.6-plus' },

  // —— 自定义 ——
  { kind: 'custom', name: '自定义',
    apiType: 'openai-completions',
    baseUrl: '',
    endpointPath: '/v1/chat/completions',
    models: [],
    defaultModel: undefined },
];
```

## 改造任务拆分（4 阶段）

### Phase 1：后端表 + 加密（先做，不破坏现状）
- [ ] migration: `20260527_user_providers.sql`（建表、Vault 集成、RLS）
- [ ] `src-api/src/shared/provider/user-store.ts`（CRUD + KMS）
- [ ] `src-api/src/app/api/providers.ts` 新增上述 6 个路由
- [ ] 单元测试：表 CRUD、Vault 加解密、RLS 隔离

### Phase 2：后端 Agent 调度对接
- [ ] `runJobPrompt`（cron）改为按 `job.user_id` 拉 user_providers
- [ ] `/agent` 路由按 `auth.uid()` 拉默认 provider（不再读 ConfigLoader）
- [ ] `/providers/:id/test` 实现（服务端代测）

### Phase 3：macOS 端切换数据源
- [ ] `src/shared/db/settings.ts` 把 providers[] 从 settings 中拆出
- [ ] 新建 `src/shared/sync/providers-sync.ts` 接 user_providers
- [ ] `ModelSettings.tsx` UI 改造：+号按钮 + 添加页下拉
- [ ] 删除 baseUrl 中带 `/anthropic`、`/v1` 的旧约定，改用显式 endpoint_path
- [ ] 旧用户迁移：首次启动时把本地 providers[] upsert 到云端

### Phase 4：iOS 端重写
- [ ] 引入 supabase-swift（已有依赖）
- [ ] 重写 `SettingsService.swift`：删除 v3 schema，改为内存态 + 云端拉取
- [ ] 删除 `chatCompletionsPath` / `messagesPath` / `ProviderEndpointResolver` / `migrateFromLegacy` / `resetProviderToDefault`
- [ ] 新建 `CloudProviderStore.swift`：URL 拼接靠云端字段，不再客户端推断
- [ ] UI 改造：右上角 + 号 → 添加页下拉 → 选品牌锁路径

### Phase 5：清理
- [ ] 删除 `buildEndpointUrl` 中的启发式（旧用户迁移完成后）
- [ ] 删除 `defaultProviders` 常量（macOS 端）
- [ ] 删除 iOS v3 schema 兼容代码

## 风险 & 兜底

- **Vault 性能**：每次 Cron 都解密 → 加 5 分钟级别缓存
- **多端 LWW 冲突丢数据**：用 PATCH 字段级 upsert，不用整行 upsert
- **未登录用户**：UI 引导登录，保留默认 provider（无 key）作为占位
- **网络抖动**：客户端 fetch + retry × 3，失败显示明确报错（不静默）
- **迁移失败**：保留旧 `user_settings.providers` 字段一段时间，发现迁移失败可回滚

## 时间预估

- Phase 1: 0.5 天
- Phase 2: 1 天
- Phase 3: 1.5 天
- Phase 4: 1.5 天
- Phase 5: 0.5 天
- **合计：5 工作日**

## 不做的事（明确边界）

- 不实现 E2EE（已被否决）
- 不实现离线编辑（产品定位为纯云）
- 不做 Realtime 订阅 provider 变更（保存后下次进入页面重新拉即可）
- 不做 provider-level 共享（每个 user 各自的 provider，不能跨用户）
