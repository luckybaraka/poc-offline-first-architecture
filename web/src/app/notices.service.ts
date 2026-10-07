import { Injectable, signal } from '@angular/core';

export interface Notice {
  id: number;
  kind: 'info' | 'warn' | 'error';
  title: string;
  body: string;
  actions?: { label: string; primary?: boolean; run: () => void }[];
}

@Injectable({ providedIn: 'root' })
export class NoticesService {
  private nextId = 1;
  readonly items = signal<Notice[]>([]);

  show(n: Omit<Notice, 'id'>, autoCloseMs = n.actions ? 0 : 6000) {
    const notice = { ...n, id: this.nextId++ };
    this.items.update((list) => [notice, ...list].slice(0, 5));
    if (autoCloseMs) setTimeout(() => this.dismiss(notice.id), autoCloseMs);
  }

  dismiss(id: number) {
    this.items.update((list) => list.filter((n) => n.id !== id));
  }
}
