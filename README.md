<div align="center">

# 📦 Termux Telegram Backup

**One-line installer for automated Android media backups to Telegram.**

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/adebweb/termux-telegram-backup)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Termux](https://img.shields.io/badge/Termux-Compatible-orange.svg)](https://termux.dev)

</div>

---

## 🚀 Quick Install

Copy & paste this **single command** into Termux:

```bash
curl -sL https://raw.githubusercontent.com/adebweb/termux-telegram-backup/main/install.sh | bash
```

Or with **silent / non-interactive** mode (perfect for automation):

```bash
curl -sL https://raw.githubusercontent.com/adebweb/termux-telegram-backup/main/install.sh | bash -s --   --token "YOUR_BOT_TOKEN"   --chat-id "YOUR_CHAT_ID"   --silent
```

---

## 📋 What It Does

| Feature | Description |
|---------|-------------|
| 🖼 **Images** | Auto-uploads `.jpg`, `.jpeg`, `.png`, `.webp` as photos |
| 🎥 **Videos** | Auto-uploads `.mp4`, `.mov` as videos |
| 📦 **APKs** | Auto-uploads `.apk` files as documents |
| 🕒 **Incremental** | Only uploads files created **since last run** |
| 📊 **Reports** | Sends a detailed Markdown report to Telegram after each run |
| ⏰ **Scheduled** | Daily cron job at **05:30 AM** |
| 📱 **Widget** | Home-screen one-tap backup via Termux:Widget |
| 🗑️ **Uninstall** | One-line removal with `--uninstall` flag |

---

## 🛠️ Manual Setup (If You Prefer)

```bash
# 1. Clone the repo
git clone https://github.com/adebweb/termux-telegram-backup.git

# 2. Edit config
nano termux-telegram-backup/config.json

# 3. Run
python3 termux-telegram-backup/backup.py
```

---

## ⚙️ Configuration

The installer creates `config.json` in your internal storage:

```json
{
  "token": "123456:ABC-DEF...",
  "chat_id": "123456789",
  "folders": [
    "/storage/emulated/0/DCIM",
    "/storage/emulated/0/Download",
    "/storage/emulated/0/Pictures",
    "/storage/emulated/0/Movies"
  ],
  "max_size_mb": 50
}
```

| Key | Description |
|-----|-------------|
| `token` | Your Telegram Bot token from [@BotFather](https://t.me/botfather) |
| `chat_id` | Your numeric Chat ID (use [@userinfobot](https://t.me/userinfobot)) |
| `folders` | List of absolute paths to scan |
| `max_size_mb` | Skip files larger than this (default: 50) |

---

## 📱 Home Screen Widget

1. Install **Termux:Widget** from [F-Droid](https://f-droid.org/packages/com.termux.widget/).
2. Long-press your home screen → **Widgets**.
3. Find **Termux:Widget** → `tasks` → `BackupNow`.
4. Tap the widget anytime to run an instant backup.

---

## ⏰ Cron Schedule

The installer registers a daily cron job:

```cron
30 5 * * * termux-wake-lock && python3 /storage/emulated/0/termux_backups_telegram/backup.py
```

To change the time, edit your crontab:

```bash
crontab -e
```

---

## 🗑️ Uninstall

```bash
curl -sL https://raw.githubusercontent.com/adebweb/termux-telegram-backup/main/install.sh | bash -s -- --uninstall
```

Or manually:

```bash
rm -rf /storage/emulated/0/termux_backups_telegram
rm -f ~/.shortcuts/tasks/BackupNow.sh
crontab -l | grep -v "termux_backups_telegram" | crontab -
```

---

## 🛡️ Privacy & Security

- **No data leaves your device** except to **your own** Telegram bot.
- The script runs **entirely offline** except during upload.
- No analytics, no tracking, no third-party servers.
- Source code is fully open — audit it yourself.

---

## 📁 Project Structure

```
termux-telegram-backup/
├── install.sh      # One-line installer
├── backup.py       # Backup engine (Python 3)
├── config.json     # User configuration
├── README.md       # This file
└── LICENSE         # MIT License
```

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| "Storage permission denied" | Run `termux-setup-storage` and tap **Allow** |
| "No internet connection" | Check WiFi / mobile data |
| "Bot test failed" | Verify your `token` and `chat_id` |
| Cron not firing | Disable battery optimization for Termux |
| Widget not appearing | Ensure `Termux:Widget` is installed |

---

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.

---

<div align="center">

**Built with ❤️ for the Termux community.**

</div>
