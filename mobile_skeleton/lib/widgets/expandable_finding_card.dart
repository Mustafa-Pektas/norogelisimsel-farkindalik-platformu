import 'package:flutter/material.dart';
import '../models/models.dart';

class ExpandableFindingCard extends StatefulWidget {
  final BehaviorFinding finding;
  final VoidCallback? onPlayEvidence;

  const ExpandableFindingCard({
    super.key,
    required this.finding,
    this.onPlayEvidence,
  });

  @override
  State<ExpandableFindingCard> createState() => _ExpandableFindingCardState();
}

class _ExpandableFindingCardState extends State<ExpandableFindingCard> {
  bool _isExpanded = false;

  Color get _badgeBgColor {
    switch (widget.finding.level) {
      case AwarenessLevel.green:
        return const Color(0xFFDCFCE7); // emerald-100
      case AwarenessLevel.yellow:
        return const Color(0xFFFEF3C7); // amber-100
      case AwarenessLevel.red:
        return const Color(0xFFFEE2E2); // red-100
      case AwarenessLevel.inconclusive:
        return const Color(0xFFF1F5F9); // slate-100
    }
  }

  Color get _badgeTextColor {
    switch (widget.finding.level) {
      case AwarenessLevel.green:
        return const Color(0xFF166534); // emerald-800
      case AwarenessLevel.yellow:
        return const Color(0xFF92400E); // amber-800
      case AwarenessLevel.red:
        return const Color(0xFF991B1B); // red-800
      case AwarenessLevel.inconclusive:
        return const Color(0xFF475569); // slate-600
    }
  }

  IconData get _iconData {
    final code = widget.finding.code;
    if (code == 'ONT-01') return Icons.hearing_rounded; // İsme tepki
    if (code == 'ONT-02' || code == 'ONT-03') return Icons.visibility_rounded; // Ortak dikkat / göz teması
    if (code == 'ONT-04' || code == 'ONT-05') return Icons.toys_rounded; // Oyuncak / repetitif
    if (code == 'ONT-06') return Icons.sentiment_satisfied_alt_rounded; // Gülümseme
    return Icons.psychology_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.finding;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isExpanded ? _badgeTextColor.withValues(alpha: 0.3) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // KAPALI HAL / BAŞLIK SATIRI (Tek dokunuşla açılır)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // İkon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_iconData, size: 20, color: const Color(0xFF334155)),
                  ),
                  const SizedBox(width: 12),

                  // Başlık, Kod ve Gecikme
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                f.code,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                            if (f.latencySec != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Text(
                                  '${f.latencySec} sn',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          f.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Kısa Durum Rozeti (Pill)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _badgeBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _badgeTextColor,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          f.level.shortTag,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _badgeTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF94A3B8),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // AÇILIR DETAY GÖVDESİ (Accordion Details)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Color(0xFFF1F5F9), height: 16),

                  // Açıklama Metni
                  Text(
                    f.explanation,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF334155),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Bilgi Şeridi ve Buton
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 15, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text(
                            'Zaman Aralığı: ${f.evidenceTimeframe}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),

                      if (widget.onPlayEvidence != null)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: widget.onPlayEvidence,
                          icon: const Icon(Icons.play_circle_outline_rounded, size: 14),
                          label: Text(
                            'Oynat (${f.evidenceTimeframe.split('–').first.trim()})',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
