import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

class AiService {
  AiService({FirebaseFunctions? functions, FirebaseAuth? auth})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast2'),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  Future<Map<String, dynamic>> getConfig() async {
    final result = await _functions.httpsCallable('aiGetConfig').call<dynamic>();
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> createRoom({String title = 'Chat baru'}) async {
    final result = await _functions.httpsCallable('aiCreateRoom').call<dynamic>({'title': title});
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> renameRoom(String roomId, String title) async {
    await _functions.httpsCallable('aiRenameRoom').call<dynamic>({'roomId': roomId, 'title': title});
  }

  Future<void> deleteRoom(String roomId) async {
    await _functions.httpsCallable('aiDeleteRoom').call<dynamic>({'roomId': roomId});
  }

  Future<List<Map<String, dynamic>>> getPaymentChannels() async {
    final result = await _functions.httpsCallable('aiGetPaymentChannels').call<dynamic>();
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['channels'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> createTopup({
    required int amount,
    required String method,
    String? email,
  }) async {
    final result = await _functions.httpsCallable('aiCreateTopupPayment').call<dynamic>({
      'amount': amount,
      'method': method,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Stream<Map<String, dynamic>> sendMessage({
    required String roomId,
    required String message,
    required String model,
    required String requestId,
    required List<String> plugins,
  }) async* {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sesi login habis. Silakan masuk kembali.');
    final token = await user.getIdToken();
    final projectId = Firebase.app().options.projectId;
    if (projectId == null || projectId.isEmpty) {
      throw StateError('Firebase project ID belum tersedia. Jalankan flutterfire configure.');
    }

    final request = http.Request(
      'POST',
      Uri.parse('https://asia-southeast2-$projectId.cloudfunctions.net/aiChatStream'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode({
      'roomId': roomId,
      'message': message,
      'model': model,
      'requestId': requestId,
      'plugins': plugins,
    });

    final client = http.Client();
    try {
      final response = await client.send(request).timeout(const Duration(seconds: 40));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final raw = await response.stream.bytesToString();
        var messageText = 'Permintaan gagal (' + response.statusCode.toString() + ').';
        try {
          final json = jsonDecode(raw);
          if (json is Map && json['message'] is String) messageText = json['message'] as String;
        } catch (_) {
          if (raw.isNotEmpty) messageText = raw;
        }
        throw AiRequestException(messageText);
      }

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) yield Map<String, dynamic>.from(decoded);
        } catch (_) {
          // Ignore malformed keep-alive lines; the next SSE event may still be valid.
        }
      }
    } on TimeoutException {
      throw AiRequestException('Koneksi AI terlalu lama. Status saldo akan diperiksa server.');
    } finally {
      client.close();
    }
  }
}

class AiRequestException implements Exception {
  AiRequestException(this.message);
  final String message;
  @override
  String toString() => message;
}
