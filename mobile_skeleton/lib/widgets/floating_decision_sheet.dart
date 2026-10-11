import 'package:flutter/material.dart';
import '../models/scenarios_data.dart';

class FloatingDecisionCard extends StatelessWidget {
  final List<ScenarioBranchModel> branches;
  final ValueChanged<ScenarioBranchModel> onSelectBranch;

  const FloatingDecisionCard({
    super.key,
    required this.branches,
    required this.onSelectBranch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SADELEŞTİRİLMİŞ BAŞLIK
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.touch_app_rounded, color: Color(0xFF4F46E5), size: 18),
              ),
              const SizedBox(width: 8),
              const Text(
                'Davranış Tepkisini Seçin',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // YAN YANA 3'LÜ HAP BUTON SATIRI (KESİNTİSİZ VE FERAH)
          Row(
            children: branches.map((branch) {
              Color btnColor = const Color(0xFF10B981); // Emerald
              Color btnBg = const Color(0xFFECFDF5);
              IconData iconData = Icons.check_circle_outline_rounded;
              String shortTitle = 'Tipik';

              if (branch.level == 'SARI') {
                btnColor = const Color(0xFFD97706); // Amber
                btnBg = const Color(0xFFFFFBEB);
                iconData = Icons.warning_amber_rounded;
                shortTitle = 'Gecikmeli';
              } else if (branch.level == 'KIRMIZI') {
                btnColor = const Color(0xFFDC2626); // Red
                btnBg = const Color(0xFFFEF2F2);
                iconData = Icons.cancel_outlined;
                shortTitle = 'Tepkisiz';
              }

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Material(
                    color: btnBg,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onSelectBranch(branch),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: btnColor.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(iconData, color: btnColor, size: 22),
                            const SizedBox(height: 5),
                            Text(
                              '${branch.level}\n($shortTitle)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: btnColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
