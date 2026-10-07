import 'package:flutter/material.dart';

import '../config.dart';
import '../local_db.dart';
import '../sync_engine.dart';
import '../theme.dart';

/// Local-first data view: everything here is read from the phone's database, never from the API.
class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key, required this.db, required this.sync});

  final LocalDb db;
  final SyncEngine sync;

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _status = 'ACTIVE';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await widget.db.createRecord(name, _phone.text.trim(), _status);
    widget.sync.soon();
    _name.clear();
    _phone.clear();
    setState(() => _status = 'ACTIVE');
    if (mounted) FocusScope.of(context).unfocus();
  }

  Future<void> _setStatus(LocalRecord r, String status) async {
    await widget.db.updateRecord(r.id, {'status': status});
    widget.sync.soon();
  }

  Future<void> _edit(LocalRecord r) async {
    final name = TextEditingController(text: r.name);
    final phone = TextEditingController(text: r.phone);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit record'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (action == 'save') {
      await widget.db.updateRecord(r.id, {'name': name.text.trim(), 'phone': phone.text.trim()});
      widget.sync.soon();
    } else if (action == 'delete') {
      await widget.db.deleteRecord(r.id);
      widget.sync.soon();
    }
    name.dispose();
    phone.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.db, widget.sync]),
      builder: (context, _) {
        final records = widget.db.records;
        final pendingIds = widget.db.pendingRecordIds;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            InfoBanner(
              title: 'Loaded from this device',
              body: 'Last synced with the server ${ago(widget.sync.lastSyncAt)}',
              bg: AppColors.mint,
              fg: AppColors.teal,
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  TextField(controller: _name, decoration: const InputDecoration(labelText: 'Patient name')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone number'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [for (final s in kStatuses) DropdownMenuItem(value: s, child: Text(s))],
                        onChanged: (v) => setState(() => _status = v ?? 'ACTIVE'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _add, child: const Text('Add record')),
                  ]),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                const Text('Records', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                Text('${records.length} total', style: const TextStyle(color: AppColors.muted)),
              ]),
            ),
            if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No records yet. Add one above. It works offline too.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              ),
            for (final r in records)
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _edit(r),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      CircleAvatar(
                        backgroundColor: AppColors.mint,
                        child: Text(r.name.isEmpty ? '?' : r.name[0].toUpperCase(),
                            style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.name.isEmpty ? 'Unnamed record' : r.name,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${r.phone.isEmpty ? 'No phone' : r.phone}  v${r.version}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                          const SizedBox(height: 4),
                          pendingIds.contains(r.id)
                              ? const Tag('Waiting to sync', bg: AppColors.amberBg, fg: AppColors.amberInk)
                              : const Tag('Synced', bg: AppColors.mint, fg: AppColors.teal),
                        ]),
                      ),
                      _StatusButton(status: r.status, onChanged: (s) => _setStatus(r, s)),
                    ]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.status, required this.onChanged});

  final String status;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final bg = switch (status) {
      'ACTIVE' => AppColors.mint,
      'SUSPENDED' => AppColors.redBg,
      _ => const Color(0xFFECEFF0),
    };
    return PopupMenuButton<String>(
      tooltip: 'Change status',
      onSelected: onChanged,
      itemBuilder: (_) => [for (final s in kStatuses) PopupMenuItem(value: s, child: Text(s))],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(status, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]),
      ),
    );
  }
}
