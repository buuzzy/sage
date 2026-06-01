/**
 * SiliconFlow 语音转文字（ASR）适配器。
 *
 * 端点：POST https://api.siliconflow.cn/v1/audio/transcriptions（multipart/form-data）
 * 模型：FunAudioLLM/SenseVoiceSmall（中文 + 金融术语效果好，离线非流式，契合 push-to-talk）
 * 文档：https://docs.siliconflow.cn/cn/api-reference/audio/create-audio-transcriptions
 *
 * API Key 仅在服务端通过环境变量 SILICONFLOW_API_KEY 读取，绝不下发到 iOS 客户端。
 * 文件规格：时长 ≤ 1h、大小 ≤ 50MB（push-to-talk 实际只有几秒）。
 */

const SILICONFLOW_TRANSCRIPTION_URL = 'https://api.siliconflow.cn/v1/audio/transcriptions';
const DEFAULT_ASR_MODEL = 'FunAudioLLM/SenseVoiceSmall';

/** 携带建议返回给客户端的 HTTP 状态：503=未配置 key，502=上游失败。 */
export class TranscriptionError extends Error {
  constructor(
    message: string,
    readonly httpStatus: 502 | 503
  ) {
    super(message);
    this.name = 'TranscriptionError';
  }
}

interface SiliconFlowTranscriptionResponse {
  text?: string;
}

/**
 * 把音频转写为文字。
 * @param audio    音频二进制（m4a/mp3/wav/ogg/flac）
 * @param filename multipart 文件名（扩展名建议匹配真实格式）
 * @param model    ASR 模型，默认 SenseVoiceSmall
 * @returns        转写文本（已 trim，可能为空字符串）
 */
export async function transcribeAudio(
  audio: Blob,
  filename = 'audio.m4a',
  model: string = DEFAULT_ASR_MODEL
): Promise<string> {
  const apiKey = process.env.SILICONFLOW_API_KEY;
  if (!apiKey) {
    throw new TranscriptionError('SILICONFLOW_API_KEY 未配置', 503);
  }

  const form = new FormData();
  form.append('file', audio, filename);
  form.append('model', model);

  const res = await fetch(SILICONFLOW_TRANSCRIPTION_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new TranscriptionError(`SiliconFlow ASR 失败 (HTTP ${res.status}): ${detail.slice(0, 200)}`, 502);
  }

  const data = (await res.json()) as SiliconFlowTranscriptionResponse;
  return (data.text ?? '').trim();
}
