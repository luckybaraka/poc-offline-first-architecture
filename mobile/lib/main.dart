import 'dart:async';

import 'package:flutter/material.dart';

import 'connectivity_service.dart';
import 'local_db.dart';
import 'screens/history_screen.dart';
import 'screens/pending_screen.dart';
import 'screens/records_screen.dart';
import 'sync_engine.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await LocalDb.open();
  final conn = ConnectivityService(db);
  final sync = SyncEngine(db, conn);
  await conn.start();
  await sync.start();
  runApp(PocApp(db: db, conn: conn, sync: sync));
}

class PocApp extends StatelessWidget {
  const PocApp({super.key, required this.db, required this.conn, required this.sync});

  final LocalDb db;
  final ConnectivityService conn;
  final SyncEngine sync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Patient status',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(db: db, conn: conn, sync: sync),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.db, required this.conn, required this.sync});

  final LocalDb db;
  final ConnectivityService conn;
  final SyncEngine sync;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  StreamSubscription<SyncNotice>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.sync.notices.listen(_showNotice);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _showNotice(SyncNotice n) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (n.kind == NoticeKind.lost) {
      // A lost edit needs a decision, so it stays on screen until the user picks.
      messenger.hideCurrentMaterialBanner();
      messenger.showMaterialBanner(MaterialBanner(
        backgroundColor: AppColors.redBg,
        leading: const Icon(Icons.warning_amber_rounded, color: AppColors.red),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.redInk)),
            const SizedBox(height: 4),
            Text(n.body),
          ],
        ),
        actions: [
          TextButton(onPressed: messenger.hideCurrentMaterialBanner, child: const Text('Keep newer')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              widget.sync.reenter(n);
            },
            child: const Text('Re-enter mine'),
          ),
        ],
      ));
      return;
    }
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: n.kind == NoticeKind.error ? AppColors.red : AppColors.ink,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(n.body),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final all = Listenable.merge([widget.db, widget.conn, widget.sync]);
    return ListenableBuilder(
      listenable: all,
      builder: (context, _) {
        final pending = widget.db.outbox.length;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Patient status', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('Device ${widget.db.deviceId}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
            actions: [
              StatusPill(status: widget.sync.status, pending: pending),
              IconButton(
                tooltip: widget.conn.forceOffline ? 'Turn force offline off' : 'Force offline',
                icon: Icon(widget.conn.forceOffline ? Icons.cloud_off : Icons.cloud_outlined,
                    color: widget.conn.forceOffline ? AppColors.amber : AppColors.ink),
                onPressed: widget.conn.toggleForceOffline,
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(3),
              child: widget.sync.syncing
                  ? const LinearProgressIndicator(minHeight: 3, color: AppColors.blue)
                  : const SizedBox(height: 3),
            ),
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              RecordsScreen(db: widget.db, sync: widget.sync),
              PendingScreen(db: widget.db, conn: widget.conn, sync: widget.sync),
              HistoryScreen(db: widget.db),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.people_outline), label: 'Records'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: pending > 0,
                  label: Text('$pending'),
                  backgroundColor: AppColors.amber,
                  child: const Icon(Icons.upload_outlined),
                ),
                label: 'Pending',
              ),
              const NavigationDestination(icon: Icon(Icons.history), label: 'Sync history'),
            ],
          ),
        );
      },
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, required this.pending});

  final String status;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, dot) = switch (status) {
      'offline' => ('Offline', AppColors.amberBg, AppColors.amberInk, AppColors.amber),
      'syncing' => ('Syncing', AppColors.blueBg, AppColors.blueInk, AppColors.blue),
      _ => ('Online', AppColors.mint, AppColors.ink, AppColors.teal),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(pending > 0 ? '$label, $pending pending' : label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
      ]),
    );
  }
}
