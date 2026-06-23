// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../services/saved_pattern.dart';
import '../services/monitor_service.dart';
import '../services/telegram_service.dart';
import '../services/overlay_service.dart';
import 'pattern_editor_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<SavedPattern> _patterns = [];
  bool _monitoring = false;
  bool _overlayVisible = false;
  bool _overlayPermission = false;
  double? _liveChartPct;
  TriggerEvent? _lastTrigger;

  @override
  void initState() {
    super.initState();
    _load();
    _checkOverlayPermission();
    MonitorService.instance.onValueUpdate = (pct) {
      if (mounted) setState(() => _liveChartPct = pct);
    };
    MonitorService.instance.onTrigger = (event) {
      if (mounted) setState(() => _lastTrigger = event);
      // Forward to overlay
      OverlayService.sendData({
        'trigger': {
          'pattern': event.patternName,
          'line': event.lineLabel,
          'pct': event.chartPct,
          'direction': event.direction.name,
        }
      });
    };
  }

  Future<void> _load() async {
    final list = await PatternStore.loadAll();
    setState(() => _patterns = list);
    MonitorService.instance.setPatterns(list);
  }

  Future<void> _checkOverlayPermission() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    setState(() => _overlayPermission = granted);
  }

  Future<void> _toggleMonitoring() async {
    if (_monitoring) {
      MonitorService.instance.stop();
      if (_overlayVisible) {
        await OverlayService.hideOverlay();
        setState(() => _overlayVisible = false);
      }
      setState(() {
        _monitoring = false;
        _liveChartPct = null;
      });
    } else {
      if (!_overlayPermission) {
        await FlutterOverlayWindow.requestPermission();
        await _checkOverlayPermission();
        if (!_overlayPermission) return;
      }
      MonitorService.instance.setPatterns(_patterns);
      MonitorService.instance.start();
      await OverlayService.showOverlay();
      setState(() {
        _monitoring = true;
        _overlayVisible = true;
      });
    }
  }

  Future<void> _togglePatternActive(SavedPattern p) async {
    final updated = p.copyWith(active: !p.active);
    await PatternStore.upsert(updated);
    await _load();
    if (_monitoring) {
      MonitorService.instance.setPatterns(_patterns);
    }
  }

  Future<void> _deletePattern(String id) async {
    await PatternStore.delete(id);
    await _load();
  }

  Future<void> _openEditor([SavedPattern? pattern]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatternEditorScreen(existing: pattern),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        title: const Text('Game Recorder',
            style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white54),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: Column(children: [
        // ── Live Monitor Banner ──────────────────────────────────
        _buildMonitorBanner(),
        // ── Patterns List ────────────────────────────────────────
        Expanded(child: _buildPatternsList()),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.tealAccent,
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  Widget _buildMonitorBanner() {
    final pct = _liveChartPct;
    final inRange = pct != null && pct.abs() <= 30;

    return GestureDetector(
      onTap: _toggleMonitoring,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        decoration: BoxDecoration(
          color: _monitoring
              ? (inRange
                  ? Colors.tealAccent.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.08))
              : const Color(0xFF161b22),
          border: Border(
            bottom: BorderSide(
              color: _monitoring
                  ? (inRange ? Colors.tealAccent : Colors.orange)
                  : Colors.white10,
            ),
          ),
        ),
        child: Row(children: [
          // Status dot
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _monitoring
                  ? (inRange ? Colors.tealAccent : Colors.orange)
                  : Colors.white24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _monitoring ? 'LIVE MONITORING' : 'TAP TO START',
                  style: TextStyle(
                    color: _monitoring ? Colors.tealAccent : Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                if (_monitoring && pct != null)
                  Text(
                    '${pct >= 0 ? '▲' : '▼'} ${pct.abs().toStringAsFixed(1)}%  ${inRange ? '· In range' : '· Out of range (>30%)'}',
                    style: TextStyle(
                      color: inRange ? Colors.white70 : Colors.orange,
                      fontSize: 12,
                    ),
                  )
                else if (_monitoring)
                  const Text('Reading screen…',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 12)),
                if (_lastTrigger != null && _monitoring)
                  Text(
                    '🎯 ${_lastTrigger!.patternName} · Line ${_lastTrigger!.lineLabel} · ${_lastTrigger!.direction == BetDirection.up ? 'BET UP 📈' : 'BET DOWN 📉'}',
                    style: const TextStyle(
                        color: Colors.yellow, fontSize: 11),
                  ),
              ],
            ),
          ),
          // Start/Stop button
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _monitoring
                  ? Colors.redAccent.withOpacity(0.15)
                  : Colors.tealAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _monitoring ? Colors.redAccent : Colors.tealAccent,
              ),
            ),
            child: Text(
              _monitoring ? 'STOP' : 'START',
              style: TextStyle(
                color: _monitoring ? Colors.redAccent : Colors.tealAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildPatternsList() {
    if (_patterns.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add_chart, size: 64, color: Colors.white12),
          const SizedBox(height: 16),
          const Text('No patterns yet.',
              style:
                  TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Tap + to create your first pattern.',
              style:
                  TextStyle(color: Colors.white38, fontSize: 13)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: _patterns.length,
      itemBuilder: (context, i) => _patternCard(_patterns[i]),
    );
  }

  Widget _patternCard(SavedPattern p) {
    final enabledLines = p.lines.where((l) => l.enabled).toList();

    return Card(
      color: const Color(0xFF161b22),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: p.active ? Colors.tealAccent.withOpacity(0.4) : Colors.white10,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Expanded(
              child: Text(p.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ),
            // Active toggle
            GestureDetector(
              onTap: () => _togglePatternActive(p),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: p.active
                      ? Colors.tealAccent.withOpacity(0.15)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: p.active ? Colors.tealAccent : Colors.white24,
                  ),
                ),
                child: Text(
                  p.active ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: p.active ? Colors.tealAccent : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: Colors.white38, size: 18),
              onPressed: () => _openEditor(p),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.white24, size: 18),
              onPressed: () => _confirmDelete(p.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
          const SizedBox(height: 10),
          // Lines summary
          if (enabledLines.isEmpty)
            const Text('No lines enabled',
                style: TextStyle(color: Colors.white24, fontSize: 12))
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: p.lines.map((line) {
                final color = _lineColor(line.label);
                return Opacity(
                  opacity: line.enabled ? 1.0 : 0.3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withOpacity(0.5)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        line.label,
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${line.value >= 0 ? '+' : ''}${line.value.toStringAsFixed(1)}%',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        line.direction == BetDirection.up ? '📈' : '📉',
                        style: const TextStyle(fontSize: 10),
                      ),
                      if (!line.enabled)
                        const Text(' OFF',
                            style: TextStyle(
                                color: Colors.white24, fontSize: 9)),
                    ]),
                  ),
                );
              }).toList(),
            ),
        ]),
      ),
    );
  }

  Color _lineColor(String label) => switch (label) {
        'A' => const Color(0xFFef4444),
        'B' => const Color(0xFF22c55e),
        'C' => const Color(0xFFb91c1c),
        _ => const Color(0xFF15803d),
      };

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF21262d),
        title: const Text('Delete Pattern?',
            style: TextStyle(color: Colors.white)),
        content: const Text('This cannot be undone.',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePattern(id);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showSettings() {
    final tokenCtrl = TextEditingController();
    final chatCtrl = TextEditingController();
    AppSettings.getBotToken().then((t) => tokenCtrl.text = t);
    AppSettings.getChatId().then((c) => chatCtrl.text = c);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF21262d),
        title: const Text('Telegram Settings',
            style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: tokenCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Bot Token',
              labelStyle: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: chatCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Chat ID',
              labelStyle: TextStyle(color: Colors.white54),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent),
            onPressed: () async {
              await AppSettings.saveBotToken(tokenCtrl.text.trim());
              await AppSettings.saveChatId(chatCtrl.text.trim());
              Navigator.pop(context);
              await TelegramService.testConnection();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Saved! Test message sent.')),
                );
              }
            },
            child: const Text('Save',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}
