import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/sync/survey_payload_builder.dart';
import '../../widgets/survey_yes_no_field.dart';
import '../utils/household_entry_constants.dart';
import '../utils/household_entry_formatters.dart';
import '../utils/household_entry_validators.dart';
import 'animated_visibility_section.dart';
import 'choice_segmented_field.dart';

class MemberFormSheet extends StatefulWidget {
  final Map<String, dynamic>? initialMember;
  final List<String> relationshipOptions;

  const MemberFormSheet({
    super.key,
    this.initialMember,
    required this.relationshipOptions,
  });

  @override
  State<MemberFormSheet> createState() => _MemberFormSheetState();
}

class _MemberFormSheetState extends State<MemberFormSheet> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final SurveyPayloadBuilder payloadBuilder = const SurveyPayloadBuilder();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController ageController = TextEditingController();
  final TextEditingController relationshipOtherController =
      TextEditingController();
  final TextEditingController shgNameController = TextEditingController();
  final TextEditingController shgCodeController = TextEditingController();
  final TextEditingController aadhaarController = TextEditingController();
  final TextEditingController epicController = TextEditingController();
  final TextEditingController pmaygCodeController = TextEditingController();
  final TextEditingController jobCardCodeController = TextEditingController();

  String? relationship;
  String? gender;
  String? maritalStatus;
  String? specialGroup;

  bool isShgMember = false;
  bool isJobCardHolder = false;
  bool isPmayg = false;
  bool isSpecialGroup = false;
  bool hasAadhaar = false;
  bool hasEpic = false;
  bool hasSubmitted = false;

  String? relationshipError;
  String? genderError;
  String? maritalStatusError;

  int? get _memberAge => HouseholdEntryValidators.parseAge(ageController.text);

  List<String> get _allowedSpecialGroupsForAge =>
      HouseholdEntryValidators.allowedSpecialGroupsForAge(_memberAge);

  bool get _showEpicSection => (_memberAge ?? -1) > 18;

  bool get _showShgSectionForRelationship {
    final isMaleRelationship =
        HouseholdEntryValidators.isMaleOnlyRelationship(relationship);
    if (!isMaleRelationship) return true;
    return isSpecialGroup;
  }

  void _clearShgState() {
    isShgMember = false;
    shgNameController.clear();
    shgCodeController.clear();
  }

  void _clearEpicState() {
    hasEpic = false;
    epicController.clear();
  }

  void _syncMemberDependentState() {
    if (!_showShgSectionForRelationship) {
      _clearShgState();
    }

    if (!_showEpicSection) {
      _clearEpicState();
    }

    if (!hasAadhaar) {
      aadhaarController.clear();
    }

    if (specialGroup != null &&
        !_allowedSpecialGroupsForAge.contains(specialGroup)) {
      specialGroup = null;
    }

    genderError = HouseholdEntryValidators.validateMemberGenderForRelationship(
      relationshipToHof: relationship,
      memberGender: gender,
    );
  }

  @override
  void initState() {
    super.initState();

    final rawMember = widget.initialMember;
    final m = rawMember == null
        ? null
        : payloadBuilder.normalizeMember(Map<String, dynamic>.from(rawMember));
    if (m != null) {
      nameController.text = (m['member_name'] ?? '').toString();
      ageController.text = (m['age'] ?? '').toString();
      relationshipOtherController.text =
          (m['relationship_to_hof_other'] ?? '').toString();
      shgNameController.text = (m['shg_name'] ?? '').toString();
      shgCodeController.text = (m['shg_code'] ?? '').toString();
      aadhaarController.text = (m['aadhaar_no'] ?? '').toString();
      epicController.text = (m['epic_no'] ?? '').toString();
      pmaygCodeController.text = (m['pmayg_code'] ?? '').toString();
      jobCardCodeController.text = (m['job_card_code'] ?? '').toString();

      relationship = m['relationship_to_hof']?.toString();
      gender = m['gender']?.toString();
      maritalStatus = m['marital_status']?.toString();
      specialGroup = m['special_group']?.toString();

      isShgMember = m['is_shg_member'] == true;
      isJobCardHolder = m['is_job_card_holder'] == true;
      isPmayg = m['is_pmayg'] == true;
      isSpecialGroup = specialGroup != null && specialGroup!.isNotEmpty;
      hasAadhaar = m['has_aadhaar'] == true;
      hasEpic = m['has_epic'] == true;
    }

    if (relationship != null &&
        !widget.relationshipOptions.contains(relationship)) {
      relationship = null;
      relationshipOtherController.clear();
    }

    _syncMemberDependentState();
  }

  @override
  void dispose() {
    nameController.dispose();
    ageController.dispose();
    relationshipOtherController.dispose();
    shgNameController.dispose();
    shgCodeController.dispose();
    aadhaarController.dispose();
    epicController.dispose();
    pmaygCodeController.dispose();
    jobCardCodeController.dispose();
    super.dispose();
  }

  void submit() {
    _syncMemberDependentState();
    final valid = formKey.currentState?.validate() ?? false;

    setState(() {
      hasSubmitted = true;
      relationshipError =
          relationship == null ? 'Please select relationship' : null;
      genderError = gender == null
          ? 'Please select gender'
          : HouseholdEntryValidators.validateMemberGenderForRelationship(
              relationshipToHof: relationship,
              memberGender: gender,
            );
      maritalStatusError =
          maritalStatus == null ? 'Please select marital status' : null;
    });

    if (!valid ||
        relationshipError != null ||
        genderError != null ||
        maritalStatusError != null) {
      return;
    }

    Navigator.pop(context, {
      'device_member_ref': widget.initialMember?['device_member_ref'],
      'relationship_to_hof': relationship,
      'relationship_to_hof_other':
          relationship == 'other' ? relationshipOtherController.text.trim() : null,
      'member_name': nameController.text.trim(),
      'gender': gender,
      'age': int.parse(ageController.text.trim()),
      'marital_status': maritalStatus,
      'is_shg_member': isShgMember,
      'shg_name': isShgMember ? shgNameController.text.trim() : null,
      'shg_code': isShgMember ? shgCodeController.text.trim() : null,
      'special_group': isSpecialGroup ? specialGroup : null,
      'is_job_card_holder': isJobCardHolder,
      'job_card_code': isJobCardHolder ? jobCardCodeController.text.trim() : null,
      'is_pmayg': isPmayg,
      'pmayg_code': isPmayg ? pmaygCodeController.text.trim() : null,
      'has_aadhaar': hasAadhaar,
      'aadhaar_no': hasAadhaar ? aadhaarController.text.trim() : null,
      'has_epic': hasEpic,
      'epic_no': hasEpic ? epicController.text.trim() : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialMember != null;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F7FB),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 52,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white.withOpacity(0.18),
                      child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isEditing ? 'Edit Member' : 'Add Member',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  child: Form(
                    key: formKey,
                    autovalidateMode: hasSubmitted
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: relationship,
                            decoration: InputDecoration(
                              labelText: 'Relationship to HOF',
                              prefixIcon: const Icon(Icons.family_restroom_rounded),
                              errorText: relationshipError,
                            ),
                            items: widget.relationshipOptions
                                .map((e) => DropdownMenuItem<String>(
                                      value: e,
                                      child: Text(HouseholdEntryFormatters.formatRelationship(e)),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                relationship = value;
                                relationshipError = null;
                                if (value != 'other') {
                                  relationshipOtherController.clear();
                                }
                                _syncMemberDependentState();
                              });
                            },
                          ),
                          AnimatedVisibilitySection(
                            show: relationship == 'other',
                            child: TextFormField(
                              controller: relationshipOtherController,
                              decoration: const InputDecoration(
                                labelText: 'Specify Relationship',
                                prefixIcon: Icon(Icons.edit_note_rounded),
                              ),
                              validator: (value) {
                                if (relationship == 'other' &&
                                    (value == null || value.trim().isEmpty)) {
                                  return 'Please specify relationship';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Member Name',
                              prefixIcon: Icon(Icons.person_rounded),
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                    ? 'Please enter member name'
                                    : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: ageController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Age',
                              prefixIcon: Icon(Icons.cake_rounded),
                            ),
                            validator: (value) {
                              final age = HouseholdEntryValidators.parseAge(value ?? '');
                              if (age == null || age < 0 || age > 130) {
                                return 'Please enter valid age';
                              }
                              return null;
                            },
                            onChanged: (_) {
                              setState(() {
                                _syncMemberDependentState();
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          ChoiceSegmentedField(
                            title: 'Gender',
                            options: const [
                              ChoiceOption('M', 'Male'),
                              ChoiceOption('F', 'Female'),
                            ],
                            selectedValue: gender,
                            errorText: genderError,
                            onSelected: (value) {
                              setState(() {
                                gender = value;
                                _syncMemberDependentState();
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: maritalStatus,
                            decoration: InputDecoration(
                              labelText: 'Marital Status',
                              prefixIcon: const Icon(Icons.favorite_outline_rounded),
                              errorText: maritalStatusError,
                            ),
                            items: maritalOptions
                                .map((e) => DropdownMenuItem<String>(
                                      value: e,
                                      child: Text(e),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                maritalStatus = value;
                                maritalStatusError = null;
                                _syncMemberDependentState();
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          SurveyYesNoField(
                            title: 'Is part of a special group',
                            value: isSpecialGroup,
                            onChanged: (value) {
                              setState(() {
                                isSpecialGroup = value;
                                if (!value) {
                                  specialGroup = null;
                                }
                                _syncMemberDependentState();
                              });
                            },
                          ),
                          AnimatedVisibilitySection(
                            show: isSpecialGroup,
                            child: DropdownButtonFormField<String>(
                              initialValue: specialGroup,
                              decoration: const InputDecoration(
                                labelText: 'Special Group Type',
                                prefixIcon: Icon(Icons.workspace_premium_rounded),
                              ),
                              items: specialGroupOptions
                                  .where(_allowedSpecialGroupsForAge.contains)
                                  .map((e) => DropdownMenuItem<String>(
                                        value: e,
                                        child: Text(e),
                                      ))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  specialGroup = value;
                                  _syncMemberDependentState();
                                });
                              },
                              validator: (value) {
                                if (isSpecialGroup && value == null) {
                                  return 'Please select special group type';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          AnimatedVisibilitySection(
                            show: _showShgSectionForRelationship,
                            child: SurveyYesNoField(
                              title: 'Part of SHG',
                              value: isShgMember,
                              onChanged: (value) {
                                setState(() {
                                  isShgMember = value;
                                  if (!value) {
                                    shgNameController.clear();
                                    shgCodeController.clear();
                                  }
                                });
                              },
                            ),
                          ),
                          AnimatedVisibilitySection(
                            show: _showShgSectionForRelationship && isShgMember,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: shgNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'SHG Name',
                                    prefixIcon: Icon(Icons.groups_rounded),
                                  ),
                                  validator: (value) {
                                    if (isShgMember &&
                                        (value == null || value.trim().isEmpty)) {
                                      return 'Please enter SHG name';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: shgCodeController,
                                  decoration: const InputDecoration(
                                    labelText: 'SHG Code (Optional)',
                                    prefixIcon: Icon(Icons.qr_code_rounded),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SurveyYesNoField(
                            title: 'Job Card Holder',
                            value: isJobCardHolder,
                            onChanged: (value) {
                              setState(() {
                                isJobCardHolder = value;
                                if (!value) {
                                  jobCardCodeController.clear();
                                }
                              });
                            },
                          ),
                          AnimatedVisibilitySection(
                            show: isJobCardHolder,
                            child: TextFormField(
                              controller: jobCardCodeController,
                              decoration: const InputDecoration(
                                labelText: 'Job Card Code (Optional)',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SurveyYesNoField(
                            title: 'Has Aadhaar',
                            value: hasAadhaar,
                            onChanged: (value) {
                              setState(() {
                                hasAadhaar = value;
                                _syncMemberDependentState();
                              });
                            },
                          ),
                          AnimatedVisibilitySection(
                            show: hasAadhaar,
                            child: TextFormField(
                              controller: aadhaarController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Aadhaar Number (Optional)',
                                prefixIcon: Icon(Icons.credit_card_rounded),
                              ),
                              validator: (value) =>
                                  HouseholdEntryValidators.validateOptionalAadhaar(
                                value ?? '',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AnimatedVisibilitySection(
                            show: _showEpicSection,
                            child: SurveyYesNoField(
                              title: 'Has EPIC',
                              value: hasEpic,
                              onChanged: (value) {
                                setState(() {
                                  hasEpic = value;
                                  if (!value) epicController.clear();
                                });
                              },
                            ),
                          ),
                          AnimatedVisibilitySection(
                            show: _showEpicSection && hasEpic,
                            child: TextFormField(
                              controller: epicController,
                              decoration: const InputDecoration(
                                labelText: 'EPIC Number (Optional)',
                                prefixIcon: Icon(Icons.how_to_vote_rounded),
                              ),
                            ),
                          ),
                          if (!_showShgSectionForRelationship)
                            const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: Text(
                                'Part of SHG is available for this relationship only when special group is Yes.',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF0F766E), Color(0xFF10B981)],
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: ElevatedButton(
                                    onPressed: submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                    ),
                                    child: Text(
                                      isEditing ? 'Update Member' : 'Add Member',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
