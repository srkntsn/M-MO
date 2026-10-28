# MİMO – Gemini AI sunucusu

Bu klasördeki `worker.js`, Gemini API anahtarını Android APK'sından ve herkese açık GitHub deposundan uzak tutar.

1. [Google AI Studio](https://aistudio.google.com/api-keys) üzerinden Gemini API anahtarı oluşturun. Anahtarı GitHub'a veya sohbete yazmayın.
2. [Cloudflare Workers](https://dash.cloudflare.com/) hesabında yeni Worker oluşturun, `worker.js` içeriğini yerleştirip deploy edin.
3. Worker ayarlarında **Secrets** olarak `GEMINI_API_KEY` ve kendiniz belirleyeceğiniz uzun, rastgele `MIMO_ACCESS_TOKEN` değerlerini ekleyin.
4. İsterseniz `GEMINI_MODEL` ortam değişkeniyle erişiminiz olan modeli seçin. Varsayılan: `gemini-2.5-flash-lite`.
5. MİMO'nun ayar ekranında HTTPS Worker URL'sini ve **MIMO_ACCESS_TOKEN** erişim parolasını yazın. **Gemini API anahtarını uygulamaya yazmayın.**

Worker bağlantısı aktif değilse MİMO henüz gerçek yapay zekâ sohbeti yapamaz. Google'ın ücretsiz kotası hesabınıza ve modele bağlıdır. Worker'ın herkese açık URL'sini paylaşırsanız başkaları da erişmeyi deneyebilir; erişim parolanızı gizli tutun ve gerektiğinde değiştirin. Bu basit tek-kullanıcılı örnektir, geniş çapta yayın için ek kimlik doğrulama, kota ve kötüye kullanım sınırlaması gerekir.

MİMO'nun ses menüsü telefonda yüklü Türkçe TTS seslerini listeler. Bu sesler tam olarak insan sesine eşdeğer olmayabilir; bulut tabanlı doğal ses henüz eklenmedi.
