#!/bin/bash
set -e

# --- Environment ---
USER_HOME="$HOME"

log_success() { echo -e "\e[32m✅ $1\e[0m"; }
log_info() { echo -e "\e[34mℹ️  $1\e[0m"; }
log_fail() { echo -e "\e[31m❌ $1\e[0m"; exit 1; }

# --- Download app files ---
log_info "Downloading latest app files..."

curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/motion_vlc.py" -o "$USER_HOME/motion_vlc.py" || log_fail "Failed to download motion_vlc.py"
# curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/settings.json" -o "$USER_HOME/settings.json" || log_fail "Failed to download settings.json"
chmod +x "$USER_HOME/motion_vlc.py"

curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/images/logo.png" -o "$USER_HOME/images/logo.png" || log_fail "Failed to download logo.png"
curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/pause_video/paused_rotated.mp4" -o "$USER_HOME/pause_video/paused_rotated.mp4" || log_fail "Failed to download paused_rotated.mp4"

curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/flask_ui/app.py" -o "$USER_HOME/flask_ui/app.py" || log_fail "Failed to download Flask app.py"
curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/flask_ui/templates/index.html" -o "$USER_HOME/flask_ui/templates/index.html" || log_fail "Failed to download index.html"

curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/shared/vlc_helper.py" -o "$USER_HOME/shared/vlc_helper.py" || log_fail "Failed to download vlc_helper.py"

# --- Update version file ---
VERSION=$(curl -fsSL "https://raw.githubusercontent.com/frosty409/LivingPortraitApp/refs/heads/main/pi/version.txt") || log_fail "Failed to download version.txt"
echo "$VERSION" > "$USER_HOME/version.txt"

log_success "App files updated to version $VERSION"


# --- Reboot the Pi ---
log_info "Rebooting system to apply changes..."
sudo reboot
