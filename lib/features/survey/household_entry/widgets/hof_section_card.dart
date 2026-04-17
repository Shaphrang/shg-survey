import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/survey_yes_no_field.dart';
import '../utils/household_entry_constants.dart';
import 'animated_visibility_section.dart';
import 'choice_segmented_field.dart';
import 'survey_section_card.dart';

class HofSectionData {
  final TextEditingController hofNameController;
  final TextEditingController hofGuardianSpecifyController;
  final TextEditingController hofAgeController;
  final TextEditingController hofShgNameController;
  final TextEditingController hofShgCodeController;
  final TextEditingController hofAadhaarController;
  final TextEditingController hofEpicController;
  final TextEditingController hofPmaygCodeController;
  final TextEditingController hofJobCardCodeController;
  final FocusNode hofNameFocusNode;
  final String? hofType;
  final String? hofGender;
  final String? hofMaritalStatus;
  final bool hofIsShgMember;
  final bool hofIsJobCardHolder;
  final bool hofIsPmayg;
  final bool hofHasAadhaar;
  final bool hofHasEpic;
  final bool hofIsSpecialGroup;
  final String? hofSpecialGroup;
  final bool showShgField;
  final List<String> availableSpecialGroups;
  final String? hofGenderErrorText;
  final String? hofAadhaarErrorText;

  const HofSectionData({
    required this.hofNameController,
    required this.hofGuardianSpecifyController,
    required this.hofAgeController,
    required this.hofShgNameController,
    required this.hofShgCodeController,
    required this.hofAadhaarController,
    required this.hofEpicController,
    required this.hofPmaygCodeController,
    required this.hofJobCardCodeController,
    required this.hofNameFocusNode,
    required this.hofType,
    required this.hofGender,
    required this.hofMaritalStatus,
    required this.hofIsShgMember,
    required this.hofIsJobCardHolder,
    required this.hofIsPmayg,
    required this.hofHasAadhaar,
    required this.hofHasEpic,
    required this.hofIsSpecialGroup,
    required this.hofSpecialGroup,
    required this.showShgField,
    required this.availableSpecialGroups,
    required this.hofGenderErrorText,
    required this.hofAadhaarErrorText,
  });
}

class HofSectionCard extends StatelessWidget {
  final HofSectionData data;
  final ValueChanged<String> onHofTypeChanged;
  final ValueChanged<String> onHofGenderChanged;
  final ValueChanged<String?> onMaritalStatusChanged;
  final ValueChanged<bool> onShgChanged;
  final ValueChanged<bool> onPmaygChanged;
  final ValueChanged<bool> onSpecialGroupChanged;
  final ValueChanged<String?> onSpecialGroupTypeChanged;
  final ValueChanged<bool> onJobCardChanged;
  final ValueChanged<bool> onAadhaarChanged;
  final ValueChanged<bool> onEpicChanged;

  const HofSectionCard({
    super.key,
    required this.data,
    required this.onHofTypeChanged,
    required this.onHofGenderChanged,
    required this.onMaritalStatusChanged,
    required this.onShgChanged,
    required this.onPmaygChanged,
    required this.onSpecialGroupChanged,
    required this.onSpecialGroupTypeChanged,
    required this.onJobCardChanged,
    required this.onAadhaarChanged,
    required this.onEpicChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SurveySectionCard(
      title: 'Head of Family',
      subtitle: 'First entry will also be saved as member #1',
      icon: Icons.badge_rounded,
      onTap: () => FocusScope.of(context).requestFocus(data.hofNameFocusNode),
      child: Column(
        children: [
          TextField(
            controller: data.hofNameController,
            focusNode: data.hofNameFocusNode,
            decoration: const InputDecoration(
              labelText: 'HOF Name',
              prefixIcon: Icon(Icons.person_rounded),
            ),
          ),
          const SizedBox(height: 16),
          ChoiceSegmentedField(
            title: 'HOF Type',
            options: const [
              ChoiceOption('father', 'Father'),
              ChoiceOption('mother', 'Mother'),
              ChoiceOption('guardian', 'Guardian'),
            ],
            selectedValue: data.hofType,
            onSelected: onHofTypeChanged,
          ),
          AnimatedVisibilitySection(
            show: data.hofType == 'guardian',
            child: TextField(
              controller: data.hofGuardianSpecifyController,
              decoration: const InputDecoration(
                labelText: 'If guardian, specify',
                prefixIcon: Icon(Icons.badge_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: data.hofAgeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Age',
              prefixIcon: Icon(Icons.cake_rounded),
            ),
          ),
          const SizedBox(height: 16),
          ChoiceSegmentedField(
            title: 'Gender',
            options: const [
              ChoiceOption('M', 'Male'),
              ChoiceOption('F', 'Female'),
            ],
            selectedValue: data.hofGender,
            errorText: data.hofGenderErrorText,
            onSelected: onHofGenderChanged,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: data.hofMaritalStatus,
            decoration: const InputDecoration(
              labelText: 'Marital Status',
              prefixIcon: Icon(Icons.favorite_outline_rounded),
            ),
            items: maritalOptions
                .map(
                  (e) => DropdownMenuItem<String>(
                    value: e,
                    child: Text(e),
                  ),
                )
                .toList(),
            onChanged: onMaritalStatusChanged,
          ),
          const SizedBox(height: 16),
          SurveyYesNoField(
            title: 'Is part of a special group',
            value: data.hofIsSpecialGroup,
            onChanged: onSpecialGroupChanged,
          ),
          AnimatedVisibilitySection(
            show: data.hofIsSpecialGroup,
            child: DropdownButtonFormField<String>(
              initialValue: data.hofSpecialGroup,
              decoration: const InputDecoration(
                labelText: 'Special Group Type',
                prefixIcon: Icon(Icons.workspace_premium_rounded),
              ),
              items: data.availableSpecialGroups
                  .map(
                    (e) => DropdownMenuItem<String>(
                      value: e,
                      child: Text(e),
                    ),
                  )
                  .toList(),
              onChanged: onSpecialGroupTypeChanged,
            ),
          ),
          const SizedBox(height: 16),
          AnimatedVisibilitySection(
            show: data.showShgField,
            child: SurveyYesNoField(
              title: 'Part of SHG',
              value: data.hofIsShgMember,
              onChanged: onShgChanged,
            ),
          ),
          AnimatedVisibilitySection(
            show: data.showShgField && data.hofIsShgMember,
            child: Column(
              children: [
                TextField(
                  controller: data.hofShgNameController,
                  decoration: const InputDecoration(
                    labelText: 'SHG Name',
                    prefixIcon: Icon(Icons.groups_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: data.hofShgCodeController,
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
            title: 'PMAY-G Beneficiary',
            value: data.hofIsPmayg,
            onChanged: onPmaygChanged,
          ),
          AnimatedVisibilitySection(
            show: data.hofIsPmayg,
            child: TextField(
              controller: data.hofPmaygCodeController,
              decoration: const InputDecoration(
                labelText: 'PMAY-G Code (Optional)',
                prefixIcon: Icon(Icons.home_work_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SurveyYesNoField(
            title: 'Job Card Holder',
            value: data.hofIsJobCardHolder,
            onChanged: onJobCardChanged,
          ),
          AnimatedVisibilitySection(
            show: data.hofIsJobCardHolder,
            child: TextField(
              controller: data.hofJobCardCodeController,
              decoration: const InputDecoration(
                labelText: 'Job Card Code (Optional)',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SurveyYesNoField(
            title: 'Has Aadhaar',
            value: data.hofHasAadhaar,
            onChanged: onAadhaarChanged,
          ),
          AnimatedVisibilitySection(
            show: data.hofHasAadhaar,
            child: TextField(
              controller: data.hofAadhaarController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12),
              ],
              decoration: InputDecoration(
                labelText: 'Aadhaar Number (Optional)',
                prefixIcon: Icon(Icons.credit_card_rounded),
                errorText: data.hofAadhaarErrorText,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SurveyYesNoField(
            title: 'Has EPIC',
            value: data.hofHasEpic,
            onChanged: onEpicChanged,
          ),
          AnimatedVisibilitySection(
            show: data.hofHasEpic,
            child: TextField(
              controller: data.hofEpicController,
              decoration: const InputDecoration(
                labelText: 'EPIC Number (Optional)',
                prefixIcon: Icon(Icons.how_to_vote_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
