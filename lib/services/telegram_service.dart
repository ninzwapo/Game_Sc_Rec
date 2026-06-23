// lib/services/telegram_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'saved_pattern.dart';

class TelegramService {
  static Future<bool> sendMessage(String message) async {
    try {
      final token = await AppSettings.getBotToken();
      final chatId = await AppSettings.getChatId();
      final url =
          Uri.parse('https://api.telegram.org/bot$token/sendMessage');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': message,
          'parse_mode': 'HTML',
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> testConnection() async {
    return sendMessage('✅ Game Recorder connected! Live monitoring active.');
  }
}
