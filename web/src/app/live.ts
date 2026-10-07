import { DestroyRef, NgZone, Signal, inject, signal } from '@angular/core';
import { liveQuery } from 'dexie';

/**
 * Turn a Dexie live query into an Angular signal that updates whenever the data changes,
 * including changes written by the background sync. Updates are run inside Angular's zone
 * so the screen refreshes straight away.
 */
export function live<T>(query: () => Promise<T>, initial: T): Signal<T> {
  const zone = inject(NgZone);
  const value = signal<T>(initial);
  const sub = liveQuery(query).subscribe({
    next: (v) => zone.run(() => value.set(v)),
    error: (e) => console.error('live query failed', e),
  });
  inject(DestroyRef, { optional: true })?.onDestroy(() => sub.unsubscribe());
  return value.asReadonly();
}
