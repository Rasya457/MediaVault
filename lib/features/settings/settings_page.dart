import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'SETTINGS',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: MoriColors.label,
          letterSpacing: 3,
        ),
      ),
    );
  }
}
