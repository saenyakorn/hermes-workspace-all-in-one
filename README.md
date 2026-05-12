# Hermes Agent + WebUI (Railway, single container)

This repository is a **Railway-ready template**: one Docker image and one running process that serves **[Hermes WebUI](https://github.com/nesquena/hermes-webui)** while using the same Python environment as **[Hermes Agent](https://github.com/nousresearch/hermes-agent)** from the official agent image. The WebUI talks to the agent in-process; there is no separate agent container.

## Architecture

- **Base image:** [`nousresearch/hermes-agent`](https://hub.docker.com/r/nousresearch/hermes-agent) on Docker Hub (`HERMES_AGENT_VERSION`, default `latest`). Agent code and venv live under `/opt/hermes` (venv: `/opt/hermes/.venv`).
- **WebUI:** Files are copied at build time from **`ghcr.io/nesquena/hermes-webui`** (tag from `HERMES_WEBUI_VERSION`, default `latest`) into **`/app`**; `requirements.txt` is installed **into the agent venv** so one interpreter runs `server.py` with full agent capabilities.
- **Startup:** The upstream agent `ENTRYPOINT` (`tini` + `docker/entrypoint.sh`) still runs first to bootstrap `$HERMES_HOME` (default `/opt/data`) on disk. Then [`docker/railway-webui.sh`](docker/railway-webui.sh) starts the WebUI, binding to `0.0.0.0` and **Railway’s `PORT`**.
- **Hermes config:** On first boot, when `config.yaml` is missing under the data volume, the agent entrypoint copies the upstream `cli-config.yaml.example` from the Hermes Agent image. Customize `config.yaml` in the volume (or via the WebUI) as needed.

## Deploy on Railway

1. Create a **new project** and deploy **from this GitHub repository** (or push this repo and connect it).
2. Railway will use [`railway.json`](railway.json): Dockerfile builder, root `Dockerfile`.
3. Add a **volume** on the Web service, mount path **`/opt/data`**. This persists Hermes home (config, memory, skills, sessions) and WebUI state (`/opt/data/webui` by default).
4. Set **environment variables** (at minimum one LLM provider key, e.g. `ANTHROPIC_API_KEY`). See [Hermes Agent environment docs](https://hermes-agent.nousresearch.com/).
5. For any **public** URL, set a strong **`HERMES_WEBUI_PASSWORD`** (optional password auth in the WebUI).

Health checks use `GET /health` on the bound port (`PORT` or `8787`).

## Build arguments

| Build arg | Default | Meaning |
|-----------|---------|---------|
| `HERMES_AGENT_VERSION` | `latest` | Docker Hub tag for `nousresearch/hermes-agent` |
| `HERMES_WEBUI_VERSION` | `latest` | Tag for `ghcr.io/nesquena/hermes-webui` (e.g. `latest` or `v0.51.50`) |

The WebUI sources are **copied from the published container image** (`FROM ghcr.io/nesquena/hermes-webui:${HERMES_WEBUI_VERSION}`); this repo does not clone the WebUI git repository at build time.

Configure these under **Service → Settings → Build → Docker Build Args** (or in `railway.json` under `build.args`). Pin versions for reproducible deploys.

## Local Docker

```bash
docker build -t hermes-railway-all-in-one \
  --build-arg HERMES_AGENT_VERSION=latest \
  --build-arg HERMES_WEBUI_VERSION=latest \
  .

docker run --rm -p 8787:8787 -e PORT=8787 \
  -v hermes-data:/opt/data \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  hermes-railway-all-in-one
```

Open `http://localhost:8787`. For password protection add `-e HERMES_WEBUI_PASSWORD=...`.

## Upstream projects

- Agent: [https://github.com/nousresearch/hermes-agent](https://github.com/nousresearch/hermes-agent)
- WebUI: [https://github.com/nesquena/hermes-webui](https://github.com/nesquena/hermes-webui)

## License

Hermes Agent and Hermes WebUI have their own licenses (see upstream repos). The scaffolding in this repository follows the same spirit as the projects it packages; add a `LICENSE` file here if you redistribute the combined image.
