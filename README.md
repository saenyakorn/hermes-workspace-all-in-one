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
├── Dockerfile             # multi-stage build: agent source → webui image
├── entrypoint.sh          # boots gateway + dashboard + webui in one container
├── config.default.yaml    # seeded into ~/.hermes/config.yaml on first boot
├── railway.json           # Railway build/deploy config
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

### Messaging gateway environment variables

The bundled [`config.default.yaml`](config.default.yaml) pre-wires sensible Telegram and Discord settings; you only need to supply the bot token **and** the user allowlist. Both gateways are **deny-all by default** — without the allowed-users variable nobody can talk to the bot.

#### Telegram ([docs](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram))

| Variable                  | Required?                                    | Notes                                                                                                                                          |
| ------------------------- | -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `TELEGRAM_BOT_TOKEN`      | Yes                                          | From [@BotFather](https://t.me/BotFather) → `/newbot`.                                                                                         |
| `TELEGRAM_ALLOWED_USERS`  | Yes                                          | Comma-separated numeric user IDs from [@userinfobot](https://t.me/userinfobot). Without this, the bot ignores everyone.                        |
| `TELEGRAM_WEBHOOK_URL`    | Recommended on Railway                       | Public HTTPS URL (e.g. `https://your-service.up.railway.app/telegram`). Switches Telegram from polling to webhook mode so the service can idle. |
| `TELEGRAM_WEBHOOK_SECRET` | **Required** when `TELEGRAM_WEBHOOK_URL` set | Run `openssl rand -hex 32`. Gateway refuses to start without it ([GHSA-3vpc-7q5r-276h](https://github.com/NousResearch/hermes-agent/security/advisories/GHSA-3vpc-7q5r-276h)). |
| `TELEGRAM_HOME_CHANNEL`   | No                                           | Chat ID for cron / proactive messages. DM chat ID = your user ID; group IDs are negative.                                                      |

Before adding the bot to a group, disable BotFather privacy mode (`/mybots → Bot Settings → Group Privacy → Turn off`) **and** remove/re-add the bot so the new privacy state takes effect.

#### Discord ([docs](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord))

| Variable                | Required?                                     | Notes                                                                                                                                  |
| ----------------------- | --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `DISCORD_BOT_TOKEN`     | Yes                                           | From <https://discord.com/developers/applications> → Bot → Reset Token.                                                                |
| `DISCORD_ALLOWED_USERS` | Yes (or `DISCORD_ALLOWED_ROLES`)              | Comma-separated user IDs. Right-click your name → Copy User ID (Developer Mode on). Without either of these, the gateway denies all users. |
| `DISCORD_ALLOWED_ROLES` | Alternative to `DISCORD_ALLOWED_USERS`        | Comma-separated role IDs — any member with one of these roles is authorized. Auto-enables the Server Members Intent.                   |
| `DISCORD_HOME_CHANNEL`  | No                                            | Channel ID for cron / proactive messages.                                                                                              |

In the Discord Developer Portal → Bot → Privileged Gateway Intents, you must enable **Message Content Intent** (otherwise the bot sees empty messages) and **Server Members Intent** (required if you use `DISCORD_ALLOWED_ROLES`). Use permissions integer `274878286912` when generating the invite URL.

#### Other platforms

| Variable          | Notes                                                                       |
| ----------------- | --------------------------------------------------------------------------- |
| `SLACK_BOT_TOKEN` | Optional — same flow for Slack. See upstream docs for the full env-var set. |

The gateway starts inside the container at boot; once a token + allowlist are set, the corresponding platform is live.

### Optional environment variables

| Variable                         | Default                     | Notes                                                       |
| -------------------------------- | --------------------------- | ----------------------------------------------------------- |
| `HERMES_WEBUI_DEFAULT_MODEL`     | `openai/gpt-5.4-mini`       | Default model the WebUI selects on first launch.            |
| `HERMES_WEBUI_DEFAULT_WORKSPACE` | `~/workspace`               | Default workspace path the WebUI opens.                     |
| `HERMES_HOME`                    | `/home/hermeswebui/.hermes` | Where state, sessions, skills, and config live.             |

---

## Default configuration

[`config.default.yaml`](config.default.yaml) is baked into the image at `/opt/hermes-defaults/config.yaml`. On first boot (when `~/.hermes/config.yaml` does not yet exist) [`entrypoint.sh`](entrypoint.sh) copies it to `${HERMES_HOME}/config.yaml`. On subsequent boots — and any boot where you've mounted a volume containing an existing `config.yaml` — the file is left alone.

The bundled defaults wire up:

- `model.provider: "auto"` — picks the first matching `*_API_KEY` env var.
- Telegram defaults: `require_mention: true`, `pretty_tables: true`, reactions off. Webhook mode is recommended on Railway (see env vars above).
- Discord defaults: `require_mention: true`, `auto_thread: true`, reactions on, safe `allow_mentions` (no `@everyone` / `@role` pings even if the model produces those tokens).
- `group_sessions_per_user: true` — Alice and Bob in the same room get isolated sessions.
- `session_reset` on either 24 h idle or daily 4 AM boundary — keeps Telegram / Discord context bounded.
- Curated `platform_toolsets` (`hermes-telegram`, `hermes-discord`) so the bot can run terminal, file, web, vision, image-gen, browser, skills, todo, and cron tools out of the box.
- Memory + skill auto-nudge intervals (10 and 15 turns).

To customize, either edit the file in your fork before redeploying (changes the seed) or edit `${HERMES_HOME}/config.yaml` directly via Hermes Control Center / SSH (changes the live config).

---

## State persistence

**Mount path: `/home/hermeswebui/.hermes`**

All Hermes state lives under `~/.hermes`, which maps to `/home/hermeswebui/.hermes` inside the container. A single Railway volume at this path persists everything across redeploys:

| Subpath                                  | What's in it                                          |
| ---------------------------------------- | ----------------------------------------------------- |
| `/home/hermeswebui/.hermes/config.yaml`  | Provider / model / profile config                     |
| `/home/hermeswebui/.hermes/.env`         | Credentials (provider API keys written by onboarding) |
| `/home/hermeswebui/.hermes/sessions/`    | Conversation history                                  |
| `/home/hermeswebui/.hermes/skills/`      | User-created and auto-learned skills                  |
| `/home/hermeswebui/.hermes/memory/`      | `MEMORY.md`, `USER.md`, agent notes                   |
| `/home/hermeswebui/.hermes/mcp/`         | MCP server registrations                              |
| `/home/hermeswebui/.hermes/hermes-agent/`| Symlink to the bundled agent source (`/opt/hermes`)   |
| `/home/hermeswebui/.hermes/webui/`       | WebUI state — settings, workspaces, last-session, projects |

### Add the volume

1. In Railway: **Settings → Volumes → Add Volume**.
2. **Mount path**: `/home/hermeswebui/.hermes`
3. **Size**: 1 GB is plenty for typical use; bump if you store large workspaces or many sessions.
4. Redeploy. The container picks up the volume on next boot.

> Without a volume, every redeploy starts from an empty state (you'll re-run onboarding and lose all sessions / skills / memory).

> The bundled agent source lives at `/opt/hermes` and is reinstalled on every build, so you do **not** need to put it on the volume — the `hermes-agent` symlink inside `~/.hermes` points to the image-baked copy.

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

1. Seeds `${HERMES_HOME}/config.yaml` from the bundled [`config.default.yaml`](config.default.yaml) on first boot only.
2. Starts `hermes gateway run` in the background on loopback `:8642`.
3. Waits up to 30 s for `:8642` to accept TCP connections (bash `/dev/tcp` probe — no `/health` round-trip required).
4. Starts `hermes dashboard --host 0.0.0.0 --insecure` in the background on `:9119`.
5. Execs the upstream WebUI startup (`/home/hermeswebui/docker_init.bash`), which finally runs `python server.py` on `:8787`.

SIGTERM/SIGINT received by PID 1 fans out to the gateway and dashboard children before the WebUI's own shutdown.

> Railway's healthcheck is intentionally left at TCP level (no `healthcheckPath` in [`railway.json`](railway.json)). The WebUI's `/health` endpoint exists but the WebUI's startup (auto-installing agent deps, recovering sessions, starting the gateway watcher) can exceed Railway's 30 s healthcheck window on a cold boot, which would cause unnecessary restart loops. TCP-level healthcheck against the container port is enough to detect a crash.

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
