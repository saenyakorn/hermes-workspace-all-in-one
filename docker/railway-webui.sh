#!/usr/bin/env bash
set -euo pipefail

# Hermes WebUI launcher for Railway / single-container images.
# Invoked after nousresearch/hermes-agent docker/entrypoint.sh has bootstrapped
# HERMES_HOME on the persistent volume (runs as the hermes user).

export HERMES_WEBUI_AGENT_DIR="${HERMES_WEBUI_AGENT_DIR:-/opt/hermes}"
export HERMES_WEBUI_HOST="${HERMES_WEBUI_HOST:-0.0.0.0}"
# Railway sets PORT; fall back to HERMES_WEBUI_PORT then 8787.
export HERMES_WEBUI_PORT="${PORT:-${HERMES_WEBUI_PORT:-8787}}"

_hermes_home="${HERMES_HOME:-/opt/data}"
export HERMES_WEBUI_STATE_DIR="${HERMES_WEBUI_STATE_DIR:-${_hermes_home}/webui}"
export HERMES_WEBUI_DEFAULT_WORKSPACE="${HERMES_WEBUI_DEFAULT_WORKSPACE:-${_hermes_home}/workspace}"

mkdir -p "${HERMES_WEBUI_STATE_DIR}"
mkdir -p "${HERMES_WEBUI_DEFAULT_WORKSPACE}"

cd /app
exec /opt/hermes/.venv/bin/python server.py
