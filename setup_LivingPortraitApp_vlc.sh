#!/bin/bash
set -e

log_success() {
    echo -e "\e[32m✅ $1 completed successfully.\e[0m"
}

log_fail() {
    echo -e "\e[31m❌ $1 failed.\e[0m"
    exit 1
}

echo -e "\nUpdating system..."
if sudo apt update && sudo apt upgrade -y; then
    log_success "System update"
else
    log_fail "System update"
fi

echo -e "\nInstalling VLC and GPIO libraries..."
if sudo apt install -y vlc python3-gpiozero python3-vlc python3-venv; then
    log_success "VLC and GPIO installation"
else
    log_fail "VLC and GPIO installation"
fi

echo -e "\nSetting up Python virtual environment for Flask..."
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

echo -e "\nCreating Flask app directory and placeholder..."
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

echo -e "\nCreating systemd service for Flask UI..."
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

echo -e "\nEnabling Flask UI to run on boot..."
if sudo systemctl daemon-reexec && sudo systemctl enable flask_ui && sudo systemctl start flask_ui; then
    log_success "Flask service enabled and started"
else
    log_fail "Starting Flask service"
fi


echo -e "\nDownloading motion_vlc.py to /home/pi..."
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/motion_vlc.py" -o /home/pi/motion_vlc.py
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/settings.json" -o /home/pi/settings.json
chmod +x /home/pi/motion_vlc.py

echo "Creating /home/pi/PauseVideo directory..."
mkdir -p /home/pi/PauseVideo

echo "Downloading paused_rotated.mp4 to /home/pi/PauseVideo..."
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/PauseVideo/paused_rotated.mp4" -o /home/pi/PauseVideo/paused_rotated.mp4

echo -e "\nCreating logs folder..."
mkdir -p /home/pi/logs

echo -e "\nCreating Flask app directory and structure..."
mkdir -p /home/pi/flask_ui/templates

echo -e "\nDownloading Flask app files..."
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/flask_ui/app.py" -o /home/pi/flask_ui/app.py
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/flask_ui/templates/index.html" -o /home/pi/flask_ui/templates/index.html
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/flask_ui/templates/view_log.html" -o /home/pi/flask_ui/templates/view_log.html

echo -e "\nCreating motion_vlc.service systemd file..."
sudo tee /etc/systemd/system/motion_vlc.service > /dev/null << EOF
[Unit]
Description=Run motion_vlc.py at boot
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/pi/motion_vlc.py
WorkingDirectory=/home/pi
StandardOutput=inherit
StandardError=inherit
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable motion_vlc.service
sudo systemctl restart motion_vlc.service

echo -e "\nAll setup steps completed. Please reboot to apply all changes."