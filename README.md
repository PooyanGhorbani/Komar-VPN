# Komar Web Tunnel 0.12

این پروژه برای **منتشر کردن یک سرویس HTTP معمولی** پشت **Cloudflare Tunnel** است. این اسکریپت برای وب‌سرویس، پنل داخلی، API یا داشبورد محلی مناسب است.

## چه چیزهایی اضافه شد

- پشتیبانی از فایل `.env`
- امکان `install`
- امکان `sync`
- امکان `uninstall`
- پشتیبانی از **چند hostname** برای یک tunnel
- سرویس systemd اختصاصی با `--token-file`

## نیازمندی‌های Cloudflare

برای ساخت tunnel با API، Cloudflare در مستندات رسمی حداقل این permissionها را ذکر می‌کند:

- **Account → Cloudflare Tunnel → Edit**
- **Zone → DNS → Edit**

برای tunnelهای remotely-managed، اجرای `cloudflared` فقط به **Tunnel Token** نیاز دارد. همچنین `cloudflared tunnel run --token-file <PATH>` برای این نوع tunnel پشتیبانی می‌شود.

## فایل `.env`

نمونه:

```env
CF_API_TOKEN=cf_xxxxxxxxxxxxxxxxx
ACCOUNT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ZONE_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TUNNEL_NAME=komar-web
HOSTNAME_MAP=app.example.com=http://localhost:8080;api.example.com=http://localhost:3000
```

اگر فقط یک hostname داری، این مدل هم کار می‌کند:

```env
CF_API_TOKEN=cf_xxxxxxxxxxxxxxxxx
ACCOUNT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ZONE_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TUNNEL_NAME=komar-web
DOMAIN=example.com
SUBDOMAIN=app
LOCAL_SERVICE=http://localhost:8080
```

## نصب

```bash
sudo bash komar-web-tunnel-0.12.sh install .env
```

یا اگر `.env` در همان پوشه باشد:

```bash
sudo bash komar-web-tunnel-0.12.sh install
```

## همگام‌سازی تنظیمات

بعد از تغییر `.env`:

```bash
sudo bash komar-web-tunnel-0.12.sh sync .env
```

## حذف

برای حذف سرویس محلی و در صورت وجود credential لازم، حذف DNS و خود tunnel:

```bash
sudo bash komar-web-tunnel-0.12.sh uninstall .env
```

## وضعیت

```bash
sudo bash komar-web-tunnel-0.12.sh state
```

## نکته مهم

Cloudflare برای tunnel یک زیردامنه از نوع `<UUID>.cfargotunnel.com` می‌سازد و hostnameهای شما باید به آن با **CNAME proxied** اشاره کنند. همچنین می‌توانید چند hostname را به یک tunnel وصل کنید.

## دستور نصب از GitHub

اگر فایل را در ریشهٔ ریپوی `PooyanGhorbani/Komar-VPN` با نام `komar-web-tunnel.sh` بگذاری:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PooyanGhorbani/Komar-VPN/main/komar-web-tunnel.sh)
```
