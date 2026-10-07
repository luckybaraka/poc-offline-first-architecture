/// Layer 1 (local storage) and layer 2 (operation queue), in SQLite.
///
/// Every user change writes the record AND its queue entry in one transaction, so the
/// screen updates instantly and the change can't be lost. The network is never touched here.
///
/// The latest records, queue and history are also kept in memory and the screens rebuild
/// whenever they change (this class is a ChangeNotifier).
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'config.dart';

const _uuid = Uuid();

int _now() => DateTime.now().millisecondsSinceEpoch;

class LocalRecord {
  LocalRecord({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    required this.deleted,
    required this.version,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String phone;
  final String status;
  final bool deleted;
  final int version; // last server version this device knows about (0 = never synced)
  final int updatedAt;

  factory LocalRecord.fromMap(Map<String, Object?> m) => LocalRecord(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        status: (m['status'] as String?) ?? 'ACTIVE',
        deleted: ((m['deleted'] as int?) ?? 0) == 1,
        version: (m['version'] as int?) ?? 0,
        updatedAt: (m['updated_at'] as int?) ?? 0,
      );

  Object? valueOf(String field) {
    switch (field) {
      case 'name':
        return name;
      case 'phone':
        return phone;
      case 'status':
        return status;
      case 'deleted':
        return deleted;
    }
    return null;
  }
}

class OutboxOp {
  OutboxOp({
    required this.seq,
    required this.opId,
    required this.recordId,
    required this.type,
    required this.fields,
    required this.baseVersion,
    required this.deviceId,
    required this.clientTs,
    required this.label,
    required this.attempts,
  });

  final int seq; // local order; ops are pushed in this order
  final String opId;
  final String recordId;
  final String type; // create | update | delete
  final Map<String, dynamic> fields; // only the fields that changed (delta)
  final int baseVersion;
  final String deviceId;
  final int clientTs;
  final String label; // record name, for the pending screen
  final int attempts;

  factory OutboxOp.fromMap(Map<String, Object?> m) => OutboxOp(
        seq: m['seq'] as int,
        opId: m['op_id'] as String,
        recordId: m['record_id'] as String,
        type: m['type'] as String,
        fields: Map<String, dynamic>.from(jsonDecode(m['fields'] as String) as Map),
        baseVersion: (m['base_version'] as int?) ?? 0,
        deviceId: m['device_id'] as String,
        clientTs: m['client_ts'] as int,
        label: (m['label'] as String?) ?? '',
        attempts: (m['attempts'] as int?) ?? 0,
      );

  /// The shape the server expects.
  Map<String, dynamic> toApi() => {
        'op_id': opId,
        'record_id': recordId,
        'type': type,
        'fields': fields,
        'base_version': baseVersion,
        'device_id': deviceId,
        'client_ts': clientTs,
      };
}

class HistoryEntry {
  HistoryEntry({
    int? at,
    this.ok = true,
    this.sent = 0,
    this.received = 0,
    this.merged = 0,
    this.conflicts = 0,
    this.duplicates = 0,
    this.message = '',
  }) : at = at ?? _now();

  int at;
  bool ok;
  int sent;
  int received;
  int merged;
  int conflicts;
  int duplicates;
  String message;

  factory HistoryEntry.fromMap(Map<String, Object?> m) => HistoryEntry(
        at: m['at'] as int,
        ok: ((m['ok'] as int?) ?? 1) == 1,
        sent: (m['sent'] as int?) ?? 0,
        received: (m['received'] as int?) ?? 0,
        merged: (m['merged'] as int?) ?? 0,
        conflicts: (m['conflicts'] as int?) ?? 0,
        duplicates: (m['duplicates'] as int?) ?? 0,
        message: (m['message'] as String?) ?? '',
      );

  Map<String, Object?> toMap() => {
        'at': at,
        'ok': ok ? 1 : 0,
        'sent': sent,
        'received': received,
        'merged': merged,
        'conflicts': conflicts,
        'duplicates': duplicates,
        'message': message,
      };
}

class LocalDb extends ChangeNotifier {
  LocalDb._(this._db, this.deviceId);

  final Database _db;
  final String deviceId;

  // In-memory copies the screens read from. Refreshed after every write.
  List<LocalRecord> records = [];
  List<OutboxOp> outbox = [];
  List<HistoryEntry> history = [];

  Set<String> get pendingRecordIds => outbox.map((o) => o.recordId).toSet();

  static Future<LocalDb> open() async {
    // One database per DEVICE_ID, so two emulators or two runs can act as two devices.
    final suffix = kDeviceIdOverride.isEmpty ? 'default' : kDeviceIdOverride;
    final path = p.join(await getDatabasesPath(), 'offline_poc_$suffix.db');
    final db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('''CREATE TABLE records (
        id TEXT PRIMARY KEY, name TEXT, phone TEXT, status TEXT,
        deleted INTEGER NOT NULL DEFAULT 0, version INTEGER NOT NULL DEFAULT 0, updated_at INTEGER)''');
      await db.execute('''CREATE TABLE outbox (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, op_id TEXT NOT NULL, record_id TEXT NOT NULL,
        type TEXT NOT NULL, fields TEXT NOT NULL, base_version INTEGER NOT NULL,
        device_id TEXT NOT NULL, client_ts INTEGER NOT NULL, label TEXT, attempts INTEGER NOT NULL DEFAULT 0)''');
      await db.execute('CREATE INDEX outbox_record ON outbox(record_id)');
      await db.execute('''CREATE TABLE history (
        id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER, ok INTEGER, sent INTEGER, received INTEGER,
        merged INTEGER, conflicts INTEGER, duplicates INTEGER, message TEXT)''');
      await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
    });

    var deviceId = kDeviceIdOverride;
    if (deviceId.isEmpty) {
      final rows = await db.query('meta', where: 'key = ?', whereArgs: ['deviceId']);
      if (rows.isNotEmpty) {
        deviceId = rows.first['value'] as String;
      } else {
        deviceId = 'phone-${_uuid.v4().substring(0, 4)}';
        await db.insert('meta', {'key': 'deviceId', 'value': deviceId});
      }
    }
    final local = LocalDb._(db, deviceId);
    await local.reload();
    return local;
  }

  Future<void> reload() async {
    records = (await _db.query('records', where: 'deleted = 0', orderBy: 'name COLLATE NOCASE'))
        .map(LocalRecord.fromMap)
        .toList();
    outbox = (await _db.query('outbox', orderBy: 'seq')).map(OutboxOp.fromMap).toList();
    history = (await _db.query('history', orderBy: 'at DESC', limit: 100)).map(HistoryEntry.fromMap).toList();
    notifyListeners();
  }

  // ---- user changes (local first) -------------------------------------------

  Future<void> createRecord(String name, String phone, String status) async {
    final id = _uuid.v4();
    await _db.transaction((txn) async {
      await txn.insert('records', {
        'id': id, 'name': name, 'phone': phone, 'status': status,
        'deleted': 0, 'version': 0, 'updated_at': _now(),
      });
      await _enqueue(txn, 'create', id, name, 0, {'name': name, 'phone': phone, 'status': status});
    });
    await reload();
  }

  Future<void> updateRecord(String id, Map<String, Object?> changes) async {
    await _db.transaction((txn) async {
      final rows = await txn.query('records', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final current = LocalRecord.fromMap(rows.first);
      // Delta: keep only the fields that actually changed.
      final delta = <String, Object?>{};
      changes.forEach((field, value) {
        if (current.valueOf(field) != value) delta[field] = value;
      });
      if (delta.isEmpty) return;
      await txn.update('records', {..._columns(delta), 'updated_at': _now()}, where: 'id = ?', whereArgs: [id]);
      final label = (delta['name'] as String?) ?? current.name;
      await _enqueue(txn, 'update', id, label, current.version, delta);
    });
    await reload();
  }

  Future<void> deleteRecord(String id) async {
    await _db.transaction((txn) async {
      final rows = await txn.query('records', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final current = LocalRecord.fromMap(rows.first);
      await txn.update('records', {'deleted': 1, 'updated_at': _now()}, where: 'id = ?', whereArgs: [id]);
      await _enqueue(txn, 'delete', id, current.name, current.version, {'deleted': true});
    });
    await reload();
  }

  Future<void> _enqueue(Transaction txn, String type, String recordId, String label, int baseVersion,
      Map<String, Object?> fields) {
    return txn.insert('outbox', {
      'op_id': _uuid.v4(),
      'record_id': recordId,
      'type': type,
      'fields': jsonEncode(fields),
      'base_version': baseVersion,
      'device_id': deviceId,
      'client_ts': _now(),
      'label': label.isEmpty ? 'Unnamed record' : label,
      'attempts': 0,
    });
  }

  /// SQLite has no booleans: 'deleted' is stored as 0/1.
  Map<String, Object?> _columns(Map<String, Object?> fields) =>
      fields.map((k, v) => MapEntry(k, k == 'deleted' ? ((v == true) ? 1 : 0) : v));

  // ---- used by the sync engine ------------------------------------------------

  Future<List<OutboxOp>> nextBatch(int size) async =>
      (await _db.query('outbox', orderBy: 'seq', limit: size)).map(OutboxOp.fromMap).toList();

  Future<void> bumpAttempts(List<OutboxOp> ops) async {
    final batch = _db.batch();
    for (final op in ops) {
      batch.update('outbox', {'attempts': op.attempts + 1}, where: 'seq = ?', whereArgs: [op.seq]);
    }
    await batch.commit(noResult: true);
    await reload();
  }

  /// Remove the op from the queue, record the server version, and if one of its fields lost a
  /// conflict, show the value the server kept (unless a newer local edit is still queued).
  Future<void> applyPushResult(OutboxOp op, Map<String, dynamic> result) async {
    await _db.transaction((txn) async {
      await txn.delete('outbox', where: 'seq = ?', whereArgs: [op.seq]);
      final rows = await txn.query('records', where: 'id = ?', whereArgs: [op.recordId]);
      if (rows.isEmpty) return;
      final current = LocalRecord.fromMap(rows.first);
      final update = <String, Object?>{};
      final version = result['version'];
      if (version is int) update['version'] = max(current.version, version);
      final fields = (result['fields'] as Map?)?.cast<String, dynamic>() ?? const {};
      for (final entry in fields.entries) {
        final fr = (entry.value as Map).cast<String, dynamic>();
        if (fr['outcome'] == 'lost' &&
            kSyncedFields.contains(entry.key) &&
            !await _hasPending(txn, op.recordId, entry.key)) {
          update.addAll(_columns({entry.key: fr['server_value']}));
        }
      }
      if (update.isNotEmpty) {
        await txn.update('records', update, where: 'id = ?', whereArgs: [op.recordId]);
      }
    });
    await reload();
  }

  /// Apply field-level changes pulled from the server. Returns how many came from other devices.
  Future<int> applyPulledChanges(List<dynamic> changes, int nextSeq) async {
    var fromOthers = 0;
    await _db.transaction((txn) async {
      for (final raw in changes) {
        final c = (raw as Map).cast<String, dynamic>();
        final recordId = c['record_id'] as String;
        final field = c['field'] as String;
        if (c['device_id'] != deviceId) fromOthers++;
        if (!kSyncedFields.contains(field)) continue;
        if (await _hasPending(txn, recordId, field)) continue; // local edit not yet sent wins locally
        final rows = await txn.query('records', where: 'id = ?', whereArgs: [recordId]);
        var currentVersion = 0;
        if (rows.isEmpty) {
          await txn.insert('records', {
            'id': recordId, 'name': '', 'phone': '', 'status': 'ACTIVE',
            'deleted': 0, 'version': 0, 'updated_at': _now(),
          });
        } else {
          currentVersion = (rows.first['version'] as int?) ?? 0;
        }
        await txn.update(
          'records',
          {..._columns({field: c['value']}), 'version': max(currentVersion, c['version'] as int), 'updated_at': _now()},
          where: 'id = ?',
          whereArgs: [recordId],
        );
      }
      await txn.insert('meta', {'key': 'lastSeq', 'value': '$nextSeq'},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await reload();
    return fromOthers;
  }

  Future<bool> _hasPending(Transaction txn, String recordId, String field) async {
    final rows = await txn.query('outbox', columns: ['fields'], where: 'record_id = ?', whereArgs: [recordId]);
    return rows.any((r) => (jsonDecode(r['fields'] as String) as Map).containsKey(field));
  }

  Future<void> addHistory(HistoryEntry entry) async {
    await _db.insert('history', entry.toMap());
    await reload();
  }

  Future<String?> getMeta(String key) async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) =>
      _db.insert('meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
}
