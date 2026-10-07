/**
 * Layer 3 (sync engine) plus the client side of layer 4 (showing conflict results).
 *
 * One sync = push the queue (oldest first, in batches) then pull everything new.
 * It runs: when the connection comes back, every 5 s while online, shortly after
 * each local change, and when the user presses "Sync now".
 * If a push fails half-way, the unsent ops stay queued; ops the server already
 * applied are safe to resend because the server de-duplicates by op_id.
 */
import { Injectable, computed, effect, inject, signal, untracked } from '@angular/core';
import { API_BASE, BATCH_SIZE, DEVICE_ID, SYNC_INTERVAL_MS } from './config';
import { ConnectivityService } from './connectivity.service';
import { HistoryEntry, LocalRecord, OutboxOp, db } from './db';
import { NoticesService } from './notices.service';
import { Editable, updateLocal } from './local-writes';

interface FieldResult { outcome: 'applied' | 'merged' | 'won' | 'lost'; other_device?: string; server_value?: unknown; other_value?: unknown; }
interface OpResult {
  op_id: string; record_id: string; version?: number; error?: string;
  outcome: 'applied' | 'merged' | 'conflict' | 'duplicate' | 'rejected';
  fields?: Record<string, FieldResult>;
}
interface Change { seq: number; record_id: string; field: string; value: unknown; version: number; device_id: string; }

const FIELD_LABELS: Record<string, string> = { name: 'name', phone: 'phone number', status: 'status', deleted: 'deletion' };

@Injectable({ providedIn: 'root' })
export class SyncService {
  private conn = inject(ConnectivityService);
  private notices = inject(NoticesService);

  readonly syncing = signal(false);
  readonly lastSyncAt = signal<number | null>(null);
  readonly status = computed(() => (!this.conn.online() ? 'offline' : this.syncing() ? 'syncing' : 'online'));

  private soonTimer: ReturnType<typeof setTimeout> | undefined;

  constructor() {
    db.getMeta<number | null>('lastSyncAt', null).then((v) => this.lastSyncAt.set(v));
    // Reconnect -> sync. untracked() so this effect only reacts to connectivity, not to sync state.
    effect(() => { if (this.conn.online()) untracked(() => this.syncNow()); });
    setInterval(() => this.syncNow(), SYNC_INTERVAL_MS);
  }

  /** Called after each local change: sync shortly, batching quick edits together. */
  soon() {
    clearTimeout(this.soonTimer);
    this.soonTimer = setTimeout(() => this.syncNow(), 400);
  }

  async syncNow() {
    if (!this.conn.online() || this.syncing()) return;
    this.syncing.set(true);
    const entry: HistoryEntry = { at: Date.now(), ok: true, sent: 0, received: 0, merged: 0, conflicts: 0, duplicates: 0, message: '' };
    try {
      await this.push(entry);
      await this.pull(entry);
      const now = Date.now();
      this.lastSyncAt.set(now);
      await db.setMeta('lastSyncAt', now);
      entry.message = entry.conflicts ? 'Sync completed with conflicts'
        : entry.merged ? 'Sync completed with a merge' : 'Sync completed';
    } catch (e) {
      entry.ok = false;
      entry.message = `Sync failed: ${(e as Error).message}. Changes stay queued and will retry.`;
      this.conn.ping();
    } finally {
      // Don't fill the history with empty background syncs.
      if (!entry.ok || entry.sent || entry.received) await db.history.add(entry);
      this.syncing.set(false);
    }
  }

  /** Demo helper: resend the last batch to show the server ignores duplicates. */
  async replayLastBatch() {
    const ops = await db.getMeta<OutboxOp[]>('lastBatch', []);
    if (!ops.length) {
      this.notices.show({ kind: 'info', title: 'Nothing to replay', body: 'Make a change and let it sync first.' });
      return;
    }
    const { results } = await this.post<{ results: OpResult[] }>('/sync/push/', { device_id: DEVICE_ID, ops });
    const dupes = results.filter((r) => r.outcome === 'duplicate').length;
    await db.history.add({ at: Date.now(), ok: true, sent: ops.length, received: 0, merged: 0, conflicts: 0,
      duplicates: dupes, message: `Replayed ${ops.length} change(s): ${dupes} recognised as duplicates, nothing applied twice` });
    this.notices.show({ kind: 'info', title: 'Replay sent',
      body: `${dupes} of ${ops.length} change(s) were recognised as already applied.` });
  }

  // ---- push --------------------------------------------------------------

  private async push(entry: HistoryEntry) {
    for (;;) {
      const batch = await db.outbox.orderBy('seq').limit(BATCH_SIZE).toArray();
      if (!batch.length) return;
      const ops = batch.map(({ seq, label, attempts, ...op }) => op);
      let results: OpResult[];
      try {
        ({ results } = await this.post<{ results: OpResult[] }>('/sync/push/', { device_id: DEVICE_ID, ops }));
      } catch (e) {
        await db.outbox.bulkPut(batch.map((op) => ({ ...op, attempts: op.attempts + 1 })));
        throw e;
      }
      await db.setMeta('lastBatch', ops);
      entry.sent += batch.length;
      for (const [i, result] of results.entries()) await this.handleResult(batch[i], result, entry);
    }
  }

  private async handleResult(op: OutboxOp, r: OpResult, entry: HistoryEntry) {
    await db.transaction('rw', db.records, db.outbox, async () => {
      await db.outbox.delete(op.seq!);
      const rec = await db.records.get(op.record_id);
      if (rec && r.version) await db.records.update(rec.id, { version: Math.max(rec.version, r.version) });

      // A losing field: show the value the server kept, unless a newer local edit is still queued.
      for (const [field, fr] of Object.entries(r.fields ?? {})) {
        if (fr.outcome === 'lost' && rec && !(await this.hasPending(rec.id, field))) {
          await db.records.update(rec.id, { [field]: fr.server_value } as Partial<LocalRecord>);
        }
      }
    });

    const name = op.label;
    if (r.outcome === 'duplicate') entry.duplicates++;
    if (r.outcome === 'merged') {
      entry.merged++;
      this.notices.show({ kind: 'info', title: 'Changes merged',
        body: `${name} was also changed on another device. Both changes were kept.` });
    }
    if (r.outcome === 'rejected') {
      this.notices.show({ kind: 'error', title: 'Change rejected by the server', body: `${name}: ${r.error}` });
    }
    if (r.outcome === 'conflict') {
      entry.conflicts++;
      for (const [field, fr] of Object.entries(r.fields ?? {})) {
        const label = FIELD_LABELS[field] ?? field;
        const mine = (op.fields as Record<string, unknown>)[field];
        if (fr.outcome === 'lost') {
          this.notices.show({
            kind: 'warn', title: 'One of your edits was replaced',
            body: `You set the ${label} of ${name} to "${mine}". A newer edit from ${fr.other_device} set it to "${fr.server_value}", so that value was kept.`,
            actions: [
              { label: 'Re-enter mine', primary: true, run: () => this.reenter(op.record_id, field, mine) },
              { label: 'Keep newer', run: () => {} },
            ],
          });
        } else if (fr.outcome === 'won') {
          this.notices.show({ kind: 'info', title: 'Your edit replaced an older one',
            body: `${fr.other_device} had set the ${label} of ${name} to "${fr.other_value}". Your newer value was kept.` });
        }
      }
    }
  }

  private async reenter(recordId: string, field: string, value: unknown) {
    await updateLocal(recordId, { [field]: value } as Editable);
    this.soon();
  }

  // ---- pull --------------------------------------------------------------

  private async pull(entry: HistoryEntry) {
    let since = await db.getMeta<number>('lastSeq', 0);
    for (;;) {
      const data = await this.get<{ changes: Change[]; next_seq: number; has_more: boolean }>(
        `/sync/pull/?since=${since}&device_id=${encodeURIComponent(DEVICE_ID)}`);
      await db.transaction('rw', db.records, db.outbox, db.meta, async () => {
        for (const c of data.changes) {
          if (c.device_id !== DEVICE_ID) entry.received++;
          if (await this.hasPending(c.record_id, c.field)) continue;   // local edit not yet sent wins locally
          const rec = (await db.records.get(c.record_id)) ?? {
            id: c.record_id, name: '', phone: '', status: 'ACTIVE', deleted: false, version: 0, updatedAt: Date.now(),
          } as LocalRecord;
          await db.records.put({ ...rec, [c.field]: c.value, version: Math.max(rec.version, c.version), updatedAt: Date.now() });
        }
        await db.setMeta('lastSeq', data.next_seq);
      });
      since = data.next_seq;
      if (!data.has_more) return;
    }
  }

  private async hasPending(recordId: string, field: string) {
    const ops = await db.outbox.where('record_id').equals(recordId).toArray();
    return ops.some((o) => field in o.fields);
  }

  // ---- http --------------------------------------------------------------

  private async post<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  }

  private async get<T>(path: string): Promise<T> {
    return this.request<T>(path, { method: 'GET', cache: 'no-store' });
  }

  private async request<T>(path: string, init: RequestInit): Promise<T> {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 10_000);
    try {
      const res = await fetch(`${API_BASE}${path}`, { ...init, signal: ctrl.signal });
      if (!res.ok) throw new Error(`server returned ${res.status}`);
      return (await res.json()) as T;
    } catch (e) {
      throw new Error((e as Error).name === 'AbortError' ? 'request timed out' : (e as Error).message);
    } finally {
      clearTimeout(timer);
    }
  }
}
