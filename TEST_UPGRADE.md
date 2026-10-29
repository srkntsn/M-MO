# MİMO 0.5 test adayı

Bu dal henüz telefona yüklenmiş bir güncelleme veya Play Store yayını değildir.

## Uygulananlar

- İlk açılışta mikrofon ve kamera açıklaması; Android izinleri sırayla istenir.
- Ön/arka kamera sesle seçilir; son seçim korunur. “Beni görebiliyor musun” ön kamerayı seçer.
- İki kameranın fotoğrafları arka plan isolate içinde JPEG'e dönüştürülür; en uzun kenar en fazla 960 piksel, dosya en fazla 180.000 bayt. Reddedilen görüntü kendiliğinden tekrar gönderilmez.
- Dinlemeye dönüş bekleme süresi azaltıldı; boş/sessiz tanıma durumunda giderek büyüyen gecikme uygulanmaz. Gerçek zamanlı çift yönlü konuşma henüz yoktur.
- İki kişilik test için 24 saatlik tek cihaz daveti; cihaz erişimi iptal edilebilir. Ana erişim parolası APK'ya veya davet bağlantısına konmaz. Cihaz parolaları Android güvenli depolamasında tutulur.

## Sunucu kurulumu

Davet özelliği `backend` dizininden tam Wrangler dağıtımı gerektirir. Yalnızca `worker.js` dosyasını panelde değiştirmek yeterli değildir; `devices.js`, Durable Object binding ve SQLite migration birlikte dağıtılmalıdır:

```sh
cd backend
npx wrangler deploy
```

Mevcut `GEMINI_API_KEY`, `MIMO_ACCESS_TOKEN`, varsa `GEMINI_MODEL` değerleri korunur. Bunları kod deposuna koymayın. `MIMO_DEVICES` bağlanmadan davet işlemi 503 ile açıkça durur. Eski ana cihaz erişimi çalışmaya devam eder.

Ana cihazda yüze uzun bas → Davet ve cihazlar → cihaz adını yaz → Davet oluştur → Bağlantıyı kopyala. Alıcı güncel uygulamayı kurar, bağlantıyı açar ve Etkinleştir'e dokunur. Cihaz listesinde yalnızca davet edilmiş cihazlar görünür.

Bu kayıt sistemi iki kişilik test içindir: tek Durable Object ve 100 cihaz sınırı vardır. Milyonlarca eşzamanlı kullanıcı kapasitesi iddiası yoktur. Mağaza sürümü için ayrı kimlik/abonelik, dağıtık yetkilendirme, kota ve bütçe kontrolleri gerekir.

## Blender modeli

`scripts/create_avatar.py` Blender'da modellenebilir seramik android başı üretir. Ayrıntılı gözler, daralan çene, kaşlar, burun, ayrı üst/alt dudaklar ve `jawOpen` morph hedefleri bulunur. Model fotogerçekçi insan iddiası taşımaz.

`MIMO Blender avatar` iş akışı `.blend`, `.glb` ve iki render PNG'si üretir. Model uygulamaya ModelViewer ile bağlandı; APK derlemesi GLB dosyasını Blender ile üretip paketler. MimoSpeech morph animasyonu, sunucu sesinde WAV enerji zarfıyla; yerel ses yedeğinde kelime ilerlemesiyle sürülür. Bu yaklaşık dudak eşleştirmesidir, fonem/visem hizalaması değildir. 29 Ekim 2026 tarihli CI renderi başarıyla üretildi ve portre görsel olarak incelendi. Fiziksel telefon performansı henüz doğrulanmadı.

## Ses, sağlayıcı ve güncelleme

- Hazır hizmette Gemini ses üretimi `/speech` üzerinden kullanılır; başarısız olursa Android TTS yedeğine döner. Gerçek sağlayıcı kotası ve Türkçe ses kalitesi canlı telefon testinde kontrol edilmelidir. WAV enerji zarfı dudak açıklığını sürer.
- Gelişmiş ayarlarda Gemini, OpenAI ve Claude için kullanıcının kendi API anahtarı/modeli seçilebilir; anahtar güvenli depoda tutulur, istek doğrudan seçilen sağlayıcıya gider. Hazır hizmet varsayılandır. Konuşma sesi hazır MİMO hizmetini kullanır; özel model seçimi ses hizmetini değiştirmez.
- Test sürümü yeni APK'yı indirir, SHA-256 ve kurulum öncesinde paket/sürüm/imza kontrolü yapar; Android'in onay ekranını açar. Kullanıcı kurulumu kendisi onaylar. Ayarlar silinmez. Play kaynağından gelen kurulumda Play güncellemesi kullanılır; dış APK kurulumu kapalıdır. Mağaza derlemesi `MIMO_PLAY_BUILD=1` ile hazırlanmalıdır.

## Yayından önce kalan doğrulamalar

- Gerçek cihazda mikrofon izinleri, ön/arka görüntü, ses gecikmesi, yüz performansı, davet ve uygulama üstüne güncelleme.
- Canlı Worker dağıtımı ve gerçek sağlayıcıyla sohbet/görsel/ses doğrulaması.
- Fotogerçekçi insan kalitesi, ayrı fonem/visem eşleştirmesi, göz kırpma ve hapşırma sesi algılama bu adayda tamamlanmış özellik değildir.
- Kalıcı imza anahtarı/Play App Signing, mağaza AAB'si ve faturalandırma.
- Fiziksel cihaz testleri, kötü ağ koşulları, gecikme ölçümleri ve gerçek yük testleri.

Bu liste tamamlanmış özelliklerle gelecek işleri özellikle ayırır. Henüz sunucu dağıtımı veya fiziksel telefon doğrulaması yapılmadı.
