import 'package:flutter/material.dart';

/// Same palette as the web client, so the two read as one product in the demo.
class AppColors {
  static const ink = Color(0xFF12343B);
  static const muted = Color(0xFF5E6B6E);
  static const line = Color(0xFFE3E8E6);
  static const bg = Color(0xFFF5F8F7);
  static const teal = Color(0xFF1F7A6D);
  static const mint = Color(0xFFDDEFE8);
  static const amber = Color(0xFFA86B12);
  static const amberBg = Color(0xFFFCF0DA);
  static const amberInk = Color(0xFF7A4E0E);
  static const red = Color(0xFFB4432F);
  static const redBg = Color(0xFFF8E3DD);
  static const redInk = Color(0xFF8A3324);
  static const blue = Color(0xFF2B7BB9);
  static const blueBg = Color(0xFFE3F0FA);
  static const blueInk = Color(0xFF1D4E73);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.teal, primary: AppColors.teal, surface: Colors.white);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: AppColors.ink, elevation: 0),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

/// Small rounded label, e.g. "Synced" or "Waiting to sync".
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// Coloured box with a bold title and a line of detail.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.title, required this.body, required this.bg, required this.fg});

  final String title;
  final String body;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(body, style: TextStyle(color: fg)),
        ]),
      );
}

String ago(int? ts) {
  if (ts == null) return 'never';
  final s = (DateTime.now().millisecondsSinceEpoch - ts) ~/ 1000;
  if (s < 10) return 'just now';
  if (s < 60) return '$s s ago';
  final m = s ~/ 60;
  if (m < 60) return '$m min ago';
  final h = m ~/ 60;
  if (h < 24) return '$h h ago';
  return DateTime.fromMillisecondsSinceEpoch(ts).toString().substring(0, 16);
}

String clock(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}
