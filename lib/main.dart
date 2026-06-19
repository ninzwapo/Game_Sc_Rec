// main.dart
// 10-second screen recorder app for Android.
// Uses Android's MediaProjection API (via flutter_screen_recording package)
// to record whatever is on screen for exactly 10 seconds, then saves the
// .mp4 to the device's Downloads folder.

import 'package:flutter/material.dart';
import 'screens/recorder_screen.dart';

void main() {
  runApp(const ScreenRecorderApp());
}

class ScreenRecorderApp extends StatelessWidget {
  const ScreenRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Screen Recorder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.tealAccent,
        useMaterial3: true,
      ),
      home: const RecorderScreen(),
    );
  }
}
