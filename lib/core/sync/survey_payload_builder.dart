import 'dart:convert';

import 'package:crypto/crypto.dart';

class SurveyPayloadBuilder {
  const SurveyPayloadBuilder();

  Map<String, dynamic> validateAndBuild({
    required Map<String, dynamic> submission,
  }) {

    final submissionUuid = submission['local_submission_uuid']?.toString() ?? '';
    if (submissionUuid.isEmpty) {
      throw const FormatException('local_submission_uuid is required');
    }

    final householdRaw = submission['household'];
    final membersRaw = submission['members'];

    if (householdRaw is! Map) {
      throw const FormatException('Submission household payload is invalid');
    }
    if (membersRaw is! List) {
      throw const FormatException('Submission members payload is invalid');
    }

    final household = Map<String, dynamic>.from(householdRaw);
    final members = membersRaw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);

    final householdRef = household['device_household_ref']?.toString() ?? '';
    if (householdRef.isEmpty) {
      throw const FormatException('device_household_ref is required');
    }

    if (members.isEmpty) {
      throw const FormatException('At least one member is required');
    }

    final seenMemberRefs = <String>{};
    final seenSortOrder = <int>{};

    for (final member in members) {
      final ref = member['device_member_ref']?.toString() ?? '';
      final sortOrder = member['sort_order'];
      if (ref.isEmpty) {
        throw const FormatException('Each member requires device_member_ref');
      }
      if (!seenMemberRefs.add(ref)) {
        throw FormatException('Duplicate device_member_ref: $ref');
      }
      if (sortOrder is! int || sortOrder <= 0) {
        throw const FormatException('Each member requires positive sort_order');
      }
      if (!seenSortOrder.add(sortOrder)) {
        throw FormatException('Duplicate sort_order: $sortOrder');
      }
    }

    return {
      'p_household': household,
      'p_members': members,
      'p_submission_uuid': submissionUuid,
      'p_payload_hash': payloadHash({
        'household': household,
        'members': members,
      }),
    };
  }

  String payloadHash(Map<String, dynamic> payload) {
    final canonical = _canonicalize(payload);
    final bytes = utf8.encode(canonical);
    return sha256.convert(bytes).toString();
  }

  String _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      final normalized = <String, Object?>{};
      for (final key in keys) {
        normalized[key] = _normalize(value[key]);
      }
      return jsonEncode(normalized);
    }
    return jsonEncode(_normalize(value));
  }

  Object? _normalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return {
        for (final key in keys) key: _normalize(value[key]),
      };
    }
    if (value is List) {
      return value.map(_normalize).toList(growable: false);
    }
    return value;
  }
}