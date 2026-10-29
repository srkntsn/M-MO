# MİMO — kullanıcı talepleri ve kabul koşulları

29 Ekim 2026 görüşmesinde Serkan tarafından belirtilen kapsam. Bu kayıt, tamamlanmış iş iddiası değildir.

## Bu geliştirmede beklenen deneyim

1. Ana ekranda yalnızca yüz: yazışma alanı ve görünür sohbet düğmeleri olmasın.
2. Varsayılan deneyim “aç ve konuş”: teknik bilgi, sunucu adresi, ortak parola veya API anahtarı gerekmesin. Hazır MİMO güçlü olmalı; “basit” yalnızca kullanım kolaylığını anlatır.
3. Sıcak, esprili, ilgili sohbet; bağlamı takip etsin. Sırf kullanıcıyı memnun etmek için yanlış bilgiyi onaylamasın.
4. Dinleme konuşma sonunda kendiliğinden ve hızlı dönsün; yüzüne dokununca kesme mevcut test mekanizmasıdır. Mikrofon geç açılma ve gecikme ölçülüp giderilsin.
5. İlk açılışta mikrofon ve kamera izinlerinin amacı açıklansın; Android izinleri istensin. Reddedilen izin ve tekrar açma yolu açık olsun.
6. Ön ve arka kamera sesli seçilebilsin. “Beni görebiliyor musun” ön kameraya yönelsin. İzin kamera kullanımıyla aynı şey değildir: kamera yalnızca komutla açılır.
7. Her iki kamerada görüntü gönderilmeden küçültülüp sıkıştırılsın. Büyük fotoğraf hatası sonsuz tekrar/konuşma döngüsüne sokmasın.
8. Yüz daha insansı oranlarda, dikey ekranı daha çok kaplayacak ve yüksek kalitede olsun. Blender gibi gerçek bir modelleme/render programı KULLANILSIN; yalnızca mevcut geometrik çizim yeniden adlandırılmasın.
9. Üst/alt dudaklar ve çene belirgin olsun, konuşma sesiyle uyumlu hareket etsin. Rastgele ağız açma gerçek dudak senkronizasyonu diye sunulmasın.
10. Doğal Türkçe ses ve hızlı etkileşim öncelikli. Gerekli araçlar araştırılabilir; ücretli hizmet veya yeni anahtar gerektiğinde somut gereksinim belirtilecek.
11. Güncelleme basitleştirmesi ERTELENMESİN: kullanıcı her seferinde GitHub dosyası/ayar aramamalı. Bağlantı ve cihaz kimliği güncellemede korunsun. Test dağıtımı ve Play güncellemesi birbirinden ayrı tasarlanmalı.
12. Şimdilik iki kişi test edecek. Ortağı adres/parola yazmadan etkinleşebilsin. Özel davet test aracıdır; genel mağaza kullanımı için davet zorunluluğu olmayacak.
13. Son düzgün sürüm Google Play Store'da satılacak. Mağaza sürümü Play mekanizmasıyla güncellenecek; dışarıdan APK güncellemesi kullanılmayacak.
14. Büyüyebilen mimari hedefleniyor. Milyonlarca eşzamanlı kullanım mevcut kapasite olarak ilan edilmeyecek; sağlayıcı kotaları, bütçe, yetkilendirme ve yük testleriyle doğrulanacak.
15. Gelişmiş ayarlarda isteğe bağlı kendi yapay zekâ sağlayıcısını/API hesabını bağlama seçeneği olsun. Kendi kullanım ücreti kullanıcıya ait olduğu açıkça anlatılsın. Hazır hizmete geri dönüş kolay olsun. Bu seçenek normal kullanıcı akışını zorlaştırmasın.

## Çalışma ve teslim biçimi

- Kullanıcı eksikleri kullandıkça iletecek; sonraki sürümlerde düzeltilecek.
- Kullanıcının “bunu da yap” dediği talep sessizce gelecek yol haritasına atılmayacak. Bitmeyen veya erişim gerektiren işler açıkça belirtilecek.
- Hazırlanan kod, geçen testler, üretilen APK, sunucu dağıtımı ve telefon testi ayrı ayrı raporlanacak.
- Tahmini süre kesin teslim sözü gibi verilmeyecek. İşlem çalışmıyorken arka planda sürüyormuş gibi anlatılmayacak.
- “Bekle” işi duraklatır; “konuşma” sözlü güncellemeleri durdurur. Açıkça iptal edilmedikçe önceden yetkilendirilmiş iş silinmez.
