/**
 * Agent execution strategy classifier.
 * Pure functions that determine whether a prompt should go through
 * plan/approve/execute or direct execution.
 */

import type { AgentExecutionStrategy } from './types';

function isConversationalPrompt(lower: string): boolean {
  const chinesePatterns = [
    '你好',
    '您好',
    '在吗',
    '谢谢',
    '你是谁',
    '你能做什么',
    '你可以做什么',
  ];
  if (chinesePatterns.some((p) => lower.includes(p))) {
    return true;
  }

  return /\b(hello|hi|hey|thanks|thank you)\b/i.test(lower);
}

function isMemoryRecallPrompt(lower: string): boolean {
  const memoryRecallPatterns = [
    'memory',
    '记忆',
    '历史',
    '之前',
    '以前',
    '上次',
    '回顾',
    '回忆',
    '复盘',
    '找一下',
    '查一下之前',
    '聊过',
    '说过',
    '提到过',
    '回测',
    'backtest',
  ];

  return memoryRecallPatterns.some((p) => lower.includes(p));
}

function countExplicitSymbols(lower: string): number {
  const matches = lower.match(/\b(?:sh|sz|hk|bj)?\d{5,6}\b/g);
  return new Set(matches ?? []).size;
}

function isMultiTargetQuery(prompt: string): boolean {
  const lower = prompt.toLowerCase();
  const comparisonPatterns = ['对比', '比较', '分析', 'vs', '和', '与', '跟'];
  const hasComparisonIntent = comparisonPatterns.some((p) => lower.includes(p));
  const enumCount = (lower.match(/[、，,]/g) || []).length;
  const symbolCount = countExplicitSymbols(lower);

  return (
    (hasComparisonIntent && enumCount >= 1) ||
    enumCount >= 2 ||
    symbolCount >= 2
  );
}

function hasDirectLookupIntent(lower: string): boolean {
  const directPatterns = [
    // Simple quote queries
    '行情',
    '股价',
    '报价',
    '价格',
    '多少钱',
    '现在多少',
    '涨跌',
    '涨幅',
    '跌幅',
    '涨了',
    '跌了',
    // K-line / chart
    'k线',
    'kline',
    '走势',
    '日线',
    '周线',
    // Simple lookups
    '最新价',
    '收盘价',
    '开盘价',
    '换手率',
    '成交量',
    '市盈率',
    '市净率',
    'pe',
    'pb',
    // Fund NAV
    '净值',
    // Quick news
    '新闻',
    '资讯',
    '快讯',
    '早报',
    // Short question forms
    '怎么样',
    '什么情况',
    '表现如何',
  ];

  return directPatterns.some((p) => lower.includes(p));
}

function classifyAgentExecutionStrategy(
  prompt: string,
  options: { hasImages?: boolean; apiType?: string | null }
): AgentExecutionStrategy {
  const trimmed = prompt.trim();
  const lower = trimmed.toLowerCase();
  const isOpenAiProvider = options.apiType === 'openai-completions';
  const multiTarget = isMultiTargetQuery(trimmed);

  if (options.hasImages) {
    return {
      route: 'direct',
      intent: 'image',
      boostPrompt: multiTarget,
      reason: 'images require execution path',
    };
  }

  if (isOpenAiProvider) {
    return {
      route: 'direct',
      intent: multiTarget ? 'multi_target' : 'openai_provider',
      boostPrompt: multiTarget,
      reason: 'OpenAI-compatible providers use direct execution',
    };
  }

  if (trimmed.length > 300) {
    return {
      route: 'plan',
      intent: 'complex_task',
      reason: 'long request benefits from explicit plan',
    };
  }

  if (isConversationalPrompt(lower)) {
    return {
      route: 'direct',
      intent: 'conversation',
      reason: 'low-risk conversational prompt',
    };
  }

  if (isMemoryRecallPrompt(lower)) {
    return {
      route: 'direct',
      intent: 'memory_recall',
      reason: 'memory recall should execute tools directly',
    };
  }

  if (multiTarget) {
    return {
      route: 'plan',
      intent: 'multi_target',
      reason: 'multi-target comparison needs structured execution',
    };
  }

  if (hasDirectLookupIntent(lower)) {
    return {
      route: 'direct',
      intent: 'simple_lookup',
      reason: 'simple lookup can skip explicit approval',
    };
  }

  return {
    route: 'plan',
    intent: 'complex_task',
    reason: 'default explicit planning path',
  };
}

function applyAgentStrategyHint(
  prompt: string,
  strategy: AgentExecutionStrategy
): string {
  if (!strategy.boostPrompt && strategy.intent !== 'multi_target') {
    return prompt;
  }

  return `${prompt}

[Execution strategy]
- This is a multi-target or comparison request.
- Prefer batch-capable tools and aggregate results before writing the final answer.
- Keep tool calls bounded: fetch each required data category once per target group, then summarize.
- If web search is needed, search combined keywords instead of repeating one search per target.
- In the final answer, explicitly compare the targets and call out missing data instead of looping.`;
}

export { classifyAgentExecutionStrategy, applyAgentStrategyHint };
