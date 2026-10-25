import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AiService {
  AiService({FirebaseAuth? auth, http.Client? client})
      : _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client();

  final FirebaseAuth _auth;
  final http.Client _client;
  static const _baseUrl = String.fromEnvironment('DESA_AI_API_URL');

  Uri _uri(String path) {
    if (_baseUrl.trim().isEmpty) {
      throw StateError(
        'URL server Desa AI belum disetel. Jalankan dengan --dart-define=DESA_AI_API_URL=https://api.domain-anda.',
      );
    }
    return Uri.parse('${_baseUrl.replaceFirst(RegExp(r'/+$'), '')}/$path');
  }

  Future<Map<String, dynamic>> _post(String path,
      [Map<String, dynamic> data = const {}]) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sesi login habis. Silakan masuk kembali.');
    final token = await user.getIdToken();
    final response = await _client
        .post(
          _uri(path),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 30));
    final decoded = _decodeResponse(response);
    final result = decoded['result'];
    if (result is Map) return Map<String, dynamic>.from(result);
    return decoded;
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> decoded = {};
    try {
      final value = jsonDecode(response.body);
      if (value is Map) decoded = Map<String, dynamic>.from(value);
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['message'] ??
          (decoded['error'] is Map ? decoded['error']['message'] : null);
      throw AiRequestException(
        error?.toString() ?? 'Permintaan gagal (${response.statusCode}).',
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> getConfig() => _post('aiGetConfig');

  Future<Map<String, dynamic>> createRoom({String title = 'Chat baru'}) =>
      _post('aiCreateRoom', {'title': title});

  Future<void> renameRoom(String roomId, String title) async {
    await _post('aiRenameRoom', {'roomId': roomId, 'title': title});
  }

  Future<void> deleteRoom(String roomId) async {
    await _post('aiDeleteRoom', {'roomId': roomId});
  }

  Future<List<Map<String, dynamic>>> getPaymentChannels() async {
    final data = await _post('aiGetPaymentChannels');
    return (data['channels'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> createTopup({
    required int amount,
    required String method,
    String? email,
  }) =>
      _post('aiCreateTopupPayment', {
        'amount': amount,
        'method': method,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      });

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
    final request = http.Request('POST', _uri('aiChatStream'));
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

    final response = await _client.send(request).timeout(const Duration(seconds: 40));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final raw = await response.stream.bytesToString();
      var messageText = 'Permintaan gagal (${response.statusCode}).';
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['message'] is String) {
          messageText = decoded['message'] as String;
        }
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
  }
}

class AiRequestException implements Exception {
  AiRequestException(this.message);
  final String message;
  @override
  String toString() => message;
}
