/**
 * Library file CRUD operations.
 */

import type { CreateFileInput, LibraryFile } from './types';
import { getSQLiteDatabase } from './database';

export async function createFile(input: CreateFileInput): Promise<LibraryFile> {
  // Phase 1: files 也用 UUID v7（跨设备唯一，与 messages 一致）
  const id = uuidv7();
  const now = new Date().toISOString();

  const userId = currentUid;
  if (!userId) {
    throw new Error(
      '[DB] createFile called without bound user. AuthProvider must bindUserId() before any DB ops.'
    );
  }

  const file: LibraryFile = {
    id,
    user_id: userId,
    task_id: input.task_id,
    name: input.name,
    type: input.type,
    path: input.path,
    preview: input.preview ?? null,
    thumbnail: input.thumbnail ?? null,
    is_favorite: false,
    created_at: now,
    updated_at: now,
  };

  const database = await getSQLiteDatabase();
  if (database) {
    await database.execute(
      `INSERT INTO files (id, user_id, task_id, name, type, path, preview, thumbnail, is_favorite, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
      [
        file.id,
        file.user_id,
        file.task_id,
        file.name,
        file.type,
        file.path,
        file.preview,
        file.thumbnail,
        file.is_favorite ? 1 : 0,
        file.created_at,
        file.updated_at,
      ]
    );
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('files', 'readwrite');
    const store = tx.objectStore('files');
    await idbRequest(store.add(file));
  }

  enqueueFileUpsert(file);

  // 新增 file 会让 session 的 has_artifacts 变成 true
  try {
    const task = await getTask(input.task_id);
    if (task?.session_id) markSessionDirty(task.session_id);
  } catch {
    /* best effort */
  }

  return file;
}

export async function getFilesByTaskId(taskId: string): Promise<LibraryFile[]> {
  const database = await getSQLiteDatabase();

  if (database) {
    return database.select<LibraryFile[]>(
      'SELECT * FROM files WHERE task_id = $1 ORDER BY created_at ASC',
      [taskId]
    );
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('files', 'readonly');
    const store = tx.objectStore('files');
    const index = store.index('task_id');
    const files = await idbRequest(index.getAll(taskId));
    return files.sort(
      (a, b) =>
        new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    );
  }
}

export async function getAllFiles(): Promise<LibraryFile[]> {
  const database = await getSQLiteDatabase();

  if (database) {
    return database.select<LibraryFile[]>(
      'SELECT * FROM files ORDER BY created_at DESC'
    );
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('files', 'readonly');
    const store = tx.objectStore('files');
    const files = await idbRequest(store.getAll());
    return files.sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    );
  }
}

export async function toggleFileFavorite(
  fileId: string
): Promise<LibraryFile | null> {
  const database = await getSQLiteDatabase();

  if (database) {
    await database.execute(
      "UPDATE files SET is_favorite = NOT is_favorite, updated_at = datetime('now') WHERE id = $1",
      [fileId]
    );
    const files = await database.select<LibraryFile[]>(
      'SELECT * FROM files WHERE id = $1',
      [fileId]
    );
    return files[0] || null;
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('files', 'readwrite');
    const store = tx.objectStore('files');
    const file = await idbRequest(store.get(fileId));
    if (file) {
      file.is_favorite = !file.is_favorite;
      file.updated_at = new Date().toISOString();
      await idbRequest(store.put(file));
      return file;
    }
    return null;
  }
}

export async function deleteFile(fileId: string): Promise<boolean> {
  const database = await getSQLiteDatabase();

  // 删除前记下 task_id，用于刷新对应 session 的 has_artifacts
  let taskId: string | null = null;
  try {
    if (database) {
      const rows = await database.select<{ task_id: string }[]>(
        'SELECT task_id FROM files WHERE id = $1',
        [fileId]
      );
      taskId = rows[0]?.task_id ?? null;
    } else {
      const db = await getIndexedDB();
      const tx = db.transaction('files', 'readonly');
      const store = tx.objectStore('files');
      const file = await idbRequest(store.get(fileId));
      taskId = file?.task_id ?? null;
    }
  } catch {
    /* best effort */
  }

  let ok: boolean;
  if (database) {
    const result = await database.execute('DELETE FROM files WHERE id = $1', [
      fileId,
    ]);
    ok = result.rowsAffected > 0;
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('files', 'readwrite');
    const store = tx.objectStore('files');
    await idbRequest(store.delete(fileId));
    ok = true;
  }

  if (ok && taskId) {
    try {
      const task = await getTask(taskId);
      if (task?.session_id) markSessionDirty(task.session_id);
    } catch {
      /* best effort */
    }
  }

  return ok;
}

// Get files grouped by task with task info
export async function getFilesGroupedByTask(): Promise<
  { task: Task; files: LibraryFile[] }[]
> {
  const allFiles = await getAllFiles();
  const allTasks = await getAllTasks();

  // Create a map of task_id to files
  const filesByTask = new Map<string, LibraryFile[]>();
  for (const file of allFiles) {
    const existing = filesByTask.get(file.task_id) || [];
    existing.push(file);
    filesByTask.set(file.task_id, existing);
  }

  // Build result with task info
  const result: { task: Task; files: LibraryFile[] }[] = [];
  for (const task of allTasks) {
    const files = filesByTask.get(task.id);
    if (files && files.length > 0) {
      result.push({ task, files });
    }
  }

  return result;
}

