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

  static int? parseAge(String text) => int.tryParse(text.trim());

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
    if (input.hofType == 'father' && input.hofGender != 'M') {
      return 'If HOF type is father, gender must be Male';
    }
    if (input.hofType == 'mother' && input.hofGender != 'F') {
      return 'If HOF type is mother, gender must be Female';
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

    return null;
  }
}
