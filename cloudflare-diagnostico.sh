#!/usr/bin/env bash
set -u

PORT_VALUE="${OPT1_PORT:-8080}"
API_DOMAIN="${1:-${OPT1_API_DOMAIN:-}}"
ERRORS=0

ok() { printf '  [OK] %s\n' "$1"; }
fail() { printf '  [FALLO] %s\n' "$1"; ERRORS=$((ERRORS+1)); }
info() { printf '  [INFO] %s\n' "$1"; }

echo "Diagnóstico de OPT1 y Cloudflare Tunnel"
echo "========================================"

echo "1. Aplicación local"
if systemctl is-active --quiet opt1 2>/dev/null; then
  ok "opt1.service está activo"
else
  fail "opt1.service no está activo"
fi
if curl -fsS --max-time 5 "http://127.0.0.1:${PORT_VALUE}/api/health" >/dev/null; then
  ok "la API responde en localhost:${PORT_VALUE}"
else
  fail "la API no responde en localhost:${PORT_VALUE}"
fi

echo "2. Conector Cloudflare"
if command -v cloudflared >/dev/null 2>&1; then
  ok "cloudflared está instalado: $(cloudflared --version 2>&1 | head -n 1)"
else
  fail "cloudflared no está instalado"
fi
if systemctl is-active --quiet cloudflared 2>/dev/null; then
  ok "cloudflared.service está activo"
else
  fail "cloudflared.service no está activo"
fi

echo "3. Salida hacia la red de Cloudflare"
if timeout 8 bash -c '</dev/tcp/region1.v2.argotunnel.com/7844' 2>/dev/null; then
  ok "el servidor puede salir por TCP 7844"
else
  info "no se pudo verificar TCP 7844; un cortafuegos saliente puede bloquear el túnel"
fi

echo "4. Dominio público"
if [ -z "$API_DOMAIN" ]; then
  info "no se indicó dominio; use: sudo bash cloudflare-diagnostico.sh https://opt1.midominio.es"
else
  if [[ ! "$API_DOMAIN" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
    fail "el dominio debe tener el formato https://opt1.midominio.es"
  else
    HOSTNAME_VALUE="${API_DOMAIN#https://}"
    HOSTNAME_VALUE="${HOSTNAME_VALUE%%:*}"
    if getent ahosts "$HOSTNAME_VALUE" >/dev/null 2>&1; then
      ok "$HOSTNAME_VALUE tiene resolución DNS"
    else
      fail "$HOSTNAME_VALUE no resuelve por DNS"
    fi
    TMP_BODY="$(mktemp)"
    HTTP_CODE="$(curl -sS --max-time 15 -o "$TMP_BODY" -w '%{http_code}' "${API_DOMAIN}/api/health" 2>/dev/null || true)"
    if [ "$HTTP_CODE" = "200" ] && grep -q '"ok":true' "$TMP_BODY"; then
      ok "la API pública responde correctamente"
    elif [ "$HTTP_CODE" = "502" ]; then
      fail "Cloudflare devuelve 502: el túnel no alcanza http://localhost:${PORT_VALUE}"
    elif [ "$HTTP_CODE" = "000" ] || [ -z "$HTTP_CODE" ]; then
      fail "no se pudo establecer conexión HTTPS con el dominio"
    else
      fail "el dominio respondió con HTTP ${HTTP_CODE:-desconocido}"
    fi
    rm -f "$TMP_BODY"
  fi
fi

echo "5. Últimos eventos del túnel"
if command -v journalctl >/dev/null 2>&1; then
  journalctl -u cloudflared -n 12 --no-pager 2>/dev/null \
    | sed -E 's/(eyJ[A-Za-z0-9_.-]+)/[TOKEN OCULTO]/g' || true
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo "Resultado: no se han detectado fallos básicos."
else
  echo "Resultado: se han detectado ${ERRORS} fallo(s)."
  echo "Copie este resultado para localizar el punto exacto; no contiene el token."
fi
exit "$ERRORS"
