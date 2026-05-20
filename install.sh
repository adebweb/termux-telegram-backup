#!/data/data/com.termux/files/usr/bin/env bash
# ═══════════════════════════════════════════════════════
#   Termux Telegram Backup — Ultimate Installer v2.0
#   Repo: https://github.com/adebweb/termux-telegram-backup
#
#   Install:   curl -sL https://raw.githubusercontent.com/adebweb/termux-telegram-backup/main/install.sh | bash
#   Silent:    curl -sL ... | bash -s -- -t TOKEN -c CHAT_ID -s
#   Uninstall: curl -sL ... | bash -s -- -u
# ═══════════════════════════════════════════════════════

# Only catch undefined variables. Never die silently.
set -u

# ── Colors ────────────────────────────────────────────
R='\033[1;31m'
G='\033[1;32m'
Y='\033[1;33m'
B='\033[1;34m'
C='\033[1;36m'
W='\033[1;37m'
D='\033[2m'
RS='\033[0m'

# ── Helpers ───────────────────────────────────────────
log()  { printf "${B}[•]${RS} %s\n" "$1"; }
ok()   { printf "${G}[✓]${RS} %s\n" "$1"; }
warn() { printf "${Y}[!]${RS} %s\n" "$1"; }
err()  { printf "${R}[✗]${RS} %s\n" "$1"; exit 1; }
info() { printf "${D}    %s${RS}\n" "$1"; }
step() { printf "\n${C}═══ %s ═══${RS}\n" "$1"; }

banner() {
    clear 2>/dev/null || true
    printf "${C}
╔═══════════════════════════════════════════════════════╗
║  📦 Termux Telegram Backup Installer v2.0             ║
║  One-line backup automation for Android               ║
╚═══════════════════════════════════════════════════════╝${RS}\n\n"
}

# ── Defaults ────────────────────────────────────────────
PROJECT_DIR="/storage/emulated/0/termux_backups_telegram"
SHORTCUT_DIR="$HOME/.shortcuts/tasks"
MAX_SIZE_MB=50

# ── Parse Args ────────────────────────────────────────
UNINSTALL=false
SILENT=false
TOKEN=""
CHAT_ID=""
ADD_WA="n"

while getopts ":t:c:suvh" opt; do
    case $opt in
        t) TOKEN="$OPTARG" ;;
        c) CHAT_ID="$OPTARG" ;;
        s) SILENT=true ;;
        u) UNINSTALL=true ;;
        v) ;; # verbose placeholder
        h) cat << 'HELP'
Usage: install.sh [OPTIONS]

  -t TOKEN    Telegram Bot Token
  -c CHAT_ID  Telegram Chat ID
  -s          Silent mode (no prompts)
  -u          Uninstall everything
  -h          Show this help

Examples:
  curl -sL .../install.sh | bash
  curl -sL .../install.sh | bash -s -- -t 123:ABC -c 123456 -s
  curl -sL .../install.sh | bash -s -- -u
HELP
           exit 0 ;;
        \?) err "Invalid option: -$OPTARG" ;;
        :)  err "Option -$OPTARG requires an argument" ;;
    esac
done

# ═══════════════════════════════════════════════════════
# UNINSTALL
# ═══════════════════════════════════════════════════════
if [[ "$UNINSTALL" == true ]]; then
    step "UNINSTALL"
    printf "${R}"
    read -rp "⚠️  Delete ALL backup data? [y/N]: " confirm < /dev/tty
    printf "${RS}"
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0

    log "Removing files..."
    rm -rf "$PROJECT_DIR" 2>/dev/null || true
    rm -f "$SHORTCUT_DIR/BackupNow.sh" 2>/dev/null || true
    (crontab -l 2>/dev/null | grep -v "termux_backups_telegram" || true) | crontab - 2>/dev/null || true
    ok "Uninstalled successfully"
    exit 0
fi

# ═══════════════════════════════════════════════════════
# PRE-FLIGHT
# ═══════════════════════════════════════════════════════
banner
step "PRE-FLIGHT CHECKS"

[[ -z "${TERMUX_VERSION:-}" ]] && [[ ! -d "/data/data/com.termux" ]] && \
    err "This installer requires Termux."

if ! curl -s --max-time 5 https://api.telegram.org >/dev/null 2>&1; then
    err "No internet connection."
fi
ok "Environment OK"

# ═══════════════════════════════════════════════════════
# DEPENDENCIES
# ═══════════════════════════════════════════════════════
step "INSTALLING DEPENDENCIES"

log "Updating packages..."
pkg update -y -o Dpkg::Options::="--force-confold" >/dev/null 2>&1 || true

log "Installing python, cronie, termux-api..."
pkg install -y python cronie termux-api >/dev/null 2>&1 || warn "Some packages may already exist"

log "Checking python requests..."
python3 -c "import requests" 2>/dev/null || pip install requests -q >/dev/null 2>&1
ok "Dependencies ready"

# ═══════════════════════════════════════════════════════
# STORAGE PERMISSION
# ═══════════════════════════════════════════════════════
step "STORAGE PERMISSION"

if [[ ! -d "/storage/emulated/0/Download" ]]; then
    log "Requesting storage access..."
    termux-setup-storage
    printf "${Y}    → Tap ALLOW on the dialog${RS}\n"
    sleep 5
    [[ ! -d "/storage/emulated/0/Download" ]] && err "Storage permission denied."
fi
ok "Storage access granted"

# ═══════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════
step "CONFIGURATION"

if [[ "$SILENT" == false ]]; then
    printf "${W}"
    printf "⚙️  Enter your settings:\n\n"
    printf "${RS}"
fi

# Token
if [[ -z "$TOKEN" ]]; then
    [[ "$SILENT" == true ]] && err "-t TOKEN required in silent mode"
    read -rp "🤖 Bot Token: " TOKEN < /dev/tty
    [[ -z "$TOKEN" ]] && err "Bot Token is required"
fi

# Chat ID
if [[ -z "$CHAT_ID" ]]; then
    [[ "$SILENT" == true ]] && err "-c CHAT_ID required in silent mode"
    read -rp "💬 Chat ID:   " CHAT_ID < /dev/tty
    [[ -z "$CHAT_ID" ]] && err "Chat ID is required"
fi

# WhatsApp Statuses
if [[ "$SILENT" == false ]]; then
    echo ""
    info "Default: DCIM, Download, Pictures, Movies"
    read -rp "➕ Add WhatsApp Statuses? [y/N]: " ADD_WA < /dev/tty
fi

# Build folders list
FOLDERS='"/storage/emulated/0/DCIM", "/storage/emulated/0/Download", "/storage/emulated/0/Pictures", "/storage/emulated/0/Movies"'
if [[ "$ADD_WA" =~ ^[Yy]$ ]]; then
    FOLDERS="$FOLDERS, \"/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses\""
    ok "WhatsApp Statuses added"
fi

# ═══════════════════════════════════════════════════════
# BUILD PROJECT
# ═══════════════════════════════════════════════════════
step "BUILDING PROJECT"

log "Creating directories..."
mkdir -p "$PROJECT_DIR"
mkdir -p "$SHORTCUT_DIR"

# ── Write backup.py ───────────────────────────────────
log "Writing backup engine..."
cat > "$PROJECT_DIR/backup.py" << 'PYEOF'
#!/data/data/com.termux/files/usr/bin/env python3
import os, sys, json, time, datetime, requests
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
STATE_FILE = SCRIPT_DIR / "last_run.txt"
LOG_FILE   = SCRIPT_DIR / "backup.log"
CONFIG_FILE = SCRIPT_DIR / "config.json"

SUPPORTED = {".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".apk"}
IMAGES = {".jpg", ".jpeg", ".png", ".webp"}
VIDEOS = {".mp4", ".mov"}

def now_str():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def log(msg):
    line = f"[{now_str()}] [INFO] {msg}"
    print(line)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")

def log_err(msg):
    line = f"[{now_str()}] [ERROR] {msg}"
    print(line, file=sys.stderr)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")

def load_cfg():
    if not CONFIG_FILE.exists():
        log_err("config.json not found. Run install.sh first.")
        sys.exit(1)
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        log_err(f"Invalid config.json: {e}")
        sys.exit(1)

def get_last_run():
    if not STATE_FILE.exists():
        today = datetime.datetime.combine(
            datetime.datetime.now().date(), datetime.datetime.min.time()
        )
        return today.timestamp()
    try:
        with open(STATE_FILE, "r") as f:
            return float(f.read().strip())
    except (ValueError, OSError):
        return 0.0

def save_last_run(ts):
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        f.write(str(ts))

def send_file(token, chat_id, path):
    ext = path.suffix.lower()
    if ext in IMAGES:
        url, key = f"https://api.telegram.org/bot{token}/sendPhoto", "photo"
    elif ext in VIDEOS:
        url, key = f"https://api.telegram.org/bot{token}/sendVideo", "video"
    else:
        url, key = f"https://api.telegram.org/bot{token}/sendDocument", "document"

    for attempt in range(3):
        try:
            with open(path, "rb") as f:
                r = requests.post(url, data={
                    "chat_id": chat_id,
                    "caption": path.name[:100],
                    "disable_notification": "true"
                }, files={key: f}, timeout=60)
            if r.status_code == 200 and r.json().get("ok"):
                return True
        except Exception as e:
            log_err(f"Upload attempt {attempt+1} failed: {e}")
        time.sleep(2 * (attempt + 1))
    return False

def send_msg(token, chat_id, text):
    try:
        requests.post(f"https://api.telegram.org/bot{token}/sendMessage",
            data={"chat_id": chat_id, "text": text, "parse_mode": "Markdown"},
            timeout=10)
    except Exception:
        pass

def scan_folders(folders, since, max_mb):
    max_bytes = max_mb * 1024 * 1024
    files = []
    stats = {"screenshot": 0, "size": 0, "old": 0, "ext": 0, "error": 0}

    for fp in folders:
        folder = Path(fp)
        if not folder.exists():
            continue
        for root, dirs, names in os.walk(folder):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for name in names:
                p = Path(root) / name
                try:
                    if "screenshot" in p.name.lower():
                        stats["screenshot"] += 1
                        continue
                    if p.suffix.lower() not in SUPPORTED:
                        stats["ext"] += 1
                        continue
                    if p.stat().st_size > max_bytes:
                        stats["size"] += 1
                        continue
                    if p.stat().st_mtime <= since:
                        stats["old"] += 1
                        continue
                    files.append(p)
                except OSError:
                    stats["error"] += 1

    files.sort(key=lambda x: x.stat().st_mtime)
    return files, stats

def main():
    log("=" * 50)
    log("Backup Engine v2.0 starting...")

    cfg = load_cfg()
    token = cfg.get("token", "")
    chat_id = cfg.get("chat_id", "")
    folders = cfg.get("folders", [])
    max_size = cfg.get("max_size_mb", 50)

    if not token or not chat_id:
        log_err("Missing token or chat_id")
        sys.exit(1)

    last_run = get_last_run()
    now = time.time()

    log(f"Scanning {len(folders)} folder(s)...")
    files, stats = scan_folders(folders, last_run, max_size)

    if not files:
        msg = ("📭 *No new files found*\n\n"
               f"📸 Screenshots: {stats['screenshot']}\n"
               f"⚖️ Too large: {stats['size']}\n"
               f"📄 Other types: {stats['ext']}\n"
               f"🕒 Old files: {stats['old']}\n"
               f"⚠️ Errors: {stats['error']}")
        send_msg(token, chat_id, msg)
        log("Nothing to backup. Report sent.")
        return

    log(f"Found {len(files)} file(s) to upload")

    sent = failed = imgs = vids = apks = 0
    for idx, p in enumerate(files, 1):
        log(f"[{idx}/{len(files)}] {p.name}")
        if send_file(token, chat_id, p):
            sent += 1
            ext = p.suffix.lower()
            if ext in IMAGES: imgs += 1
            elif ext in VIDEOS: vids += 1
            elif ext == ".apk": apks += 1
        else:
            failed += 1
            log_err(f"Failed: {p.name}")
        time.sleep(1)

    rate = (sent / len(files) * 100) if files else 0
    msg = ("📊 *Backup Report*\n\n"
           f"✅ Success: {sent} ({round(rate)}%)\n"
           f"❌ Failed: {failed}\n"
           f"🖼 Images: {imgs}\n"
           f"🎥 Videos: {vids}\n"
           f"📦 APKs: {apks}\n"
           f"🚫 Ignored: {sum(stats.values())} files")
    send_msg(token, chat_id, msg)
    save_last_run(now)
    log("Backup complete. Report sent.")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("Interrupted by user.")
        sys.exit(130)
    except Exception as e:
        log_err(f"Fatal: {e}")
        sys.exit(1)
PYEOF

chmod +x "$PROJECT_DIR/backup.py"
ok "backup.py written"

# ── Write config.json ──────────────────────────────────
log "Writing config.json..."
python3 -c "
import json, sys
cfg = {
    '_comment': 'Generated by install.sh v2.0',
    'token': sys.argv[1],
    'chat_id': sys.argv[2],
    'folders': json.loads('[' + sys.argv[3] + ']'),
    'max_size_mb': 50,
    'version': '2.0'
}
with open(sys.argv[4], 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
" "$TOKEN" "$CHAT_ID" "$FOLDERS" "$PROJECT_DIR/config.json" || err "Failed to write config.json"

ok "config.json written"

# ── Widget Shortcut ───────────────────────────────────
log "Creating widget shortcut..."
cat > "$SHORTCUT_DIR/BackupNow.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
python3 /storage/emulated/0/termux_backups_telegram/backup.py
EOF
chmod +x "$SHORTCUT_DIR/BackupNow.sh"
ok "Widget shortcut ready"

# ── Cron Job ──────────────────────────────────────────
log "Setting up cron (05:30 daily)..."
(crontab -l 2>/dev/null | grep -v "termux_backups_telegram" || true
 echo "30 5 * * * termux-wake-lock && python3 $PROJECT_DIR/backup.py") | crontab -
ok "Cron scheduled"

# ── Test Bot ──────────────────────────────────────────
log "Testing bot token..."
if python3 -c "
import requests, json
with open('$PROJECT_DIR/config.json') as f: cfg = json.load(f)
r = requests.post('https://api.telegram.org/bot' + cfg['token'] + '/getMe', timeout=10)
assert r.json().get('ok'), r.text
print('Bot OK:', r.json()['result']['username'])
" 2>/dev/null; then
    ok "Bot validated"
else
    warn "Bot test failed — verify your TOKEN"
fi

# ═══════════════════════════════════════════════════════
# SUCCESS
# ═══════════════════════════════════════════════════════
banner

printf "${G}${W}✅ Installation Complete!${RS}\n\n"

printf "${W}📁 Location:${RS}\n"
printf "   %s\n\n" "$PROJECT_DIR"

printf "${W}📱 Widget:${RS}\n"
printf "   1. Install ${Y}Termux:Widget${RS} from F-Droid\n"
printf "   2. Long-press home screen → Widgets\n"
printf "   3. Pick ${C}Termux:Widget → tasks → BackupNow${RS}\n\n"

printf "${W}⚠️  Battery:${RS}\n"
printf "   Settings → Apps → Termux → Battery → ${R}Unrestricted${RS}\n\n"

printf "${W}🚀 Manual Run:${RS}\n"
printf "   ${D}python3 %s/backup.py${RS}\n\n" "$PROJECT_DIR"

printf "${W}🗑️  Uninstall:${RS}\n"
printf "   ${D}curl -sL ... | bash -s -- -u${RS}\n\n"

printf "${G}System ready. Your files are safe. 🛡️${RS}\n"
