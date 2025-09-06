# vlc_helper.py
import json
import random
import threading
import time
import os
from datetime import datetime, timedelta
from pathlib import Path

# Paths
HOME = Path(os.path.expanduser("~"))

SETTINGS_FILE = HOME / "settings.json"
VIDEO_FOLDER = HOME / "videos"
LOG_FOLDER = HOME / "logs"
LOG_FOLDER.mkdir(exist_ok=True)

# Thread control
stop_playlist_thread = threading.Event()

def get_version():
    version_file = HOME / "version.txt"
    try:
        with open(version_file, "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        return "unknown"

VERSION = get_version()

def log(msg):
    timestamp = f"[{datetime.now().isoformat()}]"
    log_line = f"{timestamp} {msg}"
    print(log_line)
    date_str = datetime.now().strftime("%Y-%m-%d")
    log_file = LOG_FOLDER / f"{date_str}.txt"
    with log_file.open("a") as f:
        f.write(f"{log_line}\n")

def load_settings():
    if SETTINGS_FILE.exists():
        with open(SETTINGS_FILE, 'r') as f:
            return json.load(f)
    return {
        "selected_video": "",
        "pause_flag": False,
        "playlist": {
            "mode": "single",
            "interval": 0,
            "last_updated": "",
            "order": [],
            "triggered_flag": True,
            "delay": 0
        }
    }

def save_settings(settings):
    with open(SETTINGS_FILE, 'w') as f:
        json.dump(settings, f, indent=2)

def get_days_schedule():
    settings = load_settings()
    return settings.get("days", {})

def update_days_schedule(days_schedule):
    settings = load_settings()
    settings["days"] = days_schedule
    save_settings(settings)


def get_triggered_flag():
    settings = load_settings()
    playlist = settings.get("playlist", {})

    # Default to False if not set
    flag = playlist.get("triggered_flag", False)

    return bool(flag)

def get_trigger_delay_seconds():
    settings = load_settings()
    playlist = settings.get("playlist", {})

    delay = playlist.get("delay", 0)
    try:
        return int(delay)
    except (ValueError, TypeError):
        return 0

def is_schedule_enabled_now():
    settings = load_settings()
    days = settings.get("days", {})
    
    now = datetime.now()
    current_day = now.strftime("%A")  # e.g., "Monday"
    current_time = now.strftime("%H:%M")  # e.g., "14:30" in 24-hour format

    today_schedule = days.get(current_day, {})

     # If not enabled, schedule is considered always active
    if not today_schedule.get("enabled", False):
        return True

    start = today_schedule.get("start", "00:00")
    end = today_schedule.get("end", "23:59")

    return start <= current_time < end

def get_next_start_time(settings):
    from datetime import datetime, timedelta
    
    days = settings.get("days", {})
    now = datetime.now()
    
    # Loop through next 7 days starting today
    for i in range(7):
        day_check = (now + timedelta(days=i)).strftime("%A")
        schedule = days.get(day_check, {})
        if schedule.get("enabled", False):
            start_str = schedule.get("start", "00:00")
            # Parse start time and create a datetime for that day
            try:
                start_time = datetime.strptime(start_str, "%H:%M").time()
                start_dt = datetime.combine(now.date() + timedelta(days=i), start_time)
                if start_dt > now:
                    return start_dt.strftime("%A %I:%M %p")
            except:
                continue
    return None

def get_playlist_settings():
    settings = load_settings()
    playlist = settings.get("playlist", {})
    return (
        playlist.get("mode", "single"),
        playlist.get("interval", 0),
        playlist.get("last_updated", ""),
        playlist.get("order", []),
        playlist.get("triggered_flag", False),
        playlist.get("delay", 0)
    )

def update_playlist_settings(mode=None, interval=None, last_updated=None, order=None, triggered_flag=None, delay=None):
    settings = load_settings()
    playlist = settings.get("playlist", {})

    if mode is not None:
        playlist["mode"] = mode
    if interval is not None:
        playlist["interval"] = interval
    if last_updated is not None:
        playlist["last_updated"] = last_updated
    if order is not None:
        playlist["order"] = order
    if triggered_flag is not None:
        playlist["triggered_flag"] = triggered_flag
    if interval is not None:
        playlist["delay"] = delay 

    settings["playlist"] = playlist
    save_settings(settings)

def update_playlist_timestamp_on_startup():
    try:
        settings = load_settings()
        playlist = settings.get("playlist", {})
        mode = playlist.get("mode", "single").lower()
        interval = playlist.get("interval", 0)  # interval in minutes
        last_updated_str = playlist.get("last_updated", "")

        if mode not in ("random", "fixed"):
            log(f"[Startup] Playlist mode '{mode}' does not require timestamp update.")
            return

        now = datetime.now()
        last_updated = None
        if last_updated_str:
            try:
                last_updated = datetime.strptime(last_updated_str, "%Y-%m-%d %H:%M:%S")
            except Exception as e:
                log(f"[Startup] Failed to parse last_updated timestamp: {e}")

        # Update only if missing or expired and interval > 0
        if interval > 0 and (not last_updated or (now - last_updated) >= timedelta(minutes=interval)):
            new_timestamp = now.strftime("%Y-%m-%d %H:%M:%S")
            playlist["last_updated"] = new_timestamp
            settings["playlist"] = playlist
            save_settings(settings)
            log(f"[Startup] Playlist mode '{mode}' detected. Updated last_updated to: {new_timestamp}")
        else:
            log(f"[Startup] Playlist timestamp still valid or interval is zero, no update needed.")

    except Exception as e:
        log(f"Failed to update playlist timestamp: {e}")


def get_selected_video():
    try:
        settings = load_settings()
        selected_name = settings.get("selected_video", "").strip()
        video_path = VIDEO_FOLDER / selected_name
        if video_path.exists():
            return str(video_path)
        else:
            log(f"Selected video {selected_name} not found in folder")
            return None
    except Exception as e:
        log(f"Failed to read selected_video from settings.json: {e}")
        return None

def read_pause_flag():
    try:
        settings = load_settings()
        return settings.get("pause_flag", False)
    except Exception as e:
        log(f"Failed to read pause_flag from settings.json: {e}")
        return False

def write_pause_flag(is_paused):
    settings = load_settings()
    settings["pause_flag"] = is_paused
    save_settings(settings)

def playlist_updater():
    while not stop_playlist_thread.is_set():
        mode, interval, last_updated, order = get_playlist_settings()
        pause_flag = read_pause_flag()
        schedule_enabled = is_schedule_enabled_now()
        

        if mode not in ["random", "fixed"] or interval <= 0 or pause_flag or not schedule_enabled:
            time.sleep(5)
            continue

        # Extract active filenames
        active_files = [item["filename"] for item in order if item.get("active", True)]
        if not active_files:
            time.sleep(10)
            continue

        settings = load_settings()
        current_video = settings.get("selected_video", "")
        now = datetime.now()

        try:
            last_dt = datetime.strptime(last_updated, "%Y-%m-%d %H:%M:%S") if last_updated else None
        except Exception as e:
            log(f"Error parsing last_updated: {e}")
            last_dt = None

        if not last_dt or (now - last_dt) >= timedelta(minutes=interval):
            new_video = current_video
            
            if mode == "random":
                if len(active_files) > 1:
                    other_choices = [v for v in active_files if v != current_video]
                    new_video = random.choice(other_choices) if other_choices else current_video  
                else:
                    new_video = active_files[0]

            elif mode == "fixed":
                if current_video in active_files:
                    idx = active_files.index(current_video)
                    new_video = active_files[(idx + 1) % len(active_files)]
                else:
                    new_video = active_files[0]

            last_updated_str = now.strftime("%Y-%m-%d %H:%M:%S")
            settings["selected_video"] = new_video
            settings["playlist"]["last_updated"] = last_updated_str
            save_settings(settings)
            log(f"[Playlist updater] Mode: {mode}, New video: {new_video}, Updated at: {last_updated_str}")

        time.sleep(1)
