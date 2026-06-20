// lib/services/saved_pattern.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LineValues {
  final double a; // near-down %
  final double b; // near-up %
  final double c; // far-down %
  final double d; // far-up %

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
}

class SavedPattern {
  final String id;
  final String name;
  final LineValues lines;
  final DateTime createdAt;

  SavedPattern({
    required this.id,
    required this.name,
    required this.lines,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lines': lines.toJson(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedPattern.fromJson(Map<String, dynamic> j) => SavedPattern(
        id: j['id'] as String,
        name: j['name'] as String,
        lines: LineValues.fromJson(j['lines'] as Map<String, dynamic>),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class PatternStore {
  static const _key = 'saved_patterns_v2';

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
