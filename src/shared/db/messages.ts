/**
 * Message CRUD operations + backup import.
 */

import { enqueueUserBehavior } from '@/shared/sync/behavior-sync';
import { enqueueMessageInsert } from '@/shared/sync/messages-sync';
import { markSessionDirty } from '@/shared/sync/session-dirty-queue';
import { uuidv7 } from 'uuidv7';

import type { BackupImportData, BackupImportResult } from './database';
import {
  asRecord,
  currentUid,
  getIndexedDB,
  getSQLiteDatabase,
  idbRequest,
  isTauriSync,
  nullableJsonString,
  nullableStr,
  str,
} from './database';
import { getTask, updateTask } from './tasks';
import type {
  CreateMessageInput,
  LibraryFile,
  Message,
  Session,
  Task,
} from './types';

export async function createMessage(
  input: CreateMessageInput
): Promise<Message> {
  // Phase 1: 客户端生成 UUID v7，作为本地 + 云端共用的全局唯一 id
  // 跨设备同步时无需 ID 映射，对索引友好（时间戳前缀使 B-tree 顺序写入）
  const id = uuidv7();
  const now = new Date().toISOString();

  // user_id 必须存在 —— 双写云端时 RLS 用它隔离
  const userId = currentUid;
  if (!userId) {
    throw new Error(
      '[DB] createMessage called without bound user. AuthProvider must bindUserId() before any DB ops.'
    );
  }

  const message: Message = {
    id,
    user_id: userId,
    task_id: input.task_id,
    type: input.type,
    content: input.content ?? null,
    tool_name: input.tool_name ?? null,
    tool_input: input.tool_input ?? null,
    tool_output: input.tool_output ?? null,
    tool_use_id: input.tool_use_id ?? null,
    tool_metadata: input.tool_metadata ?? null,
    subtype: input.subtype ?? null,
    error_message: input.error_message ?? null,
    attachments: input.attachments ?? null,
    created_at: now,
    updated_at: now,
  };

  const database = await getSQLiteDatabase();

  if (database) {
    await database.execute(
      `INSERT INTO messages
       (id, user_id, task_id, type, content, tool_name, tool_input, tool_output,
        tool_use_id, tool_metadata, subtype, error_message, attachments, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
      [
        message.id,
        message.user_id,
        message.task_id,
        message.type,
        message.content,
        message.tool_name,
        message.tool_input,
        message.tool_output,
        message.tool_use_id,
        message.tool_metadata,
        message.subtype,
        message.error_message,
        message.attachments,
        message.created_at,
        message.updated_at,
      ]
    );
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('messages', 'readwrite');
    const store = tx.objectStore('messages');
    await idbRequest(store.add(message));
  }

  // Phase 1: 火忘式双写，不阻塞当前调用
  enqueueMessageInsert(message);
  // Phase 4 / L4-light: user message 同步打点到 user_behavior（非 user 自动跳过）
  enqueueUserBehavior(message);

  // Mark parent session dirty (preview / message_count / updated_at 都可能变)
  try {
    const task = await getTask(input.task_id);
    if (task?.session_id) markSessionDirty(task.session_id);
  } catch {
    /* best effort */
  }

  return message;
}

export async function importBackupData(
  data: BackupImportData
): Promise<BackupImportResult> {
  const userId = currentUid;
  if (!userId) {
    throw new Error(
      '[DB] importBackupData called without bound user. Please sign in first.'
    );
  }

  const sessions = Array.isArray(data.sessions) ? data.sessions : [];
  const tasks = Array.isArray(data.tasks) ? data.tasks : [];
  const messages = Array.isArray(data.messages) ? data.messages : [];
  const files = Array.isArray(data.files) ? data.files : [];
  const now = new Date().toISOString();
  const result: BackupImportResult = {
    sessions: 0,
    tasks: 0,
    messages: 0,
    files: 0,
  };

  const database = await getSQLiteDatabase();

  if (database) {
    for (const raw of sessions) {
      const row = asRecord(raw);
      if (!row?.id) continue;
      await database.execute(
        `INSERT OR REPLACE INTO sessions (id, prompt, task_count, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5)`,
        [
          str(row.id),
          str(row.prompt),
          Number(row.task_count ?? 0),
          str(row.created_at, now),
          str(row.updated_at, now),
        ]
      );
      result.sessions++;
    }

    for (const raw of tasks) {
      const row = asRecord(raw);
      if (!row?.id || !row?.session_id) continue;
      await database.execute(
        `INSERT OR REPLACE INTO tasks
         (id, session_id, task_index, prompt, status, cost, duration, provider_usage, favorite, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
        [
          str(row.id),
          str(row.session_id),
          Number(row.task_index ?? 1),
          str(row.prompt),
          str(row.status, 'completed'),
          row.cost ?? null,
          row.duration ?? null,
          nullableJsonString(row.provider_usage),
          row.favorite ? 1 : 0,
          str(row.created_at, now),
          str(row.updated_at, now),
        ]
      );
      result.tasks++;
    }

    for (const raw of messages) {
      const row = asRecord(raw);
      if (!row?.id || !row?.task_id || !row?.type) continue;
      await database.execute(
        `INSERT OR REPLACE INTO messages
         (id, user_id, task_id, type, content, tool_name, tool_input, tool_output,
          tool_use_id, tool_metadata, subtype, error_message, attachments, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
        [
          str(row.id),
          userId,
          str(row.task_id),
          str(row.type),
          nullableStr(row.content),
          nullableStr(row.tool_name),
          nullableStr(row.tool_input),
          nullableStr(row.tool_output),
          nullableStr(row.tool_use_id),
          nullableStr(row.tool_metadata),
          nullableStr(row.subtype),
          nullableStr(row.error_message),
          nullableStr(row.attachments),
          str(row.created_at, now),
          str(row.updated_at, now),
        ]
      );
      result.messages++;
    }

    for (const raw of files) {
      const row = asRecord(raw);
      if (!row?.id || !row?.task_id || !row?.name || !row?.path) continue;
      await database.execute(
        `INSERT OR REPLACE INTO files
         (id, user_id, task_id, name, type, path, preview, thumbnail, is_favorite, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
        [
          str(row.id),
          userId,
          str(row.task_id),
          str(row.name),
          str(row.type, 'document'),
          str(row.path),
          nullableStr(row.preview),
          nullableStr(row.thumbnail),
          row.is_favorite ? 1 : 0,
          str(row.created_at, now),
          str(row.updated_at, now),
        ]
      );
      result.files++;
    }

    return result;
  }

  const db = await getIndexedDB();
  const tx = db.transaction(
    ['sessions', 'tasks', 'messages', 'files'],
    'readwrite'
  );
  const sessionStore = tx.objectStore('sessions');
  const taskStore = tx.objectStore('tasks');
  const messageStore = tx.objectStore('messages');
  const fileStore = tx.objectStore('files');

  for (const raw of sessions) {
    const row = asRecord(raw);
    if (!row?.id) continue;
    await idbRequest(
      sessionStore.put({
        id: str(row.id),
        prompt: str(row.prompt),
        task_count: Number(row.task_count ?? 0),
        created_at: str(row.created_at, now),
        updated_at: str(row.updated_at, now),
      } satisfies Session)
    );
    result.sessions++;
  }

  for (const raw of tasks) {
    const row = asRecord(raw);
    if (!row?.id || !row?.session_id) continue;
    await idbRequest(
      taskStore.put({
        id: str(row.id),
        session_id: str(row.session_id),
        task_index: Number(row.task_index ?? 1),
        prompt: str(row.prompt),
        status: str(row.status, 'completed') as Task['status'],
        cost: typeof row.cost === 'number' ? row.cost : null,
        duration: typeof row.duration === 'number' ? row.duration : null,
        provider_usage: nullableJsonString(row.provider_usage),
        favorite: Boolean(row.favorite),
        created_at: str(row.created_at, now),
        updated_at: str(row.updated_at, now),
      } satisfies Task)
    );
    result.tasks++;
  }

  for (const raw of messages) {
    const row = asRecord(raw);
    if (!row?.id || !row?.task_id || !row?.type) continue;
    await idbRequest(
      messageStore.put({
        id: str(row.id),
        user_id: userId,
        task_id: str(row.task_id),
        type: str(row.type) as Message['type'],
        content: nullableStr(row.content),
        tool_name: nullableStr(row.tool_name),
        tool_input: nullableStr(row.tool_input),
        tool_output: nullableStr(row.tool_output),
        tool_use_id: nullableStr(row.tool_use_id),
        tool_metadata: nullableStr(row.tool_metadata),
        subtype: nullableStr(row.subtype),
        error_message: nullableStr(row.error_message),
        attachments: nullableStr(row.attachments),
        created_at: str(row.created_at, now),
        updated_at: str(row.updated_at, now),
      } satisfies Message)
    );
    result.messages++;
  }

  for (const raw of files) {
    const row = asRecord(raw);
    if (!row?.id || !row?.task_id || !row?.name || !row?.path) continue;
    await idbRequest(
      fileStore.put({
        id: str(row.id),
        user_id: userId,
        task_id: str(row.task_id),
        name: str(row.name),
        type: str(row.type, 'document') as LibraryFile['type'],
        path: str(row.path),
        preview: nullableStr(row.preview),
        thumbnail: nullableStr(row.thumbnail),
        is_favorite: Boolean(row.is_favorite),
        created_at: str(row.created_at, now),
        updated_at: str(row.updated_at, now),
      } satisfies LibraryFile)
    );
    result.files++;
  }

  return result;
}

export async function getMessagesByTaskId(taskId: string): Promise<Message[]> {
  const database = await getSQLiteDatabase();

  if (database) {
    return database.select<Message[]>(
      'SELECT * FROM messages WHERE task_id = $1 ORDER BY created_at ASC',
      [taskId]
    );
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('messages', 'readonly');
    const store = tx.objectStore('messages');
    const index = store.index('task_id');
    const messages = await idbRequest(index.getAll(taskId));
    return messages.sort(
      (a, b) =>
        new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    );
  }
}

export async function deleteMessagesByTaskId(taskId: string): Promise<number> {
  const database = await getSQLiteDatabase();

  if (database) {
    const result = await database.execute(
      'DELETE FROM messages WHERE task_id = $1',
      [taskId]
    );
    return result.rowsAffected;
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('messages', 'readwrite');
    const store = tx.objectStore('messages');
    const index = store.index('task_id');
    const messages = await idbRequest(index.getAll(taskId));

    for (const message of messages) {
      await idbRequest(store.delete(message.id));
    }
    return messages.length;
  }
}

// Helper function to update task status based on message type
export async function updateTaskFromMessage(
  taskId: string,
  messageType: string,
  subtype?: string,
  cost?: number,
  duration?: number
): Promise<void> {
  if (messageType === 'result') {
    const provider_usage =
      cost !== undefined || duration !== undefined
        ? JSON.stringify({
            source: 'agent_result',
            cost_usd: cost ?? null,
            duration_ms: duration ?? null,
            captured_at: new Date().toISOString(),
          })
        : undefined;
    // Only mark as completed for actual success
    // error_max_turns means the task was interrupted, not completed
    // Keep it in 'running' state so user knows to continue
    if (subtype === 'success') {
      await updateTask(taskId, {
        status: 'completed',
        cost,
        duration,
        provider_usage,
      });
    } else if (subtype === 'error_max_turns') {
      // The stream has ended; do not leave the UI in a permanently running
      // state. Users can continue from the existing transcript if needed.
      await updateTask(taskId, {
        status: 'stopped',
        cost,
        duration,
        provider_usage,
      });
      console.log(
        `[Database] Task ${taskId} hit max turns limit, marking as stopped`
      );
    } else {
      // Other errors
      await updateTask(taskId, {
        status: 'error',
        cost,
        duration,
        provider_usage,
      });
    }
  } else if (messageType === 'error') {
    await updateTask(taskId, { status: 'error' });
  }
}

// Export utility to check environment
export function isDatabaseAvailable(): boolean {
  return isTauriSync();
}

// ============ Library File Operations ============
