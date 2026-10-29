import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'invitations.dart';

const companionInstructions =
    'Sen MİMO isimli sıcak, meraklı ve esprili bir Türkçe sesli arkadaşsın. Konuşmayı ve verilen geçmişi takip et. Genellikle 1-3 kısa cümleyle yanıtla. Gerektiğinde ayrıntıyı açıkla. Yanlış bilgiyi onaylama, bilmediğini belirt. Yalnızca gönderilen görüntüyü gördüğünü söyle; sürekli izlediğini iddia etme. Liste ve Markdown yerine doğal konuş. Kullanıcının sözlerine doğrudan karşılık ver; aynı selamı ve soruyu tekrar etme.';

class CustomAI {
  String provider, model, key;
  HttpClient? client;
  CustomAI(this.provider, this.model, this.key);
  static Future<CustomAI?> load() async {
    final value = await InviteAccess.storage.read(key: 'mimo_custom_ai');
    if (value == null) return null;
    final data = jsonDecode(value) as Map<String, dynamic>;
    return CustomAI(data['provider'] as String, data['model'] as String,
        data['key'] as String);
  }

  void cancel() {
    client?.close(force: true);
    client = null;
  }

  Future<String> ask(String message, List<Map<String, String>> history,
      {Map<String, dynamic>? image}) async {
    Uri uri;
    Map<String, String> headers = {};
    Map<String, dynamic> body;
    final previous =
        history.map((x) => {'role': x['role'], 'content': x['text']}).toList();
    if (provider == 'OpenAI') {
      uri = Uri.parse('https://api.openai.com/v1/responses');
      headers['Authorization'] = 'Bearer $key';
      body = {
        'model': model,
        'instructions': companionInstructions,
        'store': false,
        'max_output_tokens': 1200,
        'input': [
          ...previous,
          {
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': message},
              if (image != null)
                {
                  'type': 'input_image',
                  'image_url':
                      'data:${image['mimeType']};base64,${image['data']}'
                }
            ]
          }
        ]
      };
    } else if (provider == 'Claude') {
      uri = Uri.parse('https://api.anthropic.com/v1/messages');
      headers = {'x-api-key': key, 'anthropic-version': '2023-06-01'};
      body = {
        'model': model,
        'system': companionInstructions,
        'max_tokens': 1000,
        'messages': [
          ...previous,
          {
            'role': 'user',
            'content': [
              if (image != null)
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': image['mimeType'],
                    'data': image['data']
                  }
                },
              {'type': 'text', 'text': message}
            ]
          }
        ]
      };
    } else if (provider == 'Gemini') {
      uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/${Uri.encodeComponent(model)}:generateContent');
      headers['x-goog-api-key'] = key;
      body = {
        'systemInstruction': {
          'parts': [
            {'text': companionInstructions}
          ]
        },
        'generationConfig': {'maxOutputTokens': 1000},
        'contents': [
          for (final x in history)
            {
              'role': x['role'] == 'assistant' ? 'model' : 'user',
              'parts': [
                {'text': x['text']}
              ]
            },
          {
            'role': 'user',
            'parts': [
              {'text': message},
              if (image != null) {'inlineData': image}
            ]
          }
        ]
      };
    } else {
      throw const FormatException('Desteklenmeyen sağlayıcı.');
    }
    final connection = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    client = connection;
    try {
      final req =
          await connection.postUrl(uri).timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      headers.forEach(req.headers.set);
      req.add(utf8.encode(jsonEncode(body)));
      final response = await req.close().timeout(const Duration(seconds: 35));
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        bytes.addAll(chunk);
        if (bytes.length > 2000000)
          throw const FormatException('Sağlayıcı yanıtı fazla büyük.');
      }
      if (response.statusCode == 401 || response.statusCode == 403)
        throw const FormatException(
            'Kendi yapay zekâ hesabının API erişimi reddedildi.');
      if (response.statusCode == 429)
        throw const FormatException(
            'Kendi yapay zekâ hesabının kotası veya kullanım sınırı dolmuş.');
      if (response.statusCode != 200)
        throw const FormatException(
            'Seçilen model isteği kabul etmedi. Model adını ve görüntü desteğini kontrol et.');
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final String reply;
      if (provider == 'OpenAI') {
        reply = (data['output'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .expand((x) => x['content'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .where((x) => x['type'] == 'output_text')
            .map((x) => x['text'] as String? ?? '')
            .join();
      } else if (provider == 'Claude') {
        reply = (data['content'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .where((x) => x['type'] == 'text')
            .map((x) => x['text'] as String? ?? '')
            .join();
      } else {
        final candidates = data['candidates'] as List<dynamic>? ?? [];
        reply = candidates.isEmpty
            ? ''
            : ((candidates.first['content']?['parts']) as List<dynamic>? ?? [])
                .whereType<Map>()
                .where((x) => x['thought'] != true)
                .map((x) => x['text'] as String? ?? '')
                .join();
      }
      if (reply.trim().isEmpty)
        throw const FormatException(
            'Sağlayıcı konuşulabilir bir yanıt üretmedi.');
      return reply.trim();
    } finally {
      connection.close(force: true);
      if (identical(client, connection)) client = null;
    }
  }
}

Future<void> customAISettings(BuildContext parent) async {
  final config = await CustomAI.load();
  if (!parent.mounted) return;
  String provider = config?.provider ?? 'Hazır MİMO';
  final model = TextEditingController(text: config?.model ?? ''),
      secret = TextEditingController(text: config?.key ?? '');
  String? error;
  bool testing = false;
  await showDialog<void>(
      context: parent,
      builder: (context) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
                title: const Text('Gelişmiş yapay zekâ'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Normal kullanımda Hazır MİMO yeterlidir. Kendi API hesabını bağlarsan sohbet ve kamera kareleri seçtiğin sağlayıcıya gider; API kullanım ücreti kendi hesabına yansır. Normal sohbet aboneliği otomatik olarak API erişimi vermez. Ses hizmeti ayrıca MİMO sunucusunu kullanır.'),
                  DropdownButton<String>(
                      value: provider,
                      isExpanded: true,
                      items: [
                        for (final x in [
                          'Hazır MİMO',
                          'Gemini',
                          'OpenAI',
                          'Claude'
                        ])
                          DropdownMenuItem(value: x, child: Text(x))
                      ],
                      onChanged:
                          testing ? null : (x) => refresh(() => provider = x!)),
                  if (provider != 'Hazır MİMO') ...[
                    TextField(
                        controller: model,
                        decoration: const InputDecoration(
                            labelText:
                                'API model adı (hesabında erişilebilir olmalı)')),
                    TextField(
                        controller: secret,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                            labelText: 'Kendi API anahtarın')),
                    const Text(
                        'Anahtar bu cihazın güvenli deposunda tutulur ve doğrudan seçilen sağlayıcıya gönderilir. Kamera için görüntü destekli model seç.'),
                  ],
                  if (testing) const CircularProgressIndicator(),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.orange)),
                ])),
                actions: [
                  TextButton(
                      onPressed: testing ? null : () => Navigator.pop(context),
                      child: const Text('Vazgeç')),
                  if (provider != 'Hazır MİMO')
                    TextButton(
                        onPressed: testing
                            ? null
                            : () async {
                                if (model.text.trim().isEmpty ||
                                    secret.text.trim().isEmpty) {
                                  refresh(() =>
                                      error = 'Model ve API anahtarı gerekli.');
                                  return;
                                }
                                refresh(() {
                                  testing = true;
                                  error = null;
                                });
                                try {
                                  await CustomAI(provider, model.text.trim(),
                                          secret.text.trim())
                                      .ask('Yalnızca bağlantı tamam de.', []);
                                  error =
                                      'Bağlantı testi başarılı. Kaydet ile etkinleştir.';
                                } catch (e) {
                                  error = e is FormatException
                                      ? e.message
                                      : 'Bağlantı testi tamamlanamadı.';
                                }
                                if (context.mounted)
                                  refresh(() => testing = false);
                              },
                        child: const Text('Bağlantıyı dene')),
                  FilledButton(
                      onPressed: testing
                          ? null
                          : () async {
                              if (provider == 'Hazır MİMO') {
                                await InviteAccess.storage
                                    .delete(key: 'mimo_custom_ai');
                              } else {
                                if (model.text.trim().isEmpty ||
                                    secret.text.trim().isEmpty) {
                                  refresh(() =>
                                      error = 'Model ve API anahtarı gerekli.');
                                  return;
                                }
                                await InviteAccess.storage.write(
                                    key: 'mimo_custom_ai',
                                    value: jsonEncode({
                                      'provider': provider,
                                      'model': model.text.trim(),
                                      'key': secret.text.trim()
                                    }));
                              }
                              if (context.mounted) Navigator.pop(context);
                            },
                      child: const Text('Kaydet')),
                ],
              )));
  await Future<void>.delayed(const Duration(milliseconds: 400));
  model.dispose();
  secret.dispose();
}
