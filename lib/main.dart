// lib/main.dart

import 'package:flutter/material.dart';
import 'screens/main_screen.dart';
import 'screens/overlay_screen.dart';

@pragma('vm:entry-point')
void overlayMain() {
  runApp(const OverlayApp());
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GameRecorderApp());
}

class GameRecorderApp extends StatelessWidget {
  const GameRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Game Recorder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.tealAccent,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0d1117),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161b22),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const MainScreen(),
    );
  }
}
