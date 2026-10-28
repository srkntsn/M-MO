MİMO 0.4 — sesli ve 3D yüzlü sanal arkadaş (Android test sürümü)

- Ana ekranda yalnızca perspektifli, ışıklandırılmış, hareketli 3D yüz.
- Otomatik Türkçe dinleme → yanıt → yeniden dinleme. Konuşmayı kesmek için yüze dokun.
- “Kameraya bak / buna bak / bunu oku”: arka kameradan tek kare yorumlama.
- “Uyu”: dinlemeyi durdur. Uyandırmak için yüze dokun.
- “Geçmişi unut”: cihazda tutulan son 6 konuşmayı sil.
- “Güncelleme var mı?”: sürüm kontrolü. “Yeni sürümü aç”: APK indirme sayfası.
- Bağlantı ayarları için yüze uzun bas. İlk kurulumda bağlantı ekranı açılır.

Kamera ve yeni sohbet kişiliği için backend/worker.js de güncellenmelidir. Eski Worker ile sesli metin sohbeti çalışmaya devam eder. Gemini veya erişim Secrets değerlerini değiştirmeyin.

Bu bir debug/test APK’sıdır. Android kurulum izni ister. Yeni APK “paket çakışıyor” derse imza farklıdır; uygulamayı silmeden önce bağlantı ayarlarını güvenli biçimde not edin. Eski kurulumu kaldırmak cihazdaki ayarları ve sohbeti siler. Kalıcı aynı imza için deponun MIMO_DEBUG_KEYSTORE_BASE64 Secret’ını yapılandırın; yalnızca önbellekte tutulan test imzası kalıcılık garantisi vermez.

Ses tanıma cihazın Android konuşma hizmetine bağlıdır. Bu sürüm aynı anda dinleyen ve konuşan tam çift yönlü ses/video akışı değildir. Kamera sürekli açık kalmaz. Mağaza sürümü veya profesyonel imzalı yayın değildir.
