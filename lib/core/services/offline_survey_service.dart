// lib/core/services/offline_survey_service.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class OfflineSurveyService {
  static const String boxName = 'offline_surveys';

  Box get _box => Hive.box(boxName);

  String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toString() +
        Random().nextInt(99999).toString();
  }

  Future<String> saveHouseholdSurvey({
    required Map<String, dynamic> household,
    required List<Map<String, dynamic>> members,
  }) async {
    final localId = household["device_household_ref"]?.toString() ?? _generateId();
    final nowIso = DateTime.now().toIso8601String();
    final existing = _box.get(localId);
    final existingMap = existing is Map ? Map<String, dynamic>.from(existing) : null;

    await _box.put(localId, {
      "id": localId,
      "household": household,
      "members": members,
      "uploaded": false,
      "last_error": existingMap?["last_error"],
      "sync_attempts": existingMap?["sync_attempts"] ?? 0,
      "type": "household_survey",
      "created_at": existingMap?["created_at"] ?? nowIso,
      "updated_at": nowIso,
    });

    debugPrint("💾 Household saved offline: $localId");
    return localId;
  }

  List<Map<String, dynamic>> getPending() {
    return _box.values
        .where((e) => e is Map && e["uploaded"] == false)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  int getPendingCount() {
    return _box.values
        .where((e) => e is Map && e["uploaded"] == false)
        .length;
  }

  Future<void> markUploaded(String id) async {
    final data = _box.get(id);
    if (data == null) return;

    final map = Map<String, dynamic>.from(data);
    map["uploaded"] = true;

    await _box.put(id, map);
  }

    Future<void> markFailed({
    required String id,
    required String error,
  }) async {
    final data = _box.get(id);
    if (data is! Map) return;

    final map = Map<String, dynamic>.from(data);
    map["uploaded"] = false;
    map["last_error"] = error;
    map["sync_attempts"] = ((map["sync_attempts"] as num?)?.toInt() ?? 0) + 1;
    map["updated_at"] = DateTime.now().toIso8601String();

    await _box.put(id, map);
  }


  Future<void> clearUploaded() async {
    final keysToDelete = <dynamic>[];

    for (final key in _box.keys) {
      final value = _box.get(key);
      if (value is Map && value["uploaded"] == true) {
        keysToDelete.add(key);
      }
    }

    await _box.deleteAll(keysToDelete);
  }

  Future<void> clearAll() async {
    await _box.clear();
  }
}