#!/data/data/com.termux/files/usr/bin/env python3
# ═══════════════════════════════════════════════════════
#   Termux Telegram Backup Engine v1.0.0
#   https://github.com/adebweb/termux-telegram-backup
# ═══════════════════════════════════════════════════════

import os
import sys
import json
import time
import datetime
import requests
from pathlib import Path
from typing import List, Dict, Tuple, Optional

# ── Constants ───────────────────────────────────────────
SCRIPT_DIR = Path(__file__).parent.resolve()
STATE_FILE = SCRIPT_DIR / "last_run.txt"
LOG_FILE   = SCRIPT_DIR / "backup.log"
CONFIG_FILE = SCRIPT_DIR / "config.json"

SUPPORTED_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".apk"}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
VIDEO_EXTS = {".mp4", ".mov"}

# ── Logger ─────────────────────────────────────────────
class Logger:
    @staticmethod
    def _now() -> str:
        return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    @classmethod
    def info(cls, msg: str):
        line = f"[{cls._now()}] [INFO] {msg}"
        print(line)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")

    @classmethod
    def error(cls, msg: str):
        line = f"[{cls._now()}] [ERROR] {msg}"
        print(line, file=sys.stderr)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")

    @classmethod
    def warn(cls, msg: str):
        line = f"[{cls._now()}] [WARN] {msg}"
        print(line)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")

# ── Config Loader ───────────────────────────────────────
def load_config() -> Dict:
    if not CONFIG_FILE.exists():
        Logger.error("config.json not found. Run install.sh first.")
        sys.exit(1)
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        Logger.error(f"Invalid config.json: {e}")
        sys.exit(1)

# ── State Manager ─────────────────────────────────────
def get_last_run() -> float:
    if not STATE_FILE.exists():
        # Default: start of today
        today = datetime.datetime.combine(
            datetime.datetime.now().date(),
            datetime.datetime.min.time()
        )
        return today.timestamp()
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            return float(f.read().strip())
    except (ValueError, OSError) as e:
        Logger.warn(f"Corrupt state file, resetting: {e}")
        return 0.0

def save_last_run(ts: float):
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        f.write(str(ts))

# ── Telegram API ──────────────────────────────────────
class TelegramClient:
    def __init__(self, token: str, chat_id: str):
        self.token = token
        self.chat_id = chat_id
        self.base = f"https://api.telegram.org/bot{token}"

    def send_file(self, path: Path) -> bool:
        ext = path.suffix.lower()
        if ext in IMAGE_EXTS:
            endpoint, key = f"{self.base}/sendPhoto", "photo"
        elif ext in VIDEO_EXTS:
            endpoint, key = f"{self.base}/sendVideo", "video"
        else:
            endpoint, key = f"{self.base}/sendDocument", "document"

        for attempt in range(3):
            try:
                with open(path, "rb") as f:
                    r = requests.post(
                        endpoint,
                        data={
                            "chat_id": self.chat_id,
                            "caption": path.name[:100],
                            "disable_notification": "true"
                        },
                        files={key: f},
                        timeout=60
                    )
                if r.status_code == 200 and r.json().get("ok"):
                    return True
                else:
                    Logger.warn(f"Attempt {attempt+1} failed: {r.json().get('description', 'Unknown')}")
            except requests.RequestException as e:
                Logger.warn(f"Attempt {attempt+1} network error: {e}")
            time.sleep(2 * (attempt + 1))
        return False

    def send_message(self, text: str):
        try:
            requests.post(
                f"{self.base}/sendMessage",
                data={
                    "chat_id": self.chat_id,
                    "text": text,
                    "parse_mode": "Markdown",
                    "disable_notification": "false"
                },
                timeout=10
            )
        except requests.RequestException:
            pass

# ── File Scanner ──────────────────────────────────────
class FileScanner:
    def __init__(self, folders: List[str], max_size_mb: int):
        self.folders = [Path(f) for f in folders if Path(f).exists()]
        self.max_size = max_size_mb * 1024 * 1024
        self.stats = {
            "screenshot": 0,
            "size": 0,
            "old": 0,
            "ext": 0,
            "error": 0
        }

    def scan(self, since: float) -> List[Path]:
        files: List[Path] = []
        for folder in self.folders:
            for root, dirs, filenames in os.walk(folder):
                # Skip hidden directories
                dirs[:] = [d for d in dirs if not d.startswith(".")]
                for filename in filenames:
                    filepath = Path(root) / filename
                    try:
                        if "screenshot" in filepath.name.lower():
                            self.stats["screenshot"] += 1
                            continue
                        if filepath.suffix.lower() not in SUPPORTED_EXTS:
                            self.stats["ext"] += 1
                            continue
                        size = filepath.stat().st_size
                        if size > self.max_size:
                            self.stats["size"] += 1
                            continue
                        mtime = filepath.stat().st_mtime
                        if mtime <= since:
                            self.stats["old"] += 1
                            continue
                        files.append(filepath)
                    except OSError:
                        self.stats["error"] += 1
        files.sort(key=lambda p: p.stat().st_mtime)
        return files

# ── Main Engine ───────────────────────────────────────
def main():
    Logger.info("═" * 50)
    Logger.info("Backup Engine v1.0.0 starting...")

    cfg = load_config()
    token = cfg.get("token", "")
    chat_id = cfg.get("chat_id", "")
    folders = cfg.get("folders", [])
    max_size = cfg.get("max_size_mb", 50)

    if not token or not chat_id:
        Logger.error("Missing token or chat_id in config.json")
        sys.exit(1)

    tg = TelegramClient(token, chat_id)
    scanner = FileScanner(folders, max_size)

    last_run = get_last_run()
    now = time.time()

    Logger.info(f"Scanning {len(folders)} folder(s) for files newer than {datetime.datetime.fromtimestamp(last_run)}")
    files = scanner.scan(last_run)

    if not files:
        msg = (
            "📭 *No new files found*\n\n"
            f"📸 Screenshots skipped: {scanner.stats['screenshot']}\n"
            f"⚖️ Large files skipped: {scanner.stats['size']}\n"
            f"📄 Unsupported types: {scanner.stats['ext']}\n"
            f"🕒 Old files skipped: {scanner.stats['old']}\n"
            f"⚠️ Errors: {scanner.stats['error']}"
        )
        tg.send_message(msg)
        Logger.info("Nothing to backup. Report sent.")
        return

    Logger.info(f"Found {len(files)} file(s) to backup")

    sent, failed, imgs, vids, apks = 0, 0, 0, 0, 0

    for idx, filepath in enumerate(files, 1):
        Logger.info(f"[{idx}/{len(files)}] Uploading: {filepath.name}")
        if tg.send_file(filepath):
            sent += 1
            ext = filepath.suffix.lower()
            if ext in IMAGE_EXTS:
                imgs += 1
            elif ext in VIDEO_EXTS:
                vids += 1
            elif ext == ".apk":
                apks += 1
        else:
            failed += 1
            Logger.error(f"Failed to upload: {filepath.name}")
        time.sleep(1)

    rate = (sent / len(files) * 100) if files else 0
    msg = (
        "📊 *Backup Report*\n\n"
        f"✅ Success: {sent} ({round(rate)}%)\n"
        f"❌ Failed: {failed}\n"
        f"🖼 Images: {imgs}\n"
        f"🎥 Videos: {vids}\n"
        f"📦 APKs: {apks}\n"
        f"🚫 Ignored: {sum(scanner.stats.values())} files"
    )
    tg.send_message(msg)
    save_last_run(now)
    Logger.info("Backup complete. Report sent to Telegram.")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        Logger.warn("Interrupted by user.")
        sys.exit(130)
    except Exception as e:
        Logger.error(f"Fatal error: {e}")
        sys.exit(1)
