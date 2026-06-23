// lib/screens/overlay_screen.dart
//
// Floating overlay shown above Chrome/game.
// Shows live % reading, monitoring status, and last trigger.

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

@pragma('vm:entry-point')
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
  bool _expanded = true;
  double? _chartPct;
  String? _lastTrigger;
  String? _triggerDirection;

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data == null) return;
      if (data is Map) {
        setState(() {
          if (data['pct'] != null) {
            _chartPct = (data['pct'] as num).toDouble();
          }
          if (data['trigger'] != null) {
            final t = data['trigger'] as Map;
            _lastTrigger =
                '${t['pattern']} · Line ${t['line']} · ${(t['pct'] as num).toStringAsFixed(1)}%';
            _triggerDirection = t['direction'] as String?;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pct = _chartPct;
    final inRange = pct != null && pct.abs() <= 30;
    final isUp = pct != null && pct >= 0;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xEE161b22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: inRange
                ? Colors.tealAccent.withOpacity(0.6)
                : Colors.white24,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 16)
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────
            GestureDetector(
              onTap: () =>
                  setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(14),
                    bottom: _expanded
                        ? Radius.zero
                        : const Radius.circular(14),
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.tealAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('LIVE',
                      style: TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(width: 8),
                  if (pct != null)
                    Text(
                      '${pct >= 0 ? '▲' : '▼'} ${pct.abs().toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: isUp ? Colors.green : Colors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    const Text('Reading…',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 12)),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: Colors.white38,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () =>
                        FlutterOverlayWindow.closeOverlay(),
                    child: const Icon(Icons.close,
                        color: Colors.white38, size: 18),
                  ),
                ]),
              ),
            ),

            // ── Expanded content ─────────────────────────────────
            if (_expanded) ...[
              // Range indicator
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                child: Text(
                  pct == null
                      ? 'Waiting for screen data…'
                      : (inRange
                          ? '✅ In range (-30% to +30%) — Monitoring'
                          : '⚠️ Out of range — Paused'),
                  style: TextStyle(
                    color: inRange ? Colors.tealAccent : Colors.orange,
                    fontSize: 11,
                  ),
                ),
              ),

              // Last trigger
              if (_lastTrigger != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (_triggerDirection == 'up'
                            ? Colors.green
                            : Colors.red)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (_triggerDirection == 'up'
                              ? Colors.green
                              : Colors.red)
                          .withOpacity(0.4),
                    ),
                  ),
                  child: Row(children: [
                    Text(
                      _triggerDirection == 'up' ? '📈' : '📉',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _lastTrigger!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ]),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
