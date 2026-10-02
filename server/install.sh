#!/usr/bin/env bash
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Ejecute: sudo bash install.sh"; exit 1; fi
APP_DIR=/opt/opt1
DATA_DIR=/var/lib/opt1
SERVICE_USER=opt1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if ! command -v node >/dev/null 2>&1 || [ "$(node -p 'Number(process.versions.node.split(`.`)[0])')" -lt 22 ]; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi
id "$SERVICE_USER" >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
mkdir -p "$APP_DIR" "$DATA_DIR"
cp -R "$SOURCE_DIR/server" "$SOURCE_DIR/web" "$APP_DIR"/
if [ ! -f "$APP_DIR/server/.env" ]; then cp "$APP_DIR/server/.env.example" "$APP_DIR/server/.env"; fi
chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR" "$DATA_DIR"
sed "s|__APP_DIR__|$APP_DIR|g" "$APP_DIR/server/opt1.service.template" > /etc/systemd/system/opt1.service
systemctl daemon-reload
systemctl enable --now opt1
echo "Instalación terminada. Abra http://IP-DEL-SERVIDOR:8080/admin.html para crear el administrador."
