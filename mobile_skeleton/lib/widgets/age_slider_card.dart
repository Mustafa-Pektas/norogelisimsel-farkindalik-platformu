import 'package:flutter/material.dart';

class AgeSliderCard extends StatelessWidget {
  final double currentMonth;
  final ValueChanged<double> onChanged;
  final String title;

  const AgeSliderCard({
    super.key,
    required this.currentMonth,
    required this.onChanged,
    this.title = 'Gelişimsel Yaş Ayarı',
  });

  @override
  Widget build(BuildContext context) {
    final monthInt = currentMonth.round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ÜST BAŞLIK & AY ROZETİ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.child_care_rounded, size: 20, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$monthInt Aylık',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // SÜRÜKLEME ÇUBUĞU (SLIDER)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF0F172A),
              inactiveTrackColor: const Color(0xFFE2E8F0),
              thumbColor: const Color(0xFF0F172A),
              overlayColor: const Color(0xFF0F172A).withValues(alpha: 0.12),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: currentMonth,
              min: 12,
              max: 36,
              divisions: 24,
              label: '$monthInt Ay',
              onChanged: onChanged,
            ),
          ),

          const SizedBox(height: 6),

          // SENKRONİZE 3 YAŞ GRUBU HAPI (HİBRİT MODEL)
          Row(
            children: [
              _buildGroupChip(
                label: '12–18 Ay',
                isActive: currentMonth < 18,
                onTap: () => onChanged(15.0),
              ),
              const SizedBox(width: 8),
              _buildGroupChip(
                label: '18–24 Ay',
                isActive: currentMonth >= 18 && currentMonth < 24,
                onTap: () => onChanged(20.0),
              ),
              const SizedBox(width: 8),
              _buildGroupChip(
                label: '24–36 Ay',
                isActive: currentMonth >= 24,
                onTap: () => onChanged(28.0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: isActive ? Colors.white : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}
