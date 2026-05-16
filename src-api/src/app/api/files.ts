/**
 * Files API Routes
 *
 * Provides HTTP endpoints for file system operations.
 * Uses Node.js fs module for reliable filesystem access.
 */

import { exec } from 'child_process';
import * as fs from 'fs/promises';
import * as path from 'path';
import { promisify } from 'util';
import { Hono } from 'hono';

import { getAllSkillsDirs, getHomeDir, isRunningInSandbox } from '@/config/constants';

const execAsync = promisify(exec);

const files = new Hono();

interface FileEntry {
  name: string;
  path: string;
  isDir: boolean;
  children?: FileEntry[];
}

interface GitHubContentItem {
  name: string;
  path: string;
  type: 'file' | 'dir';
  download_url?: string | null;
}

interface GitHubImportRequest {
  url: string;
  targetDir?: string;
}

/**
 * Common files/folders to ignore (similar to .gitignore patterns)
 */
const IGNORED_NAMES = new Set([
  // Dependencies
  'node_modules',
  'bower_components',
  'jspm_packages',
  'vendor',
  '__pycache__',
  '.pnpm',

  // Build outputs
  'dist',
  'build',
  'out',
  '.next',
  '.nuxt',
  '.output',
  '.vercel',
  '.netlify',

  // Cache directories
  '.cache',
  '.parcel-cache',
  '.turbo',
  '.swc',
  '.eslintcache',
  '.stylelintcache',

  // IDE/Editor
  '.idea',
  '.vscode',
  '.vs',
  '*.sublime-*',

  // OS files
  '.DS_Store',
  'Thumbs.db',
  'desktop.ini',

  // Logs
  'logs',
  '*.log',
  'npm-debug.log*',
  'yarn-debug.log*',
  'yarn-error.log*',

  // Environment/secrets
  '.env.local',
  '.env.*.local',

  // Test coverage
  'coverage',
  '.nyc_output',

  // Temporary files
  'tmp',
  'temp',
  '.tmp',
  '.temp',

  // Lock files (optional, but often noisy)
  'package-lock.json',
  'yarn.lock',
  'pnpm-lock.yaml',
  'composer.lock',
  'Cargo.lock',
]);

/**
 * Check if a file/folder should be ignored
 */
function shouldIgnore(name: string): boolean {
  // Skip hidden files/folders (starting with .)
  if (name.startsWith('.')) return true;

  // Check exact match
  if (IGNORED_NAMES.has(name)) return true;

  // Check pattern matches (for wildcards like *.log)
  const lowerName = name.toLowerCase();
  if (lowerName.endsWith('.log')) return true;
  if (lowerName.endsWith('.lock')) return true;
  if (lowerName.startsWith('npm-debug')) return true;
  if (lowerName.startsWith('yarn-debug')) return true;
  if (lowerName.startsWith('yarn-error')) return true;

  return false;
}

function parseGitHubUrl(url: string): {
  owner: string;
  repo: string;
  ref?: string;
  path?: string;
} {
  const parsed = new URL(url);
  if (parsed.hostname !== 'github.com') {
    throw new Error('Only github.com repository URLs are supported');
  }

  const parts = parsed.pathname.split('/').filter(Boolean);
  if (parts.length < 2) {
    throw new Error('GitHub URL must include owner and repository');
  }

  const [owner, repo, marker, ref, ...rest] = parts;
  return {
    owner,
    repo: repo.replace(/\.git$/, ''),
    ref: marker === 'tree' ? ref : undefined,
    path: marker === 'tree' ? rest.join('/') : undefined,
  };
}

function assertAllowedSkillTarget(targetDir?: string): string {
  const skillsDirs = getAllSkillsDirs();
  const preferred = targetDir || skillsDirs.find((d) => d.name === 'sage')?.path;
  if (!preferred) {
    throw new Error('No skills directory configured');
  }

  const resolved = path.resolve(preferred);
  const allowed = skillsDirs.some((dir) => path.resolve(dir.path) === resolved);
  if (!allowed) {
    throw new Error('Target directory is not an allowed skills directory');
  }

  return resolved;
}

function safeSkillDirName(name: string): string {
  return name
    .replace(/[^a-zA-Z0-9._-]/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'imported-skill';
}

async function fetchGitHubContents(
  owner: string,
  repo: string,
  contentPath = '',
  ref?: string
): Promise<GitHubContentItem[]> {
  const pathPart = contentPath
    .split('/')
    .map(encodeURIComponent)
    .join('/');
  const url = new URL(
    `https://api.github.com/repos/${owner}/${repo}/contents/${pathPart}`
  );
  if (ref) url.searchParams.set('ref', ref);

  const response = await fetch(url, {
    headers: {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'Sage-Skill-Importer',
    },
  });

  if (!response.ok) {
    throw new Error(`GitHub contents request failed: ${response.status}`);
  }

  const data = (await response.json()) as GitHubContentItem | GitHubContentItem[];
  return Array.isArray(data) ? data : [data];
}

async function findSkillDirectory(
  owner: string,
  repo: string,
  basePath = '',
  ref?: string,
  depth = 0
): Promise<string | null> {
  if (depth > 3) return null;
  const items = await fetchGitHubContents(owner, repo, basePath, ref);
  if (items.some((item) => item.type === 'file' && item.name === 'SKILL.md')) {
    return basePath;
  }

  for (const item of items) {
    if (item.type !== 'dir') continue;
    const found = await findSkillDirectory(owner, repo, item.path, ref, depth + 1);
    if (found) return found;
  }

  return null;
}

async function copyGitHubDirectory(
  owner: string,
  repo: string,
  sourcePath: string,
  ref: string | undefined,
  targetDir: string,
  counters: { files: number; bytes: number }
): Promise<void> {
  const items = await fetchGitHubContents(owner, repo, sourcePath, ref);
  await fs.mkdir(targetDir, { recursive: true });

  for (const item of items) {
    const targetPath = path.join(targetDir, item.name);
    const relativeTarget = path.relative(targetDir, targetPath);
    if (relativeTarget.startsWith('..') || path.isAbsolute(relativeTarget)) {
      throw new Error('Unsafe file path in GitHub repository');
    }

    if (item.type === 'dir') {
      await copyGitHubDirectory(owner, repo, item.path, ref, targetPath, counters);
      continue;
    }

    if (item.type !== 'file' || !item.download_url) continue;
    const response = await fetch(item.download_url);
    if (!response.ok) {
      throw new Error(`Failed to download ${item.path}: ${response.status}`);
    }
    const buffer = Buffer.from(await response.arrayBuffer());
    counters.files++;
    counters.bytes += buffer.byteLength;
    if (counters.files > 200 || counters.bytes > 5 * 1024 * 1024) {
      throw new Error('Skill import exceeds size limits');
    }
    await fs.writeFile(targetPath, buffer);
  }
}

/**
 * Recursively read a directory
 */
async function readDirRecursive(
  dirPath: string,
  depth: number = 0,
  maxDepth: number = 3
): Promise<FileEntry[]> {
  if (depth > maxDepth) return [];

  try {
    const entries = await fs.readdir(dirPath, { withFileTypes: true });
    const files: FileEntry[] = [];

    for (const entry of entries) {
      // Skip ignored files/folders
      if (shouldIgnore(entry.name)) continue;

      const fullPath = path.join(dirPath, entry.name);
      const isDirectory = entry.isDirectory();

      const file: FileEntry = {
        name: entry.name,
        path: fullPath,
        isDir: isDirectory,
      };

      // Recursively read subdirectories
      if (isDirectory && depth < maxDepth) {
        try {
          file.children = await readDirRecursive(fullPath, depth + 1, maxDepth);
        } catch {
          file.children = [];
        }
      }

      files.push(file);
    }

    // Sort: directories first, then by name
    return files.sort((a, b) => {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.name.localeCompare(b.name);
    });
  } catch (err) {
    console.error(`[Files API] Failed to read ${dirPath}:`, err);
    return [];
  }
}

/**
 * Read directory contents recursively
 * POST /files/readdir
 * Body: { path: string, maxDepth?: number }
 */
files.post('/readdir', async (c) => {
  try {
    const body = await c.req.json<{
      path: string;
      maxDepth?: number;
    }>();

    const { path: dirPath, maxDepth = 3 } = body;

    if (!dirPath) {
      return c.json({ error: 'Path is required' }, 400);
    }

    // Security check: only allow reading from home directory
    const homedir = getHomeDir();
    const tempDir = process.platform === 'win32'
      ? (process.env.TEMP || process.env.TMP || 'C:\\Windows\\Temp')
      : '/tmp';
    const normalizedPath = process.platform === 'win32' ? dirPath.toLowerCase() : dirPath;
    const normalizedHome = process.platform === 'win32' ? homedir.toLowerCase() : homedir;
    const normalizedTemp = process.platform === 'win32' ? tempDir.toLowerCase() : tempDir;

    if (!normalizedPath.startsWith(normalizedHome) && !normalizedPath.startsWith(normalizedTemp)) {
      return c.json(
        { error: 'Access denied: path must be within home directory' },
        403
      );
    }

    // Check if directory exists
    try {
      const stat = await fs.stat(dirPath);
      if (!stat.isDirectory()) {
        return c.json({ success: false, error: 'Path is not a directory', files: [] }, 400);
      }
    } catch {
      return c.json({ success: false, error: 'Directory does not exist', files: [] }, 200);
    }

    const files = await readDirRecursive(dirPath, 0, maxDepth);

    return c.json({
      success: true,
      path: dirPath,
      files,
    });
  } catch (error) {
    console.error('[Files API] Error:', error);
    return c.json(
      {
        success: false,
        error: error instanceof Error ? error.message : String(error),
        files: [],
      },
      500
    );
  }
});

/**
 * Check if a path exists and get its type
 * POST /files/stat
 * Body: { path: string }
 */
files.post('/stat', async (c) => {
  try {
    const body = await c.req.json<{ path: string }>();
    const { path: filePath } = body;

    if (!filePath) {
      return c.json({ error: 'Path is required' }, 400);
    }

    try {
      const stat = await fs.stat(filePath);
      return c.json({
        exists: true,
        isFile: stat.isFile(),
        isDirectory: stat.isDirectory(),
        size: stat.size,
        mtime: stat.mtime.toISOString(),
      });
    } catch {
      return c.json({ exists: false });
    }
  } catch (error) {
    return c.json(
      {
        error: error instanceof Error ? error.message : String(error),
      },
      500
    );
  }
});

/**
 * Read file contents
 * POST /files/read
 * Body: { path: string }
 */
files.post('/read', async (c) => {
  try {
    const body = await c.req.json<{ path: string }>();
    const { path: filePath } = body;

    if (!filePath) {
      return c.json({ error: 'Path is required' }, 400);
    }

    // Security check
    const homedir = getHomeDir();
    const tempDir = process.platform === 'win32'
      ? (process.env.TEMP || process.env.TMP || 'C:\\Windows\\Temp')
      : '/tmp';
    const normalizedPath = process.platform === 'win32' ? filePath.toLowerCase() : filePath;
    const normalizedHome = process.platform === 'win32' ? homedir.toLowerCase() : homedir;
    const normalizedTemp = process.platform === 'win32' ? tempDir.toLowerCase() : tempDir;

    if (!normalizedPath.startsWith(normalizedHome) && !normalizedPath.startsWith(normalizedTemp)) {
      // Note: In sandbox, homedir is already restricted to ~/Library/Containers/{app-id}/Data/
      return c.json({ error: 'Access denied - path outside app sandbox' }, 403);
    }

    const content = await fs.readFile(filePath, 'utf-8');
    return c.json({
      success: true,
      content,
    });
  } catch (error) {
    return c.json(
      {
        success: false,
        error: error instanceof Error ? error.message : String(error),
      },
      500
    );
  }
});

/**
 * Get all skills directories
 * GET /files/skills-dir
 * Returns paths for both ~/.sage/skills and ~/.claude/skills
 */
files.get('/skills-dir', async (c) => {
  const inSandbox = isRunningInSandbox();
  const allSkillsDirs = getAllSkillsDirs();
  
  // Filter out Claude Code skills if in sandbox
  const skillsDirs = inSandbox
    ? allSkillsDirs.filter((dir) => dir.name !== 'claude')
    : allSkillsDirs;

  const results: { name: string; path: string; exists: boolean; sandboxRestricted?: boolean }[] = [];

  for (const dir of skillsDirs) {
    try {
      const stat = await fs.stat(dir.path);
      if (stat.isDirectory()) {
        results.push({ name: dir.name, path: dir.path, exists: true });
      } else {
        results.push({ name: dir.name, path: dir.path, exists: false });
      }
    } catch {
      // Directory doesn't exist
      if (dir.name !== 'claude') {
        // Try to create app (sage) skills dir
        try {
          await fs.mkdir(dir.path, { recursive: true });
          results.push({ name: dir.name, path: dir.path, exists: true });
        } catch {
          results.push({ name: dir.name, path: dir.path, exists: false });
        }
      } else {
        // For system directories like claude, just mark as not existing
        results.push({ name: dir.name, path: dir.path, exists: false });
      }
    }
  }

  // Add a note if Claude skills were skipped due to sandbox
  if (inSandbox) {
    results.push({
      name: 'claude',
      path: 'N/A',
      exists: false,
      sandboxRestricted: true,
    });
  }

  // Return first existing directory for backward compatibility
  const firstExisting = results.find((r) => r.exists);
  return c.json({
    path: firstExisting?.path || '',
    exists: !!firstExisting,
    directories: results,
    inSandbox,
  });
});

/**
 * Import a public GitHub repository or subdirectory as a skill.
 * POST /files/import-skill
 * Body: { url: "https://github.com/owner/repo[/tree/ref/path]", targetDir?: string }
 */
files.post('/import-skill', async (c) => {
  try {
    const body = await c.req.json<GitHubImportRequest>();
    if (!body.url) {
      return c.json({ success: false, error: 'URL is required' }, 400);
    }

    const targetRoot = assertAllowedSkillTarget(body.targetDir);
    const { owner, repo, ref, path: requestedPath } = parseGitHubUrl(body.url);
    const skillPath =
      requestedPath ??
      (await findSkillDirectory(owner, repo, '', ref)) ??
      '';

    const skillItems = await fetchGitHubContents(owner, repo, skillPath, ref);
    if (!skillItems.some((item) => item.type === 'file' && item.name === 'SKILL.md')) {
      return c.json(
        { success: false, error: 'No SKILL.md found in repository path' },
        400
      );
    }

    const installName = safeSkillDirName(
      skillPath.split('/').filter(Boolean).pop() || repo
    );
    const installDir = path.join(targetRoot, installName);
    const relativeInstall = path.relative(targetRoot, installDir);
    if (relativeInstall.startsWith('..') || path.isAbsolute(relativeInstall)) {
      return c.json({ success: false, error: 'Unsafe install path' }, 400);
    }

    const counters = { files: 0, bytes: 0 };
    await copyGitHubDirectory(owner, repo, skillPath, ref, installDir, counters);

    return c.json({
      success: true,
      path: installDir,
      files: counters.files,
      bytes: counters.bytes,
    });
  } catch (error) {
    return c.json(
      {
        success: false,
        error: error instanceof Error ? error.message : String(error),
      },
      500
    );
  }
});

/**
 * Read file as binary (base64)
 * POST /files/read-binary
 * Body: { path: string }
 */
files.post('/read-binary', async (c) => {
  try {
    const body = await c.req.json<{ path: string }>();
    const { path: filePath } = body;

    if (!filePath) {
      return c.json({ error: 'Path is required' }, 400);
    }

    // Security check
    const homedir = getHomeDir();
    const tempDir = process.platform === 'win32'
      ? (process.env.TEMP || process.env.TMP || 'C:\\Windows\\Temp')
      : '/tmp';
    const normalizedPath = process.platform === 'win32' ? filePath.toLowerCase() : filePath;
    const normalizedHome = process.platform === 'win32' ? homedir.toLowerCase() : homedir;
    const normalizedTemp = process.platform === 'win32' ? tempDir.toLowerCase() : tempDir;

    if (!normalizedPath.startsWith(normalizedHome) && !normalizedPath.startsWith(normalizedTemp)) {
      // Note: In sandbox, homedir is already restricted to ~/Library/Containers/{app-id}/Data/
      return c.json({ error: 'Access denied - path outside app sandbox' }, 403);
    }

    // Check if file exists
    try {
      const stat = await fs.stat(filePath);
      if (!stat.isFile()) {
        return c.json({ error: 'Path is not a file' }, 400);
      }
    } catch {
      return c.json({ error: 'File does not exist' }, 404);
    }

    const content = await fs.readFile(filePath);
    const base64 = content.toString('base64');
    const fileName = path.basename(filePath);

    return c.json({
      success: true,
      fileName,
      content: base64,
      size: content.length,
    });
  } catch (error) {
    return c.json(
      {
        success: false,
        error: error instanceof Error ? error.message : String(error),
      },
      500
    );
  }
});

/**
 * Detect available code editors
 * GET /files/detect-editor
 */
files.get('/detect-editor', async (c) => {
  const platform = process.platform;

  // Common editors to check (in priority order)
  const editors = [
    {
      name: 'Cursor',
      command: 'cursor',
      check: platform === 'darwin' ? 'cursor' : 'cursor.cmd',
    },
    {
      name: 'VS Code',
      command: 'code',
      check: platform === 'darwin' ? 'code' : 'code.cmd',
    },
    {
      name: 'VS Code Insiders',
      command: 'code-insiders',
      check: 'code-insiders',
    },
    {
      name: 'Sublime Text',
      command: platform === 'darwin' ? 'subl' : 'subl',
      check: 'subl',
    },
    { name: 'Atom', command: 'atom', check: 'atom' },
    { name: 'WebStorm', command: 'webstorm', check: 'webstorm' },
    { name: 'PyCharm', command: 'pycharm', check: 'pycharm' },
  ];

  for (const editor of editors) {
    try {
      // Check if editor command exists
      const checkCmd =
        platform === 'win32'
          ? `where ${editor.check}`
          : `which ${editor.check}`;
      await execAsync(checkCmd);
      return c.json({
        success: true,
        editor: editor.name,
        command: editor.command,
      });
    } catch {
      // Editor not found, try next
      continue;
    }
  }

  // No editor found, will use system default
  return c.json({
    success: true,
    editor: 'Default Editor',
    command: null,
  });
});

/**
 * Open a file in code editor
 * POST /files/open-in-editor
 * Body: { path: string }
 */
files.post('/open-in-editor', async (c) => {
  try {
    const body = await c.req.json<{ path: string }>();
    const { path: filePath } = body;

    if (!filePath) {
      return c.json({ error: 'Path is required' }, 400);
    }

    // Security check
    const homedir = getHomeDir();
    const tempDir = process.platform === 'win32'
      ? (process.env.TEMP || process.env.TMP || 'C:\\Windows\\Temp')
      : '/tmp';
    const normalizedPath = process.platform === 'win32' ? filePath.toLowerCase() : filePath;
    const normalizedHome = process.platform === 'win32' ? homedir.toLowerCase() : homedir;
    const normalizedTemp = process.platform === 'win32' ? tempDir.toLowerCase() : tempDir;

    if (!normalizedPath.startsWith(normalizedHome) && !normalizedPath.startsWith(normalizedTemp)) {
      // Note: In sandbox, homedir is already restricted to ~/Library/Containers/{app-id}/Data/
      return c.json({ error: 'Access denied - path outside app sandbox' }, 403);
    }

    // Check if file exists
    try {
      await fs.stat(filePath);
    } catch {
      return c.json({ error: 'File does not exist' }, 404);
    }

    const platform = process.platform;

    // Try to find an editor
    const editors = [
      { name: 'Cursor', command: 'cursor' },
      { name: 'VS Code', command: 'code' },
      { name: 'VS Code Insiders', command: 'code-insiders' },
      { name: 'Sublime Text', command: 'subl' },
    ];

    let editorCommand: string | null = null;
    let editorName = 'Default Editor';

    for (const editor of editors) {
      try {
        const checkCmd =
          platform === 'win32'
            ? `where ${editor.command}`
            : `which ${editor.command}`;
        await execAsync(checkCmd);
        editorCommand = editor.command;
        editorName = editor.name;
        break;
      } catch {
        continue;
      }
    }

    console.log(`[Files API] Opening in editor (${editorName}): ${filePath}`);

    try {
      if (editorCommand) {
        if (platform === 'win32') {
          await execAsync(`${editorCommand} "${filePath}"`, { shell: 'cmd.exe' });
        } else {
          await execAsync(`${editorCommand} "${filePath}"`);
        }
      } else {
        // Fallback to system default
        if (platform === 'darwin') {
          await execAsync(`open -t "${filePath}"`);
        } else if (platform === 'win32') {
          const escapedPath = filePath.replace(/"/g, '""');
          await execAsync(`cmd /c start "" "${escapedPath}"`, { shell: 'cmd.exe' });
        } else {
          await execAsync(`xdg-open "${filePath}"`);
        }
      }
      return c.json({ success: true, editor: editorName });
    } catch (execError) {
      console.error('[Files API] Failed to open in editor:', execError);
      return c.json({ success: false, error: String(execError) }, 500);
    }
  } catch (error) {
    console.error('[Files API] Error:', error);
    return c.json(
      {
        success: false,
        error: error instanceof Error ? error.message : String(error),
      },
      500
    );
  }
});

/**
 * Open a file with system default application
 * POST /files/open
 * Body: { path: string }
 */
files.post('/open', async (c) => {
  try {
    const body = await c.req.json<{ path: string }>();
    let { path: filePath } = body;

    if (!filePath) {
      return c.json({ error: 'Path is required' }, 400);
    }

    // Expand ~ to home directory (handles both ~/path and ~\path)
    const homedir = getHomeDir();
    if (filePath.startsWith('~/') || filePath.startsWith('~\\')) {
      filePath = filePath.replace(/^~/, homedir);
    } else if (filePath === '~') {
      filePath = homedir;
    }

    // Normalize path separators for current platform
    if (process.platform === 'win32') {
      filePath = filePath.replace(/\//g, '\\');
    }

    // Security check: only allow opening files from home directory or temp directory
    const tempDir = process.platform === 'win32'
      ? (process.env.TEMP || process.env.TMP || 'C:\\Windows\\Temp')
      : '/tmp';

    // Normalize paths for comparison (case-insensitive on Windows)
    const normalizedPath = process.platform === 'win32' ? filePath.toLowerCase() : filePath;
    const normalizedHome = process.platform === 'win32' ? homedir.toLowerCase() : homedir;
    const normalizedTemp = process.platform === 'win32' ? tempDir.toLowerCase() : tempDir;

    if (!normalizedPath.startsWith(normalizedHome) && !normalizedPath.startsWith(normalizedTemp)) {
      return c.json(
        { error: 'Access denied: path must be within home directory' },
        403
      );
    }

    // Check if file/directory exists
    let isDirectory = false;
    try {
      const stat = await fs.stat(filePath);
      isDirectory = stat.isDirectory();
    } catch {
      return c.json({ error: 'File does not exist' }, 404);
    }

    // Open file with system default application
    const platform = process.platform;

    console.log(`[Files API] Opening ${isDirectory ? 'directory' : 'file'}: ${filePath}`);

    try {
      if (platform === 'darwin') {
        // macOS
        await execAsync(`open "${filePath}"`);
      } else if (platform === 'win32') {
        // Windows - use explorer.exe for directories, start for files
        if (isDirectory) {
          // Use explorer to open directories
          await execAsync(`explorer "${filePath}"`, { shell: 'cmd.exe' });
        } else {
          // Use start command with cmd /c for files
          // Escape path properly for Windows cmd
          const escapedPath = filePath.replace(/"/g, '""');
          await execAsync(`cmd /c start "" "${escapedPath}"`, { shell: 'cmd.exe' });
        }
      } else {
        // Linux
        await execAsync(`xdg-open "${filePath}"`);
      }
      console.log('[Files API] Opened successfully');
      return c.json({ success: true });
    } catch (execError) {
      console.error('[Files API] Failed to open:', execError);
      return c.json({ success: false, error: String(execError) }, 500);
    }
  } catch (error) {
    console.error('[Files API] Error:', error);
    return c.json(
      {
        success: false,
        error: error instanceof Error ? error.message : String(error),
      },
      500
    );
  }
});

export { files as filesRoutes };
