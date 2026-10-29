import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdater {
  static const channel = MethodChannel('mimo/update');
  bool running = false;
  Future<bool> fromPlay() async =>
      const bool.fromEnvironment('PLAY_STORE') ||
      (await channel.invokeMethod<bool>('fromPlay') ?? false);
  Future<Map<String, dynamic>?> check() async {
    if (await fromPlay()) {
      final info = await InAppUpdate.checkForUpdate();
      return info.updateAvailability == UpdateAvailability.updateAvailable
          ? {'play': true}
          : null;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .getUrl(Uri.parse(
              'https://api.github.com/repos/srkntsn/M-MO/releases/latest'))
          .timeout(const Duration(seconds: 8));
      req.headers.set('User-Agent', 'MIMO-Android');
      final response = await req.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 8));
      if (text.length > 262144) return null;
      final release = jsonDecode(text) as Map<String, dynamic>;
      final latest = int.tryParse(RegExp(r'build\.(\d+)$')
                  .firstMatch(release['tag_name'] as String? ?? '')
                  ?.group(1) ??
              '') ??
          0;
      final info = await PackageInfo.fromPlatform();
      if (latest <= (int.tryParse(info.buildNumber) ?? 0)) return null;
      final assets = release['assets'] as List<dynamic>? ?? [];
      final matches = assets
          .whereType<Map<String, dynamic>>()
          .where((x) => x['name'] == 'mimo-ai.apk');
      if (matches.isEmpty) return null;
      final asset = matches.first,
          url = Uri.tryParse(asset['browser_download_url'] as String? ?? '');
      final digest = asset['digest'] as String? ?? '';
      if (url == null ||
          url.scheme != 'https' ||
          url.host != 'github.com' ||
          !url.path.startsWith('/srkntsn/M-MO/releases/download/') ||
          !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest)) return null;
      return {
        'play': false,
        'url': url.toString(),
        'sha256': digest.substring(7),
        'version': release['tag_name']
      };
    } finally {
      client.close(force: true);
    }
  }

  Future<void> install(
      Map<String, dynamic> update, void Function(double) progress) async {
    if (running) return;
    running = true;
    try {
      if (await fromPlay()) {
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) {
          await InAppUpdate.completeFlexibleUpdate();
        } else if (result == AppUpdateResult.inAppUpdateFailed) {
          throw const FormatException('Play güncellemesi tamamlanamadı.');
        }
        return;
      }
      if (update['play'] == true)
        throw const FormatException(
            'Güncelleme kaynağı değişti; yeniden kontrol et.');
      final temp = await getTemporaryDirectory();
      final directory = Directory('${temp.path}/mimo-updates');
      await directory.create(recursive: true);
      final file = File('${directory.path}/mimo.apk');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client
            .getUrl(Uri.parse(update['url'] as String))
            .timeout(const Duration(seconds: 12));
        final response = await req.close().timeout(const Duration(seconds: 20));
        if (response.statusCode != 200)
          throw const FormatException('Güncelleme indirilemedi.');
        final sink = file.openWrite();
        var count = 0;
        try {
          await for (final chunk
              in response.timeout(const Duration(seconds: 20))) {
            count += chunk.length;
            if (count > 250000000)
              throw const FormatException('Güncelleme dosyası fazla büyük.');
            sink.add(chunk);
            progress(response.contentLength > 0
                ? count / response.contentLength
                : 0);
          }
        } finally {
          await sink.close();
        }
        final checksum = await sha256.bind(file.openRead()).first;
        if (checksum.toString() != update['sha256']) {
          await file.delete();
          throw const FormatException('Dosya doğrulanamadı; kurulmadı.');
        }
      } finally {
        client.close(force: true);
      }
      if (!(await channel.invokeMethod<bool>('canInstall') ?? false)) {
        await channel.invokeMethod<void>('openInstallSettings');
        throw const FormatException(
            'Android kurulum iznini verdikten sonra yeniden “güncelle” de.');
      }
      await channel.invokeMethod<void>('installTestUpdate');
    } finally {
      running = false;
    }
  }
}
