# shared/context/ — 对话上下文管理

为模型组装对话上下文：控制 token 预算，必要时压缩历史消息。

## 核心流程

```
assembleContext(taskId, messages, config?)
  1. 检查 compaction-store 有无已存摘要
  2. 估算当前 messages token 总量（estimateTokens）
  3. 超预算？→ chunked compaction:
     a. 按 maxChunkTokens 切分旧消息
     b. 每 chunk 独立调 LLM summarize
     c. 合并 partial summaries → final summary
     d. 保存到 compaction-store（避免重复压缩）
  4. 返回: [summary context] + [recent N messages]
```

## 文件清单

| 文件 | 职责 | 稳定度 |
|------|------|--------|
| assembler.ts | 主入口 `assembleContext()`，编排检查 + 压缩 + 组装 | 🔒 接口稳定 |
| compaction.ts | 压缩引擎（chunked summarization + token 估算） | 🔧 算法可调优 |
| compaction-store.ts | 压缩结果持久化（JSON 文件，按 taskId 索引） | 🔒 |
| session-store.ts | 会话消息存储接口（读取消息列表） | 🔒 |

## 关键配置（DEFAULT_CONFIG）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| maxContextTokens | 12000 | 总 token 预算上限 |
| keepRecentMessages | 6 | 压缩时保留最近 N 轮消息 |
| maxChunkTokens | 8000 | 单 chunk 上限（超过则拆分） |
| timeoutMs | 60000 | 压缩 LLM 调用超时 |

## Token 估算逻辑（estimateTokens）

```
CJK 字符: 每字符 ≈ 1.5 tokens
非 CJK:   非空白字符数 / 3.5
最终:     cjkCount * 1.5 + nonCjkChars / 3.5
```

注意：这是估算，实际 tokenizer 结果可能有 ±20% 偏差。

## 不变量

- **原始消息永远不删除**，compaction 结果存在独立 store
- 压缩时**保留所有标识符**（路径、URL、股票代码、ID、hostname）
- compaction 失败不阻塞对话（fallback: 截断保留 recent N 条，不做摘要）
- assembler 输出是纯 string（用作 system prompt 补充段），不是 message array
- 不在本模块依赖特定 provider（通过 `getProviderManager()` 获取当前活跃模型）
