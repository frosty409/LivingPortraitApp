from flask import Flask, render_template, request, redirect, url_for, flash, send_from_directory
from pathlib import Path
import os
import threading
import time
import random
from datetime import datetime, timedelta
import json

app = Flask(__name__)
app.secret_key = 'replace-this-with-a-secure-random-key'

VIDEO_FOLDER = Path("/home/pi/Videos")
LOG_FOLDER = Path("/home/pi/logs")
SETTINGS_FILE = Path("/home/pi/settings.json")

VIDEO_FOLDER.mkdir(parents=True, exist_ok=True)
LOG_FOLDER.mkdir(parents=True, exist_ok=True)

# Thread control
random_thread = None
stop_random_thread = threading.Event()

def load_settings():
    if SETTINGS_FILE.exists():
        with open(SETTINGS_FILE, 'r') as f:
            return json.load(f)
    return {
        "selected_video": "",
        "random": {
            "enabled": False,
            "interval": 0,
            "video_name": "",
            "last_updated": ""
        },
        "pause_flag": False
    }

def save_settings(settings):
    with open(SETTINGS_FILE, 'w') as f:
        json.dump(settings, f, indent=2)

def get_random_config():
    settings = load_settings()
    r = settings.get("random", {})
    return (
        r.get("enabled", False),
        r.get("interval", 0),
        r.get("video_name", ""),
        r.get("last_updated", "")
    )

def update_random_config(enabled: bool, interval: int = 0, video_name: str = '', last_updated: str = ''):
    settings = load_settings()
    settings["random"] = {
        "enabled": enabled,
        "interval": interval,
        "video_name": video_name,
        "last_updated": last_updated
    }
    if not enabled:
        settings["random"]["interval"] = 0
        settings["random"]["video_name"] = ""
        settings["random"]["last_updated"] = ""
    save_settings(settings)

def read_pause_flag():
    return load_settings().get("pause_flag", False)

def write_pause_flag(is_paused):
    settings = load_settings()
    settings["pause_flag"] = is_paused
    save_settings(settings)

def random_video_updater():
    while not stop_random_thread.is_set():
        enabled, interval, _, last_updated = get_random_config()
        if not enabled or interval <= 0:
            time.sleep(5)
            continue

        videos = sorted([f.name for f in VIDEO_FOLDER.glob("*.mp4")])
        if not videos:
            time.sleep(10)
            continue

        settings = load_settings()
        current_video = settings.get("selected_video", "")
        new_video = current_video
        while new_video == current_video and len(videos) > 1:
            new_video = random.choice(videos)

        settings["selected_video"] = new_video
        save_settings(settings)

        now = datetime.now()
        last_updated_str = now.strftime("%Y-%m-%d %H:%M:%S")
        update_random_config(True, interval, video_name=new_video, last_updated=last_updated_str)
        print(f"[Random updater] New video: {new_video} at {last_updated_str}")

        # Calculate how much time to sleep based on last_updated
        try:
            last_dt = datetime.strptime(last_updated_str, "%Y-%m-%d %H:%M:%S")
            next_dt = last_dt + timedelta(minutes=interval)
            now = datetime.now()
            wait_seconds = (next_dt - now).total_seconds()
            if wait_seconds < 1:
                wait_seconds = 1  # avoid tight loop
        except Exception as e:
            print(f"Error parsing last_updated in thread: {e}")
            wait_seconds = interval * 60

        # Sleep in 1-second increments so stop_random_thread can interrupt
        for _ in range(int(wait_seconds)):
            if stop_random_thread.is_set():
                break
            time.sleep(1)

@app.route("/")
def index():
    videos = sorted([f.name for f in VIDEO_FOLDER.glob("*.mp4")])
    settings = load_settings()
    selected_video = settings.get("selected_video", "")

    random_mode, random_interval, current_random_video, last_updated = get_random_config()
    # If random mode is on, don't show selected video (since random video is playing)
    selected_video_display = selected_video if not random_mode else None

    logs = sorted([f.name for f in LOG_FOLDER.iterdir() if f.is_file()], reverse=True)

    # Calculate time remaining until next video switch if random mode is on
    time_remaining = None
    if random_mode and last_updated and random_interval > 0:
        try:
            last_updated_dt = datetime.strptime(last_updated, "%Y-%m-%d %H:%M:%S")
            next_switch = last_updated_dt + timedelta(minutes=random_interval)
            now = datetime.now()
            diff = (next_switch - now).total_seconds()
            time_remaining = max(1, int(diff))
        except Exception as e:
            print(f"Error parsing last_updated time: {e}")

    is_paused = read_pause_flag()

    return render_template(
        "index.html",
        videos=videos,
        selected=selected_video_display,
        random_mode=random_mode,
        random_interval=random_interval,
        logs=logs,
        current_random_video=current_random_video,
        last_updated=last_updated,
        time_remaining=time_remaining,
        pause=is_paused
    )

@app.route("/select", methods=["POST"])
def select():
    global random_thread, stop_random_thread

    random_mode = request.form.get("random_mode")
    if random_mode == "on":
        interval_str = request.form.get("interval")
        try:
            interval = int(interval_str)
            if interval <= 0:
                raise ValueError()
        except (ValueError, TypeError):
            flash("Invalid interval selected for random mode", "danger")
            return redirect(url_for("index"))

        videos = sorted([f.name for f in VIDEO_FOLDER.glob("*.mp4")])
        if not videos:
            flash("No videos available for random playback", "danger")
            return redirect(url_for("index"))

        if random_thread and random_thread.is_alive():
            stop_random_thread.set()
            random_thread.join()

        update_random_config(True, interval)

        stop_random_thread.clear()
        random_thread = threading.Thread(target=random_video_updater, daemon=True)
        random_thread.start()

        flash(f"Random mode enabled with interval {interval} minutes", "success")
        return redirect(url_for("index"))

    else:
        selected_video = request.form.get("video")
        if selected_video and (VIDEO_FOLDER / selected_video).exists():
            if random_thread and random_thread.is_alive():
                stop_random_thread.set()
                random_thread.join()

            update_random_config(False)

            settings = load_settings()
            settings["selected_video"] = selected_video
            save_settings(settings)

            flash(f"Selected video set to: {selected_video}", "success")
        else:
            flash("Invalid video selection", "danger")
        return redirect(url_for("index"))

@app.route('/pause_toggle', methods=['GET', 'POST'])
def pause_toggle():
    if request.method == 'POST':
        pause = request.form.get('pause')  # checkbox value if checked, else None
        is_paused = pause == 'on'
        write_pause_flag(is_paused)
        # After update, redirect to GET to avoid form resubmission on refresh
        return redirect(url_for('index'))

    # GET request
    is_paused = read_pause_flag()
    return render_template('index.html', pause=is_paused)



@app.route('/videos/<filename>')
def video_file(filename):
    full_path = VIDEO_FOLDER / filename
    print(f"Serving video file: {full_path}")
    if not full_path.exists():
        print("File does not exist!")
    return send_from_directory(VIDEO_FOLDER, filename)

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        flash('No file part', 'danger')
        return redirect(url_for('index'))
    file = request.files['file']
    if file.filename == '':
        flash('No selected file', 'danger')
        return redirect(url_for('index'))
    if file and file.filename.lower().endswith('.mp4'):
        save_path = VIDEO_FOLDER / file.filename
        file.save(save_path)
        flash(f'Uploaded: {file.filename}', 'success')
    else:
        flash('Only .mp4 files are allowed', 'danger')
    return redirect(url_for('index'))

@app.route('/delete/<filename>', methods=['POST'])
def delete(filename):
    filepath = VIDEO_FOLDER / filename
    if filepath.exists():
        filepath.unlink()
        flash(f'Deleted {filename}', 'success')
        if CONFIG_FILE.exists() and CONFIG_FILE.read_text().strip() == filename:
            CONFIG_FILE.unlink()
    else:
        flash('File not found', 'danger')
    return redirect(url_for('index'))

@app.route('/logs/view/<filename>')
def view_log(filename):
    safe_filename = os.path.basename(filename)
    filepath = LOG_FOLDER / safe_filename
    if not filepath.exists() or not filepath.is_file():
        flash("Log file not found", "danger")
        return redirect(url_for('index'))
    content = ""
    try:
        with open(filepath, 'r') as f:
            content = f.read(10000)
    except Exception as e:
        flash(f"Error reading file: {e}", "danger")
        return redirect(url_for('index'))
    return render_template("view_log.html", filename=safe_filename, content=content)

@app.route('/logs/delete/<filename>', methods=['POST'])
def delete_log(filename):
    safe_filename = os.path.basename(filename)
    filepath = LOG_FOLDER / safe_filename
    if filepath.exists():
        filepath.unlink()
        flash(f"Deleted log {safe_filename}", "success")
    else:
        flash("Log file not found", "danger")
    return redirect(url_for('index'))

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
