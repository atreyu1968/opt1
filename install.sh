#!/usr/bin/env bash
set -euo pipefail

APP_DIR=/opt/opt1
ENV_FILE="$APP_DIR/server/.env"
PORT_VALUE="${OPT1_PORT:-8080}"
PAGES_ORIGIN="${OPT1_PAGES_ORIGIN:-https://atreyu1968.github.io}"
API_DOMAIN="${OPT1_API_DOMAIN:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Este instalador necesita permisos de administración."
  echo "Ejecute: sudo bash install.sh"
  exit 1
fi

if [ -z "$API_DOMAIN" ] && [ -t 0 ]; then
  read -r -p "Dominio público de la API sin barra final, por ejemplo https://opt1.iesmmg.org: " API_DOMAIN
fi

if [ -n "$API_DOMAIN" ] && [[ ! "$API_DOMAIN" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
  echo "El dominio debe comenzar por https:// y no debe incluir rutas ni barra final."
  exit 1
fi

if ! [[ "$PORT_VALUE" =~ ^[0-9]{2,5}$ ]] || [ "$PORT_VALUE" -gt 65535 ]; then
  echo "El puerto indicado no es válido."
  exit 1
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SOURCE_DIR/server/install.sh"

if [ ! -f "$ENV_FILE" ]; then
  echo "No se ha podido localizar $ENV_FILE"
  exit 1
fi

set_env_value() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

ORIGINS="$PAGES_ORIGIN,http://localhost:8000,http://127.0.0.1:8000"
if [ -n "$API_DOMAIN" ]; then ORIGINS="$ORIGINS,$API_DOMAIN"; fi
set_env_value PORT "$PORT_VALUE"
set_env_value HOST "0.0.0.0"
set_env_value DATA_DIR "/var/lib/opt1"
set_env_value PUBLIC_ORIGINS "$ORIGINS"
set_env_value SESSION_HOURS "168"
set_env_value TRUST_PROXY "1"

chown opt1:opt1 "$ENV_FILE"
chmod 640 "$ENV_FILE"
systemctl restart opt1

for attempt in 1 2 3 4 5; do
  if curl -fsS "http://127.0.0.1:${PORT_VALUE}/api/health" >/dev/null; then
    echo ""
    echo "OPT1 se ha instalado correctamente."
    echo "Servicio local: http://127.0.0.1:${PORT_VALUE}"
    if [ -n "$API_DOMAIN" ]; then
      echo "Panel docente: ${API_DOMAIN}/admin.html"
      echo "Enlace para el alumnado: ${PAGES_ORIGIN}/opt1/?api=${API_DOMAIN}"
    else
      echo "Configure el dominio HTTPS y después abra /admin.html para crear el administrador."
    fi
    echo ""
    echo "Para instalar o comprobar Cloudflare Tunnel:"
    echo "  sudo bash configure-cloudflare.sh"
    if [ -n "${OPT1_CF_TUNNEL_TOKEN:-}" ]; then
      echo "Se ha recibido un token por variable de entorno; configurando el túnel..."
      bash "$SOURCE_DIR/configure-cloudflare.sh"
    fi
    exit 0
  fi
  sleep 2
done

echo "El servicio no ha respondido a la comprobación."
echo "Revise: sudo journalctl -u opt1 -n 100 --no-pager"
exit 1
