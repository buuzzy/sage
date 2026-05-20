/**
 * Task CRUD operations.
 */

import { enqueueTaskUpsert } from '@/shared/sync/messages-sync';
import {
  markSessionDeleted,
  markSessionDirty,
} from '@/shared/sync/session-dirty-queue';

import {
  currentUid,
  getIndexedDB,
  getSQLiteDatabase,
  idbRequest,
} from './database';
import { deleteMessagesByTaskId } from './messages';
import { getTasksBySessionId, updateSessionTaskCount } from './sessions';
import type { CreateTaskInput, Task, UpdateTaskInput } from './types';

export async function createTask(input: CreateTaskInput): Promise<Task> {
  const now = new Date().toISOString();
  const task: Task = {
    id: input.id,
    session_id: input.session_id,
    task_index: input.task_index,
    prompt: input.prompt,
    status: 'running',
    cost: null,
    duration: null,
    provider_usage: null,
    created_at: now,
    updated_at: now,
  };

  const database = await getSQLiteDatabase();

  if (database) {
    // SQLite (Tauri) - Try with new schema, fallback to old
    try {
      await database.execute(
        'INSERT INTO tasks (id, session_id, task_index, prompt) VALUES ($1, $2, $3, $4)',
        [input.id, input.session_id, input.task_index, input.prompt]
      );
    } catch {
      // Fallback for older schema without session_id
      await database.execute('INSERT INTO tasks (id, prompt) VALUES ($1, $2)', [
        input.id,
        input.prompt,
      ]);
    }
    const result = await getTask(input.id);
    if (!result) throw new Error('Failed to create task');

    // Update session task count
    await updateSessionTaskCount(input.session_id, input.task_index);
    if (currentUid) enqueueTaskUpsert(result, currentUid);

    return result;
  } else {
    // IndexedDB (Browser)
    const db = await getIndexedDB();
    const tx = db.transaction('tasks', 'readwrite');
    const store = tx.objectStore('tasks');
    await idbRequest(store.put(task));
    console.log('[IDB] Created task:', input.id);

    // Update session task count
    await updateSessionTaskCount(input.session_id, input.task_index);
    if (currentUid) enqueueTaskUpsert(task, currentUid);

    return task;
  }
}

export async function getTask(id: string): Promise<Task | null> {
  const database = await getSQLiteDatabase();

  if (database) {
    const result = await database.select<Task[]>(
      'SELECT * FROM tasks WHERE id = $1',
      [id]
    );
    const task = result[0] || null;
    // Convert favorite from 0/1 to boolean
    if (task && task.favorite !== undefined) {
      task.favorite = Boolean(task.favorite);
    }
    return task;
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('tasks', 'readonly');
    const store = tx.objectStore('tasks');
    const result = await idbRequest(store.get(id));
    return result || null;
  }
}

export async function getAllTasks(): Promise<Task[]> {
  const database = await getSQLiteDatabase();

  if (database) {
    const tasks = await database.select<Task[]>(
      'SELECT * FROM tasks ORDER BY created_at DESC'
    );
    // Convert favorite from 0/1 to boolean for all tasks
    return tasks.map((task) => ({
      ...task,
      favorite: task.favorite !== undefined ? Boolean(task.favorite) : false,
    }));
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('tasks', 'readonly');
    const store = tx.objectStore('tasks');
    const tasks = await idbRequest(store.getAll());
    // Sort by created_at descending
    return tasks.sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    );
  }
}

export async function updateTask(
  id: string,
  input: UpdateTaskInput
): Promise<Task | null> {
  const database = await getSQLiteDatabase();

  let result: Task | null;
  if (database) {
    const updates: string[] = [];
    const values: (string | number | null)[] = [];
    let paramIndex = 1;

    if (input.status !== undefined) {
      updates.push(`status = $${paramIndex++}`);
      values.push(input.status);
    }
    if (input.cost !== undefined) {
      updates.push(`cost = $${paramIndex++}`);
      values.push(input.cost);
    }
    if (input.duration !== undefined) {
      updates.push(`duration = $${paramIndex++}`);
      values.push(input.duration);
    }
    if (input.provider_usage !== undefined) {
      updates.push(`provider_usage = $${paramIndex++}`);
      values.push(input.provider_usage);
    }
    if (input.prompt !== undefined) {
      updates.push(`prompt = $${paramIndex++}`);
      values.push(input.prompt);
    }
    if (input.favorite !== undefined) {
      updates.push(`favorite = $${paramIndex++}`);
      values.push(input.favorite ? 1 : 0);
    }

    if (updates.length > 0) {
      updates.push(`updated_at = datetime('now')`);
      values.push(id);
      try {
        await database.execute(
          `UPDATE tasks SET ${updates.join(', ')} WHERE id = $${paramIndex}`,
          values
        );
      } catch (error) {
        // If favorite column doesn't exist, add it and retry
        if (
          input.favorite !== undefined &&
          String(error).includes('favorite')
        ) {
          await database.execute(
            'ALTER TABLE tasks ADD COLUMN favorite INTEGER DEFAULT 0'
          );
          await database.execute(
            `UPDATE tasks SET ${updates.join(', ')} WHERE id = $${paramIndex}`,
            values
          );
        } else {
          throw error;
        }
      }
    }

    result = await getTask(id);
  } else {
    const db = await getIndexedDB();
    const task = await getTask(id);
    if (task) {
      const updatedTask = {
        ...task,
        ...input,
        updated_at: new Date().toISOString(),
      };
      const tx = db.transaction('tasks', 'readwrite');
      const store = tx.objectStore('tasks');
      await idbRequest(store.put(updatedTask));
      result = updatedTask;
    } else {
      result = null;
    }
  }

  // 影响 session 的只有 prompt（title 来源）和 status（间接通过 preview 不变，但语义上是活跃）
  if (result?.session_id) {
    if (currentUid) enqueueTaskUpsert(result, currentUid);
    markSessionDirty(result.session_id);
  }

  return result;
}

export async function deleteTask(id: string): Promise<boolean> {
  const database = await getSQLiteDatabase();

  // 先记下 session_id，删除前拿到，删除后用它来更新 task_count / 判断是否清空 session
  const task = await getTask(id);
  const sessionId = task?.session_id ?? null;

  let ok: boolean;
  if (database) {
    const result = await database.execute('DELETE FROM tasks WHERE id = $1', [
      id,
    ]);
    ok = result.rowsAffected > 0;
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('tasks', 'readwrite');
    const store = tx.objectStore('tasks');
    await idbRequest(store.delete(id));
    // Also delete related messages
    await deleteMessagesByTaskId(id);
    ok = true;
  }

  // Refresh parent session：若 session 还剩 task 则 markDirty，否则 markDeleted
  if (ok && sessionId) {
    try {
      const remaining = await getTasksBySessionId(sessionId);
      if (remaining.length === 0) {
        markSessionDeleted(sessionId);
      } else {
        markSessionDirty(sessionId);
      }
    } catch {
      /* best effort */
    }
  }

  return ok;
}

// ============ Message Operations ============
