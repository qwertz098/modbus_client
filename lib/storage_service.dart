import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class StorageService {
  static const _keyAutoSaveEndpoints = 'autosave_endpoints';
  static const _keyAutoSaveByteOrder = 'autosave_byte_order';
  static const _keyProfiles = 'profiles';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ─── Auto-Save (last state) ─────────────────────────────────────

  Future<void> autoSave(List<Endpoint> endpoints, ByteOrder byteOrder) async {
    final jsonList = endpoints.map((e) => e.toJson()).toList();
    await _prefs.setString(_keyAutoSaveEndpoints, jsonEncode(jsonList));
    await _prefs.setString(_keyAutoSaveByteOrder, byteOrder.name);
  }

  List<Endpoint>? loadAutoSaveEndpoints() {
    final raw = _prefs.getString(_keyAutoSaveEndpoints);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Endpoint.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  ByteOrder loadAutoSaveByteOrder() {
    final raw = _prefs.getString(_keyAutoSaveByteOrder);
    if (raw == null) return ByteOrder.bigEndian;
    return ByteOrder.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ByteOrder.bigEndian,
    );
  }

  // ─── Named Profiles ────────────────────────────────────────────

  Map<String, Profile> loadProfiles() {
    final raw = _prefs.getString(_keyProfiles);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((key, value) =>
        MapEntry(key, Profile.fromJson(value as Map<String, dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> saveProfile(Profile profile) async {
    final profiles = loadProfiles();
    profiles[profile.name] = profile;
    await _saveProfiles(profiles);
  }

  Future<void> deleteProfile(String name) async {
    final profiles = loadProfiles();
    profiles.remove(name);
    await _saveProfiles(profiles);
  }

  Future<void> _saveProfiles(Map<String, Profile> profiles) async {
    final map = profiles.map((key, value) => MapEntry(key, value.toJson()));
    await _prefs.setString(_keyProfiles, jsonEncode(map));
  }

  List<String> getProfileNames() {
    return loadProfiles().keys.toList()..sort();
  }
}
