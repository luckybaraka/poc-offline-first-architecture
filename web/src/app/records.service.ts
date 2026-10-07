import { Injectable, inject } from '@angular/core';
import { Status } from './db';
import { Editable, createLocal, removeLocal, updateLocal } from './local-writes';
import { SyncService } from './sync.service';

/** UI-facing actions: write locally first, then nudge the sync engine. */
@Injectable({ providedIn: 'root' })
export class RecordsService {
  private sync = inject(SyncService);

  async create(name: string, phone: string, status: Status) {
    await createLocal(name, phone, status);
    this.sync.soon();
  }

  async update(id: string, changes: Editable) {
    await updateLocal(id, changes);
    this.sync.soon();
  }

  async remove(id: string) {
    await removeLocal(id);
    this.sync.soon();
  }
}
