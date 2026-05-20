#!/data/data/com.termux/files/usr/bin/env python3
# ═══════════════════════════════════════════════════════
#   Termux Telegram Backup Engine v3.0
#   Full Control | Extended Reports | Deep Customization
#   Repo: https://github.com/adebweb/termux-telegram-backup
# ═══════════════════════════════════════════════════════

import os
import sys
import json
import time
import datetime
import requests
import argparse
import hashlib
from pathlib import Path
from typing import List, Dict, Set, Tuple, Optional
from dataclasses import dataclass, asdict
from enum import Enum

# ── Constants ───────────────────────────────────────────
SCRIPT_DIR = Path(__file__).parent.resolve()
STATE_FILE = SCRIPT_DIR / "state.json"
LOG_FILE   = SCRIPT_DIR / "backup.log"
CONFIG_FILE = SCRIPT_DIR / "config.json"
HISTORY_FILE = SCRIPT_DIR / "history.json"

SUPPORTED_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp",
                  ".mp4", ".mov", ".avi", ".mkv", ".wmv",
                  ".mp3", ".m4a", ".ogg", ".wav", ".flac",
                  ".apk", ".pdf", ".doc", ".docx", ".xls", ".xlsx",
                  ".ppt", ".pptx", ".txt", ".zip", ".rar", ".7z"}

IMAGE_EXTS  = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"}
VIDEO_EXTS  = {".mp4", ".mov", ".avi", ".mkv", ".wmv"}
AUDIO_EXTS  = {".mp3", ".m4a", ".ogg", ".wav", ".flac"}
DOC_EXTS    = {".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt"}
ARCHIVE_EXTS = {".zip", ".rar", ".7z"}

class FileCategory(Enum):
    IMAGE = "image"
    VIDEO = "video"
    AUDIO = "audio"
    DOCUMENT = "document"
    APK = "apk"
    ARCHIVE = "archive"
    OTHER = "other"

# ── Data Classes ──────────────────────────────────────
@dataclass
class ScanStats:
    screenshots: int = 0
    too_large: int = 0
    too_old: int = 0
    unsupported: int = 0
    hidden: int = 0
    duplicates: int = 0
    errors: int = 0
    total_scanned: int = 0

    @property
    def total_ignored(self) -> int:
        return (self.screenshots + self.too_large + self.too_old +
                self.unsupported + self.hidden + self.duplicates + self.errors)

@dataclass
class UploadResult:
    success: int = 0
    failed: int = 0
    images: int = 0
    videos: int = 0
    audio: int = 0
    documents: int = 0
    apks: int = 0
    archives: int = 0
    total_bytes: int = 0
    duration_seconds: float = 0.0

@dataclass
class BackupSession:
    timestamp: str
    files_found: int
    files_uploaded: int
    files_failed: int
    bytes_uploaded: int
    duration: float
    categories: Dict[str, int]

# ── Logger ────────────────────────────────────────────
class Logger:
    LEVELS = {"DEBUG": 0, "INFO": 1, "WARN": 2, "ERROR": 3}

    def __init__(self, level: str = "INFO"):
        self.level = self.LEVELS.get(level, 1)

    def _now(self) -> str:
        return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    def _write(self, level: str, msg: str):
        if self.LEVELS.get(level, 99) >= self.level:
            line = f"[{self._now()}] [{level}] {msg}"
            print(line)
            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write(line + "\n")

    def debug(self, msg: str): self._write("DEBUG", msg)
    def info(self, msg: str):  self._write("INFO", msg)
    def warn(self, msg: str):  self._write("WARN", msg)
    def error(self, msg: str): self._write("ERROR", msg)

# ── Config Manager ────────────────────────────────────
class ConfigManager:
    DEFAULTS = {
        "token": "",
        "chat_id": "",
        "folders": [
            "/storage/emulated/0/DCIM",
            "/storage/emulated/0/Download",
            "/storage/emulated/0/Pictures",
            "/storage/emulated/0/Movies"
        ],
        "max_size_mb": 50,
        "exclude_screenshots": True,
        "exclude_patterns": [],
        "include_audio": False,
        "include_documents": False,
        "include_archives": False,
        "deduplicate": True,
        "rate_limit_seconds": 1.0,
        "retry_attempts": 3,
        "notification_level": "summary",  # none, summary, detailed, verbose
        "backup_mode": "incremental",     # incremental, full, dry-run
        "version": "3.0"
    }

    def __init__(self, path: Path = CONFIG_FILE):
        self.path = path
        self._data = self._load()

    def _load(self) -> Dict:
        if not self.path.exists():
            return dict(self.DEFAULTS)
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                data = json.load(f)
                # Merge with defaults for new fields
                for k, v in self.DEFAULTS.items():
                    if k not in data:
                        data[k] = v
                return data
        except (json.JSONDecodeError, OSError) as e:
            print(f"[ERROR] Config load failed: {e}. Using defaults.")
            return dict(self.DEFAULTS)

    def save(self):
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(self._data, f, indent=2, ensure_ascii=False)
            f.write("\n")

    def get(self, key: str, default=None):
        return self._data.get(key, default)

    def set(self, key: str, value):
        self._data[key] = value
        self.save()

    @property
    def token(self) -> str: return self._data.get("token", "")
    @property
    def chat_id(self) -> str: return self._data.get("chat_id", "")
    @property
    def folders(self) -> List[str]: return self._data.get("folders", [])
    @property
    def max_size_mb(self) -> int: return self._data.get("max_size_mb", 50)
    @property
    def backup_mode(self) -> str: return self._data.get("backup_mode", "incremental")
    @property
    def notification_level(self) -> str: return self._data.get("notification_level", "summary")
    @property
    def rate_limit(self) -> float: return self._data.get("rate_limit_seconds", 1.0)
    @property
    def retry_attempts(self) -> int: return self._data.get("retry_attempts", 3)
    @property
    def exclude_screenshots(self) -> bool: return self._data.get("exclude_screenshots", True)
    @property
    def deduplicate(self) -> bool: return self._data.get("deduplicate", True)

# ── State Manager ─────────────────────────────────────
class StateManager:
    def __init__(self, path: Path = STATE_FILE):
        self.path = path
        self._data = self._load()

    def _load(self) -> Dict:
        if not self.path.exists():
            return {"last_run": 0, "uploaded_hashes": [], "total_sessions": 0, "total_files": 0}
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            return {"last_run": 0, "uploaded_hashes": [], "total_sessions": 0, "total_files": 0}

    def save(self):
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(self._data, f, indent=2)
            f.write("\n")

    @property
    def last_run(self) -> float:
        return self._data.get("last_run", 0)

    @last_run.setter
    def last_run(self, value: float):
        self._data["last_run"] = value
        self.save()

    @property
    def uploaded_hashes(self) -> Set[str]:
        return set(self._data.get("uploaded_hashes", []))

    def add_hash(self, file_hash: str):
        hashes = self.uploaded_hashes
        hashes.add(file_hash)
        self._data["uploaded_hashes"] = list(hashes)
        self.save()

    def record_session(self, files_count: int):
        self._data["total_sessions"] = self._data.get("total_sessions", 0) + 1
        self._data["total_files"] = self._data.get("total_files", 0) + files_count
        self.save()

# ── File Scanner ──────────────────────────────────────
class FileScanner:
    def __init__(self, config: ConfigManager, logger: Logger):
        self.cfg = config
        self.log = logger
        self.max_bytes = config.max_size_mb * 1024 * 1024
        self.exclude_patterns = [p.lower() for p in config.get("exclude_patterns", [])]

    def _file_hash(self, path: Path) -> str:
        """Quick hash for deduplication (first 8KB + size)."""
        try:
            h = hashlib.md5()
            h.update(str(path.stat().st_size).encode())
            with open(path, "rb") as f:
                h.update(f.read(8192))
            return h.hexdigest()
        except OSError:
            return ""

    def _categorize(self, path: Path) -> FileCategory:
        ext = path.suffix.lower()
        if ext in IMAGE_EXTS: return FileCategory.IMAGE
        if ext in VIDEO_EXTS: return FileCategory.VIDEO
        if ext in AUDIO_EXTS: return FileCategory.AUDIO
        if ext == ".apk": return FileCategory.APK
        if ext in DOC_EXTS: return FileCategory.DOCUMENT
        if ext in ARCHIVE_EXTS: return FileCategory.ARCHIVE
        return FileCategory.OTHER

    def _should_include(self, path: Path) -> Tuple[bool, str]:
        """Returns (should_include, reason_if_not)."""
        name_lower = path.name.lower()

        # Screenshots
        if self.cfg.exclude_screenshots and "screenshot" in name_lower:
            return False, "screenshot"

        # Custom exclude patterns
        for pattern in self.exclude_patterns:
            if pattern in name_lower:
                return False, f"excluded_pattern:{pattern}"

        # Extension check
        ext = path.suffix.lower()
        allowed = set(SUPPORTED_EXTS)
        if not self.cfg.get("include_audio", False):
            allowed -= AUDIO_EXTS
        if not self.cfg.get("include_documents", False):
            allowed -= DOC_EXTS
        if not self.cfg.get("include_archives", False):
            allowed -= ARCHIVE_EXTS

        if ext not in allowed:
            return False, f"unsupported_ext:{ext}"

        # Size check
        try:
            if path.stat().st_size > self.max_bytes:
                return False, "too_large"
        except OSError:
            return False, "stat_error"

        return True, ""

    def scan(self, since: float, state: StateManager) -> Tuple[List[Path], ScanStats]:
        files = []
        stats = ScanStats()
        known_hashes = state.uploaded_hashes if self.cfg.deduplicate else set()

        for folder_path in self.cfg.folders:
            folder = Path(folder_path)
            if not folder.exists():
                self.log.warn(f"Folder not found: {folder}")
                continue

            self.log.info(f"Scanning: {folder}")
            for root, dirs, names in os.walk(folder):
                # Skip hidden directories
                dirs[:] = [d for d in dirs if not d.startswith(".")]

                for name in names:
                    stats.total_scanned += 1
                    path = Path(root) / name

                    try:
                        # Hidden files
                        if name.startswith("."):
                            stats.hidden += 1
                            continue

                        # Include check
                        should, reason = self._should_include(path)
                        if not should:
                            if reason == "screenshot": stats.screenshots += 1
                            elif reason == "too_large": stats.too_large += 1
                            elif reason.startswith("unsupported"): stats.unsupported += 1
                            elif reason.startswith("excluded"): stats.unsupported += 1
                            elif reason == "stat_error": stats.errors += 1
                            continue

                        # Time check (incremental mode)
                        if self.cfg.backup_mode == "incremental":
                            mtime = path.stat().st_mtime
                            if mtime <= since:
                                stats.too_old += 1
                                continue

                        # Deduplication
                        if self.cfg.deduplicate:
                            fh = self._file_hash(path)
                            if fh in known_hashes:
                                stats.duplicates += 1
                                continue
                            path._file_hash = fh  # Attach for later

                        files.append(path)

                    except OSError:
                        stats.errors += 1

        files.sort(key=lambda p: p.stat().st_mtime)
        self.log.info(f"Scan complete: {len(files)} files to upload, {stats.total_ignored} ignored")
        return files, stats

# ── Telegram Client ───────────────────────────────────
class TelegramClient:
    def __init__(self, token: str, chat_id: str, logger: Logger):
        self.token = token
        self.chat_id = chat_id
        self.log = logger
        self.base = f"https://api.telegram.org/bot{token}"

    def _endpoint(self, category: FileCategory) -> Tuple[str, str]:
        if category == FileCategory.IMAGE:
            return f"{self.base}/sendPhoto", "photo"
        if category == FileCategory.VIDEO:
            return f"{self.base}/sendVideo", "video"
        if category == FileCategory.AUDIO:
            return f"{self.base}/sendAudio", "audio"
        return f"{self.base}/sendDocument", "document"

    def upload(self, path: Path, category: FileCategory, attempts: int = 3) -> bool:
        url, key = self._endpoint(category)

        for attempt in range(attempts):
            try:
                with open(path, "rb") as f:
                    r = requests.post(url, data={
                        "chat_id": self.chat_id,
                        "caption": path.name[:100],
                        "disable_notification": "true"
                    }, files={key: f}, timeout=120)

                if r.status_code == 200 and r.json().get("ok"):
                    return True
                else:
                    err = r.json().get("description", "Unknown error")
                    self.log.warn(f"Attempt {attempt+1} failed: {err}")
            except requests.RequestException as e:
                self.log.warn(f"Attempt {attempt+1} network error: {e}")

            if attempt < attempts - 1:
                time.sleep(2 * (attempt + 1))

        return False

    def send_message(self, text: str, parse_mode: str = "Markdown"):
        try:
            requests.post(f"{self.base}/sendMessage", data={
                "chat_id": self.chat_id,
                "text": text,
                "parse_mode": parse_mode,
                "disable_web_page_preview": "true"
            }, timeout=15)
        except Exception:
            pass

    def validate(self) -> Tuple[bool, str]:
        try:
            r = requests.post(f"{self.base}/getMe", timeout=10)
            if r.status_code == 200 and r.json().get("ok"):
                return True, r.json()["result"]["username"]
            return False, r.json().get("description", "Invalid token")
        except Exception as e:
            return False, str(e)

# ── Report Builder ────────────────────────────────────
class ReportBuilder:
    def __init__(self, config: ConfigManager):
        self.level = config.notification_level

    def build_summary(self, result: UploadResult, stats: ScanStats, duration: float) -> str:
        rate = (result.success / (result.success + result.failed) * 100) if (result.success + result.failed) > 0 else 0

        lines = [
            "📊 *Backup Report*",
            "",
            f"⏱ Duration: `{self._fmt_duration(duration)}`",
            f"📤 Uploaded: `{result.success}` files ({round(rate)}%)",
            f"❌ Failed: `{result.failed}`",
            f"🚫 Ignored: `{stats.total_ignored}` files",
            "",
            "📁 *By Category:*",
            f"🖼 Images: `{result.images}`",
            f"🎥 Videos: `{result.videos}`",
            f"🎵 Audio: `{result.audio}`",
            f"📄 Docs: `{result.documents}`",
            f"📦 APKs: `{result.apks}`",
            f"🗜 Archives: `{result.archives}`",
            "",
            f"📦 Total: `{self._fmt_bytes(result.total_bytes)}`",
        ]
        return "\n".join(lines)

    def build_detailed(self, result: UploadResult, stats: ScanStats, duration: float,
                       failed_files: List[str]) -> str:
        base = self.build_summary(result, stats, duration)

        details = ["\n📋 *Details:*"]
        details.append(f"🔍 Scanned: `{stats.total_scanned}` files")
        details.append(f"📸 Screenshots skipped: `{stats.screenshots}`")
        details.append(f"⚖️ Too large: `{stats.too_large}`")
        details.append(f"🕒 Too old: `{stats.too_old}`")
        details.append(f"📄 Unsupported: `{stats.unsupported}`")
        details.append(f"👁 Hidden: `{stats.hidden}`")
        details.append(f"🔁 Duplicates: `{stats.duplicates}`")
        details.append(f"⚠️ Errors: `{stats.errors}`")

        if failed_files:
            details.append(f"\n❌ *Failed Files ({len(failed_files)}):*")
            for name in failed_files[:10]:
                details.append(f"• `{name}`")
            if len(failed_files) > 10:
                details.append(f"... and {len(failed_files) - 10} more")

        return base + "\n" + "\n".join(details)

    def build_verbose(self, result: UploadResult, stats: ScanStats, duration: float,
                      failed_files: List[str], uploaded_files: List[str]) -> str:
        base = self.build_detailed(result, stats, duration, failed_files)

        if uploaded_files:
            base += "\n\n✅ *Uploaded Files:*\n"
            for name in uploaded_files[:20]:
                base += f"• `{name}`\n"
            if len(uploaded_files) > 20:
                base += f"... and {len(uploaded_files) - 20} more\n"

        return base

    def build_empty(self, stats: ScanStats) -> str:
        lines = [
            "📭 *No new files found*",
            "",
            f"🔍 Scanned: `{stats.total_scanned}` files",
            "",
            "📋 *Breakdown:*",
            f"📸 Screenshots: `{stats.screenshots}`",
            f"⚖️ Too large: `{stats.too_large}`",
            f"🕒 Too old: `{stats.too_old}`",
            f"📄 Unsupported: `{stats.unsupported}`",
            f"👁 Hidden: `{stats.hidden}`",
            f"🔁 Duplicates: `{stats.duplicates}`",
            f"⚠️ Errors: `{stats.errors}`",
        ]
        return "\n".join(lines)

    @staticmethod
    def _fmt_duration(seconds: float) -> str:
        if seconds < 60:
            return f"{seconds:.1f}s"
        m, s = divmod(int(seconds), 60)
        if m < 60:
            return f"{m}m {s}s"
        h, m = divmod(m, 60)
        return f"{h}h {m}m {s}s"

    @staticmethod
    def _fmt_bytes(b: int) -> str:
        for unit in ["B", "KB", "MB", "GB"]:
            if b < 1024:
                return f"{b:.1f} {unit}"
            b /= 1024
        return f"{b:.1f} TB"

# ── History Manager ───────────────────────────────────
class HistoryManager:
    def __init__(self, path: Path = HISTORY_FILE):
        self.path = path
        self.sessions = self._load()

    def _load(self) -> List[Dict]:
        if not self.path.exists():
            return []
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            return []

    def save(self):
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(self.sessions[-50:], f, indent=2)  # Keep last 50
            f.write("\n")

    def add(self, session: BackupSession):
        self.sessions.append(asdict(session))
        self.save()

    def get_stats(self) -> Dict:
        if not self.sessions:
            return {"total_sessions": 0, "total_files": 0, "total_bytes": 0}
        return {
            "total_sessions": len(self.sessions),
            "total_files": sum(s.get("files_uploaded", 0) for s in self.sessions),
            "total_bytes": sum(s.get("bytes_uploaded", 0) for s in self.sessions),
            "avg_files_per_session": sum(s.get("files_uploaded", 0) for s in self.sessions) / len(self.sessions) if self.sessions else 0,
            "last_session": self.sessions[-1].get("timestamp", "N/A") if self.sessions else "N/A"
        }

# ── Main Engine ───────────────────────────────────────
class BackupEngine:
    def __init__(self, config: ConfigManager, logger: Logger):
        self.cfg = config
        self.log = logger
        self.state = StateManager()
        self.history = HistoryManager()
        self.telegram = TelegramClient(config.token, config.chat_id, logger)
        self.scanner = FileScanner(config, logger)
        self.reporter = ReportBuilder(config)

    def run(self, dry_run: bool = False) -> UploadResult:
        start_time = time.time()
        self.log.info("=" * 50)
        self.log.info(f"Backup Engine v3.0 | Mode: {self.cfg.backup_mode}")

        # Validate config
        if not self.cfg.token or not self.cfg.chat_id:
            self.log.error("Missing token or chat_id in config.json")
            sys.exit(1)

        # Validate bot
        valid, msg = self.telegram.validate()
        if not valid:
            self.log.error(f"Bot validation failed: {msg}")
            sys.exit(1)
        self.log.info(f"Bot validated: @{msg}")

        # Scan files
        since = 0 if self.cfg.backup_mode == "full" else self.state.last_run
        files, stats = self.scanner.scan(since, self.state)

        if not files:
            report = self.reporter.build_empty(stats)
            self.telegram.send_message(report)
            self.log.info("Nothing to backup. Empty report sent.")
            return UploadResult()

        if dry_run or self.cfg.backup_mode == "dry-run":
            self.log.info(f"DRY RUN: Would upload {len(files)} files")
            for f in files[:10]:
                self.log.info(f"  - {f.name} ({self.reporter._fmt_bytes(f.stat().st_size)})")
            if len(files) > 10:
                self.log.info(f"  ... and {len(files) - 10} more")
            return UploadResult()

        # Upload
        self.log.info(f"Starting upload of {len(files)} files...")
        result = UploadResult()
        failed_files = []
        uploaded_files = []

        for idx, path in enumerate(files, 1):
            category = self.scanner._categorize(path)
            self.log.info(f"[{idx}/{len(files)}] {path.name} ({category.value})")

            if self.telegram.upload(path, category, self.cfg.retry_attempts):
                result.success += 1
                result.total_bytes += path.stat().st_size
                uploaded_files.append(path.name)

                if category == FileCategory.IMAGE: result.images += 1
                elif category == FileCategory.VIDEO: result.videos += 1
                elif category == FileCategory.AUDIO: result.audio += 1
                elif category == FileCategory.DOCUMENT: result.documents += 1
                elif category == FileCategory.APK: result.apks += 1
                elif category == FileCategory.ARCHIVE: result.archives += 1

                # Track hash for deduplication
                if hasattr(path, '_file_hash'):
                    self.state.add_hash(path._file_hash)
            else:
                result.failed += 1
                failed_files.append(path.name)
                self.log.error(f"Failed: {path.name}")

            time.sleep(self.cfg.rate_limit)

        result.duration_seconds = time.time() - start_time

        # Save state
        self.state.last_run = time.time()
        self.state.record_session(result.success)

        # Build and send report
        if self.cfg.notification_level == "none":
            self.log.info("Notification suppressed (level: none)")
        elif self.cfg.notification_level == "verbose":
            report = self.reporter.build_verbose(result, stats, result.duration_seconds, failed_files, uploaded_files)
            self.telegram.send_message(report)
        elif self.cfg.notification_level == "detailed":
            report = self.reporter.build_detailed(result, stats, result.duration_seconds, failed_files)
            self.telegram.send_message(report)
        else:
            report = self.reporter.build_summary(result, stats, result.duration_seconds)
            self.telegram.send_message(report)

        # Save to history
        session = BackupSession(
            timestamp=datetime.datetime.now().isoformat(),
            files_found=len(files),
            files_uploaded=result.success,
            files_failed=result.failed,
            bytes_uploaded=result.total_bytes,
            duration=result.duration_seconds,
            categories={
                "images": result.images,
                "videos": result.videos,
                "audio": result.audio,
                "documents": result.documents,
                "apks": result.apks,
                "archives": result.archives
            }
        )
        self.history.add(session)

        self.log.info(f"Backup complete: {result.success} uploaded, {result.failed} failed in {result.duration_seconds:.1f}s")
        return result

# ── CLI ───────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Termux Telegram Backup v3.0")
    parser.add_argument("--config", "-c", help="Path to config.json")
    parser.add_argument("--dry-run", "-d", action="store_true", help="Simulate without uploading")
    parser.add_argument("--full", "-f", action="store_true", help="Full backup (ignore last_run)")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose logging")
    parser.add_argument("--stats", "-s", action="store_true", help="Show history stats")
    parser.add_argument("--reset", "-r", action="store_true", help="Reset state (re-upload everything)")
    args = parser.parse_args()

    config_path = Path(args.config) if args.config else CONFIG_FILE
    config = ConfigManager(config_path)

    if args.stats:
        history = HistoryManager()
        stats = history.get_stats()
        print("\n📊 Backup History Stats")
        print("═" * 30)
        print(f"Total Sessions: {stats['total_sessions']}")
        print(f"Total Files:    {stats['total_files']}")
        print(f"Total Bytes:    {ReportBuilder._fmt_bytes(stats['total_bytes'])}")
        print(f"Avg/Session:    {stats['avg_files_per_session']:.1f} files")
        print(f"Last Session:   {stats['last_session']}")
        print()
        return

    if args.reset:
        state = StateManager()
        state.last_run = 0
        state._data["uploaded_hashes"] = []
        state.save()
        print("✅ State reset. Next backup will re-upload everything.")
        return

    if args.full:
        config.set("backup_mode", "full")

    log_level = "DEBUG" if args.verbose else "INFO"
    logger = Logger(log_level)
    engine = BackupEngine(config, logger)

    try:
        result = engine.run(dry_run=args.dry_run)
        sys.exit(0 if result.failed == 0 else 1)
    except KeyboardInterrupt:
        logger.info("Interrupted by user.")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
