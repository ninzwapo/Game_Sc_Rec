// lib/services/overlay_service.dart
//
// Handles requesting SYSTEM_ALERT_WINDOW permission and launching
// the floating overlay window above Chrome or any other app.

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

class OverlayService {
  /// Request permission to draw over other apps.
  /// On Android this opens the system Settings page for the user to toggle.
  static Future<bool> requestPermission() async {
    final status = await Permission.systemAlertWindow.request();
    return status.isGranted;
  }

  /// Check if overlay permission is already granted.
  static Future<bool> hasPermission() async {
    return await FlutterOverlayWindow.isPermissionGranted();
  }

  /// Show the floating overlay panel above all apps.
  static Future<void> showOverlay() async {
    await FlutterOverlayWindow.showOverlay(
      height: 420,
      width: 320,
      alignment: OverlayAlignment.centerRight,
      flag: OverlayFlag.defaultFlag,
      overlayTitle: "Game Recorder",
      overlayContent: "Pattern lines active",
      enableDrag: true,
      positionGravity: PositionGravity.auto,
    );
  }

  /// Hide the floating overlay.
  static Future<void> hideOverlay() async {
    await FlutterOverlayWindow.closeOverlay();
  }

  /// Send data to the overlay widget (e.g. updated line positions).
  static Future<void> sendData(Map<String, dynamic> data) async {
    await FlutterOverlayWindow.shareData(data);
  }
}
