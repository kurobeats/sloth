import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the snapshot is kept: the same keychain/keystore the session token
/// uses. Both sides are pinned explicitly — on iOS the default item rides an
/// encrypted backup to a new device, while `first_unlock_this_device` keeps it
/// on this phone; on Android flutter_secure_storage 11 always wraps values in
/// Keystore AES-GCM.
const secureStorageOptions = FlutterSecureStorage(
  aOptions: AndroidOptions(),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// Last-known-good snapshot, so the app opens with data and stays readable
/// while the server is unreachable. Writes still require a connection.
///
/// The snapshot is the whole workspace — task text, project descriptions and
/// team members with their emails — so it is not plain JSON in
/// SharedPreferences. It lives in flutter_secure_storage under the same
/// per-server key instead: the payload shape is unchanged, only the store
/// moved, and the platform encrypts it at rest.
class OfflineCache {
  OfflineCache({required this.key, FlutterSecureStorage? storage})
    : _storage = storage ?? secureStorageOptions;

  final String key;
  final FlutterSecureStorage _storage;

  Future<void> save(Map<String, dynamic> snapshot) async {
    try {
      await _storage.write(key: key, value: jsonEncode(snapshot));
    } catch (_) {
      // Caching is best effort; never break a successful refresh.
    }
  }

  Future<Map<String, dynamic>?> load() async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}
