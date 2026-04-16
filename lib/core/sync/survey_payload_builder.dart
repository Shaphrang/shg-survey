import 'dart:convert';

import 'package:crypto/crypto.dart';

class SurveyPayloadBuilder {
  const SurveyPayloadBuilder();

  static const List<String> allowedSpecialGroups = <String>[
    'Elderly',
    'PWD',
    'Adolescent Group',
  ];

  static const List<String> _optionalMemberTextFields = <String>[
    'relationship_to_hof_other',
    'shg_name',
    'shg_code',
    'aadhaar_no',
    'epic_no',
    'pmayg_code',
    'job_card_code',
  ];

  Map<String, dynamic> validateAndBuild({
    required Map<String, dynamic> submission,
  }) {
    final normalizedSubmission = normalizeSubmission(submission);
    final submissionUuid =
        normalizedSubmission['local_submission_uuid']?.toString() ?? '';
    if (submissionUuid.isEmpty) {
      throw const FormatException('local_submission_uuid is required');
    }

    final householdRaw = normalizedSubmission['household'];
    final membersRaw = normalizedSubmission['members'];

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

      final relationship = member['relationship_to_hof']?.toString() ?? '';
      if (relationship.isEmpty) {
        throw const FormatException('relationship_to_hof is required');
      }

      final relationshipOther = member['relationship_to_hof_other'];
      if (relationship == 'other' &&
          (relationshipOther == null ||
              relationshipOther.toString().trim().isEmpty)) {
        throw const FormatException(
          'relationship_to_hof_other is required when relationship_to_hof is other',
        );
      }
      if (relationship != 'other' && relationshipOther != null) {
        throw const FormatException(
          'relationship_to_hof_other must be null when relationship_to_hof is not other',
        );
      }

      final gender = member['gender']?.toString();
      if (gender != 'M' && gender != 'F') {
        throw const FormatException('gender must be either M or F');
      }

      final isShgMember = member['is_shg_member'] == true;
      final shgName = member['shg_name']?.toString();
      final shgCode = member['shg_code'];
      if (isShgMember && (shgName == null || shgName.trim().isEmpty)) {
        throw const FormatException('shg_name is required when is_shg_member is true');
      }
      if (!isShgMember && (shgName != null || shgCode != null)) {
        throw const FormatException(
          'shg_name and shg_code must be null when is_shg_member is false',
        );
      }

      final specialGroup = member['special_group'];
      if (specialGroup != null &&
          !allowedSpecialGroups.contains(specialGroup.toString())) {
        throw const FormatException('special_group is invalid');
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

  Map<String, dynamic> normalizeSubmission(Map<String, dynamic> submission) {
    final normalized = Map<String, dynamic>.from(submission);
    final householdRaw = normalized['household'];
    final membersRaw = normalized['members'];

    if (householdRaw is Map) {
      normalized['household'] = _normalizeHousehold(householdRaw);
    }

    if (membersRaw is List) {
      normalized['members'] = membersRaw
          .whereType<Map>()
          .map((e) => normalizeMember(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }

    return normalized;
  }

  Map<String, dynamic> _normalizeHousehold(Map household) {
    final normalized = Map<String, dynamic>.from(household);
    for (final key in normalized.keys.toList(growable: false)) {
      normalized[key] = _trimIfString(normalized[key]);
    }
    return normalized;
  }

  Map<String, dynamic> normalizeMember(Map<String, dynamic> member) {
    final normalized = Map<String, dynamic>.from(member);
    for (final key in normalized.keys.toList(growable: false)) {
      normalized[key] = _trimIfString(normalized[key]);
    }

    if (!normalized.containsKey('relationship_to_hof_other') &&
        normalized.containsKey('guardian_name')) {
      normalized['relationship_to_hof_other'] = normalized['guardian_name'];
    }

    if (!normalized.containsKey('shg_name') &&
        normalized.containsKey('shg_name_or_code')) {
      normalized['shg_name'] = normalized['shg_name_or_code'];
    }

    normalized.remove('guardian_name');
    normalized.remove('shg_name_or_code');
    normalized.remove('aadhaar_not_willing');
    normalized.remove('willing_to_share');
    normalized.remove('is_pwd');

    final genderRaw = normalized['gender']?.toString().trim().toUpperCase();
    if (genderRaw == 'MALE') {
      normalized['gender'] = 'M';
    } else if (genderRaw == 'FEMALE') {
      normalized['gender'] = 'F';
    } else if (genderRaw == 'M' || genderRaw == 'F') {
      normalized['gender'] = genderRaw;
    }

    final relationship =
        normalized['relationship_to_hof']?.toString().trim().toLowerCase();
    if (relationship != null && relationship.isNotEmpty) {
      normalized['relationship_to_hof'] = relationship;
    }

    final special = normalized['special_group']?.toString().trim();
    if (special == null || special.isEmpty) {
      normalized['special_group'] = null;
    } else if (!allowedSpecialGroups.contains(special)) {
      normalized['special_group'] = null;
    } else {
      normalized['special_group'] = special;
    }

    for (final key in _optionalMemberTextFields) {
      normalized[key] = _nullIfBlank(normalized[key]);
    }

    final isShgMember = normalized['is_shg_member'] == true;
    final hasAadhaar = normalized['has_aadhaar'] == true;
    final hasEpic = normalized['has_epic'] == true;
    final isPmayg = normalized['is_pmayg'] == true;
    final isJobCardHolder = normalized['is_job_card_holder'] == true;
    final relationshipIsOther = relationship == 'other';

    if (!relationshipIsOther) {
      normalized['relationship_to_hof_other'] = null;
    }
    if (!isShgMember) {
      normalized['shg_name'] = null;
      normalized['shg_code'] = null;
    }
    if (!hasAadhaar) {
      normalized['aadhaar_no'] = null;
    }
    if (!hasEpic) {
      normalized['epic_no'] = null;
    }
    if (!isPmayg) {
      normalized['pmayg_code'] = null;
    }
    if (!isJobCardHolder) {
      normalized['job_card_code'] = null;
    }

    return normalized;
  }

  String? _nullIfBlank(Object? value) {
    final trimmed = _trimIfString(value);
    if (trimmed == null) return null;
    if (trimmed is String && trimmed.isEmpty) return null;
    return trimmed.toString();
  }

  Object? _trimIfString(Object? value) {
    if (value is String) {
      return value.trim();
    }
    return value;
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
