import {
  importBackupData,
  type BackupImportResult,
} from '@/shared/db/database';
import { supabase } from '@/shared/lib/supabase';

interface CloudSessionRow {
  id: string;
  title?: string | null;
  preview?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  message_count?: number | null;
}

interface RestoreCloudConversationsResult extends BackupImportResult {
  cloudSessions: number;
}

export async function restoreCloudConversations(): Promise<RestoreCloudConversationsResult> {
  const [{ data: sessions, error: sessionsError }, { data: tasks, error: tasksError }] =
    await Promise.all([
      supabase.from('sessions').select('*').order('updated_at', {
        ascending: false,
      }),
      supabase.from('tasks').select('*').order('created_at', {
        ascending: true,
      }),
    ]);

  if (sessionsError) {
    throw new Error(`Failed to fetch cloud sessions: ${sessionsError.message}`);
  }
  if (tasksError) {
    throw new Error(`Failed to fetch cloud tasks: ${tasksError.message}`);
  }

  const [{ data: messages, error: messagesError }, { data: files, error: filesError }] =
    await Promise.all([
      supabase.from('messages').select('*').order('created_at', {
        ascending: true,
      }),
      supabase.from('files').select('*').order('created_at', {
        ascending: true,
      }),
    ]);

  if (messagesError) {
    throw new Error(`Failed to fetch cloud messages: ${messagesError.message}`);
  }
  if (filesError) {
    throw new Error(`Failed to fetch cloud files: ${filesError.message}`);
  }

  const normalizedSessions = ((sessions ?? []) as CloudSessionRow[]).map(
    (session) => ({
      id: session.id,
      prompt: session.title || session.preview || session.id,
      task_count: session.message_count ?? 0,
      created_at: session.created_at ?? session.updated_at,
      updated_at: session.updated_at ?? session.created_at,
    })
  );

  const result = await importBackupData({
    sessions: normalizedSessions,
    tasks: tasks ?? [],
    messages: messages ?? [],
    files: files ?? [],
  });

  return {
    ...result,
    cloudSessions: normalizedSessions.length,
  };
}
