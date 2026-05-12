# Hermes Agent (official image) + Hermes WebUI in one container.
# https://github.com/nousresearch/hermes-agent
# https://github.com/nesquena/hermes-webui

ARG HERMES_WEBUI_VERSION=latest
ARG HERMES_AGENT_VERSION=latest
FROM ghcr.io/nesquena/hermes-webui:${HERMES_WEBUI_VERSION} AS webui

FROM docker.io/nousresearch/hermes-agent:${HERMES_AGENT_VERSION}

USER root

ARG HERMES_AGENT_VERSION

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Official WebUI image bakes the repo under /apptoo; we install from /app on the agent image.
RUN rm -rf /app
COPY --from=webui /apptoo /app

RUN /usr/local/bin/uv pip install --python /opt/hermes/.venv/bin/python -r /app/requirements.txt \
  && /usr/local/bin/uv pip install --python /opt/hermes/.venv/bin/python -U pip setuptools

RUN chown -R hermes:hermes /app

COPY docker/railway-webui.sh /opt/hermes/docker/railway-webui.sh
RUN chmod 0755 /opt/hermes/docker/railway-webui.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT:-8787}/health" || exit 1

USER root
CMD ["/bin/bash", "/opt/hermes/docker/railway-webui.sh"]
