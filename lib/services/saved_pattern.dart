// lib/services/saved_pattern.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum TriggerType { touch, passThrough, count }

enum BetDirection { up, down }

class LineSettings {
  final TriggerType triggerType;
  final BetDirection direction;
  final double tolerance; // ± percentage
  final int countTarget;  // only used when triggerType == count
  final String telegramMessageUp;
  final String telegramMessageDown;

  const LineSettings({
    this.triggerType = TriggerType.touch,
    this.direction = BetDirection.up,
    this.tolerance = 0.5,
    this.countTarget = 3,
    this.telegramMessageUp = '📈 BET UP triggered!',
    this.telegramMessageDown = '📉 BET DOWN triggered!',
  });

  Map<String, dynamic> toJson() => {
        'triggerType': triggerType.name,
        'direction': direction.name,
        'tolerance': tolerance,
        'countTarget': countTarget,
        'telegramMessageUp': telegramMessageUp,
        'telegramMessageDown': telegramMessageDown,
      };

  factory LineSettings.fromJson(Map<String, dynamic> j) => LineSettings(
        triggerType: TriggerType.values.firstWhere(
            (e) => e.name == j['triggerType'],
            orElse: () => TriggerType.touch),
        direction: BetDirection.values.firstWhere(
            (e) => e.name == j['direction'],
            orElse: () => BetDirection.up),
        tolerance: (j['tolerance'] as num?)?.toDouble() ?? 0.5,
        countTarget: (j['countTarget'] as int?) ?? 3,
        telegramMessageUp:
            j['telegramMessageUp'] as String? ?? '📈 BET UP triggered!',
        telegramMessageDown:
            j['telegramMessageDown'] as String? ?? '📉 BET DOWN triggered!',
      );

  LineSettings copyWith({
    TriggerType? triggerType,
    BetDirection? direction,
    double? tolerance,
    int? countTarget,
    String? telegramMessageUp,
    String? telegramMessageDown,
  }) =>
      LineSettings(
        triggerType: triggerType ?? this.triggerType,
        direction: direction ?? this.direction,
        tolerance: tolerance ?? this.tolerance,
        countTarget: countTarget ?? this.countTarget,
        telegramMessageUp: telegramMessageUp ?? this.telegramMessageUp,
        telegramMessageDown: telegramMessageDown ?? this.telegramMessageDown,
      );
}

class LineValues {
  final double a;
  final double b;
  final double c;
  final double d;

  const LineValues({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
  });

  Map<String, dynamic> toJson() => {'a': a, 'b': b, 'c': c, 'd': d};

  factory LineValues.fromJson(Map<String, dynamic> j) => LineValues(
        a: (j['a'] as num).toDouble(),
        b: (j['b'] as num).toDouble(),
        c: (j['c'] as num).toDouble(),
        d: (j['d'] as num).toDouble(),
      );

  double operator [](String key) {
    switch (key) {
      case 'a': return a;
      case 'b': return b;
      case 'c': return c;
      default:  return d;
    }
  }
}

class LineSettingsMap {
  final LineSettings a;
  final LineSettings b;
  final LineSettings c;
  final LineSettings d;

  const LineSettingsMap({
    this.a = const LineSettings(),
    this.b = const LineSettings(),
    this.c = const LineSettings(),
    this.d = const LineSettings(),
  });

  LineSettings operator [](String key) {
    switch (key) {
      case 'a': return a;
      case 'b': return b;
      case 'c': return c;
      default:  return d;
    }
  }

  LineSettingsMap copyWithKey(String key, LineSettings s) {
    return LineSettingsMap(
      a: key == 'a' ? s : a,
      b: key == 'b' ? s : b,
      c: key == 'c' ? s : c,
      d: key == 'd' ? s : d,
    );
  }

  Map<String, dynamic> toJson() => {
        'a': a.toJson(),
        'b': b.toJson(),
        'c': c.toJson(),
        'd': d.toJson(),
      };

  factory LineSettingsMap.fromJson(Map<String, dynamic> j) => LineSettingsMap(
        a: LineSettings.fromJson(j['a'] as Map<String, dynamic>? ?? {}),
        b: LineSettings.fromJson(j['b'] as Map<String, dynamic>? ?? {}),
        c: LineSettings.fromJson(j['c'] as Map<String, dynamic>? ?? {}),
        d: LineSettings.fromJson(j['d'] as Map<String, dynamic>? ?? {}),
      );
}

class SavedPattern {
  final String id;
  final String name;
  final LineValues lines;
  final LineSettingsMap settings;
  final DateTime createdAt;

  SavedPattern({
    required this.id,
    required this.name,
    required this.lines,
    LineSettingsMap? settings,
    required this.createdAt,
  }) : settings = settings ?? const LineSettingsMap();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lines': lines.toJson(),
        'settings': settings.toJson(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedPattern.fromJson(Map<String, dynamic> j) => SavedPattern(
        id: j['id'] as String,
        name: j['name'] as String,
        lines: LineValues.fromJson(j['lines'] as Map<String, dynamic>),
        settings: j['settings'] != null
            ? LineSettingsMap.fromJson(j['settings'] as Map<String, dynamic>)
            : const LineSettingsMap(),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class PatternStore {
  static const _key = 'saved_patterns_v3';

  static Future<List<SavedPattern>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => SavedPattern.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> upsert(SavedPattern p) async {
    final all = await loadAll();
    final idx = all.indexWhere((x) => x.id == p.id);
    if (idx >= 0) all[idx] = p;
    else all.add(p);
    await _saveAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((x) => x.id == id);
    await _saveAll(all);
  }

  static Future<void> _saveAll(List<SavedPattern> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(all.map((p) => p.toJson()).toList()));
  }
}

// Global monitoring state
class MonitorState {
  static const _key = 'monitor_config';
  static const _activePatternKey = 'active_pattern_id';
  static const _botTokenKey = 'telegram_bot_token';
  static const _chatIdKey = 'telegram_chat_id';

  static Future<void> saveBotToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_botTokenKey, token);
  }

  static Future<String> getBotToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_botTokenKey) ?? '8960569163:AAGQeHxLZENLAmoG9A2Yz0At73-vTuJn-Uo';
  }

  static Future<void> saveChatId(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatIdKey, chatId);
  }

  static Future<String> getChatId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_chatIdKey) ?? '157828443';
  }

  static Future<void> setActivePattern(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) await prefs.remove(_activePatternKey);
    else await prefs.setString(_activePatternKey, id);
  }

  static Future<String?> getActivePatternId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activePatternKey);
  }
}
