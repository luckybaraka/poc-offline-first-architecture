/**
 * Layer 1 (local storage) and layer 2 (operation queue), both in IndexedDB via Dexie.
 * Each device id gets its own database, so two tabs can act as two devices.
 */
import Dexie, { Table } from 'dexie';
import { DEVICE_ID } from './config';

export type Status = 'ACTIVE' | 'INACTIVE' | 'SUSPENDED';
export const STATUSES: Status[] = ['ACTIVE', 'INACTIVE', 'SUSPENDED'];

export interface LocalRecord {
  id: string;
  name: string;
  phone: string;
  status: Status;
  deleted: boolean;
  version: number;     // last server version this device knows about (0 = never synced)
  updatedAt: number;
}

export type OpType = 'create' | 'update' | 'delete';

export interface OutboxOp {
  seq?: number;        // local order; ops are pushed in this order
  op_id: string;
  record_id: string;
  type: OpType;
  fields: Partial<Pick<LocalRecord, 'name' | 'phone' | 'status' | 'deleted'>>;
  base_version: number;
  device_id: string;
  client_ts: number;
  label: string;       // record name, for the pending screen
  attempts: number;
}

export interface HistoryEntry {
  id?: number;
  at: number;
  ok: boolean;
  sent: number;
  received: number;
  merged: number;
  conflicts: number;
  duplicates: number;
  message: string;
}

export interface Meta {
  key: string;
  value: unknown;
}

class LocalDb extends Dexie {
  records!: Table<LocalRecord, string>;
  outbox!: Table<OutboxOp, number>;
  history!: Table<HistoryEntry, number>;
  meta!: Table<Meta, string>;

  constructor() {
    super(`offline-poc-${DEVICE_ID}`);
    this.version(1).stores({
      records: 'id, name',
      outbox: '++seq, record_id',
      history: '++id, at',
      meta: 'key',
    });
  }

  async getMeta<T>(key: string, fallback: T): Promise<T> {
    const row = await this.meta.get(key);
    return row ? (row.value as T) : fallback;
  }

  setMeta(key: string, value: unknown) {
    return this.meta.put({ key, value });
  }
}

export const db = new LocalDb();
