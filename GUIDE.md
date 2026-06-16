# 📖 راهنمای کامل استفاده از TunnelMaster

این راهنما مفاهیم، روش‌های تونل‌زنی، سناریوهای واقعی و مدیریت پیشرفته را به‌صورت گام‌به‌گام
توضیح می‌دهد. برای نصب و مرجع سریع، [README.md](README.md) را ببینید.

> مخزن: <https://github.com/iPmartNetwork/TunnelMaster> — برنچ: `master`

---

## 📌 فهرست

- [مفاهیم پایه](#مفاهیم-پایه)
- [نقش سرور](#نقش-سرور)
- [روش‌های Direct (مستقیم)](#روش‌های-direct-مستقیم)
- [روش‌های Reverse (معکوس)](#روش‌های-reverse-معکوس)
- [سناریوهای پیشنهادی](#سناریوهای-پیشنهادی)
- [راهنمای گام‌به‌گام](#راهنمای-گام‌به‌گام)
- [مدیریت پروفایل](#مدیریت-پروفایل)
- [پشتیبان‌گیری و بازیابی](#پشتیبان‌گیری-و-بازیابی)
- [بهینه‌سازی سیستم](#بهینه‌سازی-سیستم)
- [مدیریت سرویس‌ها](#مدیریت-سرویس‌ها)
- [رفع اشکال](#رفع-اشکال)
- [نکات امنیتی](#نکات-امنیتی)

---

## مفاهیم پایه

```
سرور ایران (Iran)  ←→  سرور خارج (Kharej)
     ↑                      ↑
  کاربران              سرویس‌ها (پنل/کانفیگ/Xray)
```

- **Direct (مستقیم):** ترافیک از سرور ایران به سرور خارج ارسال می‌شود. سرور ایران نقش
  client/forwarder دارد و سرور خارج نقش server.
- **Reverse (معکوس):** سرور خارج به سرور ایران متصل می‌شود. این روش برای **IP کثیف ایران**
  و عبور از DPI بهتر است، چون اتصال از سمت خارج برقرار می‌شود.

**DPI چیست؟** Deep Packet Inspection تکنیکی است که محتوای بسته‌ها را بررسی می‌کند تا
پروتکل‌هایی مثل SSH/VPN را شناسایی و مسدود کند. راه‌حل، پوشاندن ترافیک داخل TLS/WebSocket
است تا شبیه HTTPS عادی به نظر برسد.

---

## نقش سرور

TunnelMaster در اولین اجرا می‌پرسد این سرور **ایران** است یا **خارج** و انتخاب را ذخیره
می‌کند (`/etc/tunnelmaster/tunnelmaster.conf`). پس از آن، نقش هر تونل (server/client)
خودکار تعیین می‌شود.

| نوع تونل | روی ایران | روی خارج |
|----------|-----------|----------|
| Direct (WSS / QUIC / Chisel) | client | server |
| Reverse (Chisel / frp / Gost) | server | client |
| Gost Simple | فقط ایران | — |

تغییر نقش:

```bash
sudo bash install.sh role
```

یا گزینهٔ `r` در منوی تعاملی.

---

## روش‌های Direct (مستقیم)

### ۱) Gost — Simple Port Forward
ساده‌ترین روش. ترافیک TCP/UDP را مستقیم فوروارد می‌کند.
- **مزیت:** سبک، سریع
- **عیب:** بدون obfuscation — قابل شناسایی توسط DPI پیشرفته
- **اجرا:** فقط روی سرور ایران

```
[Iran]  →  gost -L=tcp://:PORT/KHAREJ_IP:PORT  →  [Kharej]
```

### ۲) Gost — WSS + MUX (ضد DPI) ★
ترافیک را داخل WebSocket رمزنگاری‌شده با TLS و مالتی‌پلکس قرار می‌دهد.
- **مزیت:** شبیه HTTPS عادی — DPI سخت‌تر تشخیص می‌دهد؛ پشتیبانی از SNI camouflage
- **عیب:** overhead کمی بیشتر

```
[Kharej Server]:  gost -L=mwss://:6060/:8080
[Iran Client]:    gost -L=tcp://:8080 -F=mwss://KHAREJ:6060?host=dl.google.com
```

### ۳) Gost — QUIC
انتقال روی پروتکل QUIC (UDP).
- **مزیت:** عملکرد خوب روی شبکه‌های با packet loss
- **عیب:** ممکن است توسط برخی ISPها مسدود شود

```
[Kharej Server]:  gost -L=quic://:443
[Iran Client]:    gost -L=tcp://:443 -F=quic://KHAREJ:443
```

### ۴) Chisel — HTTP Tunnel
ترافیک TCP/UDP را داخل HTTP/WebSocket با رمزنگاری SSH قرار می‌دهد.
- **مزیت:** یک باینری، رمزنگاری قوی، auto-reconnect
- **عیب:** نیاز به باز بودن پورت HTTP

```
[Kharej Server]:  chisel server --port 8080
[Iran Client]:    chisel client KHAREJ:8080 443:127.0.0.1:443
```

---

## روش‌های Reverse (معکوس)

### ۵) Chisel Reverse
سرور خارج به ایران متصل می‌شود. مناسب IP کثیف.
- **مزیت:** IP ایران کثیف هم کار می‌کند، رمزنگاری SSH
- **عیب:** نیاز به chisel در هر دو سرور

```
[Iran Server]:    chisel server --port 443 --reverse
[Kharej Client]:  chisel client IRAN:443 R:443:127.0.0.1:2083
```

### ۶) Chisel Reverse + TLS + SNI ★
تونل معکوس رمزنگاری‌شده با TLS و SNI camouflage — بیشترین مخفی‌کاری.
- **مزیت:** شبیه HTTPS، عبور قوی از DPI، مناسب محدودیت SNI
- **عیب:** پیکربندی کمی بیشتر (گواهی TLS خودکار ساخته می‌شود)

```
[Iran Server]:    chisel server --port 443 --reverse --tls-key ... --tls-cert ...
[Kharej Client]:  chisel client --tls-skip-verify --hostname www.google.com \
                    https://IRAN:443 R:443:127.0.0.1:2083
```

### ۷) frp Reverse
کامل‌ترین ابزار reverse tunnel. auth با token، چند پورت، پایداری بالا.
- **مزیت:** پایدار، امکانات زیاد، TCP/UDP
- **عیب:** دو باینری جدا (frps/frpc)

```
[Iran — frps]:
  bindPort = 7000
  auth.token = "SECRET"

[Kharej — frpc]:
  serverAddr = "IRAN_IP"
  serverPort = 7000
  auth.token = "SECRET"
  [[proxies]]
  name = "tunnel"
  type = "tcp"
  localPort = 2083
  remotePort = 443
```

### ۸) Gost Reverse (Relay + WSS) ★
ترکیب relay و WebSocket TLS برای تونل معکوس.
- **مزیت:** ضد DPI قوی، ترافیک شبیه HTTPS
- **عیب:** پیکربندی پیچیده‌تر

```
[Iran Server]:    gost -L=tcp://:443 -L=relay+wss://:4443
[Kharej Client]:  gost -L=rtcp://:0/127.0.0.1:2083 -F=relay+wss://IRAN:4443
```

---

## سناریوهای پیشنهادی

| سناریو | پیشنهاد |
|--------|---------|
| IP ایران تمیز + DPI ضعیف | **Gost Simple** یا **Chisel Direct** |
| IP ایران کثیف | **Chisel Reverse** یا **frp Reverse** |
| DPI قوی (محدودیت SNI) | **Gost WSS** یا **Chisel Reverse+TLS** |
| نیاز به چند پورت + پایداری | **frp Reverse** |
| شبکهٔ پر packet-loss | **Gost QUIC** |

---

## راهنمای گام‌به‌گام

### مثال کامل: frp Reverse (سناریوی پرکاربرد)

**روی سرور ایران:**

```bash
sudo bash install.sh
# نقش: 1) Iran
# گزینه: 7) frp Reverse  → نقش server خودکار
# frps bind port: 7000
# token: یک رشتهٔ قوی مثل  s3cretToken!2026
```

**روی سرور خارج:**

```bash
sudo bash install.sh
# نقش: 2) Kharej
# گزینه: 7) frp Reverse  → نقش client خودکار
# Iran IP: <IP سرور ایران>
# frps port: 7000
# token: همان s3cretToken!2026
# Port to expose on Iran: 443
# Local port on Kharej: 2083  (پورت سرویس/پنل شما)
```

اکنون کاربران به `IRAN_IP:443` وصل می‌شوند و ترافیک به سرویس روی خارج (`:2083`) می‌رسد.

### مثال: Gost WSS (ضد DPI، مستقیم)

**روی سرور خارج (server):** گزینهٔ `2`، پورت تونل `6060` و پورت مقصد `8080`.
**روی سرور ایران (client):** گزینهٔ `2`، IP خارج، پورت تونل `6060`، و در صورت تمایل
یک دامنهٔ SNI مثل `dl.google.com` برای استتار.

---

## مدیریت پروفایل

هر تونل به‌صورت یک فایل در `/etc/tunnelmaster/profiles/` ذخیره می‌شود. از منوی `p`:

- **لیست** همهٔ تونل‌ها با وضعیت زنده
- **مشاهده** جزئیات یک تونل
- **Start / Stop / Restart**
- **Edit (wizard):** حذف و بازسازی تونل با ویزارد (ساده)
- **Edit raw conf:** ویرایش مستقیم فایل و بازسازی سرویس از روی `CMD` (حرفه‌ای)
- **Remove:** حذف کامل تونل

```bash
sudo bash install.sh list
sudo bash install.sh start-all
sudo bash install.sh stop-all
```

---

## پشتیبان‌گیری و بازیابی

```bash
sudo bash install.sh backup            # ساخت بکاپ
sudo bash install.sh restore           # بازیابی از آخرین بکاپ
sudo bash install.sh restore FILE.tar.gz
```

- بکاپ شامل پروفایل‌ها، کانفیگ frp، گواهی TLS، wrapperها و تنظیمات است.
- هنگام restore، سرویس‌ها از روی پروفایل‌ها بازسازی می‌شوند.
- فقط ۱۰ بکاپ اخیر نگه‌داری می‌شود (چرخش خودکار).

**انتقال به سرور جدید:**

```bash
# سرور قدیم
sudo bash install.sh backup
scp /etc/tunnelmaster/backups/tunnelmaster-*.tar.gz user@NEW_SERVER:/root/

# سرور جدید
sudo bash install.sh install
sudo bash install.sh restore /root/tunnelmaster-*.tar.gz
```

---

## بهینه‌سازی سیستم

```bash
sudo bash install.sh optimize
```

- فعال‌سازی **BBR** برای throughput بالاتر
- تیونینگ بافرهای TCP، TCP Fast Open، backlog و conntrack
- افزایش محدودیت file descriptor

> برخی تغییرات نیاز به ریبوت دارند.

---

## مدیریت سرویس‌ها

```bash
# وضعیت
systemctl status 'tm-*'

# ری‌استارت
systemctl restart tm-reverse-frpc-443

# لاگ زنده
journalctl -u tm-reverse-frpc-443 -f

# توقف/حذف از منو
sudo bash install.sh   →  گزینهٔ 11 (Stop/Remove a Tunnel)
```

---

## رفع اشکال

| مشکل | بررسی / راه‌حل |
|------|----------------|
| باینری دانلود نمی‌شود | دسترسی به GitHub، DNS، یا پراکسی |
| سرویس فعال نمی‌شود | `journalctl -u tm-<name> -f` |
| تونل وصل نمی‌شود | فایروال و پورت‌های هر دو سرور (`ufw status`) |
| frp وصل نمی‌شود | یکسان بودن `token` در دو سرور |
| نقش اشتباه انتخاب شد | `sudo bash install.sh role` |
| بررسی صحت اسکریپت | `bash -n install.sh && echo OK` |

---

## نکات امنیتی

1. حتماً برای frp یک `token` قوی تنظیم کنید.
2. برای Chisel از `--fingerprint` و `--auth` استفاده کنید.
3. پورت‌های استفاده‌نشده را با `ufw` ببندید.
4. روی سرور ایران `fail2ban` فعال کنید.
5. باینری‌ها را دوره‌ای آپدیت کنید (گزینهٔ 12).
6. فایل‌های پروفایل/کانفیگ با مجوز `600` ذخیره می‌شوند.
