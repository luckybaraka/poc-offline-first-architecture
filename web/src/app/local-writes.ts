/**
 * Every user change goes through these functions. Each one writes the record AND its
 * queue entry in one local transaction, so the screen updates instantly and the change
 * can't be lost. The network is never touched here.
 */
import { DEVICE_ID } from './config';
import { LocalRecord, OpType, OutboxOp, Status, db } from './db';

export type Editable = Partial<Pick<LocalRecord, 'name' | 'phone' | 'status'>>;

function makeOp(type: OpType, record: LocalRecord, fields: OutboxOp['fields']): OutboxOp {
  return {
    op_id: crypto.randomUUID(),
    record_id: record.id,
    type,
    fields,
    base_version: record.version,
    device_id: DEVICE_ID,
    client_ts: Date.now(),
    label: record.name || 'Unnamed record',
    attempts: 0,
  };
}

export async function createLocal(name: string, phone: string, status: Status) {
  const record: LocalRecord = {
    id: crypto.randomUUID(), name, phone, status, deleted: false, version: 0, updatedAt: Date.now(),
  };
  await db.transaction('rw', db.records, db.outbox, async () => {
    await db.records.add(record);
    await db.outbox.add(makeOp('create', record, { name, phone, status }));
  });
}

export async function updateLocal(id: string, changes: Editable) {
  await db.transaction('rw', db.records, db.outbox, async () => {
    const current = await db.records.get(id);
    if (!current) return;
    // Delta: keep only the fields that actually changed.
    const delta: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(changes)) {
      if ((current as unknown as Record<string, unknown>)[key] !== value) delta[key] = value;
    }
    if (!Object.keys(delta).length) return;
    const updated = { ...current, ...delta, updatedAt: Date.now() } as LocalRecord;
    await db.records.put(updated);
    await db.outbox.add(makeOp('update', updated, delta as OutboxOp['fields']));
  });
}

export async function removeLocal(id: string) {
  await db.transaction('rw', db.records, db.outbox, async () => {
    const current = await db.records.get(id);
    if (!current) return;
    const updated = { ...current, deleted: true, updatedAt: Date.now() };
    await db.records.put(updated);
    await db.outbox.add(makeOp('delete', updated, { deleted: true }));
  });
}
