MİMO 0.5 — Android test adayı

- Açılışta mikrofon ve kamera izinlerini açıklayan ekran.
- Sesle ön/arka kamera seçimi; iki kamerada fotoğraf küçültme ve sıkıştırma, boyut hatasında tekrar döngüsünün durdurulması.
- Dinlemeye dönüş gecikmesinin azaltılması.
- Blender ile üretilmiş insansı seramik android başı, ses enerjisiyle hareket eden ayrı dudaklar.
- Sunucu üzerinden Türkçe ses üretimi; başarısızlıkta cihaz sesi yedeği.
- İki kişilik test için tek cihaz daveti, cihaz erişimini iptal etme.
- Gelişmiş ayarlarda isteğe bağlı Gemini/OpenAI/Claude API hesabı; varsayılan hazır MİMO hizmeti.
- “Güncelle” komutuyla indirme, dosya ve imza doğrulaması, Android kurulum onayı. Play kurulumlarında Play güncelleme yolu.

Bu test adayı yeni Worker dağıtımını gerektirir. backend dizininin tamamı Wrangler ile dağıtılmalıdır; eski erişim ve Gemini Secrets korunur. Ayrıntılar TEST_UPGRADE.md dosyasındadır.

Fiziksel cihaz ve canlı sağlayıcı testleri henüz doğrulanmamıştır. Bu APK bir mağaza yayını, fotogerçekçi yüz veya milyonlarca eşzamanlı kullanıcı kapasitesi beyanı değildir. Test imzasının korunması için aynı önbellek/kalıcı keystore kullanılmalıdır; uygulamayı kaldırmak ayarları siler.
