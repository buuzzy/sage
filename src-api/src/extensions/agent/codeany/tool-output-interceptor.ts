/**
 * Sage-owned adapter around SDK PostToolUse hooks.
 *
 * The SDK patch only provides a generic ability to replace tool output through
 * `modifiedOutput`. Detection, artifact queueing, and summary semantics live in
 * this adapter so they remain Sage product code rather than vendor SDK code.
 */

import { createLogger } from '@/shared/utils/logger';

const logger = createLogger('ToolOutputInterceptor');

export interface ToolOutputMetadata {
  skill: string;
  action: string;
  list_code?: string;
}

export interface ToolOutputInterceptResult {
  metadata: ToolOutputMetadata;
  artifactBlock: string;
  summary: string;
}

export interface ToolOutputInterceptorOptions {
  queueArtifact: (artifactBlock: string) => void;
  intercept: (
    command: string,
    output: string
  ) => ToolOutputInterceptResult | null;
}

function extractCommand(toolInput: unknown): string {
  if (typeof toolInput === 'string') return toolInput;
  if (toolInput && typeof toolInput === 'object') {
    const command = (toolInput as Record<string, unknown>).command;
    return typeof command === 'string' ? command : '';
  }
  return '';
}

export function createToolOutputInterceptorHook({
  queueArtifact,
  intercept,
}: ToolOutputInterceptorOptions) {
  return {
    matcher: 'Bash',
    hooks: [
      async (input: {
        toolInput?: unknown;
        toolOutput?: unknown;
      }): Promise<{ modifiedOutput: string } | undefined> => {
        const toolOutput =
          typeof input.toolOutput === 'string' ? input.toolOutput : '';
        const command = extractCommand(input.toolInput);
        const result = intercept(command, toolOutput);
        if (!result) return undefined;

        queueArtifact(result.artifactBlock);

        logger.info(
          `[PostToolUse] Intercepted → ${result.metadata.skill}/${result.metadata.action}, artifact queued, summary ${result.summary.length} chars`
        );

        return { modifiedOutput: result.summary };
      },
    ],
  };
}
