#!/data/data/com.termux/files/usr/bin/env bash
# ═══════════════════════════════════════════════════════
#   Termux Telegram Backup — Professional Installer
#   Repo: https://github.com/adebweb/termux-telegram-backup
#   Install:  curl -sL https://raw.githubusercontent.com/adebweb/termux-telegram-backup/main/install.sh | bash
#   Silent:   curl -sL ... | bash -s -- --token <TOKEN> --chat-id <ID> --silent
#   Uninstall: curl -sL ... | bash -s -- --uninstall
# ═══════════════════════════════════════════════════════

# Only catch unbound variables, don't die on command failures
set -u

# ── Metadata ──────────────────────────────────────────
REPO_RAW="https://raw.githubusercontent.com/adebweb/termux-telegram-backup/main"
VERSION="1.0.0"
PROJECT_DIR="/storage/emulated/0/termux_backups_telegram"
SHORTCUT_DIR="$HOME/.shortcuts/tasks"

# ── Colors ────────────────────────────────────────────
R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"
B="\033[1;34m"; C="\033[1;36m"; W="\033[1;37m"
D="\033[2m"; BOLD="\033[1m"; RS="\033[0m"

log()  { echo -e "${B}[•]${RS} $1"; }
ok()   { echo -e "${G}[✓]${RS} $1"; }
warn() { echo -e "${Y}[!]${RS} $1"; }
err()  { echo -e "${R}[✗]${RS} $1"; }
info() { echo -e "${D}    $1${RS}"; }
dbg()  { [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${D}[DBG] $1${RS}"; }

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
VERBOSE=false
TOKEN=""
CHAT_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall|-u) UNINSTALL=true; shift ;;
        --silent|-s)    SILENT=true; shift ;;
        --verbose|-v)   VERBOSE=true; shift ;;
        --token|-t)     TOKEN="$2"; shift 2 ;;
        --chat-id|-c)   CHAT_ID="$2"; shift 2 ;;
        --help|-h)
            echo -e "${C}Usage:${RS}"
            echo "  curl -sL ${REPO_RAW}/install.sh | bash"
            echo "  curl -sL ${REPO_RAW}/install.sh | bash -s -- --token <TOKEN> --chat-id <ID> --silent"
            echo ""
            echo "Options:"
            echo "  -t, --token <TOKEN>    Telegram Bot Token"
            echo "  -c, --chat-id <ID>     Telegram Chat ID"
            echo "  -s, --silent           Non-interactive mode"
            echo "  -v, --verbose          Show debug output"
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
    read -rp "⚠️  This will delete ALL backup data. Continue? [y/N]: " confirm < /dev/tty
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
    exit 1
fi
ok "Environment validated"

# Check network
if ! curl -s --max-time 5 https://api.telegram.org >/dev/null 2>&1; then
    err "No internet connection or Telegram is blocked."
    exit 1
fi
ok "Internet connection OK"

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
    if [[ ! -d "/storage/emulated/0/Download" ]]; then
        err "Storage permission denied."
        exit 1
    fi
fi
ok "Storage access granted"

# ── Interactive Config ────────────────────────────────
banner
if [[ "$SILENT" == false ]]; then
    echo -e "${W}${BOLD}⚙️  Configuration${RS}
"
fi

if [[ -z "$TOKEN" ]]; then
    if [[ "$SILENT" == true ]]; then
        err "--token is required in silent mode."
        exit 1
    fi
    read -rp "🤖 Telegram BOT_TOKEN: " TOKEN < /dev/tty
    if [[ -z "$TOKEN" ]]; then
        err "BOT_TOKEN is required."
        exit 1
    fi
fi

if [[ -z "$CHAT_ID" ]]; then
    if [[ "$SILENT" == true ]]; then
        err "--chat-id is required in silent mode."
        exit 1
    fi
    read -rp "💬 Telegram CHAT_ID:  " CHAT_ID < /dev/tty
    if [[ -z "$CHAT_ID" ]]; then
        err "CHAT_ID is required."
        exit 1
    fi
fi

ADD_WA="n"
if [[ "$SILENT" == false ]]; then
    echo ""
    info "Default folders: DCIM, Download, Pictures, Movies"
    read -rp "➕ Include WhatsApp Statuses? [y/N]: " ADD_WA < /dev/tty
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

if ! curl -sL "${REPO_RAW}/backup.py" -o "${PROJECT_DIR}/backup.py"; then
    err "Failed to download backup.py"
    exit 1
fi

if ! curl -sL "${REPO_RAW}/config.json" -o "${PROJECT_DIR}/config.json"; then
    err "Failed to download config.json"
    exit 1
fi

# Inject user config into config.json
sed -i "s|YOUR_BOT_TOKEN|$TOKEN|g" "${PROJECT_DIR}/config.json"
sed -i "s|YOUR_CHAT_ID|$CHAT_ID|g" "${PROJECT_DIR}/config.json"
sed -i "s|\[YOUR_FOLDERS\]|[$FOLDERS]|g" "${PROJECT_DIR}/config.json"

chmod +x "${PROJECT_DIR}/backup.py"
ok "Engine downloaded and configured"

# ── Create Widget Shortcut ────────────────────────────
log "Creating home-screen shortcut..."
cat > "$SHORTCUT_DIR/BackupNow.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
python3 /storage/emulated/0/termux_backups_telegram/backup.py
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
r = requests.post('https://api.telegram.org/bot' + cfg['token'] + '/getMe', timeout=10)
assert r.json().get('ok'), r.text
print('Bot OK:', r.json()['result']['username'])
" 2>/dev/null; then
    ok "Telegram bot validated"
else
    warn "Bot test failed — check your TOKEN and CHAT_ID"
fi

# ── Success Banner ────────────────────────────────────
banner
echo ""
echo -e "${G}${W}✅ Installation Complete!${RS}"
echo ""
echo -e "${W}📁 Project Location:${RS}"
echo -e "   Internal Storage → ${C}termux_backups_telegram${RS}"
echo ""
echo -e "${W}📱 Home Screen Widget:${RS}"
echo -e "   1. Install ${Y}Termux:Widget${RS} from F-Droid."
echo -e "   2. Long-press home screen → Widgets."
echo -e "   3. Pick ${C}Termux:Widget → tasks → BackupNow${RS}."
echo ""
echo -e "${W}⚠️  Battery:${RS}"
echo -e "   Settings → Apps → Termux → Battery → ${R}Unrestricted${RS}"
echo ""
echo -e "${W}🚀 Manual Run:${RS}"
echo -e "   ${D}python3 ${PROJECT_DIR}/backup.py${RS}"
echo ""
echo -e "${W}🗑️  Uninstall:${RS}"
echo -e "   ${D}curl -sL ${REPO_RAW}/install.sh | bash -s -- --uninstall${RS}"
echo ""
echo -e "${G}System ready. Your files are safe. 🛡️${RS}"
