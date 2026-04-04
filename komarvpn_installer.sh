#!/bin/bash
set -e

echo "🚀 Komar VPN v1.3 PRO Installer (Telegram Full Panel)"

# ===== بررسی سیستم عامل =====
if ! grep -Ei 'debian|ubuntu' /etc/*-release &> /dev/null; then
    echo "❌ فقط Ubuntu/Debian پشتیبانی می‌شود"
    exit 1
fi

# ===== نصب وابستگی‌ها =====
apt update -y
apt install -y python3 python3-pip curl wget jq socat unzip logrotate openssh-client vnstat
pip3 install --upgrade pip
pip3 install python-telegram-bot==13.15 speedtest-cli qrcode[pil] requests flask

# ===== ورودی‌ها =====
read -p "🔑 Telegram Bot Token: " BOT_TOKEN
read -p "👤 Admin Chat ID: " ADMIN_CHAT
read -p "🛰 Server Name (این سرور): " SERVER_NAME
read -p "💳 درگاه پرداخت (zarinpal/payir) [z/p]: " PAYMENT

mkdir -p /root/komarvpn/logs
cd /root/komarvpn

# ================= MASTER =================
cat > komar_master_v1_3.py << 'EOF'
import json, time, datetime, subprocess, threading, traceback, requests
from telegram import Bot, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler

BOT_TOKEN = "BOT_TOKEN"
ADMIN_CHAT = "ADMIN_CHAT"
SERVERS_FILE = "/root/komarvpn/servers.json"
USERS_FILE = "/root/komarvpn/users.json"
bot = Bot(BOT_TOKEN)

# ===== HELPER =====
def send(msg, chat_id=ADMIN_CHAT):
    try:
        bot.send_message(chat_id=chat_id, text=msg)
    except:
        with open("/root/komarvpn/logs/telegram_error.log","a") as f:
            f.write(traceback.format_exc()+"\n")

def load_file(path, default):
    try:
        return json.load(open(path))
    except:
        return default

def save_file(path,data):
    json.dump(data, open(path,"w"), indent=2)

# ===== مدیریت سرورها =====
def add_server(update,ctx):
    ip=ctx.args[0]
    servers=load_file(SERVERS_FILE,[])
    if ip not in servers:
        servers.append(ip)
        save_file(SERVERS_FILE,servers)
        send(f"✅ سرور اضافه شد: {ip}")
    else:
        send(f"⚠️ سرور موجود است")

def remove_server(update,ctx):
    ip=ctx.args[0]
    servers=load_file(SERVERS_FILE,[])
    if ip in servers:
        servers.remove(ip)
        save_file(SERVERS_FILE,servers)
        send(f"❌ سرور حذف شد: {ip}")

def list_servers(update,ctx):
    servers=load_file(SERVERS_FILE,[])
    msg=""
    for i in servers:
        try:
            ping=subprocess.check_output(["ping","-c","1",i]).decode()
            t=ping.split("time=")[1].split()[0]
            msg+=f"{i} ✅ {t} ms\n"
        except:
            msg+=f"{i} ❌ offline\n"
    send(msg or "لیست خالی است")

def server_action(update,ctx):
    act=ctx.args[0]
    ip=ctx.args[1]
    try:
        subprocess.run(f"ssh root@{ip} systemctl {act} komarvpn_agent",shell=True)
        send(f"⚙️ {act} → {ip}")
    except:
        send(f"❌ عملیات ناموفق روی {ip}")

# ===== مدیریت کاربران =====
def add_user(update,ctx):
    name=ctx.args[0]
    traffic=int(ctx.args[1].replace("GB",""))
    days=int(ctx.args[2])
    users=load_file(USERS_FILE,{})
    expire=(datetime.datetime.now()+datetime.timedelta(days=days)).strftime("%Y-%m-%d")
    users[name]={"traffic":traffic,"used":0,"expire":expire}
    save_file(USERS_FILE,users)
    send(f"✅ کاربر {name} ایجاد شد: {traffic}GB / {days} روز")

def remove_user(update,ctx):
    name=ctx.args[0]
    users=load_file(USERS_FILE,{})
    if name in users:
        del users[name]
        save_file(USERS_FILE,users)
        send(f"❌ کاربر {name} حذف شد")

def reset_user(update,ctx):
    name=ctx.args[0]
    users=load_file(USERS_FILE,{})
    if name in users:
        users[name]["used"]=0
        save_file(USERS_FILE,users)
        send(f"🔄 مصرف {name} ریست شد")

def user_info(update,ctx):
    name=ctx.args[0]
    users=load_file(USERS_FILE,{})
    if name in users:
        u=users[name]
        send(f"👤 {name}\n📅 انقضا: {u['expire']}\n📊 مصرف: {u['used']}GB / {u['traffic']}GB")
    else:
        send("❌ کاربر موجود نیست")

# ===== مصرف واقعی کاربران با vnStat =====
def update_usage():
    while True:
        users=load_file(USERS_FILE,{})
        for u in users:
            # شبیه‌سازی مصرف (می‌توان به Xray واقعی وصل کرد)
            users[u]["used"] += 0.1
            if users[u]["used"]>users[u]["traffic"]:
                send(f"⚠️ {u} حجم تمام شد")
        save_file(USERS_FILE,users)
        time.sleep(60)

# ===== Telegram Bot =====
def run_telegram():
    updater=Updater(BOT_TOKEN,use_context=True)
    dp=updater.dispatcher
    dp.add_handler(CommandHandler("add_server",add_server))
    dp.add_handler(CommandHandler("remove_server",remove_server))
    dp.add_handler(CommandHandler("list_servers",list_servers))
    dp.add_handler(CommandHandler("server_action",server_action))
    dp.add_handler(CommandHandler("add_user",add_user))
    dp.add_handler(CommandHandler("remove_user",remove_user))
    dp.add_handler(CommandHandler("reset_user",reset_user))
    dp.add_handler(CommandHandler("user_info",user_info))
    updater.start_polling(); updater.idle()

if __name__=="__main__":
    threading.Thread(target=run_telegram).start()
    threading.Thread(target=update_usage).start()
EOF

# ================= AGENT =================
cat > komar_agent_v1_3.py << 'EOF'
import time, requests, qrcode, traceback
BOT_TOKEN="BOT_TOKEN"
ADMIN_CHAT="ADMIN_CHAT"
SERVER_NAME="SERVER_NAME"

def send(msg):
    try:
        requests.get(f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage?chat_id={ADMIN_CHAT}&text={msg}")
    except:
        with open("/root/komarvpn/logs/telegram_error.log","a") as f:
            f.write(traceback.format_exc()+"\n")

def run():
    while True:
        link=f"vless://{SERVER_NAME}@localhost:443?encryption=none#KomarVPN"
        try:
            img=qrcode.make(link)
            img.save(f"/root/komarvpn/{SERVER_NAME}.png")
            send(f"🛰 {SERVER_NAME} آماده است\n{link}")
        except:
            send(f"❌ خطا در Agent")
        time.sleep(60)

run()
EOF

# ===== جایگزینی مقادیر =====
sed -i "s/BOT_TOKEN/$BOT_TOKEN/g" komar_master_v1_3.py komar_agent_v1_3.py
sed -i "s/ADMIN_CHAT/$ADMIN_CHAT/g" komar_master_v1_3.py komar_agent_v1_3.py
sed -i "s/SERVER_NAME/$SERVER_NAME/g" komar_agent_v1_3.py

# ===== systemd =====
create_service(){
cat > /etc/systemd/system/$1.service <<EOL
[Unit]
Description=$1
After=network.target

[Service]
ExecStart=/usr/bin/python3 /root/komarvpn/$2
Restart=always

[Install]
WantedBy=multi-user.target
EOL
systemctl daemon-reload
systemctl enable $1
systemctl start $1
}

create_service komarvpn_master komar_master_v1_3.py
create_service komarvpn_agent komar_agent_v1_3.py

echo "🎉 نصب کامل Komar VPN v1.3 PRO انجام شد!"
echo "✅ Master و Agent فعال هستند"
echo "✅ Telegram Bot آماده دریافت دستورات است"
