# syntax=docker/dockerfile:1.7
#
# All-in-one Hermes container for Railway.
# Bundles Hermes Agent (gateway) and Hermes WebUI into a single image so
# the WebUI can import agent modules directly from the same filesystem
# (Railway cannot share volumes between services the way the upstream
# docker-compose.three-container.yml does).
#
# Build args:
#   HERMES_AGENT_VERSION  tag of nousresearch/hermes-agent (default: latest)
#   HERMES_WEBUI_VERSION  tag of ghcr.io/nesquena/hermes-webui (default: latest)

ARG HERMES_AGENT_VERSION=latest
ARG HERMES_WEBUI_VERSION=latest

# Stage 1 — pull hermes-agent so we can lift its source tree.
# Mirrors the hermes-agent-src named volume from the upstream
# docker-compose.three-container.yml.
FROM nousresearch/hermes-agent:${HERMES_AGENT_VERSION} AS agent

# Stage 2 — build on top of the WebUI image.
FROM ghcr.io/nesquena/hermes-webui:${HERMES_WEBUI_VERSION}

USER root

# Drop the agent source where the WebUI's docker_init.bash expects it.
COPY --from=agent /opt/hermes /opt/hermes
RUN mkdir -p /home/hermeswebui/.hermes \
    && ln -snf /opt/hermes /home/hermeswebui/.hermes/hermes-agent

# Install the agent into the system Python so the supervised
# `hermes gateway run` command in entrypoint.sh resolves to a real binary
# on $PATH (the upstream WebUI image ships the WebUI server only, not the
# agent CLI).
#
# Extras chosen for what the supervisor actually invokes:
#   [messaging] python-telegram-bot, discord.py, aiohttp, slack-* — Telegram
#               and Discord platform adapters.
#   [slack]     slack-bolt + slack-sdk for the Slack adapter (already pulled
#               in transitively via [messaging]; listed for clarity).
# We deliberately skip [all] to keep the image lean — voice/matrix/google
# extras add ~500MB and aren't part of this template's default surface.
#
# The install creates `hermes_agent.egg-info/` under /opt/hermes; chown
# afterwards so the runtime install at /app/venv (which the upstream
# docker_init.bash performs as `hermeswebui`) can update those timestamps.
RUN if command -v uv >/dev/null 2>&1; then \
        uv pip install --system "/opt/hermes[messaging,slack]"; \
    else \
        pip install --no-cache-dir "/opt/hermes[messaging,slack]"; \
    fi \
    && chown -R hermeswebui:hermeswebui /opt/hermes

# Bundled default config.yaml — seeded into ~/.hermes/config.yaml on first
# boot by entrypoint.sh. Kept outside any volume mount path so it survives
# volume-backed redeploys and can be refreshed by rebuilding the image.
COPY config.default.yaml /opt/hermes-defaults/config.yaml

# Bind on all interfaces — Railway proxies into the container by IP, not loopback.
ENV HERMES_WEBUI_HOST=0.0.0.0 \
    HERMES_WEBUI_PORT=8787 \
    HERMES_WEBUI_STATE_DIR=/home/hermeswebui/.hermes/webui \
    HERMES_HOME=/home/hermeswebui/.hermes \
    HERMES_WEBUI_AGENT_DIR=/opt/hermes

# Process supervisor that runs the gateway + the WebUI in one container.
COPY entrypoint.sh /usr/local/bin/hermes-entrypoint.sh
RUN chmod +x /usr/local/bin/hermes-entrypoint.sh \
    && chown -R hermeswebui:hermeswebui /home/hermeswebui/.hermes /opt/hermes-defaults 2>/dev/null || true

EXPOSE 8787

ENTRYPOINT ["/usr/local/bin/hermes-entrypoint.sh"]
