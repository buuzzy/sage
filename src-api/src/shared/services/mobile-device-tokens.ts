import type { SupabaseClient } from '@supabase/supabase-js';

export async function upsertMobileDeviceToken(
  db: SupabaseClient,
  userId: string,
  input: {
    token: string;
    platform?: string;
    environment?: string;
    appVersion?: string;
  }
): Promise<void> {
  const token = input.token.trim();
  if (!token) throw new Error('device token is required');

  const now = new Date().toISOString();
  const id = `${input.platform ?? 'ios'}-${token}`;
  const { error } = await db
    .from('mobile_device_tokens')
    .upsert(
      {
        id,
        user_id: userId,
        platform: input.platform ?? 'ios',
        token,
        environment: input.environment === 'sandbox' ? 'sandbox' : 'production',
        app_version: input.appVersion ?? null,
        last_seen_at: now,
        updated_at: now,
      },
      { onConflict: 'user_id,token' }
    );

  if (error) {
    throw new Error(`Failed to register device token: ${error.message}`);
  }
}
