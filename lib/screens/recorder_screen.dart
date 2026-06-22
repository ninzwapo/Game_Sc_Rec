// lib/screens/recorder_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../services/saved_pattern.dart';
import '../services/overlay_service.dart';
import '../services/monitor_service.dart';
import '../services/telegram_service.dart';
import '../widgets/line_chart_widget.dart';
import 'line_settings_screen.dart';

enum _State {
  idle,
  countdown,
  recording,
  saving,
  playback,
  saveDialog,
  patterns,
  monitoring,
}

const _lineKeys = ['a', 'b', 'c', 'd'];
const _lineNames = [
  'A — Near-down',
  'B — Near-up',
  'C — Far-down',
  'D — Far-up'
];

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  _State _state = _State.idle;
  int _countdown = 3;
  int _elapsed = 0;
  String? _videoPath;
  Timer? _timer;
  bool _overlayVisible = false;
  bool _overlayPermission = false;

  // Video playback
  VideoPlayerController? _videoController;
  bool _videoReady = false;

  // Line placement
  int _activeLineIndex = 0;
  Map<String, double> _linePositions = {
    'a': 0.65,
    'b': 0.35,
    'c': 0.78,
    'd': 0.22
  };
  Map<String, bool> _lineLocked = {
    'a': false,
    'b': false,
    'c': false,
    'd': false
  };
  LineSettingsMap _lineSettings = const LineSettingsMap();

  // Save dialog
  final _nameController = TextEditingController();

  // Patterns list
  List<SavedPattern> _patterns = [];

  // Monitoring
  double? _liveChartPct;
  String? _lastTriggerInfo;
  SavedPattern? _monitoringPattern;

  @override
  void initState() {
    super.initState();
    _checkOverlayPermission();
    _loadPatterns();
    MonitorService.instance.onValueUpdate = (pct) {
      if (mounted) setState(() => _liveChartPct = pct);
    };
    MonitorService.instance.onTrigger = (key, pct, dir) {
      if (mounted) {
        setState(() {
          _lastTriggerInfo =
              'Line ${key.toUpperCase()} @ ${pct.toStringAsFixed(1)}% → ${dir == BetDirection.up ? 'BET UP 📈' : 'BET DOWN 📉'}';
        });
      }
    };
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nameController.dispose();
    _videoController?.dispose();
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
    await Permission.photos.request();
    await Permission.videos.request();
    await Permission.storage.request();

    setState(() {
      _state = _State.countdown;
      _countdown = 3;
    });

    int c = 3;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      c--;
      setState(() => _countdown = c);
      if (c <= 0) {
        t.cancel();
        _beginCapture();
      }
    });
  }

  Future<void> _beginCapture() async {
    final fileName =
        'rec_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
    final started =
        await FlutterScreenRecording.startRecordScreen(fileName);
    if (!started) {
      setState(() => _state = _State.idle);
      return;
    }

    setState(() {
      _state = _State.recording;
      _elapsed = 0;
    });

    int e = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      e++;
      setState(() => _elapsed = e);
      if (e >= 10) {
        t.cancel();
        _stopCapture();
      }
    });
  }

  Future<void> _stopCapture() async {
    setState(() => _state = _State.saving);
    final path = await FlutterScreenRecording.stopRecordScreen;

    if (path != null && path.isNotEmpty) {
      _videoPath = await _copyToStorage(path);
    }

    // Reset line placement
    _activeLineIndex = 0;
    _linePositions = {'a': 0.65, 'b': 0.35, 'c': 0.78, 'd': 0.22};
    _lineLocked = {'a': false, 'b': false, 'c': false, 'd': false};
    _lineSettings = const LineSettingsMap();

    // Initialize video player
    if (_videoPath != null) {
      await _initVideo(_videoPath!);
    }

    setState(() => _state = _State.playback);
  }

  Future<void> _initVideo(String path) async {
    _videoController?.dispose();
    _videoController = VideoPlayerController.file(File(path));
    await _videoController!.initialize();
    await _videoController!.setLooping(true);
    await _videoController!.play();
    setState(() => _videoReady = true);
  }

  Future<String?> _copyToStorage(String src) async {
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
      setState(() {
        _lineLocked[key] = false;
        _activeLineIndex = _lineKeys.indexOf(key);
      });
    } else {
      setState(() {
        _lineLocked[key] = true;
        if (_activeLineIndex < _lineKeys.length - 1) {
          _activeLineIndex++;
        } else {
          _state = _State.saveDialog;
        }
      });
    }
  }

  bool get _allLocked => _lineLocked.values.every((v) => v);

  void _openLineSettings(String key) async {
    final result = await Navigator.push<LineSettings>(
      context,
      MaterialPageRoute(
        builder: (_) => LineSettingsScreen(
          lineKey: key,
          settings: _lineSettings[key],
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _lineSettings = _lineSettings.copyWithKey(key, result);
      });
    }
  }

  // ─── Save ──────────────────────────────────────────────────────────────────

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
      settings: _lineSettings,
      createdAt: DateTime.now(),
    );

    await PatternStore.upsert(pattern);

    if (_overlayVisible) {
      await OverlayService.sendData({'refresh': true});
    }

    _nameController.clear();
    _videoController?.dispose();
    _videoController = null;
    _videoReady = false;
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

  // ─── Monitoring ────────────────────────────────────────────────────────────

  void _startMonitoring(SavedPattern pattern) {
    MonitorService.instance.setPattern(pattern);
    MonitorService.instance.start();
    setState(() {
      _monitoringPattern = pattern;
      _state = _State.monitoring;
      _liveChartPct = null;
      _lastTriggerInfo = null;
    });
  }

  void _stopMonitoring() {
    MonitorService.instance.stop();
    setState(() {
      _state = _State.patterns;
      _monitoringPattern = null;
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        title: Text(_appBarTitle(),
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        actions: [
          if (_state == _State.idle || _state == _State.patterns)
            IconButton(
              icon: Icon(
                _overlayVisible
                    ? Icons.picture_in_picture
                    : Icons.picture_in_picture_outlined,
                color:
                    _overlayVisible ? Colors.tealAccent : Colors.white54,
              ),
              onPressed: _toggleOverlay,
            ),
          if (_state == _State.patterns)
            IconButton(
              icon: const Icon(Icons.add, color: Colors.tealAccent),
              onPressed: () => setState(() => _state = _State.idle),
            ),
          if (_state == _State.patterns)
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white54),
              onPressed: _showTelegramSettings,
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  String _appBarTitle() => switch (_state) {
        _State.playback =>
          'Place Lines  (${_activeLineIndex + 1}/4)',
        _State.saveDialog => 'Save Pattern',
        _State.patterns => 'Saved Patterns',
        _State.monitoring =>
          '🔴 Monitoring: ${_monitoringPattern?.name ?? ''}',
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
        _State.monitoring => _buildMonitoring(),
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
            'Tap REC then switch to the game.\nRecording stops after 10 seconds.\nThen place your 4 pattern lines.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Colors.white54, fontSize: 15, height: 1.6),
          ),
          const SizedBox(height: 40),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              padding:
                  const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            onPressed: _startRecording,
            icon: const Icon(Icons.fiber_manual_record,
                color: Colors.red, size: 22),
            label: const Text('REC',
                style: TextStyle(
                    color: Colors.black,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2)),
          ),
          const SizedBox(height: 20),
          if (_patterns.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                await _loadPatterns();
                setState(() => _state = _State.patterns);
              },
              icon: const Icon(Icons.list, color: Colors.white54),
              label: Text('${_patterns.length} saved pattern(s)',
                  style: const TextStyle(color: Colors.white54)),
            ),
          const SizedBox(height: 8),
          if (!_overlayPermission)
            OutlinedButton.icon(
              onPressed: _requestOverlayPermission,
              icon: const Icon(Icons.picture_in_picture_outlined,
                  color: Colors.tealAccent),
              label: const Text('Allow overlay permission',
                  style: TextStyle(color: Colors.tealAccent)),
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
            style: const TextStyle(
                fontSize: 100,
                fontWeight: FontWeight.w900,
                color: Colors.tealAccent)),
        const SizedBox(height: 16),
        const Text('Switch to the game now!\nRecording starts in…',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 18, color: Colors.white54, height: 1.5)),
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
          width: 140,
          height: 140,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 10,
              color: Colors.red,
              backgroundColor: Colors.red.withOpacity(0.15),
            ),
            Text('$remaining',
                style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: Colors.red)),
          ]),
        ),
        const SizedBox(height: 24),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Text('RECORDING…',
              style: TextStyle(
                  fontSize: 18, color: Colors.white, letterSpacing: 2)),
        ]),
        const SizedBox(height: 12),
        const Text('You can switch apps — recording continues.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
      ]),
    );
  }

  // ── Saving ────────────────────────────────────────────────────────────────

  Widget _buildSaving() {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: Colors.tealAccent),
        SizedBox(height: 20),
        Text('Processing recording…',
            style: TextStyle(color: Colors.white70, fontSize: 16)),
      ]),
    );
  }

  // ── Playback + Line placement ─────────────────────────────────────────────

  Widget _buildPlayback() {
    final instruction = _activeLineIndex < 4
        ? 'Drag ${_lineNames[_activeLineIndex]} → tap 🔒 to lock'
        : 'All lines placed!';

    return Column(children: [
      // Video player
      if (_videoReady && _videoController != null)
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        )
      else
        Container(
          height: 200,
          color: Colors.black,
          child: const Center(
            child: Text('Loading video…',
                style: TextStyle(color: Colors.white54)),
          ),
        ),

      // Instruction bar
      Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        color: Colors.tealAccent.withOpacity(0.08),
        child: Text(instruction,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: Colors.tealAccent, fontSize: 13)),
      ),

      // Line placement chart (shows % values for placing lines)
      Expanded(
        child: Stack(children: [
          LineChartWidget(
            chartData: const [],
            activeLineIndex: _activeLineIndex,
            linePositions: _linePositions,
            lineLocked: _lineLocked,
            onLineDragged: _onLineDragged,
            onLockTapped: _onLockTapped,
          ),
          // Settings buttons per line
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _lineKeys.map((key) {
                final locked = _lineLocked[key] ?? false;
                if (!locked) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () => _openLineSettings(key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF21262d),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.tealAccent.withOpacity(0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.tune,
                          size: 12, color: Colors.tealAccent),
                      const SizedBox(width: 4),
                      Text('${key.toUpperCase()} settings',
                          style: const TextStyle(
                              color: Colors.tealAccent, fontSize: 10)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ]),
      ),

      // Lock chips
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: _lineKeys.asMap().entries.map((e) {
            final idx = e.key;
            final key = e.value;
            final locked = _lineLocked[key] ?? false;
            final visible =
                idx <= _activeLineIndex || locked;
            if (!visible) return const SizedBox.shrink();
            return Chip(
              avatar: Icon(
                  locked ? Icons.lock : Icons.lock_open,
                  size: 14,
                  color: locked
                      ? Colors.tealAccent
                      : Colors.white54),
              label: Text('Line ${key.toUpperCase()}',
                  style: TextStyle(
                      color: locked
                          ? Colors.tealAccent
                          : Colors.white54,
                      fontSize: 12)),
              backgroundColor: locked
                  ? Colors.tealAccent.withOpacity(0.1)
                  : const Color(0xFF21262d),
            );
          }).toList(),
        ),
      ),

      if (_allLocked && _state == _State.playback)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent,
                minimumSize: const Size.fromHeight(48)),
            onPressed: () => setState(() => _state = _State.saveDialog),
            icon: const Icon(Icons.save, color: Colors.black),
            label: const Text('Save Pattern',
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold)),
          ),
        ),
    ]);
  }

  // ── Save dialog ───────────────────────────────────────────────────────────

  Widget _buildSaveDialog() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const Icon(Icons.save_alt, size: 56, color: Colors.tealAccent),
        const SizedBox(height: 20),
        const Text('Name this pattern',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. Pattern 1',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF21262d),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 16),
        // Line values preview with settings summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF21262d),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _lineKeys.map((k) {
                final val = _fracToPercent(k);
                final s = _lineSettings[k];
                final color = switch (k) {
                  'a' => const Color(0xFFef4444),
                  'b' => const Color(0xFF22c55e),
                  'c' => const Color(0xFFb91c1c),
                  _ => const Color(0xFF15803d),
                };
                return Column(children: [
                  Text(k.toUpperCase(),
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  Text(
                      '${val >= 0 ? '+' : ''}${val.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                  Text(
                      s.direction == BetDirection.up ? '📈' : '📉',
                      style: const TextStyle(fontSize: 12)),
                  Text(
                      s.triggerType.name,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 9)),
                ]);
              }).toList(),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                // Allow editing line settings before saving
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF21262d),
                    title: const Text('Edit Line Settings',
                        style: TextStyle(color: Colors.white)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _lineKeys.map((key) {
                        return ListTile(
                          title: Text('Line ${key.toUpperCase()}',
                              style:
                                  const TextStyle(color: Colors.white)),
                          trailing: const Icon(Icons.chevron_right,
                              color: Colors.white54),
                          onTap: () {
                            Navigator.pop(context);
                            _openLineSettings(key);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.tune,
                  size: 14, color: Colors.tealAccent),
              label: const Text('Edit line settings',
                  style:
                      TextStyle(color: Colors.tealAccent, fontSize: 12)),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _state = _State.playback),
              child: const Text('Back',
                  style: TextStyle(color: Colors.white54)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.tealAccent),
              onPressed: _savePattern,
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold)),
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
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent),
            onPressed: () => setState(() => _state = _State.idle),
            icon: const Icon(Icons.add, color: Colors.black),
            label: const Text('Record pattern',
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _patterns.length,
      itemBuilder: (context, i) {
        final p = _patterns[i];
        final isMonitoring = MonitorService.instance.isRunning &&
            MonitorService.instance.activePattern?.id == p.id;

        return Card(
          color: const Color(0xFF161b22),
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isMonitoring
                  ? Colors.tealAccent
                  : Colors.white10,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Text(p.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      Row(children: [
                        if (isMonitoring)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.tealAccent
                                  .withOpacity(0.15),
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: const Text('LIVE',
                                style: TextStyle(
                                    color: Colors.tealAccent,
                                    fontSize: 11,
                                    fontWeight:
                                        FontWeight.bold)),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.white24, size: 20),
                          onPressed: () =>
                              _confirmDelete(p.id),
                        ),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Line values
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceAround,
                    children: _lineKeys.map((k) {
                      final val = p.lines[k];
                      final s = p.settings[k];
                      final color = switch (k) {
                        'a' => const Color(0xFFef4444),
                        'b' => const Color(0xFF22c55e),
                        'c' => const Color(0xFFb91c1c),
                        _ => const Color(0xFF15803d),
                      };
                      return Column(children: [
                        Text(k.toUpperCase(),
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                        Text(
                            '${val >= 0 ? '+' : ''}${val.toStringAsFixed(1)}%',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11)),
                        Text(
                            s.direction == BetDirection.up
                                ? '📈'
                                : '📉',
                            style:
                                const TextStyle(fontSize: 11)),
                        Text('±${s.tolerance}%',
                            style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 9)),
                      ]);
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  // Monitor button
                  SizedBox(
                    width: double.infinity,
                    child: isMonitoring
                        ? OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: Colors.redAccent),
                            ),
                            onPressed: _stopMonitoring,
                            icon: const Icon(Icons.stop,
                                color: Colors.redAccent,
                                size: 16),
                            label: const Text('Stop Monitoring',
                                style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 13)),
                          )
                        : FilledButton.icon(
                            style: FilledButton.styleFrom(
                                backgroundColor:
                                    Colors.tealAccent),
                            onPressed: () =>
                                _startMonitoring(p),
                            icon: const Icon(
                                Icons.radar,
                                color: Colors.black,
                                size: 16),
                            label: const Text(
                                'Start Monitoring',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.bold)),
                          ),
                  ),
                ]),
          ),
        );
      },
    );
  }

  // ── Monitoring screen ─────────────────────────────────────────────────────

  Widget _buildMonitoring() {
    final pct = _liveChartPct;
    final inRange = pct != null && pct.abs() <= 30;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // Live value display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF161b22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: inRange ? Colors.tealAccent : Colors.orange,
            ),
          ),
          child: Column(children: [
            Text(
              pct == null
                  ? '—'
                  : '${pct >= 0 ? '▲' : '▼'} ${pct.abs().toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: pct == null
                    ? Colors.white24
                    : (pct >= 0 ? Colors.green : Colors.red),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pct == null
                  ? 'Reading screen…'
                  : (inRange
                      ? '✅ Within range (-30% to +30%)'
                      : '⚠️ Outside range — monitoring paused'),
              style: TextStyle(
                color: inRange ? Colors.tealAccent : Colors.orange,
                fontSize: 13,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Pattern line values
        if (_monitoringPattern != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF161b22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pattern: ${_monitoringPattern!.name}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: _lineKeys.map((k) {
                    final val = _monitoringPattern!.lines[k];
                    final s = _monitoringPattern!.settings[k];
                    final color = switch (k) {
                      'a' => const Color(0xFFef4444),
                      'b' => const Color(0xFF22c55e),
                      'c' => const Color(0xFFb91c1c),
                      _ => const Color(0xFF15803d),
                    };
                    // Highlight if near this line
                    final near = pct != null &&
                        (pct - val).abs() <= s.tolerance;
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: near
                            ? color.withOpacity(0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: near
                            ? Border.all(color: color)
                            : null,
                      ),
                      child: Column(children: [
                        Text(k.toUpperCase(),
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        Text(
                            '${val >= 0 ? '+' : ''}${val.toStringAsFixed(1)}%',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12)),
                        Text(
                            s.direction == BetDirection.up
                                ? '📈 UP'
                                : '📉 DOWN',
                            style:
                                const TextStyle(fontSize: 10)),
                        if (near)
                          const Text('HIT!',
                              style: TextStyle(
                                  color: Colors.yellow,
                                  fontSize: 10,
                                  fontWeight:
                                      FontWeight.bold)),
                      ]),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Last trigger info
        if (_lastTriggerInfo != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.tealAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: Colors.tealAccent.withOpacity(0.3)),
            ),
            child: Text(
              '🎯 Last trigger: $_lastTriggerInfo',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.tealAccent, fontSize: 13),
            ),
          ),

        const Spacer(),

        // Stop button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _stopMonitoring,
            icon:
                const Icon(Icons.stop, color: Colors.redAccent),
            label: const Text('Stop Monitoring',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }

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

  void _showTelegramSettings() {
    final tokenCtrl = TextEditingController();
    final chatCtrl = TextEditingController();

    MonitorState.getBotToken().then((t) => tokenCtrl.text = t);
    MonitorState.getChatId().then((c) => chatCtrl.text = c);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF21262d),
        title: const Text('Telegram Settings',
            style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: tokenCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Bot Token',
              labelStyle: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: chatCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Chat ID',
              labelStyle: TextStyle(color: Colors.white54),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent),
            onPressed: () async {
              await MonitorState.saveBotToken(tokenCtrl.text.trim());
              await MonitorState.saveChatId(chatCtrl.text.trim());
              Navigator.pop(context);
              TelegramService.testConnection();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Telegram settings saved! Test message sent.')),
              );
            },
            child: const Text('Save',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}
