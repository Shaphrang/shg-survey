//lib\core\services\sync_service.dart
import 'package:flutter/foundation.dart';
import '../../features/survey/remote/household_remote_service.dart';
import 'offline_survey_service.dart';

class SyncService {
  final offline = OfflineSurveyService();
  final remote = HouseholdRemoteService();

  Future<Map<String, dynamic>> syncAll() async {
    final pending = offline.getPending();

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
            .map((e) => Map<String, dynamic>.from(e as Map))
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