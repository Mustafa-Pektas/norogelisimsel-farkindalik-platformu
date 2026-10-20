import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/behavior_cards.dart';
import 'ontology_detail_screen.dart';
import 'video_analysis_screen.dart';
import 'institutions_screen.dart';
import 'synthetic_video_studio_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  DateTime? _lastBackPressTime;
  final _videoTabVisibility = ValueNotifier<bool>(false);

  void _selectTab(int index) {
    // Bildirim build'i beklemez; aynı karede ayrılıp dönme de duraklatır.
    _videoTabVisibility.value = index == 1;
    setState(() { _currentTabIndex = index; });
  }

  @override
  void dispose() {
    _videoTabVisibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;

        // 1. Eğer başka bir sekmedeyse (Video Analiz veya Senaryo Stüdyosu), Ana Panel'e dön
        if (_currentTabIndex != 0) {
          _selectTab(0);
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
              )
            : null,
        body: IndexedStack(
          index: _currentTabIndex,
          children: [
            _buildDashboardTab(),
            VideoAnalysisScreen(tabVisibility: _videoTabVisibility),
            const SyntheticVideoStudioScreen(),
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
              onDestinationSelected: _selectTab,
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
                  label: 'Video Analizi',
                ),
                NavigationDestination(
                  icon: Icon(Icons.movie_creation_outlined),
                  selectedIcon: Icon(Icons.movie_creation_rounded, color: Color(0xFF0F172A)),
                  label: 'Simülasyon ve Eğitim',
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
            title: 'Video Analizi',
            subtitle: 'Video seçip izleyin. Otomatik analiz bağlantısı henüz tamamlanmadı.',
            icon: Icons.analytics_outlined,
            onTap: () => _selectTab(1),
          ),
          const SizedBox(height: 8),

          _buildModeCard(
            title: 'Simülasyon ve Eğitim',
            subtitle: 'Hazır D01 örneğinin akışını inceleyin.',
            icon: Icons.movie_creation_outlined,
            onTap: () => _selectTab(2),
          ),
          const SizedBox(height: 22),

          const Text(
            'Davranışları tanıyın',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 6),
          const Text('Videolarda incelenen davranışlar hakkında bilgi edinin.'),
          const SizedBox(height: 12),
          ...BehaviorCards.all.map((card) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            color: Colors.white,
            child: ListTile(
              key: ValueKey('behavior-card:${card.id}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: Text(card.id, style: const TextStyle(fontWeight: FontWeight.bold)),
              title: Text(card.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(card.summary),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => OntologyDetailScreen(card: card),
              )),
            ),
          )),
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
