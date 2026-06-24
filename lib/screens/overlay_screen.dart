// lib/screens/overlay_screen.dart
//
// Floating overlay over Chrome.
// States: fab → menu → addPattern → patternList → lineEditor

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../services/saved_pattern.dart';
import '../services/telegram_service.dart';

@pragma('vm:entry-point')
void overlayMain() {
  runApp(const OverlayApp());
}

class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: const OverlayRoot(),
      );
}

// ─── Root: handles channel messages + passes state down ──────────────────────

class OverlayRoot extends StatefulWidget {
  const OverlayRoot({super.key});
  @override
  State<OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<OverlayRoot> {
  double? _chartPct;
  bool _monitoring = false;
  String? _lastTriggerText;
  String? _lastTriggerDir;

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data == null || data is! Map) return;
      setState(() {
        if (data['pct'] != null) _chartPct = (data['pct'] as num).toDouble();
        if (data['monitoring'] != null) _monitoring = data['monitoring'] as bool;
        if (data['trigger'] != null) {
          final t = data['trigger'] as Map;
          _lastTriggerText =
              '${t['pattern']} · L${t['line']} · ${(t['pct'] as num).toStringAsFixed(1)}%';
          _lastTriggerDir = t['direction'] as String?;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => OverlayWidget(
        chartPct: _chartPct,
        monitoring: _monitoring,
        lastTriggerText: _lastTriggerText,
        lastTriggerDir: _lastTriggerDir,
      );
}

// ─── Main overlay widget ──────────────────────────────────────────────────────

enum _OverlayState { fab, menu, addPattern, patternList }

class OverlayWidget extends StatefulWidget {
  final double? chartPct;
  final bool monitoring;
  final String? lastTriggerText;
  final String? lastTriggerDir;

  const OverlayWidget({
    super.key, this.chartPct, this.monitoring = false,
    this.lastTriggerText, this.lastTriggerDir,
  });

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  _OverlayState _view = _OverlayState.fab;
  List<SavedPattern> _patterns = [];

  // Add pattern form state
  final _nameCtrl = TextEditingController();
  late List<LineConfig> _draftLines;
  int? _editingLineIndex;

  // Channel to send commands to main app
  static const _channel = MethodChannel('com.example.game_recorder/overlay_cmd');

  @override
  void initState() {
    super.initState();
    _draftLines = SavedPattern.defaultLines();
    _loadPatterns();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPatterns() async {
    final list = await PatternStore.loadAll();
    if (mounted) setState(() => _patterns = list);
  }

  void _sendCmd(String cmd, [Map<String, dynamic>? args]) {
    try {
      _channel.invokeMethod(cmd, args);
    } catch (_) {}
  }

  void _startMonitoring() {
    _sendCmd('start');
    setState(() => _view = _OverlayState.fab);
  }

  void _stopMonitoring() {
    _sendCmd('stop');
    setState(() => _view = _OverlayState.fab);
  }

  Future<void> _savePattern() async {
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Pattern ${DateTime.now().millisecondsSinceEpoch}'
        : _nameCtrl.text.trim();
    final pattern = SavedPattern(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      lines: _draftLines,
      active: true,
    );
    await PatternStore.upsert(pattern);
    _sendCmd('refresh');
    _nameCtrl.clear();
    _draftLines = SavedPattern.defaultLines();
    await _loadPatterns();
    setState(() => _view = _OverlayState.fab);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _buildView(),
    );
  }

  Widget _buildView() {
    switch (_view) {
      case _OverlayState.fab:
        return _buildFab();
      case _OverlayState.menu:
        return _buildMenu();
      case _OverlayState.addPattern:
        return _editingLineIndex != null
            ? _buildLineEditor(_editingLineIndex!)
            : _buildAddPattern();
      case _OverlayState.patternList:
        return _buildPatternList();
    }
  }

  // ── FAB ────────────────────────────────────────────────────────────────────

  Widget _buildFab() {
    final monitoring = widget.monitoring;
    final pct = widget.chartPct;

    return GestureDetector(
      onTap: () => setState(() => _view = _OverlayState.menu),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: monitoring ? const Color(0xFF0d2b1e) : const Color(0xFF161b22),
          border: Border.all(
            color: monitoring ? Colors.tealAccent : Colors.white24,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10),
            if (monitoring)
              BoxShadow(
                  color: Colors.tealAccent.withOpacity(0.3), blurRadius: 16),
          ],
        ),
        child: Center(
          child: pct != null && monitoring
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    pct >= 0 ? '▲' : '▼',
                    style: TextStyle(
                      color: pct >= 0 ? Colors.green : Colors.red,
                      fontSize: 10,
                      height: 1,
                    ),
                  ),
                  Text(
                    '${pct.abs().toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: pct >= 0 ? Colors.green : Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                ])
              : Icon(
                  monitoring ? Icons.radar : Icons.add_chart,
                  color: monitoring ? Colors.tealAccent : Colors.white54,
                  size: 22,
                ),
        ),
      ),
    );
  }

  // ── Menu ───────────────────────────────────────────────────────────────────

  Widget _buildMenu() {
    final monitoring = widget.monitoring;
    final pct = widget.chartPct;
    final inRange = pct != null && pct.abs() <= 30;

    return _panel(
      width: 220,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header with live %
        _header(
          Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: monitoring ? Colors.tealAccent : Colors.white24,
              ),
            ),
            const SizedBox(width: 8),
            if (pct != null)
              Text(
                '${pct >= 0 ? '▲' : '▼'} ${pct.abs().toStringAsFixed(1)}%  ${inRange ? '✅' : '⚠️'}',
                style: TextStyle(
                  color: inRange ? Colors.tealAccent : Colors.orange,
                  fontSize: 13, fontWeight: FontWeight.bold,
                ),
              )
            else
              Text(
                monitoring ? 'Reading…' : 'Not monitoring',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ]),
          onClose: () => setState(() => _view = _OverlayState.fab),
        ),

        // Last trigger
        if (widget.lastTriggerText != null)
          Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (widget.lastTriggerDir == 'up' ? Colors.green : Colors.red)
                  .withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${widget.lastTriggerDir == 'up' ? '📈' : '📉'} ${widget.lastTriggerText}',
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ),

        const Divider(height: 1, color: Colors.white10),

        // Menu buttons
        _menuBtn(
          icon: monitoring ? Icons.stop_circle : Icons.play_circle,
          label: monitoring ? 'Stop Monitoring' : 'Start Monitoring',
          color: monitoring ? Colors.redAccent : Colors.tealAccent,
          onTap: monitoring ? _stopMonitoring : _startMonitoring,
        ),
        _menuBtn(
          icon: Icons.add_circle_outline,
          label: 'Add Pattern',
          color: Colors.tealAccent,
          onTap: () {
            _nameCtrl.clear();
            _draftLines = SavedPattern.defaultLines();
            setState(() => _view = _OverlayState.addPattern);
          },
        ),
        _menuBtn(
          icon: Icons.list_alt,
          label: 'Patterns (${_patterns.length})',
          color: Colors.white70,
          onTap: () {
            _loadPatterns();
            setState(() => _view = _OverlayState.patternList);
          },
        ),
        _menuBtn(
          icon: Icons.settings_outlined,
          label: 'Telegram Settings',
          color: Colors.white38,
          onTap: _showTelegramSettings,
        ),
      ]),
    );
  }

  // ── Add Pattern ────────────────────────────────────────────────────────────

  Widget _buildAddPattern() {
    return _panel(
      width: 280,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _header(
          const Text('New Pattern',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          onClose: () => setState(() => _view = _OverlayState.menu),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Pattern name…',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF0d1117),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Lines A B C D
        ..._draftLines.asMap().entries.map((e) {
          final i = e.key;
          final line = e.value;
          final color = _lineColor(line.label);
          return Container(
            margin: const EdgeInsets.fromLTRB(10, 2, 10, 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: line.enabled
                  ? color.withOpacity(0.08)
                  : const Color(0xFF0d1117),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: line.enabled ? color.withOpacity(0.4) : Colors.white10),
            ),
            child: Row(children: [
              // Label
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color),
                ),
                child: Center(
                  child: Text(line.label,
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: line.enabled
                    ? Text(
                        '${line.value >= 0 ? '+' : ''}${line.value.toStringAsFixed(1)}%  ${line.direction == BetDirection.up ? '📈' : '📉'}  ±${line.tolerance}%',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      )
                    : const Text('Disabled',
                        style: TextStyle(color: Colors.white24, fontSize: 11)),
              ),
              // Enable toggle
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: line.enabled,
                  activeColor: color,
                  onChanged: (v) => setState(() {
                    _draftLines[i] = line.copyWith(enabled: v);
                  }),
                ),
              ),
              // Edit button
              if (line.enabled)
                GestureDetector(
                  onTap: () => setState(() => _editingLineIndex = i),
                  child: Icon(Icons.tune, size: 16, color: color),
                ),
            ]),
          );
        }),

        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: () => setState(() => _view = _OverlayState.menu),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: _savePattern,
                child: const Text('Save',
                    style: TextStyle(
                        color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Line Editor (inline) ──────────────────────────────────────────────────

  Widget _buildLineEditor(int index) {
    final line = _draftLines[index];
    final color = _lineColor(line.label);
    final valueCtrl = TextEditingController(
        text: line.value == 0 ? '' : line.value.toString());
    final msgUpCtrl = TextEditingController(text: line.telegramMessageUp);
    final msgDownCtrl = TextEditingController(text: line.telegramMessageDown);

    return StatefulBuilder(builder: (context, setLS) {
      var ttype = line.triggerType;
      var dir = line.direction;
      var tol = line.tolerance;

      return _panel(
        width: 290,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _header(
            Text('Line ${line.label} Settings',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
            onClose: () => setState(() => _editingLineIndex = null),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: valueCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'e.g. 18 or -5.5',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 16),
                filled: true,
                fillColor: const Color(0xFF0d1117),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                suffixText: '%',
                suffixStyle: TextStyle(color: color, fontSize: 18),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: color)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: color.withOpacity(0.4))),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Direction row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              const Text('Direction:',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 8),
              _chip('📈 UP', dir == BetDirection.up, color,
                  () => setLS(() => dir = BetDirection.up)),
              const SizedBox(width: 6),
              _chip('📉 DOWN', dir == BetDirection.down, Colors.redAccent,
                  () => setLS(() => dir = BetDirection.down)),
            ]),
          ),
          const SizedBox(height: 6),

          // Trigger type row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              const Text('Trigger:',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 8),
              _chip('Touch', ttype == TriggerType.touch, color,
                  () => setLS(() => ttype = TriggerType.touch)),
              const SizedBox(width: 4),
              _chip('Cross', ttype == TriggerType.passThrough, color,
                  () => setLS(() => ttype = TriggerType.passThrough)),
            ]),
          ),
          const SizedBox(height: 6),

          // Tolerance
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Text('±${tol.toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: tol, min: 0.1, max: 5.0, divisions: 49,
                  activeColor: color,
                  onChanged: (v) => setLS(
                      () => tol = double.parse(v.toStringAsFixed(1))),
                ),
              ),
            ]),
          ),

          // Telegram messages
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('📈 UP message:',
                  style: TextStyle(color: Colors.green, fontSize: 11)),
              const SizedBox(height: 4),
              _smallTextField(msgUpCtrl, 'BET UP message…'),
              const SizedBox(height: 6),
              const Text('📉 DOWN message:',
                  style: TextStyle(color: Colors.redAccent, fontSize: 11)),
              const SizedBox(height: 4),
              _smallTextField(msgDownCtrl, 'BET DOWN message…'),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onPressed: () => setState(() => _editingLineIndex = null),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onPressed: () {
                    final val = double.tryParse(valueCtrl.text.trim()) ?? 0.0;
                    setState(() {
                      _draftLines[index] = _draftLines[index].copyWith(
                        value: val, triggerType: ttype, direction: dir,
                        tolerance: tol,
                        telegramMessageUp: msgUpCtrl.text.trim().isEmpty
                            ? '📈 BET UP triggered!'
                            : msgUpCtrl.text.trim(),
                        telegramMessageDown: msgDownCtrl.text.trim().isEmpty
                            ? '📉 BET DOWN triggered!'
                            : msgDownCtrl.text.trim(),
                      );
                      _editingLineIndex = null;
                    });
                  },
                  child: const Text('Apply',
                      style: TextStyle(
                          color: Colors.white, fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ]),
      );
    });
  }

  // ── Pattern List ───────────────────────────────────────────────────────────

  Widget _buildPatternList() {
    return _panel(
      width: 270,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _header(
          const Text('Patterns',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          onClose: () => setState(() => _view = _OverlayState.menu),
        ),

        if (_patterns.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No patterns yet.\nTap + to add one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          )
        else
          ..._patterns.map((p) {
            final enabledLines = p.lines.where((l) => l.enabled).toList();
            return Container(
              margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: p.active
                    ? Colors.tealAccent.withOpacity(0.06)
                    : const Color(0xFF0d1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: p.active
                      ? Colors.tealAccent.withOpacity(0.3)
                      : Colors.white10,
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(p.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                  // ON/OFF
                  GestureDetector(
                    onTap: () async {
                      await PatternStore.upsert(p.copyWith(active: !p.active));
                      _sendCmd('refresh');
                      await _loadPatterns();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.active
                            ? Colors.tealAccent.withOpacity(0.15)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: p.active ? Colors.tealAccent : Colors.white24),
                      ),
                      child: Text(
                        p.active ? 'ON' : 'OFF',
                        style: TextStyle(
                          color: p.active ? Colors.tealAccent : Colors.white38,
                          fontSize: 10, fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () async {
                      await PatternStore.delete(p.id);
                      _sendCmd('refresh');
                      await _loadPatterns();
                    },
                    child: const Icon(Icons.delete_outline,
                        color: Colors.white24, size: 16),
                  ),
                ]),
                if (enabledLines.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4, runSpacing: 4,
                    children: enabledLines.map((l) {
                      final c = _lineColor(l.label);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: c.withOpacity(0.4)),
                        ),
                        child: Text(
                          '${l.label} ${l.value >= 0 ? '+' : ''}${l.value.toStringAsFixed(1)}% ${l.direction == BetDirection.up ? '📈' : '📉'}',
                          style: TextStyle(color: c, fontSize: 9),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ]),
            );
          }),

        // Add new pattern shortcut
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.tealAccent.withOpacity(0.4)),
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
              onPressed: () {
                _nameCtrl.clear();
                _draftLines = SavedPattern.defaultLines();
                setState(() => _view = _OverlayState.addPattern);
              },
              icon: const Icon(Icons.add, color: Colors.tealAccent, size: 14),
              label: const Text('Add New Pattern',
                  style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _panel({required Widget child, double width = 240}) => Container(
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xF0161b22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.tealAccent.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.7), blurRadius: 20)
          ],
        ),
        child: child,
      );

  Widget _header(Widget title, {required VoidCallback onClose}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.tealAccent.withOpacity(0.06),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Row(children: [
          Expanded(child: title),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close, color: Colors.white38, size: 18),
          ),
        ]),
      );

  Widget _menuBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w500)),
          ]),
        ),
      );

  Widget _chip(String label, bool selected, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? color : Colors.white24),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? color : Colors.white38, fontSize: 11)),
        ),
      );

  Widget _smallTextField(TextEditingController ctrl, String hint) => TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 11),
        maxLines: 2,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
          filled: true,
          fillColor: const Color(0xFF0d1117),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none),
        ),
      );

  Color _lineColor(String label) => switch (label) {
        'A' => const Color(0xFFef4444),
        'B' => const Color(0xFF22c55e),
        'C' => const Color(0xFFb91c1c),
        _ => const Color(0xFF15803d),
      };

  void _showTelegramSettings() {
    // Can't show dialog from overlay easily — send command to main app
    _sendCmd('openTelegramSettings');
  }
}
