#!/bin/bash
set -e

# ============================================================
# Raspberry Pi 5 setup for LivingPortraitApp
# ============================================================

# --- Environment setup ---
USERNAME=$(whoami)
USER_HOME="$HOME"
VENV_PATH="$USER_HOME/flask_venv"

log_success() {
    echo -e "\e[32m✅ $1 completed successfully.\e[0m"
}

log_fail() {
    echo -e "\e[31m❌ $1 failed.\e[0m"
    exit 1
}

echo -e "\nUpdating package list..."
sudo apt update -y || log_fail "apt update failed"

echo -e "\nUpgrading packages (this may take several minutes)..."
sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || log_fail "apt upgrade failed"

log_success "System update completed"

# --- Required packages ---
echo -e "\nChecking required packages..."
REQUIRED_PKGS=(vlc python3-gpiozero python3-vlc python3-venv libvlc-dev libpulse-dev)
MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
    dpkg -s "$pkg" &>/dev/null || MISSING_PKGS+=("$pkg")
done

if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
    log_success "All required packages already installed"
else
    echo "Installing missing packages: ${MISSING_PKGS[*]}"
    sudo apt install -y "${MISSING_PKGS[@]}" && log_success "Package installation" || log_fail "Package installation"
fi

# --- Virtual environment ---
echo -e "\nSetting up Python virtual environment..."
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH" || log_fail "Virtual environment creation"
    "$VENV_PATH/bin/pip" install --upgrade pip
    "$VENV_PATH/bin/pip" install flask || log_fail "Flask pip install"
    log_success "Flask virtual environment setup"
else
    log_success "Virtual environment already exists"
fi

# --- Directories ---
echo -e "\nCreating directories..."
mkdir -p "$USER_HOME/videos" \
         "$USER_HOME/pause_video" \
         "$USER_HOME/images" \
         "$USER_HOME/logs" \
         "$USER_HOME/shared" \
         "$USER_HOME/flask_ui/templates"

# --- Download app files ---
echo -e "\nDownloading app files..."
curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/motion_vlc.py" -o "$USER_HOME/motion_vlc.py"
curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/settings.json" -o "$USER_HOME/settings.json"
chmod +x "$USER_HOME/motion_vlc.py"

curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/images/logo.png" -o "$USER_HOME/images/logo.png"
curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/pause_video/paused_rotated.mp4" -o "$USER_HOME/pause_video/paused_rotated.mp4"
curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/flask_ui/app.py" -o "$USER_HOME/flask_ui/app.py"
curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/flask_ui/templates/index.html" -o "$USER_HOME/flask_ui/templates/index.html"
curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/shared/vlc_helper.py" -o "$USER_HOME/shared/vlc_helper.py"

VERSION=$(curl -fsSL https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/version.txt)
echo -e "\n📦 Installed LivingPortraitApp version $VERSION"
echo "$VERSION" > "$USER_HOME/version.txt"

# --- Flask systemd service ---
echo -e "\nSetting up Flask systemd service..."
if [ ! -f /etc/systemd/system/flask_ui.service ]; then
    sudo tee /etc/systemd/system/flask_ui.service > /dev/null << EOF
[Unit]
Description=Flask Web UI for Video Selector
After=network.target

[Service]
User=$USERNAME
WorkingDirectory=$USER_HOME/flask_ui
Environment=PYTHONPATH=$USER_HOME
Environment=DISPLAY=:0
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=$VENV_PATH/bin/python $USER_HOME/flask_ui/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    log_success "Systemd service file for Flask created"
else
    echo "✔ flask_ui.service already exists"
fi

sudo systemctl daemon-reload
sudo systemctl enable flask_ui
sudo systemctl restart flask_ui
log_success "Flask UI service enabled and restarted"

# --- motion_vlc.service for Raspberry Pi 5 ---
echo -e "\nSetting up motion_vlc.service..."
if [ ! -f /etc/systemd/system/motion_vlc.service ]; then
    sudo tee /etc/systemd/system/motion_vlc.service > /dev/null << EOF
[Unit]
Description=Run motion_vlc.py at boot (Raspberry Pi 5 optimized)
After=network.target

[Service]
User=$USERNAME
WorkingDirectory=$USER_HOME
Environment=DISPLAY=:0
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=PULSE_SERVER=unix:/run/user/1000/pulse/native
ExecStart=/usr/bin/python3 $USER_HOME/motion_vlc.py
StandardOutput=append:$USER_HOME/logs/motion_vlc.log
StandardError=append:$USER_HOME/logs/motion_vlc.err
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    log_success "Systemd service file for motion_vlc created (Pi 5)"
else
    echo "✔ motion_vlc.service already exists"
fi

sudo systemctl daemon-reload
sudo systemctl enable motion_vlc.service
sudo systemctl restart motion_vlc.service
log_success "motion_vlc service enabled and restarted"

echo -e "\n🎉 All setup steps completed. Please reboot to apply all changes."
