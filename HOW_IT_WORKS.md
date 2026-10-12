# How it works

A plain-language walkthrough of the offline-first PoC. If you want the exact API shapes and
the 10-step demo table, see the main [README](./README.md); this doc is the *why* behind them.

## The one idea

Every device (a browser tab, a phone) keeps its **own local database** and writes to it first.
The network is optional. When a connection is available, devices reconcile their changes through
a small Django server. Nothing a user does is ever blocked on the network, and nothing they do
offline is ever lost.

```
   Your edit ──▶ local DB (instant UI)  ──▶ outbox queue ──▶ [network] ──▶ server
                                                                              │
   Your screen ◀── local DB ◀── apply pulled changes ◀── [network] ◀─────────┘
```

## The lifecycle of one change

1. **You edit a record.** The app writes the new value **and** a queue entry ("outbox op") in a
   single local transaction. The screen updates immediately — online or not. Only the *changed
   fields* are stored (a delta), never the whole record.
   - Web: `web/src/app/local-writes.ts` · Mobile: `mobile/lib/local_db.dart` (`updateRecord`)

2. **The sync engine drains the queue.** It runs when the connection returns, every 5 seconds
   while online, ~400 ms after an edit (so quick edits batch together), and on "Sync now".
   A sync is always **push, then pull**.
   - Web: `web/src/app/sync.service.ts` · Mobile: `mobile/lib/sync_engine.dart`

3. **Push** sends queued ops oldest-first to `POST /api/sync/push/`. Each op carries an `op_id`,
   the changed `fields`, and the `base_version` the device last saw. If the request fails
   half-way, unsent ops stay in the queue and retry later.

4. **The server applies each op** and decides the outcome (see conflict rules below).
   - `backend/sync/engine.py` (`apply_op`)

5. **Pull** asks `GET /api/sync/pull/?since=<seq>` for every field change after the last global
   sequence number this device saw. That's **delta sync**: a status change pulls one field, not
   the whole record.

## The conflict rules (field-level, on the server)

For each pushed op, the server checks, in order:

| Situation | Outcome | What the user sees |
|-----------|---------|--------------------|
| This `op_id` was already processed | `duplicate` | nothing — a safe retry |
| Nobody changed the record since `base_version` | `applied` | the change just lands |
| Others changed **different** fields | `merged` | "Changes merged — both kept" |
| Another device changed the **same** field | `conflict` | Last-Write-Wins by `client_ts` |

On a same-field conflict, the edit with the **later timestamp wins**. The losing device is told
which value was kept and offered **Re-enter mine** / **Keep newer**. "Re-enter mine" simply
re-queues your value as a brand-new edit, which then wins because it's now the newest.

## Two things that make it feel safe

- **Idempotency.** The server remembers every `op_id` and its result. Resending a batch after a
  dropped connection changes nothing and applies nothing twice. (That's what "Replay last batch"
  demonstrates.)
- **Local edits win locally.** A value pulled from the server — or a "you lost" value — never
  overwrites a field you still have *queued but unsent*. Your own un-synced work is never
  clobbered by incoming data; it gets reconciled on the next push instead.
  (`hasPending` in web, `_hasPending` in mobile.)

## "Online" is stricter than the browser thinks

A device considers itself online only when **all three** are true: the OS/browser reports a
network, a health-check ping to `GET /api/health/` succeeds, and the demo "Force offline" switch
is off. This is why stopping the backend flips the device to Offline within ~10 seconds even
though the laptop still has Wi-Fi.
- Web: `web/src/app/connectivity.service.ts` · Mobile: `mobile/lib/connectivity_service.dart`

## The same contract on both clients

The web (IndexedDB via Dexie) and mobile (SQLite via sqflite) clients store data differently but
speak the **identical** push/pull API. That's why a phone and a browser tab sync with each other
through the server — they're just two devices to the backend. Record and op IDs are UUIDs made on
the device, so records created offline can never collide.

## Testing it on a phone (quick version)

1. Start the backend bound to all interfaces so the phone can reach it:
   `python manage.py runserver 0.0.0.0:8000`
2. Find your laptop's IP (`ipconfig` on Windows, e.g. `192.168.1.20`).
3. Open the web client next to the phone: `http://localhost:4200/?device=web-a`
4. Run the mobile app pointed at your laptop:
   `flutter run --dart-define=API_BASE=http://192.168.1.20:8000/api --dart-define=DEVICE_ID=phone-a`
   (Android emulator can use the default `10.0.2.2` and skip `API_BASE`.)
5. Add a record on the phone → it appears in the web tab within a few seconds.
6. Put the phone in airplane mode (or tap force-offline), edit the status, **close and reopen the
   app** — the pending change is still there because the queue lives in SQLite.
7. Edit the *same* field on both the phone and web while both are offline, then bring them back
   online one at a time → watch Last-Write-Wins and the "Re-enter mine" banner.

See `mobile/README.md` for first-time setup (`flutter create`, Android cleartext permission).
