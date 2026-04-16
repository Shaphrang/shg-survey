import 'package:flutter/material.dart';

class ChoiceOption {
  final String value;
  final String label;

  const ChoiceOption(this.value, this.label);
}

class ChoiceSegmentedField extends StatelessWidget {
  final String title;
  final List<ChoiceOption> options;
  final String? selectedValue;
  final String? errorText;
  final ValueChanged<String> onSelected;

  const ChoiceSegmentedField({
    super.key,
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = options.length >= 3 ? 3 : 2;
        const spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: spacing,
              runSpacing: 8,
              children: options.map((option) {
                final selected = selectedValue == option.value;

                return SizedBox(
                  width: itemWidth,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onSelected(option.value),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFDCEBFF)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF0F6FFF)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            option.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected
                                  ? const Color(0xFF0F6FFF)
                                  : const Color(0xFF334155),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  errorText!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
