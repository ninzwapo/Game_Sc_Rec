// lib/screens/overlay_screen.dart
//
// This is the widget shown in the floating overlay above Chrome.
// It displays the saved pattern lines as a compact draggable panel.
// flutter_overlay_window renders this as the overlay content.

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../services/saved_pattern.dart';

@pragma("vm:entry-point")
void overlayMain() {
  runApp(const OverlayApp());
}

class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const OverlayScreen(),
    );
  }
}

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  List<SavedPattern> _patterns = [];
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _loadPatterns();
    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data != null) _loadPatterns();
    });
  }

  Future<void> _loadPatterns() async {
    final patterns = await PatternStore.loadAll();
    setState(() => _patterns = patterns);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xE6161b22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.tealAccent.withOpacity(0.4)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 16)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(16),
                    bottom: _expanded ? Radius.zero : const Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(children: [
                      Icon(Icons.videocam, color: Colors.tealAccent, size: 16),
                      SizedBox(width: 6),
                      Text('Game Recorder', style: TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                    ]),
                    Row(children: [
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: Colors.white54, size: 18),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => FlutterOverlayWindow.closeOverlay(),
                        child: const Icon(Icons.close, color: Colors.white54, size: 18),
                      ),
                    ]),
                  ],
                ),
              ),
            ),

            if (_expanded) ...[
              if (_patterns.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No patterns saved yet.\nOpen the app to record and place lines.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                )
              else
                ..._patterns.map((p) => _patternTile(p)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _patternTile(SavedPattern p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(children: [
            _lineChip('A', p.lines.a, const Color(0xFFef4444)),
            const SizedBox(width: 6),
            _lineChip('B', p.lines.b, const Color(0xFF22c55e)),
            const SizedBox(width: 6),
            _lineChip('C', p.lines.c, const Color(0xFFb91c1c)),
            const SizedBox(width: 6),
            _lineChip('D', p.lines.d, const Color(0xFF15803d)),
          ]),
        ],
      ),
    );
  }

  Widget _lineChip(String label, double val, Color color) {
    final pct = '${val >= 0 ? '+' : ''}${val.toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label $pct', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
