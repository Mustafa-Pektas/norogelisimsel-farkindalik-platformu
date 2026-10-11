import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/main.dart';

void main() {
  testWidgets('Platform ana ekran ve mod yukleme testi', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const NeuroAwarenessApp());

    // Verify that the title and core modes are present
    expect(find.text('Nörogelişimsel Farkındalık Platformu'), findsOneWidget);
    expect(find.text('1. Simülasyon ve Eğitim Modu'), findsOneWidget);
    expect(find.text('2. Video Analiz Modu'), findsOneWidget);
  });
}
