class HouseholdEntryFormatters {
  const HouseholdEntryFormatters._();

  static String formatRelationship(String? value) {
    switch (value) {
      case 'spouse':
        return 'Spouse';
      case 'son':
        return 'Son';
      case 'daughter':
        return 'Daughter';
      case 'father':
        return 'Father';
      case 'mother':
        return 'Mother';
      case 'brother':
        return 'Brother';
      case 'sister':
        return 'Sister';
      case 'grandfather':
        return 'Grandfather';
      case 'grandmother':
        return 'Grandmother';
      case 'other':
        return 'Other';
      case 'head_of_family':
        return 'Head of Family';
      default:
        return 'Member';
    }
  }

  static String formatGender(String? value) {
    switch (value) {
      case 'M':
        return 'Male';
      case 'F':
        return 'Female';
      default:
        return '-';
    }
  }

  static String buildMemberMeta(Map<String, dynamic> member) {
    final parts = <String>[];
    final relationship = member['relationship_to_hof']?.toString();
    final relationshipOther = member['relationship_to_hof_other']?.toString();
    if (relationship == 'other' &&
        relationshipOther != null &&
        relationshipOther.trim().isNotEmpty) {
      parts.add('Other: ${relationshipOther.trim()}');
    }

    if (member['is_shg_member'] == true) {
      final shgName = member['shg_name']?.toString();
      final shgCode = member['shg_code']?.toString();
      if (shgName != null && shgName.trim().isNotEmpty) {
        parts.add('SHG: ${shgName.trim()}');
      }
      if (shgCode != null && shgCode.trim().isNotEmpty) {
        parts.add('SHG Code: ${shgCode.trim()}');
      }
    }

    if (member['has_aadhaar'] == true) {
      final aadhaar = member['aadhaar_no']?.toString();
      if (aadhaar != null && aadhaar.trim().isNotEmpty) {
        parts.add('Aadhaar: ${aadhaar.trim()}');
      }
    }
    if (member['has_epic'] == true) {
      final epic = member['epic_no']?.toString();
      if (epic != null && epic.trim().isNotEmpty) {
        parts.add('EPIC: ${epic.trim()}');
      }
    }
    if (member['is_pmayg'] == true) {
      final pmayg = member['pmayg_code']?.toString();
      if (pmayg != null && pmayg.trim().isNotEmpty) {
        parts.add('PMAY-G: ${pmayg.trim()}');
      }
    }
    if (member['is_job_card_holder'] == true) {
      final jobCard = member['job_card_code']?.toString();
      if (jobCard != null && jobCard.trim().isNotEmpty) {
        parts.add('Job Card: ${jobCard.trim()}');
      }
    }
    return parts.join(' • ');
  }
}
