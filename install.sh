#!/data/data/com.termux/files/usr/bin/env bash
# ═══════════════════════════════════════════════════════
#   Termux Telegram Backup — Installer v3.2
#   Lightweight: downloads backup.py from GitHub
#   Repo: https://github.com/adebweb/termux-telegram-backup
# ═══════════════════════════════════════════════════════

set -u

R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'
B='\033[1;34m'; C='\033[1;36m'; W='\033[1;37m'
D='\033[2m'; RS='\033[0m'

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
║  📦 Termux Telegram Backup Installer v3.2             ║
║  Lightweight | Reliable | Fast Download               ║
╚═══════════════════════════════════════════════════════╝${RS}\n\n"
}

PROJECT_DIR="/storage/emulated/0/termux_backups_telegram"
SHORTCUT_DIR="$HOME/.shortcuts/tasks"
REPO_RAW="https://raw.githubusercontent.com/adebweb/termux-telegram-backup/main"

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
        v) ;;
        h) cat << 'HELP'
Usage: install.sh [OPTIONS]
  -t TOKEN    Telegram Bot Token
  -c CHAT_ID  Telegram Chat ID
  -s          Silent mode
  -u          Uninstall everything
  -h          Show this help
HELP
           exit 0 ;;
        \?) err "Invalid option: -$OPTARG" ;;
        :)  err "Option -$OPTARG requires an argument" ;;
    esac
done

if [[ "$UNINSTALL" == true ]]; then
    step "UNINSTALL"
    printf "${R}"
    read -rp "⚠️  Delete ALL backup data? [y/N]: " confirm < /dev/tty
    printf "${RS}"
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
    rm -rf "$PROJECT_DIR" 2>/dev/null || true
    rm -f "$SHORTCUT_DIR/BackupNow.sh" 2>/dev/null || true
    (crontab -l 2>/dev/null | grep -v "termux_backups_telegram" || true) | crontab - 2>/dev/null || true
    ok "Uninstalled successfully"
    exit 0
fi

banner
step "PRE-FLIGHT CHECKS"

[[ -z "${TERMUX_VERSION:-}" ]] && [[ ! -d "/data/data/com.termux" ]] && err "This installer requires Termux."

if ! curl -s --max-time 5 https://api.telegram.org >/dev/null 2>&1; then
    err "No internet connection."
fi
ok "Environment OK"

step "INSTALLING DEPENDENCIES"

log "Updating packages..."
pkg update -y -o Dpkg::Options::="--force-confold" >/dev/null 2>&1 || true

log "Installing python, cronie, termux-api..."
pkg install -y python cronie termux-api >/dev/null 2>&1 || warn "Some packages may already exist"

log "Checking python requests..."
python3 -c "import requests" 2>/dev/null || pip install requests -q >/dev/null 2>&1
ok "Dependencies ready"

step "STORAGE PERMISSION"

if [[ ! -d "/storage/emulated/0/Download" ]]; then
    log "Requesting storage access..."
    termux-setup-storage
    printf "${Y}    → Tap ALLOW on the dialog${RS}\n"
    sleep 5
    [[ ! -d "/storage/emulated/0/Download" ]] && err "Storage permission denied."
fi
ok "Storage access granted"

step "CONFIGURATION"

if [[ "$SILENT" == false ]]; then
    printf "${W}"
    printf "⚙️  Enter your settings:\n\n"
    printf "${RS}"
fi

if [[ -z "$TOKEN" ]]; then
    [[ "$SILENT" == true ]] && err "-t TOKEN required in silent mode"
    read -rp "🤖 Bot Token: " TOKEN < /dev/tty
    [[ -z "$TOKEN" ]] && err "Bot Token is required"
fi

if [[ -z "$CHAT_ID" ]]; then
    [[ "$SILENT" == true ]] && err "-c CHAT_ID required in silent mode"
    read -rp "💬 Chat ID:   " CHAT_ID < /dev/tty
    [[ -z "$CHAT_ID" ]] && err "Chat ID is required"
fi

if [[ "$SILENT" == false ]]; then
    echo ""
    info "Default: DCIM, Download, Pictures, Movies"
    read -rp "➕ Add WhatsApp Statuses? [y/N]: " ADD_WA < /dev/tty
fi

FOLDERS='"/storage/emulated/0/DCIM", "/storage/emulated/0/Download", "/storage/emulated/0/Pictures", "/storage/emulated/0/Movies"'
if [[ "$ADD_WA" =~ ^[Yy]$ ]]; then
    FOLDERS="$FOLDERS, \"/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses\""
    ok "WhatsApp Statuses added"
fi

MAX_SIZE="50"
NOTIFY_LEVEL="detailed"
BACKUP_MODE="incremental"
INCLUDE_AUDIO="false"
INCLUDE_DOCS="false"
INCLUDE_ARCHIVES="false"
DEDUPLICATE="true"
RATE_LIMIT="1.0"

if [[ "$SILENT" == false ]]; then
    echo ""
    step "ADVANCED OPTIONS (press Enter for defaults)"

    read -rp "⚖️  Max file size in MB [50]: " input
    [[ -n "$input" ]] && MAX_SIZE="$input"

    read -rp "📊 Notification level (none/summary/detailed/verbose) [detailed]: " input
    [[ -n "$input" ]] && NOTIFY_LEVEL="$input"

    read -rp "🔄 Backup mode (incremental/full) [incremental]: " input
    [[ -n "$input" ]] && BACKUP_MODE="$input"

    read -rp "🎵 Include audio files? [y/N]: " input
    [[ "$input" =~ ^[Yy]$ ]] && INCLUDE_AUDIO="true"

    read -rp "📄 Include documents (pdf, docx)? [y/N]: " input
    [[ "$input" =~ ^[Yy]$ ]] && INCLUDE_DOCS="true"

    read -rp "🗜 Include archives (zip, rar)? [y/N]: " input
    [[ "$input" =~ ^[Yy]$ ]] && INCLUDE_ARCHIVES="true"

    read -rp "🔁 Deduplicate (skip duplicate files)? [Y/n]: " input
    [[ "$input" =~ ^[Nn]$ ]] && DEDUPLICATE="false"
fi

step "BUILDING PROJECT"

# ── Create directories ────────────────────────────────
log "Creating directories..."
if ! mkdir -p "$PROJECT_DIR"; then
    err "Failed to create $PROJECT_DIR"
fi
if [[ ! -d "$PROJECT_DIR" ]]; then
    err "Directory not accessible: $PROJECT_DIR"
fi
ok "Project directory ready"

# ── Download backup.py with retry ─────────────────────
log "Downloading backup engine v3.2..."

BPY_URL="${REPO_RAW}/backup.py"
BPY_DEST="${PROJECT_DIR}/backup.py"

downloaded=false
for attempt in 1 2 3; do
    log "Download attempt $attempt/3..."
    if curl -sL --max-time 30 "$BPY_URL" -o "$BPY_DEST" 2>/dev/null; then
        if [[ -s "$BPY_DEST" ]]; then
            downloaded=true
            break
        fi
    fi
    sleep 2
done

if [[ "$downloaded" != true ]]; then
    err "Failed to download backup.py after 3 attempts.\n   URL: $BPY_URL\n   Check your internet or GitHub availability."
fi

chmod +x "$BPY_DEST"
ok "backup.py downloaded ($(wc -l < "$BPY_DEST") lines)"

# ── Write config.json ──────────────────────────────────
log "Writing config.json..."

CFG_WRITER="${PROJECT_DIR}/.write_config.py"

cat > "$CFG_WRITER" << 'PYCFG'
import json
import sys

cfg = {
    "_comment": "Generated by install.sh v3.2",
    "token": sys.argv[1],
    "chat_id": sys.argv[2],
    "folders": json.loads("[" + sys.argv[3] + "]"),
    "max_size_mb": int(sys.argv[4]),
    "exclude_screenshots": True,
    "exclude_patterns": [],
    "include_audio": sys.argv[5] == "true",
    "include_documents": sys.argv[6] == "true",
    "include_archives": sys.argv[7] == "true",
    "deduplicate": sys.argv[8] == "true",
    "rate_limit_seconds": float(sys.argv[9]),
    "retry_attempts": 3,
    "notification_level": sys.argv[10],
    "backup_mode": sys.argv[11],
    "version": "3.2"
}

with open(sys.argv[12], "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("config.json written")
PYCFG

if ! python3 "$CFG_WRITER" \
    "$TOKEN" "$CHAT_ID" "$FOLDERS" "$MAX_SIZE" \
    "$INCLUDE_AUDIO" "$INCLUDE_DOCS" "$INCLUDE_ARCHIVES" \
    "$DEDUPLICATE" "$RATE_LIMIT" "$NOTIFY_LEVEL" "$BACKUP_MODE" \
    "${PROJECT_DIR}/config.json"; then
    err "Failed to write config.json"
fi

if [[ ! -f "$PROJECT_DIR/config.json" ]]; then
    err "config.json was not written"
fi

rm -f "$CFG_WRITER"
ok "config.json written"

# ── Widget Shortcut ───────────────────────────────────
log "Creating widget shortcut..."
mkdir -p "$SHORTCUT_DIR" 2>/dev/null || true
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
printf "${W}📁 Location:${RS}\n   %s\n\n" "$PROJECT_DIR"
printf "${W}⚙️  Config:${RS}\n   %s/config.json\n\n" "$PROJECT_DIR"
printf "${W}📱 Widget:${RS}\n   1. Install ${Y}Termux:Widget${RS} from F-Droid\n"
printf "   2. Long-press home screen → Widgets\n"
printf "   3. Pick ${C}Termux:Widget → tasks → BackupNow${RS}\n\n"
printf "${W}🚀 Commands:${RS}\n"
printf "   ${D}python3 %s/backup.py${RS}          (normal backup)\n" "$PROJECT_DIR"
printf "   ${D}python3 %s/backup.py --full${RS}     (full re-upload)\n" "$PROJECT_DIR"
printf "   ${D}python3 %s/backup.py --dry-run${RS}  (simulate only)\n" "$PROJECT_DIR"
printf "   ${D}python3 %s/backup.py --stats${RS}    (view history)\n" "$PROJECT_DIR"
printf "   ${D}python3 %s/backup.py --reset${RS}    (reset state)\n\n" "$PROJECT_DIR"
printf "${W}⚠️  Battery:${RS}\n   Settings → Apps → Termux → Battery → ${R}Unrestricted${RS}\n\n"
printf "${W}🗑️  Uninstall:${RS}\n   ${D}curl -sL ... | bash -s -- -u${RS}\n\n"
printf "${G}System ready. Your files are safe. 🛡️${RS}\n"
