import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/veo_prompt_service.dart';
import '../widgets/api_key_dialog.dart';

class VeoStudioScreen extends StatefulWidget {
  const VeoStudioScreen({super.key});

  @override
  State<VeoStudioScreen> createState() => _VeoStudioScreenState();
}

class _VeoStudioScreenState extends State<VeoStudioScreen> {
  int _selectedAge = 18;
  int _selectedDuration = 8;
  String _selectedRisk = 'atipik';
  VeoPromptSession? _session;
  bool _isGenerating = false;
  @override
  void initState() {
    super.initState();
    _generateSession();
  }

  String _getAgeGroupLabel(int months) {
    if (months < 18) return '12–18 Ay';
    if (months < 24) return '18–24 Ay';
    return '24–36 Ay';
  }

  void _generateSession() {
    setState(() => _isGenerating = true);
    Future.delayed(const Duration(milliseconds: 300), () {
      final s = VeoPromptService.generateSession(
        ageMonths: _selectedAge,
        blockDurationSec: _selectedDuration,
        riskProfile: _selectedRisk,
      );
      if (mounted) {
        setState(() {
          _session = s;
          _isGenerating = false;
        });
      }
    });
  }

  void _copyToClipboard(String text, String successMsg) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(successMsg, style: const TextStyle(fontSize: 13))),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Sentetik Video Stüdyosu',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined, size: 20),
            tooltip: 'Gemini API Anahtarı',
            onPressed: () => ApiKeyDialog.show(context),
          ),
          if (_session != null) ...[
            IconButton(
              icon: const Icon(Icons.copy_all_outlined, size: 20),
              tooltip: 'Tüm Senaryoyu Kopyala',
              onPressed: () {
                _copyToClipboard(
                  _session!.exportFullMarkdown(),
                  'Senaryo akışı Markdown olarak kopyalandı!',
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.data_object_outlined, size: 20),
              tooltip: 'Senaryo JSON Kopyala',
              onPressed: () {
                _copyToClipboard(
                  _session!.exportGroundTruthJson(),
                  'Senaryo JSON formatında kopyalandı!',
                );
              },
            ),
          ],
        ],
      ),
      body: _isGenerating
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF0F172A)),
                  SizedBox(height: 16),
                  Text(
                    'Klinik Prompt Zinciri Oluşturuluyor...',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // AYARLAR KARTI
                  _buildConfigCard(),
                  const SizedBox(height: 14),

                  if (_session != null) ...[
                    // ADIMLAR LİSTESİ
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Seans Akışı (${_session!.steps.length} Klip)',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          '${_session!.totalDurationSec} sn',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _session!.steps.length,
                      itemBuilder: (context, index) {
                        return _buildStepCard(_session!.steps[index]);
                      },
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildConfigCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // YAŞ SEÇİCİ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Çocuğun Yaşı', style: TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_selectedAge Ay (${_getAgeGroupLabel(_selectedAge)})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
              ),
            ],
          ),
          Slider(
            value: _selectedAge.toDouble(),
            min: 12,
            max: 36,
            divisions: 24,
            activeColor: const Color(0xFF0F172A),
            inactiveColor: const Color(0xFFE2E8F0),
            label: '$_selectedAge Ay',
            onChanged: (val) {
              setState(() => _selectedAge = val.round());
            },
            onChangeEnd: (val) {
              _generateSession();
            },
          ),
          const SizedBox(height: 8),

          // KLİP SÜRESİ
          const Text('Klip Süresi', style: TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(
            children: [5, 6, 8, 10].map((sec) {
              final sel = _selectedDuration == sec;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('$sec sn'),
                  selected: sel,
                  selectedColor: const Color(0xFF0F172A),
                  backgroundColor: const Color(0xFFF1F5F9),
                  side: BorderSide(color: sel ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
                  labelStyle: TextStyle(
                    color: sel ? Colors.white : const Color(0xFF334155),
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    fontSize: 11.5,
                  ),
                  onSelected: (val) {
                    if (val) {
                      setState(() => _selectedDuration = sec);
                      _generateSession();
                    }
                  },
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // PROFİL
          const Text('Klinik Profil', style: TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              _buildRiskChip('atipik', 'Atipik (Kırmızı)', Colors.red.shade700),
              _buildRiskChip('karma', 'Karma (Sarı)', Colors.amber.shade800),
              _buildRiskChip('tipik', 'Tipik (Yeşil)', Colors.green.shade700),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRiskChip(String key, String label, Color color) {
    final sel = _selectedRisk == key;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      selectedColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: sel ? color : const Color(0xFFE2E8F0)),
      backgroundColor: const Color(0xFFF1F5F9),
      labelStyle: TextStyle(
        color: sel ? color : const Color(0xFF475569),
        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
        fontSize: 11.5,
      ),
      onSelected: (val) {
        if (val) {
          setState(() => _selectedRisk = key);
          _generateSession();
        }
      },
    );
  }

  Widget _buildStepCard(VeoPromptStep step) {
    Color typeColor = const Color(0xFF64748B);
    if (step.blockType.contains('RED')) typeColor = const Color(0xFFEF4444);
    if (step.blockType.contains('YELLOW')) typeColor = const Color(0xFFF59E0B);
    if (step.blockType.contains('GREEN')) typeColor = const Color(0xFF10B981);
    if (step.blockType == 'STIMULUS') typeColor = const Color(0xFF0F172A);

    final startStr = step.startSec.toString().padLeft(2, '0');
    final endStr = step.endSec.toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ÜST BİLGİ ŞERİDİ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: typeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${step.stepNumber}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$startStr - $endStr sn',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  step.blockType,
                  style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // BAŞLIK VE AÇIKLAMA
          Text(
            step.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 2),
          Text(
            step.actionDescription,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 10),

          // VEO İNGİLİZCE PROMPTU (KOD KUTUSU)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              step.veoPrompt,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Color(0xFFE2E8F0),
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // KOPYALA BUTONU
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: () {
                _copyToClipboard(
                  step.veoPrompt,
                  'Adım ${step.stepNumber} promptu kopyalandı!',
                );
              },
              icon: const Icon(Icons.copy, size: 15),
              label: Text(
                'Adım ${step.stepNumber} Promptunu Kopyala',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
