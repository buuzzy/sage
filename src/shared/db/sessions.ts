/**
 * Session CRUD operations.
 */

import { markSessionDirty } from '@/shared/sync/session-dirty-queue';

import { getIndexedDB, getSQLiteDatabase, idbRequest } from './database';
import type { CreateSessionInput, Session, Task } from './types';

export async function createSession(
  input: CreateSessionInput
): Promise<Session> {
  const now = new Date().toISOString();
  const session: Session = {
    id: input.id,
    prompt: input.prompt,
    task_count: 0,
    created_at: now,
    updated_at: now,
  };

  const database = await getSQLiteDatabase();

  if (database) {
    // SQLite (Tauri) - sessions table may not exist in older DBs
    try {
      await database.execute(
        'INSERT INTO sessions (id, prompt, task_count) VALUES ($1, $2, $3)',
        [input.id, input.prompt, 0]
      );
    } catch {
      // If sessions table doesn't exist, create it first
      await database.execute(`
        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY NOT NULL,
          prompt TEXT NOT NULL,
          task_count INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      `);
      await database.execute(
        'INSERT INTO sessions (id, prompt, task_count) VALUES ($1, $2, $3)',
        [input.id, input.prompt, 0]
      );
    }
    markSessionDirty(input.id);
    return session;
  } else {
    // IndexedDB (Browser)
    const db = await getIndexedDB();
    const tx = db.transaction('sessions', 'readwrite');
    const store = tx.objectStore('sessions');
    await idbRequest(store.put(session));
    console.log('[IDB] Created session:', input.id);
    markSessionDirty(input.id);
    return session;
  }
}

export async function getSession(id: string): Promise<Session | null> {
  const database = await getSQLiteDatabase();

  if (database) {
    try {
      const result = await database.select<Session[]>(
        'SELECT * FROM sessions WHERE id = $1',
        [id]
      );
      return result[0] || null;
    } catch {
      return null;
    }
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('sessions', 'readonly');
    const store = tx.objectStore('sessions');
    const result = await idbRequest(store.get(id));
    return result || null;
  }
}

export async function getAllSessions(): Promise<Session[]> {
  const database = await getSQLiteDatabase();

  if (database) {
    try {
      const sessions = await database.select<Session[]>(
        'SELECT * FROM sessions ORDER BY created_at DESC'
      );
      return sessions;
    } catch {
      return [];
    }
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('sessions', 'readonly');
    const store = tx.objectStore('sessions');
    const sessions = await idbRequest(store.getAll());
    return sessions.sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    );
  }
}

export async function updateSessionTaskCount(
  sessionId: string,
  taskCount: number
): Promise<void> {
  const database = await getSQLiteDatabase();

  if (database) {
    try {
      await database.execute(
        "UPDATE sessions SET task_count = $1, updated_at = datetime('now') WHERE id = $2",
        [taskCount, sessionId]
      );
    } catch {
      // Session table may not exist
    }
  } else {
    const db = await getIndexedDB();
    const session = await getSession(sessionId);
    if (session) {
      const updatedSession = {
        ...session,
        task_count: taskCount,
        updated_at: new Date().toISOString(),
      };
      const tx = db.transaction('sessions', 'readwrite');
      const store = tx.objectStore('sessions');
      await idbRequest(store.put(updatedSession));
    }
  }
  markSessionDirty(sessionId);
}

export async function getTasksBySessionId(sessionId: string): Promise<Task[]> {
  const database = await getSQLiteDatabase();

  if (database) {
    try {
      const tasks = await database.select<Task[]>(
        'SELECT * FROM tasks WHERE session_id = $1 ORDER BY task_index ASC',
        [sessionId]
      );
      // Convert favorite from 0/1 to boolean for all tasks
      return tasks.map((task) => ({
        ...task,
        favorite: task.favorite !== undefined ? Boolean(task.favorite) : false,
      }));
    } catch {
      // session_id column may not exist in older DBs
      return [];
    }
  } else {
    const db = await getIndexedDB();
    const tx = db.transaction('tasks', 'readonly');
    const store = tx.objectStore('tasks');
    try {
      const index = store.index('session_id');
      const tasks = await idbRequest(index.getAll(sessionId));
      return tasks.sort((a, b) => (a.task_index || 0) - (b.task_index || 0));
    } catch {
      // Index may not exist
      return [];
    }
  }
}

// ============ Task Operations ============
