# extensions/agent/codeany/ — CodeAny SDK Agent 适配器

Sage 的 Agent 大脑。把 `@codeany/open-agent-sdk` 包装成 Sage 的 IAgent 接口，加入记忆注入、工具拦截、artifact 生成等产品能力。

## 请求完整流程

```
前端 useAgent POST /agent
  → shared/services/agent.ts getAgent()
  → CodeAnyAgent (this file)
  → buildSystemPrompt():
      SOUL.md
      + AGENTS.md (技能列表 + artifact 协议)
      + persona section (Layer 1, persona-injector.ts)
      + active-recall section (Layer 2, active-recall.ts)
      + skills SKILL.md (predictor 选择)
  → SDK query() with PostToolUse hooks:
      tool-output-interceptor → URL/结构检测 → modifiedOutput + artifact queue
  → processMessage():
      flush pendingArtifacts → 组装 SSE events → yield to stream
```

## 文件清单

| 文件 | 职责 | 稳定度 |
|------|------|--------|
| index.ts | Agent 适配器主类（plan / run / processMessage / buildSystemPrompt） | ⚠️ 核心，谨慎修改 |
| tool-output-interceptor.ts | PostToolUse hook 工厂（URL 检测 + JSON 结构检测 → summary + artifact） | 🔧 可扩展新拦截规则 |
| persona-injector.ts | Phase 3 画像注入（从 Supabase persona_memory 拉取） | 🔒 接口稳定 |
| active-recall.ts | Phase 4 主动召回（FTS top-2 相关历史片段） | 🔒 接口稳定 |

## index.ts 关键结构

```
ARTIFACT_TYPE_MAP        — (skill, action) → artifact component type 映射表
class CodeAnyAgent       — implements IAgent
  plan()                 — 规划阶段（生成 TaskPlan）
  run()                  — 直接执行（跳过 plan）
  execute()              — 执行已批准 plan
  buildSystemPrompt()    — 组装完整 system prompt
  processMessage()       — 解析 SDK 输出 → SSE events（text/tool/artifact/done）
```

## 工具拦截机制（tool-output-interceptor.ts）

| 层 | 检测方式 | 说明 |
|---|---|---|
| Layer 1 | URL pattern（`detectFromCommand()`） | 匹配 Bash 命令中的 westock/iwencai API URL |
| Layer 2 | JSON 结构（`detectFromResponseStructure()`） | 匹配 tool output 中的 JSON 字段模式 |
| Layer 0 | `_metadata` 字段 | Fallback，工具自行标记 |

拦截后：
- `generateSummary()` → 100~200 字符摘要替换原始 output（省 ~5K tokens/次）
- `transformForComponent()` → API 格式 → 前端组件数据格式
- artifact block 入 `pendingArtifacts` 队列 → processMessage 时 flush

## 扩展工具拦截的步骤

1. `index.ts` 的 `ARTIFACT_TYPE_MAP` 添加 `{skill: {action: component_type}}`
2. `tool-output-interceptor.ts` 的 `detectFromCommand()` 添加 URL pattern
3. （可选）`detectFromResponseStructure()` 添加 JSON 结构规则
4. 前端 `htui/` 添加对应组件 + `ArtifactRenderer` 注册

## 记忆注入时序

| 阶段 | 触发条件 | 文件 | 失败行为 |
|------|---------|------|---------|
| Persona (L1) | 每次对话 | persona-injector.ts | 静默返回空 |
| Active Recall (L2) | 首轮 user message + conversation 为空 | active-recall.ts | 静默返回空 |
| MCP Tool (L3) | Agent 主动调用 search_memory | app/api/mcp-memory.ts | 返回空结果 |

## 不变量

- SDK patch 只承载 `modifiedOutput` 传输能力，产品逻辑不进 patch
- persona / active-recall 失败**必须静默返回空**，不阻塞对话
- `pendingArtifacts` 必须在 `processMessage()` 中 flush，不在 hook 里直接 yield
- artifact block 格式：` ```artifact:TYPE\n{pure data json}\n``` `（不包 `{type, data}` wrapper）
- 不为单一模型加特殊路由或硬编码兜底
