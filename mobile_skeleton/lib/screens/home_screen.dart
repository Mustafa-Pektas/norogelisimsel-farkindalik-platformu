import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/behavior_cards.dart';
import 'ontology_detail_screen.dart';
import 'video_analysis_screen.dart';
import 'institutions_screen.dart';
import 'synthetic_video_studio_screen.dart';
import '../widgets/api_key_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  final Set<int> _visitedTabs = {0};
  DateTime? _lastBackPressTime;
  final _videoTabVisibility = ValueNotifier<bool>(false);

  void _selectTab(int index) {
    _videoTabVisibility.value = index == 1;
    setState(() {
      _currentTabIndex = index;
      _visitedTabs.add(index);
    });
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

        // 1. Eğer başka bir sekmedeyse, Ana Panel'e dön
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

        // 2 saniye içinde tekrar basıldıysa uygulamadan çık
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
          key: const ValueKey('home-tabs'),
          index: _currentTabIndex,
          children: [
            _buildDashboardTab(),
            _visitedTabs.contains(1)
                ? VideoAnalysisScreen(tabVisibility: _videoTabVisibility)
                : const SizedBox.shrink(),
            _visitedTabs.contains(2)
                ? const SyntheticVideoStudioScreen()
                : const SizedBox.shrink(),
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
            subtitle: 'Gözlem videosunu yükleyin ve otomatik analiz edin.',
            icon: Icons.analytics_outlined,
            onTap: () => _selectTab(1),
          ),
          const SizedBox(height: 8),

          _buildModeCard(
            title: 'Simülasyon ve Eğitim Stüdyosu',
            subtitle: 'Klinik senaryo ve sentetik video promptları üretin.',
            icon: Icons.movie_creation_outlined,
            onTap: () => _selectTab(2),
          ),
          const SizedBox(height: 22),

          // DAVRANIŞ KATALOĞU (D01–D10)
          const Text(
            'Davranış Kataloğu (D01–D10)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 12),

          ...BehaviorCards.all.map((card) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: ListTile(
              dense: true,
              key: ValueKey('behavior-card:${card.id}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  card.id,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB), fontSize: 12.5),
                ),
              ),
              title: Text(
                card.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
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
              'Kurum bilgileri',
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
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF0F172A), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.3),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}
