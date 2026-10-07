/// Layer 3 (sync engine) plus the client side of layer 4 (showing conflict results).
///
/// One sync = push the queue (oldest first, in batches), then pull everything new.
/// It runs when the connection comes back, every 5 s while online, shortly after each
/// local change, and when the user taps "Sync now".
/// If a push fails half-way, unsent ops stay queued. Ops the server already applied are
/// safe to resend because the server de-duplicates by op_id.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'connectivity_service.dart';
import 'local_db.dart';

enum NoticeKind { info, lost, error }

class SyncNotice {
  SyncNotice(this.kind, this.title, this.body, {this.recordId, this.field, this.mine});

  final NoticeKind kind;
  final String title;
  final String body;
  // Set for "lost" notices, so the user can re-enter their value.
  final String? recordId;
  final String? field;
  final Object? mine;
}

const _fieldLabels = {'name': 'name', 'phone': 'phone number', 'status': 'status', 'deleted': 'deletion'};

class SyncEngine extends ChangeNotifier {
  SyncEngine(this.db, this.conn);

  final LocalDb db;
  final ConnectivityService conn;

  bool syncing = false;
  int? lastSyncAt;

  final _notices = StreamController<SyncNotice>.broadcast();
  Stream<SyncNotice> get notices => _notices.stream;

  Timer? _soonTimer;
  Timer? _interval;
  bool _wasOnline = false;

  /// 'offline' | 'syncing' | 'online'
  String get status => !conn.online ? 'offline' : (syncing ? 'syncing' : 'online');

  Future<void> start() async {
    lastSyncAt = int.tryParse(await db.getMeta('lastSyncAt') ?? '');
    conn.addListener(_onConnectivityChanged);
    _interval = Timer.periodic(kSyncInterval, (_) => syncNow());
    _onConnectivityChanged();
  }

  void _onConnectivityChanged() {
    final online = conn.online;
    if (online && !_wasOnline) syncNow(); // reconnect -> sync
    _wasOnline = online;
    notifyListeners();
  }

  /// Called after each local change: sync shortly, batching quick edits together.
  void soon() {
    _soonTimer?.cancel();
    _soonTimer = Timer(const Duration(milliseconds: 400), syncNow);
  }

  Future<void> syncNow() async {
    if (!conn.online || syncing) return;
    syncing = true;
    notifyListeners();
    final entry = HistoryEntry();
    try {
      await _push(entry);
      await _pull(entry);
      lastSyncAt = DateTime.now().millisecondsSinceEpoch;
      await db.setMeta('lastSyncAt', '$lastSyncAt');
      entry.message = entry.conflicts > 0
          ? 'Sync completed with conflicts'
          : entry.merged > 0
              ? 'Sync completed with a merge'
              : 'Sync completed';
    } catch (e) {
      entry.ok = false;
      entry.message = 'Sync failed: ${_describe(e)}. Changes stay queued and will retry.';
      conn.ping();
    } finally {
      // Don't fill the history with empty background syncs.
      if (!entry.ok || entry.sent > 0 || entry.received > 0) await db.addHistory(entry);
      syncing = false;
      notifyListeners();
    }
  }

  /// Demo helper: resend the last batch to show the server ignores duplicates.
  Future<void> replayLastBatch() async {
    final saved = await db.getMeta('lastBatch');
    if (saved == null) {
      _notices.add(SyncNotice(NoticeKind.info, 'Nothing to replay', 'Make a change and let it sync first.'));
      return;
    }
    final ops = jsonDecode(saved) as List<dynamic>;
    try {
      final body = await _post('/sync/push/', {'device_id': db.deviceId, 'ops': ops});
      final results = body['results'] as List<dynamic>;
      final dupes = results.where((r) => (r as Map)['outcome'] == 'duplicate').length;
      await db.addHistory(HistoryEntry(
        sent: ops.length,
        duplicates: dupes,
        message: 'Replayed ${ops.length} change(s): $dupes recognised as duplicates, nothing applied twice',
      ));
      _notices.add(SyncNotice(NoticeKind.info, 'Replay sent',
          '$dupes of ${ops.length} change(s) were recognised as already applied.'));
    } catch (e) {
      _notices.add(SyncNotice(NoticeKind.error, 'Replay failed', _describe(e)));
    }
  }

  // ---- push ---------------------------------------------------------------------

  Future<void> _push(HistoryEntry entry) async {
    while (true) {
      final batch = await db.nextBatch(kBatchSize);
      if (batch.isEmpty) return;
      final ops = batch.map((o) => o.toApi()).toList();
      List<dynamic> results;
      try {
        final body = await _post('/sync/push/', {'device_id': db.deviceId, 'ops': ops});
        results = body['results'] as List<dynamic>;
      } catch (_) {
        await db.bumpAttempts(batch);
        rethrow;
      }
      await db.setMeta('lastBatch', jsonEncode(ops));
      entry.sent += batch.length;
      for (var i = 0; i < batch.length; i++) {
        final result = (results[i] as Map).cast<String, dynamic>();
        await db.applyPushResult(batch[i], result);
        _announce(batch[i], result, entry);
      }
    }
  }

  void _announce(OutboxOp op, Map<String, dynamic> r, HistoryEntry entry) {
    final name = op.label;
    switch (r['outcome']) {
      case 'duplicate':
        entry.duplicates++;
      case 'merged':
        entry.merged++;
        _notices.add(SyncNotice(NoticeKind.info, 'Changes merged',
            '$name was also changed on another device. Both changes were kept.'));
      case 'rejected':
        _notices.add(SyncNotice(NoticeKind.error, 'Change rejected by the server', '$name: ${r['error']}'));
      case 'conflict':
        entry.conflicts++;
        final fields = (r['fields'] as Map?)?.cast<String, dynamic>() ?? const {};
        for (final f in fields.entries) {
          final fr = (f.value as Map).cast<String, dynamic>();
          final label = _fieldLabels[f.key] ?? f.key;
          final mine = op.fields[f.key];
          if (fr['outcome'] == 'lost') {
            _notices.add(SyncNotice(
              NoticeKind.lost,
              'One of your edits was replaced',
              'You set the $label of $name to "$mine". A newer edit from ${fr['other_device']} '
                  'set it to "${fr['server_value']}", so that value was kept.',
              recordId: op.recordId,
              field: f.key,
              mine: mine,
            ));
          } else if (fr['outcome'] == 'won') {
            _notices.add(SyncNotice(NoticeKind.info, 'Your edit replaced an older one',
                '${fr['other_device']} had set the $label of $name to "${fr['other_value']}". Your newer value was kept.'));
          }
        }
    }
  }

  /// "Re-enter mine": make the value a fresh local change, which then syncs as the newest edit.
  Future<void> reenter(SyncNotice n) async {
    if (n.recordId == null || n.field == null) return;
    await db.updateRecord(n.recordId!, {n.field!: n.mine});
    soon();
  }

  // ---- pull ---------------------------------------------------------------------

  Future<void> _pull(HistoryEntry entry) async {
    var since = int.tryParse(await db.getMeta('lastSeq') ?? '') ?? 0;
    while (true) {
      final data = await _get('/sync/pull/?since=$since&device_id=${Uri.encodeQueryComponent(db.deviceId)}');
      final nextSeq = data['next_seq'] as int;
      entry.received += await db.applyPulledChanges(data['changes'] as List<dynamic>, nextSeq);
      since = nextSeq;
      if (data['has_more'] != true) return;
    }
  }

  // ---- http ---------------------------------------------------------------------

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final res = await http
        .post(Uri.parse('$kApiBase$path'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
    return _decode(res);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await http.get(Uri.parse('$kApiBase$path')).timeout(const Duration(seconds: 10));
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode != 200) throw Exception('server returned ${res.statusCode}');
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  String _describe(Object e) {
    if (e is TimeoutException) return 'request timed out';
    final text = e.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  @override
  void dispose() {
    _soonTimer?.cancel();
    _interval?.cancel();
    conn.removeListener(_onConnectivityChanged);
    _notices.close();
    super.dispose();
  }
}
