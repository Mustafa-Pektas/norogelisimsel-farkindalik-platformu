import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/scenarios_data.dart';
import '../services/llm_rag_service.dart';
import '../widgets/scenario_picker_sheet.dart';
import 'synthetic_video_studio_screen.dart';

class SimulationModeScreen extends StatefulWidget {
  const SimulationModeScreen({super.key});

  @override
  State<SimulationModeScreen> createState() => _SimulationModeScreenState();
}

class _SimulationModeScreenState extends State<SimulationModeScreen> {
  int _selectedScenarioIndex = 0;
  int _selectedFsmAgeIndex = 0;
  ScenarioModel? _activeCustomScenario;
  final List<String> _fsmAgeGroups = ['12–18 Ay', '18–24 Ay', '24–36 Ay'];

  late final TextEditingController _contextController;
  late final TextEditingController _itemsController;
  bool _isGenerating = false;
  String _generatingStep = '';

  @override
  void initState() {
    super.initState();
    _contextController = TextEditingController(text: 'Salonda halı üzerinde serbest oynarken');
    _itemsController = TextEditingController(text: 'renkli pelüş ayı ve bloklar');
  }

  @override
  void dispose() {
    _contextController.dispose();
    _itemsController.dispose();
    super.dispose();
  }

  // EASTER EGG (GELİŞTİRİCİ / ARAŞTIRMACI MODU)
  int _easterEggTapCount = 0;
  DateTime? _lastEasterEggTap;
  bool _isResearcherMode = false;

  void _handleEasterEggTap() {
    final now = DateTime.now();
    if (_lastEasterEggTap == null || now.difference(_lastEasterEggTap!) > const Duration(seconds: 2)) {
      _easterEggTapCount = 1;
    } else {
      _easterEggTapCount++;
    }
    _lastEasterEggTap = now;

    if (_easterEggTapCount >= 5) {
      _easterEggTapCount = 0;
      HapticFeedback.heavyImpact();
      setState(() {
        _isResearcherMode = !_isResearcherMode;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                _isResearcherMode ? Icons.lock_open_rounded : Icons.lock_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isResearcherMode
                      ? 'Araştırmacı & Model Doğrulama Modu Açıldı (Ground-Truth & Prompt Stüdyosu Aktif).'
                      : 'Standart Kullanıcı Moduna Dönüldü.',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: _isResearcherMode ? const Color(0xFF0F172A) : const Color(0xFF475569),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
    } else if (_easterEggTapCount >= 2) {
      HapticFeedback.lightImpact();
    }
  }


  @override
  Widget build(BuildContext context) {
    final scenarios = ScenariosRepository.allScenarios;
    final currentScenario = _activeCustomScenario ?? scenarios[_selectedScenarioIndex];
    final selectedAge = _fsmAgeGroups[_selectedFsmAgeIndex];
    final branches = currentScenario.getBranchesForAge(selectedAge);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleEasterEggTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Senaryo & Simülasyon',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
              ),
              if (_isResearcherMode) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'MÜHENDİS',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Gemini API Anahtarı',
            icon: const Icon(Icons.key_outlined, size: 20),
            onPressed: _showApiKeyDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. KART: SENARYO VE ÇEKİM ÖZELLEŞTİRME
            Container(
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. SENARYO SEÇİCİ (MODERN KLİNİK KART)
                  InkWell(
                    onTap: () {
                      ScenarioPickerSheet.show(
                        context,
                        selectedIndex: _selectedScenarioIndex,
                        onSelected: (newIdx) {
                          setState(() {
                            _activeCustomScenario = null;
                            _selectedScenarioIndex = newIdx;
                          });
                        },
                      );
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _getScenarioIcon(currentScenario.code),
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _cleanScenarioTitle(currentScenario.title),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${currentScenario.code} • ${_selectedScenarioIndex + 1}/${scenarios.length} Senaryo',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Değiştir',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                SizedBox(width: 3),
                                Icon(
                                  Icons.unfold_more_rounded,
                                  size: 15,
                                  color: Color(0xFF64748B),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ANA YAŞ SEÇİCİ (MASTER AGE SELECTOR)
                  const Row(
                    children: [
                      Icon(Icons.child_care_rounded, size: 18, color: Color(0xFF0F172A)),
                      SizedBox(width: 6),
                      Text(
                        'Çocuğun Yaş Grubu',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: List.generate(_fsmAgeGroups.length, (idx) {
                        final ageLabel = _fsmAgeGroups[idx];
                        final isSelected = _selectedFsmAgeIndex == idx;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedFsmAgeIndex = idx;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: isSelected
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2))]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                ageLabel,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? Colors.white : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // EV ORTAMI VE OYUNCAKLAR (YAPAY ZEKA İLE UYARLAMA ALANI - VARSAYILAN OLARAK KAPALI)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Material(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          initiallyExpanded: false,
                          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        title: const Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 16, color: Color(0xFF0F172A)),
                            SizedBox(width: 8),
                            Text(
                              'Klinik Ortam & Materyal Uyarlaması',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                        subtitle: const Text(
                          'Gözlem protokolünü klinik ortama ve kullanılan materyallere göre uyarlayın',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        children: [
                          const SizedBox(height: 8),
                          // Hızlı Ortam Çipleri
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildPresetChip('🏥 Gözlem Masası', 'Klinik odasında çocuk değerlendirme masasında', 'çıngırak ve ahşap bloklar'),
                                _buildPresetChip('🛋️ Gözlem Halısı', 'Klinik değerlendirme odasında oyun halısı üzerinde serbest oynarken', 'renkli pelüş ayı ve bloklar'),
                                _buildPresetChip('📦 Kilitli Kutu', 'Klinik odasında kilitli şeffaf kutuyu açmaya çalışırken', 'kilitli şeffaf kutu'),
                                _buildPresetChip('🪑 Alçak Masa', 'Gelişimsel değerlendirme masasında hekim karşısında', 'renkli halkalar ve bultak'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _contextController,
                            enabled: !_isGenerating,
                            style: const TextStyle(fontSize: 12.5),
                            decoration: InputDecoration(
                              labelText: 'Ortam / Klinik Bağlam',
                              hintText: 'Örn: Klinik değerlendirme odasında halı üzerinde',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _itemsController,
                            enabled: !_isGenerating,
                            style: const TextStyle(fontSize: 12.5),
                            decoration: InputDecoration(
                              labelText: 'Kullanılacak Materyal veya Oyuncaklar',
                              hintText: 'Örn: renkli ahşap bloklar ve çıngırak',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_isGenerating) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _generatingStep,
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _isGenerating ? null : _generateCustomScenario,
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: Text(
                                _isGenerating ? 'Senaryo Uyarlanıyor...' : 'Klinik Ortama Göre Uyarlayın',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 2. KART: SENARYO ÇEKİM REHBERİ (3 ADIM)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Senaryo ${_selectedScenarioIndex + 1}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Text(
                          currentScenario.code,
                          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _cleanScenarioTitle(currentScenario.title),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const Divider(height: 22, color: Color(0xFFE2E8F0)),

                  // Adım 1: Ne Yapacaksınız?
                  _buildStepGuideRow(
                    stepNumber: '1',
                    icon: Icons.record_voice_over_outlined,
                    title: 'Ne Yapacaksınız?',
                    description: currentScenario.antecedent,
                  ),
                  const SizedBox(height: 10),

                  // Adım 2: Kamera & Ortam Düzeni
                  _buildStepGuideRow(
                    stepNumber: '2',
                    icon: Icons.videocam_outlined,
                    title: 'Kamera & Ortam Düzeni',
                    description: _cleanInstruction(currentScenario.instruction),
                  ),
                  const SizedBox(height: 10),

                  // Adım 3: Kamerada İzlenecek Tepki
                  _buildStepGuideRow(
                    stepNumber: '3',
                    icon: Icons.visibility_outlined,
                    title: 'Kamerada İzlenecek Tepki',
                    description: _cleanMeasurementCriteria(currentScenario.measurementCriteria),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 3. KART: BU YAŞTA BEKLENEN DAVRANIŞ & RİSK (SEÇİLİ YAŞA ÖZEL TEK BİLGİ)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_outlined, color: Color(0xFF0F172A), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '$selectedAge İçin Beklenen Davranış',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      _cleanAgeBreakdown(currentScenario.ageBreakdowns[selectedAge] ?? currentScenario.antecedent),
                      style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF334155)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFF0F172A), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dikkat Edilmesi Gereken Durum: ${currentScenario.riskThreshold}',
                            style: const TextStyle(color: Color(0xFF334155), fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 4. KART: OLASI ÇOCUK TEPKİLERİ (FSM STATE TREE - SEÇİLİ YAŞ İÇİN 3 DAL)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Olası Çocuk Tepkileri (Ne Görebilirsiniz?)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: Color(0xFF0F172A)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    selectedAge,
                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            ...List.generate(branches.length, (bIdx) {
              final b = branches[bIdx];
              final cleanTitle = b.title.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();

              Color badgeColor = const Color(0xFF10B981);
              String badgeLabel = 'Tipik';
              if (b.level.toUpperCase() == 'SARI') {
                badgeColor = const Color(0xFFF59E0B);
                badgeLabel = 'Takip';
              } else if (b.level.toUpperCase() == 'KIRMIZI') {
                badgeColor = const Color(0xFFEF4444);
                badgeLabel = 'Risk';
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // BAŞLIK VE TİPİK / TAKİP / RİSK ROZETİ
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cleanTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: Color(0xFF0F172A),
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _cleanBranchDetails(b.details),
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.35),
                    ),
                    const SizedBox(height: 10),

                    // HER KARTTA GÖRÜNEN ANLAMI (KLİNİK ÇIKARIM)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.psychology_outlined, size: 15, color: badgeColor),
                              const SizedBox(width: 6),
                              const Text(
                                'Bu Tepki Ne Anlama Geliyor?',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _cleanClinicalOutcome(b.clinicalOutcome),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF334155),
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 14),

            // KULLANICI GÖRÜNÜMÜ VEYA GİZLİ MÜHENDİSLİK / ARAŞTIRMACI MODU KARTLARI
            if (!_isResearcherMode) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.info_outline_rounded, color: Color(0xFF475569), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Bu gözlem adımlarını ev ortamında uyguladıktan sonra Video Analiz sekmesinden videonuzu yükleyerek yapay zeka kanıtlarını inceleyebilirsiniz.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              // GİZLİ ARAŞTIRMACI MODU AKTİF (5 TIK İLE AÇILDI)
              _buildResearcherPromptCard(currentScenario, selectedAge),
              _buildResearcherValidationCard(currentScenario, selectedAge),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildResearcherPromptCard(ScenarioModel currentScenario, String selectedAge) {
    final promptText =
        'A photorealistic eye-level 4k video, 35mm lens, warm natural lighting. '
        'A $selectedAge toddler in a living room, ${_contextController.text.trim()}, '
        'with ${_itemsController.text.trim()}. An adult caregiver steps in and executes '
        '${currentScenario.title} protocol. The child demonstrates subtle developmental micro-behaviors. '
        'Cinematic consistency, high fidelity, 24fps.';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.movie_filter_rounded, color: Color(0xFF10B981), size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Sentetik Video Prompt Fabrikası',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'SORA / RUNWAY GEN-3',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Text(
              promptText,
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: promptText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('📋 Sentetik video promptu panoya kopyalandı!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white),
                  label: const Text('Promptu Kopyala', style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF475569)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SyntheticVideoStudioScreen()),
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFF0F172A)),
                  label: const Text(
                    'Tam Stüdyo',
                    style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResearcherValidationCard(ScenarioModel currentScenario, String selectedAge) {
    return Container(
      key: const ValueKey('unmeasured-validation'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Model Doğrulama & Başarım Testi',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
          const SizedBox(height: 12),
          Text('Senaryo taslağı: ${currentScenario.title} · $selectedAge'),
          const Text('Ölçülmedi / doğrulama hizmeti bağlı değil.'),
          const SizedBox(height: 8),
          const Text('Gerçek ölçüm olmadığı için güven, zamanlama sapması veya doğrulandı sonucu gösterilmez.'),
          const SizedBox(height: 12),
          const ElevatedButton(onPressed: null, child: Text('Doğrulama hizmeti bağlı değil')),
        ],
      ),
    );
  }
  Future<void> _generateCustomScenario() async {
    final scenarios = ScenariosRepository.allScenarios;
    final currentScenario = scenarios[_selectedScenarioIndex];
    final ageMonths = _selectedFsmAgeIndex == 0 ? 15 : (_selectedFsmAgeIndex == 1 ? 20 : 30);

    var behaviorCode = currentScenario.code;
    if (behaviorCode.startsWith('AI-')) {
      behaviorCode = behaviorCode.replaceFirst('AI-', '');
    }

    setState(() {
      _isGenerating = true;
      _generatingStep = 'RAG başlatılıyor...';
    });

    try {
      final newScenario = await LlmRagService.generateScenario(
        ageMonths: ageMonths,
        behaviorCode: behaviorCode,
        contextEnvironment: _contextController.text,
        specificItems: _itemsController.text,
        onProgress: (msg) {
          if (mounted) {
            setState(() => _generatingStep = msg);
          }
        },
      );

      if (mounted) {
        setState(() {
          _activeCustomScenario = newScenario;
          _isGenerating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F172A),
            content: Text('"${_cleanScenarioTitle(newScenario.title)}" senaryosu ortamınıza göre uyarlandı.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('Uyarlama hatası: $e'),
          ),
        );
      }
    }
  }

  Widget _buildStepGuideRow({
    required String stepNumber,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Adım $stepNumber',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getScenarioIcon(String code) {
    switch (code) {
      case 'ONT-01':
        return Icons.hearing_rounded; // İsme Tepki
      case 'ONT-02':
        return Icons.visibility_rounded; // Ortak Dikkat
      case 'ONT-03':
        return Icons.remove_red_eye_rounded; // Ortak Dikkat Başlatma
      case 'ONT-04':
        return Icons.touch_app_rounded; // Deklaratif İşaret Etme
      case 'ONT-05':
        return Icons.pan_tool_rounded; // İstek Bildirme
      case 'ONT-06':
        return Icons.front_hand_rounded; // El Aleti Kullanma
      case 'ONT-07':
        return Icons.sentiment_very_satisfied_rounded; // Ce-e Oyunu
      case 'ONT-08':
        return Icons.card_giftcard_rounded; // Nesne Getirme
      case 'ONT-09':
        return Icons.favorite_rounded; // Duygulanım Paylaşımı
      case 'ONT-10':
        return Icons.checklist_rounded; // Yönerge Takibi
      case 'ONT-11':
        return Icons.waving_hand_rounded; // İletişimsel Jestler
      case 'ONT-12':
        return Icons.diversity_3_rounded; // Akran İlgisi
      default:
        return Icons.psychology_rounded;
    }
  }

  Widget _buildPresetChip(String label, String contextText, String itemsText) {
    final isSelected = _contextController.text == contextText;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
        backgroundColor: isSelected ? const Color(0xFF0F172A) : Colors.white,
        side: BorderSide(color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1)),
        onPressed: () {
          setState(() {
            _contextController.text = contextText;
            _itemsController.text = itemsText;
          });
        },
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
    );
  }

  String _cleanScenarioTitle(String title) {
    return title.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  }

  String _cleanInstruction(String text) {
    return text.replaceFirst(RegExp(r'^Nasıl Yapılır:\s*', caseSensitive: false), '').trim();
  }

  String _cleanMeasurementCriteria(String text) {
    var cleaned = text.replaceFirst(RegExp(r'^MediaPipe\s*(Face Mesh|Pose)?:\s*', caseSensitive: false), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\(?Yaw\s*[≥<~]\s*[^)]*\)?', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\(?AU\d+[^)]*\)?', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\(?Yüzü en az \d+° dönük\)?', caseSensitive: false), '');
    cleaned = cleaned.replaceAll('açısal hız ve ', '');
    cleaned = cleaned.replaceAll('açısal hız, ', '');
    cleaned = cleaned.replaceAll('açısal hız', '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isNotEmpty) {
      cleaned = cleaned[0].toUpperCase() + cleaned.substring(1);
    }
    return cleaned;
  }

  String _cleanAgeBreakdown(String text) {
    var cleaned = text.replaceAll(RegExp(r'\s*\(%[0-9–\-]+\s*başarı\s*oranı\)', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\(%[0-9–\-]+\)', caseSensitive: false), '');
    return cleaned.trim();
  }

  String _cleanBranchDetails(String text) {
    var cleaned = text.replaceAll(RegExp(r'\(?Yaw\s*[≥<~]\s*[^)]*\)?', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\(?Yüzü en az \d+° dönük\)?', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  String _cleanClinicalOutcome(String outcome) {
    var clean = outcome.replaceFirst(RegExp(r'^(M-CHAT-R|ADOS-2|Vineland|CARS|ASQ-3):\s*', caseSensitive: false), '').trim();
    return clean;
  }


  void _showApiKeyDialog() async {
    final currentKey = await LlmRagService.getApiKey();
    final controller = TextEditingController(text: currentKey ?? '');
    bool obscure = true;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            final hasKey = currentKey != null && currentKey.isNotEmpty;
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.key, color: Color(0xFF4F46E5), size: 22),
                  SizedBox(width: 8),
                  Text('Gemini API Anahtarı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kendi Google Gemini API anahtarınızı girerek senaryoları doğrudan gerçek LLM ile üretebilirsiniz.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'API Anahtarı (AIzaSy...)',
                      hintText: 'AIzaSy...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Anahtar yalnızca cihazınızda saklanır. Anahtar girmeden de yerel klinik RAG motoruyla senaryo üretebilirsiniz.',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600, height: 1.3),
                  ),
                ],
              ),
              actions: [
                if (hasKey)
                  TextButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await LlmRagService.clearApiKey();
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('API anahtarı temizlendi. Yerel RAG motoru aktif.')),
                      );
                    },
                    child: const Text('Temizle', style: TextStyle(color: Colors.red)),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final keyToSave = controller.text.trim();
                    if (keyToSave.isNotEmpty) {
                      await LlmRagService.saveApiKey(keyToSave);
                    } else {
                      await LlmRagService.clearApiKey();
                    }
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(keyToSave.isNotEmpty
                            ? 'Gemini API anahtarı kaydedildi. Model aktif.'
                            : 'API anahtarı boş bırakıldı, yerel RAG motoru aktif.'),
                      ),
                    );
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
