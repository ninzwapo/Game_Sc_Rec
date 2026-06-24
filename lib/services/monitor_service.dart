// lib/services/monitor_service.dart

import 'dart:async';
import 'package:flutter/services.dart';
import 'saved_pattern.dart';
import 'telegram_service.dart';

class TriggerEvent {
  final String patternId;
  final String patternName;
  final String lineLabel;
  final double chartPct;
  final BetDirection direction;
  final DateTime time;

  TriggerEvent({
    required this.patternId, required this.patternName,
    required this.lineLabel, required this.chartPct,
    required this.direction, required this.time,
  });
}

typedef OnValueUpdate = void Function(double? pct);
typedef OnTrigger = void Function(TriggerEvent event);

class MonitorService {
  static const _channel = MethodChannel('com.example.game_recorder/monitor');
  static final MonitorService instance = MonitorService._();
  MonitorService._();

  Timer? _timer;
  bool _running = false;
  List<SavedPattern> _activePatterns = [];

  final Map<String, int> _crossCounts = {};
  final Map<String, bool> _wasAbove = {};
  final Map<String, DateTime> _lastTrigger = {};
  double? _lastValue;

  static const _cooldown = Duration(seconds: 8);

  OnValueUpdate? onValueUpdate;
  OnTrigger? onTrigger;

  bool get isRunning => _running;

  void setPatterns(List<SavedPattern> patterns) {
    _activePatterns = patterns.where((p) => p.active).toList();
    _crossCounts.clear();
    _wasAbove.clear();
    _lastTrigger.clear();
  }

  void start() {
    if (_running) return;
    _running = true;
    _crossCounts.clear();
    _wasAbove.clear();
    _lastTrigger.clear();
    _lastValue = null;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    onValueUpdate?.call(null);
  }

  Future<void> _tick() async {
    if (!_running) return;
    final pct = await _readChartPercent();
    onValueUpdate?.call(pct);
    if (pct == null) { _lastValue = null; return; }
    if (pct.abs() > 30) { _lastValue = pct; return; }

    for (final pattern in _activePatterns) {
      for (final line in pattern.lines) {
        if (!line.enabled) continue;
        final key = '${pattern.id}_${line.label}';
        _checkLine(key, line, pct, pattern);
      }
    }
    _lastValue = pct;
  }

  void _checkLine(String key, LineConfig line, double pct, SavedPattern pattern) {
    final now = DateTime.now();
    final last = _lastTrigger[key];
    if (last != null && now.difference(last) < _cooldown) return;

    bool triggered = false;
    switch (line.triggerType) {
      case TriggerType.touch:
        if ((pct - line.value).abs() <= line.tolerance) triggered = true;
        break;
      case TriggerType.passThrough:
        if (_lastValue != null) {
          if ((_lastValue! > line.value) != (pct > line.value)) triggered = true;
        }
        break;
      case TriggerType.count:
        if (_lastValue != null) {
          final wasAbove = _wasAbove[key] ?? (_lastValue! > line.value);
          final isAbove = pct > line.value;
          if (wasAbove != isAbove) {
            _crossCounts[key] = (_crossCounts[key] ?? 0) + 1;
            _wasAbove[key] = isAbove;
            if ((_crossCounts[key] ?? 0) >= line.countTarget) {
              _crossCounts[key] = 0;
              triggered = true;
            }
          } else { _wasAbove[key] = isAbove; }
        }
        break;
    }

    if (triggered) {
      _lastTrigger[key] = now;
      final event = TriggerEvent(
        patternId: pattern.id, patternName: pattern.name,
        lineLabel: line.label, chartPct: pct,
        direction: line.direction, time: now,
      );
      onTrigger?.call(event);
      _sendTelegram(event, line);
    }
  }

  void _sendTelegram(TriggerEvent event, LineConfig line) {
    final isUp = event.direction == BetDirection.up;
    final msg = '${isUp ? '📈' : '📉'} <b>${event.patternName} — Line ${event.lineLabel} triggered!</b>\n'
        'Chart: ${event.chartPct >= 0 ? '+' : ''}${event.chartPct.toStringAsFixed(1)}%\n'
        'Action: ${isUp ? 'BET UP ⬆️' : 'BET DOWN ⬇️'}\n\n'
        '${isUp ? line.telegramMessageUp : line.telegramMessageDown}';
    TelegramService.sendMessage(msg);
  }

  Future<double?> _readChartPercent() async {
    try {
      final result = await _channel.invokeMethod('readChartPercent');
      if (result == null) return null;
      return (result as num).toDouble();
    } catch (_) { return null; }
  }
}
