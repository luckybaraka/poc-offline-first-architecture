import { Component, computed, inject } from '@angular/core';
import { ConnectivityService } from './connectivity.service';
import { OutboxOp, db } from './db';
import { live } from './live';
import { SyncService } from './sync.service';
import { ago, clock } from './time';

/** The operation queue made visible: what is waiting, and how old the oldest change is. */
@Component({
  selector: 'app-pending',
  template: `
    @if (ops().length) {
      <div class="banner amber">
        <strong>{{ ops().length }} change(s) waiting to sync</strong>
        <span>Oldest change made {{ ago(oldest()) }}. They are stored on this device and survive a reload or restart.</span>
      </div>
    } @else {
      <div class="banner mint"><strong>Nothing waiting</strong><span>Every local change has reached the server.</span></div>
    }

    @for (op of ops(); track op.seq) {
      <div class="card row">
        <div class="op-icon" [attr.data-type]="op.type">{{ icon[op.type] }}</div>
        <div class="grow">
          <div class="title">{{ verb[op.type] }}: {{ op.label }}</div>
          <div class="muted">{{ describe(op) }}</div>
        </div>
        <div class="right muted">
          {{ clock(op.client_ts) }}
          @if (op.attempts) { <div class="tag red">{{ op.attempts }} failed attempt(s)</div> }
        </div>
      </div>
    }

    <div class="actions">
      <button class="primary" (click)="sync.syncNow()" [disabled]="!conn.online() || sync.syncing()">Sync now</button>
      <button (click)="sync.replayLastBatch()" [disabled]="!conn.online()"
              title="Re-sends the last batch to prove the server never applies a change twice">
        Replay last batch (duplicate test)
      </button>
    </div>
    <p class="muted center">Sync starts on its own when the connection comes back.</p>
  `,
})
export class PendingComponent {
  protected sync = inject(SyncService);
  protected conn = inject(ConnectivityService);
  protected ago = ago;
  protected clock = clock;
  protected ops = live(() => db.outbox.orderBy('seq').toArray(), [] as OutboxOp[]);
  protected oldest = computed(() => this.ops()[0]?.client_ts ?? null);
  protected icon = { create: '+', update: '✎', delete: '−' } as const;
  protected verb = { create: 'Added', update: 'Edited', delete: 'Deleted' } as const;

  describe(op: OutboxOp): string {
    if (op.type === 'delete') return 'Record deleted';
    return Object.entries(op.fields).map(([k, v]) => `${k} → ${v}`).join(', ') + ` (based on v${op.base_version})`;
  }
}
