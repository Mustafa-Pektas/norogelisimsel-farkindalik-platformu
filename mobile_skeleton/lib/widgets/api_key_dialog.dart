import 'package:flutter/material.dart';
import '../services/llm_rag_service.dart';

class ApiKeyDialog {
  static Future<bool?> show(BuildContext context) async {
    final currentKey = await LlmRagService.getApiKey();
    final controller = TextEditingController(text: currentKey ?? '');
    bool obscure = true;

    if (!context.mounted) return null;

    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                    'Kendi Google Gemini API anahtarınızı girerek senaryoları ve Veo promptlarını doğrudan gerçek LLM ile üretebilirsiniz.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'AIzaSy...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      prefixIcon: const Icon(Icons.vpn_key_outlined, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '💡 aistudio.google.com adresinden ücretsiz alabilirsiniz. Anahtarınız yalnızca telefonunuzda saklanır.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                  ),
                  if (hasKey) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 16),
                          SizedBox(width: 6),
                          Text('Cihazda kayıtlı anahtar mevcut', style: TextStyle(fontSize: 11.5, color: Colors.green, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                if (hasKey)
                  TextButton(
                    onPressed: () async {
                      await LlmRagService.clearApiKey();
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                    },
                    child: const Text('Anahtarı Sil', style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('İptal', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final key = controller.text.trim();
                    if (key.isNotEmpty) {
                      await LlmRagService.saveApiKey(key);
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                    }
                  },
                  child: const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
