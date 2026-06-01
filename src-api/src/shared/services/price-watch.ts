/**
 * 条件单实时监控：扫描所有「监控中」的条件想法，用 broker 实时报价比对触发条件，
 * 命中则把监控卡转成待确认下单卡（triggerWatch）。
 *
 * 由 Railway 后台任务（service-role）周期调用。当前 broker 为富途语义 mock，报价稳定，
 * 自动触发主要演示「机制存在」；demo 现场用 iOS 的「模拟触发」按钮做即时演示。
 * 接真实富途行情后，本 sweep 即可真实自动触发，无需改动调用方。
 */

import { getBrokerAdapter } from '@/shared/broker';
import { getServiceSupabase } from '@/shared/supabase/client';
import { triggerWatch } from '@/shared/services/mobile-actions';

interface ActiveWatchRow {
  id: string;
  user_id: string;
  symbol: string | null;
  condition_op: string | null;
  condition_price: number | null;
}

function conditionMet(op: string | null, price: number, target: number | null): boolean {
  if (target == null) return false;
  if (op === 'lte') return price <= target;
  if (op === 'gte') return price >= target;
  return false;
}

export async function sweepPriceWatches(): Promise<{ checked: number; triggered: number }> {
  const db = getServiceSupabase();
  const { data, error } = await db
    .from('idea_notes')
    .select('id, user_id, symbol, condition_op, condition_price')
    .eq('task_type', 'conditional')
    .eq('watch_status', 'watching');

  if (error) {
    throw new Error(`Failed to list active watches: ${error.message}`);
  }

  const rows = (data as ActiveWatchRow[] | null) ?? [];
  const adapter = getBrokerAdapter();
  let triggered = 0;

  for (const row of rows) {
    if (!row.symbol) continue;
    const resolved = await adapter.resolveInstrument(row.symbol);
    if (!resolved) continue;
    const price = await adapter.getQuote(resolved.code);
    if (price == null) continue;

    if (conditionMet(row.condition_op, price, row.condition_price)) {
      await triggerWatch(db, row.user_id, row.id);
      triggered += 1;
    }
  }

  return { checked: rows.length, triggered };
}
