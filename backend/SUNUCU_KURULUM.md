# İlk uzak backend kurulumu

## Durum ve kapsam

Bu belge tekrarlanabilir kurulum hazırlığını tanımlar; gerçek sunucu, DNS, HTTPS
sertifikası veya dış ağdan erişim kurulmuş/doğrulanmış değildir. 25 Ekim 2026'da
kullanıcı aşağıdaki image/deployment kontrollerini çalıştırıp geçtiğini bildirdi;
bu sonuçlar Compose servislerinin birlikte çalıştığını veya dış erişimi kanıtlamaz.
Kurulum yalnız `backend/` içindeki API içindir. Mobil paket videoları ve
uygulamanın belge dizinindeki video kopyaları sunucuya taşınmaz.

| Hazırlanan | Kullanıcı bildirimiyle doğrulanan | Sunucu gelince yapılacak |
|---|---|---|
| Node Dockerfile, lockfile tabanlı kurulum, kanonik kart kaynağı | Linux Docker image build; deployment `createApp` yükleme kontrolü; yeniden image içinde `npm audit --omit=dev` sonucu 0 açık; aynı ağ kapalı image içinde 86 backend testi | Ubuntu sunucusu, alan adı ve güvenlik duvarı |
| Backend için dışa port açmayan Compose servisi | `docker compose config --quiet` | Compose servislerinin birlikte çalışması ve proxy üzerinden HTTP erişimi |
| Caddy ters proxy, HTTPS otomatik sertifika yapılandırması ve health check | `caddy:2.11.7-alpine` ile ağ kapalı `caddy validate`: `Valid configuration` | DNS, dış health/erişim kontrolleri, sertifika edinimi |
| Log döndürme, yeniden başlatma ve kalıcı Caddy volume’ları | `package-lock.json` içindeki body-parser güvenlik düzeltmesinin npm ile güncellenmesi | Gerçek sağlayıcı isteği, yedekten geri yükleme uygulaması |

Bu doğrulamalar kullanıcı tarafından 25 Ekim 2026'da bildirildi; bu oturumda
yeniden çalıştırılmadı. `npm audit` ve backend testleri aynı yeniden oluşturulmuş
image içinde, ağ erişimi kapalıyken çalıştırılmıştır.

## Çalışma biçimi ve endpoint’ler

Backend kodu, `package-lock.json` içindeki Gemini SDK’sının Node `>=18` şartını
karşılayan **Node 24.21.0 LTS** taban imajını kullanır. Lockfile sürümü 3’tür;
imaj `npm ci --omit=dev` çalıştırır. `package.json` içinde development
bağımlılığı yoktur. Tam Node dalı yerine belirli imaj etiketi kullanılmıştır;
güncelleme öncesi resmi Node yayın takvimini ve imaj etiketini yeniden kontrol
edin ([Node yayın takvimi](https://nodejs.org/en/about/previous-releases),
[resmi Node imajı](https://hub.docker.com/_/node)). Caddy imajı da sabit etikettir;
güncellemeden önce [resmi Caddy imajını](https://hub.docker.com/_/caddy) ve
[otomatik HTTPS gereksinimlerini](https://caddyserver.com/docs/automatic-https)
kontrol edin.

Docker imajına yalnız gerekli backend JS modülleri, doğrulayıcılar ve tek
kanonik `resources/Davranis_Kartlari_v02.md` dosyası kopyalanır. `.dockerignore`
`.env`, bağımlılık klasörü, testler, loglar, Git içeriği, mobil dosyalar ve medya
dosyalarını dışlar. Uygulama resmi Node imajındaki `node` kullanıcısıyla çalışır.

Compose iki servis başlatır:

| Servis | İşlev / erişim |
|---|---|
| `backend` | Node API, yalnız Compose ağı içindeki TCP 8000; host portu yayımlanmaz. Sağlık kontrolü dahili `/health` isteğidir. |
| `caddy` | Tek ters proxy; hosta TCP 80/443 ve UDP 443 (HTTP/3) yayımlar, HTTPS sertifikasını alan adı için otomatik yönetir. |

`BACKEND_MODE=deployment` modunda:

| Yol | Durum |
|---|---|
| `GET/HEAD /health` | Açık; anahtar ve kapasite kullanmaz. `online`, Node/Express yanıt verdiğini gösterir; Gemini anahtarı/model erişimini göstermez. |
| `POST /api/generate-scenario-input` | Açık; Bearer ekip anahtarı, 1 MiB JSON sınırı, ortak kapasite ve 90 saniyelik sağlayıcı bekleme sınırı. |
| `POST /api/compare-scenario` | Açık; aynı erişim/gövde/kapasite/timeout korumaları. Önizleme sağlayıcı çağırmaz; kullanıcı ayrıca üretimi başlatır. |
| `POST /api/generate-clip-plan` | Açık; aynı korumalar ve güncel graf/plan doğrulaması. |
| Eski `/api/generate-scenario`, `/api/analyze-video` ve diğer yollar | Deployment filtresinde sağlayıcıya veya dosya yüklemeye ulaşmadan 404. Kodları silinmemiştir. |

Üç açık üretim yolunun modeli `SCENARIO_INPUT_MODEL` ile seçilir; bu ayar
Gemini sağlayıcısı içindeki model kimliğidir, sağlayıcı seçicisi değildir.
`gemini_text.js` mevcut sağlayıcı adaptörüdür ve `GEMINI_API_KEY` ister.
Başka sağlayıcıya geçişte bu adaptör, ham metin/usage/hata sözleşmesini
koruyacak biçimde ayrıca değiştirilip test edilmelidir; bugün yalnız ortam
değişkeniyle başka sağlayıcıya geçilemez. Otomatik başka model/örnek sonuç
yoktur.

Mevcut kapasite varsayılanı tek Node sürecinde 1 eşzamanlı sağlayıcı işidir;
bu bir aylık harcama sınırı, istek hızı sınırı veya çoklu süreç kotası değildir.
Backend sağlayıcı zaman aşımı 90 saniyedir. Caddy upstream yanıt başlığı
zaman aşımı 105 saniyedir; böylece backend’in 90 saniyelik hata yanıtına pay
bırakılır. Mobil HTTP istemcisinin beklemesi 100 saniyedir. Timeout veya istemci
bağlantısının kapanması sağlayıcı işinin durduğunu kanıtlamaz ve kapasite slotu
sağlayıcı Promise’ı bitmeden serbest kalmaz.

## Ubuntu sunucuyu hazırlama

Aşağıdaki komutlar **Linux Ubuntu sunucusunda** çalıştırılır. `<...>` yer
tutucularını gerçek değerlerle değiştirin; komutlara anahtar/parola koymayın.

### 1. DNS ve SSH

Önce alan adının A kaydını sunucu IPv4 adresine yönlendirin. IPv6 tam çalışır
değilse AAAA kaydı yayımlamayın. DNS dışarıdan çözülmeden ve 80/443
erişilemeden Caddy sertifika alamaz. Bu görevde DNS değişikliği yapılmadı.

SSH anahtarıyla, yönetici IP/CIDR’si sınırlandırılmış şekilde bağlanın:

```powershell
# Windows PowerShell — kendi SSH anahtarınız ve kullanıcı/host adınızla
ssh <SSH_KULLANICISI>@<SUNUCU_IP>
```

İlk girişten sonra sunucuda Ubuntu güvenlik güncellemelerini uygulayın:

```bash
# Linux sunucu
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y ca-certificates curl git openssl gnupg
```

### 2. Docker Engine ve Compose

Docker’ın resmi Ubuntu apt deposunu kullanın; kolaylık kurulum betiği üretim
kurulumu için önerilen yol değildir. Resmi adımları ve Ubuntu sürüm desteğini
[Docker Engine Ubuntu kurulum belgesinden](https://docs.docker.com/engine/install/ubuntu/)
kontrol edin. Güncel deb822 depo kurulumu:

```bash
# Linux sunucu — Docker resmi apt deposu
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world
docker compose version
```

Docker daemon erişimi root yetkisine denktir; sıradan uygulama hesabını
`docker` grubuna eklemenin bu yetkiyi verdiğini kabul edin. Kurulum için
`sudo docker ...` kullanın veya kurumunuzun onaylı rootless Docker düzenini
ayrıca kurun.

### 3. Ağ güvenlik duvarı

Bulut sağlayıcısının ağ güvenlik duvarında yalnız şunları açın:

- TCP 22: sadece yönetici IP/CIDR’si.
- TCP 80 ve 443: genel erişim (ACME HTTP doğrulaması ve HTTPS).
- UDP 443: Caddy HTTP/3 kullanılacaksa; kullanılmayacaksa Compose port
  yayımlamasını ve bu kuralı birlikte kaldırın.
- TCP 8000: **açmayın**. Compose bu host portunu zaten yayımlamaz.

Sunucudan dışarı DNS çözümleme (UDP/TCP 53) ve HTTPS (TCP 443) erişimi gerekir:
Docker imaj/paket indirmeleri, Gemini API ve Caddy ACME sertifika işlemleri bu
çıkışları kullanır. Kurum ağı bu çıkışları kısıtlıyorsa gereken hedefleri ve
kuralları dağıtım öncesi doğrulayın; burada sağlayıcı IP listesi sabitlenmemiştir.

UFW kullanıyorsanız SSH erişimini doğrulamadan etkinleştirmeyin. Önce yönetici
kuralını ekleyin; bulut güvenlik duvarını da ayrıca ayarlayın:

```bash
# Linux sunucu — <YONETICI_CIDR> yerine sabit yönetici IP/CIDR'si
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from <YONETICI_CIDR> to any port 22 proto tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
sudo ufw enable
sudo ufw status verbose
```

Docker’ın hosta yayımladığı portlar bazı UFW kurallarını atlayabilir. Bu
Compose’ta yalnız proxy portları yayımlanır; ayrıca bulut firewall’ını gerçek
dış sınır olarak kullanın ve Docker/iptables kural yapısını dağıtım öncesi
kontrol edin. IPv6 açıksa güvenlik kurallarını onun için de doğrulayın.

### 4. Kaynağı ve ortam dosyasını hazırlama

Backend kodunu onaylanmış Git deposundan sunucuya alın ve **dağıtılacak commit**
ile sabitleyin. Özel depo için kurumun onaylı SSH/deploy-key yöntemini kullanın;
anahtarı komuta, Git remote URL’sine veya depoya koymayın.

```bash
# Linux sunucu — yer tutucular
git clone <ONAYLI_REPO_SSH_URL> /opt/norogelisim
cd /opt/norogelisim
git checkout --detach <DAGITILACAK_COMMIT>
cd backend
```

İlk kurulumda şablonu gizli izinlerle kopyalayın. Güncellemede mevcut `.env`
dosyasının üzerine `.env.example` kopyalamayın:

```bash
# Linux sunucu, backend/ içinde
umask 077
cp .env.example .env
chmod 600 .env
openssl rand -hex 32
```

`openssl rand` çıktısını güvenli bir parola kasasında/terminalde saklayın ve
`.env` düzenleyicisine elle aktarın. `cat .env`, `docker compose config` çıktısı,
debug logu veya ekran paylaşımıyla sırları göstermeyin. `.env` Git’te yok sayılır
ve Docker build context/image’ına alınmaz; Compose onu yalnız çalışma anında
backend container’ına geçirir.

`.env` içindeki gerekli değerleri şöyle ayarlayın:

| Değişken | Uzak deployment değeri / anlamı |
|---|---|
| `BACKEND_MODE` | `deployment`; Compose bunu ayrıca zorlar. |
| `PORT` | `8000`; yalnız container ağı içinde. |
| `PUBLIC_DOMAIN` | DNS’e yöneltilmiş gerçek API hostname’i; `api.example.invalid` yer tutucusunu bırakmayın. |
| `TEAM_ACCESS_KEY` | `openssl rand -hex 32` ile oluşturulmuş, boşluksuz gizli ekip anahtarı. Sunucu ortamı dışında paylaşmayın. |
| `GENERATION_MAX_CONCURRENT` | Pozitif tam sayı; varsayılan `1`, tek Node süreci için. Aylık maliyet limiti değildir. |
| `GEMINI_API_KEY` | Sunucu ortamında sağlayıcı anahtarı; yalnız backend kullanır. |
| `SCENARIO_INPUT_MODEL` | Gemini hesabında kullanılabilen model kimliği. Üç güncel üretim yolu bunu paylaşır. |
| `BEHAVIOR_CARDS_PATH` | Boş bırakılırsa image içindeki kanonik kart dosyası kullanılır. Açık override varsa container içinde gerçekten mevcut olmalıdır. |

`PUBLIC_DOMAIN` Compose tarafından proxy container’ına, diğer değerler backend’e
verilir. `TEAM_ACCESS_KEY` boşsa backend başlangıçta hata verir. Sağlayıcı/model
ayarı eksikse `/health` yine `online` dönebilir; üretim endpoint’inde açık
yapılandırma hatası alınır. Health’i model testi saymayın.

### 5. Yapılandırmayı kontrol etme ve başlatma

```bash
# Linux sunucu, backend/ içinde; -q sırları ekrana dökmez
docker compose config -q
docker compose build --pull
docker compose up -d
docker compose ps
docker compose logs --tail=80 backend caddy
curl --fail --silent --show-error https://<PUBLIC_DOMAIN>/health
```

`docker compose ps` backend’i `healthy` göstermelidir. `/health` JSON’undaki
`status: online`, yalnız uygulamanın yanıt verdiğini belirtir. HTTP portu 80’den
HTTPS’e yönlendirme, TLS sertifikası ve dış ağdan HTTPS health ayrıca kontrol
edilmelidir. `docker compose logs` sağlayıcı hata kategorilerini içerebilir;
Authorization başlığı, anahtar, prompt, ham cevap veya çocuk/kişi bağlamı
loglanmamalıdır. Caddy erişim loglama yönergesi özellikle ekli değildir.

Sağlık kontrolü ücretli üretim çağrısı yapmaz. Modelin gerçekten erişilebilir
olduğunu kabul öncesi sınamak için ekip anahtarıyla **tek bir açık üretim isteği**
gönderin; bu sağlayıcı kullanımı/kota tüketebilir. A/B/C önizlemesi model çağrısı
yapmaz; üretim eylemi yapar. Benchmark veya otomatik tekrar başlatmayın.

### 6. Mobil uygulamayı uzak HTTPS adresine bağlama

Uygulamada **Simülasyon ve Eğitim → Stüdyo → Sunucu ayarları** alanından tam
`https://<PUBLIC_DOMAIN>` adresini girip kaydedin. `ServerApiService.setBaseUrl`
değeri cihazın `SharedPreferences` alanında `custom_server_base_url` olarak
saklar; sonraki açılışlarda bu kayıt varsayılan `http://10.0.2.2:8000` emülatör
adresinin üzerine geçer. Eski kayıtlı adres varsa yeni HTTPS adresini elle
kaydedin; uygulama bunu sunucudan otomatik keşfetmez. “Bağlantıyı dene” yalnız
health yanıtını kontrol eder, Gemini modelini doğrulamaz.

Ekip anahtarını Stüdyo’daki gizli alana girin. Uygulama bunu yalnız mevcut
oturum belleğinde tutar; tercihlere/taslağa kaydetmez. Senaryo, A/B/C ve klip
planı istekleri aynı Bearer anahtarını kullanır. Ekran yeniden açılırsa yeniden
girilmesi gerekir. Bu ortak anahtar kullanıcı/rol hesabı veya kişi bazında iptal
sistemi değildir.

Bugünkü deployment’ta anlatı üretimi, A/B/C ve klip planı backend/Gemini
tarafındadır; graf dönüştürme mobilde yereldir. Video seçme, yerel kopyalama,
önizleme ve D01/D02 oynatma mobil cihazdadır. Deployment’ta video yükleme,
sunucudan video oynatma, FFmpeg, video üretimi ve gerçek video analiz servisi
yoktur. Eski video analiz endpoint’leri dış modda kapalıdır.

## Güncelleme ve geri dönüş

Her dağıtımda önce çalışan commit’i not edin; yeni kaynakta `.env` ve Caddy
volume’larını koruyun. Git checkout/merge sırasında `.env`’yi silmeyin veya
yeniden şablonla ezmeyin.

```bash
# Linux sunucu — yeni, önceden gözden geçirilmiş commit
cd /opt/norogelisim
git rev-parse HEAD
git fetch --all --tags
git checkout --detach <YENI_ONAYLI_COMMIT>
cd backend
docker compose build backend
docker compose up -d --no-deps backend
docker compose up -d caddy
docker compose ps
curl --fail --silent --show-error https://<PUBLIC_DOMAIN>/health
```

Yerel `test/deployment_smoke.ps1`, istekleri backend container’ındaki Node
`fetch` ile `http://caddy` adresine göndererek proxy zincirini sınar; Windows
hostundan loopback/port erişimini bu test doğrulamaz. Gerçek endpoint smoke
check’i bilinçli ve tek üretim isteği olmalıdır; benchmark veya otomatik tekrar
başlatmayın. Bu istek sağlayıcı kotası tüketebilir. Erişim anahtarsız/yanlış
istek 401, eski analiz/26-sahne yolları deployment’ta 404 vermelidir.

Geri dönüş için dağıtım öncesi commit’i kullanın ve aynı Compose tanımıyla
imajı yeniden kurun. Server’da uygulama sonucu/veritabanı migrasyonu olmadığı
için kod rollback’i veri şeması geri dönüşü gerektirmez:

```bash
# Linux sunucu — <ONCEKI_COMMIT> dağıtım öncesi kaydedilen hash
cd /opt/norogelisim
git checkout --detach <ONCEKI_COMMIT>
cd backend
docker compose build backend
docker compose up -d --no-deps backend
docker compose up -d caddy
docker compose ps
```

`docker compose down -v` kullanmayın; bu Caddy sertifika/config volume’larını
siler. Normal `down` container’ları durdurur ama volume’ları bırakır.

## Yedekleme ve kurtarma

Backend’de üretim cevapları veya ölçüm kayıtları kalıcı sunucu dosyasına
yazılmaz; ölçümler yanıtla döner, production’da ölçüm callback’i/dosya arşivi
yoktur. Video dosyası yükleme/kalıcı video deposu deployment kapsamına açık
değildir. Uygulama taslakları ve video eşlemeleri cihazın yerel saklamasında
kalır; bu sunucu yedeğine dahil değildir. Gerçek sunucu kurtarması için:

1. Dağıtılmış Git commit/hash’i ve `backend/` Compose/Caddy/Docker yapılandırması
   uzaktaki Git deposundan geri alınabilir.
2. `.env` içindeki provider ve ekip sırlarını sunucu dışında, şifreli bir yedek
   konumunda tutun. Aşağıdaki örnek GPG parolayı etkileşimli sorar;
   çıktı yolu gerçekten sunucu dışında ve erişimi sınırlı şifreli bir mount olmalı:

```bash
# Linux sunucu; yer tutucuyu bağlı, sunucu dışındaki korumalı konumla değiştirin
umask 077
gpg --symmetric --cipher-algo AES256 \
  --output <SIFRELI_DIS_YEDEK>/backend-env-$(date +%F).gpg .env
```

   Kurtarmada GPG parolasını girin ve dosyayı doğrudan backend `.env` konumuna
   çözün; `umask 077` izinleri kısıtlar. Yetkili kişiyle güvenli editörde
   doğrulayın; içeriği terminale yazdırmayın:

```bash
# Linux sunucu — backend dizininde
umask 077
gpg --decrypt --output .env <SIFRELI_DIS_YEDEK>/backend-env-<TARIH>.gpg
chmod 600 .env
```
3. `norogelisim_caddy_data` volume’u Caddy’nin sertifika özel anahtarlarını
   içerir. Aynı hosttaki güncellemelerde volume korunur. Host kaybında DNS/80/443
   hazırsa sertifikayı yeniden almak mümkündür; bunun için ACME sağlayıcısının
   sınırları geçerlidir. Volume yedeği tutulacaksa onu da şifreli, sunucu dışı
   depoda saklayın; bu volume’u normal `down` sırasında silmeyin.
   Caddy’yi durdurup iki volume’u ayrı ayrı doğrudan şifreli dış yedeğe aktarın;
   aşağıdaki komutlar arşivi diskte açık bırakmaz ve GPG parolayı etkileşimli
   ister:

```bash
# Linux sunucu — hedef, sunucu dışında bağlı ve erişimi kısıtlı yedek mount'u olmalı
docker compose stop caddy
umask 077
docker run --rm -v norogelisim_caddy_data:/data:ro --entrypoint sh caddy:2.11.7-alpine \
  -c 'tar -C /data -czf - .' \
  | gpg --symmetric --cipher-algo AES256 --output <SIFRELI_DIS_YEDEK>/caddy-data-$(date +%F).gpg
docker run --rm -v norogelisim_caddy_config:/data:ro --entrypoint sh caddy:2.11.7-alpine \
  -c 'tar -C /data -czf - .' \
  | gpg --symmetric --cipher-algo AES256 --output <SIFRELI_DIS_YEDEK>/caddy-config-$(date +%F).gpg
docker compose start caddy
```

   Geri yüklemeden önce Caddy’yi durdurun. Doğru volume’a açın; GPG parolayı
   sorar. Volume arşivlerinin içeriği sertifika özel anahtarlarını kapsar:

```bash
# Linux sunucu — yedek dosyaları sunucu dışı korumalı konumdan okunur
docker compose stop caddy
gpg --decrypt <SIFRELI_DIS_YEDEK>/caddy-data-<TARIH>.gpg \
  | docker run --rm -i -v norogelisim_caddy_data:/data --entrypoint sh caddy:2.11.7-alpine \
      -c 'tar -C /data -xzf -'
gpg --decrypt <SIFRELI_DIS_YEDEK>/caddy-config-<TARIH>.gpg \
  | docker run --rm -i -v norogelisim_caddy_config:/data --entrypoint sh caddy:2.11.7-alpine \
      -c 'tar -C /data -xzf -'
docker compose start caddy
```

   Hedef volume önceden boş değilse geri yükleme öncesi içeriği kontrollü olarak
   temizleyin; volume adını ve yedek tarihini iki kişiyle doğrulayın. Şifreli
   arşivleri ve parolayı aynı yerde saklamayın.
4. Yeni hostta seçilmiş commit’i alıp aynı `.env`’yi güvenli biçimde geri
   yükleyin. Compose başlatın; Caddy volume’u geri yüklendiyse sertifika/config
   korunur, yüklenmediyse Caddy yeniden sertifika edinir. Önce `/health`, sonra
   dış HTTPS ve erişim kontrollerini yapın.

Kod yedeği (Git commit) ile veri/secret yedeği birbirinin yerine geçmez.
Şifreli `.env` yedeği erişim anahtarını ve sağlayıcı yetkisini taşır; kaybolursa
anahtarları sağlayıcıda döndürüp yeni değerleri kontrollü dağıtın. Bu kodda
aylık harcama tavanı yoktur. Tek süreçli eşzamanlılık sınırı sadece aynı anda
çalışan işleri sınırlar; Gemini proje kotası/ücret uyarısı veya hard budget
garantisi değildir. Sağlayıcı konsolunda güncel kota/harcama kontrolleri ayrıca
ayarlanmalıdır.

## Taşıma ve sonraki sağlayıcı

Ubuntu hostu veya Docker destekli başka bir hosta geçerken aynı onaylı Git
commit’ini ve kilitli backend image build’ini kullanın; `.env`’yi şifreli kanal/
depo dışında aktarın, Caddy DNS kaydını yeni IP’ye taşıyın ve host güvenlik
duvarını yeniden kurun. Kalıcı uygulama verisi taşınmaz; Caddy sertifikası ya
korunan volume’dan geri alınır ya da yeniden edinilir.

Başka model kimliği için `SCENARIO_INPUT_MODEL` değişebilir; yalnız mevcut
Gemini sağlayıcısında kullanılabilir bir model adı olmalıdır. Başka sağlayıcı
veya kendi model sunucusu için `gemini_text.js` adaptörü ve ortam sözleşmesi
değiştirilip kontrollü test edilmeden eşdeğer taşınabilirlik yoktur. CPU/RAM/GPU,
eşzamanlı kullanıcı ve maliyet kapasitesi bu projede ölçülmemiştir; sunucu
boyutu bu belgeden tahmin edilmemelidir.

## İlk sunucu kabul listesi

- [ ] Dağıtım commit’i sabitlenmiş; `.env` Git’te değil ve izinleri sınırlı.
- [ ] DNS A/isteğe bağlı AAAA, HTTPS sertifikası ve TCP 80/443 dışarıdan
      doğrulandı; TCP 8000 dışarıdan kapalı.
- [ ] `docker compose ps` backend’i healthy gösteriyor; HTTPS `/health` 200.
- [ ] Health anahtar/model erişimi kanıtı sayılmıyor.
- [ ] Eksik/yanlış Bearer 401; eski 26-sahne/analiz yolları 404; gövde sınırı
      ve ortak kapasite kontrollü olarak ayrıca denetlendi.
- [ ] Tek, ekipçe onaylanmış üretim isteğiyle doğru model/anahtar cevabı,
      süre ve sağlayıcı maliyeti kontrol edildi; otomatik tekrar/benchmark yok.
- [ ] Loglarda anahtar, Authorization, prompt, ham cevap veya kişisel bağlam yok;
      log döndürme ve şifreli sunucu dışı yedek/geri yükleme adımları denendi.
- [ ] Mobilde kayıtlı eski URL güncellenip HTTPS health ve oturumluk ekip anahtarı
      ile tek açık işlem doğrulandı.

Kabul listesinin tamamı henüz geçilmiş değildir. Yukarıdaki kullanıcı bildirimiyle
image, deployment yükleme, bağımlılık denetimi, backend testleri, Compose yapı
kontrolü ve Caddy yapılandırma doğrulaması tamamlandı. Gerçek sunucu, servislerin
birlikte çalışması/proxy erişimi, DNS, sertifika, firewall, mobil uzak bağlantı,
yedekten geri yükleme ve gerçek sağlayıcı çağrısı hâlâ doğrulanmadı.
