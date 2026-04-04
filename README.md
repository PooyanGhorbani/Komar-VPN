عالی! 😎 برای GitHub بهتر است توضیحات زیبا، جذاب و قابل فهم باشد تا کاربران هم جذب شوند. من یک نمونه کامل README با شکلک، پرچم، نکات مهم و دستورات واضح برای نسخه ۱.۳ PRO آماده کردم که می‌توانی مستقیم استفاده کنی:
🌐 Komar VPN v1.3 PRO – Telegram Full Panel 🚀
💡 مدیریت و فروش VPN حرفه‌ای، همه چیز در تلگرام!
�
🔹 ویژگی‌ها
🛰 مدیریت سرورها: اضافه، حذف، ریست و کنترل Agent
👤 مدیریت کاربران: ایجاد، حذف، ریست مصرف، مشاهده مصرف واقعی
📊 مصرف واقعی کاربران: با Xray یا vnStat
🖼 لینک و QR Code اتوماتیک: به صورت مستقیم به تلگرام ارسال می‌شود
⚠️ هشدار هوشمند: اتمام حجم، منقضی شدن کاربر، سرور آفلاین
💳 فروش خودکار: آماده اتصال به درگاه‌های پرداخت مانند ZarinPal / Pay.ir
✅ تمام عملیات در Telegram Bot: بدون نیاز به پنل وب
📁 ساختار فایل‌ها
Plain text
/root/komarvpn/
├─ komar_master_v1_3.py   # Master و مدیریت اصلی
├─ komar_agent_v1_3.py    # Agent برای تولید لینک و QR
├─ servers.json           # لیست سرورها
├─ users.json             # اطلاعات کاربران
└─ logs/                  # فایل‌های لاگ
⚙️ نصب سریع
Bash
wget https://github.com/username/KomarVPN/raw/main/komarvpn_installer.sh
chmod +x komarvpn_installer.sh
./komarvpn_installer.sh
🔑 هنگام نصب اطلاعات زیر را وارد کنید:
Telegram Bot Token
Admin Chat ID
Server Name
درگاه پرداخت (اختیاری)
📌 دستورات مهم Telegram Bot
مدیریت سرورها
دستور
توضیح
/add_server IP
اضافه کردن سرور جدید
/remove_server IP
حذف سرور
/list_servers
مشاهده وضعیت و پینگ سرورها
`/server_action start
stop
مدیریت کاربران
دستور
توضیح
/add_user NAME TRAFFIC DAYS
ایجاد کاربر جدید (مثال: /add_user ali 10GB 30)
/remove_user NAME
حذف کاربر
/reset_user NAME
ریست مصرف کاربر
/user_info NAME
مشاهده مصرف و تاریخ انقضا
🌟 نکات مهم
همه عملیات کاملاً تلگرام محور هستند
Master و Agent به صورت خودکار فعال می‌شوند
قابلیت افزودن تعداد نامحدود سرور و کاربر
QR Code و لینک VPN خودکار تولید می‌شود
هشدارها و مصرف لحظه‌ای کاربران قابل مشاهده است
🏷️ لایسنس
MIT License – استفاده تجاری و شخصی مجاز است
اگر بخواهی، می‌توانم همین README را �⁠یک نسخه تصویری و بسیار جذاب با آیکون‌ها، پرچم کشورها، نمودار مصرف و لینک نمونه QR هم بسازم که واقعا حرفه‌ای و شبیه مخازن Outline و Marzban شود.
می‌خوای برات بسازم؟
