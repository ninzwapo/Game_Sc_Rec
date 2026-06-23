// lib/services/overlay_service.dart

import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayService {
  static Future<void> showOverlay() async {
    await FlutterOverlayWindow.showOverlay(
      height: 160,
      width: 300,
      alignment: OverlayAlignment.topRight,
      flag: OverlayFlag.defaultFlag,
      overlayTitle: 'Game Recorder',
      overlayContent: 'Monitoring active',
      enableDrag: true,
      positionGravity: PositionGravity.auto,
    );
  }

  static Future<void> hideOverlay() async {
    await FlutterOverlayWindow.closeOverlay();
  }

  static Future<void> sendData(Map<String, dynamic> data) async {
    await FlutterOverlayWindow.shareData(data);
  }
}
