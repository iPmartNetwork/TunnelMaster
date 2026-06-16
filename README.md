<div align="center">

# 🚀 TunnelMaster

**مدیریت جامع تونل برای عبور از DPI و فیلترینگ**

اسکریپت تک‌فایلی Bash برای راه‌اندازی، مدیریت و پایش تونل بین سرور **ایران** و **خارج (Kharej)** با پشتیبانی از روش‌های مستقیم (Direct) و معکوس (Reverse).

[![Shell](https://img.shields.io/badge/Shell-Bash-121011?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Backends](https://img.shields.io/badge/Backends-Gost%20%7C%20Chisel%20%7C%20frp-blue.svg)](#-روش‌های-تونل‌زنی)

</div>

---

## 📌 فهرست مطالب

- [معرفی](#-معرفی)
- [امکانات](#-امکانات)
- [معماری](#-معماری)
- [پیش‌نیازها](#-پیش‌نیازها)
- [نصب](#-نصب)
- [شروع سریع](#-شروع-سریع)
- [نقش سرور (ایران/خارج)](#-نقش-سرور-ایرانخارج)
- [روش‌های تونل‌زنی](#-روش‌های-تونل‌زنی)
- [منوی تعاملی](#-منوی-تعاملی)
- [مرجع دستورات CLI](#-مرجع-دستورات-cli)
- [مدیریت پروفایل](#-مدیریت-پروفایل)
- [پشتیبان‌گیری و بازیابی](#-پشتیبان‌گیری-و-بازیابی)
- [بهینه‌سازی سیستم](#-بهینه‌سازی-سیستم)
- [ساختار فایل‌ها](#-ساختار-فایل‌ها)
- [مدیریت سرویس‌ها](#-مدیریت-سرویس‌ها)
- [نکات امنیتی](#-نکات-امنیتی)
- [رفع اشکال](#-رفع-اشکال)
- [حذف کامل](#-حذف-کامل)
- [مشارکت](#-مشارکت)
- [مجوز](#-مجوز)

---

## 🎯 معرفی

**TunnelMaster** یک ابزار مدیریت تونل است که پیچیدگی راه‌اندازی ابزارهای حرفه‌ای تونل‌زنی
(Gost، Chisel، frp) را پشت یک منوی تعاملی ساده پنهان می‌کند. هدف اصلی، عبور پایدار از
**بازرسی عمیق بسته (DPI)** و فیلترینگ با کمترین پیچیدگی برای کاربر است.

مناسب برای:
- اتصال پایدار سرور ایران به سرور خارج (پنل، Xray، کانفیگ و ...)
- عبور از DPI با پوشش TLS/WebSocket
- سناریوهای IP کثیف ایران با تونل معکوس



---

## ✨ امکانات

| دسته | امکانات |
|------|---------|
| **تونل مستقیم** | Gost Simple، Gost WSS+MUX (ضد DPI)، Gost QUIC، Chisel |
| **تونل معکوس** | Chisel Reverse، Chisel Reverse+TLS، frp Reverse، Gost Reverse WSS |
| **نقش سرور** | انتخاب یک‌بارهٔ ایران/خارج و اعمال خودکار در همهٔ تونل‌ها |
| **مدیریت پروفایل** | ذخیره، لیست، مشاهده، ویرایش (ویزارد و خام) و حذف هر تونل |
| **پشتیبان‌گیری** | بکاپ/بازیابی کامل با چرخش خودکار و بازسازی سرویس‌ها |
| **پایداری** | سرویس‌های systemd با `Restart=always` |
| **بهینه‌سازی** | فعال‌سازی BBR و تیونینگ کرنل برای throughput بالا |
| **نصب خودکار** | دانلود و نصب باینری‌ها برای `amd64` / `arm64` / `armv7` |
| **رابط کاربری** | منوی تعاملی فارسی/انگلیسی + دستورات CLI |

نسخهٔ باینری‌های نصب‌شده:

| ابزار | نسخه |
|-------|------|
| Chisel | `1.11.5` |
| Gost | `2.12.0` |
| frp | `0.69.1` |

---

## 🏗 معماری

```
        ┌─────────────────────┐                 ┌─────────────────────┐
        │   سرور ایران (Iran)  │                 │  سرور خارج (Kharej)  │
        │                     │   تونل امن      │                     │
   کاربران ───►│  TunnelMaster   │◄──────────────►│  TunnelMaster   │───►  سرویس‌ها
        │                     │  (Direct/Reverse) │  (Xray/پنل/کانفیگ)  │
        └─────────────────────┘                 └─────────────────────┘
```

- **Direct (مستقیم):** ترافیک از سرور ایران به سرور خارج ارسال می‌شود (ایران = client).
- **Reverse (معکوس):** سرور خارج به سرور ایران متصل می‌شود — مناسب IP کثیف و عبور از DPI (ایران = server).

---

## 📋 پیش‌نیازها

| مورد | جزئیات |
|------|--------|
| **سیستم‌عامل** | Ubuntu 20.04 / 22.04 / 24.04 یا Debian 11 / 12 |
| **دسترسی** | root (با `sudo`) |
| **معماری** | `x86_64` / `aarch64` / `armv7l` |
| **شبکه** | دسترسی به GitHub برای دانلود باینری‌ها |

وابستگی‌ها (`wget`, `curl`, `unzip`, `jq`, `openssl`) به‌صورت خودکار نصب می‌شوند.

---

## 📥 نصب

### روش ۱ — نصب با یک دستور

```bash
sudo wget -qO install.sh https://raw.githubusercontent.com/iPmartNetwork/TunnelMaster/master/install.sh \
  && sudo chmod +x install.sh \
  && sudo bash install.sh
```

یا با `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/iPmartNetwork/TunnelMaster/master/install.sh -o install.sh \
  && sudo bash install.sh
```

### روش ۲ — کلون مخزن

```bash
git clone https://github.com/iPmartNetwork/TunnelMaster.git
cd TunnelMaster
sudo bash install.sh
```

در اولین اجرا، باینری‌ها نصب و سپس نقش سرور (ایران/خارج) از شما پرسیده می‌شود.

---

## ⚡ شروع سریع

```bash
# اجرای منوی تعاملی
sudo bash install.sh

# فقط نصب باینری‌ها
sudo bash install.sh install

# تعیین/تغییر نقش سرور
sudo bash install.sh role

# مشاهده وضعیت
sudo bash install.sh status
```

یک نمونه سناریو (Reverse با frp):

1. روی **سرور ایران**: نقش را `Iran` انتخاب کن → گزینه `7) frp Reverse` → نقش server.
2. روی **سرور خارج**: نقش را `Kharej` انتخاب کن → گزینه `7) frp Reverse` → نقش client.
3. همان token مشترک را در هر دو وارد کن. تمام.

---

## 🌐 نقش سرور (ایران/خارج)

در اولین اجرا، اسکریپت می‌پرسد این سرور **ایران** است یا **خارج**، و انتخاب را در
`/etc/tunnelmaster/tunnelmaster.conf` ذخیره می‌کند. پس از آن، هنگام ساخت هر تونل،
نقش (server/client) **به‌صورت خودکار** تعیین می‌شود و دیگر نیازی به انتخاب دستی نیست.

نقش فعلی در بالای منوی اصلی نمایش داده می‌شود.

```bash
sudo bash install.sh role     # تغییر نقش سرور
```

نگاشت خودکار نقش:

| نوع تونل | روی ایران | روی خارج |
|----------|-----------|----------|
| **Direct** (WSS / QUIC / Chisel) | client | server |
| **Reverse** (Chisel / frp / Gost) | server | client |
| **Gost Simple** | فقط ایران (تک‌طرفه) | — |

> نکته: تونل Gost Simple فقط روی سرور ایران اجرا می‌شود؛ بقیه تونل‌ها روی هر دو سرور
> (هر کدام با نقش خودش) راه‌اندازی می‌شوند.

---

## 🔀 روش‌های تونل‌زنی

| # | روش | ابزار | جهت | ویژگی |
|---|-----|-------|-----|-------|
| 1 | Gost Simple | Gost | Direct | فوروارد ساده TCP/UDP، سریع، بدون رمزنگاری |
| 2 | Gost WSS + MUX ★ | Gost | Direct | WebSocket روی TLS، شبیه HTTPS، با SNI camouflage |
| 3 | Gost QUIC | Gost | Direct | انتقال UDP، مناسب شبکه‌های پر packet-loss |
| 4 | Chisel | Chisel | Direct | تونل HTTP با رمزنگاری SSH و reconnect خودکار |
| 5 | Chisel Reverse | Chisel | Reverse | WebSocket + SSH، مناسب IP کثیف ایران |
| 6 | Chisel Reverse + TLS ★ | Chisel | Reverse | TLS + SNI، حداکثر مخفی‌کاری |
| 7 | frp Reverse ★ | frp | Reverse | هاب چندسروری: چند خارج → یک ایران، چند پورت، داشبورد وب |
| 8 | Gost Reverse WSS ★ | Gost | Reverse | relay + WebSocket TLS، ضد DPI قوی |

★ = پیشنهادشده برای عبور از DPI.

برای توضیح کامل هر روش و سناریوهای پیشنهادی، فایل [GUIDE.md](GUIDE.md) را ببینید.

### 🌐 حالت چندسروری (Multi-Server Hub با frp)

با روش `7) frp Reverse` می‌توانید **چند سرور خارج را به یک سرور ایران** متصل کنید،
هر کدام روی پورت‌های متفاوت:

```
        ┌──────── Kharej-A (label: de1)  → Iran:443
Iran ───┤
(frp Hub)├──────── Kharej-B (label: fi)   → Iran:8443
        └──────── Kharej-C (label: nl)   → Iran:9443
```

- روی **ایران**: یک‌بار هاب frp را بسازید (نقش server). در صورت تمایل **داشبورد وب**
  را فعال کنید تا همهٔ سرورهای خارجِ متصل را در یک صفحه ببینید.
- روی هر **خارج**: یک کلاینت با **برچسب (label)** یکتا بسازید و یک یا **چند پورت** را
  هم‌زمان به هاب ایران expose کنید. همان token هاب را وارد کنید.

هر سرور خارج پروفایل جداگانهٔ خود را دارد (`reverse-frpc-<label>`) و از طریق منوی
`p` (Manage Profiles) مدیریت می‌شود. جزئیات کامل در [GUIDE.md](GUIDE.md).

---

## 🖥 منوی تعاملی

```
╔═══════════════════════════════════════════════╗
║         TunnelMaster v2.0                     ║
║     Anti-DPI Tunnel Manager                   ║
╚═══════════════════════════════════════════════╝

   Server role: IRAN (داخل)

 ── Direct Tunnels (Iran → Kharej) ──────────────
  1) Gost Simple         (TCP/UDP, no encryption)
  2) Gost WSS + MUX      (Anti-DPI, TLS, SNI camouflage) ★
  3) Gost QUIC           (UDP transport, fast)
  4) Chisel              (HTTP tunnel, SSH encryption)

 ── Reverse Tunnels (Kharej → Iran) ─────────────
  5) Chisel Reverse      (WebSocket + SSH)
  6) Chisel Reverse+TLS  (TLS + SNI, maximum stealth) ★
  7) frp Reverse         (Multi-port, auth, stable)
  8) Gost Reverse WSS    (Relay + WSS, Anti-DPI) ★

 ── System & Management ──────────────────────────
  p)  Manage Profiles    (list, start/stop, edit, remove)
  b)  Backup / Restore   (save & restore configs)
  r)  Change Server Role (Iran / Kharej)
  9)  Optimize System    (BBR + Kernel tuning)
  10) Show Status
  11) Stop/Remove a Tunnel
  12) Reinstall Binaries
  13) Uninstall Everything

  0)  Exit
```

---

## 🧰 مرجع دستورات CLI

```bash
sudo bash install.sh [COMMAND] [ARGS]
```

| دستور | توضیح |
|-------|-------|
| `install` | نصب وابستگی‌ها و باینری‌ها |
| `role` | تعیین/تغییر نقش سرور (ایران/خارج) |
| `list` | لیست همهٔ پروفایل‌های تونل با وضعیت زنده |
| `start-all` | شروع همهٔ تونل‌ها |
| `stop-all` | توقف همهٔ تونل‌ها |
| `backup` | ساخت بکاپ از کانفیگ‌ها و پروفایل‌ها |
| `restore [FILE]` | بازیابی از آخرین بکاپ یا فایل مشخص |
| `status` | نمایش وضعیت باینری‌ها، BBR و سرویس‌ها |
| `optimize` | فعال‌سازی BBR و تیونینگ کرنل |
| `uninstall` | حذف کامل (سرویس‌ها، باینری‌ها، کانفیگ‌ها) |
| _(بدون آرگومان)_ | اجرای منوی تعاملی |

---

## 📂 مدیریت پروفایل

هر تونل هنگام ساخت به‌صورت یک فایل کانفیگ خوانا در `/etc/tunnelmaster/profiles/` ذخیره
می‌شود. این فایل **منبع حقیقت (source of truth)** آن تونل است و سرویس systemd از روی آن
ساخته می‌شود.

نمونهٔ یک پروفایل:

```ini
NAME="reverse-frpc-443"
METHOD="reverse-frp"
DESC="frp Client R:443->:2083"
SERVICE="tm-reverse-frpc-443"
CREATED="2026-06-16 22:10:00"
CMD="/usr/local/bin/frpc -c /etc/tunnelmaster/frpc-443.toml"
ROLE="client"
IRAN_IP="1.2.3.4"
REMOTE_PORT="443"
LOCAL_PORT="2083"
TOKEN="secret123"
```

از منوی `p` (Manage Profiles) می‌توانید برای هر تونل:

- **مشاهده جزئیات** کامل (روش، نقش، پورت‌ها، وضعیت، پارامترها)
- **Start / Stop / Restart**
- **ویرایش** با دو حالت:
  - **Edit (wizard)** — تونل حذف و ویزارد ساخت همان نوع دوباره اجرا می‌شود (ساده)
  - **Edit raw conf** — ویرایش مستقیم فایل پروفایل در ویرایشگر و بازسازی سرویس از روی `CMD` (حرفه‌ای)
- **حذف** تونل (پروفایل + سرویس + فایل‌های مرتبط)

```bash
sudo bash install.sh list        # لیست همه پروفایل‌ها
sudo bash install.sh start-all   # شروع همه تونل‌ها
sudo bash install.sh stop-all    # توقف همه تونل‌ها
```

---

## 💾 پشتیبان‌گیری و بازیابی

بکاپ از **کل** پوشهٔ کانفیگ گرفته می‌شود: پروفایل‌ها، فایل‌های `*.toml` مربوط به frp،
گواهی‌های TLS، wrapperها و فایل تنظیمات. هنگام بازیابی، سرویس‌های systemd به‌صورت خودکار
از روی پروفایل‌ها بازسازی می‌شوند.

```bash
sudo bash install.sh backup            # ساخت بکاپ
sudo bash install.sh restore           # بازیابی از آخرین بکاپ
sudo bash install.sh restore FILE.tar.gz   # بازیابی از فایل مشخص
```

- بکاپ‌ها در `/etc/tunnelmaster/backups/` ذخیره می‌شوند.
- **چرخش خودکار:** فقط ۱۰ نسخهٔ اخیر نگه‌داری می‌شود.
- در منوی تعاملی، گزینه `b` (Backup / Restore) همین کارها را فراهم می‌کند.

---

## ⚙️ بهینه‌سازی سیستم

گزینهٔ `9` (یا `install.sh optimize`) موارد زیر را اعمال می‌کند:

- فعال‌سازی **BBR** (`tcp_bbr` + `fq`)
- افزایش بافرهای TCP تا ۶۴ مگابایت
- فعال‌سازی **TCP Fast Open**
- افزایش `somaxconn`، `netdev_max_backlog`، `nf_conntrack_max`
- افزایش محدودیت file descriptor تا `1048576`
- فعال‌سازی IP forwarding (IPv4 + IPv6)

> برخی تنظیمات برای اعمال کامل نیاز به ریبوت دارند.

---

## 🗂 ساختار فایل‌ها

```
/etc/tunnelmaster/
├── tunnelmaster.conf        # تنظیمات کلی (نقش سرور)
├── profiles/                # پروفایل هر تونل (.conf)
├── backups/                 # بکاپ‌های فشرده (tar.gz)
├── frps.toml / frpc-*.toml  # کانفیگ frp
├── server.crt / server.key  # گواهی TLS (برای Chisel TLS)
└── run-*.sh                 # wrapper scriptها (برای Gost WSS client)

/usr/local/bin/
├── chisel · gost · frps · frpc   # باینری‌ها

/etc/systemd/system/
└── tm-*.service             # سرویس‌های تونل
```

---

## 🔧 مدیریت سرویس‌ها

تمام تونل‌ها به‌صورت سرویس systemd با پیشوند `tm-` اجرا می‌شوند.

```bash
# مشاهده وضعیت همهٔ تونل‌ها
systemctl status 'tm-*'

# ری‌استارت یک تونل
systemctl restart tm-reverse-frpc-443

# مشاهدهٔ لاگ زنده
journalctl -u tm-reverse-frpc-443 -f
```

> مدیریت ساده‌تر از طریق منوی `p` (Manage Profiles) در دسترس است.

---

## 🔒 نکات امنیتی

1. برای **frp** حتماً یک `token` قوی تنظیم کنید.
2. برای **Chisel** از `--auth` و `--fingerprint` برای امنیت بیشتر استفاده کنید.
3. پورت‌های استفاده‌نشده را با `ufw` ببندید.
4. روی سرور ایران **fail2ban** فعال کنید.
5. به‌صورت دوره‌ای باینری‌ها را آپدیت کنید (گزینهٔ `12` — Reinstall).
6. فایل‌های پروفایل و کانفیگ با مجوز `600` ذخیره می‌شوند (شامل token).

---

## 🩺 رفع اشکال

| مشکل | راه‌حل |
|------|--------|
| دانلود باینری ناموفق | دسترسی به GitHub را بررسی کنید؛ در صورت نیاز از DNS/پراکسی استفاده کنید |
| سرویس بالا نمی‌آید | `journalctl -u tm-<name> -f` را بررسی کنید |
| تونل وصل نمی‌شود | پورت‌ها و فایروال هر دو سرور را بررسی کنید (`ufw status`) |
| frp وصل نمی‌شود | یکسان بودن `token` در دو سرور را بررسی کنید |
| تغییرات BBR اعمال نشد | یک‌بار سرور را ریبوت کنید |
| اعتبارسنجی اسکریپت | `bash -n install.sh && echo OK` |

---

## 🧹 حذف کامل

```bash
sudo bash install.sh uninstall
```

این دستور همهٔ سرویس‌ها، باینری‌ها، کانفیگ‌ها و تنظیمات کرنل افزوده‌شده را پاک می‌کند.

---

## 🤝 مشارکت

Pull Requestها و Issueها در مخزن [iPmartNetwork/TunnelMaster](https://github.com/iPmartNetwork/TunnelMaster) خوش‌آمد هستند.
برای تغییرات بزرگ، ابتدا یک Issue باز کنید تا دربارهٔ آن گفت‌وگو شود.

---

## 📄 مجوز

این پروژه تحت مجوز MIT منتشر شده است. جزئیات در فایل [LICENSE](LICENSE).
