#!/usr/bin/env python3
import vlc
from gpiozero import MotionSensor
from pathlib import Path
from time import sleep
from datetime import datetime
import json
import sys

# === Configuration ===
VIDEO_FOLDER = Path('/home/pi/Videos')
LOG_FOLDER = Path('/home/pi/logs')
SETTINGS_FILE = Path("/home/pi/settings.json")
PAUSE_VIDEO = Path("/home/pi/PauseVideo/paused_rotated.mp4")

# Create log folder if it doesn't exist
LOG_FOLDER.mkdir(exist_ok=True)

def log(msg):
    timestamp = f"[{datetime.now().isoformat()}]"
    log_line = f"{timestamp} {msg}"
    print(log_line)
    date_str = datetime.now().strftime("%Y-%m-%d")
    log_file = LOG_FOLDER / f"motion_log_{date_str}.txt"
    with log_file.open("a") as f:
        f.write(f"{log_line}\n")

def read_random_config():
    try:
        with open(SETTINGS_FILE, 'r') as f:
            settings = json.load(f)

        random_settings = settings.get("random", {})
        enabled = random_settings.get("enabled", False)
        interval = random_settings.get("interval", 0)
        video_name = random_settings.get("video_name", "")
        last_updated = random_settings.get("last_updated", "")

        # Update last_updated if enabled on startup
        if enabled:
            new_timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            random_settings["last_updated"] = new_timestamp
            settings["random"] = random_settings
            with open(SETTINGS_FILE, "w") as f:
                json.dump(settings, f, indent=2)
            log(f"[Startup] Updated last_updated to: {new_timestamp}")

        return enabled, interval, video_name, random_settings.get("last_updated", "")

    except Exception as e:
        log(f"Failed to read or update settings.json: {e}")
        return False, 0, "", ""

def get_selected_video():
    try:
        with open(SETTINGS_FILE, 'r') as f:
            settings = json.load(f)
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
        with open(SETTINGS_FILE, 'r') as f:
            settings = json.load(f)
        return settings.get("pause_flag", False)
    except Exception as e:
        log(f"Failed to read pause_flag from settings.json: {e}")
        return False

def main():
    if not VIDEO_FOLDER.exists():
        print(f"Folder {VIDEO_FOLDER} not found")
        sys.exit(1)

    video_files = sorted(VIDEO_FOLDER.glob("*.mp4"))
    if not video_files:
        print("No videos found!")
        sys.exit(1)

    log(f"Found {len(video_files)} video(s)")

    # Initialize PIR sensor
    pir = MotionSensor(4)

    # Load random settings
    enabled, interval, video_name, _ = read_random_config()

    # Get selected video
    media_path = get_selected_video()
    if not media_path:
        media_path = str(video_files[0])
        log(f"Falling back to {media_path}")

    # Setup VLC player and media
    player = vlc.MediaPlayer()
    media = vlc.Media(media_path)
    player.set_media(media)

    # Preload pause video
    pause_media = vlc.Media(str(PAUSE_VIDEO))

    # Start paused with selected video loaded
    player.play()
    sleep(0.5)
    player.set_pause(1)
    player.set_time(0)
    log(f"Loaded video {Path(media_path).name} in paused state")

    paused_mode = False

    try:
        while True:
            pause_flag = read_pause_flag()

            if pause_flag and not paused_mode:
                log("Pause flag detected ON. Switching to pause screen.")
                if player.is_playing():
                    player.stop()
                player.set_media(pause_media)
                player.play()
                sleep(0.5)
                player.set_pause(1)
                player.set_time(0)
                log(f"[PAUSED] Loaded pause screen: {PAUSE_VIDEO.name}")
                paused_mode = True

            elif not pause_flag and paused_mode:
                log("[UNPAUSED] Pause flag cleared, returning to motion-triggered mode")
                if player.is_playing():
                    player.stop()
                new_path = get_selected_video()
                if new_path and new_path != media_path:
                    media_path = new_path
                    log(f"Updated video selection to {Path(media_path).name}")
                media = vlc.Media(media_path)
                player.set_media(media)
                player.play()
                sleep(0.5)
                player.set_pause(1)
                player.set_time(0)
                paused_mode = False

            if not paused_mode:
                log("Waiting for motion...")
                pir.wait_for_motion()
                log("Motion detected! Playing video")
                new_path = get_selected_video()
                if new_path and new_path != media_path:
                    media_path = new_path
                    log(f"Updated video selection to {Path(media_path).name}")
                media = vlc.Media(media_path)
                player.set_media(media)
                player.play()
                sleep(0.5)
                while player.get_state() not in (vlc.State.Ended, vlc.State.Stopped):
                    if read_pause_flag():
                        log("Pause detected mid-playback. Stopping video.")
                        player.stop()
                        break
                    sleep(0.1)
                log("Video ended or paused. Resetting...")
                player.pause()
                player.set_time(0)
            else:
                sleep(1)

    except KeyboardInterrupt:
        log("Exiting")
        player.stop()
        sys.exit(0)

if __name__ == "__main__":
    main()
