#!/usr/bin/env bash
set -euo pipefail

PORT_VALUE="${OPT1_PORT:-8080}"
API_DOMAIN="${OPT1_API_DOMAIN:-}"
TUNNEL_TOKEN="${OPT1_CF_TUNNEL_TOKEN:-}"
REPLACE_SERVICE="${OPT1_CF_REPLACE:-0}"

if [ "${1:-}" = "--replace-service" ]; then
  REPLACE_SERVICE=1
elif [ "$#" -gt 0 ]; then
  echo "Uso: sudo bash configure-cloudflare.sh [--replace-service]"
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Este configurador necesita permisos de administración."
  echo "Ejecute: sudo bash configure-cloudflare.sh"
  exit 1
fi

if ! [[ "$PORT_VALUE" =~ ^[0-9]{2,5}$ ]] || [ "$PORT_VALUE" -gt 65535 ]; then
  echo "El puerto indicado no es válido: $PORT_VALUE"
  exit 1
fi

echo "Comprobando primero la aplicación OPT1..."
if ! curl -fsS "http://127.0.0.1:${PORT_VALUE}/api/health" >/dev/null; then
  echo "ERROR: OPT1 no responde en http://127.0.0.1:${PORT_VALUE}/api/health"
  echo "Cloudflare no puede publicar una aplicación que no responde localmente."
  echo "Revise: sudo systemctl status opt1 --no-pager"
  echo "Revise: sudo journalctl -u opt1 -n 100 --no-pager"
  exit 1
fi
echo "OPT1 responde correctamente en el servidor."

if [ -z "$API_DOMAIN" ] && [ -t 0 ]; then
  read -r -p "Dominio público de la API, por ejemplo https://opt1.midominio.es: " API_DOMAIN
fi
if [ -n "$API_DOMAIN" ] && [[ ! "$API_DOMAIN" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
  echo "El dominio debe comenzar por https:// y no debe incluir rutas ni barra final."
  exit 1
fi

echo "Instalando cloudflared desde el repositorio oficial de Cloudflare..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates gnupg
install -d -m 0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
  | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
  > /etc/apt/sources.list.d/cloudflared.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y cloudflared

request_token() {
  if [ -z "$TUNNEL_TOKEN" ] && [ -t 0 ]; then
    echo ""
    echo "En Cloudflare Zero Trust cree/abra el túnel y copie únicamente el token eyJ..."
    read -r -s -p "Token del túnel (no se mostrará): " TUNNEL_TOKEN
    echo ""
  fi
  if [ -z "$TUNNEL_TOKEN" ]; then
    echo "ERROR: falta el token del túnel."
    echo "Vuelva a ejecutar este script y péguelo cuando se solicite."
    exit 1
  fi
}

if systemctl list-unit-files cloudflared.service --no-legend 2>/dev/null | grep -q '^cloudflared.service'; then
  echo ""
  echo "Ya existe un servicio cloudflared en este servidor."
  if [ "$REPLACE_SERVICE" = "1" ]; then
    echo "Se ha solicitado expresamente reemplazar el servicio existente."
    echo "Continúe solo si este conector está dedicado a OPT1."
    request_token
    cloudflared service uninstall
    cloudflared service install "$TUNNEL_TOKEN"
    unset TUNNEL_TOKEN OPT1_CF_TUNNEL_TOKEN
    systemctl enable --now cloudflared
  else
    echo "No se sustituirá automáticamente porque podría publicar otras aplicaciones."
    systemctl enable --now cloudflared
    echo "Si este conector pertenece solo a OPT1 y su token es incorrecto, use:"
    echo "  sudo bash configure-cloudflare.sh --replace-service"
  fi
else
  request_token
  cloudflared service install "$TUNNEL_TOKEN"
  unset TUNNEL_TOKEN OPT1_CF_TUNNEL_TOKEN
  systemctl enable --now cloudflared
fi

sleep 3
if ! systemctl is-active --quiet cloudflared; then
  echo "ERROR: cloudflared no está activo."
  echo "Revise: sudo journalctl -u cloudflared -n 100 --no-pager"
  exit 1
fi

echo ""
echo "cloudflared está activo."
echo "En Cloudflare, el hostname público debe apuntar exactamente a:"
echo "  Tipo: HTTP"
echo "  URL:  http://localhost:${PORT_VALUE}"

if [ -n "$API_DOMAIN" ]; then
  echo ""
  echo "Comprobando ${API_DOMAIN}/api/health ..."
  if curl -fsS --max-time 15 "${API_DOMAIN}/api/health"; then
    echo ""
    echo "Acceso público correcto."
    echo "Panel docente: ${API_DOMAIN}/admin.html"
    echo "Curso: https://atreyu1968.github.io/opt1/?api=${API_DOMAIN}"
  else
    echo ""
    echo "El túnel está iniciado, pero el dominio aún no responde correctamente."
    echo "Compruebe en Cloudflare que el hostname usa HTTP y localhost:${PORT_VALUE}."
    echo "Ejecute: sudo bash cloudflare-diagnostico.sh ${API_DOMAIN}"
    exit 2
  fi
else
  echo "Ejecute después: sudo bash cloudflare-diagnostico.sh https://SU-DOMINIO"
fi
