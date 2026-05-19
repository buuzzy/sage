/**
 * File extraction and persistence utilities.
 * Detects file content in agent responses and saves them to local storage.
 */

import { createFile, type FileType } from '@/shared/db';

function getFileTypeFromPath(path: string): FileType {
  const ext = path.split('.').pop()?.toLowerCase() || '';

  // Code files
  if (
    [
      'js',
      'jsx',
      'ts',
      'tsx',
      'py',
      'go',
      'rs',
      'java',
      'c',
      'cpp',
      'h',
      'hpp',
      'cs',
      'rb',
      'php',
      'swift',
      'kt',
      'scala',
      'sh',
      'bash',
      'zsh',
      'ps1',
      'sql',
    ].includes(ext)
  ) {
    return 'code';
  }

  // Image files
  if (
    ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico'].includes(ext)
  ) {
    return 'image';
  }

  // Presentation files
  if (['ppt', 'pptx', 'key', 'odp'].includes(ext)) {
    return 'presentation';
  }

  // Spreadsheet files
  if (['xls', 'xlsx', 'numbers', 'ods'].includes(ext)) {
    return 'spreadsheet';
  }

  // Document files
  if (['md', 'pdf', 'doc', 'docx', 'txt', 'rtf', 'odt'].includes(ext)) {
    return 'document';
  }

  // Text files (config, data)
  if (
    [
      'json',
      'yaml',
      'yml',
      'xml',
      'toml',
      'ini',
      'conf',
      'cfg',
      'env',
      'csv',
      'tsv',
    ].includes(ext)
  ) {
    return 'text';
  }

  // HTML files
  if (['html', 'htm'].includes(ext)) {
    return 'website';
  }

  // Default to text
  return 'text';
}

// Extract file paths from text content (for text messages that mention file paths)
async function extractFilesFromText(
  taskId: string,
  textContent: string
): Promise<void> {
  if (!textContent) return;

  try {
    // Patterns to match file paths in text
    const filePatterns = [
      // Match paths in backticks with common document extensions
      /`([^`]+\.(?:pptx|xlsx|docx|pdf))`/gi,
      // Match absolute paths with Chinese/unicode support
      /(\/[^\s"'`\n]*[\u4e00-\u9fff][^\s"'`\n]*\.(?:pptx|xlsx|docx|pdf))/gi,
      // Match standard absolute paths
      /(\/(?:Users|home|tmp|var)[^\s"'`\n]+\.(?:pptx|xlsx|docx|pdf))/gi,
    ];

    const detectedFiles = new Set<string>();

    for (const pattern of filePatterns) {
      const matches = textContent.matchAll(pattern);
      for (const match of matches) {
        const filePath = match[1] || match[0];
        if (filePath && !detectedFiles.has(filePath)) {
          detectedFiles.add(filePath);
          const fileName = getFileName(filePath);
          const fileType = getFileTypeFromPath(filePath);

          await createFile({
            task_id: taskId,
            name: fileName,
            type: fileType,
            path: filePath,
            preview: `File mentioned in response`,
          });
          console.log(
            '[useAgent] Created file record from text message:',
            fileName
          );
        }
      }
    }
  } catch (error) {
    console.error('[useAgent] Failed to extract files from text:', error);
  }
}

// Extract file info from tool use messages and create file records
async function extractAndSaveFiles(
  taskId: string,
  toolName: string,
  toolInput: Record<string, unknown> | undefined,
  toolOutput: string | undefined
): Promise<void> {
  if (!toolInput) return;

  try {
    // Handle Write tool - creates new files
    if (toolName === 'Write' && toolInput.file_path) {
      const filePath = String(toolInput.file_path);
      const fileName = getFileName(filePath);
      const content = toolInput.content ? String(toolInput.content) : '';
      const preview = content.slice(0, 500);
      const fileType = getFileTypeFromPath(filePath);

      await createFile({
        task_id: taskId,
        name: fileName,
        type: fileType,
        path: filePath,
        preview: preview || undefined,
      });
      console.log('[useAgent] Created file record for Write:', fileName);
    }

    // Handle Edit tool - modifies existing files
    if (toolName === 'Edit' && toolInput.file_path) {
      const filePath = String(toolInput.file_path);
      const fileName = getFileName(filePath);
      const newContent = toolInput.new_string
        ? String(toolInput.new_string)
        : '';
      const fileType = getFileTypeFromPath(filePath);

      await createFile({
        task_id: taskId,
        name: `${fileName} (edited)`,
        type: fileType,
        path: filePath,
        preview: newContent.slice(0, 500) || undefined,
      });
      console.log('[useAgent] Created file record for Edit:', fileName);
    }

    // Handle WebFetch tool - captures web content
    if (toolName === 'WebFetch' && toolInput.url) {
      const url = String(toolInput.url);
      const title = url.replace(/^https?:\/\//, '').slice(0, 60);

      await createFile({
        task_id: taskId,
        name: title,
        type: 'website',
        path: url,
        preview: toolOutput?.slice(0, 500) || undefined,
      });
      console.log('[useAgent] Created file record for WebFetch:', title);
    }

    // Handle WebSearch tool - captures search results
    if (toolName === 'WebSearch' && toolInput.query) {
      const query = String(toolInput.query);

      await createFile({
        task_id: taskId,
        name: `Search: ${query.slice(0, 50)}`,
        type: 'text',
        path: `search://${encodeURIComponent(query)}`,
        preview: toolOutput?.slice(0, 500) || undefined,
      });
      console.log('[useAgent] Created file record for WebSearch:', query);
    }

    // Handle Bash tool - capture command outputs and detect generated files
    if (toolName === 'Bash' && toolInput.command) {
      const command = String(toolInput.command);
      const detectedBashFiles = new Set<string>();

      // Check if this is a file generation command (pptx, pdf, etc.)
      const filePatterns = [
        /saved?\s+(?:to\s+)?["']?([^\s"']+\.(?:pptx|xlsx|docx|pdf))["']?/i,
        /(?:created|generated|wrote|output)\s+["']?([^\s"']+\.(?:pptx|xlsx|docx|pdf))["']?/i,
        /writeFile\s*\(\s*["']([^"']+\.(?:pptx|xlsx|docx|pdf))["']/i,
        // Match any absolute path to pptx/xlsx/docx/pdf files
        /(\/[^\s"'`\n]+\.(?:pptx|xlsx|docx|pdf))/gi,
        // Match paths in backticks
        /`([^`]+\.(?:pptx|xlsx|docx|pdf))`/gi,
      ];

      if (toolOutput) {
        for (const pattern of filePatterns) {
          const matches = toolOutput.matchAll(pattern);
          for (const match of matches) {
            const filePath = match[1] || match[0];
            if (filePath && !detectedBashFiles.has(filePath)) {
              detectedBashFiles.add(filePath);
              const fileName = getFileName(filePath);
              const fileType = getFileTypeFromPath(filePath);

              await createFile({
                task_id: taskId,
                name: fileName,
                type: fileType,
                path: filePath,
                preview: `Generated by command: ${command.slice(0, 100)}`,
              });
              console.log(
                '[useAgent] Created file record for generated file:',
                fileName
              );
            }
          }
        }
      }
    }

    // Handle Skill tool - capture skill outputs and detect generated files
    if (toolName === 'Skill' && toolOutput) {
      // Try to detect file paths in skill output
      const filePatterns = [
        /(?:saved?|created|generated|wrote|output)\s+(?:to\s+)?["']?([^\s"'\n]+\.(?:pptx|xlsx|docx|pdf|png|jpg|html))["']?/gi,
        /(?:file|output|presentation|document):\s*["']?([^\s"'\n]+\.(?:pptx|xlsx|docx|pdf|png|jpg|html))["']?/gi,
        // Match any absolute path to these file types
        /(\/[^\s"'`\n]+\.(?:pptx|xlsx|docx|pdf))/gi,
        // Match paths in backticks
        /`([^`]+\.(?:pptx|xlsx|docx|pdf))`/gi,
        // Match Chinese/unicode paths
        /(\/[^\s"'\n]*[\u4e00-\u9fff][^\s"'\n]*\.(?:pptx|xlsx|docx|pdf))/gi,
      ];

      const detectedFiles = new Set<string>();

      for (const pattern of filePatterns) {
        const matches = toolOutput.matchAll(pattern);
        for (const match of matches) {
          const filePath = match[1] || match[0];
          if (filePath && !detectedFiles.has(filePath)) {
            detectedFiles.add(filePath);
            const fileName = getFileName(filePath);
            const fileType = getFileTypeFromPath(filePath);

            await createFile({
              task_id: taskId,
              name: fileName,
              type: fileType,
              path: filePath,
              preview: `Generated by skill: ${toolInput.skill || 'unknown'}`,
            });
            console.log(
              '[useAgent] Created file record from Skill output:',
              fileName
            );
          }
        }
      }
    }
  } catch (error) {
    console.error('[useAgent] Failed to extract and save file:', error);
  }
}

export { getFileTypeFromPath, extractFilesFromText, extractAndSaveFiles };
