/**
 * Connectivity monitoring. "Online" means all three are true:
 *  - the browser reports a network,
 *  - the backend answers a health check (the browser can say online while the server is unreachable),
 *  - the demo "force offline" switch is off.
 */
import { Injectable, computed, signal } from '@angular/core';
import { API_BASE, DEVICE_ID, PING_INTERVAL_MS } from './config';

const FORCE_KEY = `forceOffline:${DEVICE_ID}`;

@Injectable({ providedIn: 'root' })
export class ConnectivityService {
  readonly browserOnline = signal(navigator.onLine);
  readonly serverReachable = signal(false);
  // Remembered across reloads, so you can reload while "offline" and see the queue survive.
  readonly forceOffline = signal(localStorage.getItem(FORCE_KEY) === '1');
  readonly online = computed(() => this.browserOnline() && this.serverReachable() && !this.forceOffline());

  constructor() {
    window.addEventListener('online', () => { this.browserOnline.set(true); this.ping(); });
    window.addEventListener('offline', () => { this.browserOnline.set(false); this.serverReachable.set(false); });
    this.ping();
    setInterval(() => this.ping(), PING_INTERVAL_MS);
  }

  toggleForceOffline() {
    this.forceOffline.update((v) => !v);
    localStorage.setItem(FORCE_KEY, this.forceOffline() ? '1' : '0');
    if (!this.forceOffline()) this.ping();
  }

  async ping() {
    if (!this.browserOnline() || this.forceOffline()) return;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 3000);
    try {
      const res = await fetch(`${API_BASE}/health/`, { signal: ctrl.signal, cache: 'no-store' });
      this.serverReachable.set(res.ok);
    } catch {
      this.serverReachable.set(false);
    } finally {
      clearTimeout(timer);
    }
  }
}
