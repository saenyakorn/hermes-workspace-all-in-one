# Hermes All-in-One — Railway Template

Single-container Railway template that bundles [Hermes Agent](https://github.com/NousResearch/hermes-agent) (gateway + dashboard) and [Hermes WebUI](https://github.com/nesquena/hermes-webui) into one image, built from one `Dockerfile`.

| Port | Service                | Exposure         |
| ---- | ---------------------- | ---------------- |
| 8787 | Hermes WebUI (browser) | Public (primary) |
| 9119 | Hermes Dashboard       | Public (secondary, generate domain manually) |
| 8642 | Hermes Gateway API     | Internal only    |

> The WebUI imports the agent as a Python package in-process, so a single container is the correct topology on Railway (Railway services can't share Docker volumes the way the upstream `docker-compose.three-container.yml` does).

---

## Repo layout

```
.
├── Dockerfile          # multi-stage build: agent source → webui image
├── entrypoint.sh       # boots gateway + dashboard + webui in one container
├── railway.json        # Railway build/deploy config
├── .dockerignore
└── README.md
```

---

## Deploy on Railway

1. Fork (or import) this repo on GitHub.
2. In Railway: **New Project → Deploy from GitHub** → pick the fork.
3. Railway reads [`railway.json`](railway.json), builds the [`Dockerfile`](Dockerfile), and starts the service.
4. Go to **Settings → Networking** and generate **two public domains**:
   - Domain #1 → target port `8787` (Hermes WebUI — the main UI you log into)
   - Domain #2 → target port `9119` (Hermes Dashboard — monitoring + sessions)
5. Set the required env vars below under **Variables**, then redeploy.

### Required environment variables

| Variable                 | Required? | Notes                                                                                                  |
| ------------------------ | --------- | ------------------------------------------------------------------------------------------------------ |
| `HERMES_WEBUI_PASSWORD`  | Yes       | Hermes WebUI's fail-closed guard requires this whenever it binds non-loopback. Pick a strong value.    |
| `ANTHROPIC_API_KEY`      | At least one provider key | Anthropic Claude.                                                                       |
| `OPENAI_API_KEY`         |           | OpenAI / o-series.                                                                                     |
| `OPENROUTER_API_KEY`     |           | OpenRouter (200+ models, free tier available).                                                         |
| `GOOGLE_API_KEY`         |           | Gemini.                                                                                                |

### Optional environment variables

| Variable                         | Default                | Notes                                                       |
| -------------------------------- | ---------------------- | ----------------------------------------------------------- |
| `HERMES_WEBUI_DEFAULT_MODEL`     | `openai/gpt-5.4-mini`  | Default model the WebUI selects on first launch.            |
| `HERMES_WEBUI_DEFAULT_WORKSPACE` | `~/workspace`          | Default workspace path the WebUI opens.                     |
| `HERMES_HOME`                    | `/home/hermeswebui/.hermes` | Where state, sessions, skills, and config live.        |

---

## State persistence

All state — sessions, skills, memory, MCP config, credentials — lives under `~/.hermes`, which maps to `/home/hermeswebui/.hermes` inside the container. To survive redeploys:

1. In Railway: **Settings → Volumes → New Volume**.
2. Mount path: `/home/hermeswebui/.hermes`.

Without a volume, every redeploy starts from an empty state.

---

## Pinning versions

Both build args default to `latest`. Override them in **Settings → Build → Build Args** to pin a specific upstream tag for reproducible deploys:

| Build arg               | Default | Maps to                                            |
| ----------------------- | ------- | -------------------------------------------------- |
| `HERMES_AGENT_VERSION`  | `latest` | `nousresearch/hermes-agent:<tag>` on Docker Hub   |
| `HERMES_WEBUI_VERSION`  | `latest` | `ghcr.io/nesquena/hermes-webui:<tag>` on GHCR     |

Example pinned values: `HERMES_AGENT_VERSION=v0.13.0`, `HERMES_WEBUI_VERSION=v0.51.46`.

---

## Local build & run

```bash
# Build with defaults (latest of both)
docker build \
  --build-arg HERMES_AGENT_VERSION=latest \
  --build-arg HERMES_WEBUI_VERSION=latest \
  -t hermes-stack .

# Run locally — exposes both web (8787) and dashboard (9119)
docker run --rm \
  -p 8787:8787 \
  -p 9119:9119 \
  -e HERMES_WEBUI_PASSWORD=change-me \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -v "$HOME/.hermes-railway:/home/hermeswebui/.hermes" \
  hermes-stack
```

Open <http://localhost:8787> (WebUI) and <http://localhost:9119> (dashboard).

---

## How it works

```
┌──────────────────── Single container ────────────────────┐
│                                                          │
│  hermes gateway run     127.0.0.1:8642  (internal API)   │
│         ▲                                                │
│         │ in-process imports & health probe              │
│         │                                                │
│  hermes-webui  →→→→→→  0.0.0.0:8787    ← Railway public  │
│  hermes dashboard →→→  0.0.0.0:9119    ← Railway public  │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

[`entrypoint.sh`](entrypoint.sh):

1. Starts `hermes gateway run` in the background on loopback `:8642`.
2. Waits up to 30 s for `GET /health` to return `200`.
3. Starts `hermes dashboard --host 0.0.0.0 --insecure` in the background on `:9119`.
4. Execs the upstream WebUI startup (`/home/hermeswebui/docker_init.bash`), which finally runs `python server.py` on `:8787`.

SIGTERM/SIGINT received by PID 1 fans out to the gateway and dashboard children before the WebUI's own shutdown.

---

## Caveats

- `latest` upstream images shift without notice — **pin both build args before going to production**.
- One container = one restart blast radius. If the gateway crashes, the dashboard and WebUI lose their backing API surface; rely on the `ON_FAILURE` restart policy in [`railway.json`](railway.json) to recover.
- Railway services only auto-generate one public domain — manually generate the second one for port `9119` if you want browser access to the dashboard.
- The agent image's source layout (`/opt/hermes`) is fixed by the upstream `docker-compose.three-container.yml`; if a future release moves it, update the `COPY --from=agent` line in the [`Dockerfile`](Dockerfile).

---

## Upstream projects

- Hermes Agent — <https://github.com/NousResearch/hermes-agent>
- Hermes WebUI — <https://github.com/nesquena/hermes-webui>

Licensed MIT, matching both upstreams.
