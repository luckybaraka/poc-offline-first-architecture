# Offline-first PoC: Flutter client

The mobile half of the PoC. It uses the same Django backend and the same push/pull API as the
web client, so a phone and a browser tab sync with each other.

| Layer | File |
|-------|------|
| 1. Local storage | `lib/local_db.dart`: SQLite tables `records`, `outbox`, `history`, `meta` (sqflite) |
| 2. Change tracking and queue | `lib/local_db.dart` (`createRecord`, `updateRecord`, `deleteRecord`): record and queue entry in one transaction, changed fields only |
| 3. Sync engine | `lib/sync_engine.dart` (push, then pull) and `lib/connectivity_service.dart` (network changes, a health-check ping, force offline) |
| 4. Conflict resolution | On the server (`backend/sync/engine.py`). The app shows the result: a "merged" message, or a banner with **Re-enter mine** / **Keep newer** |

Needs Flutter 3.27 or newer. Packages: `sqflite`, `http`, `connectivity_plus`, `uuid`. There's no code generation step.

## First-time setup (about 5 minutes)

This folder contains `lib/` and `pubspec.yaml` but not the Android/iOS project folders.
Generate them once:

```bash
cd mobile
flutter create --project-name offline_poc_mobile --platforms android,ios .
flutter pub get
flutter analyze
```

`flutter create .` only adds files that are missing. It won't replace the code in `lib/`.

**Android: allow plain HTTP to your laptop.** In `android/app/src/main/AndroidManifest.xml`,
add the permission line above `<application`, and add the attribute to the `<application` tag:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<application
    android:usesCleartextTraffic="true"
    ...>
```

**iOS (only if you run on an iPhone or simulator):** in `ios/Runner/Info.plist`, inside the main `<dict>`:

```xml
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsArbitraryLoads</key><true/></dict>
```

These HTTP exceptions are for the PoC only. A real build would use HTTPS.

## Run it

Start the backend first (see the main README), using `runserver 0.0.0.0:8000` so other devices can reach it.

**Android emulator.** The default address `10.0.2.2` already points at your laptop:

```bash
flutter run --dart-define=DEVICE_ID=phone-a
```

**Real phone on the same Wi-Fi.** Use your laptop's IP (`ipconfig` on Windows):

```bash
flutter run --dart-define=API_BASE=http://192.168.1.20:8000/api --dart-define=DEVICE_ID=phone-a
```

`DEVICE_ID` names the device in conflict messages and keeps its local database separate.

## Demo with phone + web

1. Open the web client at `http://localhost:4200/?device=web-a` next to the phone.
2. Add a record on the phone. It appears in the web tab within a few seconds.
3. Turn on airplane mode, or tap the cloud icon (force offline). Change the status. The pill shows "Offline, 1 pending" and the row says "Waiting to sync".
4. **Close the app completely and reopen it.** The pending change is still there, because the queue is in SQLite.
5. In the web tab, force offline and change the same status to something else.
6. Bring the web tab online first, then the phone. The phone gets the "One of your edits was replaced" banner, with **Re-enter mine** / **Keep newer**.
7. Repeat with different fields (phone number on one device, status on the other). Both are kept and the app shows "Changes merged".
8. Pending tab, then **Replay last batch**. The server ignores the duplicates.
9. The Sync history tab shows everything that happened.
