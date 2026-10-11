import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const NeuroAwarenessApp());
}

class NeuroAwarenessApp extends StatelessWidget {
  const NeuroAwarenessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nörogelişimsel Farkındalık Platformu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          primary: Colors.indigo.shade700,
          secondary: Colors.teal.shade700,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}
