import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shg_survey/core/services/offline_survey_service.dart';
import 'package:shg_survey/core/services/sync_service.dart';
import 'package:shg_survey/core/sync/survey_payload_builder.dart';
import 'package:shg_survey/features/survey/remote/household_remote_service.dart';

class _SuccessRemoteService extends HouseholdRemoteService {
  @override
  Future<Map<String, dynamic>> saveHouseholdSurvey({
    required Map<String, dynamic> household,
    required List<Map<String, dynamic>> members,
    required String submissionUuid,
    required String payloadHash,
  }) async {
    return {
      'success': true,
      'status': 'processed',
      'submission_uuid': submissionUuid,
      'household_id': 100,
      'server_timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

class _AlreadyProcessedRemoteService extends HouseholdRemoteService {
  @override
  Future<Map<String, dynamic>> saveHouseholdSurvey({
    required Map<String, dynamic> household,
    required List<Map<String, dynamic>> members,
    required String submissionUuid,
    required String payloadHash,
  }) async {
    return {
      'success': true,
      'status': 'already_processed',
      'submission_uuid': submissionUuid,
      'household_id': 100,
      'server_timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

class _NetworkFailureRemoteService extends HouseholdRemoteService {
  @override
  Future<Map<String, dynamic>> saveHouseholdSurvey({
    required Map<String, dynamic> household,
    required List<Map<String, dynamic>> members,
    required String submissionUuid,
    required String payloadHash,
  }) async {
    throw const SocketException('offline');
  }
}

class _UuidMismatchRemoteService extends HouseholdRemoteService {
  @override
  Future<Map<String, dynamic>> saveHouseholdSurvey({
    required Map<String, dynamic> household,
    required List<Map<String, dynamic>> members,
    required String submissionUuid,
    required String payloadHash,
  }) async {
    throw Exception(
      'submission_uuid $submissionUuid was reused with a different payload_hash',
    );
  }
}

void main() {
  late Directory tempDir;
  late OfflineSurveyService offline;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('shg_sync_test');
    Hive.init(tempDir.path);
    await Hive.openBox(OfflineSurveyService.boxName);
  });

  tearDown(() async {
    await Hive.box(OfflineSurveyService.boxName).clear();
  });

  tearDownAll(() async {
    await Hive.box(OfflineSurveyService.boxName).close();
    await Hive.deleteFromDisk();
  });

  setUp(() {
    offline = OfflineSurveyService();
  });

  test('payload builder rejects duplicate member refs', () {
    final builder = const SurveyPayloadBuilder();

    expect(
      () => builder.validateAndBuild(
        submission: {
         'local_submission_uuid': 'sub-1',
          'household': {'device_household_ref': 'hh-1'},
          'members': [
            {'device_member_ref': 'm-1', 'sort_order': 1},
            {'device_member_ref': 'm-1', 'sort_order': 2},
          ],
        },
      ),
      throwsFormatException,
    );
  });

  test('offline save writes durable pending record', () async {
    final id = await offline.saveHouseholdSurvey(
      household: {'device_household_ref': 'hh-10', 'district_id': 1},
      members: [
        {'device_member_ref': 'm-1', 'sort_order': 1},
      ],
    );

    final box = Hive.box(OfflineSurveyService.boxName);
    final stored = Map<String, dynamic>.from(box.get(id) as Map);

    expect(stored['local_submission_uuid'], isNotNull);
    expect(stored['sync_status'], 'pending');
    expect(stored['sync_attempt_count'], 0);
    expect(stored['device_household_ref'], 'hh-10');
    expect(offline.getPendingCount(), 1);
  });

  test('sync success marks record synced after RPC ack', () async {
    await offline.saveHouseholdSurvey(
      household: {'device_household_ref': 'hh-20', 'district_id': 1},
      members: [
        {'device_member_ref': 'm-1', 'sort_order': 1},
      ],
    );

    final sync = SyncService(
      offlineSurveyService: offline,
      remoteService: _SuccessRemoteService(),
      minimumSyncGap: Duration.zero,
    );

    final result = await sync.syncAll(forceConnectivityCheck: false);
    expect(result['uploaded'], 1);

    final all = offline.listAll();
    expect(all.single['sync_status'], 'synced');
    expect(all.single['synced_at'], isNotNull);
  });

    test('already_processed response is treated as synced replay ack', () async {
    await offline.saveHouseholdSurvey(
      household: {'device_household_ref': 'hh-22', 'district_id': 1},
      members: [
        {'device_member_ref': 'm-1', 'sort_order': 1},
      ],
    );

    final sync = SyncService(
      offlineSurveyService: offline,
      remoteService: _AlreadyProcessedRemoteService(),
      minimumSyncGap: Duration.zero,
    );

    final result = await sync.syncAll(forceConnectivityCheck: false);
    expect(result['uploaded'], 1);
    expect(offline.listAll().single['last_server_status'], 'already_processed');
  });

  test('network sync failure keeps record as failed_transient for retry', () async {
    await offline.saveHouseholdSurvey(
      household: {'device_household_ref': 'hh-30', 'district_id': 1},
      members: [
        {'device_member_ref': 'm-1', 'sort_order': 1},
      ],
    );

    final sync = SyncService(
      offlineSurveyService: offline,
      remoteService: _NetworkFailureRemoteService(),
      minimumSyncGap: Duration.zero,
    );

    final result = await sync.syncAll(forceConnectivityCheck: false);
    expect(result['failed'], 1);

    final record = offline.listAll().single;
    expect(record['sync_status'], 'failed_transient');
    expect(record['next_retry_at'], isNotNull);
  });

  test('uuid mismatch becomes failed_permanent', () async {
    await offline.saveHouseholdSurvey(
      household: {'device_household_ref': 'hh-31', 'district_id': 1},
      members: [
        {'device_member_ref': 'm-1', 'sort_order': 1},
      ],
    );

    final sync = SyncService(
      offlineSurveyService: offline,
      remoteService: _UuidMismatchRemoteService(),
      minimumSyncGap: Duration.zero,
    );

    await sync.syncAll(forceConnectivityCheck: false);
    expect(offline.listAll().single['sync_status'], 'failed_permanent');
  });


  test('invalid payload transitions to failed_permanent', () async {
    final box = Hive.box(OfflineSurveyService.boxName);
    await box.put('bad', {
      'local_submission_uuid': 'bad',
      'device_household_ref': 'hh-bad',
      'household': {'device_household_ref': 'hh-bad'},
      'members': [
        {'sort_order': 1},
      ],
      'sync_status': 'pending',
      'sync_attempt_count': 0,
      'local_created_at': DateTime.now().toUtc().toIso8601String(),
      'local_updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    final sync = SyncService(
      offlineSurveyService: offline,
      remoteService: _SuccessRemoteService(),
      minimumSyncGap: Duration.zero,
    );

    await sync.syncAll(forceConnectivityCheck: false);
    final all = offline.listAll();
    expect(all.single['sync_status'], 'failed_permanent');
  });

  test('stale syncing is reset to pending on next sync run', () async {
    final box = Hive.box(OfflineSurveyService.boxName);
    await box.put('stale', {
      'local_submission_uuid': 'stale',
      'device_household_ref': 'hh-stale',
      'household': {'device_household_ref': 'hh-stale'},
      'members': [
        {'device_member_ref': 'm-1', 'sort_order': 1},
      ],
      'sync_status': 'syncing',
      'sync_attempt_count': 1,
      'last_sync_attempt_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 10))
          .toIso8601String(),
      'local_created_at': DateTime.now().toUtc().toIso8601String(),
      'local_updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    final sync = SyncService(
      offlineSurveyService: offline,
      remoteService: _SuccessRemoteService(),
      minimumSyncGap: Duration.zero,
    );
    await sync.syncAll(forceConnectivityCheck: false);

    expect(offline.listAll().single['sync_status'], 'synced');
  });
}