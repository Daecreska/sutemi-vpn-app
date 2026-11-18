import 'package:flutter/material.dart';

import '../../core/geo/country_detector.dart';
import '../theme/sutemi_theme.dart';

class CountryBadge extends StatelessWidget {
  final String code;
  final bool verified;
  final bool compact;

  const CountryBadge({
    super.key,
    required this.code,
    this.verified = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final safeCode = code.isEmpty ? 'WW' : code.toUpperCase();
    final flag = CountryDetector.flagEmoji(safeCode);
    return Container(
      width: compact ? 38 : 44,
      height: compact ? 28 : 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        color: Colors.white.withValues(alpha: 0.10),
        border: Border.all(
          color: verified && safeCode != 'WW'
              ? SutemiColors.mint.withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.24),
          width: verified ? 1.4 : 1.0,
        ),
      ),
      child: Text(
        safeCode == 'WW' ? 'WW' : '$flag $safeCode',
        style: TextStyle(
          fontSize: compact ? 9.5 : 10.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        overflow: TextOverflow.clip,
      ),
    );
  }
}
