# Küçük sohbet şablonu fixture'ları

Bu klasörde model ağırlığı, kullanıcı sohbet kaydı, cihaz yolu veya gizli bilgi yoktur. Dosyalar yalnızca şablon motorunun davranışını test etmek için kullanılır; uygulama bu klasörden model ya da üretim şablonu yüklemez.

- `llama32_device_template.json`: mevcut Llama GGUF metadatasından alınmış sohbet şablonu ile BOS/EOS metinleri (yaklaşık 4 KB). Kaynak model: [Llama-3.2-1B-Instruct GGUF](https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF). Kişisel mesajlar veya ağırlık tensorları içermez.
- `qwen3_package_4b_template.jinja`: kurulu [llamadart 0.12.0](https://pub.dev/packages/llamadart/versions/0.12.0) paketindeki `test/fixtures/templates/Qwen3-4B.jinja` dosyasının kopyası (yaklaşık 5 KB). Bu, seçilen Qwen3-1.7B GGUF'den çıkarılmış bir şablon değildir. Gerçek modelin şablonu ayrıca çalışma anında denetlenir.

Şablon metninde koşullu araç/JSON talimatlarının bulunması, araçsız D01 isteğinde bu talimatların etkin olduğu anlamına gelmez; testler oluşturulan son promptu denetler. Fixture cevapları model çıkarımı veya davranış ground truth'u değildir.

## llamadart paketinin lisans bildirimi

Paketten alınan Qwen fixture'ı için paketle birlikte gelen bildirim korunmuştur:

```text
MIT License

Copyright (c) 2024 Jhin Lee

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
