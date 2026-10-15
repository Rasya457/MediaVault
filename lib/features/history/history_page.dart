import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'HISTORY',
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