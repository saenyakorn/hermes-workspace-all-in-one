#!/usr/bin/env bash
# Process supervisor for the all-in-one Hermes container on Railway.
#
# Order of operations:
#   1. Seed ${HERMES_HOME}/config.yaml from /opt/hermes-defaults/config.yaml
#      when the user has no config yet (preserves any volume-mounted config).
#   2. Make sure HERMES_HOME and its children are owned by hermeswebui (UID 1024
#      from the upstream image) so the WebUI init script and the gateway agree
#      on file ownership.
#   3. Start `hermes gateway run` as hermeswebui in the background.
#      (Don't block on a port — the gateway only binds :8642 when at least
#      one messaging platform is enabled, and the dashboard/webui both tolerate
#      the gateway being unavailable.)
#   4. Start `hermes dashboard --host 0.0.0.0` as hermeswebui in the background.
#   5. Exec /hermeswebui_init.bash — the upstream root-then-hermeswebui init
#      that installs the WebUI venv, syncs /app, and runs `python server.py`.
#
# SIGTERM/SIGINT received by PID 1 propagates to the gateway and dashboard
# children before handing off to the WebUI init.

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

HERMES_HOME_DIR="${HERMES_HOME:-/home/hermeswebui/.hermes}"
HERMES_CONFIG_PATH="${HERMES_HOME_DIR}/config.yaml"
HERMES_DEFAULTS_PATH="/opt/hermes-defaults/config.yaml"

mkdir -p "${HERMES_HOME_DIR}"

if [[ ! -f "${HERMES_CONFIG_PATH}" && -f "${HERMES_DEFAULTS_PATH}" ]]; then
  log "seeding default config -> ${HERMES_CONFIG_PATH}"
  cp "${HERMES_DEFAULTS_PATH}" "${HERMES_CONFIG_PATH}"
  chmod 0600 "${HERMES_CONFIG_PATH}" || true
else
  log "config.yaml already present at ${HERMES_CONFIG_PATH} — leaving it alone"
fi

# Both the gateway/dashboard processes we background here and the WebUI init
# script that takes over PID 1 run as the hermeswebui user. Make sure every
# file under HERMES_HOME is owned by them before any agent code touches it.
if id -u hermeswebui >/dev/null 2>&1; then
  chown -R hermeswebui:hermeswebui "${HERMES_HOME_DIR}" 2>/dev/null || true
fi

# runuser keeps the env (we need HERMES_HOME, GATEWAY_HEALTH_URL, provider keys
# from Railway) but executes as the hermeswebui user — that way any state
# written under ~/.hermes is readable by the WebUI process started later.
run_as_hermeswebui() {
  runuser --preserve-environment -u hermeswebui -- "$@"
}

log "starting hermes gateway (as hermeswebui)"
run_as_hermeswebui hermes gateway run >/proc/1/fd/1 2>/proc/1/fd/2 &
GATEWAY_PID=$!

log "starting hermes dashboard on 0.0.0.0:9119 (as hermeswebui)"
run_as_hermeswebui hermes dashboard --host 0.0.0.0 --insecure >/proc/1/fd/1 2>/proc/1/fd/2 &
DASHBOARD_PID=$!

log "handing off to upstream WebUI init (port ${HERMES_WEBUI_PORT:-8787})"
exec /hermeswebui_init.bash
