// lib/services/saved_pattern.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum TriggerType { touch, passThrough, count }
enum BetDirection { up, down }

class LineConfig {
  final String label;
  final double value;
  final TriggerType triggerType;
  final BetDirection direction;
  final double tolerance;
  final int countTarget;
  final String telegramMessageUp;
  final String telegramMessageDown;
  final bool enabled;

  const LineConfig({
    required this.label,
    required this.value,
    this.triggerType = TriggerType.touch,
    this.direction = BetDirection.up,
    this.tolerance = 0.5,
    this.countTarget = 3,
    this.telegramMessageUp = '📈 BET UP triggered!',
    this.telegramMessageDown = '📉 BET DOWN triggered!',
    this.enabled = true,
  });

  LineConfig copyWith({
    String? label, double? value, TriggerType? triggerType,
    BetDirection? direction, double? tolerance, int? countTarget,
    String? telegramMessageUp, String? telegramMessageDown, bool? enabled,
  }) => LineConfig(
    label: label ?? this.label, value: value ?? this.value,
    triggerType: triggerType ?? this.triggerType,
    direction: direction ?? this.direction,
    tolerance: tolerance ?? this.tolerance,
    countTarget: countTarget ?? this.countTarget,
    telegramMessageUp: telegramMessageUp ?? this.telegramMessageUp,
    telegramMessageDown: telegramMessageDown ?? this.telegramMessageDown,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'label': label, 'value': value,
    'triggerType': triggerType.name, 'direction': direction.name,
    'tolerance': tolerance, 'countTarget': countTarget,
    'telegramMessageUp': telegramMessageUp,
    'telegramMessageDown': telegramMessageDown,
    'enabled': enabled,
  };

  factory LineConfig.fromJson(Map<String, dynamic> j) => LineConfig(
    label: j['label'] as String,
    value: (j['value'] as num).toDouble(),
    triggerType: TriggerType.values.firstWhere(
        (e) => e.name == j['triggerType'], orElse: () => TriggerType.touch),
    direction: BetDirection.values.firstWhere(
        (e) => e.name == j['direction'], orElse: () => BetDirection.up),
    tolerance: (j['tolerance'] as num?)?.toDouble() ?? 0.5,
    countTarget: (j['countTarget'] as int?) ?? 3,
    telegramMessageUp: j['telegramMessageUp'] as String? ?? '📈 BET UP triggered!',
    telegramMessageDown: j['telegramMessageDown'] as String? ?? '📉 BET DOWN triggered!',
    enabled: j['enabled'] as bool? ?? true,
  );
}

class SavedPattern {
  final String id;
  final String name;
  final List<LineConfig> lines;
  final bool active;

  SavedPattern({
    required this.id, required this.name,
    required this.lines, this.active = true,
  });

  SavedPattern copyWith({String? id, String? name, List<LineConfig>? lines, bool? active}) =>
      SavedPattern(
        id: id ?? this.id, name: name ?? this.name,
        lines: lines ?? this.lines, active: active ?? this.active,
      );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name,
    'lines': lines.map((l) => l.toJson()).toList(),
    'active': active,
  };

  factory SavedPattern.fromJson(Map<String, dynamic> j) => SavedPattern(
    id: j['id'] as String, name: j['name'] as String,
    lines: (j['lines'] as List<dynamic>)
        .map((e) => LineConfig.fromJson(e as Map<String, dynamic>)).toList(),
    active: j['active'] as bool? ?? true,
  );

  static List<LineConfig> defaultLines() => [
    const LineConfig(label: 'A', value: 0, enabled: false, direction: BetDirection.up),
    const LineConfig(label: 'B', value: 0, enabled: false, direction: BetDirection.up),
    const LineConfig(label: 'C', value: 0, enabled: false, direction: BetDirection.down),
    const LineConfig(label: 'D', value: 0, enabled: false, direction: BetDirection.down),
  ];
}

class PatternStore {
  static const _key = 'saved_patterns_v4';

  static Future<List<SavedPattern>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => SavedPattern.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> upsert(SavedPattern p) async {
    final all = await loadAll();
    final idx = all.indexWhere((x) => x.id == p.id);
    if (idx >= 0) all[idx] = p; else all.add(p);
    await _saveAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((x) => x.id == id);
    await _saveAll(all);
  }

  static Future<void> _saveAll(List<SavedPattern> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all.map((p) => p.toJson()).toList()));
  }
}

class AppSettings {
  static const _botTokenKey = 'telegram_bot_token';
  static const _chatIdKey = 'telegram_chat_id';
  static const _overlayXKey = 'overlay_x';
  static const _overlayYKey = 'overlay_y';

  static Future<void> saveBotToken(String t) async =>
      (await SharedPreferences.getInstance()).setString(_botTokenKey, t);
  static Future<String> getBotToken() async =>
      (await SharedPreferences.getInstance()).getString(_botTokenKey) ??
      '8960569163:AAGQeHxLZENLAmoG9A2Yz0At73-vTuJn-Uo';

  static Future<void> saveChatId(String c) async =>
      (await SharedPreferences.getInstance()).setString(_chatIdKey, c);
  static Future<String> getChatId() async =>
      (await SharedPreferences.getInstance()).getString(_chatIdKey) ?? '157828443';

  static Future<void> saveOverlayPosition(double x, double y) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_overlayXKey, x);
    await p.setDouble(_overlayYKey, y);
  }

  static Future<Map<String, double>> getOverlayPosition() async {
    final p = await SharedPreferences.getInstance();
    return {
      'x': p.getDouble(_overlayXKey) ?? 20.0,
      'y': p.getDouble(_overlayYKey) ?? 100.0,
    };
  }
}
