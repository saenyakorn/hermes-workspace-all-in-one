#!/usr/bin/env bash
# Process supervisor for the all-in-one Hermes container on Railway.
# Starts:
#   1. hermes gateway run        — background, loopback :8642
#   2. hermes dashboard          — background, all interfaces :9119
#   3. hermes-webui (server.py)  — foreground, all interfaces :8787
#
# SIGTERM/SIGINT received by PID 1 is propagated to the gateway and
# dashboard children before exec'ing the WebUI startup.

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

log "starting hermes gateway on 127.0.0.1:8642"
hermes gateway run >/proc/1/fd/1 2>/proc/1/fd/2 &
GATEWAY_PID=$!

log "waiting for gateway /health (up to 30s)"
for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8642/health >/dev/null 2>&1; then
    log "gateway is healthy"
    break
  fi
  if ! kill -0 "${GATEWAY_PID}" 2>/dev/null; then
    log "gateway exited before becoming healthy"
    exit 1
  fi
  sleep 1
done

log "starting hermes dashboard on 0.0.0.0:9119"
hermes dashboard --host 0.0.0.0 --insecure >/proc/1/fd/1 2>/proc/1/fd/2 &
DASHBOARD_PID=$!

log "handing off to upstream WebUI init (port ${HERMES_WEBUI_PORT:-8787})"
exec /home/hermeswebui/docker_init.bash
