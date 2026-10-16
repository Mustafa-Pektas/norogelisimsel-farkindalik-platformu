import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/scenarios_data.dart';
import 'ontology_detail_screen.dart';
import 'video_analysis_screen.dart';
import 'institutions_screen.dart';
import 'synthetic_video_studio_screen.dart';
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
  String? _studioOntologyCode;
  DateTime? _lastBackPressTime;

  String get _currentAgeGroup {
    if (_currentMonth < 18) return '12–18 Ay';
    if (_currentMonth < 24) return '18–24 Ay';
    return '24–36 Ay';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;

        // 1. Eğer başka bir sekmedeyse (Video Analiz veya Senaryo Stüdyosu), Ana Panel'e dön
        if (_currentTabIndex != 0) {
          setState(() {
            _currentTabIndex = 0;
          });
          return;
        }

        // 2. Eğer zaten Ana Panel'deyse, kazara çıkmayı önlemek için iki kez basma kuralı
        final now = DateTime.now();
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Uygulamadan çıkmak için tekrar geri tuşuna basın.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: const Color(0xFF0F172A),
            ),
          );
          return;
        }

        // 2 saniye içinde tekrar basıldıysa uygulamadan güvenle çık
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: _currentTabIndex == 0
            ? AppBar(
                title: const Text(
                  'Nörogelişimsel Farkındalık Platformu',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
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
            SyntheticVideoStudioScreen(
              initialOntologyCode: _studioOntologyCode,
              initialAgeMonths: _currentMonth.toInt(),
            ),
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
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  letterSpacing: -0.2,
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
                  icon: Icon(Icons.movie_creation_outlined),
                  selectedIcon: Icon(Icons.movie_creation_rounded, color: Color(0xFF0F172A)),
                  label: 'Senaryo\u00A0Stüdyosu',
                ),
              ],
            ),
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

          // PLATFORM MODLARI VE HIZLI ERİŞİM
          const Text(
            'Temel Çalışma Modları',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 10),

          _buildModeCard(
            title: '1. Video Analiz Modu',
            subtitle: 'Kamera veya video yükleyerek otomatik zaman damgalı kanıt analizi',
            icon: Icons.analytics_outlined,
            onTap: () => setState(() => _currentTabIndex = 1),
          ),
          const SizedBox(height: 8),

          _buildModeCard(
            title: '2. Senaryo & Simülasyon Stüdyosu',
            subtitle: 'Klinik davranış akışı, seans kurgulama ve sentetik video prompt stüdyosu',
            icon: Icons.movie_creation_outlined,
            onTap: () => setState(() => _currentTabIndex = 2),
          ),
          const SizedBox(height: 22),

          // 12 HEDEF DAVRANIŞ VE YAŞ NORMLARI
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '12 Hedef Davranış & Yaş Normları',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _currentAgeGroup,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          ...ScenariosRepository.allScenarios.map((scenario) {
            final expectedBehavior = scenario.ageBreakdowns[_currentAgeGroup] ?? scenario.antecedent;

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
                          'Gözlem Eşiği: ${scenario.riskThreshold}',
                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OntologyDetailScreen(
                          scenario: scenario,
                          currentAgeGroup: _currentAgeGroup,
                          currentAgeMonths: _currentMonth.toInt(),
                          onNavigateToTab: (targetTab, ontCode) {
                            setState(() {
                              _currentTabIndex = targetTab;
                              if (ontCode != null) {
                                _studioOntologyCode = ontCode;
                              }
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          }),
          const SizedBox(height: 16),

          // YETKİLİ SAĞLIK MERKEZLERİ BUTONU
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
              'Yetkili Sağlık Merkezleri ve Kurumlar',
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
