import 'package:flutter/material.dart';
import '../models/scenarios_data.dart';
import 'simulation_mode_screen.dart';
import 'video_analysis_screen.dart';
import 'institutions_screen.dart';
import 'interactive_player_screen.dart';
import 'veo_studio_screen.dart';
import '../widgets/api_key_dialog.dart';
import '../widgets/age_slider_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  double _currentMonth = 18.0;

  String get _currentAgeGroup {
    if (_currentMonth < 18) return '12–18 Ay';
    if (_currentMonth < 24) return '18–24 Ay';
    return '24–36 Ay';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: (_currentTabIndex == 0 || _currentTabIndex == 4)
          ? AppBar(
              title: Text(
                _currentTabIndex == 0
                    ? 'Nörogelişimsel Farkındalık Platformu'
                    : 'Gelişim Rehberi & Klinik Normlar',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
              ),
              elevation: 0,
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.key_outlined, size: 20),
                  tooltip: 'Gemini API Anahtarı',
                  onPressed: () => ApiKeyDialog.show(context),
                ),
              ],
            )
          : null,
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildDashboardTab(),
          const VideoAnalysisScreen(),
          const InteractivePlayerScreen(),
          const SimulationModeScreen(),
          _buildGuidanceTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final isSelected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                letterSpacing: -0.3,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: _currentTabIndex,
            onDestinationSelected: (idx) {
              setState(() {
                _currentTabIndex = idx;
              });
            },
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFF0F172A).withValues(alpha: 0.08),
            elevation: 0,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded, color: Color(0xFF0F172A)),
                label: 'Ana\u00A0Panel',
              ),
              NavigationDestination(
                icon: Icon(Icons.analytics_outlined),
                selectedIcon: Icon(Icons.analytics_rounded, color: Color(0xFF0F172A)),
                label: 'Video\u00A0Analiz',
              ),
              NavigationDestination(
                icon: Icon(Icons.smart_display_outlined),
                selectedIcon: Icon(Icons.smart_display_rounded, color: Color(0xFF0F172A)),
                label: 'Simülatör',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_tree_outlined),
                selectedIcon: Icon(Icons.account_tree_rounded, color: Color(0xFF0F172A)),
                label: 'Eğitim\u00A0Modu',
              ),
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book_rounded, color: Color(0xFF0F172A)),
                label: 'Gelişim\u00A0Rehberi',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 1. SEKME: ANA PANEL (DASHBOARD)
  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SÜRÜKLEMELİ YAŞ AYARI KARTI
          AgeSliderCard(
            currentMonth: _currentMonth,
            onChanged: (val) {
              setState(() {
                _currentMonth = val;
              });
            },
          ),
          const SizedBox(height: 16),

          // KLİNİK SORUMLULUK REDDİ
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: Color(0xFF92400E), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bu platform tıbbi tanı koymaz; gelişimsel takip ve bilgilendirme amaçlıdır.',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade900, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ÇALIŞMA MODLARI BAŞLIĞI
          const Text(
            'Çalışma Modları',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 10),

          _buildModeCard(
            title: '1. Video Analiz Modu',
            subtitle: 'Kamera veya video yükleyerek otomatik davranış analizi',
            icon: Icons.analytics_outlined,
            onTap: () => setState(() => _currentTabIndex = 1),
          ),
          const SizedBox(height: 8),

          _buildModeCard(
            title: '2. İnteraktif Video Simülatörü',
            subtitle: '12 ontoloji ve dallanan tepki videolarıyla etkileşimli oynatıcı',
            icon: Icons.smart_display_outlined,
            onTap: () => setState(() => _currentTabIndex = 2),
          ),
          const SizedBox(height: 8),

          _buildModeCard(
            title: '3. Simülasyon ve Eğitim Modu',
            subtitle: 'Klinik davranış akış şemaları ve kural tabanlı karar ağacı',
            icon: Icons.account_tree_outlined,
            onTap: () => setState(() => _currentTabIndex = 3),
          ),
          const SizedBox(height: 8),

          _buildModeCard(
            title: '4. Sentetik Video Stüdyosu',
            subtitle: 'Klinik video üretim promptları ve seans zinciri',
            icon: Icons.movie_creation_outlined,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const VeoStudioScreen()),
              );
            },
          ),
          const SizedBox(height: 8),

          _buildModeCard(
            title: '5. Gelişim Rehberi & Klinik Normlar',
            subtitle: '12 hedef davranış göstergesi, yaş normları ve sağlık merkezleri',
            icon: Icons.menu_book_outlined,
            onTap: () => setState(() => _currentTabIndex = 4),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 4. SEKME: GELİŞİM REHBERİ VE VEO
  Widget _buildGuidanceTab() {
    final currentAge = _currentAgeGroup;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // BAŞLIK VE HIZLI GEÇİŞ BUTONU
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '12 Hedef Davranış Göstergesi',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  currentAge,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // YAŞ SEÇİCİ
          AgeSliderCard(
            currentMonth: _currentMonth,
            onChanged: (val) {
              setState(() {
                _currentMonth = val;
              });
            },
          ),
          const SizedBox(height: 16),

          // SENARYO KARTLARI (Design System)
          ...ScenariosRepository.allScenarios.map((scenario) {
            final expectedBehavior = scenario.ageBreakdowns[currentAge] ?? scenario.antecedent;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Text(
                    scenario.code,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                ),
                title: Text(
                  scenario.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Beklenen: $expectedBehavior',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.3),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Risk Eşiği: ${scenario.riskThreshold}',
                        style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => InteractivePlayerScreen(
                        initialScenario: scenario,
                        initialAgeGroup: currentAge,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          }),
          const SizedBox(height: 16),

          // SAĞLIK MERKEZLERİ
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InstitutionsScreen()),
              );
            },
            icon: const Icon(Icons.local_hospital_outlined, color: Color(0xFF0F172A)),
            label: const Text(
              'Yetkili Sağlık Merkezleri',
              style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }


  Widget _buildModeCard({
    required String title,
    String? subtitle,
    required IconData icon,
    String? badgeText,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Icon(icon, color: const Color(0xFF0F172A), size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (badgeText != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}
