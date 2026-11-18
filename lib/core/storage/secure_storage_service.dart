import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vpn_models.dart';

class DiagnosticsLogger {
  final List<String> _entries = [];

  void add(String level, String module, String message) {
    final safeMsg = redactSecrets(message);
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    _entries.add('[$stamp] [$level] [$module] $safeMsg');
    if (_entries.length > 250) {
      _entries.removeAt(0);
    }
  }

  List<String> get lines => List.unmodifiable(_entries);

  void clear() => _entries.clear();

  static String redactSecrets(String input) {
    return input
        .replaceAll(
          RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', caseSensitive: false),
          '[REDACTED-UUID]',
        )
        .replaceAllMapped(
          RegExp(r'(pbk|sid|password|obfs-password|auth|secret)=([^&\s]+)', caseSensitive: false),
          (m) => '${m.group(1)}=[REDACTED]',
        )
        .replaceAllMapped(
          RegExp(r'("(?:uuid|password|public_key|short_id|secret|private_key)"\s*:\s*")([^"]+)(")', caseSensitive: false),
          (m) => '${m.group(1)}[REDACTED]${m.group(3)}',
        )
        .replaceAllMapped(
          RegExp(r'(ss:\/\/)([A-Za-z0-9+/_=-]+)([?#\s]|$)', caseSensitive: false),
          (m) => '${m.group(1)}[REDACTED]${m.group(3)}',
        )
        .replaceAllMapped(
          RegExp(r'([a-z0-9+.-]+:\/\/)([^@\s]+)@', caseSensitive: false),
          (m) => '${m.group(1)}[REDACTED]@',
        );
  }
}

class SecureStorageService {
  static const _profilesKey = 'sutemi_encrypted_profiles_v1';
  static const _groupsKey = 'sutemi_groups_v1';
  static const _settingsKey = 'sutemi_settings_v1';
  static const _selectedIdKey = 'sutemi_selected_profile_id';

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  Future<List<VpnProfile>> loadProfiles() async {
    try {
      final raw = await _secure.read(key: _profilesKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => VpnProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProfiles(List<VpnProfile> profiles) async {
    final encoded = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await _secure.write(key: _profilesKey, value: encoded);
  }

  Future<void> clearProfiles() async {
    await _secure.delete(key: _profilesKey);
  }

  Future<List<ServerGroup>> loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_groupsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => ServerGroup.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveGroups(List<ServerGroup> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupsKey, jsonEncode(groups.map((g) => g.toJson()).toList()));
  }

  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<int?> loadSelectedProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_selectedIdKey);
  }

  Future<void> saveSelectedProfileId(int? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_selectedIdKey);
    } else {
      await prefs.setInt(_selectedIdKey, id);
    }
  }
}
