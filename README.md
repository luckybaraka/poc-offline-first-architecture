# Offline-first PoC: web and mobile

A small proof of concept for the ideas in
[Offline-First Systems](https://luckybaraka.github.io/posts/offline-first-architecture/).
One kind of record (a patient's name, phone and status), built so that every layer of the
architecture can be seen working.

- **Backend:** Django + Django REST Framework, Postgres (SQLite if you skip Docker)
- **Web client:** Angular 20, IndexedDB through Dexie, Angular service worker (`web/`)
- **Mobile client:** Flutter, SQLite through sqflite (`mobile/`, see `mobile/README.md`)

Both clients use the same two sync endpoints (see "API contract" below), so a phone and a
browser tab sync with each other.

## Run it

You need Python 3.12 and Node 20 or 22.

**1. Backend** (pick one)

```bash
# Quickest: SQLite, no Docker
cd backend
python -m venv .venv
.venv\Scripts\activate          # Windows   (macOS/Linux: source .venv/bin/activate)
source .venv/Scripts/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

```bash
# Closer to our stack: Postgres in Docker
docker compose up --build
```

Check it: <http://localhost:8000/api/health/> should return `{"ok": true}`.

**2. Web client**

```bash
cd web
npm install
npm run demo        # production build with the service worker, served on http://localhost:4200
```

`npm start` also works for development, but the service worker (app loads with no network)
is only active in the `npm run demo` build.

## Two devices in one browser

Each device keeps its own local database. Open two tabs:

- <http://localhost:4200/?device=web-a>
- <http://localhost:4200/?device=web-b>

Each tab has a **Force offline** switch in the header. It's remembered across reloads. You can also use Chrome DevTools
(Network tab, "Offline"), which only affects that tab. Another option is a phone on the same
Wi-Fi, opening `http://<your-laptop-ip>:4200/?device=phone&api=http://<your-laptop-ip>:8000/api`.

To see the server's copy at any time: <http://localhost:8000/api/records/>.
Server-side audit trail: <http://localhost:8000/api/sync/events/>.

## Demo script (about 5 minutes)

| # | Do this | What it shows |
|---|---------|---------------|
| 1 | In **web-a**, add "Amina Wanjiru". Within a few seconds she appears in **web-b**. | Local write, background push and pull |
| 2 | Turn on **Force offline** in web-a. Change her status to INACTIVE. | The UI updates instantly with no network. The pill says Offline and the row says "Waiting to sync" |
| 3 | Open **Pending changes** in web-a. Reload the tab. | The queue is stored on disk and survives a reload |
| 4 | Turn on Force offline in **web-b**. Change the same status to SUSPENDED. | Two devices editing the same field while disconnected |
| 5 | Turn web-b back online, **then** web-a. | web-a gets "One of your edits was replaced" (Last-Write-Wins), with **Re-enter mine** / **Keep newer** |
| 6 | Click **Re-enter mine**. | The user can put back what they lost. web-b picks it up |
| 7 | Take both offline. Edit the **phone** in web-a and the **status** in web-b. Bring both online. | Different fields are merged and both changes are kept ("Changes merged") |
| 8 | In Pending changes, click **Replay last batch**. | The server recognises the op IDs and applies nothing twice |
| 9 | Open **Sync history** on each tab. | The audit log of every sync, merge and conflict |
| 10 | Stop the backend and keep working. Start it again. | The pill switches to Offline within about 10 seconds because the health check fails, even though the browser still has internet. Changes queue, then drain when the server is back |

## How it maps to the four layers

| Layer | Where |
|-------|-------|
| 1. Local storage | `web/src/app/db.ts`: IndexedDB tables `records`, `outbox`, `history`, `meta` |
| 2. Change tracking and queue | `web/src/app/local-writes.ts`: every change writes the record **and** an outbox entry in one transaction, sending only the changed fields |
| 3. Sync engine | `web/src/app/sync.service.ts` (push the queue in order, then pull everything since the last sequence number) and `connectivity.service.ts` (browser events, a health-check ping, and the force-offline switch) |
| 4. Conflict resolution | `backend/sync/engine.py`: version check, field-level merge, Last-Write-Wins on the same field. The client shows the outcome |

## How sync works

**Push** `POST /api/sync/push/`. Each queued change is sent as an operation:

```json
{
  "op_id": "uuid",
  "record_id": "uuid",
  "type": "update",
  "fields": { "status": "INACTIVE" },
  "base_version": 3,
  "device_id": "web-a",
  "client_ts": 1759750000000
}
```

The server handles each operation like this:

1. **Seen this `op_id` before?** Return the stored result and change nothing. This makes retries safe after a dropped connection.
2. **Has nobody else changed the record since `base_version`?** Apply it.
3. **Did other devices change *different* fields?** Apply it. The result is `merged`.
4. **Did another device change the *same* field?** The edit with the later `client_ts` wins. The losing device is told which value was kept.

**Pull** `GET /api/sync/pull/?since=<seq>`. Every applied field change gets a global sequence
number, and the client asks for everything after the last number it saw. That's delta sync:
a status change sends one field, not the whole record. A pulled value never overwrites a
local edit that is still waiting in the queue.

## API contract (for the Flutter client and other PoCs)

| Endpoint | Purpose |
|----------|---------|
| `GET /api/health/` | Connectivity check |
| `POST /api/sync/push/` | `{"device_id", "ops": [op…]}`, at most 100 per batch. Returns one result per op, in order. `outcome` is `applied`, `merged`, `conflict`, `duplicate` or `rejected`. For conflicts, `fields.<name>.outcome` is `won` or `lost`, and `server_value` is the value that was kept |
| `GET /api/sync/pull/?since=N&device_id=X` | `{"changes": [{seq, record_id, field, value, version, device_id}], "next_seq", "has_more"}` |
| `GET /api/sync/events/` | Server audit trail |
| `GET /api/records/` | Server copy (read-only, for the demo) |

Record and op IDs are UUIDs created on the device, so records created offline never clash.

## Deliberately left out (next steps)

- **Auth and per-user data.** The API is open. A real build would use our Keycloak tokens, and sync would only pull the records a user can see.
- **Encryption at rest.** IndexedDB isn't encrypted. Sensitive data needs encryption, key management and wipe-on-logout (SQLCipher on Flutter).
- **Clock skew.** Last-Write-Wins trusts device clocks. A hybrid logical clock, or server-assigned order for some fields, removes that risk.
- **Server push.** Other devices pick up changes by polling every 5 seconds. Pushing through Centrifugo or NATS would make it instant.
- **Coalescing and back-pressure.** Several edits to one field are sent separately. Squashing them, plus rate limits on the server, matters when many devices reconnect at once.
- **CRDTs.** Not needed for single-value fields like these. They'd only be worth it for free text edited by several people at once.

## Tests

```bash
cd backend && python manage.py test sync
```

Seven tests cover create and pull, a clean update, duplicate ops, field merge,
Last-Write-Wins (both winning and losing), a device's own queued edits, and invalid values.
