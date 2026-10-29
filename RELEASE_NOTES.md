MİMO 0.6 — geniş insan yüzü ve daha dayanıklı sesli sohbet (Android test sürümü)

- MakeHuman'ın CC0 anatomik baş temelinden düzenlenmiş geniş yüz: gerçek burun, yanak, çene, göz kapakları ve dudak topolojisi; ayrı göz, iris, dil ve üst-alt diş geometrisi.
- Blender 4.3.2 ile aynı modelden alınan gerçek Cycles render’ları indirmelere eklendi. Uygulama içindeki glTF modeli hareketlidir; bu bir fotogerçekçi insan veya tam fonem senkronizasyonu iddiası değildir.
- Çene ve göz kapağı hareketlerinin mobil dışa aktarmada kaybolmasını engelleyen model doğrulaması.
- Model yüklenirken boş ekran yerine gerçek render; yüzün JavaScript güncellemelerinde birikmeyi önleyen sınırlandırma.
- Varsayılan hızlı cihaz sesi. Yüze uzun basılan ayarlarda Bulut sesi isteğe bağlıdır; başarısız/geciken ses üretimi ve oynatımı sınırlanır ve cihaz sesine dönülür.
- Sessizlikten sonra dinlemeyi yeniden başlatan kontrol; geç gelen/eski ve çift sonuçların ayıklanması; geçici ses hizmeti hatasından toparlanma.
- Eksik Gemini modeli için başarılı alternatif seçimi 30 dakika bellekte tutulur; her konuşmada katalog isteği tekrarlanmaz. Backend güncellemesi gerektirir; mevcut Secrets değiştirilmez.

Mevcut uygulamayı kaldırmayın: aynı imzalı APK’yı üzerine kurun. Uygulama içindeki “güncelle” komutu da kullanılabilir. İmza uyuşmazlığı varsa ayarları yedeklemeden uygulamayı kaldırmayın.

Derleme, analiz, birim ve dışa aktarma kontrolleri gerçek telefondaki mikrofon/kamera testinin yerine geçmez. Android’in ses tanıması kısa oturumlarla çalışır; bu sürüm tam çift yönlü canlı ses değildir. Gemini’nin ağ/kota/model koşulları geçerlidir.
