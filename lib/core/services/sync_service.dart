//lib\core\services\sync_service.dart
import 'package:flutter/foundation.dart';
import '../../features/survey/remote/household_remote_service.dart';
import 'offline_survey_service.dart';

class SyncService {
  final offline = OfflineSurveyService();
  final remote = HouseholdRemoteService();

  Future<Map<String, dynamic>> syncAll() async {
    final pending = offline.getPending()
      ..sort((a, b) {
        final aCreated = DateTime.tryParse((a['created_at'] ?? '').toString());
        final bCreated = DateTime.tryParse((b['created_at'] ?? '').toString());
        if (aCreated == null && bCreated == null) return 0;
        if (aCreated == null) return 1;
        if (bCreated == null) return -1;
        return aCreated.compareTo(bCreated);
      });

    if (pending.isEmpty) {
      debugPrint("📦 No pending data");
      return {
        "total": 0,
        "uploaded": 0,
        "failed": 0,
        "errors": <String>[],
      };
    }

    int success = 0;
    int failed = 0;
    final List<String> errors = [];

    for (final item in pending) {
      try {
        final localId = item["id"]?.toString() ?? 'unknown_local_id';

        final householdRaw = item["household"];
        final membersRaw = item["members"];

        if (householdRaw is! Map) {
          throw Exception("Invalid household payload type");
        }

        if (membersRaw is! List) {
          throw Exception("Invalid members payload type");
        }

        final household = Map<String, dynamic>.from(householdRaw);
        final members = membersRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        if (household.isEmpty || members.isEmpty) {
          throw Exception("Empty household or members payload");
        }

        await remote.saveHouseholdSurvey(
          household: household,
          members: members,
        );

        await offline.markUploaded(localId);
        success++;
      } catch (e) {
        failed++;
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        final itemId = item["id"]?.toString() ?? 'unknown_local_id';
        final message = '[$itemId] $errorMessage';
        
        await offline.markFailed(
          id: itemId,
          error: errorMessage,
        );

        errors.add(message);
        debugPrint("❌ Sync failed for one household: $message");
      }
    }

    if (success > 0) {
      await offline.clearUploaded();
    }

    return {
      "total": pending.length,
      "uploaded": success,
      "failed": failed,
      "errors": errors,
    };
  }
}