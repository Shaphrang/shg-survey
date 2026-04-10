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
  }) async {
    return {'success': true, 'household_id': 100};
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
    );

    final result = await sync.syncAll(forceConnectivityCheck: false);
    expect(result['uploaded'], 1);

    final all = offline.listAll();
    expect(all.single['sync_status'], 'synced');
    expect(all.single['synced_at'], isNotNull);
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
    );

    await sync.syncAll(forceConnectivityCheck: false);
    final all = offline.listAll();
    expect(all.single['sync_status'], 'failed_permanent');
  });
}