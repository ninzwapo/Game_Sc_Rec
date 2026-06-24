// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../services/saved_pattern.dart';
import '../services/monitor_service.dart';
import '../services/telegram_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<SavedPattern> _patterns = [];
  bool _monitoring = false;
  bool _overlayPermission = false;
  double? _liveChartPct;
  TriggerEvent? _lastTrigger;

  static const _overlayCmd =
      MethodChannel('com.example.game_recorder/overlay_cmd');

  @override
  void initState() {
    super.initState();
    _load();
    _checkOverlayPermission();

    // Listen for commands FROM overlay
    _overlayCmd.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'start':
          _startMonitoring();
          break;
        case 'stop':
          _stopMonitoring();
          break;
        case 'refresh':
          await _load();
          break;
        case 'openTelegramSettings':
          _showTelegramSettings();
          break;
      }
    });

    MonitorService.instance.onValueUpdate = (pct) {
      if (mounted) setState(() => _liveChartPct = pct);
      // Forward to overlay
      _sendToOverlay({'pct': pct, 'monitoring': _monitoring});
    };

    MonitorService.instance.onTrigger = (event) {
      if (mounted) setState(() => _lastTrigger = event);
      _sendToOverlay({
        'pct': _liveChartPct,
        'monitoring': true,
        'trigger': {
          'pattern': event.patternName,
          'line': event.lineLabel,
          'pct': event.chartPct,
          'direction': event.direction.name,
        },
      });
    };
  }

  Future<void> _sendToOverlay(Map<String, dynamic> data) async {
    try {
      await FlutterOverlayWindow.shareData(data);
    } catch (_) {}
  }

  Future<void> _load() async {
    final list = await PatternStore.loadAll();
    if (mounted) setState(() => _patterns = list);
    MonitorService.instance.setPatterns(list);
  }

  Future<void> _checkOverlayPermission() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (mounted) setState(() => _overlayPermission = granted);
  }

  Future<void> _ensureOverlayVisible() async {
    final active = await FlutterOverlayWindow.isActive();
    if (!active) {
      await FlutterOverlayWindow.showOverlay(
        height: 600,
        width: 300,
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: 'Game Recorder',
        overlayContent: 'Tap the button to control monitoring',
        enableDrag: true,
        positionGravity: PositionGravity.auto,
      );
    }
  }

  void _startMonitoring() {
    MonitorService.instance.setPatterns(_patterns);
    MonitorService.instance.start();
    setState(() => _monitoring = true);
    _sendToOverlay({'monitoring': true, 'pct': _liveChartPct});
  }

  void _stopMonitoring() {
    MonitorService.instance.stop();
    setState(() {
      _monitoring = false;
      _liveChartPct = null;
    });
    _sendToOverlay({'monitoring': false, 'pct': null});
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
            onPressed: _showTelegramSettings,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF161b22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _monitoring
                      ? Colors.tealAccent.withOpacity(0.4)
                      : Colors.white10,
                ),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _monitoring ? Colors.tealAccent : Colors.white24,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _monitoring ? 'MONITORING ACTIVE' : 'NOT MONITORING',
                    style: TextStyle(
                      color: _monitoring ? Colors.tealAccent : Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                ]),
                if (_monitoring && _liveChartPct != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${_liveChartPct! >= 0 ? '▲' : '▼'} ${_liveChartPct!.abs().toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: _liveChartPct! >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
                if (_lastTrigger != null && _monitoring) ...[
                  const SizedBox(height: 8),
                  Text(
                    '🎯 ${_lastTrigger!.patternName} · Line ${_lastTrigger!.lineLabel} · ${_lastTrigger!.direction == BetDirection.up ? 'BET UP 📈' : 'BET DOWN 📉'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.yellow, fontSize: 12),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 20),

            // Launch overlay button
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _overlayPermission
                  ? _ensureOverlayVisible
                  : () async {
                      await FlutterOverlayWindow.requestPermission();
                      await _checkOverlayPermission();
                    },
              icon: const Icon(Icons.picture_in_picture,
                  color: Colors.black),
              label: Text(
                _overlayPermission
                    ? 'Show Floating Button'
                    : 'Allow Overlay Permission',
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
            ),
            const SizedBox(height: 12),

            // Start/Stop buttons
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _monitoring
                        ? Colors.redAccent
                        : const Color(0xFF22c55e),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed:
                      _monitoring ? _stopMonitoring : _startMonitoring,
                  icon: Icon(
                    _monitoring ? Icons.stop : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  label: Text(
                    _monitoring ? 'Stop' : 'Start',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // Patterns count
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_patterns.length} Pattern${_patterns.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13),
                ),
                Text(
                  '${_patterns.where((p) => p.active).length} active',
                  style: const TextStyle(
                      color: Colors.tealAccent, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Pattern list preview
            Expanded(
              child: _patterns.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_chart,
                              size: 48, color: Colors.white12),
                          const SizedBox(height: 12),
                          const Text(
                            'No patterns yet.\nUse the floating button over\nChrome to add patterns.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white38, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _patterns.length,
                      itemBuilder: (_, i) {
                        final p = _patterns[i];
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: p.active
                                  ? Colors.tealAccent
                                  : Colors.white24,
                            ),
                          ),
                          title: Text(p.name,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          subtitle: Text(
                            '${p.lines.where((l) => l.enabled).length}/4 lines enabled',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                          trailing: Switch(
                            value: p.active,
                            activeColor: Colors.tealAccent,
                            onChanged: (v) async {
                              await PatternStore.upsert(
                                  p.copyWith(active: v));
                              await _load();
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTelegramSettings() {
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
