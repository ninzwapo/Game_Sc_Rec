// lib/screens/recorder_screen.dart
//
// Flow:
//   1. Idle — REC button + toggle overlay
//   2. Countdown 3s — switch to Chrome
//   3. Recording 10s — captures screen in background
//   4. Playback — recorded chart shown, drag lines A→B→C→D, lock each
//   5. Save — name and save pattern
//   6. Patterns list — all saved patterns, tap to edit or delete

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import '../services/saved_pattern.dart';
import '../services/overlay_service.dart';
import '../widgets/line_chart_widget.dart';

enum _State { idle, countdown, recording, saving, playback, saveDialog, patterns }

const _lineKeys = ['a', 'b', 'c', 'd'];
const _lineNames = ['A — Near-down', 'B — Near-up', 'C — Far-down', 'D — Far-up'];

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  _State _state = _State.idle;
  int _countdown = 3;
  int _elapsed = 0;
  String? _savedVideoPath;
  Timer? _timer;
  bool _overlayVisible = false;
  bool _overlayPermission = false;

  // Simulated chart data from the recording
  // In a real implementation this would be pixel-sampled from the video frames
  List<double> _chartData = [];

  // Line placement state
  int _activeLineIndex = 0;
  Map<String, double> _linePositions = {'a': 0.65, 'b': 0.35, 'c': 0.78, 'd': 0.22};
  Map<String, bool> _lineLocked = {'a': false, 'b': false, 'c': false, 'd': false};

  // Save dialog
  final _nameController = TextEditingController();

  // Patterns list
  List<SavedPattern> _patterns = [];

  @override
  void initState() {
    super.initState();
    _checkOverlayPermission();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _checkOverlayPermission() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    setState(() => _overlayPermission = granted);
  }

  Future<void> _requestOverlayPermission() async {
    await FlutterOverlayWindow.requestPermission();
    await _checkOverlayPermission();
  }

  Future<void> _toggleOverlay() async {
    if (!_overlayPermission) {
      await _requestOverlayPermission();
      return;
    }
    if (_overlayVisible) {
      await FlutterOverlayWindow.closeOverlay();
      setState(() => _overlayVisible = false);
    } else {
      await OverlayService.showOverlay();
      setState(() => _overlayVisible = true);
    }
  }

  // ─── Recording flow ────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    // Request permissions
    await Permission.photos.request();
    await Permission.videos.request();
    await Permission.storage.request();

    setState(() { _state = _State.countdown; _countdown = 3; });

    int c = 3;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      c--;
      setState(() => _countdown = c);
      if (c <= 0) { t.cancel(); _beginCapture(); }
    });
  }

  Future<void> _beginCapture() async {
    final fileName = 'rec_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
    final started = await FlutterScreenRecording.startRecordScreen(fileName);
    if (!started) {
      setState(() => _state = _State.idle);
      return;
    }

    setState(() { _state = _State.recording; _elapsed = 0; });

    int e = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      e++;
      setState(() => _elapsed = e);
      if (e >= 10) { t.cancel(); _stopCapture(); }
    });
  }

  Future<void> _stopCapture() async {
    setState(() => _state = _State.saving);
    final path = await FlutterScreenRecording.stopRecordScreen;

    if (path != null && path.isNotEmpty) {
      _savedVideoPath = await _copyToDownloads(path);
    }

    // Generate chart data from the recording
    // (simulated random walk — represents the line movement pattern)
    _chartData = _generateChartFromRecording();

    // Reset line placement
    _activeLineIndex = 0;
    _linePositions = {'a': 0.65, 'b': 0.35, 'c': 0.78, 'd': 0.22};
    _lineLocked = {'a': false, 'b': false, 'c': false, 'd': false};

    setState(() => _state = _State.playback);
  }

  List<double> _generateChartFromRecording() {
    // Generates a plausible-looking chart line for the playback UI.
    // Starts at 0, random walk, same shape every time for a given recording.
    final rand = Random(DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final pts = [0.0];
    for (int i = 1; i < 80; i++) {
      pts.add(pts.last + (rand.nextDouble() - 0.5) * 0.8);
    }
    return pts;
  }

  Future<String?> _copyToDownloads(String src) async {
    try {
      final dl = Directory('/storage/emulated/0/Download');
      if (await dl.exists()) {
        final name = src.split('/').last;
        final dest = '${dl.path}/$name';
        await File(src).copy(dest);
        return dest;
      }
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final name = src.split('/').last;
        final dest = '${ext.path}/$name';
        await File(src).copy(dest);
        return dest;
      }
    } catch (_) {}
    return src;
  }

  // ─── Line placement ────────────────────────────────────────────────────────

  void _onLineDragged(String key, double frac) {
    setState(() => _linePositions[key] = frac);
  }

  void _onLockTapped(String key) {
    final locked = _lineLocked[key] ?? false;
    if (locked) {
      // Unlock: allow re-dragging
      setState(() {
        _lineLocked[key] = false;
        _activeLineIndex = _lineKeys.indexOf(key);
      });
    } else {
      // Lock: advance to next line
      setState(() {
        _lineLocked[key] = true;
        if (_activeLineIndex < _lineKeys.length - 1) {
          _activeLineIndex++;
        } else {
          // All 4 locked — show save dialog
          _state = _State.saveDialog;
        }
      });
    }
  }

  bool get _allLocked => _lineLocked.values.every((v) => v);

  // ─── Save pattern ──────────────────────────────────────────────────────────

  double _fracToPercent(String key) {
    final frac = _linePositions[key] ?? 0.5;
    return double.parse(((0.5 - frac) * 10).toStringAsFixed(2));
  }

  Future<void> _savePattern() async {
    final name = _nameController.text.trim().isEmpty
        ? 'Pattern ${_patterns.length + 1}'
        : _nameController.text.trim();

    final pattern = SavedPattern(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      lines: LineValues(
        a: _fracToPercent('a'),
        b: _fracToPercent('b'),
        c: _fracToPercent('c'),
        d: _fracToPercent('d'),
      ),
      createdAt: DateTime.now(),
    );

    await PatternStore.upsert(pattern);

    // Notify overlay to refresh
    if (_overlayVisible) {
      await OverlayService.sendData({'refresh': true});
    }

    _nameController.clear();
    await _loadPatterns();
    setState(() => _state = _State.patterns);
  }

  Future<void> _loadPatterns() async {
    final list = await PatternStore.loadAll();
    setState(() => _patterns = list);
  }

  Future<void> _deletePattern(String id) async {
    await PatternStore.delete(id);
    await _loadPatterns();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        title: Text(_appBarTitle(), style: const TextStyle(color: Colors.white, fontSize: 17)),
        actions: [
          if (_state == _State.idle || _state == _State.patterns)
            IconButton(
              icon: Icon(_overlayVisible ? Icons.picture_in_picture : Icons.picture_in_picture_outlined,
                  color: _overlayVisible ? Colors.tealAccent : Colors.white54),
              tooltip: _overlayVisible ? 'Hide overlay' : 'Show overlay above Chrome',
              onPressed: _toggleOverlay,
            ),
          if (_state == _State.patterns)
            IconButton(
              icon: const Icon(Icons.add, color: Colors.tealAccent),
              tooltip: 'Record new pattern',
              onPressed: () => setState(() => _state = _State.idle),
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  String _appBarTitle() => switch (_state) {
        _State.playback => 'Place Lines  (${_activeLineIndex + 1}/4)',
        _State.saveDialog => 'Save Pattern',
        _State.patterns => 'Saved Patterns',
        _ => 'Game Recorder',
      };

  Widget _buildBody() => switch (_state) {
        _State.idle => _buildIdle(),
        _State.countdown => _buildCountdown(),
        _State.recording => _buildRecording(),
        _State.saving => _buildSaving(),
        _State.playback => _buildPlayback(),
        _State.saveDialog => _buildSaveDialog(),
        _State.patterns => _buildPatternsList(),
      };

  // ── Idle ──────────────────────────────────────────────────────────────────

  Widget _buildIdle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam, size: 72, color: Colors.tealAccent),
          const SizedBox(height: 24),
          const Text(
            'Tap REC then switch to Chrome.\nRecording stops after 10 seconds.\nThen place your 4 pattern lines.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 15, height: 1.6),
          ),
          const SizedBox(height: 40),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            onPressed: _startRecording,
            icon: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 22),
            label: const Text('REC', style: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2)),
          ),
          const SizedBox(height: 20),
          if (_patterns.isNotEmpty)
            TextButton.icon(
              onPressed: () async { await _loadPatterns(); setState(() => _state = _State.patterns); },
              icon: const Icon(Icons.list, color: Colors.white54),
              label: Text('${_patterns.length} saved pattern(s)', style: const TextStyle(color: Colors.white54)),
            ),
          const SizedBox(height: 8),
          if (!_overlayPermission)
            OutlinedButton.icon(
              onPressed: _requestOverlayPermission,
              icon: const Icon(Icons.picture_in_picture_outlined, color: Colors.tealAccent),
              label: const Text('Allow overlay permission', style: TextStyle(color: Colors.tealAccent)),
            ),
        ]),
      ),
    );
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  Widget _buildCountdown() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$_countdown',
            style: const TextStyle(fontSize: 100, fontWeight: FontWeight.w900, color: Colors.tealAccent)),
        const SizedBox(height: 16),
        const Text('Switch to Chrome now!\nRecording starts in…',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.white54, height: 1.5)),
      ]),
    );
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Widget _buildRecording() {
    final progress = _elapsed / 10;
    final remaining = 10 - _elapsed;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 140, height: 140,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
              value: progress, strokeWidth: 10,
              color: Colors.red,
              backgroundColor: Colors.red.withOpacity(0.15),
            ),
            Text('$remaining',
                style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: Colors.red)),
          ]),
        ),
        const SizedBox(height: 24),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Text('RECORDING…', style: TextStyle(fontSize: 18, color: Colors.white, letterSpacing: 2)),
        ]),
        const SizedBox(height: 12),
        const Text('You can switch apps — recording continues.', style: TextStyle(color: Colors.white54, fontSize: 13)),
      ]),
    );
  }

  // ── Saving ────────────────────────────────────────────────────────────────

  Widget _buildSaving() {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: Colors.tealAccent),
        SizedBox(height: 20),
        Text('Processing recording…', style: TextStyle(color: Colors.white70, fontSize: 16)),
      ]),
    );
  }

  // ── Playback + Line placement ─────────────────────────────────────────────

  Widget _buildPlayback() {
    final instruction = _activeLineIndex < 4
        ? 'Drag ${_lineNames[_activeLineIndex]} → tap 🔓 to lock'
        : 'All lines placed!';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.tealAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(instruction,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.tealAccent, fontSize: 13)),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LineChartWidget(
            chartData: _chartData,
            activeLineIndex: _activeLineIndex,
            linePositions: _linePositions,
            lineLocked: _lineLocked,
            onLineDragged: _onLineDragged,
            onLockTapped: _onLockTapped,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 6,
          alignment: WrapAlignment.center,
          children: _lineKeys.asMap().entries.map((e) {
            final idx = e.key;
            final key = e.value;
            final locked = _lineLocked[key] ?? false;
            final visible = idx <= _activeLineIndex || locked;
            if (!visible) return const SizedBox.shrink();
            return Chip(
              avatar: Icon(locked ? Icons.lock : Icons.lock_open, size: 14,
                  color: locked ? Colors.tealAccent : Colors.white54),
              label: Text('Line ${key.toUpperCase()}',
                  style: TextStyle(color: locked ? Colors.tealAccent : Colors.white54, fontSize: 12)),
              backgroundColor: locked ? Colors.tealAccent.withOpacity(0.1) : const Color(0xFF21262d),
            );
          }).toList(),
        ),
        if (_allLocked && _state == _State.playback)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.tealAccent),
              onPressed: () => setState(() => _state = _State.saveDialog),
              icon: const Icon(Icons.save, color: Colors.black),
              label: const Text('Save Pattern', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ),
      ]),
    );
  }

  // ── Save dialog ───────────────────────────────────────────────────────────

  Widget _buildSaveDialog() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const Icon(Icons.save_alt, size: 56, color: Colors.tealAccent),
        const SizedBox(height: 20),
        const Text('Name this pattern', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. Pattern 1',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true, fillColor: const Color(0xFF21262d),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 16),
        // Preview of line values
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF21262d),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _lineKeys.map((k) {
              final val = _fracToPercent(k);
              final color = switch (k) {
                'a' => const Color(0xFFef4444),
                'b' => const Color(0xFF22c55e),
                'c' => const Color(0xFFb91c1c),
                _ => const Color(0xFF15803d),
              };
              return Column(children: [
                Text(k.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                Text('${val >= 0 ? '+' : ''}${val.toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]);
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _state = _State.playback),
              child: const Text('Back', style: TextStyle(color: Colors.white54)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.tealAccent),
              onPressed: _savePattern,
              child: const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Patterns list ─────────────────────────────────────────────────────────

  Widget _buildPatternsList() {
    if (_patterns.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.show_chart, size: 56, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('No patterns yet.\nTap + to record your first one.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.tealAccent),
            onPressed: () => setState(() => _state = _State.idle),
            icon: const Icon(Icons.add, color: Colors.black),
            label: const Text('Record pattern', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _patterns.length,
      itemBuilder: (context, i) {
        final p = _patterns[i];
        return Card(
          color: const Color(0xFF161b22),
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: () => _deletePattern(p.id),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                _valueChip('A', p.lines.a, const Color(0xFFef4444)),
                _valueChip('B', p.lines.b, const Color(0xFF22c55e)),
                _valueChip('C', p.lines.c, const Color(0xFFb91c1c)),
                _valueChip('D', p.lines.d, const Color(0xFF15803d)),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _valueChip(String label, double val, Color color) {
    final pct = '${val >= 0 ? '+' : ''}${val.toStringAsFixed(2)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$label $pct', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
