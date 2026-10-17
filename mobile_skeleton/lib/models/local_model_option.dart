/// Aynı indirme/çıkarım hattında ayrı dosyalar; senaryo motoru seçimi değildir.
enum LocalModelOption {
  llama(
    id: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
    name: 'Llama-3.2-1B-Instruct Q4_K_M',
    fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    estimatedBytes: 813700000,
    downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
  ),
  qwen3(
    id: 'unsloth/Qwen3-1.7B-GGUF',
    name: 'Qwen3-1.7B Q4_K_M',
    fileName: 'Qwen3-1.7B-Q4_K_M.gguf',
    estimatedBytes: 1107409472,
    downloadUrl: 'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
  ),
  miniCpmTurkish(
    id: 'thealper2/MiniCPM5-1B-Turkish',
    name: 'MiniCPM5-1B-Turkish Q4_K_M',
    fileName: 'MiniCPM5-1B-Turkish-Q4_K_M.gguf',
    estimatedBytes: 688065856,
    downloadUrl: 'https://huggingface.co/thealper2/MiniCPM5-1B-Turkish/resolve/main/MiniCPM5-1B-Turkish-Q4_K_M.gguf',
  );

  const LocalModelOption({
    required this.id,
    required this.name,
    required this.fileName,
    required this.estimatedBytes,
    required this.downloadUrl,
  });
  final String id;
  final String name;
  final String fileName;
  final int estimatedBytes;
  final String downloadUrl;
}
