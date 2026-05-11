# syntax=docker/dockerfile:1.7
#
# All-in-one Hermes container for Railway.
# Bundles Hermes Agent (gateway + dashboard) and Hermes WebUI into a single
# image so the WebUI can import agent modules directly (Railway cannot share
# volumes between services the way docker-compose.three-container.yml does).
#
# Build args:
#   HERMES_AGENT_VERSION  tag of nousresearch/hermes-agent (default: latest)
#   HERMES_WEBUI_VERSION  tag of ghcr.io/nesquena/hermes-webui (default: latest)

ARG HERMES_AGENT_VERSION=latest
ARG HERMES_WEBUI_VERSION=latest

# Stage 1 — pull hermes-agent so we can lift its source tree.
# The upstream three-container compose mounts /opt/hermes from this image
# at /home/hermeswebui/.hermes/hermes-agent in the WebUI container.
FROM nousresearch/hermes-agent:${HERMES_AGENT_VERSION} AS agent

# Stage 2 — build on top of the WebUI image.
FROM ghcr.io/nesquena/hermes-webui:${HERMES_WEBUI_VERSION}

USER root

# Drop the agent source where the WebUI image expects it (mirrors the
# hermes-agent-src named volume from docker-compose.three-container.yml).
COPY --from=agent /opt/hermes /opt/hermes
RUN mkdir -p /home/hermeswebui/.hermes \
    && ln -snf /opt/hermes /home/hermeswebui/.hermes/hermes-agent

# Install the agent into the WebUI's Python environment. This mirrors the
# `uv pip install /home/hermeswebui/.hermes/hermes-agent` call the WebUI's
# docker_init.bash performs at startup; doing it at build time moves the
# cost from boot to build.
RUN if command -v uv >/dev/null 2>&1; then \
        uv pip install --system /opt/hermes; \
    else \
        pip install --no-cache-dir /opt/hermes; \
    fi

# curl is required by the entrypoint health probe; install if missing.
RUN if ! command -v curl >/dev/null 2>&1; then \
        (apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*) \
        || (apk add --no-cache curl) \
        || true; \
    fi

# Bind on all interfaces — Railway proxies into the container by IP, not loopback.
ENV HERMES_WEBUI_HOST=0.0.0.0 \
    HERMES_WEBUI_PORT=8787 \
    HERMES_WEBUI_STATE_DIR=/home/hermeswebui/.hermes/webui \
    HERMES_HOME=/home/hermeswebui/.hermes \
    HERMES_WEBUI_AGENT_DIR=/opt/hermes \
    GATEWAY_HEALTH_URL=http://127.0.0.1:8642

# Process supervisor that runs gateway + dashboard + webui in one container.
COPY entrypoint.sh /usr/local/bin/hermes-entrypoint.sh
RUN chmod +x /usr/local/bin/hermes-entrypoint.sh \
    && chown -R hermeswebui:hermeswebui /home/hermeswebui/.hermes 2>/dev/null || true

EXPOSE 8787 9119

ENTRYPOINT ["/usr/local/bin/hermes-entrypoint.sh"]
