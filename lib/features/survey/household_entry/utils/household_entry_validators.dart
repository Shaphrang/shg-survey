class HofValidationInput {
  final String hofName;
  final String? hofType;
  final String guardianSpecify;
  final String? hofGender;
  final String age;
  final String? hofMaritalStatus;
  final bool hofIsShgMember;
  final String shgName;
  final bool hofIsSpecialGroup;
  final String? hofSpecialGroup;

  const HofValidationInput({
    required this.hofName,
    required this.hofType,
    required this.guardianSpecify,
    required this.hofGender,
    required this.age,
    required this.hofMaritalStatus,
    required this.hofIsShgMember,
    required this.shgName,
    required this.hofIsSpecialGroup,
    required this.hofSpecialGroup,
  });
}

class HouseholdEntryValidators {
  const HouseholdEntryValidators._();

  static const Set<String> maleOnlyRelationshipGroup = <String>{
    'father',
    'son',
    'brother',
    'grandfather',
  };

  static const Set<String> femaleOnlyRelationshipGroup = <String>{
    'mother',
    'daughter',
    'sister',
    'grandmother',
  };

  static int? parseAge(String text) => int.tryParse(text.trim());

  static bool isMaleOnlyRelationship(String? relationship) =>
      maleOnlyRelationshipGroup.contains(relationship?.trim().toLowerCase());

  static bool isFemaleOnlyRelationship(String? relationship) =>
      femaleOnlyRelationshipGroup.contains(relationship?.trim().toLowerCase());

  static String? validateMemberGenderForRelationship({
    required String? relationshipToHof,
    required String? memberGender,
  }) {
    if (isMaleOnlyRelationship(relationshipToHof) && memberGender != 'M') {
      return 'Gender must be Male for this relationship';
    }
    if (isFemaleOnlyRelationship(relationshipToHof) && memberGender != 'F') {
      return 'Gender must be Female for this relationship';
    }
    return null;
  }

  static String? validateHofGenderForType({
    required String? hofType,
    required String? hofGender,
  }) {
    if (hofType == 'father' && hofGender != 'M') {
      return 'Gender must be Male for HOF type father';
    }
    if (hofType == 'mother' && hofGender != 'F') {
      return 'Gender must be Female for HOF type mother';
    }
    return null;
  }

  static List<String> allowedSpecialGroupsForAge(int? age) {
    if (age != null && age > 54) {
      return const ['Elderly', 'PWD'];
    }
    if (age != null && age > 11 && age < 18) {
      return const ['Adolescent Group', 'PWD'];
    }
    return const ['PWD'];
  }

  static String? validateOptionalAadhaar(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^\d+$').hasMatch(trimmed)) {
      return 'Aadhaar number must contain digits only';
    }
    if (trimmed.length != 12) {
      return 'Please enter exactly 12 digits for Aadhaar number';
    }
    return null;
  }

  static bool isHeadOfFamilyReadyToAddMember({
    required String hofName,
    required String? hofType,
    required String age,
    required String? hofGender,
  }) {
    return hofName.trim().isNotEmpty &&
        hofType != null &&
        parseAge(age) != null &&
        hofGender != null;
  }

  static String? validateHof(HofValidationInput input) {
    if (input.hofName.trim().isEmpty) {
      return 'Please enter head of family name';
    }
    if (input.hofType == null) {
      return 'Please select HOF type';
    }
    if (input.hofType == 'guardian' && input.guardianSpecify.trim().isEmpty) {
      return 'Please specify guardian';
    }
    if (input.hofGender == null) {
      return 'Please select gender';
    }
    final hofGenderError = validateHofGenderForType(
      hofType: input.hofType,
      hofGender: input.hofGender,
    );
    if (hofGenderError != null) {
      return hofGenderError;
    }

    final age = parseAge(input.age);
    if (age == null || age < 0 || age > 130) {
      return 'Please enter valid age';
    }

    if (input.hofMaritalStatus == null) {
      return 'Please select marital status';
    }

    if (input.hofIsShgMember && input.shgName.trim().isEmpty) {
      return 'Please enter SHG name';
    }

    if (input.hofIsSpecialGroup && input.hofSpecialGroup == null) {
      return 'Please select the special group type';
    }
    if (input.hofIsSpecialGroup && input.hofSpecialGroup != null) {
      final allowedGroups = allowedSpecialGroupsForAge(age);
      if (!allowedGroups.contains(input.hofSpecialGroup)) {
        return 'Selected special group is not allowed for the current age';
      }
    }

    return null;
  }
}
