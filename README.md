# MİMO 0.7

Ön planda sürekli mikrofon + Gemini Live ses bağlantısı. Normal sohbet sırasında AudioRecord durdurulup yeniden başlatılmaz. Çıkış PCM 24 kHz, giriş PCM 16 kHz/20 ms. Server-side VAD, START_OF_ACTIVITY_INTERRUPTS; kesilme sinyali Android ses kuyruğunu temizler. AEC cihaz destekliyorsa etkinleşir. Arka plan/uyku/ayarlar mikrofonu kapatır.

`GET /live` WebSocket yükseltmesi mevcut owner/device bearer yetkisini kullanır. Worker, erişilebilir `bidiGenerateContent` modelini katalogdan seçer; mevcut `GEMINI_MODEL` metin API ayarı değişmez. İstenirse ayrıca `GEMINI_LIVE_MODEL` kullanılabilir. Gemini anahtarı Worker'da kalır. POST `/` ve `/speech` eski istemciler için korunur.

Yüz: CC0 Vitruvian anatomik model, taşınabilir glTF PBR kaplamaları ve gerçek FACS şekilleri. Kaynaklar `scripts/avatar_sources.json` içindeki commit ve SHA-256 değerlerine sabitlenir; `python scripts/fetch_avatar_sources.py` indirir ve doğrular. Credits: `assets/source/NOTICE-VITRUVIAN.md`. Blender aynı modeli hem mobil GLB hem Cycles önizlemeleri için kullanır. Ses seviyesine bağlı çene hareketi, fonem hizalaması değildir.

Güncelleme: uygulama açılışında GitHub Release kanalı kontrol edilir. Kullanıcı uygulama içinden günceller; Android kurulum onayı gerekir. Anahtar/parola değiştirilmez. Fiziksel telefon yankı/Bluetooth ve gecikme testleri ayrıca yapılmalıdır.

---

# MİMO · 0.6

Türkçe sesli sanal arkadaş. Normal ekranda yalnızca perspektifle çizilen, ışıklandırılmış geniş hatlı, insana benzeyen bir 3D yüz görünür. Model ve animasyonlar cihazda çalışır; dışarıdan 3D dosya indirmez.

## Kullanım

- Konuş: MİMO dinler, Gemini yanıtını seslendirir ve tekrar dinlemeye geçer.
- Yüzüne dokun: konuşmasını/isteğini kes ve yeniden dinle; uykudan uyandır.
- Yüzüne uzun bas: bağlantı ayarları. Önceki sürümün `endpoint`, `access`, `voice` ayarları aynı imzalı güncellemede korunur.
- “Uyu” / “dinlemeyi kapat”: dinlemeyi durdur. Dokunarak uyandır.
- “Kameraya bak”, “buna bak”, “bunu oku”: arka kamerayı nesneye çevir. Sesli bilgilendirmeden sonra tek kare gönderilir; kamera kapatılır, geçici fotoğraf silinir.
- “Geçmişi unut”: cihazda saklanan son 6 konuşmayı sil. Görüntüler geçmişte saklanmaz.
- “Güncelleme var mı?”: yeni APK kontrolü. “Yeni sürümü aç”: indirme sayfası.

Mikrofon/kamera yalnızca uygulama ön plandayken kullanılır. Android’in izin pencereleri ilk kullanımda görünür. Dinleme ile seslendirme sırayla çalışır: bu sürüm tam çift yönlü canlı ses/video değildir. Ağız hareketi TTS ilerlemesi ve hece benzeri animasyondur; fonem hassasiyetinde dudak eşleme değildir. Yüz gerçek anatomik baş topolojisine dayanır; stilize bir karakterdir. Modelden alınan Cycles render’ları sürüm dosyalarında yer alır. Fotogerçekçi insan veya tam fonem senkronizasyonu iddiası değildir.

## Ses akışı ve model

Varsayılan cihaz sesi yanıtı ikinci bir bulut ses isteğini beklemeden okur. Yüze uzun basılan ayarlardaki **Bulut sesi** seçeneği isteğe bağlıdır. Dinleme oturumları, geciken/çift sonuçlar ve geçici tanıma hataları için toparlanma kontrolü vardır. Fiziksel Android testi gereklidir.

`scripts/create_avatar.py`, `assets/source/human-head.obj` (MakeHuman CC0 temelinden çıkarılmış baş geometrisi) üzerinden Blender modeli, mobil glTF ve Cycles portrelerini üretir. CC0 metni aynı klasördedir. `scripts/validate_avatar.py` dışa aktarılan dosyadaki çene/göz kapağı hareketlerini kontrol eder. Blender 4.3.2 ve Flutter 3.47.8 derlemede sabitlenmiştir.

## Kolay güncelleme

`main` değiştiğinde **MIMO Android APK** iş akışı testleri ve analizi çalıştırır, APK üretir ve GitHub Releases’a `mimo-ai.apk` ekler. Aynı bağlantı her zaman en son başarılı sürümü gösterir:

https://github.com/srkntsn/M-MO/releases/latest

Android kurulumu kullanıcı onayı gerektirir. Sessiz/izinsiz APK kurulumu yapılmaz. Ayarların korunması için uygulama kimliği **ve imza anahtarı** aynı olmalıdır.

### Kalıcı imza

Bu depo test/debug APK üretir. İş akışı debug anahtarını cache içinde yeniden kullanır; cache silinir veya süresi dolarsa bu yeterli değildir. Uzun süreli güncellemeler için ilk kullanılan debug keystore'u güvenli bir yerde yedekleyip Base64 içeriğini depo Secret’ı `MIMO_DEBUG_KEYSTORE_BASE64` olarak ayarlayın. Dosyanın alias/parolası Android varsayılan debug değerleri olmalıdır (`androiddebugkey`, `android`). Anahtarı Git deposuna eklemeyin veya paylaşmayın. Play Store için ayrı release imzası gereklidir.

Eski APK farklı anahtarla üretilmişse ilk geçişte Android güncellemeyi reddedebilir. Kaldırmak ayarları/geçmişi siler; bağlantı bilgilerini önce güvenli biçimde kaydedin. İmza anahtarı olmadan bunun aşılması mümkün değildir.

## Backend güncellemesi

Yeni `backend/worker.js`, sesli sohbet kişiliğini ve tek kare görüntü isteğini destekler. Eski metin istemcileriyle uyumludur. Mevcut `GEMINI_API_KEY`, `MIMO_ACCESS_TOKEN`, isteğe bağlı `GEMINI_MODEL` değerlerini değiştirmeyin.

Cloudflare erişimi bu çalışma ortamına aktarılmadıysa Worker kendiliğinden güncellenmiş sayılmaz. İlk kurulum: mevcut Worker’ın **Edit code** ekranına `backend/worker.js` içeriğini yapıştırıp Deploy yapın.

Tekrarlayan kopyalamayı kaldırmak için deponun Actions Secrets alanında `CLOUDFLARE_API_TOKEN` (ilgili hesaba Workers düzenleme yetkisi) ve `CLOUDFLARE_ACCOUNT_ID` ayarlandığında **MIMO Worker Deploy** iş akışı sonraki backend değişikliklerini otomatik deploy eder. Bu sırlar yoksa akış deploy’u açıkça atlar. Token üretimi ve yetkilendirmesi kullanıcı tarafından yapılmalıdır. İş akışı mevcut Worker Secrets değerlerini oluşturmaz/değiştirmez/silmez; `keep_vars` dashboard değişkenlerini de korur.

## Doğrulama

```
flutter pub get
flutter analyze lib test
flutter test
node --test backend/*.test.mjs
```

Fiziksel telefonda: sessizlikten sonra yeniden dinleme, mikrofon izni reddi, arka plana alıp dönme, konuşmayı dokunarak kesme, kamera izni reddi, kamera kare analizi ve aynı imzayla güncelleme ayrıca denenmelidir. Birim/render testleri mikrofon veya kamera donanımını doğrulamaz.

Gemini ağ bağlantısı, kullanılabilir model ve kotaya bağlıdır; sınırsız/ömür boyu hizmet garantisi yoktur.
