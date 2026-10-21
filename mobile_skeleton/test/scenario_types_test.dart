import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';

void main() {
  testWidgets('Doktor modunda saniyesiz klinik protokol görünür; 5 tıkla gizli admin video stüdyosu açılır', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SyntheticVideoStudioScreen(),
      ),
    );

    // Initial delay in _generateScenario
    await tester.pumpAndSettle();

    // 1. Standart doktor modunda video tür seçicisi, saniyelik ayarlar ve geliştirici benchmark kartları gizlidir
    expect(find.text('Tür 1: Doktor Protokolü'), findsNothing);
    expect(find.text('Tür 2: Video Stüdyosu'), findsNothing);
    expect(find.text('Saniyelik Klip Dilimleme & Prompt Ayarları (Admin)'), findsNothing);
    expect(find.text('Geliştirici & On-Device Model Benchmark Testleri'), findsNothing);

    // 2. Üç motor seçeneği (Yerel, Llama 3.2, Qwen3) mevcuttur
    expect(find.text('Yerel Klinik'), findsOneWidget);
    expect(find.text('Llama-3.2'), findsOneWidget);
    expect(find.text('Qwen3-1.7B'), findsOneWidget);

    // 3. Varsayılan olarak Doktor Klinik Protokolü, FSM dalları ve AI metrikleri görünür
    expect(find.text('1. Klinik Test & Uyaran Protokolü'), findsOneWidget);
    expect(find.text('2. Olası Davranışsal Tepkiler (FSM Dallanma)'), findsOneWidget);
    expect(find.text('3. AI & Bilgisayarlı Görü Ölçüm Parametreleri'), findsOneWidget);
    expect(find.text('YEŞİL'), findsOneWidget);
    expect(find.text('SARI'), findsOneWidget);
    expect(find.text('KIRMIZI'), findsOneWidget);

    // 4. Başlığa 5 kez dokunarak gizli Admin Modunu açalım
    final titleFinder = find.text('Doktor Klinik Protokolü');
    expect(titleFinder, findsOneWidget);

    for (int i = 0; i < 5; i++) {
      await tester.tap(titleFinder);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 350));

    // Admin modu açılınca: Tür seçici, saniyelik klip dilimleme ve geliştirici kartları görünür hale gelir
    expect(find.text('Tür 1: Doktor Protokolü'), findsOneWidget);
    expect(find.text('Tür 2: Video Stüdyosu'), findsOneWidget);
    expect(find.text('Saniyelik Klip Dilimleme & Prompt Ayarları (Admin)'), findsOneWidget);
    expect(find.text('Geliştirici & On-Device Model Benchmark Testleri'), findsOneWidget);
    expect(find.text('Adım Adım'), findsOneWidget);
    expect(find.text('Tek Metin (Birleşik)'), findsOneWidget);

    // 5. 'Kapat' butonuna basarak tekrar temiz doktor moduna dönelim
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle(const Duration(milliseconds: 350));

    // Tekrar gizlenmiş olmalıdır
    expect(find.text('Tür 1: Doktor Protokolü'), findsNothing);
    expect(find.text('Tür 2: Video Stüdyosu'), findsNothing);
    expect(find.text('Saniyelik Klip Dilimleme & Prompt Ayarları (Admin)'), findsNothing);
    expect(find.text('Geliştirici & On-Device Model Benchmark Testleri'), findsNothing);
    expect(find.text('1. Klinik Test & Uyaran Protokolü'), findsOneWidget);
  });
}
