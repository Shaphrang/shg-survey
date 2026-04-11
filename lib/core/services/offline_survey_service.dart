// lib/core/services/offline_survey_service.dart
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../sync/survey_payload_builder.dart';
import '../sync/sync_types.dart';

class OfflineSurveyService {
  static const String boxName = 'offline_surveys';
  static const _uuid = Uuid();

  final SurveyPayloadBuilder _payloadBuilder;

  OfflineSurveyService({SurveyPayloadBuilder? payloadBuilder})
      : _payloadBuilder = payloadBuilder ?? const SurveyPayloadBuilder();

  Box get _box => Hive.box(boxName);

  String newDeviceRef(String prefix) => '${prefix}_${_uuid.v4()}';

  Future<String> saveHouseholdSurvey({
    required Map<String, dynamic> household,
    required List<Map<String, dynamic>> members,
  }) async {
    final now = DateTime.now().toUtc();
    final householdCopy = Map<String, dynamic>.from(household);

    householdCopy['device_household_ref'] ??= newDeviceRef('hh');

    final stableMembers = members.asMap().entries.map((entry) {
      final original = Map<String, dynamic>.from(entry.value);
      original['device_member_ref'] ??= newDeviceRef('mem');
      original['sort_order'] ??= entry.key + 1;
      return original;
    }).toList(growable: false);

    final localSubmissionUuid = _uuid.v4();
    final record = {
      'local_submission_uuid': localSubmissionUuid,
      'device_household_ref': householdCopy['device_household_ref'],
      'household': householdCopy,
      'members': stableMembers,
      'local_created_at': now.toIso8601String(),
      'local_updated_at': now.toIso8601String(),
      'sync_status': SyncStatusCodec.encode(SyncStatus.pending),
      'sync_attempt_count': 0,
      'last_sync_attempt_at': null,
      'synced_at': null,
      'last_error_code': SyncErrorCodeCodec.encode(SyncErrorCode.none),
      'last_error_message': null,
      'next_retry_at': null,
      'payload_hash': _payloadBuilder.payloadHash({
        'household': householdCopy,
        'members': stableMembers,
      }),
      'last_server_status': null,
      'last_server_timestamp': null,
      'schema_version': 2,
      'type': 'household_submission',
    };

    _payloadBuilder.validateAndBuild(submission: record);
    await _box.put(localSubmissionUuid, record);
    SyncLog.info('Saved submission locally: $localSubmissionUuid');
    return localSubmissionUuid;
  }

  List<Map<String, dynamic>> listAll() {
    return _box.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false)
      ..sort((a, b) {
        final aTime = DateTime.tryParse('${a['local_created_at']}');
        final bTime = DateTime.tryParse('${b['local_created_at']}');
        if (aTime == null || bTime == null) return 0;
        return aTime.compareTo(bTime);
      });
  }

  List<Map<String, dynamic>> getReadyToSync({DateTime? now}) {
    final current = (now ?? DateTime.now().toUtc());
    return listAll().where((item) {
      final status = SyncStatusCodec.decode(item['sync_status']);
      if (status == SyncStatus.pending) {
        return true;
      }
      if (status == SyncStatus.failedTransient) {
        final nextRetryAtRaw = item['next_retry_at']?.toString();
        final retryAt =
            nextRetryAtRaw == null ? null : DateTime.tryParse(nextRetryAtRaw);
        return retryAt == null || !retryAt.isAfter(current);
      }
      return false;
    }).toList(growable: false);
  }

  int getPendingCount() {
    return listAll().where((item) {
      final status = SyncStatusCodec.decode(item['sync_status']);
      return status == SyncStatus.pending ||
          status == SyncStatus.syncing ||
          status == SyncStatus.failedTransient;
    }).length;
  }

  int getFailedCount() {
    return listAll().where((item) {
      final status = SyncStatusCodec.decode(item['sync_status']);
      return status == SyncStatus.failedTransient ||
          status == SyncStatus.failedPermanent;
    }).length;
  }

  Future<int> markSyncing(String localSubmissionUuid) async {
    final record = _read(localSubmissionUuid);
    if (record == null) return 0;

    final attempts = (record['sync_attempt_count'] as int? ?? 0) + 1;

    record['sync_status'] = SyncStatusCodec.encode(SyncStatus.syncing);
    record['sync_attempt_count'] = (record['sync_attempt_count'] as int? ?? 0) + 1;
    record['sync_attempt_count'] = attempts;
    record['last_sync_attempt_at'] = DateTime.now().toUtc().toIso8601String();
    record['local_updated_at'] = DateTime.now().toUtc().toIso8601String();

    await _box.put(localSubmissionUuid, record);
    return attempts;
  }

  Future<void> markSynced(
    String localSubmissionUuid, {
    String? serverStatus,
    String? serverTimestamp,
  }) async {
    final record = _read(localSubmissionUuid);
    if (record == null) return;

    record['sync_status'] = SyncStatusCodec.encode(SyncStatus.synced);
    record['synced_at'] = DateTime.now().toUtc().toIso8601String();
    record['last_error_code'] = SyncErrorCodeCodec.encode(SyncErrorCode.none);
    record['last_error_message'] = null;
    record['next_retry_at'] = null;
    record['last_server_status'] = serverStatus;
    record['last_server_timestamp'] = serverTimestamp;
    record['local_updated_at'] = DateTime.now().toUtc().toIso8601String();

    await _box.put(localSubmissionUuid, record);
  }

  Future<void> markFailed({
    required String localSubmissionUuid,
    required SyncErrorCode code,
    required String message,
    required bool permanent,
    String? nextRetryAt,
  }) async {
    final record = _read(localSubmissionUuid);
    if (record == null) return;

    record['sync_status'] = SyncStatusCodec.encode(
      permanent ? SyncStatus.failedPermanent : SyncStatus.failedTransient,
    );
    record['last_error_code'] = SyncErrorCodeCodec.encode(code);
    record['last_error_message'] = message;
    record['next_retry_at'] = permanent ? null : nextRetryAt;
    record['local_updated_at'] = DateTime.now().toUtc().toIso8601String();

    await _box.put(localSubmissionUuid, record);
  }

  Future<void> resetStaleSyncing(
      {Duration maxStale = const Duration(minutes: 5)}) async {
    final now = DateTime.now().toUtc();
    for (final item in listAll()) {
      if (SyncStatusCodec.decode(item['sync_status']) != SyncStatus.syncing) {
        continue;
      }

      final lastAttemptRaw = item['last_sync_attempt_at']?.toString();
      final lastAttempt =
          lastAttemptRaw == null ? null : DateTime.tryParse(lastAttemptRaw);
      if (lastAttempt == null || now.difference(lastAttempt) >= maxStale) {
        final id = item['local_submission_uuid']?.toString();
        if (id == null || id.isEmpty) continue;
        item['sync_status'] = SyncStatusCodec.encode(SyncStatus.pending);
        item['local_updated_at'] = now.toIso8601String();
        await _box.put(id, item);
      }
    }
  }
  Future<void> retryAllFailedTransientNow() async {
    for (final item in listAll()) {
      if (SyncStatusCodec.decode(item['sync_status']) !=
          SyncStatus.failedTransient) {
        continue;
      }
      final id = item['local_submission_uuid']?.toString();
      if (id == null || id.isEmpty) continue;

      item['sync_status'] = SyncStatusCodec.encode(SyncStatus.pending);
      item['next_retry_at'] = null;
      item['local_updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _box.put(id, item);
    }
  }

  Map<String, dynamic>? _read(String localSubmissionUuid) {
    final existing = _box.get(localSubmissionUuid);
    if (existing is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(existing);
  }

  Future<void> clearAll() async => _box.clear();
}