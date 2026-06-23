// lib/screens/pattern_editor_screen.dart

import 'package:flutter/material.dart';
import '../services/saved_pattern.dart';

class PatternEditorScreen extends StatefulWidget {
  final SavedPattern? existing;
  const PatternEditorScreen({super.key, this.existing});

  @override
  State<PatternEditorScreen> createState() => _PatternEditorScreenState();
}

class _PatternEditorScreenState extends State<PatternEditorScreen> {
  late TextEditingController _nameCtrl;
  late List<LineConfig> _lines;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: widget.existing?.name ?? '');
    _lines = widget.existing?.lines != null
        ? List.from(widget.existing!.lines)
        : SavedPattern.defaultLines();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Color _lineColor(String label) => switch (label) {
        'A' => const Color(0xFFef4444),
        'B' => const Color(0xFF22c55e),
        'C' => const Color(0xFFb91c1c),
        _ => const Color(0xFF15803d),
      };

  void _editLine(int index) async {
    final result = await Navigator.push<LineConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => LineEditorScreen(config: _lines[index]),
      ),
    );
    if (result != null) {
      setState(() => _lines[index] = result);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Pattern ${DateTime.now().millisecondsSinceEpoch}'
        : _nameCtrl.text.trim();

    final pattern = SavedPattern(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      lines: _lines,
      active: widget.existing?.active ?? true,
    );

    await PatternStore.upsert(pattern);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        title: Text(
          widget.existing == null ? 'New Pattern' : 'Edit Pattern',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(
                    color: Colors.tealAccent,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Pattern name
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Pattern Name',
              labelStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF161b22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              hintText: 'e.g. Morning Pattern',
              hintStyle: const TextStyle(color: Colors.white24),
            ),
          ),
          const SizedBox(height: 24),

          const Text('LINES',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          const SizedBox(height: 10),

          // 4 line cards
          ..._lines.asMap().entries.map((e) {
            final i = e.key;
            final line = e.value;
            final color = _lineColor(line.label);

            return Card(
              color: const Color(0xFF161b22),
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: line.enabled
                      ? color.withOpacity(0.5)
                      : Colors.white10,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      // Line label badge
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color),
                        ),
                        child: Center(
                          child: Text(line.label,
                              style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.enabled
                                  ? '${line.value >= 0 ? '+' : ''}${line.value.toStringAsFixed(1)}%  ·  ${line.direction == BetDirection.up ? '📈 UP' : '📉 DOWN'}  ·  ±${line.tolerance}%'
                                  : 'Disabled',
                              style: TextStyle(
                                color: line.enabled
                                    ? Colors.white
                                    : Colors.white38,
                                fontSize: 13,
                              ),
                            ),
                            if (line.enabled)
                              Text(
                                line.triggerType.name,
                                style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                      // Enable/Disable toggle
                      Switch(
                        value: line.enabled,
                        activeColor: color,
                        onChanged: (v) {
                          setState(() {
                            _lines[i] = line.copyWith(enabled: v);
                          });
                        },
                      ),
                    ]),
                    if (line.enabled) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: color.withOpacity(0.4)),
                          ),
                          onPressed: () => _editLine(i),
                          icon: Icon(Icons.tune,
                              size: 14, color: color),
                          label: Text('Configure Line ${line.label}',
                              style: TextStyle(
                                  color: color, fontSize: 13)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _save,
            child: const Text('Save Pattern',
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Line Editor ───────────────────────────────────────────────────────────────

class LineEditorScreen extends StatefulWidget {
  final LineConfig config;
  const LineEditorScreen({super.key, required this.config});

  @override
  State<LineEditorScreen> createState() => _LineEditorScreenState();
}

class _LineEditorScreenState extends State<LineEditorScreen> {
  late TextEditingController _valueCtrl;
  late TextEditingController _msgUpCtrl;
  late TextEditingController _msgDownCtrl;
  late TriggerType _triggerType;
  late BetDirection _direction;
  late double _tolerance;
  late int _countTarget;
  late bool _enabled;

  Color get _color => switch (widget.config.label) {
        'A' => const Color(0xFFef4444),
        'B' => const Color(0xFF22c55e),
        'C' => const Color(0xFFb91c1c),
        _ => const Color(0xFF15803d),
      };

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _valueCtrl = TextEditingController(
        text: c.value == 0 ? '' : c.value.toString());
    _msgUpCtrl = TextEditingController(text: c.telegramMessageUp);
    _msgDownCtrl = TextEditingController(text: c.telegramMessageDown);
    _triggerType = c.triggerType;
    _direction = c.direction;
    _tolerance = c.tolerance;
    _countTarget = c.countTarget;
    _enabled = c.enabled;
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _msgUpCtrl.dispose();
    _msgDownCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final val = double.tryParse(_valueCtrl.text.trim()) ?? 0.0;
    final result = widget.config.copyWith(
      value: val,
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
      enabled: _enabled,
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        title: Text(
          'Line ${widget.config.label} Settings',
          style: TextStyle(
              color: _color, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(
                    color: Colors.tealAccent,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // % Value
          _section('Chart % Value'),
          TextField(
            controller: _valueCtrl,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'e.g. 18 or -5.5',
              hintStyle: const TextStyle(
                  color: Colors.white24, fontSize: 20),
              filled: true,
              fillColor: const Color(0xFF161b22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _color),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _color.withOpacity(0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _color),
              ),
              prefixText: '  ',
              suffixText: '%  ',
              suffixStyle: TextStyle(color: _color, fontSize: 20),
            ),
          ),
          const SizedBox(height: 20),

          // Trigger Type
          _section('Trigger Type'),
          _card(Column(children: [
            _radio('Touch',
                'Alert when chart reaches this % value',
                TriggerType.touch),
            _divider(),
            _radio('Pass Through',
                'Alert every time chart crosses this line',
                TriggerType.passThrough),
            _divider(),
            _radio('Count',
                'Alert after crossing N times',
                TriggerType.count),
            if (_triggerType == TriggerType.count) ...[
              _divider(),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Cross count target',
                        style:
                            TextStyle(color: Colors.white70)),
                    Row(children: [
                      IconButton(
                        icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.white54),
                        onPressed: _countTarget > 1
                            ? () => setState(() => _countTarget--)
                            : null,
                      ),
                      Text('$_countTarget',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: Icon(Icons.add_circle_outline,
                            color: _color),
                        onPressed: () =>
                            setState(() => _countTarget++),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ])),
          const SizedBox(height: 20),

          // Direction
          _section('Bet Direction'),
          _card(Column(children: [
            RadioListTile<BetDirection>(
              value: BetDirection.up,
              groupValue: _direction,
              onChanged: (v) => setState(() => _direction = v!),
              activeColor: Colors.green,
              title: const Text('📈 BET UP',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Auto action when triggered',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 12)),
            ),
            _divider(),
            RadioListTile<BetDirection>(
              value: BetDirection.down,
              groupValue: _direction,
              onChanged: (v) => setState(() => _direction = v!),
              activeColor: Colors.redAccent,
              title: const Text('📉 BET DOWN',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Auto action when triggered',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 12)),
            ),
          ])),
          const SizedBox(height: 20),

          // Tolerance
          _section(
              'Tolerance  ±${_tolerance.toStringAsFixed(1)}%'),
          _card(Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: Column(children: [
              Slider(
                value: _tolerance,
                min: 0.1,
                max: 5.0,
                divisions: 49,
                label: '±${_tolerance.toStringAsFixed(1)}%',
                activeColor: _color,
                onChanged: (v) => setState(() => _tolerance =
                    double.parse(v.toStringAsFixed(1))),
              ),
              Text(
                'Trigger when chart is within ±${_tolerance.toStringAsFixed(1)}% of ${_valueCtrl.text.isEmpty ? '?' : _valueCtrl.text}%',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12),
              ),
            ]),
          )),
          const SizedBox(height: 20),

          // Telegram messages
          _section('Telegram Messages'),
          _card(Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📈 Message when BET UP:',
                    style: TextStyle(
                        color: Colors.green, fontSize: 13)),
                const SizedBox(height: 8),
                _textField(_msgUpCtrl, 'BET UP message…'),
                const SizedBox(height: 16),
                const Text('📉 Message when BET DOWN:',
                    style: TextStyle(
                        color: Colors.redAccent, fontSize: 13)),
                const SizedBox(height: 8),
                _textField(_msgDownCtrl, 'BET DOWN message…'),
              ],
            ),
          )),
          const SizedBox(height: 32),

          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _color,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _save,
            child: Text(
              'Save Line ${widget.config.label}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
      );

  Widget _card(Widget child) => Container(
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: const Color(0xFF161b22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _divider() =>
      const Divider(height: 1, color: Colors.white10, indent: 16);

  Widget _radio(String title, String subtitle, TriggerType value) =>
      RadioListTile<TriggerType>(
        value: value,
        groupValue: _triggerType,
        onChanged: (v) => setState(() => _triggerType = v!),
        activeColor: _color,
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(subtitle,
            style:
                const TextStyle(color: Colors.white38, fontSize: 12)),
      );

  Widget _textField(TextEditingController ctrl, String hint) =>
      TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        maxLines: 3,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: const Color(0xFF0d1117),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      );
}
