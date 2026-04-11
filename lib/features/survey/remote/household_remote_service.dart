//lib\features\survey\remote\household_remote_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class HouseholdRemoteService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> saveHouseholdSurvey({
    required Map<String, dynamic> household,
    required List<Map<String, dynamic>> members,
    required String submissionUuid,
    required String payloadHash,
  }) async {
    try {
      final response = await supabase
          .rpc(
            'save_household_survey',
            params: {
              'p_household': household,
              'p_members': members,
              'p_submission_uuid': submissionUuid,
              'p_payload_hash': payloadHash,
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }

      if (response is String) {
        final decoded = jsonDecode(response);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }

      throw Exception(
        'Unexpected response from save_household_survey: '
        '${response.runtimeType} -> $response',
      );
    } on TimeoutException {
      throw Exception('Server timeout while saving household');
    } on PostgrestException catch (e) {

      final message = e.message.toString().trim();
      final details = (e.details?.toString() ?? '').trim();
      final hint = (e.hint?.toString() ?? '').trim();
      final code = (e.code?.toString() ?? '').trim();

      final parts = <String>[
        if (message.isNotEmpty) message,
        if (details.isNotEmpty) details,
        if (hint.isNotEmpty) 'Hint: $hint',
        if (code.isNotEmpty) 'Code: $code',
      ];

      throw Exception(parts.join(' | '));
    } catch (e) {
      throw Exception('Remote save failed: $e');
    }
  }
}
