#!/bin/bash
set -euo pipefail

DATA_DISK="/dev/disk/by-id/google-zomboid-data-disk"
MOUNT_POINT="/mnt/zomboid-data"
ZOMBOID_HOME="${MOUNT_POINT}/home"
STEAMCMD_DIR="${MOUNT_POINT}/steamcmd"
SERVER_DIR="${MOUNT_POINT}/pzserver"

# --- 1. Format the data disk, but only if it has no filesystem yet ---
if ! blkid "${DATA_DISK}" > /dev/null 2>&1; then
  echo "No filesystem found on data disk -- formatting (first boot only)"
  mkfs.ext4 -m 0 -F "${DATA_DISK}"
else
  echo "Data disk already formatted -- skipping"
fi

# --- 2. Mount it ---
mkdir -p "${MOUNT_POINT}"
if ! mountpoint -q "${MOUNT_POINT}"; then
  mount "${DATA_DISK}" "${MOUNT_POINT}"
fi

# --- 3. Persist the mount across reboots via fstab (idempotent) ---
if ! grep -q "${MOUNT_POINT}" /etc/fstab; then
  echo "${DATA_DISK} ${MOUNT_POINT} ext4 discard,defaults 0 2" >> /etc/fstab
fi

# --- 4. Install OS-level dependencies SteamCMD needs ---
dpkg --add-architecture i386
apt-get update -y
apt-get install -y --no-install-recommends \
  lib32gcc-s1 lib32stdc++6 curl ca-certificates unzip

# --- 5. Create the dedicated non-root user, home directory on the persistent disk ---
mkdir -p "${ZOMBOID_HOME}"
if ! id -u zomboid > /dev/null 2>&1; then
  useradd --system --home-dir "${ZOMBOID_HOME}" --shell /usr/sbin/nologin zomboid
fi
chown -R zomboid:zomboid "${MOUNT_POINT}"

# --- 6. Install SteamCMD itself, only if not already present ---
if [ ! -f "${STEAMCMD_DIR}/steamcmd.sh" ]; then
  echo "Installing SteamCMD (first boot only)"
  mkdir -p "${STEAMCMD_DIR}"
  curl -sSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
    | tar -xz -C "${STEAMCMD_DIR}"
  chown -R zomboid:zomboid "${STEAMCMD_DIR}"
fi

# --- 7. Install / update the Zomboid Dedicated Server via SteamCMD ---
# App ID 380870 is Project Zomboid Dedicated Server -- public, anonymous login works
sudo -u zomboid HOME="${ZOMBOID_HOME}" "${STEAMCMD_DIR}/steamcmd.sh" \
  +force_install_dir "${SERVER_DIR}" \
  +login anonymous \
  +app_update 380870 validate \
  +quit

echo "Disk mount and server install stage complete"

# --- 8. Pull config from instance metadata (single source of truth = Terraform vars) ---
META_URL="http://metadata.google.internal/computeMetadata/v1"
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" "${META_URL}/project/project-id")
RCON_PORT=$(curl -s -H "Metadata-Flavor: Google" "${META_URL}/instance/attributes/rcon-port")
SERVER_NAME=$(curl -s -H "Metadata-Flavor: Google" "${META_URL}/instance/attributes/server-name")

# --- 9. Fetch the RCON password from Secret Manager using the VM's own identity ---
ACCESS_TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  "${META_URL}/instance/service-accounts/default/token" \
  | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

RCON_PASSWORD=$(curl -s \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/zomboid-rcon-password/versions/latest:access" \
  | python3 -c "import sys, json, base64; print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode())")

# --- 10. Write RCON settings into the server config (created fresh by the game server on its very first run) ---
CONFIG_DIR="${ZOMBOID_HOME}/Zomboid/Server"
mkdir -p "${CONFIG_DIR}"
CONFIG_FILE="${CONFIG_DIR}/${SERVER_NAME}.ini"
touch "${CONFIG_FILE}"

if grep -q "^RCONPassword=" "${CONFIG_FILE}"; then
  sed -i "s/^RCONPassword=.*/RCONPassword=${RCON_PASSWORD}/" "${CONFIG_FILE}"
else
  echo "RCONPassword=${RCON_PASSWORD}" >> "${CONFIG_FILE}"
fi

if grep -q "^RCONPort=" "${CONFIG_FILE}"; then
  sed -i "s/^RCONPort=.*/RCONPort=${RCON_PORT}/" "${CONFIG_FILE}"
else
  echo "RCONPort=${RCON_PORT}" >> "${CONFIG_FILE}"
fi

# --- 10b. Fetch the server (join) password and write it into the config ---
SERVER_PASSWORD=$(curl -s \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/zomboid-server-password/versions/latest:access" \
  | python3 -c "import sys, json, base64; print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode())")

if grep -q "^Password=" "${CONFIG_FILE}"; then
  sed -i "s/^Password=.*/Password=${SERVER_PASSWORD}/" "${CONFIG_FILE}"
else
  echo "Password=${SERVER_PASSWORD}" >> "${CONFIG_FILE}"
fi

chown -R zomboid:zomboid "${ZOMBOID_HOME}/Zomboid"

# --- 11a. Create a launch wrapper that fetches the admin password at runtime
#          and feeds it to the server's first-run interactive prompt via stdin ---
cat > "${SERVER_DIR}/launch-zomboid.sh" <<'WRAPEOF'
#!/bin/bash
set -euo pipefail

META_URL="http://metadata.google.internal/computeMetadata/v1"
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" "${META_URL}/project/project-id")
SERVER_NAME=$(curl -s -H "Metadata-Flavor: Google" "${META_URL}/instance/attributes/server-name")

ACCESS_TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  "${META_URL}/instance/service-accounts/default/token" \
  | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

ADMIN_PASSWORD=$(curl -s \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/zomboid-admin-password/versions/latest:access" \
  | python3 -c "import sys, json, base64; print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode())")

printf '%s\n%s\n' "${ADMIN_PASSWORD}" "${ADMIN_PASSWORD}" | exec "$(dirname "$0")/start-server.sh" -servername "${SERVER_NAME}"
WRAPEOF

chmod 750 "${SERVER_DIR}/launch-zomboid.sh"
chown zomboid:zomboid "${SERVER_DIR}/launch-zomboid.sh"

# --- 11. Write (or update) the systemd unit and (re)start the game server ---
cat > /etc/systemd/system/zomboid.service <<EOF
[Unit]
Description=Project Zomboid Dedicated Server
After=network-online.target local-fs.target
Wants=network-online.target

[Service]
Type=simple
User=zomboid
Group=zomboid
WorkingDirectory=${SERVER_DIR}
Environment=HOME=${ZOMBOID_HOME}
ExecStart=${SERVER_DIR}/launch-zomboid.sh
Restart=on-failure
RestartSec=10
TimeoutStopSec=60
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zomboid.service
systemctl restart zomboid.service

echo "Zomboid systemd service configured and (re)started"