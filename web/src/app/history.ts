import { Component, computed } from '@angular/core';
import { HistoryEntry, db } from './db';
import { live } from './live';
import { clock } from './time';

/** Sync history and audit log, kept on the device so it is readable offline. */
@Component({
  selector: 'app-history',
  template: `
    <div class="stats">
      <div class="card stat"><b>{{ items().length }}</b><span>Syncs</span></div>
      <div class="card stat"><b class="teal">{{ count('ok') }}</b><span>Done</span></div>
      <div class="card stat"><b class="amber">{{ count('merged') }}</b><span>Merged</span></div>
      <div class="card stat"><b class="amber">{{ count('conflicts') }}</b><span>Conflicts</span></div>
      <div class="card stat"><b class="red">{{ count('failed') }}</b><span>Failed</span></div>
    </div>

    @for (h of items(); track h.id) {
      <div class="card row">
        <div class="grow">
          <div class="title">{{ h.message }}</div>
          <div class="muted">{{ summary(h) }}</div>
        </div>
        <div class="right">
          <div class="muted">{{ clock(h.at) }}</div>
          <span class="tag" [class.teal]="h.ok && !h.conflicts && !h.merged"
                [class.amber]="h.ok && (h.conflicts || h.merged)" [class.red]="!h.ok">
            {{ !h.ok ? 'Failed' : h.conflicts ? 'Conflict' : h.merged ? 'Merged' : 'Done' }}
          </span>
        </div>
      </div>
    } @empty {
      <div class="empty">No syncs yet.</div>
    }
  `,
})
export class HistoryComponent {
  protected clock = clock;
  protected items = live(() => db.history.orderBy('at').reverse().limit(100).toArray(), [] as HistoryEntry[]);
  private totals = computed(() => {
    const t = { ok: 0, merged: 0, conflicts: 0, failed: 0 };
    for (const h of this.items()) {
      if (h.ok) t.ok++; else t.failed++;
      if (h.merged) t.merged++;
      if (h.conflicts) t.conflicts++;
    }
    return t;
  });

  summary(h: HistoryEntry): string {
    const parts = [`${h.sent} sent`, `${h.received} received`];
    if (h.merged) parts.push(`${h.merged} merged`);
    if (h.conflicts) parts.push(`${h.conflicts} conflict(s)`);
    if (h.duplicates) parts.push(`${h.duplicates} duplicate(s) ignored`);
    return parts.join(', ');
  }

  count(k: 'ok' | 'merged' | 'conflicts' | 'failed') {
    return this.totals()[k];
  }
}
