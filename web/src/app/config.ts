/**
 * Runtime settings, read from the URL so the demo needs no rebuilds:
 *   ?device=web-b   run as a separate device (its own local database)
 *   ?api=http://host:8000/api   point at a different backend
 */
const params = new URLSearchParams(window.location.search);

export const API_BASE = params.get('api') ?? 'http://localhost:8000/api';

function resolveDeviceId(): string {
  const fromUrl = params.get('device');
  if (fromUrl) return fromUrl;
  try {
    let id = localStorage.getItem('deviceId');
    if (!id) {
      id = 'web-' + Math.random().toString(36).slice(2, 6);
      localStorage.setItem('deviceId', id);
    }
    return id;
  } catch {
    return 'web-' + Math.random().toString(36).slice(2, 6);
  }
}

export const DEVICE_ID = resolveDeviceId();

export const SYNC_INTERVAL_MS = 5_000;   // background pull; a real build would use server push (e.g. Centrifugo)
export const PING_INTERVAL_MS = 10_000;
export const BATCH_SIZE = 50;
