// lib/screens/line_settings_screen.dart
//
// Per-line settings: trigger type, direction, tolerance, count target,
// and custom Telegram messages for UP and DOWN.

import 'package:flutter/material.dart';
import '../services/saved_pattern.dart';

class LineSettingsScreen extends StatefulWidget {
  final String lineKey;
  final LineSettings settings;

  const LineSettingsScreen({
    super.key,
    required this.lineKey,
    required this.settings,
  });

  @override
  State<LineSettingsScreen> createState() => _LineSettingsScreenState();
}

class _LineSettingsScreenState extends State<LineSettingsScreen> {
  late TriggerType _triggerType;
  late BetDirection _direction;
  late double _tolerance;
  late int _countTarget;
  late TextEditingController _msgUpCtrl;
  late TextEditingController _msgDownCtrl;

  @override
  void initState() {
    super.initState();
    _triggerType = widget.settings.triggerType;
    _direction = widget.settings.direction;
    _tolerance = widget.settings.tolerance;
    _countTarget = widget.settings.countTarget;
    _msgUpCtrl =
        TextEditingController(text: widget.settings.telegramMessageUp);
    _msgDownCtrl =
        TextEditingController(text: widget.settings.telegramMessageDown);
  }

  @override
  void dispose() {
    _msgUpCtrl.dispose();
    _msgDownCtrl.dispose();
    super.dispose();
  }

  Color get _lineColor => switch (widget.lineKey) {
        'a' => const Color(0xFFef4444),
        'b' => const Color(0xFF22c55e),
        'c' => const Color(0xFFb91c1c),
        _ => const Color(0xFF15803d),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        title: Text(
          'Line ${widget.lineKey.toUpperCase()} Settings',
          style: TextStyle(color: _lineColor, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(
                    color: Colors.tealAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Trigger Type ────────────────────────────────────────────────
          _sectionHeader('Trigger Type'),
          _card(
            child: Column(children: [
              _radioTile(
                title: 'Touch',
                subtitle: 'Alert when chart reaches this line value',
                value: TriggerType.touch,
                groupValue: _triggerType,
                onChanged: (v) => setState(() => _triggerType = v!),
              ),
              _divider(),
              _radioTile(
                title: 'Pass Through',
                subtitle: 'Alert every time chart crosses this line',
                value: TriggerType.passThrough,
                groupValue: _triggerType,
                onChanged: (v) => setState(() => _triggerType = v!),
              ),
              _divider(),
              _radioTile(
                title: 'Count',
                subtitle: 'Alert after chart crosses line N times',
                value: TriggerType.count,
                groupValue: _triggerType,
                onChanged: (v) => setState(() => _triggerType = v!),
              ),
              if (_triggerType == TriggerType.count) ...[
                _divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Cross count target',
                          style: TextStyle(color: Colors.white70)),
                      Row(children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.white54),
                          onPressed: _countTarget > 1
                              ? () =>
                                  setState(() => _countTarget--)
                              : null,
                        ),
                        Text('$_countTarget',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: Colors.tealAccent),
                          onPressed: () =>
                              setState(() => _countTarget++),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),

          // ── Bet Direction ───────────────────────────────────────────────
          _sectionHeader('Bet Direction'),
          _card(
            child: Column(children: [
              _radioTile(
                title: '📈 BET UP',
                subtitle: 'Auto tap UP button when triggered',
                value: BetDirection.up,
                groupValue: _direction,
                onChanged: (v) => setState(() => _direction = v!),
              ),
              _divider(),
              _radioTile(
                title: '📉 BET DOWN',
                subtitle: 'Auto tap DOWN button when triggered',
                value: BetDirection.down,
                groupValue: _direction,
                onChanged: (v) => setState(() => _direction = v!),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Tolerance ───────────────────────────────────────────────────
          _sectionHeader('Range Tolerance  ±${_tolerance.toStringAsFixed(1)}%'),
          _card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Column(children: [
                Slider(
                  value: _tolerance,
                  min: 0.1,
                  max: 5.0,
                  divisions: 49,
                  label: '±${_tolerance.toStringAsFixed(1)}%',
                  activeColor: _lineColor,
                  onChanged: (v) =>
                      setState(() => _tolerance = double.parse(v.toStringAsFixed(1))),
                ),
                Text(
                  'Trigger when chart is within ±${_tolerance.toStringAsFixed(1)}% of this line',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // ── Telegram Messages ───────────────────────────────────────────
          _sectionHeader('Telegram Messages'),
          _card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📈 Message for BET UP:',
                      style: TextStyle(
                          color: Colors.green, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _msgUpCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Enter UP message…',
                      hintStyle:
                          const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: const Color(0xFF0d1117),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('📉 Message for BET DOWN:',
                      style: TextStyle(
                          color: Colors.redAccent, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _msgDownCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Enter DOWN message…',
                      hintStyle:
                          const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: const Color(0xFF0d1117),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: _lineColor),
            onPressed: _save,
            child: Text(
              'Save Line ${widget.lineKey.toUpperCase()} Settings',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _save() {
    final result = LineSettings(
      triggerType: _triggerType,
      direction: _direction,
      tolerance: _tolerance,
      countTarget: _countTarget,
      telegramMessageUp: _msgUpCtrl.text.trim().isEmpty
          ? '📈 BET UP triggered!'
          : _msgUpCtrl.text.trim(),
      telegramMessageDown: _msgDownCtrl.text.trim().isEmpty
          ? '📉 BET DOWN triggered!'
          : _msgDownCtrl.text.trim(),
    );
    Navigator.pop(context, result);
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5)),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _divider() =>
      const Divider(height: 1, color: Colors.white10, indent: 16);

  Widget _radioTile<T>({
    required String title,
    required String subtitle,
    required T value,
    required T groupValue,
    required ValueChanged<T?> onChanged,
  }) {
    return RadioListTile<T>(
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      activeColor: _lineColor,
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Text(subtitle,
          style:
              const TextStyle(color: Colors.white38, fontSize: 12)),
    );
  }
}
