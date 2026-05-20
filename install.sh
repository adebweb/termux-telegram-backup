#!/data/data/com.termux/files/usr/bin/env bash
# ═══════════════════════════════════════════════════════
#   Termux Telegram Backup — Professional Installer
#   Install:  curl -sL https://raw.githubusercontent.com/YOURNAME/termux-telegram-backup/main/install.sh | bash
#   Uninstall: curl -sL https://raw.githubusercontent.com/YOURNAME/termux-telegram-backup/main/install.sh | bash -s -- --uninstall
# ═══════════════════════════════════════════════════════

set -euo pipefail

# ── Metadata ──────────────────────────────────────────
REPO_RAW="https://raw.githubusercontent.com/YOURNAME/termux-telegram-backup/main"
VERSION="1.0.0"
PROJECT_DIR="/storage/emulated/0/termux_backups_telegram"
SHORTCUT_DIR="$HOME/.shortcuts/tasks"

# ── Colors ────────────────────────────────────────────
R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"
B="\033[1;34m"; C="\033[1;36m"; W="\033[1;37m"
D="\033[2m"; RS="\033[0m"

log()  { echo -e "${B}[•]${RS} $1"; }
ok()   { echo -e "${G}[✓]${RS} $1"; }
warn() { echo -e "${Y}[!]${RS} $1"; }
err()  { echo -e "${R}[✗]${RS} $1"; exit 1; }
info() { echo -e "${D}    $1${RS}"; }

banner() {
    clear 2>/dev/null || true
    echo -e "${C}
╔═══════════════════════════════════════════════════════╗
║  📦 Termux Telegram Backup Installer v${VERSION}          ║
║  One-line backup automation for Android               ║
╚═══════════════════════════════════════════════════════╝${RS}"
}

# ── Args ──────────────────────────────────────────────
UNINSTALL=false
SILENT=false
TOKEN=""
CHAT_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall|-u) UNINSTALL=true; shift ;;
        --silent|-s)    SILENT=true; shift ;;
        --token|-t)     TOKEN="$2"; shift 2 ;;
        --chat-id|-c)   CHAT_ID="$2"; shift 2 ;;
        --help|-h)
            echo -e "${C}Usage:${RS}"
            echo "  curl -sL .../install.sh | bash"
            echo "  curl -sL .../install.sh | bash -s -- --token <TOKEN> --chat-id <ID> --silent"
            echo ""
            echo "Options:"
            echo "  -t, --token <TOKEN>    Telegram Bot Token"
            echo "  -c, --chat-id <ID>     Telegram Chat ID"
            echo "  -s, --silent           Non-interactive mode"
            echo "  -u, --uninstall        Remove everything"
            echo "  -h, --help             Show this help"
            exit 0
            ;;
        *) warn "Unknown option: $1"; shift ;;
    esac
done

# ── Uninstall ─────────────────────────────────────────
if [[ "$UNINSTALL" == true ]]; then
    echo -e "${R}${W}"
    read -rp "⚠️  This will delete ALL backup data. Continue? [y/N]: " confirm
    echo -e "${RS}"
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0

    log "Removing project files..."
    rm -rf "$PROJECT_DIR" 2>/dev/null || true
    rm -f "$SHORTCUT_DIR/BackupNow.sh" 2>/dev/null || true
    (crontab -l 2>/dev/null | grep -v "termux_backups_telegram" || true) | crontab - 2>/dev/null || true
    ok "Uninstall complete."
    exit 0
fi

# ── Pre-flight Checks ──────────────────────────────────
banner

log "Running pre-flight checks..."
[[ "$SILENT" == false ]] && sleep 1

# Check Termux environment
if [[ -z "${TERMUX_VERSION:-}" && ! -d "/data/data/com.termux" ]]; then
    err "This installer is designed for Termux only."
fi

# Check network
if ! curl -s --max-time 5 https://api.telegram.org >/dev/null 2>&1; then
    err "No internet connection or Telegram is blocked."
fi
ok "Environment validated"

# ── Dependencies ──────────────────────────────────────
log "Installing dependencies (this may take a minute)..."
pkg update -y -o Dpkg::Options::="--force-confold" >/dev/null 2>&1 || true
pkg install -y python cronie termux-api >/dev/null 2>&1 || warn "Some packages may already exist"
python3 -c "import requests" 2>/dev/null || pip install requests -q >/dev/null 2>&1
ok "Dependencies ready"

# ── Storage Permission ────────────────────────────────
if [[ ! -d "/storage/emulated/0/Download" ]]; then
    log "Requesting storage permission..."
    termux-setup-storage
    [[ "$SILENT" == false ]] && echo -e "${Y}    → Tap ALLOW on the dialog, then wait...${RS}"
    sleep 5
    [[ ! -d "/storage/emulated/0/Download" ]] && err "Storage permission denied."
fi
ok "Storage access granted"

# ── Interactive Config ────────────────────────────────
banner
if [[ "$SILENT" == false ]]; then
    echo -e "${W}${BOLD}⚙️  Configuration${RS}\n"
fi

if [[ -z "$TOKEN" ]]; then
    if [[ "$SILENT" == true ]]; then
        err "--token is required in silent mode."
    fi
    read -rp "🤖 Telegram BOT_TOKEN: " TOKEN
    [[ -z "$TOKEN" ]] && err "BOT_TOKEN is required."
fi

if [[ -z "$CHAT_ID" ]]; then
    if [[ "$SILENT" == true ]]; then
        err "--chat-id is required in silent mode."
    fi
    read -rp "💬 Telegram CHAT_ID:  " CHAT_ID
    [[ -z "$CHAT_ID" ]] && err "CHAT_ID is required."
fi

ADD_WA="n"
if [[ "$SILENT" == false ]]; then
    echo ""
    info "Default folders: DCIM, Download, Pictures, Movies"
    read -rp "➕ Include WhatsApp Statuses? [y/N]: " ADD_WA
fi

FOLDERS='"/storage/emulated/0/DCIM", "/storage/emulated/0/Download", "/storage/emulated/0/Pictures", "/storage/emulated/0/Movies"'
if [[ "$ADD_WA" =~ ^[Yy]$ ]]; then
    FOLDERS="$FOLDERS, "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses""
    ok "WhatsApp Statuses included"
fi

# ── Download Engine ───────────────────────────────────
log "Downloading backup engine v${VERSION}..."
mkdir -p "$PROJECT_DIR"
mkdir -p "$SHORTCUT_DIR"

curl -sL "${REPO_RAW}/backup.py" -o "${PROJECT_DIR}/backup.py" || err "Failed to download backup.py"
curl -sL "${REPO_RAW}/config.json" -o "${PROJECT_DIR}/config.json" || err "Failed to download config.json"

# Inject user config into config.json
sed -i "s|YOUR_BOT_TOKEN|$TOKEN|g" "${PROJECT_DIR}/config.json"
sed -i "s|YOUR_CHAT_ID|$CHAT_ID|g" "${PROJECT_DIR}/config.json"
sed -i "s|\[YOUR_FOLDERS\]|[$FOLDERS]|g" "${PROJECT_DIR}/config.json"

chmod +x "${PROJECT_DIR}/backup.py"
ok "Engine downloaded and configured"

# ── Create Widget Shortcut ────────────────────────────
log "Creating home-screen shortcut..."
cat > "$SHORTCUT_DIR/BackupNow.sh" << EOF
#!/data/data/com.termux/files/usr/bin/sh
# Termux Telegram Backup — Manual Trigger
termux-wake-lock
python3 "${PROJECT_DIR}/backup.py"
EOF
chmod +x "$SHORTCUT_DIR/BackupNow.sh"
ok "Shortcut ready"

# ── Cron Schedule ─────────────────────────────────────
log "Scheduling daily backup at 05:30..."
(crontab -l 2>/dev/null | grep -v "termux_backups_telegram" || true; echo "30 5 * * * termux-wake-lock && python3 ${PROJECT_DIR}/backup.py") | crontab -
ok "Automation scheduled"

# ── First Run Test ────────────────────────────────────
log "Running test ping to Telegram..."
if python3 -c "
import requests, json
with open('${PROJECT_DIR}/config.json') as f: cfg = json.load(f)
r = requests.post(f'https://api.telegram.org/bot{cfg[\'token\']}/getMe', timeout=10)
assert r.json().get('ok'), r.text
print('Bot OK:', r.json()['result']['username'])
" 2>/dev/null; then
    ok "Telegram bot validated"
else
    warn "Bot test failed — check your TOKEN and CHAT_ID"
fi

# ── Success Banner ────────────────────────────────────
banner
cat << EOF

${G}${W}✅ Installation Complete!${RS}

${W}📁 Project Location:${RS}
   Internal Storage → ${C}termux_backups_telegram${RS}

${W}📱 Home Screen Widget:${RS}
   1. Install ${Y}Termux:Widget${RS} from F-Droid.
   2. Long-press home screen → Widgets.
   3. Pick ${C}Termux:Widget → tasks → BackupNow${RS}.

${W}⚠️  Battery:${RS}
   Settings → Apps → Termux → Battery → ${R}Unrestricted${RS}

${W}🚀 Manual Run:${RS}
   ${D}python3 ${PROJECT_DIR}/backup.py${RS}

${W}🗑️  Uninstall:${RS}
   ${D}curl -sL ${REPO_RAW}/install.sh | bash -s -- --uninstall${RS}

${G}System ready. Your files are safe. 🛡️${RS}
EOF
