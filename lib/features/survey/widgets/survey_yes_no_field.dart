import 'package:flutter/material.dart';

class SurveyYesNoField extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool dismissKeyboardOnToggle;

  const SurveyYesNoField({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.dismissKeyboardOnToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  fontSize: 14.5,
                  letterSpacing: 0.1,
                  height: 1.2,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChoicePill(
                  label: 'Yes',
                  selected: value,
                  onTap: () {
                    if (dismissKeyboardOnToggle) {
                      FocusManager.instance.primaryFocus?.unfocus();
                    }
                    onChanged(true);
                  },
                ),
                const SizedBox(width: 6),
                _ChoicePill(
                  label: 'No',
                  selected: !value,
                  onTap: () {
                    if (dismissKeyboardOnToggle) {
                      FocusManager.instance.primaryFocus?.unfocus();
                    }
                    onChanged(false);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isYes = label == 'Yes';

    final LinearGradient selectedGradient = isYes
        ? const LinearGradient(
            colors: [
              Color(0xFF38BDF8),
              Color(0xFF2563EB),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [
              Color(0xFFEF4444),
              Color(0xFFDC2626),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Semantics(
      button: true,
      selected: selected,
      label: '$label option',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(
              minHeight: 36,
              minWidth: 58,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: selected ? selectedGradient : null,
              color: selected ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
