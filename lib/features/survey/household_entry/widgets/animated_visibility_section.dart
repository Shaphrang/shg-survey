import 'package:flutter/material.dart';

class AnimatedVisibilitySection extends StatelessWidget {
  final bool show;
  final Widget child;

  const AnimatedVisibilitySection({
    super.key,
    required this.show,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: show
          ? Padding(
              key: ValueKey<bool>(show),
              padding: const EdgeInsets.only(top: 16),
              child: child,
            )
          : const SizedBox.shrink(key: ValueKey<bool>(false)),
    );
  }
}
