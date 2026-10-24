import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Last-known-good snapshot, so the app opens with data and stays readable
/// while the server is unreachable. Writes still require a connection.
class OfflineCache {
  OfflineCache({required this.key});

  final String key;

  Future<void> save(Map<String, dynamic> snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(snapshot));
    } catch (_) {
      // Caching is best effort; never break a successful refresh.
    }
  }

  Future<Map<String, dynamic>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }
}
