import 'dart:math';

import 'package:flutter/foundation.dart';

enum SyncStatus {
  draft,
  pending,
  syncing,
  synced,
  failedTransient,
  failedPermanent,
}

enum SyncErrorCode {
  none,
  network,
  auth,
  validation,
  server,
  unknown,
}

@immutable
class RetrySchedule {
  const RetrySchedule({
    required this.at,
    required this.delaySeconds,
  });

  final DateTime at;
  final int delaySeconds;
}

class SyncBackoff {
  SyncBackoff({
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 30),
    Random? random,
  }) : _random = random ?? Random();

  final Duration baseDelay;
  final Duration maxDelay;
  final Random _random;

  RetrySchedule next(int attemptCount) {
    final power = attemptCount <= 0 ? 0 : attemptCount - 1;
    final expSeconds = baseDelay.inSeconds * (1 << power.clamp(0, 10));
    final bounded = expSeconds.clamp(baseDelay.inSeconds, maxDelay.inSeconds);
    final jitter = _random.nextInt(((bounded * 0.25).ceil()).clamp(1, 30));
    final finalDelay = bounded + jitter;

    return RetrySchedule(
      at: DateTime.now().toUtc().add(Duration(seconds: finalDelay)),
      delaySeconds: finalDelay,
    );
  }
}

class SyncLog {
  static void info(String message) => debugPrint('ℹ️ [sync] $message');
  static void warn(String message) => debugPrint('⚠️ [sync] $message');
  static void error(String message) => debugPrint('❌ [sync] $message');
}

class SyncStatusCodec {
  static String encode(SyncStatus status) {
    switch (status) {
      case SyncStatus.draft:
        return 'draft';
      case SyncStatus.pending:
        return 'pending';
      case SyncStatus.syncing:
        return 'syncing';
      case SyncStatus.synced:
        return 'synced';
      case SyncStatus.failedTransient:
        return 'failed_transient';
      case SyncStatus.failedPermanent:
        return 'failed_permanent';
    }
  }

  static SyncStatus decode(Object? raw) {
    switch (raw?.toString()) {
      case 'draft':
        return SyncStatus.draft;
      case 'syncing':
        return SyncStatus.syncing;
      case 'synced':
        return SyncStatus.synced;
      case 'failed_transient':
        return SyncStatus.failedTransient;
      case 'failed_permanent':
        return SyncStatus.failedPermanent;
      case 'pending':
      default:
        return SyncStatus.pending;
    }
  }
}

class SyncErrorCodeCodec {
  static String encode(SyncErrorCode code) {
    switch (code) {
      case SyncErrorCode.none:
        return 'none';
      case SyncErrorCode.network:
        return 'network';
      case SyncErrorCode.auth:
        return 'auth';
      case SyncErrorCode.validation:
        return 'validation';
      case SyncErrorCode.server:
        return 'server';
      case SyncErrorCode.unknown:
        return 'unknown';
    }
  }
}