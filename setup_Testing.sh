#!/bin/bash
set -e

# ============================================================
# Raspberry Pi 3B, 3B+, 4, Zero, setup for LivingPortraitApp
# ============================================================

# Get current username and home directory
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
# Show progress, avoid waiting for input
sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || log_fail "apt upgrade failed"

log_success "System update completed"

echo -e "\nChecking required packages..."
REQUIRED_PKGS=(vlc python3-gpiozero python3-vlc python3-venv)
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

echo -e "\nChecking for additional Python packages (psutil, picamera2)..."
ADDITIONAL_PKGS=(python3-psutil python3-picamera2)
MISSING_ADDITIONAL=()
for pkg in "${ADDITIONAL_PKGS[@]}"; do
    dpkg -s "$pkg" &>/dev/null || MISSING_ADDITIONAL+=("$pkg")
done

if [ ${#MISSING_ADDITIONAL[@]} -eq 0 ]; then
    log_success "All additional Python packages already installed"
else
    echo "Installing missing Python packages: ${MISSING_ADDITIONAL[*]}"
    sudo apt install -y "${MISSING_ADDITIONAL[@]}" && log_success "Python package installation" || log_fail "Python package installation"
fi

echo -e "\nSetting up Python virtual environment..."
if [ ! -d "$VENV_PATH" ]; then
    # Create virtual environment with access to system packages
    python3 -m venv --system-site-packages "$VENV_PATH" || { echo "❌ Virtual environment creation failed"; exit 1; }
    # Upgrade pip inside the venv
    "$VENV_PATH/bin/pip" install --upgrade pip || { echo "❌ pip upgrade failed"; exit 1; }
    # Install Flask if not already present
    "$VENV_PATH/bin/pip" install flask || { echo "❌ Flask pip install failed"; exit 1; }
    echo "✅ Flask virtual environment setup complete"
else
    echo "✅ Virtual environment already exists (using system-site-packages)"
fi

echo -e "\nCreating directories..."
mkdir -p "$USER_HOME/videos" \
         "$USER_HOME/pause_video" \
         "$USER_HOME/images" \
         "$USER_HOME/logs" \
         "$USER_HOME/shared" \
         "$USER_HOME/flask_ui/templates"

echo -e "\nDownloading app files..."
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/motion_vlc.py" -o "$USER_HOME/motion_vlc.py"
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/settings.json" -o "$USER_HOME/settings.json"
chmod +x "$USER_HOME/motion_vlc.py"

curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/images/logo.png" -o "$USER_HOME/images/logo.png"
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/pause_video/paused_rotated.mp4" -o "$USER_HOME/pause_video/paused_rotated.mp4"
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/flask_ui/app.py" -o "$USER_HOME/flask_ui/app.py"
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/flask_ui/templates/index.html" -o "$USER_HOME/flask_ui/templates/index.html"
curl -fsSL "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/shared/vlc_helper.py" -o "$USER_HOME/shared/vlc_helper.py"

VERSION=$(curl -fsSL https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/version.txt)
echo -e "\n📦 Installed LivingPortraitApp version $VERSION"
echo "$VERSION" > "$USER_HOME/version.txt"

echo -e "\nSetting up Flask systemd service..."
SERVICE_FILE="/etc/systemd/system/flask_ui.service"

if [ ! -f "$SERVICE_FILE" ]; then
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Flask Web UI for Video Selector
After=network.target

[Service]
User=$USERNAME
WorkingDirectory=$USER_HOME/flask_ui
# Use venv's bin first in PATH
Environment="PATH=$VENV_PATH/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
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

echo -e "\nSetting up motion_vlc.service..."
if [ ! -f /etc/systemd/system/motion_vlc.service ]; then
    sudo tee /etc/systemd/system/motion_vlc.service > /dev/null << EOF
[Unit]
Description=Run motion_vlc.py at boot
After=network.target

[Service]
User=$USERNAME
ExecStart=/usr/bin/python3 $USER_HOME/motion_vlc.py
WorkingDirectory=$USER_HOME
StandardOutput=inherit
StandardError=inherit
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    log_success "Systemd service file for motion_vlc created"
else
    echo "✔ motion_vlc.service already exists"
fi

sudo systemctl daemon-reload
sudo systemctl enable motion_vlc.service
sudo systemctl restart motion_vlc.service
log_success "motion_vlc service enabled and restarted"

echo -e "\n🎉 All setup steps completed. Please reboot to apply all changes."
