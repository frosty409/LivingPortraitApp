from flask import Flask, render_template, request, redirect, url_for, flash, send_from_directory
from pathlib import Path
import os
from datetime import datetime, timedelta
import random
from flask import jsonify

import sys
sys.path.append('/home/pi/')
from shared.vlc_helper import (
    log,
    load_settings,
    save_settings,
    get_playlist_settings,
    update_playlist_settings,
    read_pause_flag,
    write_pause_flag,
    get_days_schedule,
    update_days_schedule,
    is_schedule_enabled_now,
    get_next_start_time
)

app = Flask(__name__)
app.secret_key = 'replace-this-with-a-secure-random-key'  # Change to a secure key in production

VIDEO_FOLDER = Path("/home/pi/videos")
IMAGES_FOLDER = Path("/home/pi/images")
LOG_FOLDER = Path("/home/pi/logs")
SETTINGS_FILE = Path("/home/pi/settings.json")

VIDEO_FOLDER.mkdir(parents=True, exist_ok=True)
LOG_FOLDER.mkdir(parents=True, exist_ok=True)

def format_ampm(time_str):
    return datetime.strptime(time_str, "%H:%M").strftime("%I:%M %p")

@app.route("/")
def index():
    current_time = datetime.now().strftime("%A %I:%M:%S %p") 
    theme = request.cookies.get("themeMode", "light")
    videos = sorted([f.name for f in VIDEO_FOLDER.glob("*.mp4")])
    settings = load_settings()
    selected_video = settings.get("selected_video", "")
    pause_flag = settings.get("pause_flag", False)

    mode, interval, last_updated, order, triggered_flag, delay = get_playlist_settings()

    # Get days schedule
    days_schedule = settings.get("days", {})

    # Format times
    for day, sched in days_schedule.items():
        sched["start_ampm"] = format_ampm(sched["start"])
        sched["end_ampm"] = format_ampm(sched["end"])
    
    # Get today's name, e.g., "Friday"
    today = datetime.now().strftime("%A")
    today_schedule = days_schedule.get(today, {})

    # Check if schedule is enabled right now
    schedule_enabled = is_schedule_enabled_now()

    next_start_time = get_next_start_time(settings)

    fixed_order = [
         entry for entry in order
         if isinstance(entry, dict) and entry.get("filename") in videos and entry.get("active")
    ]

    manage_videos = [
        entry for entry in order
        if isinstance(entry, dict) and entry.get("filename") in videos
    ]

    # Calculate time remaining until next video switch
    time_remaining = None
    if mode in ["random", "fixed"] and last_updated and interval > 0:
        try:
            last_dt = datetime.strptime(last_updated, "%Y-%m-%d %H:%M:%S")
            next_dt = last_dt + timedelta(seconds=interval * 60)
            now = datetime.now()
            diff = (next_dt - now).total_seconds()
            time_remaining = max(0, int(diff))
        except Exception as e:
            log(f"Error calculating time remaining: {e}")

    logs = []
    if LOG_FOLDER.exists():
        for f in LOG_FOLDER.glob("*.txt"):
            logs.append({
                "name": f.name,
                "mtime": datetime.fromtimestamp(f.stat().st_mtime).strftime('%Y-%m-%d %I:%M %p'),
                "size": f.stat().st_size
            })
        logs.sort(key=lambda x: x["mtime"], reverse=True)

    return render_template(
        "index.html",
        logs=logs,
        videos=fixed_order,
        selected=selected_video,
        playlist_mode=mode,
        interval=interval,
        last_updated=last_updated,
        fixed_order=fixed_order,
        manage_videos=manage_videos, 
        time_remaining=time_remaining,
        pause=pause_flag,
        video_count=len(fixed_order),
        theme=theme,
        days=days_schedule,
        today_schedule=today_schedule,
        today=today,
        current_time=current_time,
        is_schedule_enabled_now=schedule_enabled,
        next_start_time=next_start_time,
        triggered_flag=triggered_flag,
        delay=delay
    )

@app.route("/select", methods=["POST"])
def select():
    action = request.form.get("action", "")
        # Normal save logic below
    playlist_mode = request.form.get("mode", "")
    interval_str = request.form.get("interval", "0")
    triggered_flag = request.form.get("triggered_flag") == "on"
    delay = int(request.form.get("delay", 0))

    try:
        interval = int(interval_str)
        if interval < 0:
            raise ValueError()
    except (ValueError, TypeError):
        flash("Invalid interval value", "danger")
        return redirect(url_for("index"))    
    
    if action == "shuffle":
        settings = load_settings()
        order = settings.get("playlist", {}).get("order", [])
        
        # Separate active and inactive videos
        active_videos = [v for v in order if v.get("active", True)]
        inactive_videos = [v for v in order if not v.get("active", True)]
        
        random.shuffle(active_videos)
        
        # Combine shuffled active with inactive
        new_order = active_videos + inactive_videos

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        update_playlist_settings(mode="fixed",interval=interval,last_updated=timestamp,order=new_order,triggered_flag=triggered_flag,delay=delay)

        # Now load settings again to update selected_video
        settings = load_settings()
        if new_order:
            settings["selected_video"] = new_order[0]["filename"]
            save_settings(settings)
        
        flash("Playlist order shuffled!", "success")
        return redirect(url_for("index"))
    


    videos = sorted([f.name for f in VIDEO_FOLDER.glob("*.mp4")])
    if not videos:
        flash("No videos found in the Videos folder", "danger")
        return redirect(url_for("index"))

    if playlist_mode == "random":
        if interval == 0:
            flash("Interval must be greater than zero for random mode", "danger")
            return redirect(url_for("index"))

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        update_playlist_settings(mode="random",interval=interval,last_updated=timestamp,triggered_flag=triggered_flag,delay=delay)

        settings = load_settings()
        current_video = settings.get("selected_video", "")
        order = settings.get("playlist", {}).get("order", [])
        active_files = [item["filename"] for item in order if item.get("active", True)]

        if not active_files:
            flash("No active videos available for random playback", "danger")
            return redirect(url_for("index"))

        other_choices = [f for f in active_files if f != current_video]
        new_video = random.choice(other_choices) if other_choices else current_video

        settings["selected_video"] = new_video
        save_settings(settings)

        flash(f"Random mode enabled with interval {interval} seconds", "success")

    elif playlist_mode == "fixed":
        if interval == 0:
            flash("Interval must be greater than zero for fixed mode", "danger")
            return redirect(url_for("index"))

        order_str = request.form.get("fixed_order", "")
        filenames = [v.strip() for v in order_str.split(",") if v.strip() in videos]

        if not filenames:
            flash("Please provide a valid fixed order with existing videos", "danger")
            return redirect(url_for("index"))

        existing_order = load_settings().get("playlist", {}).get("order", [])
        existing_dict = {entry['filename']: entry for entry in existing_order if 'filename' in entry}

        new_order = []
        for fn in filenames:
            new_order.append({"filename": fn, "active": True})

        for fn, entry in existing_dict.items():
            if fn not in filenames:
                new_order.append({"filename": fn, "active": False})

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        update_playlist_settings(mode="fixed", interval=interval, last_updated=timestamp, order=new_order,triggered_flag=triggered_flag,delay=delay)

        # Now load settings again to update selected_video
        settings = load_settings()
        if new_order:
            settings["selected_video"] = new_order[0]["filename"]
            save_settings(settings)

        flash(f"Fixed playlist mode enabled with interval {interval} seconds", "success")

    else:
        selected_video = request.form.get("video")
        if selected_video and (VIDEO_FOLDER / selected_video).exists():
            update_playlist_settings(mode="single", interval=0, last_updated="",triggered_flag=triggered_flag,delay=delay)
            settings = load_settings()
            settings["selected_video"] = selected_video
            save_settings(settings)
            flash(f"Selected single video: {selected_video}", "success")
        else:
            flash("Invalid video selection", "danger")

    return redirect(url_for("index"))

@app.route('/pause_toggle', methods=['POST'])
def pause_toggle():
    pause = request.form.get('pause')  # 'on' if checked, else None
    is_paused = pause == 'on'
    write_pause_flag(is_paused)
    return redirect(url_for('index'))

@app.route('/videos/<filename>')
def video_file(filename):
    full_path = VIDEO_FOLDER / filename
    log(f"Serving video file: {full_path}")
    if not full_path.exists():
        log("File does not exist!")
        return "File not found", 404
    return send_from_directory(VIDEO_FOLDER, filename)


@app.route('/images/<filename>')
def image_file(filename):
    full_path = IMAGES_FOLDER / filename
    log(f"Serving video file: {full_path}")
    if not full_path.exists():
        log("File does not exist!")
        return "File not found", 404
    return send_from_directory(IMAGES_FOLDER, filename)


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

        # Update playlist order by appending new video with active = True
        settings = load_settings()
        order = settings.get("playlist", {}).get("order", [])

        # Check if filename already present
        if not any(item["filename"] == file.filename for item in order):
            order.append({"filename": file.filename, "active": True})
            settings["playlist"]["order"] = order
            save_settings(settings)

        flash(f'Uploaded: {file.filename}', 'success')
    else:
        flash('Only .mp4 files are allowed', 'danger')
    return redirect(url_for('index'))



@app.route('/save_schedule', methods=['POST'])
def save_schedule():
    settings = load_settings()
    current_days = settings.get("days", {})
    days = {}

    for day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']:
        key = day.lower()
        enabled = request.form.get(f"{key}Enabled") == 'on'

        # Only get values from form if field is enabled
        if enabled:
            start_time = request.form.get(f"{key}Start") or "00:00"
            end_time = request.form.get(f"{key}End") or "23:59"
        else:
            # Fall back to existing values in JSON if present
            start_time = current_days.get(day, {}).get("start", "00:00")
            end_time = current_days.get(day, {}).get("end", "23:59")

        days[day] = {
            "enabled": enabled,
            "start": start_time,
            "end": end_time
        }

    settings["days"] = days
    save_settings(settings)
    flash("Schedule saved successfully!", "success")
    return redirect(url_for('index'))




@app.route('/update_status', methods=['POST'])
def update_status():
    filename = request.form.get('filename')
    active = request.form.get('active') == 'true'

    settings = load_settings()
    order = settings.get('playlist', {}).get('order', [])

    # Count active videos before updating
    active_count = sum(1 for v in order if v.get('active', True))

    # Find target video
    target_video = next((v for v in order if v['filename'] == filename), None)

    # If trying to deactivate and it's the only active video
    if target_video and not active and active_count <= 1:
        flash("At least one video must remain active.", "danger")
        return redirect(url_for('index'))

    # If not found, optionally add it
    if not target_video:
        order.append({'filename': filename, 'active': active})
    else:
        target_video['active'] = active

    settings['playlist']['order'] = order
    save_settings(settings)

    # After updating, check how many are now active
    updated_active = [v for v in order if v.get('active', True)]

    if len(updated_active) == 1:
        only_video = updated_active[0]['filename']
        update_playlist_settings(mode="single", interval=0, last_updated="")
        settings = load_settings()
        settings["selected_video"] = only_video
        save_settings(settings)
        flash(f"Only one active video remains. Switched to single mode with video: {only_video}", "info")
    else:
        flash(f"Updated status for {filename}: {'Active' if active else 'Inactive'}", "success")

    return redirect(url_for('index'))


@app.route('/delete/<filename>', methods=['POST'])
def delete(filename):
    filepath = VIDEO_FOLDER / filename
    if filepath.exists():
        filepath.unlink()

        # Remove from playlist order
        settings = load_settings()
        order = settings.get("playlist", {}).get("order", [])
        order = [item for item in order if item["filename"] != filename]
        settings["playlist"]["order"] = order
        save_settings(settings)

        flash(f'Deleted {filename}', 'success')
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
    try:
        with open(filepath, 'r') as f:
            content = f.read(10000)
    except Exception as e:
        flash(f"Error reading file: {e}", "danger")
        return redirect(url_for('index'))
    return render_template("view_log.html", filename=safe_filename, content=content)

@app.route('/logs/raw/<filename>')
def get_log_content(filename):
    safe_filename = os.path.basename(filename)
    filepath = LOG_FOLDER / safe_filename
    if not filepath.exists() or not filepath.is_file():
        return "File not found", 404

    try:
        with open(filepath, 'r') as f:
            content = f.read(10000)
        return content, 200, {'Content-Type': 'text/plain'}
    except Exception as e:
        return f"Error reading file: {e}", 500




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
    app.run(host="0.0.0.0", port=5000)
