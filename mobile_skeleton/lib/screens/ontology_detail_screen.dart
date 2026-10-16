import 'package:flutter/material.dart';
import '../models/scenarios_data.dart';
import 'synthetic_video_studio_screen.dart';

class OntologyDetailScreen extends StatelessWidget {
  final ScenarioModel scenario;
  final String currentAgeGroup;
  final int currentAgeMonths;
  final void Function(int targetTab, String? ontologyCode)? onNavigateToTab;

  const OntologyDetailScreen({
    super.key,
    required this.scenario,
    this.currentAgeGroup = '18–24 Ay',
    this.currentAgeMonths = 18,
    this.onNavigateToTab,
  });

  String _cleanInstruction(String text) {
    return text.replaceFirst(RegExp(r'^Nasıl Yapılır:\s*', caseSensitive: false), '').trim();
  }

  String _cleanCriteria(String code, String rawText) {
    const friendlyMap = {
      'ONT-01': 'Başın ses yönüne net şekilde dönmesi, yönelme hızı ve göz teması kurup kurmadığı.',
      'ONT-02': 'Parmağınızla gösterdiğiniz uzaktaki nesneye çocuğun doğrudan dönüp bakması.',
      'ONT-03': 'Çocuğun nesne ile ebeveyn arasında bakış aktarması (nesneye bakıp hemen ardından gülümseyerek ebeveyne bakması).',
      'ONT-04': 'İlgi duyduğu nesneyi işaret parmağını uzatarak göstermesi ve eş zamanlı ebeveynle göz teması kurması.',
      'ONT-05': 'Ulaşamadığı oyuncağı isterken ebeveynin yüzüne bakarak ses veya jestle talepte bulunması.',
      'ONT-06': 'Yetişkinin elini alet gibi kullanıp kullanmadığı veya göz temasından kaçınma durumu.',
      'ONT-07': 'Sıra alma oyununda (ce-e gibi) oyunun devamını merak ve tebessümle beklemesi.',
      'ONT-08': 'Beğendiği bir eşyayı ya da oyuncağı ebeveyne uzatarak göstermesi ve göz teması kurması.',
      'ONT-09': 'Şaşırtıcı veya komik bir anda yetişkine dönüp neşesini bakışla paylaşması.',
      'ONT-10': 'Basit bir sözel komut verildiğinde ("topu ver") doğru nesneye yönelip yerine getirmesi.',
      'ONT-11': 'El sallama veya bay-bay yaparken karşıdakinin yüzüne bakıp eşlik etmesi.',
      'ONT-12': 'Kendi yaşındaki çocuklara ilgi göstermesi, yanlarına yaklaşıp oyunlarına bakması.',
    };
    if (friendlyMap.containsKey(code)) {
      return friendlyMap[code]!;
    }
    return rawText.replaceFirst(RegExp(r'^MediaPipe[a-zA-Z\s]*:\s*', caseSensitive: false), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final expectedBehavior = scenario.ageBreakdowns[currentAgeGroup] ?? scenario.antecedent;
    final branches = scenario.getBranchesForAge(currentAgeGroup);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          scenario.code,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ÜST BAŞLIK VE ETİKET KARTI
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          scenario.code,
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          currentAgeGroup,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    scenario.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kategori: ${scenario.category}',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 1. KART: BU YAŞTA NE BEKLENİR?
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.verified_outlined, color: Color(0xFF10B981), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Bu Yaşta Ne Beklenir? ($currentAgeGroup)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    expectedBehavior,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF334155),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 2. KART: GÖZLEM EŞİĞİ VE OLASI TEPKİLER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Gözlem Eşiği (Şüpheli Durum)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Text(
                      scenario.riskThreshold,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (branches.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Olası Tepkiler ve Seviyeleri:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 8),
                    ...branches.map((b) {
                      Color badgeColor = const Color(0xFF10B981);
                      String levelText = 'Tipik';
                      if (b.level.toUpperCase() == 'SARI') {
                        badgeColor = const Color(0xFFF59E0B);
                        levelText = 'Gecikmeli';
                      } else if (b.level.toUpperCase() == 'KIRMIZI') {
                        badgeColor = const Color(0xFFEF4444);
                        levelText = 'Şüpheli / Risk';
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                levelText,
                                style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 10),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                b.details,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 3. KART: NASIL GÖZLEMLENİR? (UYGULAMA İPUÇLARI)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.touch_app_outlined, color: Color(0xFF0284C7), size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Nasıl Gözlemlenir?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _buildObservationTip(
                    number: '1',
                    title: 'Ortam ve Hazırlık',
                    detail: _cleanInstruction(scenario.instruction),
                  ),
                  const SizedBox(height: 10),
                  _buildObservationTip(
                    number: '2',
                    title: 'Uygulama Yönergesi',
                    detail: scenario.antecedent,
                  ),
                  const SizedBox(height: 10),
                  _buildObservationTip(
                    number: '3',
                    title: 'İzlenecek Temel Noktalar',
                    detail: _cleanCriteria(scenario.code, scenario.measurementCriteria),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 4. AKSİYON BUTONLARI
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  if (onNavigateToTab != null) {
                    onNavigateToTab!(2, scenario.code);
                    Navigator.pop(context);
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SyntheticVideoStudioScreen(
                          initialOntologyCode: scenario.code,
                          initialAgeMonths: currentAgeMonths,
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.movie_creation_outlined, size: 18),
                label: const Text(
                  'Bu Davranış İçin Senaryo Üret',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  if (onNavigateToTab != null) {
                    onNavigateToTab!(1, scenario.code);
                    Navigator.pop(context);
                  } else {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.analytics_outlined, size: 18),
                label: const Text(
                  'Videodan Analiz Et',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildObservationTip({
    required String number,
    required String title,
    required String detail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
