// screens/recorder_screen.dart
//
// Single screen with a big REC button.
// Tap it → Android asks permission to capture screen → 3-second countdown
// → records for exactly 10 seconds → stops and saves .mp4 to Downloads.
// The app can be minimised immediately after tapping REC — recording
// continues in the background and captures whatever is on screen
// (including Chrome or any other app).

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

enum _State { idle, countdown, recording, saving, done, error }

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  static const int _recordSeconds = 10;
  static const int _countdownSeconds = 3;

  _State _state = _State.idle;
  int _countdown = _countdownSeconds;
  int _elapsed = 0;
  String? _savedPath;
  String? _errorMsg;

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    // 1. Request permissions
    final storageOk = await _requestPermissions();
    if (!storageOk) {
      setState(() {
        _state = _State.error;
        _errorMsg = 'Storage permission denied. Please allow it in Settings.';
      });
      return;
    }

    // 2. Countdown
    setState(() {
      _state = _State.countdown;
      _countdown = _countdownSeconds;
    });

    await _runCountdown();
    if (!mounted) return;

    // 3. Start recording (this triggers the Android system permission dialog)
    final fileName =
        'rec_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';

    bool started = false;
    try {
      started = await FlutterScreenRecording.startRecordScreen(fileName);
    } catch (e) {
      setState(() {
        _state = _State.error;
        _errorMsg = 'Could not start recording: $e';
      });
      return;
    }

    if (!started) {
      setState(() {
        _state = _State.error;
        _errorMsg =
            'Recording permission denied or screen capture unavailable.';
      });
      return;
    }

    // 4. Record for 10 seconds, showing elapsed time
    setState(() {
      _state = _State.recording;
      _elapsed = 0;
    });

    await _runRecording();
    if (!mounted) return;

    // 5. Stop and retrieve the file
    setState(() => _state = _State.saving);

    String? path;
    try {
      path = await FlutterScreenRecording.stopRecordScreen;
    } catch (e) {
      setState(() {
        _state = _State.error;
        _errorMsg = 'Failed to stop recording: $e';
      });
      return;
    }

    // 6. Copy to Downloads if possible
    if (path != null && path.isNotEmpty) {
      final saved = await _copyToDownloads(path, '$fileName.mp4');
      setState(() {
        _state = _State.done;
        _savedPath = saved ?? path;
      });
    } else {
      setState(() {
        _state = _State.error;
        _errorMsg = 'Recording stopped but no file path returned.';
      });
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Android 13+ uses granular media permissions
      final photos = await Permission.photos.request();
      final videos = await Permission.videos.request();
      final storage = await Permission.storage.request();
      return photos.isGranted || videos.isGranted || storage.isGranted;
    }
    return true;
  }

  Future<void> _runCountdown() async {
    final completer = Completer<void>();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        completer.complete();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        completer.complete();
      }
    });
    return completer.future;
  }

  Future<void> _runRecording() async {
    final completer = Completer<void>();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        completer.complete();
        return;
      }
      setState(() => _elapsed++);
      if (_elapsed >= _recordSeconds) {
        t.cancel();
        completer.complete();
      }
    });
    return completer.future;
  }

  Future<String?> _copyToDownloads(String sourcePath, String fileName) async {
    try {
      // Try the standard Android Downloads path first
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) {
        final dest = '${downloads.path}/$fileName';
        await File(sourcePath).copy(dest);
        return dest;
      }
      // Fallback: app's external files directory
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final dest = '${extDir.path}/$fileName';
        await File(sourcePath).copy(dest);
        return dest;
      }
    } catch (_) {}
    return sourcePath; // return original path if copy failed
  }

  void _reset() {
    setState(() {
      _state = _State.idle;
      _savedPath = null;
      _errorMsg = null;
      _elapsed = 0;
      _countdown = _countdownSeconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('10-Second Recorder')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: switch (_state) {
            _State.idle => _buildIdle(),
            _State.countdown => _buildCountdown(),
            _State.recording => _buildRecording(),
            _State.saving => _buildSaving(),
            _State.done => _buildDone(),
            _State.error => _buildError(),
          },
        ),
      ),
    );
  }

  Widget _buildIdle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.videocam, size: 72, color: Colors.tealAccent),
        const SizedBox(height: 24),
        const Text(
          'Tap REC, then switch to\nthe app you want to capture.\nRecording stops automatically after 10 seconds.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 40),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
          label: const Text('REC', style: TextStyle(fontSize: 20)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdown() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$_countdown',
          style: const TextStyle(fontSize: 96, fontWeight: FontWeight.bold, color: Colors.tealAccent),
        ),
        const SizedBox(height: 16),
        const Text(
          'Switch to your app now!\nRecording starts in…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ],
    );
  }

  Widget _buildRecording() {
    final remaining = _recordSeconds - _elapsed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CircularProgressIndicator(
                value: _elapsed / _recordSeconds,
                strokeWidth: 8,
                color: Colors.red,
                backgroundColor: Colors.red.withOpacity(0.2),
              ),
            ),
            Text(
              '$remaining',
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
            SizedBox(width: 6),
            Text('RECORDING…', style: TextStyle(fontSize: 18, letterSpacing: 2)),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'You can switch apps — recording\ncontinues in the background.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      ],
    );
  }

  Widget _buildSaving() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 24),
        Text('Saving recording…', style: TextStyle(fontSize: 18)),
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, size: 72, color: Colors.tealAccent),
        const SizedBox(height: 24),
        const Text(
          'Saved!',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          _savedPath ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 8),
        const Text(
          'Find the file in your Downloads folder.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 40),
        FilledButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.refresh),
          label: const Text('Record again'),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 72, color: Colors.red),
        const SizedBox(height: 24),
        Text(
          _errorMsg ?? 'Unknown error',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 40),
        FilledButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
