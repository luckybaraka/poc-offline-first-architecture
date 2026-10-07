import 'package:flutter/material.dart';

import '../connectivity_service.dart';
import '../local_db.dart';
import '../sync_engine.dart';
import '../theme.dart';

/// The operation queue made visible: what is waiting, and how old the oldest change is.
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key, required this.db, required this.conn, required this.sync});

  final LocalDb db;
  final ConnectivityService conn;
  final SyncEngine sync;

  static const _verb = {'create': 'Added', 'update': 'Edited', 'delete': 'Deleted'};
  static const _icon = {'create': Icons.add, 'update': Icons.edit, 'delete': Icons.remove};
  static const _color = {'create': AppColors.teal, 'update': AppColors.blue, 'delete': AppColors.red};

  String _describe(OutboxOp op) {
    if (op.type == 'delete') return 'Record deleted';
    final changes = op.fields.entries.map((e) => '${e.key} → ${e.value}').join(', ');
    return '$changes (based on v${op.baseVersion})';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([db, conn, sync]),
      builder: (context, _) {
        final ops = db.outbox;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ops.isEmpty
                ? const InfoBanner(
                    title: 'Nothing waiting',
                    body: 'Every local change has reached the server.',
                    bg: AppColors.mint,
                    fg: AppColors.teal)
                : InfoBanner(
                    title: '${ops.length} change(s) waiting to sync',
                    body: 'Oldest change made ${ago(ops.first.clientTs)}. '
                        'They are stored on this phone and survive closing the app.',
                    bg: AppColors.amberBg,
                    fg: AppColors.amberInk),
            for (final op in ops)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _color[op.type],
                    child: Icon(_icon[op.type], color: Colors.white, size: 18),
                  ),
                  title: Text('${_verb[op.type]}: ${op.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(_describe(op)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(clock(op.clientTs), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      if (op.attempts > 0)
                        Tag('${op.attempts} failed', bg: AppColors.redBg, fg: AppColors.redInk),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton(
                  onPressed: conn.online && !sync.syncing ? sync.syncNow : null,
                  child: const Text('Sync now'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: conn.online ? sync.replayLastBatch : null,
                  child: const Text('Replay last batch (duplicate test)'),
                ),
                const SizedBox(height: 12),
                const Text('Sync starts on its own when the connection comes back.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              ]),
            ),
          ],
        );
      },
    );
  }
}
