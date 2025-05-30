#!/bin/bash
set -e

log_success() {
    echo -e "\e[32m✅ $1 completed successfully.\e[0m"
}

log_fail() {
    echo -e "\e[31m❌ $1 failed.\e[0m"
    exit 1
}

echo "Updating system..."
if sudo apt update && sudo apt upgrade -y; then
    log_success "System update"
else
    log_fail "System update"
fi

echo "Installing VLC and GPIO libraries..."
if sudo apt install -y vlc python3-gpiozero python3-vlc python3-venv; then
    log_success "VLC and GPIO installation"
else
    log_fail "VLC and GPIO installation"
fi

echo "Setting up Python virtual environment for Flask..."
if python3 -m venv ~/flask_venv; then
    source ~/flask_venv/bin/activate
    if pip install flask; then
        deactivate
        log_success "Flask virtual environment setup"
    else
        log_fail "Flask pip install"
    fi
else
    log_fail "Virtual environment creation"
fi

echo "Creating Flask app directory and placeholder..."
mkdir -p ~/flask_ui
if cat << 'EOF' > ~/flask_ui/app.py
from flask import Flask
app = Flask(__name__)

@app.route("/")
def home():
    return "Flask UI is running!"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF
then
    log_success "Flask app.py created"
else
    log_fail "Creating app.py"
fi

echo "Creating systemd service for Flask UI..."
if sudo tee /etc/systemd/system/flask_ui.service > /dev/null << EOF
[Unit]
Description=Flask Web UI for Video Selector
After=network.target

[Service]
WorkingDirectory=/home/pi/flask_ui
ExecStart=/home/pi/flask_venv/bin/python /home/pi/flask_ui/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF
then
    log_success "Systemd service file created"
else
    log_fail "Creating systemd service"
fi

echo "Enabling Flask UI to run on boot..."
if sudo systemctl daemon-reexec && sudo systemctl enable flask_ui && sudo systemctl start flask_ui; then
    log_success "Flask service enabled and started"
else
    log_fail "Starting Flask service"
fi

echo "Adding motion_vlc.py to auto-run on console login..."
if grep -qxF 'if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then' ~/.bashrc; then
    echo ".bashrc already contains autorun code."
else
    if cat << 'EOF' >> ~/.bashrc

# Auto-run motion_vlc.py on console login
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    /usr/bin/python3 /home/pi/motion_vlc.py
fi
EOF
    then
        log_success "Autorun added to .bashrc"
    else
        log_fail "Modifying .bashrc"
    fi
fi


echo "📝 Creating motion_vlc.py script in /home/pi..."
cat <<'EOF' > /home/pi/motion_vlc.py
#!/usr/bin/env python3

import vlc
from gpiozero import MotionSensor
from pathlib import Path
from time import sleep, time
from datetime import datetime, timedelta
import sys

VIDEO_FOLDER = Path('/home/pi/Videos')
LOG_FOLDER = Path('/home/pi/logs')
CONFIG_FILE = Path('/home/pi/config.txt')
RANDOM_CONFIG_FILE = Path('/home/pi/random_config.txt')

LOG_FOLDER.mkdir(exist_ok=True)

def log(msg):
    timestamp = f"[{time():.1f}]"
    log_line = f"{timestamp} {msg}"
    print(log_line)

    date_str = datetime.now().strftime("%Y-%m-%d")
    log_file = LOG_FOLDER / f"motion_log_{date_str}.txt"
    with log_file.open("a") as f:
        f.write(f"{datetime.now().isoformat()} {msg}\n")

def read_random_config():
    if not RANDOM_CONFIG_FILE.exists():
        return False, 0, '', ''
    lines = RANDOM_CONFIG_FILE.read_text().splitlines()
    enabled = lines[0].strip().upper() == "ON"
    interval = 0
    video_name = ''
    last_updated = ''
    for line in lines[1:]:
        if line.startswith("INTERVAL="):
            try:
                interval = int(line.split("=", 1)[1])
            except ValueError:
                interval = 0
        elif line.startswith("video_name="):
            video_name = line.split("=", 1)[1].strip()
        elif line.startswith("last_updated="):
            last_updated = line.split("=", 1)[1].strip()
    return enabled, interval, video_name, last_updated

def get_current_video():
    if not CONFIG_FILE.exists():
        log("config.txt missing - no video selected")
        return None
    name = CONFIG_FILE.read_text().strip()
    path = VIDEO_FOLDER / name
    if path.exists():
        return str(path)
    else:
        log(f"Video '{name}' from config.txt not found in {VIDEO_FOLDER}")
        return None

def main():
    if not VIDEO_FOLDER.exists():
        print(f"Video folder {VIDEO_FOLDER} does not exist!")
        sys.exit(1)

    videos = list(VIDEO_FOLDER.glob("*.mp4"))
    if not videos:
        print(f"No mp4 videos found in {VIDEO_FOLDER}!")
        sys.exit(1)

    log(f"Found {len(videos)} video(s). Starting...")

    pir = MotionSensor(4)  # Change GPIO pin if needed

    # === PLACE THE LAST_UPDATED UPDATE HERE ===
    enabled, interval, video_name, _ = read_random_config()
    if enabled and interval > 0:
        last_updated_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        RANDOM_CONFIG_FILE.write_text(
            f"ON\nINTERVAL={interval}\nvideo_name={video_name}\nlast_updated={last_updated_str}\n"
        )
        log(f"[Startup] Updated last_updated to: {last_updated_str}")
    # =========================================

    current_video_path = get_current_video()
    if not current_video_path:
        current_video_path = str(videos[0])
        log(f"Defaulting to first video: {Path(current_video_path).name}")

    player = vlc.MediaPlayer()
    media = vlc.Media(current_video_path)
    player.set_media(media)
    player.play()
    sleep(0.5)
    player.set_pause(1)  # Start paused
    player.set_time(0)
    log(f"Loaded video {Path(current_video_path).name} paused")

    while True:
        enabled, interval, _, last_updated_str = read_random_config()

        timer_expired = False
        if enabled and interval > 0 and last_updated_str:
            try:
                last_updated = datetime.strptime(last_updated_str, "%Y-%m-%d %H:%M:%S")
                if datetime.now() >= last_updated + timedelta(minutes=interval):
                    timer_expired = True
            except Exception as e:
                log(f"Error parsing last_updated: {e}")

        motion = pir.wait_for_motion(timeout=1)

        if motion or timer_expired:
            trigger = "Motion detected" if motion else "Timer expired"
            log(f"{trigger} triggered video playback")

            if timer_expired:
                # On timer expired, re-read config.txt for new video path
                new_video_path = get_current_video()
                if new_video_path:
                    current_video_path = new_video_path
                    log(f"Timer expired - reloaded video from config.txt: {Path(current_video_path).name}")
                else:
                    log("Timer expired - no valid video found in config.txt, keeping current video")

            media = vlc.Media(current_video_path)
            player.set_media(media)
            player.play()
            sleep(0.5)

            while player.get_state() not in (vlc.State.Ended, vlc.State.Stopped):
                sleep(0.1)

            log(f"Video {Path(current_video_path).name} finished, pausing")
            player.pause()
            player.set_time(0)

        else:
            sleep(0.1)

if __name__ == "__main__":
    main()
EOF

chmod +x /home/pi/motion_vlc.py

echo "Creating default random_config.txt..."
cat <<EOF > /home/pi/random_config.txt
OFF
EOF

echo "Creating default config.txt..."
cat <<EOF > /home/pi/config.txt
default_video.mp4
EOF

echo "Creating logs folder..."
mkdir -p /home/pi/logs

set -e

APP_DIR=~/flask_ui
TEMPLATES_DIR=$APP_DIR/templates
LOGS_DIR=$APP_DIR/logs

echo "📁 Creating Flask app directory and structure..."
mkdir -p "$APP_DIR"
mkdir -p "$TEMPLATES_DIR"
mkdir -p "$LOGS_DIR"

echo "📝 Writing Flask app file (app.py)..."
cat > "$APP_DIR/app.py" << 'EOF'
from flask import Flask, render_template, request, redirect, url_for, flash, send_from_directory
from pathlib import Path
import os
import threading
import time
import random
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = 'replace-this-with-a-secure-random-key'

VIDEO_FOLDER = Path("/home/pi/Videos")
LOG_FOLDER = Path("/home/pi/logs")
CONFIG_FILE = Path("/home/pi/config.txt")
RANDOM_CONFIG_FILE = Path("/home/pi/random_config.txt")

VIDEO_FOLDER.mkdir(parents=True, exist_ok=True)
LOG_FOLDER.mkdir(parents=True, exist_ok=True)

# Thread control
random_thread = None
stop_random_thread = threading.Event()

def write_random_config(enabled: bool, interval: int = 0, video_name: str = '', last_updated: str = ''):
    if enabled:
        text = f"ON\nINTERVAL={interval}"
        if video_name and last_updated:
            text += f"\nvideo_name={video_name}\nlast_updated={last_updated}"
    else:
        text = "OFF"
    RANDOM_CONFIG_FILE.write_text(text)

def read_random_config():
    if not RANDOM_CONFIG_FILE.exists():
        return False, 0, '', ''
    lines = RANDOM_CONFIG_FILE.read_text().splitlines()
    enabled = lines[0].strip() == "ON"
    interval = 0
    video_name = ''
    last_updated = ''
    for line in lines[1:]:
        if line.startswith("INTERVAL="):
            try:
                interval = int(line.split("=", 1)[1])
            except:
                interval = 0
        elif line.startswith("video_name="):
            video_name = line.split("=", 1)[1]
        elif line.startswith("last_updated="):
            last_updated = line.split("=", 1)[1]
    return enabled, interval, video_name, last_updated

def random_video_updater():
    while not stop_random_thread.is_set():
        enabled, interval, _, last_updated = read_random_config()
        if not enabled or interval <= 0:
            time.sleep(5)
            continue

        videos = sorted([f.name for f in VIDEO_FOLDER.glob("*.mp4")])
        if not videos:
            time.sleep(10)
            continue

        current_video = CONFIG_FILE.read_text().strip() if CONFIG_FILE.exists() else None
        new_video = current_video
        while new_video == current_video and len(videos) > 1:
            new_video = random.choice(videos)

        CONFIG_FILE.write_text(new_video)
        now = datetime.now()
        last_updated_str = now.strftime("%Y-%m-%d %H:%M:%S")
        write_random_config(True, interval, video_name=new_video, last_updated=last_updated_str)
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
    selected = CONFIG_FILE.read_text().strip() if CONFIG_FILE.exists() else None

    random_mode, random_interval, current_random_video, last_updated = read_random_config()
    selected_video = selected if not random_mode else None

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

    return render_template(
        "index.html",
        videos=videos,
        selected=selected_video,
        random_mode=random_mode,
        random_interval=random_interval,
        logs=logs,
        current_random_video=current_random_video,
        last_updated=last_updated,
        time_remaining=time_remaining
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

        write_random_config(True, interval)

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

            write_random_config(False)

            CONFIG_FILE.write_text(selected_video)
            flash(f"Selected video set to: {selected_video}", "success")
        else:
            flash("Invalid video selection", "danger")
        return redirect(url_for("index"))

    

@app.route('/videos/<filename>')
def video_file(filename):
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
    app.run(host="0.0.0.0", port=5000)

EOF


chmod +x /home/pi/flask_ui/app.py

echo "Writing template: index.html..."
cat > "$TEMPLATES_DIR/index.html" << 'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Video Selector</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet" />
  <style>
    .video-wrapper {
      width: 100%;
      max-width: 360px;
      height: 640px;
      overflow: hidden;
      margin-top: 1rem;
    }

    #videoPreview {
      width: 640px;
      height: 360px;
      transform: rotate(90deg) translate(0, -100%);
      transform-origin: top left;
      display: block;
      max-width: none;
    }

#dropArea {
  cursor: pointer;
  transition: background-color 0.3s, border-color 0.3s;
}


    @media (max-width: 400px) {
      .video-wrapper {
        overflow-x: auto;
      }
    }
  </style>
</head>
<body class="bg-light py-4">
  <div class="container">
    <h1 class="mb-4">Video Selector</h1>

    {% with messages = get_flashed_messages(with_categories=true) %}
      {% if messages %}
        {% for category, message in messages %}
          <div class="alert alert-{{ category }} alert-dismissible fade show" role="alert">
            {{ message }}
            <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
          </div>
        {% endfor %}
      {% endif %}
    {% endwith %}

    <!-- Tab Navigation -->
    <ul class="nav nav-tabs mb-3" id="videoTabs" role="tablist">
      <li class="nav-item" role="presentation">
        <button class="nav-link active" id="select-tab" data-bs-toggle="tab" data-bs-target="#select" type="button" role="tab">Select</button>
      </li>
      <li class="nav-item" role="presentation">
        <button class="nav-link" id="upload-tab" data-bs-toggle="tab" data-bs-target="#upload" type="button" role="tab">Upload</button>
      </li>
      <li class="nav-item" role="presentation">
        <button class="nav-link" id="manage-tab" data-bs-toggle="tab" data-bs-target="#manage" type="button" role="tab">Manage</button>
      </li>
      <li class="nav-item" role="presentation">
        <button class="nav-link" id="logs-tab" data-bs-toggle="tab" data-bs-target="#logs" type="button" role="tab">Logs</button>
      </li>
    </ul>

    <div class="tab-content" id="videoTabsContent">
      <!-- Select Tab -->
      <div class="tab-pane fade show active" id="select" role="tabpanel" aria-labelledby="select-tab">
        <form method="POST" action="{{ url_for('select') }}">
         {% if videos|length > 1 %}
          <div class="mb-3 form-check">
            <input class="form-check-input" type="checkbox" id="randomMode" name="random_mode" value="on" {% if random_mode %}checked{% endif %} onchange="toggleRandomMode()" />
            <label class="form-check-label" for="randomMode">Enable Random Mode</label>
          </div>
          {% endif %}

          <div class="mb-3" id="intervalGroup" style="display: {{ 'block' if random_mode else 'none' }}">
            <label for="interval" class="form-label">Interval (minutes):</label>
            <select class="form-select" id="interval" name="interval" {% if not random_mode %}disabled{% endif %}>
              {% for i in range(1, 61) %}
                <option value="{{ i }}" {% if i == random_interval %}selected{% endif %}>{{ i }}</option>
              {% endfor %}
            </select>
          </div>

          <div id="videoSelectGroup" style="display: {{ 'none' if random_mode else 'block' }}">
            <label for="video" class="form-label">Select Video:</label>
            <select class="form-select" id="video" name="video" onchange="updateVideoPreview()">
              <option value="">-- Select a video --</option>
              {% for video in videos %}
                <option value="{{ video }}" {% if video == selected %}selected{% endif %}>{{ video }}</option>
              {% endfor %}
            </select>
          </div>

          <button type="submit" class="btn btn-primary mt-3">Save</button>
        </form>

        <div class="video-wrapper">
        {% if random_mode and time_remaining is not none %}
          <div class="mt-3">
            <h5>Random mode active</h5>
            <p>Current Video: <strong>{{ current_random_video }}</strong></p>
            <p>Next switch in: <span id="countdown">{{ time_remaining }}</span> seconds</p>
          </div>
	{% else %}
		<h5>Selected Video</h5>
		<p>Current Video: <strong>{{ selected }}</strong></p>
        {% endif %}


          <video id="videoPreview" controls autoplay muted>
            {% if not random_mode and selected %}
              <source src="{{ url_for('video_file', filename=selected) }}" type="video/mp4" />
            {% elif random_mode and current_random_video %}
              <source src="{{ url_for('video_file', filename=current_random_video) }}" type="video/mp4" />
            {% endif %}
            Your browser does not support the video tag.
          </video>
        </div>
      </div>

      <!-- Upload Tab -->
      <div class="tab-pane fade" id="upload" role="tabpanel" aria-labelledby="upload-tab">
<form id="uploadForm" method="POST" action="{{ url_for('upload') }}" enctype="multipart/form-data">
  <div id="dropArea" class="border border-3 border-secondary rounded p-5 text-center bg-white">
    <p class="mb-2">Drag & drop an MP4 file here</p>
    <p class="small text-muted">or click to select</p>
    <input type="file" id="fileInput" name="file" accept=".mp4" hidden />
    <button type="button" class="btn btn-outline-secondary btn-sm" onclick="document.getElementById('fileInput').click()">Choose File</button>
    <p id="fileName" class="mt-3 fw-bold text-success"></p>
  </div>
  <div class="text-center mt-3">
    <button type="submit" class="btn btn-success" id="uploadBtn" disabled>Upload</button>
  </div>
</form>      </div>

      <!-- Manage Tab -->
      <div class="tab-pane fade" id="manage" role="tabpanel" aria-labelledby="manage-tab">
        <h5>Manage Videos</h5>
        <ul class="list-group">
          {% for video in videos %}
            <li class="list-group-item d-flex justify-content-between align-items-center">
              {{ video }}
              <form method="POST" action="{{ url_for('delete', filename=video) }}" onsubmit="return confirm('Delete {{ video }}?');">
                <button type="submit" class="btn btn-danger btn-sm">Delete</button>
              </form>
            </li>
          {% else %}
            <li class="list-group-item">No videos found.</li>
          {% endfor %}
        </ul>
      </div>

      <!-- Logs Tab -->
      <div class="tab-pane fade" id="logs" role="tabpanel" aria-labelledby="logs-tab">
        <h5>Logs</h5>
        <ul class="list-group mb-3">
          {% for log in logs %}
            <li class="list-group-item d-flex justify-content-between align-items-center">
              <a href="{{ url_for('view_log', filename=log) }}">{{ log }}</a>
              <form method="POST" action="{{ url_for('delete_log', filename=log) }}" onsubmit="return confirm('Delete log {{ log }}?');">
                <button type="submit" class="btn btn-danger btn-sm">Delete</button>
              </form>
            </li>
          {% else %}
            <li class="list-group-item">No logs found.</li>
          {% endfor %}
        </ul>
      </div>
    </div>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>

  <script>
const dropArea = document.getElementById('dropArea');
const fileInput = document.getElementById('fileInput');
const fileName = document.getElementById('fileName');
const uploadBtn = document.getElementById('uploadBtn');

// Highlight on drag
['dragenter', 'dragover'].forEach(eventName => {
  dropArea.addEventListener(eventName, e => {
    e.preventDefault();
    e.stopPropagation();
    dropArea.classList.add('border-success', 'bg-light');
  });
});

['dragleave', 'drop'].forEach(eventName => {
  dropArea.addEventListener(eventName, e => {
    e.preventDefault();
    e.stopPropagation();
    dropArea.classList.remove('border-success', 'bg-light');
  });
});

// Handle drop
dropArea.addEventListener('drop', e => {
  const dt = e.dataTransfer;
  const files = dt.files;
  handleFile(files[0]);
});

// Handle file chosen by click
fileInput.addEventListener('change', e => {
  if (e.target.files.length > 0) {
    handleFile(e.target.files[0]);
  }
});

function handleFile(file) {
  if (file.type === "video/mp4") {
    fileInput.files = new DataTransfer().files;
    const dataTransfer = new DataTransfer();
    dataTransfer.items.add(file);
    fileInput.files = dataTransfer.files;

    fileName.textContent = `Selected: ${file.name}`;
    uploadBtn.disabled = false;
  } else {
    fileName.textContent = "Please upload a valid MP4 file.";
    uploadBtn.disabled = true;
  }
}


    function toggleRandomMode() {
      const randomModeCheckbox = document.getElementById('randomMode');
      const intervalGroup = document.getElementById('intervalGroup');
      const intervalSelect = document.getElementById('interval');
      const videoSelectGroup = document.getElementById('videoSelectGroup');

      if (randomModeCheckbox.checked) {
        intervalGroup.style.display = 'block';
        intervalSelect.disabled = false;
        videoSelectGroup.style.display = 'none';
      } else {
        intervalGroup.style.display = 'none';
        intervalSelect.disabled = true;
        videoSelectGroup.style.display = 'block';
      }
    }

    function updateVideoPreview() {
      const videoSelect = document.getElementById('video');
      const videoPreview = document.getElementById('videoPreview');
      const selectedVideo = videoSelect.value;

      if (selectedVideo) {
        const url = `/videos/${encodeURIComponent(selectedVideo)}`;
        videoPreview.src = url;
        videoPreview.load();
        videoPreview.play();
      } else {
        videoPreview.pause();
        videoPreview.src = "";
      }
    }

    // Countdown timer for random mode
    {% if random_mode and time_remaining is not none and time_remaining > 0 %}
  let countdown = {{ time_remaining }};
  const countdownElement = document.getElementById('countdown');

  const interval = setInterval(() => {
    if (countdown > 0) {
      countdown--;
      countdownElement.textContent = countdown;
    } else {
      clearInterval(interval);
      location.reload(); // Refresh page only when countdown ends
    }
  }, 1000);   
{% endif %}


  </script>
</body>
</html>

EOF

echo "Writing template: view_log.html..."
cat > "$TEMPLATES_DIR/view_log.html" << 'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>View Log - {{ log_name }}</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet" />
  <style>
    pre {
      white-space: pre-wrap;
      word-wrap: break-word;
      background-color: #f8f9fa;
      padding: 1rem;
      border-radius: 5px;
      max-height: 600px;
      overflow-y: auto;
      font-family: monospace;
    }
  </style>
</head>
<body class="bg-light py-4">
  <div class="container">
    <h1>Log File: {{ log_name }}</h1>
    <a href="{{ url_for('index') }}" class="btn btn-secondary mb-3">Back</a>
    <pre>{{ content }}</pre>
  </div>
</body>
</html>
EOF

echo -e "\nAll setup steps completed. Please reboot to apply all changes."
