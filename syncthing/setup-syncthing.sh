#!/usr/bin/env bash
set -euo pipefail

# Determine actual non-root user
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

echo "==> Installing prerequisites..."
sudo apt-get update
sudo apt-get install -y curl apt-transport-https ca-certificates gnupg ufw

echo "==> Adding official Syncthing APT repository..."
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | \
  sudo tee /etc/apt/sources.list.d/syncthing.list

echo "==> Installing Syncthing..."
sudo apt-get update
sudo apt-get install -y syncthing

echo "==> Configuring base homelab folders..."
mkdir -p "${TARGET_HOME}/homelab/"{data,configs,backups}
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/homelab"

echo "==> Enabling and initializing systemd user service..."
sudo systemctl enable --now "syncthing@${TARGET_USER}.service"

# Wait briefly for default config.xml to generate
echo "==> Waiting for configuration generation..."
CONFIG_FILE="${TARGET_HOME}/.local/state/syncthing/config.xml"
ALT_CONFIG="${TARGET_HOME}/.config/syncthing/config.xml"

for _ in {1..15}; do
  if [ -f "$CONFIG_FILE" ]; then break; fi
  if [ -f "$ALT_CONFIG" ]; then CONFIG_FILE="$ALT_CONFIG"; break; fi
  sleep 1
done

echo "==> Binding GUI to 0.0.0.0:8384 for LAN / Tailscale access..."
sudo systemctl stop "syncthing@${TARGET_USER}.service"

if [ -f "$CONFIG_FILE" ]; then
  sed -i 's/<address>127.0.0.1:8384<\/address>/<address>0.0.0.0:8384<\/address>/' "$CONFIG_FILE"
else
  echo "Warning: config.xml not found yet. Change GUI address manually or restart service."
fi

sudo systemctl start "syncthing@${TARGET_USER}.service"

echo "==> Adjusting UFW firewall rules..."
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow 8384/tcp comment 'Syncthing Web GUI' || true
  sudo ufw allow 22000/tcp comment 'Syncthing Transfer TCP' || true
  sudo ufw allow 22000/udp comment 'Syncthing Transfer UDP (QUIC)' || true
  sudo ufw allow 21027/udp comment 'Syncthing Local Discovery' || true
fi

echo "--------------------------------------------------------"
echo " Syncthing setup complete!"
echo " Web GUI: http://<LAN-IP>:8384 or http://<TAILSCALE-IP>:8384"
echo " Remember to set an Admin password under Actions > Settings."
echo "--------------------------------------------------------"