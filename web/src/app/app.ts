import { Component, computed, inject, signal } from '@angular/core';
import { ConnectivityService } from './connectivity.service';
import { DEVICE_ID } from './config';
import { db } from './db';
import { HistoryComponent } from './history';
import { live } from './live';
import { NoticesService } from './notices.service';
import { PendingComponent } from './pending';
import { RecordsComponent } from './records';
import { SyncService } from './sync.service';

type Tab = 'records' | 'pending' | 'history';

@Component({
  selector: 'app-root',
  imports: [RecordsComponent, PendingComponent, HistoryComponent],
  template: `
    <header>
      <div class="brand">
        <h1>Patient status</h1>
        <span class="muted">Offline-first PoC, device <code>{{ deviceId }}</code></span>
      </div>
      <div class="header-actions">
        <span class="pill" [attr.data-state]="sync.status()">
          <i></i>{{ statusLabel() }}
          @if (pendingCount()) { <em>{{ pendingCount() }} pending</em> }
        </span>
        <label class="switch" title="Simulate losing the network without touching DevTools">
          <input type="checkbox" [checked]="conn.forceOffline()" (change)="conn.toggleForceOffline()" />
          Force offline
        </label>
      </div>
    </header>
    @if (sync.status() === 'syncing') { <div class="progress"><div></div></div> }

    <div class="notices" aria-live="polite">
      @for (n of notices.items(); track n.id) {
        <div class="notice" [attr.data-kind]="n.kind">
          <div class="grow">
            <strong>{{ n.title }}</strong>
            <p>{{ n.body }}</p>
            @if (n.actions) {
              <div class="actions">
                @for (a of n.actions; track a.label) {
                  <button [class.primary]="a.primary" (click)="a.run(); notices.dismiss(n.id)">{{ a.label }}</button>
                }
              </div>
            }
          </div>
          <button class="close" (click)="notices.dismiss(n.id)" aria-label="Dismiss">✕</button>
        </div>
      }
    </div>

    <nav>
      <button [class.active]="tab() === 'records'" (click)="tab.set('records')">Records</button>
      <button [class.active]="tab() === 'pending'" (click)="tab.set('pending')">
        Pending changes @if (pendingCount()) { <span class="count">{{ pendingCount() }}</span> }
      </button>
      <button [class.active]="tab() === 'history'" (click)="tab.set('history')">Sync history</button>
    </nav>

    <main>
      @switch (tab()) {
        @case ('records') { <app-records /> }
        @case ('pending') { <app-pending /> }
        @case ('history') { <app-history /> }
      }
    </main>
  `,
})
export class App {
  protected conn = inject(ConnectivityService);
  protected sync = inject(SyncService);
  protected notices = inject(NoticesService);
  protected deviceId = DEVICE_ID;
  protected tab = signal<Tab>('records');

  private outbox = live(() => db.outbox.count(), 0);
  protected pendingCount = computed(() => this.outbox());
  protected statusLabel = computed(() => ({
    online: 'Online', offline: 'Offline, saving on this device', syncing: 'Syncing',
  })[this.sync.status()]);
}
