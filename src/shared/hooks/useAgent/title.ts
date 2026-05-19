/**
 * Title sanitization utilities.
 * Pure functions for cleaning and validating generated task titles.
 */

const TITLE_COMPACT_RE = /[\s"'「」『』.,，。!?！？:：;；\-_/\\()[\]{}]/g;
const ASSISTANT_REPLY_TITLE_RE =
  /^(好的|可以|当然|没问题|以下是|我会|我可以|让我|根据你的|这是|这里是|已完成|sure|okay|here'?s|i can)\b/i;

function isLowQualityTitle(title: string): boolean {
  const compact = title.replace(TITLE_COMPACT_RE, '');
  if (compact.length <= 1) return true;
  if (/^\d+$/.test(compact)) return true;
  return ASSISTANT_REPLY_TITLE_RE.test(title.trim());
}

/**
 * 清洗 backend /agent/title 的输出，防止 thinking 模型的 `<think>...</think>`
 * 推理内容污染 task.prompt。返回空串表示"拒绝使用此 title"，调用方应保留原 prompt。
 *
 * 后端 chat.ts:generateTitle 已有同样处理，此处是防御性兜底。
 */
function sanitizeTitle(raw: string): string {
  if (!raw) return '';
  let out = raw.replace(/<think\b[^>]*>[\s\S]*?<\/think>/gi, '');
  out = out.replace(/<think\b[^>]*>[\s\S]*$/i, '');
  out = out.replace(/^[\s\S]*<\/think>/i, '');
  out = out.split(/\r?\n/)[0].trim();
  out = out.replace(/^["'「『]+|["'」』]+$/g, '').trim();
  if (out.length === 0 || out.length > 40) return '';
  if (isLowQualityTitle(out)) return '';
  return out;
}

export { sanitizeTitle, isLowQualityTitle };
