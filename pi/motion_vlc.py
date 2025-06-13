#!/usr/bin/env python3
import vlc
import sys
import atexit
import threading
from time import sleep
from gpiozero import MotionSensor
from pathlib import Path
from shared.vlc_helper import (
    log,
    playlist_updater,
    stop_playlist_thread,
    update_playlist_timestamp_on_startup,
    get_selected_video,
    read_pause_flag
)

LOG_FOLDER = Path('/home/pi/logs')
VIDEO_FOLDER = Path('/home/pi/videos')
PAUSE_VIDEO = Path("/home/pi/pause_video/paused_rotated.mp4")

def on_exit():
    try:
        player.stop()
    except Exception:
        pass
    log("[EXIT] Script is exiting.")

def main():
    log("SYSTEM HAS STARTED")
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

    # Start playlist updater thread
    update_playlist_timestamp_on_startup()
    global playlist_thread
    playlist_thread = threading.Thread(target=playlist_updater, daemon=True)
    playlist_thread.start()
    log("Started playlist updater thread")

    # VLC setup using proper instance
    instance = vlc.Instance()
    player = instance.media_player_new()
    pause_media = instance.media_new(str(PAUSE_VIDEO))

    # Start with selected or fallback video
    media_path = get_selected_video()
    if not media_path:
        media_path = str(video_files[0])
        log(f"Falling back to {media_path}")

    try:
        while True:
            log("Waiting for motion...")
            pir.wait_for_motion()
            log("Motion detected!")

            pause_flag = read_pause_flag()

            if pause_flag:
                log("Pause flag is ON. Playing pause screen.")
                media = pause_media
                media_path = str(PAUSE_VIDEO)
            else:
                new_path = get_selected_video()
                if new_path and new_path != media_path:
                    media_path = new_path
                    log(f"Updated video selection to {Path(media_path).name}")
                media = instance.media_new(media_path)

            player.set_media(media)
            player.play()
            sleep(0.5)

            while player.get_state() not in (vlc.State.Ended, vlc.State.Stopped, vlc.State.Error):
                sleep(0.1)

            log("Video ended. Resetting player...")
            player.stop()  # Use stop() instead of pause/resetting time

    except KeyboardInterrupt:
        log("Exiting")
        stop_playlist_thread.set()
        playlist_thread.join()
        player.stop()
        sys.exit(0)




def on_exit():
    log("[EXIT] Script is exiting.")

atexit.register(on_exit)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        log("[CRASH] Uncaught exception:")
        log(traceback.format_exc())
        raise
