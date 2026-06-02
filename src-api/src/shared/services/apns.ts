import { createSign } from 'node:crypto';
import http2 from 'node:http2';

import type { SupabaseClient } from '@supabase/supabase-js';

import type { IdeaNote } from '@/shared/services/mobile-actions';

interface DeviceTokenRow {
  token: string;
  environment: string | null;
}

interface ApnsPayload {
  aps: {
    alert: {
      title: string;
      body: string;
    };
    sound: string;
    badge?: number;
  };
  type: 'price_watch_triggered';
  noteId: string;
  action: 'confirm_order';
}

function base64Url(input: Buffer | string): string {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function apnsPrivateKey(): string | null {
  const raw = process.env.APNS_PRIVATE_KEY;
  if (!raw) return null;
  return raw.includes('\\n') ? raw.replace(/\\n/g, '\n') : raw;
}

function apnsJwt(): string | null {
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const privateKey = apnsPrivateKey();
  if (!keyId || !teamId || !privateKey) return null;

  const header = base64Url(JSON.stringify({ alg: 'ES256', kid: keyId }));
  const claims = base64Url(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }));
  const signingInput = `${header}.${claims}`;
  const signature = createSign('sha256')
    .update(signingInput)
    .sign({ key: privateKey, dsaEncoding: 'ieee-p1363' });
  return `${signingInput}.${base64Url(signature)}`;
}

function triggerBody(note: IdeaNote): string {
  const condition = note.condition;
  const verb = condition?.op === 'gte' ? '涨到' : '回调到';
  const price = condition ? `${condition.price}` : '目标价';
  const intent = note.intent || '操作';
  return `${note.symbol || '标的'}${verb} ${price}，是否${intent}？`;
}

async function sendOne(token: string, environment: string, payload: ApnsPayload): Promise<void> {
  const bundleId = process.env.APNS_BUNDLE_ID || 'ai.sage.app';
  const jwt = apnsJwt();
  if (!jwt) throw new Error('APNs env missing: APNS_KEY_ID/APNS_TEAM_ID/APNS_PRIVATE_KEY');

  const host = environment === 'sandbox' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
  const client = http2.connect(host);

  await new Promise<void>((resolve, reject) => {
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${token}`,
      authorization: `bearer ${jwt}`,
      'apns-topic': bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
    });

    let status = 0;
    let body = '';
    req.setEncoding('utf8');
    req.on('response', (headers) => {
      status = Number(headers[':status'] ?? 0);
    });
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      client.close();
      if (status >= 200 && status < 300) resolve();
      else reject(new Error(`APNs failed (${status}): ${body.slice(0, 200)}`));
    });
    req.on('error', (err) => {
      client.close();
      reject(err);
    });
    req.end(JSON.stringify(payload));
  });
}

export async function sendPriceWatchTriggeredPush(
  db: SupabaseClient,
  userId: string,
  note: IdeaNote
): Promise<void> {
  if (process.env.SAGE_ENABLE_APNS_PUSH !== 'true') {
    console.log('[apns] Remote APNs disabled; iOS uses local notification for demo triggers');
    return;
  }

  const { data, error } = await db
    .from('mobile_device_tokens')
    .select('token, environment')
    .eq('user_id', userId)
    .eq('platform', 'ios')
    .order('last_seen_at', { ascending: false });

  if (error) {
    console.warn('[apns] Failed to list device tokens:', error.message);
    return;
  }

  const tokens = (data as DeviceTokenRow[] | null) ?? [];
  if (tokens.length === 0) {
    console.warn('[apns] No iOS device tokens registered for user:', userId);
    return;
  }

  const payload: ApnsPayload = {
    aps: {
      alert: {
        title: '价格条件已触发',
        body: triggerBody(note),
      },
      sound: 'default',
      badge: 1,
    },
    type: 'price_watch_triggered',
    noteId: note.id,
    action: 'confirm_order',
  };

  const results = await Promise.allSettled(
    tokens.map((row) => sendOne(row.token, row.environment === 'sandbox' ? 'sandbox' : 'production', payload))
  );
  const rejected = results.filter((result) => result.status === 'rejected');
  if (rejected.length > 0) {
    for (const result of rejected) {
      console.warn(
        '[apns] Push failed:',
        result.status === 'rejected' && result.reason instanceof Error ? result.reason.message : result
      );
    }
  } else {
    console.log('[apns] Price watch push sent:', { userId, noteId: note.id, devices: tokens.length });
  }
}
