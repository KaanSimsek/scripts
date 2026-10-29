---
name: disk-cleanup
description: Use when the user wants to free up disk space on their Mac (disk alanı açma, yer açma, temizlik) or asks to find/remove caches, logs, Xcode build data, npm caches, Trash contents, or files larger than 1 GB. This skill runs the repository's cleanup.sh safely: list first, then delete only the exact items the user approved.
---

# Disk Cleanup

Bu beceri, repo kökündeki `cleanup.sh` betiğini güvenli biçimde kullanır. Betik
önce tarar, sonra yalnızca açıkça onaylanan öğeleri siler. Varsayılan davranış
hiçbir şeyi silmemektir.

## Temel kural

Kullanıcı belirli kimlikleri (ID) onaylamadan hiçbir şey silme. "Yer aç" veya
"temizle" demek silme izni değildir; önce bulguları göster ve neyin silineceğini
sor. Emin değilsen tekrar sor.

## İş akışı

1. Repo kökünü bul ve betiğin varlığını doğrula:

   ```bash
   git rev-parse --show-toplevel
   ./cleanup.sh --help
   ```

   Betik yoksa kullanıcıya söyle; kendi başına silme komutları yazma.

2. Makine tarafından okunabilir raporu al (yavaş olabilir, 1 GB üstü dosyaları
   tarar):

   ```bash
   ./cleanup.sh --json
   ```

   `jq` varsa `jq .` ile, yoksa `python3 -m json.tool` ile doğrula. JSON alanları:
   `disk`, `total_reclaimable_kb`, `items[]` (`id`, `kind`, `name`, `path`,
   `size_kb`, `entries`). `kind` değeri `category` (bilinen önbellek/log) veya
   `file` (1 GB üstü tek dosya) olur.

3. Bulguları kullanıcıya kısa bir tablo halinde göster: disk doluluk yüzdesi,
   toplam temizlenebilir alan ve en büyük birkaç öğe (ID, boyut, yol). Tüm
   listeyi boğmadan özetle; kullanıcı isterse tamamını göster.

4. Kullanıcıya iki soruyu birlikte sor:
   - Hangi ID'ler silinsin? (örn. `2,7,12`)
   - Çöpe mi taşınsın (geri alınabilir), kalıcı mı silinsin?

   Varsayılan öneri çöpe taşımaktır. Kalıcı silmeyi yalnızca kullanıcı açıkça
   "kalıcı sil" derse kullan. Kullanıcı ID vermeden "hepsini sil" derse, önce
   hangi öğelerin dahil olduğunu listeleyip tekrar onay al.

5. Onaylanan işlemi çalıştır:

   ```bash
   ./cleanup.sh --trash 2,7,12
   # veya yalnızca açık onay varsa:
   ./cleanup.sh --delete 2,7,12 --yes
   ```

6. Sonucu bildir: temizlenen boyut ve kalan alan. Çöpe taşındıysa, alanın
   gerçekten boşalması için Çöp Kutusu'nun boşaltılması gerektiğini hatırlat.
   Kullanıcı isterse Çöp Kutusu'nu boşaltmak için `--trash 1` kullanılabilir;
   bunun geri alınamaz olduğunu söyle.

## Komut özeti

| Komut | Etki |
| --- | --- |
| `./cleanup.sh --list` | İnsan okunur rapor, silme yok |
| `./cleanup.sh --json` | Makine okunur rapor, silme yok |
| `./cleanup.sh --trash <idler>` | Seçilenleri Çöpe taşır |
| `./cleanup.sh --delete <idler> --yes` | Seçilenleri kalıcı siler |
| `./cleanup.sh` | Etkileşimli mod (yalnızca gerçek terminalde) |

ID'ler her çalıştırmada yeniden numaralanır. Bir raporda gördüğün ID'yi başka
bir çalıştırmada kullanma; silmeden hemen önce taze rapor al veya aynı
çalıştırmadaki ID'leri kullan.

## Güvenlik sınırları

- `sudo` kullanma. Betik yalnızca kullanıcının ev dizinini temizler.
- `--delete` komutunu kullanıcı onayı olmadan çalıştırma; `--yes` bayrağını
  kullanıcı adına kendiliğinden ekleme.
- `~/Library/CloudStorage`, sistem dizinleri ve ev dizini dışındaki yolları
  silme. Betik büyük dosya taramasında CloudStorage'ı zaten atlar.
- Betiğin onay kontrollerini, güvenlik denetimlerini veya `--yes` zorunluluğunu
  değiştirme.
- Kullanıcı "hepsi" derse bunun tüm kategorileri kapsadığını, 1 GB üstü büyük
  dosyaları kapsamadığını açıkla.
- Emin olmadığın bir dosya kullanıcı verisi olabilir (Xcode Archives, uygulama
  desteği, büyük medya). Boyutu ve yolunu gösterip kararı kullanıcıya bırak.

## İpuçları

- Eşiği değiştirmek için: `LARGE_FILE_GB=5 ./cleanup.sh --json`
- Listelenecek büyük dosya sayısı: `MAX_LARGE_FILES=50 ./cleanup.sh --json`
- Betik çıktısı Türkçedir; kullanıcıya da Türkçe yanıt ver.
- Çıktı boru hattında (`| head`) kullanılırsa `SIGPIPE` görülebilir; raporu
  dosyaya yönlendirip (`> /tmp/cleanup.json`) sonra oku.
