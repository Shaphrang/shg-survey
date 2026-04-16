import 'dart:async';
import 'dart:io';

import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../features/survey/remote/household_remote_service.dart';
import '../sync/survey_payload_builder.dart';
import '../sync/sync_types.dart';
import 'offline_survey_service.dart';

enum HouseholdSaveStatus {
  savedToServer,
  savedOfflinePending,
}

class HouseholdSaveResult {
  const HouseholdSaveResult({
    required this.status,
    required this.message,
    this.localSubmissionUuid,
    this.serverStatus,
    this.errorCategory,
  });

  final HouseholdSaveStatus status;
  final String message;
  final String? localSubmissionUuid;
  final String? serverStatus;
  final String? errorCategory;
}

class HouseholdSubmissionService {
  HouseholdSubmissionService({
    OfflineSurveyService? offlineService,
    HouseholdRemoteService? remoteService,
    SurveyPayloadBuilder? payloadBuilder,
    InternetConnection? internetConnection,
  })  : _offline = offlineService ?? OfflineSurveyService(),
        _remote = remoteService ?? HouseholdRemoteService(),
        _payloadBuilder = payloadBuilder ?? const SurveyPayloadBuilder(),
        _internetConnection = internetConnection ?? InternetConnection();

  final OfflineSurveyService _offline;
  final HouseholdRemoteService _remote;
  final SurveyPayloadBuilder _payloadBuilder;
  final InternetConnection _internetConnection;
  static const _uuid = Uuid();

  Future<HouseholdSaveResult> saveWithOnlineFirstFallback({
    required Map<String, dynamic> household,
    required List<Map<String, dynamic>> members,
  }) async {
    final generatedSubmissionUuid = _uuid.v4();
    final submission = _payloadBuilder.normalizeSubmission({
      'local_submission_uuid': generatedSubmissionUuid,
      'household': household,
      'members': members,
    });
    final submissionUuid = submission['local_submission_uuid'].toString();
    final normalizedHousehold =
        Map<String, dynamic>.from(submission['household'] as Map);
    final normalizedMembers = (submission['members'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);

    final payload = _payloadBuilder.validateAndBuild(submission: submission);
    final hasInternet = await _internetConnection.hasInternetAccess;

    if (!hasInternet) {
      SyncLog.warn('Save fallback: no internet, storing to Hive pending');
      final localId = await _offline.saveHouseholdSurvey(
        household: normalizedHousehold,
        members: normalizedMembers,
      );
      return HouseholdSaveResult(
        status: HouseholdSaveStatus.savedOfflinePending,
        message:
            'No internet. Saved offline safely and marked pending for sync.',
        localSubmissionUuid: localId,
        errorCategory: 'no_internet',
      );
    }

    try {
      final response = await _remote.saveHouseholdSurvey(
        household: Map<String, dynamic>.from(payload['p_household'] as Map),
        members: (payload['p_members'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false),
        submissionUuid: payload['p_submission_uuid'].toString(),
        payloadHash: payload['p_payload_hash'].toString(),
      );

      final success = response['success'] == true;
      final status = response['status']?.toString();
      final acknowledged = success &&
          (status == 'processed' || status == 'already_processed');
      if (!acknowledged) {
        throw Exception('Backend did not acknowledge submission: $response');
      }

      SyncLog.info('Online save success ($status) submission=$submissionUuid');
      return HouseholdSaveResult(
        status: HouseholdSaveStatus.savedToServer,
        message: 'Saved to server successfully.',
        serverStatus: status,
      );
    } catch (error) {
      final category = _classify(error);
      SyncLog.error(
        'Online save failed ($category). Falling back to Hive. error=$error',
      );
      final localId = await _offline.saveHouseholdSurvey(
        household: normalizedHousehold,
        members: normalizedMembers,
      );
      return HouseholdSaveResult(
        status: HouseholdSaveStatus.savedOfflinePending,
        message:
            'Server save failed ($category). Saved offline safely for later sync.',
        localSubmissionUuid: localId,
        errorCategory: category,
      );
    }
  }

  String _classify(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error.toString().contains('SocketException')) {
      return 'timeout/network_failure';
    }
    if (error is AuthException ||
        error.toString().toLowerCase().contains('auth')) {
      return 'auth/session_failure';
    }
    if (error is PostgrestException) {
      return 'backend_rejection';
    }
    if (error is FormatException) {
      return 'validation_error';
    }
    return 'unexpected_exception';
  }
}
