import 'package:flutter/material.dart';

import '../local_db.dart';
import '../theme.dart';

/// Sync history and audit log, kept on the phone so it can be read offline.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.db});

  final LocalDb db;

  String _summary(HistoryEntry h) {
    final parts = ['${h.sent} sent', '${h.received} received'];
    if (h.merged > 0) parts.add('${h.merged} merged');
    if (h.conflicts > 0) parts.add('${h.conflicts} conflict(s)');
    if (h.duplicates > 0) parts.add('${h.duplicates} duplicate(s) ignored');
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: db,
      builder: (context, _) {
        final items = db.history;
        final ok = items.where((h) => h.ok).length;
        final merged = items.where((h) => h.merged > 0).length;
        final conflicts = items.where((h) => h.conflicts > 0).length;
        return ListView(
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                _Stat('${items.length}', 'Syncs', AppColors.ink),
                _Stat('$ok', 'Done', AppColors.teal),
                _Stat('$merged', 'Merged', AppColors.amber),
                _Stat('$conflicts', 'Conflicts', AppColors.amber),
                _Stat('${items.length - ok}', 'Failed', AppColors.red),
              ]),
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No syncs yet.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              ),
            for (final h in items)
              Card(
                child: ListTile(
                  title: Text(h.message, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(_summary(h)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(clock(h.at), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      const SizedBox(height: 4),
                      !h.ok
                          ? const Tag('Failed', bg: AppColors.redBg, fg: AppColors.redInk)
                          : h.conflicts > 0
                              ? const Tag('Conflict', bg: AppColors.amberBg, fg: AppColors.amberInk)
                              : h.merged > 0
                                  ? const Tag('Merged', bg: AppColors.amberBg, fg: AppColors.amberInk)
                                  : const Tag('Done', bg: AppColors.mint, fg: AppColors.teal),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          margin: const EdgeInsets.all(3),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
          ),
        ),
      );
}
