// lib/services/monitor_service.dart
//
// Periodically takes a screenshot, crops the % region,
// runs OCR to extract the current chart %, then checks
// against active pattern lines and triggers actions.

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'saved_pattern.dart';
import 'telegram_service.dart';

typedef OnTrigger = void Function(String lineKey, double chartPct, BetDirection dir);
typedef OnValueUpdate = void Function(double chartPct);

class MonitorService {
  static const _channel = MethodChannel('com.example.game_recorder/monitor');

  static MonitorService? _instance;
  static MonitorService get instance => _instance ??= MonitorService._();
  MonitorService._();

  Timer? _timer;
  bool _running = false;
  SavedPattern? _activePattern;

  // Track cross counts per line for "count" trigger type
  final Map<String, int> _crossCounts = {'a': 0, 'b': 0, 'c': 0, 'd': 0};

  // Track last value to detect direction of movement
  double? _lastValue;

  // Track if line was already triggered (to detect pass-through)
  final Map<String, bool> _wasAbove = {};

  // Cooldown per line to avoid spamming
  final Map<String, DateTime> _lastTrigger = {};
  static const _cooldown = Duration(seconds: 10);

  OnTrigger? onTrigger;
  OnValueUpdate? onValueUpdate;

  bool get isRunning => _running;
  SavedPattern? get activePattern => _activePattern;

  void setPattern(SavedPattern pattern) {
    _activePattern = pattern;
    _crossCounts.updateAll((k, v) => 0);
    _wasAbove.clear();
    _lastTrigger.clear();
  }

  void start() {
    if (_running) return;
    _running = true;
    _crossCounts.updateAll((k, v) => 0);
    _wasAbove.clear();
    _lastTrigger.clear();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (!_running || _activePattern == null) return;

    final pct = await _readChartPercent();
    if (pct == null) return;

    onValueUpdate?.call(pct);

    // Only act within -30% to +30% range
    if (pct.abs() > 30) {
      _lastValue = pct;
      return;
    }

    final pattern = _activePattern!;
    for (final key in ['a', 'b', 'c', 'd']) {
      final lineValue = pattern.lines[key];
      final settings = pattern.settings[key];

      _checkLine(key, lineValue, pct, settings);
    }

    _lastValue = pct;
  }

  void _checkLine(
      String key, double lineValue, double currentPct, LineSettings settings) {
    final tolerance = settings.tolerance;
    final now = DateTime.now();

    // Cooldown check
    final last = _lastTrigger[key];
    if (last != null && now.difference(last) < _cooldown) return;

    switch (settings.triggerType) {
      case TriggerType.touch:
        // Trigger when within tolerance of line value
        if ((currentPct - lineValue).abs() <= tolerance) {
          _trigger(key, currentPct, settings);
        }
        break;

      case TriggerType.passThrough:
        // Trigger when chart crosses the line value
        if (_lastValue != null) {
          final wasAbove = _lastValue! > lineValue;
          final isAbove = currentPct > lineValue;
          if (wasAbove != isAbove) {
            _trigger(key, currentPct, settings);
          }
        }
        break;

      case TriggerType.count:
        // Count crossings, trigger when count reaches target
        if (_lastValue != null) {
          final wasAbove = _wasAbove[key] ?? (_lastValue! > lineValue);
          final isAbove = currentPct > lineValue;
          if (wasAbove != isAbove) {
            _crossCounts[key] = (_crossCounts[key] ?? 0) + 1;
            _wasAbove[key] = isAbove;
            if ((_crossCounts[key] ?? 0) >= settings.countTarget) {
              _crossCounts[key] = 0;
              _trigger(key, currentPct, settings);
            }
          } else {
            _wasAbove[key] = isAbove;
          }
        }
        break;
    }
  }

  void _trigger(String key, double currentPct, LineSettings settings) {
    _lastTrigger[key] = DateTime.now();

    final dir = settings.direction;
    onTrigger?.call(key, currentPct, dir);

    // Send Telegram message
    final msg = dir == BetDirection.up
        ? settings.telegramMessageUp
        : settings.telegramMessageDown;

    final fullMsg =
        '${dir == BetDirection.up ? '📈' : '📉'} <b>Line ${key.toUpperCase()} triggered!</b>\n'
        'Chart: ${currentPct >= 0 ? '+' : ''}${currentPct.toStringAsFixed(1)}%\n'
        'Action: ${dir == BetDirection.up ? 'BET UP' : 'BET DOWN'}\n\n'
        '$msg';

    TelegramService.sendMessage(fullMsg);

    // Auto tap via platform channel
    _autoTap(dir);
  }

  Future<void> _autoTap(BetDirection dir) async {
    try {
      await _channel.invokeMethod('autoTap', {
        'direction': dir == BetDirection.up ? 'up' : 'down',
      });
    } catch (_) {
      // Auto tap not available — requires accessibility service
    }
  }

  // OCR the chart percentage from screen
  Future<double?> _readChartPercent() async {
    try {
      final result = await _channel.invokeMethod('readChartPercent');
      if (result == null) return null;
      return (result as num).toDouble();
    } catch (e) {
      // Fallback: try to parse from method channel string result
      return null;
    }
  }
}
