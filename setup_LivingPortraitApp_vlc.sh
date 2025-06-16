#!/bin/bash
set -e

# Flags
UPDATE_ONLY=false
for arg in "$@"; do
  case $arg in
    --update-only)
      UPDATE_ONLY=true
      ;;
  esac
done

log_success() {
    echo -e "\e[32m✅ $1 completed successfully.\e[0m"
}

log_fail() {
    echo -e "\e[31m❌ $1 failed.\e[0m"
    exit 1
}

download_if_changed() {
    local url=$1
    local dest=$2

    if [ -f "$dest" ] && curl -fsSL "$url" | diff -q - "$dest" &>/dev/null; then
        echo "✔ $dest is up to date"
    else
        curl -fsSL "$url" -o "$dest" && echo "⬇️  Updated $dest"
    fi
}

if [ "$UPDATE_ONLY" = false ]; then
    echo -e "\nUpdating system..."
    if sudo apt update && sudo apt upgrade -y; then
        log_success "System update"
    else
        log_fail "System update"
    fi

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

    echo -e "\nSetting up Python virtual environment..."
    if [ ! -d "$HOME/flask_venv" ]; then
        python3 -m venv ~/flask_venv || log_fail "Virtual environment creation"
        source ~/flask_venv/bin/activate
        pip install flask && deactivate || log_fail "Flask pip install"
        log_success "Flask virtual environment setup"
    else
        log_success "Virtual environment already exists"
    fi
fi

echo -e "\nCreating directories..."
mkdir -p ~/videos ~/pause_video ~/images ~/logs ~/shared ~/flask_ui/templates

echo -e "\nDownloading app files..."
download_if_changed "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/motion_vlc.py" "$HOME/motion_vlc.py"
download_if_changed "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/settings.json" "$HOME/settings.json"
chmod +x ~/motion_vlc.py

download_if_changed "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/images/logo.png" "$HOME/images/logo.png"
download_if_changed "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/pause_video/paused_rotated.mp4" "$HOME/pause_video/paused_rotated.mp4"
download_if_changed "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/flask_ui/app.py" "$HOME/flask_ui/app.py"
download_if_changed "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/flask_ui/templates/index.html" "$HOME/flask_ui/templates/index.html"
download_if_changed "https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/pi/shared/vlc_helper.py" "$HOME/shared/vlc_helper.py"

echo -e "\nSetting up Flask systemd service..."
if [ ! -f /etc/systemd/system/flask_ui.service ]; then
    sudo tee /etc/systemd/system/flask_ui.service > /dev/null << EOF
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
    log_success "Systemd service file for Flask created"
else
    echo "✔ flask_ui.service already exists"
fi

sudo systemctl daemon-reexec
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
ExecStart=/usr/bin/python3 /home/pi/motion_vlc.py
WorkingDirectory=/home/pi
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
