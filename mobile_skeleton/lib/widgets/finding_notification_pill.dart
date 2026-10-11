import 'package:flutter/material.dart';
import '../models/models.dart';

class FindingNotificationPill extends StatelessWidget {
  final BehaviorFinding? finding;
  final bool isVisible;

  const FindingNotificationPill({
    super.key,
    required this.finding,
    required this.isVisible,
  });

  @override
  Widget build(BuildContext context) {
    if (finding == null) return const SizedBox.shrink();

    final Color badgeColor;
    final IconData badgeIcon;
    final String statusText;

    switch (finding!.level) {
      case AwarenessLevel.green:
        badgeColor = const Color(0xFF10B981); // Emerald
        badgeIcon = Icons.check_circle_rounded;
        statusText = 'Tipik';
        break;
      case AwarenessLevel.yellow:
        badgeColor = const Color(0xFFF59E0B); // Amber
        badgeIcon = Icons.warning_amber_rounded;
        statusText = 'Takip';
        break;
      case AwarenessLevel.red:
        badgeColor = const Color(0xFFEF4444); // Red
        badgeIcon = Icons.priority_high_rounded;
        statusText = 'Risk';
        break;
      case AwarenessLevel.inconclusive:
        badgeColor = const Color(0xFF94A3B8); // Slate
        badgeIcon = Icons.help_outline_rounded;
        statusText = 'Belirsiz';
        break;
    }

    return IgnorePointer(
      child: AnimatedSlide(
        offset: isVisible ? Offset.zero : const Offset(0, 0.25),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOut,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xF20F172A), // Slate 900 (%95)
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: badgeColor.withValues(alpha: 0.5), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: badgeColor.withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(badgeIcon, color: badgeColor, size: 13),
                ),
                const SizedBox(width: 7),
                Text(
                  finding!.name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
