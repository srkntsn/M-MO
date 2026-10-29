import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Invitation {
  const Invitation(this.server, this.code);
  final Uri server;
  final String code;
  static Invitation? parse(Uri link) {
    if (link.scheme != 'mimo' || link.host != 'activate') return null;
    final server = Uri.tryParse(link.queryParameters['server'] ?? '');
    final code = link.queryParameters['invite'] ?? '';
    if (server == null ||
        server.scheme != 'https' ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        server.hasQuery ||
        server.hasFragment ||
        (server.path.isNotEmpty && server.path != '/') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(code)) return null;
    return Invitation(server.replace(path: '/'), code);
  }
}

class InviteAccess {
  static const storage = FlutterSecureStorage();
  Future<Map<String, String>?> load() async {
    final value = await storage.read(key: 'mimo_credential');
    if (value == null) return null;
    final data = jsonDecode(value) as Map<String, dynamic>;
    return {
      'endpoint': data['endpoint'] as String,
      'token': data['token'] as String,
    };
  }

  Future<void> save(String endpoint, String token) => storage.write(
        key: 'mimo_credential',
        value: jsonEncode({'endpoint': endpoint, 'token': token}),
      );
  Future<Map<String, dynamic>> request(
    Uri server,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    if (server.scheme != 'https' ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty) {
      throw const FormatException('Geçerli HTTPS sunucusu gerekli.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .openUrl(body == null ? 'GET' : 'POST', server.resolve(path))
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      if (body != null) req.add(utf8.encode(jsonEncode(body)));
      final response = await req.close().timeout(const Duration(seconds: 12));
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        bytes.addAll(chunk);
        if (bytes.length > 65536)
          throw const FormatException('Geçersiz sunucu yanıtı.');
      }
      if (response.statusCode == 401)
        throw const FormatException(
          'Bu işlem için ana cihazın erişimi gerekli.',
        );
      if (response.statusCode == 409)
        throw const FormatException('Bu davet başka bir cihazda kullanılmış.');
      if (response.statusCode == 410)
        throw const FormatException(
          'Davetin süresi dolmuş veya bağlantı geçersiz.',
        );
      if (response.statusCode == 503)
        throw const FormatException(
          'Sunucuda cihaz etkinleştirme henüz kurulmamış.',
        );
      if (response.statusCode != 200)
        throw const FormatException(
          'İşlem tamamlanamadı. Biraz sonra tekrar deneyebilirsin.',
        );
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> redeem(Invitation invitation) async {
    // Persist BEFORE redemption so a lost response can safely be retried.
    final saved = await storage.read(key: 'mimo_pending_activation');
    Map<String, dynamic>? pending;
    if (saved != null) pending = jsonDecode(saved) as Map<String, dynamic>;
    final server = invitation.server.toString();
    if (pending?['server'] != server || pending?['code'] != invitation.code) {
      final random = Random.secure();
      final secret = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      pending = {
        'server': server,
        'code': invitation.code,
        'token': 'device_$secret',
      };
      await storage.write(
        key: 'mimo_pending_activation',
        value: jsonEncode(pending),
      );
    }
    final deviceToken = pending!['token'] as String;
    final result = await request(
      invitation.server,
      '/auth/redeem',
      body: {'code': invitation.code, 'deviceToken': deviceToken},
    );
    if (result['activated'] != true)
      throw const FormatException('Cihaz etkinleştirilemedi.');
    await save(server, deviceToken);
    await storage.delete(key: 'mimo_pending_activation');
    return deviceToken;
  }
}
