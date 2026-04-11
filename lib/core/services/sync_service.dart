//lib\core\services\sync_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/survey/remote/household_remote_service.dart';
import '../sync/survey_payload_builder.dart';
import '../sync/sync_types.dart';
import 'offline_survey_service.dart';

class SyncService {
  SyncService({
    OfflineSurveyService? offlineSurveyService,
    HouseholdRemoteService? remoteService,
    SurveyPayloadBuilder? payloadBuilder,
    SyncBackoff? backoff,
    Duration? minimumSyncGap,
  })  : offline = offlineSurveyService ?? OfflineSurveyService(),
        remote = remoteService ?? HouseholdRemoteService(),
        _payloadBuilder = payloadBuilder ?? const SurveyPayloadBuilder(),
        _backoff = backoff ?? SyncBackoff(),
        _minimumSyncGap = minimumSyncGap ?? const Duration(seconds: 3);

  final OfflineSurveyService offline;
  final HouseholdRemoteService remote;
  final SurveyPayloadBuilder _payloadBuilder;
  final SyncBackoff _backoff;
  final Duration _minimumSyncGap;

  static const int _maxConcurrency = 3;
  final Set<String> _inFlight = <String>{};
  bool _running = false;
  DateTime? _lastCompletedSync;

  Future<Map<String, dynamic>> syncAll({bool forceConnectivityCheck = true}) async {
    if (_running) {
      return {
        'total': 0,
        'uploaded': 0,
        'failed': 0,
        'errors': <String>['Sync already running'],
      };
    }

    final now = DateTime.now().toUtc();
    if (_lastCompletedSync != null &&
        now.difference(_lastCompletedSync!) < _minimumSyncGap) {
      return {
        'total': 0,
        'uploaded': 0,
        'failed': 0,
        'errors': <String>['Sync throttled to prevent storm'],
      };
    }

    _running = true;

    try {
      await offline.resetStaleSyncing();

      if (forceConnectivityCheck) {
        final hasInternet = await InternetConnection().hasInternetAccess;
        if (!hasInternet) {
          return {
            'total': 0,
            'uploaded': 0,
            'failed': 0,
            'errors': <String>['No internet access'],
          };
        }
      }

      final ready = offline.getReadyToSync();
      if (ready.isEmpty) {
        return {
          'total': 0,
          'uploaded': 0,
          'failed': 0,
          'errors': <String>[],
        };
      }
      final total = ready.length;
      var uploaded = 0;
      var failed = 0;
      final errors = <String>[];

      for (var i = 0; i < ready.length; i += _maxConcurrency) {
        final chunk = ready.skip(i).take(_maxConcurrency).toList(growable: false);
        final results = await Future.wait(chunk.map(_syncOne));
        for (final r in results) {
          if (r.success) {
            uploaded += 1;
          } else {
            failed += 1;
            if (r.message != null) {
              errors.add(r.message!);
            }
          }
        }
      }

      return {
        'total': total,
        'uploaded': uploaded,
        'failed': failed,
        'errors': errors,
      };
    } finally {
      _lastCompletedSync = DateTime.now().toUtc();
      _running = false;
    }
  }

  Future<void> retryFailedNow() async {
    await offline.retryAllFailedTransientNow();
  }

  Future<_SyncResult> _syncOne(Map<String, dynamic> submission) async {
    final localId = submission['local_submission_uuid']?.toString();
    if (localId == null || localId.isEmpty) {
      return const _SyncResult.failure('Missing local_submission_uuid');
    }

    if (_inFlight.contains(localId)) {
      return const _SyncResult.failure('Skipped duplicate in-flight sync');
    }
    _inFlight.add(localId);
    try {
      await offline.markSyncing(localId);
      SyncLog.info('Sync start: $localId');

      final payload = _payloadBuilder.validateAndBuild(submission: submission);
      final response = await remote.saveHouseholdSurvey(
        household: Map<String, dynamic>.from(payload['p_household'] as Map),
        members: (payload['p_members'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false),
        submissionUuid: payload['p_submission_uuid'].toString(),
        payloadHash: payload['p_payload_hash'].toString(),
      );

      final success = response['success'] == true;
      final status = response['status']?.toString() ?? '';
      final isAck = success && (status == 'processed' || status == 'already_processed');

      if (!isAck) {
        throw Exception('RPC non-ack response: $response');
      }

      await offline.markSynced(
        localId,
        serverStatus: status,
        serverTimestamp: response['server_timestamp']?.toString(),
      );
      SyncLog.info('Sync success: $localId ($status)');
      return const _SyncResult.success();
    } catch (error, stackTrace) {
      SyncLog.error('Sync failed: $localId -> $error');
      debugPrintStack(stackTrace: stackTrace);

      final classified = _classifyFailure(error);
      final attempts = (submission['sync_attempt_count'] as int? ?? 0) + 1;
      final schedule = _backoff.next(attempts);

      await offline.markFailed(
        localSubmissionUuid: localId,
        code: classified.code,
        message: classified.message,
        permanent: classified.permanent,
        nextRetryAt:
            classified.permanent ? null : schedule.at.toIso8601String(),
      );
      if (!classified.permanent) {
        SyncLog.warn(
          'Retry scheduled for $localId in ${schedule.delaySeconds}s at ${schedule.at.toIso8601String()}',
        );
      }

      return _SyncResult.failure('[$localId] ${classified.message}');
    } finally {
      _inFlight.remove(localId);
    }
  }

  _FailureClassification _classifyFailure(Object error) {
    final lower = error.toString().toLowerCase();

    if (lower.contains('submission_uuid') && lower.contains('different payload')) {
      return _FailureClassification(
        code: SyncErrorCode.validation,
        message: 'Unsafe submission replay detected: ${error.toString()}',
        permanent: true,
      );
    }

    if (error is SocketException ||
        error is TimeoutException ||
        lower.contains('socketexception') ||
        lower.contains('timed out') ||
        lower.contains('network')) {
      return _FailureClassification(
        code: SyncErrorCode.network,
        message: 'Network failure: ${error.toString()}',
        permanent: false,
      );
    }

    if (error is AuthException ||
        lower.contains('jwt') ||
        lower.contains('auth') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden')) {
      return _FailureClassification(
        code: SyncErrorCode.auth,
        message: 'Auth/session failure: ${error.toString()}',
        permanent: false,
      );
    }

    if (error is FormatException ||
        lower.contains('invalid') ||
        lower.contains('constraint') ||
        lower.contains('violates') ||
        lower.contains('required')) {
      return _FailureClassification(
        code: SyncErrorCode.validation,
        message: 'Validation failure: ${error.toString()}',
        permanent: true,
      );
    }

    if (error is PostgrestException ||
        lower.contains('server') ||
        lower.contains('database') ||
        lower.contains('postgres')) {
      return _FailureClassification(
        code: SyncErrorCode.server,
        message: 'Server/database failure: ${error.toString()}',
        permanent: false,
      );
    }

    return _FailureClassification(
      code: SyncErrorCode.unknown,
      message: 'Unknown sync failure: ${error.toString()}',
      permanent: false,
    );
  }
}

class _FailureClassification {
  const _FailureClassification({
    required this.code,
    required this.message,
    required this.permanent,
  });

  final SyncErrorCode code;
  final String message;
  final bool permanent;
}

class _SyncResult {
  const _SyncResult._({required this.success, this.message});

  const _SyncResult.success() : this._(success: true);

  const _SyncResult.failure(String message)
      : this._(success: false, message: message);

  final bool success;
  final String? message;
}