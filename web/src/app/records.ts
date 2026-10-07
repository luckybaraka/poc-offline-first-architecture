import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { LocalRecord, STATUSES, Status, db } from './db';
import { live } from './live';
import { RecordsService } from './records.service';
import { SyncService } from './sync.service';
import { ago } from './time';

/** Local-first data view: everything here is read from IndexedDB, never from the API. */
@Component({
  selector: 'app-records',
  imports: [FormsModule],
  template: `
    <div class="banner mint">
      <strong>Loaded from this device</strong>
      <span>Last synced with the server {{ ago(sync.lastSyncAt()) }}</span>
    </div>

    <form class="card add" (ngSubmit)="add()">
      <input name="name" [(ngModel)]="newName" placeholder="Patient name" required />
      <input name="phone" [(ngModel)]="newPhone" placeholder="Phone number" />
      <select name="status" [(ngModel)]="newStatus">
        @for (s of statuses; track s) { <option [value]="s">{{ s }}</option> }
      </select>
      <button class="primary" type="submit" [disabled]="!newName.trim()">Add record</button>
    </form>

    <h2>Records <span class="muted">{{ visible().length }} total</span></h2>

    @for (r of visible(); track r.id) {
      <div class="card row">
        <div class="avatar">{{ (r.name || '?')[0] }}</div>
        @if (editing() === r.id) {
          <div class="grow edit">
            <input [(ngModel)]="editName" placeholder="Name" />
            <input [(ngModel)]="editPhone" placeholder="Phone" />
          </div>
          <button class="primary" (click)="saveEdit(r)">Save</button>
          <button (click)="editing.set(null)">Cancel</button>
        } @else {
          <div class="grow">
            <div class="title">{{ r.name || 'Unnamed record' }}</div>
            <div class="muted">{{ r.phone || 'No phone' }} <span class="version">v{{ r.version }}</span></div>
          </div>
          <select class="status" [attr.data-status]="r.status" [ngModel]="r.status"
                  (ngModelChange)="setStatus(r, $event)" aria-label="Status">
            @for (s of statuses; track s) { <option [value]="s">{{ s }}</option> }
          </select>
          @if (pendingIds().has(r.id)) {
            <span class="tag amber">Waiting to sync</span>
          } @else {
            <span class="tag teal">Synced</span>
          }
          <button (click)="startEdit(r)">Edit</button>
          <button class="danger" (click)="records.remove(r.id)" aria-label="Delete">Delete</button>
        }
      </div>
    } @empty {
      <div class="empty">No records yet. Add one above. It works offline too.</div>
    }
  `,
})
export class RecordsComponent {
  protected records = inject(RecordsService);
  protected sync = inject(SyncService);
  protected statuses = STATUSES;
  protected ago = ago;

  private all = live(() => db.records.orderBy('name').toArray(), [] as LocalRecord[]);
  private outbox = live(() => db.outbox.toArray(), []);
  protected visible = computed(() => this.all().filter((r) => !r.deleted));
  protected pendingIds = computed(() => new Set(this.outbox().map((o) => o.record_id)));

  protected newName = '';
  protected newPhone = '';
  protected newStatus: Status = 'ACTIVE';
  protected editing = signal<string | null>(null);
  protected editName = '';
  protected editPhone = '';

  add() {
    if (!this.newName.trim()) return;
    this.records.create(this.newName.trim(), this.newPhone.trim(), this.newStatus);
    this.newName = ''; this.newPhone = ''; this.newStatus = 'ACTIVE';
  }

  setStatus(r: LocalRecord, status: Status) {
    this.records.update(r.id, { status });
  }

  startEdit(r: LocalRecord) {
    this.editName = r.name; this.editPhone = r.phone; this.editing.set(r.id);
  }

  saveEdit(r: LocalRecord) {
    this.records.update(r.id, { name: this.editName.trim(), phone: this.editPhone.trim() });
    this.editing.set(null);
  }
}
