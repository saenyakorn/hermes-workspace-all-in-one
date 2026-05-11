#!/usr/bin/env bash
# Process supervisor for the all-in-one Hermes container on Railway.
#
# Order of operations:
#   1. Seed ~/.hermes/config.yaml from /opt/hermes-defaults/config.yaml if
#      the user has no config yet (preserves any volume-mounted config).
#   2. Start hermes gateway run        — background, loopback :8642
#   3. Wait for :8642 to accept TCP connections (no /health dependency).
#   4. Start hermes dashboard          — background, all interfaces :9119
#   5. Exec the upstream WebUI startup — foreground, all interfaces :8787
#
# SIGTERM/SIGINT received by PID 1 propagates to the gateway and dashboard
# children before handing off to the WebUI.

set -euo pipefail

GATEWAY_PID=""
DASHBOARD_PID=""

cleanup() {
  if [[ -n "${GATEWAY_PID}" ]]; then
    kill "${GATEWAY_PID}" 2>/dev/null || true
  fi
  if [[ -n "${DASHBOARD_PID}" ]]; then
    kill "${DASHBOARD_PID}" 2>/dev/null || true
  fi
}
trap cleanup TERM INT EXIT

log() {
  printf '[hermes-entrypoint] %s\n' "$*"
}

HERMES_CONFIG_PATH="${HERMES_HOME:-/home/hermeswebui/.hermes}/config.yaml"
HERMES_DEFAULTS_PATH="/opt/hermes-defaults/config.yaml"

if [[ ! -f "${HERMES_CONFIG_PATH}" && -f "${HERMES_DEFAULTS_PATH}" ]]; then
  log "seeding default config -> ${HERMES_CONFIG_PATH}"
  mkdir -p "$(dirname "${HERMES_CONFIG_PATH}")"
  cp "${HERMES_DEFAULTS_PATH}" "${HERMES_CONFIG_PATH}"
  chmod 0600 "${HERMES_CONFIG_PATH}" || true
else
  log "config.yaml already present at ${HERMES_CONFIG_PATH} — leaving it alone"
fi

log "starting hermes gateway on 127.0.0.1:8642"
hermes gateway run >/proc/1/fd/1 2>/proc/1/fd/2 &
GATEWAY_PID=$!

log "waiting for gateway to accept TCP connections on :8642 (up to 30s)"
gateway_ready=0
for _ in $(seq 1 30); do
  if (echo >/dev/tcp/127.0.0.1/8642) 2>/dev/null; then
    log "gateway port :8642 is open"
    gateway_ready=1
    break
  fi
  if ! kill -0 "${GATEWAY_PID}" 2>/dev/null; then
    log "gateway exited before opening :8642"
    exit 1
  fi
  sleep 1
done

if [[ "${gateway_ready}" -ne 1 ]]; then
  log "gateway did not open :8642 within 30s — continuing anyway"
fi

log "starting hermes dashboard on 0.0.0.0:9119"
hermes dashboard --host 0.0.0.0 --insecure >/proc/1/fd/1 2>/proc/1/fd/2 &
DASHBOARD_PID=$!

log "handing off to upstream WebUI init (port ${HERMES_WEBUI_PORT:-8787})"
exec /home/hermeswebui/docker_init.bash
