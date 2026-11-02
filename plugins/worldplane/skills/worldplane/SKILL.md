---
name: worldplane
description: Integrate WorldPlane into a studio Unreal Engine 5.8 game, upgrade its plugins/CLI/skill, or operate its hosted zones. Covers WorldPlane and WorldPlaneGAS installation, Iris/config/server targets, worldplane check, cross-server handoffs and ghosts, authority and persistence, RPCs/GAS effects, spawning and GameState, local runs, server packaging and WP_ log diagnosis. Use for game integration, border bugs, check findings and plugin upgrades. Also manage tenants, projects, environments, builds, deploys/rollbacks, stop/wake, secrets, members/API keys, status, usage/spend and audit through WorldPlane MCP, CLI or HTTP API at app.worldplane.net.
---

# WorldPlane

WorldPlane hosts a studio's Unreal Engine 5.8 game servers as zones: several dedicated servers share one seamless world, players and NPCs are handed between them at area borders, and players connect through one gateway. Its control plane is at **https://app.worldplane.net**: the panel (web UI) and the HTTP API (`/v1/...`) share that origin. The `worldplane` CLI calls the same API, and WorldPlane's MCP server (`https://app.worldplane.net/mcp`, which this plugin adds) wraps it in tools.

This skill covers two jobs:
- **Integrating a game** with the Unreal plugins: start at [Integrate a game](#integrate-a-game-unreal) below.
- **Running the account** (projects, environments, builds, deploys): everything from [Rules](#rules) on.

The model: a **tenant** (the studio) has **projects** (games); a project has **builds** (uploaded server packages) and **environments** (`dev`, `test`, `prod`...). Each environment runs one **zone**: its own coordinator, servers, gateway and budget. Slugs are 2 to 18 lowercase letters, digits or `-`, starting with a letter, and never change.

The full endpoint list, with bodies, answers and errors, is in [reference/api.md](reference/api.md). Read it before calling an endpoint this file does not show.

## Integrate a game (Unreal)

The plugin does the work: most single-server game code runs across servers unchanged, and a few patterns that only hold on one server need a small change. Never use another game's integration as the template; work from the studio's own code and these references:

| Read | For |
|---|---|
| [reference/unreal-integration.md](reference/unreal-integration.md) | installing the plugins, `Build.cs`, `DefaultEngine.ini`, the plugin settings, the server target, `worldplane check`, running a zone locally, packaging, server arguments |
| [reference/cross-server.md](reference/cross-server.md) | what game code needs: authority and the gateway, handoffs and what survives them, calls and damage on another server's entity, GAS, spawning, GameState and world-wide state, persistence, multicasts, relevancy, what is unsupported |
| [reference/unreal-api.md](reference/unreal-api.md) | the plugin's classes, functions, settings, delegates and Blueprint nodes, with signatures and short examples |
| [reference/troubleshooting.md](reference/troubleshooting.md) | the plugin's `WP_` log lines and what to do about each |
| [reference/upgrade.md](reference/upgrade.md) | upgrading this skill, the CLI and a project's plugins to the latest versions |

The plugin includes a prebuilt native runtime. Update its source adapter and libraries together; do not rebuild Rust, restore internal tests, or add replacement connection/handoff policy in game code. Distributed source intentionally omits non-legal comments, including header documentation; use the published API reference and explicit editor tooltips. Tests, fixtures and internal debugging material are absent throughout the bundle. See the native-library contract in [unreal-integration.md](reference/unreal-integration.md).

### Rules for game code

The standalone **WorldPlane Multiplayer Diagnostics** editor tool and `worldplane check --profile unreal` are covered in [reference/diagnostics.md](reference/diagnostics.md). They share the offline Rust scanner and preview/apply repair engine. Public diagnostics work without an account or WorldPlane runtime; keep general Unreal and WorldPlane readiness profiles separate.

1. **Read before you change.** Find the `.uproject`, `Source/*/*.Build.cs`, the `*.Target.cs` files, `Config/DefaultEngine.ini` and `Config/DefaultGame.ini`, the GameMode, GameState, PlayerController, PlayerState, pawn and character classes, any ability system component, and where the game spawns actors, deals damage, saves, and calls `NetMulticast` RPCs. Say what you found before editing.
2. **Make the smallest change that works.** Prefer settings over code, and one line (`WP_RUN_ON_OWNER`, `ForwardDamageToOwner`, `ForwardToOwner`) over restructuring. Don't add entity components (WorldPlane adds them), don't reformat files, and don't touch gameplay that doesn't cross servers.
3. **Use only names that exist.** Every class, function, setting and log line in the references is in the plugin's public headers. If the game needs something they don't cover, say so; don't invent an API.
4. **Say what is uncertain.** Items marked Uncertain in the references are inferred, not documented: tell the user and suggest a test.
5. **Don't build or launch Unreal unless the user asks.** Builds, cooks and packaging take long and use the user's machine; give the command and let them run it. `worldplane check` is safe to run any time: it reads files only.
6. **The plugin comes from the studio's subscription.** If `Plugins/WorldPlane` is missing, ask the user to download it from the panel, or, with their go-ahead, fetch it with `GET /v1/tenants/T/downloads/unreal-plugin` ([reference/api.md](reference/api.md)). Never copy it from elsewhere.

### Workflow: integrate a game
1. **Survey** the project (rule 1). Note the engine version (WorldPlane is UE 5.8 only), whether it is a C++ project with a dedicated server target, whether it already uses Iris, and whether it uses GAS.
2. **Plugins:** `Plugins/WorldPlane` (and `Plugins/WorldPlaneGAS` only with GAS) present and enabled in the `.uproject`.
3. **`worldplane check <project> --fix`.** It lists or enables the plugin, writes the four `DefaultEngine.ini` settings, adds `SetupIrisSupport(Target)` where fast arrays need it, and adds the damage-forwarding line to pawns' `TakeDamage`. Show the user its "Fixed" and "Still to do" lists. Without the CLI, make the same changes by hand from [unreal-integration.md](reference/unreal-integration.md).
4. **By hand:** `LocalPlayerClassName=/Script/WorldPlaneCore.WPLocalPlayer` under `[/Script/Engine.Engine]` (the check doesn't set it); the `Scope` setting for local runs; module dependencies for the WorldPlane headers the game will include; a `*Server.Target.cs` if there is none.
5. **Game code**, for each remaining finding and each pattern in [cross-server.md](reference/cross-server.md) the survey found:
   - gameplay that must not run on the gateway: `WorldPlane::ShouldRunGameplay`;
   - `NetMulticast` on NPCs and world actors: `UWPEventsComponent` or replicated state;
   - `IsNetRelevantFor`: `WorldPlane::Relevancy::Update`;
   - functions that change another entity (interact, heal, use): `OwnerFunctions` or `WP_RUN_ON_OWNER`;
   - GAS: the `WorldPlane::GAS::ForwardToOwner` line in the ability system component;
   - state that must survive a crossing: `SaveGame`, or a restore provider for player systems;
   - spawning: gate by `WorldPlane::FindOwnerServer`, or placed spawners (`PlacedSpawnerClasses`);
   - GameState pointers and zone-wide state; login checks (`WorldPlane::IsTrustedGatewayLogin`, `ForwardedLoginOptions`).
6. **`worldplane check <project>` again** until it reports no errors, and explain any warnings left (some multicasts, for example, may be on player-owned actors and fine).
7. **Test:** a local zone of two servers and a gateway, then a `dev` environment with a packaged Linux build ([unreal-integration.md](reference/unreal-integration.md#7-running-a-zone-locally), [§8](reference/unreal-integration.md#8-packaging-the-linux-server)). Walk across a border, fight across it, and read the logs for the lines in [troubleshooting.md](reference/troubleshooting.md).
8. **Ship:** [Upload a build](#upload-a-build) and [Deploy, roll back](#deploy-roll-back) below, with the user's go-ahead.

For a narrower request ("make this actor work across servers"), read that actor and what calls it, then go straight to step 5 for it, and finish with step 6.

### Workflow: upgrade WorldPlane
For "upgrade WorldPlane", "update the plugin" or "are we on the latest version", follow [reference/upgrade.md](reference/upgrade.md): this skill first, then the CLI, then the project's plugins, with `worldplane check --fix` and the changelog's items after the plugins change.

## Rules

1. **Never print, log, echo or commit a token.** That includes session tokens, API keys (`wpk_...`) and secret values. Don't put them in a command line, a file in the repository, a URL or your reply. Don't `cat` the CLI's session file. Use the helper scripts or the CLI; they read the token themselves.
2. **Ask the user first, and wait for a yes, before anything that costs money or affects players.** Name the exact tenant/project/environment and build. This covers:
   - deploying, redeploying or rolling back (servers start and are billed; players on a running zone are disconnected);
   - stopping a zone (players are disconnected);
   - waking a sleeping zone (servers start and are billed);
   - uploading a build;
   - creating an API key, adding or removing members, setting or deleting secrets, changing a budget or the spend limit;
   - changing an environment's zone settings.

   Reading things (status, builds, usage, audit) needs no confirmation.
3. **On a 402, stop.** Tell the user what the error says, usually that the tenant needs an active WorldPlane subscription. Owners and the billing role subscribe in the panel: https://app.worldplane.net, the tenant's billing ("Subscribe"). Don't retry, and don't try to subscribe for them. A 402 can also mean deploys are on hold for an unpaid invoice, or that the tenant's monthly spend limit is reached. Each needs the user in the panel's billing.
4. **Errors are sentences meant for people:** `{"error": "..."}`. Show the user the sentence. 403 means the caller's role does not allow it (see Roles below). 409 usually says what has to happen first.
5. **Never sign up, sign in, or type a password for the user.** That includes the MCP server's sign-in page in the browser: the user signs in there and chooses what you may do. If there is no sign-in at all, ask the user to connect the MCP server (below), run `worldplane login` themselves, or put an API key in `WORLDPLANE_KEY`.

## Authentication

**The MCP server signs in with OAuth.** This plugin adds the server `worldplane` at `https://app.worldplane.net/mcp`. Its tools appear once the user has signed in, once:
- **Claude Code:** `/mcp`, choose `worldplane` (`plugin:worldplane:worldplane`), Authenticate;
- **Codex:** `codex mcp login worldplane`, or Authenticate in `/mcp`.

A browser opens on WorldPlane's sign-in page. The user enters their password (and authenticator code), and picks what the agent may do (everything they can do except billing, deleting, keys and members; deploy and operate; develop; or read only) and, if they like, the one organisation or project it may touch. Never sign in for them. They can disconnect the agent in the panel at any time (home page, Connected agents). The tool `whoami` says who you act as and how far you may go; a tool's 403 means this sign-in doesn't allow it, so tell the user, who can sign in again with a wider choice. What you do is written to the audit log as `agent:<their e-mail> (<program>)`.

Without the MCP server, the API takes `Authorization: Bearer <secret>`. The secret is either:
- **a session token**, from `worldplane login`. It lasts 30 days and acts as the person, with their roles in every tenant they belong to;
- **an API key** (`wpk_...`). An owner or admin creates it in the panel or with `POST /v1/tenants/{tenant}/keys`. It has one role on one tenant, or on one project. It is shown once. A key cannot create tenants, and can never be an owner.

Where the CLI and the helper scripts find it, in this order:
1. `WORLDPLANE_KEY` (with `WORLDPLANE_URL`, such as `https://app.worldplane.net`). This is the usual setup for CI and agents. Despite the name, the CLI sends it as is, so a session token works here too.
2. The session `worldplane login` kept: `session.json` in `%APPDATA%\worldplane\` on Windows, `$XDG_CONFIG_HOME/worldplane/` or `~/.config/worldplane/` elsewhere, or `$WORLDPLANE_CONFIG_DIR/`. It holds `url`, `email` and `token`.

Check who you are with `GET /v1/me`. It returns the account (null for a key), `actor`, `grants` and `tenants`.

## How to call WorldPlane

**Prefer the MCP tools** when they are there (the `worldplane` server's tools, such as `whoami` and `list_projects`). They cover:

| Task | Tool |
|---|---|
| Who you are, what you may do | `whoami` |
| Tenants and projects; regions | `list_projects`; `list_regions` |
| Environments; a zone's status, gateway and players | `list_environments`; `get_zone_status` |
| A running zone's events and the plugin's warnings | `get_zone_events` |
| Builds | `list_builds`, `get_build` |
| Secrets (names only); set one | `list_secrets`; `set_secret` |
| Usage and spend; the audit log | `get_usage`; `get_audit_log` |
| A new environment | `create_environment` |
| Upload a build | `start_build_upload`, then a PUT outside the conversation, then `finish_build_upload` ([Upload a build](#upload-a-build)) |
| Deploy, roll back | `deploy`, `roll_back` |
| Stop, wake | `stop_zone`, `wake_zone` |

Errors come back as the API's sentence with its status, such as `... (402)`; the rules below apply to them as to the API's. The tools have nothing for members, API keys, billing or deleting: those stay with the user, in the panel. Rule 2 applies to the acting tools just as to the CLI: say what will happen and wait for a yes. Your client may ask the user too.

**Otherwise use the CLI** when `worldplane` is on the PATH (`worldplane --version`). If it isn't, the user can download it from the panel (Engine integrations, Command-line tool) or, with their go-ahead, you can fetch it with `GET /v1/downloads/cli/{windows|linux}` (x86-64, any signed-in account or key; `chmod +x` on Linux). It covers:

| Task | Command |
|---|---|
| Sign in (the user runs it; it asks for the password) | `worldplane login --url https://app.worldplane.net --email <email>` |
| Sign out | `worldplane logout` |
| Tenant | `worldplane tenant create <tenant> --name "<Name>"` |
| Project | `worldplane project create <tenant>/<project> --name "<Name>"` |
| Environment | `worldplane env create <t>/<p>/<env> --region <id> --map /Game/Maps/World [--min-servers 1] [--max-servers 4] [--size tiny|small|standard|plus|max]|plus\|max] [--half-size 1000] [--warm-servers 1] [--sleep-after <min>] [--budget <usd/h>] [--server-arg <arg>]...` |
| Change it | `worldplane env update <t>/<p>/<env> [same flags] [--name] [--no-sleep] [--no-budget]` |
| Secrets | `worldplane env secret set\|list\|delete <t>/<p>/<env> [NAME]` (the value comes from stdin or `--from-file`, never an argument) |
| Check a zip before upload | `worldplane build check LinuxServer.zip` |
| Upload a build, wait for its checks | `worldplane build push --project <t>/<p> --label <version> LinuxServer.zip` |
| Deploy | `worldplane deploy <t>/<p>/<env> <build id>` |

From Git Bash, set `MSYS_NO_PATHCONV=1` before passing `/Game/...` maps, or the shell rewrites them into Windows paths, which the API refuses.

**The CLI has no commands for status, listing, usage, audit, stop, members or keys. For these, without the MCP tools, and when the CLI is missing, use HTTP.** Use the helper script, which finds the URL and token as above and never prints the token:

```sh
# bash / zsh (needs curl)
scripts/wp-api.sh GET  /v1/tenants/mystudio/projects/mygame/environments/test
scripts/wp-api.sh POST /v1/tenants/mystudio/projects/mygame/environments/test/deploy '{"build":"<id>"}'
```
```powershell
# PowerShell 5.1 or 7
scripts/wp-api.ps1 GET  /v1/tenants/mystudio/usage
scripts/wp-api.ps1 POST /v1/tenants/mystudio/projects/mygame/environments/test/stop
```
Paths are relative to this skill's folder. Both print the response body and exit non-zero on an HTTP error, showing its status and `error`.

Without the scripts, plain curl works. Keep the token in the environment; never write it out:
```sh
curl -sS -H "Authorization: Bearer $WORLDPLANE_KEY" "$WORLDPLANE_URL/v1/me"
```
```powershell
Invoke-RestMethod -Uri "$env:WORLDPLANE_URL/v1/me" -Headers @{ Authorization = "Bearer $env:WORLDPLANE_KEY" }
```

## Workflows

Below, `T/P/E` is tenant/project/environment, and `$B` is `/v1/tenants/T/projects/P`.

### Find out where things stand
1. `GET /v1/me`: the tenants and roles you have.
2. `GET /v1/tenants/T`: the tenant and the projects you can read. `GET /v1/tenants/T/projects` lists only the projects.
3. `GET $B/environments`: each environment's `state` (`stopped`, `starting`, `running`, `sleeping`, `failed`), its `build`, region, budget and zone settings.
4. `GET $B/builds`: the builds, each with its `state` and `reason`.

### Set up a game
1. The tenant, if the studio has none: `worldplane tenant create` or `POST /v1/tenants {"slug","name"}`. This needs a signed-in person. The caller becomes its owner.
2. The project: `POST /v1/tenants/T/projects {"slug","name"}` (owner or admin).
3. `GET /v1/regions` for the region ids. Ask the user which region, and for the map's package path (`/Game/...`).
4. The environment: `worldplane env create ...` or `POST $B/environments` (body in the reference). Suggest a `max_per_hour` budget. For a dev or test zone that is idle most of the time, suggest `sleep_after_minutes`. `smoke` is not allowed as an environment name.

### Upload a build
1. Check the zip first: `worldplane build check LinuxServer.zip`. The zip is the packaged `LinuxServer` folder: one `<Name>Server.sh`, an x86-64 Linux server binary, the WorldPlane plugin, and no files that look like secrets.
2. **With the MCP tools** (up to 5 GiB), after the user's yes:
   1. `start_build_upload` with `tenant`, `project`, `label` and the zip's `size` in bytes. It registers the build and answers an `upload.url`, good for two hours.
   2. PUT the zip there yourself, outside the conversation: `curl --fail -T LinuxServer.zip "<upload.url>"` (`curl.exe` in PowerShell). The archive never goes through MCP. The URL is a permission for this one build: don't paste it anywhere else.
   3. `finish_build_upload`, then `get_build` every 10 seconds until the state is `ready`, `rejected` or `failed`.

   A zip over 5 GiB goes up with the CLI, as below.
3. Otherwise, confirm with the user, then `worldplane build push --project T/P --label <version> <zip>`. It waits through `checking` → (`imaging` → `starting` on hosted zones) → `ready`. It exits non-zero with the reason if the build is `rejected` or `failed`.
4. Without the CLI: `POST $B/builds {"label","kind":"archive"}`, then upload the archive (see Builds in the reference: on app.worldplane.net it goes to storage in parts), then poll `GET $B/builds/{id}` every few seconds until the state is no longer `uploading`, `checking`, `imaging` or `starting`.
5. `rejected` gives the reason in plain words, including the server's last log lines if it stopped during its first start. Relay it. `failed` (imaging, or no game node free) can be retried without another upload, after asking: `POST $B/builds/{id}/image`.

### Deploy, roll back
1. `GET $B/builds/{id}` must be `ready` (otherwise 409).
2. Tell the user what will happen ("deploy build X (label) to T/P/E; servers start and are billed; players on it now are disconnected") and wait for a yes.
3. The `deploy` tool, `worldplane deploy T/P/E <id>`, or `POST $B/environments/E/deploy {"build":"<id>"}`. The answer has the zone.
4. Rolling back is a deploy of an older `ready` build. The `roll_back` tool finds the one deployed before the current build by itself.
5. A 409 that names a missing secret means a server argument uses `{env:NAME}` and the environment has no `NAME`. Ask the user to set it (`worldplane env secret set T/P/E NAME`; the user types the value). Don't invent a value.

### Status, logs and players
- `GET $B/environments/E` returns `environment`, `zone` and `players`:
  - `zone.running`, and `zone.gateway` (`host:port` where players connect, once the gateway is up);
  - `zone.fleet.fleets[].members[]` with each server's state;
  - `players.accounts`: the number of WorldPlane player accounts.
- **There is no endpoint for raw server logs.** What there is:
  - a build's `reason` (a rejected first start includes its last log lines);
  - the zone's events through the coordinator relay: `GET $B/environments/E/coordinator/v1/history?since=0`. `events[]` has `kind` and `detail`. `fleet_member_failed` is a server or gateway that died and was replaced, with its exit code and summary;
  - `.../coordinator/v1/fleet` and `.../coordinator/v1/servers` for the zone's servers now;
  - the audit log (below).

  The relay answers 503 or 502 when the zone isn't running or its coordinator didn't answer.

### Stop, sleep and wake
- **Stop** (confirm first): `POST $B/environments/E/stop` → 204. The zone's servers stop and the state becomes `stopped`. A stopped zone comes back only by deploying again.
- **Sleep** is automatic. With `zone.sleep_after_minutes` set, a zone with no players for that long becomes `sleeping`: nothing runs or is metered, and the build stays.
- **Wake** (confirm first; it starts billed servers): `POST /v1/play/T/P/E/wake`. It needs no token. It answers 202 `{"state":"starting"}` until players can connect, then 200 `{"state":"running","gateway":"host:port"}`. Poll every 5 to 10 seconds. From cold it takes a few minutes. It answers 409 when the environment isn't deployed (stopped or failed): deploy instead. It answers 402 without a subscription.

### Usage, spend and the audit log
- `GET /v1/tenants/T/usage`: this month (since the 1st, UTC). `environments[]` gives `server_hours` and `usd` per environment, `usd` the total, plus `subscribed`, `subscription_status`, `active` (whether builds, deploys and wakes are allowed), `max_per_month` (the spend limit) and `billing`. Needs owner, admin or billing. Bigger servers count more: `plus` is 2 server-minutes a minute, `max` 4.
- `PUT /v1/tenants/T/spend-limit {"max_per_month": 500}` (or `null` for none). Confirm first. Once the month's spend reaches the limit, new deploys are refused (402); running zones keep running.
- `GET /v1/tenants/T/audit?limit=100&before=<seq>`: who did what, newest first. Owners and admins only.

### Secrets
Servers get an environment secret as `{env:NAME}` in their arguments, such as `--server-arg=-ApiToken={env:API_TOKEN}`. The value is set by the user: have them run `worldplane env secret set T/P/E NAME`, which asks for it unshown. Never ask for the value in chat, and never put it in a command. Listing (`worldplane env secret list`, `GET .../secrets`) shows names and times, never values. Changes take effect at the next deploy.

### Team and CI keys
- Members: `GET/POST /v1/tenants/T/members`, `DELETE /v1/tenants/T/members/{email}` (owner or admin; only owners grant or remove owners). Someone without an account is invited, and gets the role when they sign up.
- Keys: `POST /v1/tenants/T/keys {"name":"ci","role":"developer","project":"P"}` answers the secret once. Tell the user to store it in their CI's secret store right away. Don't display it in your reply unless they ask, and never write it to a file in the repository. `DELETE /v1/tenants/T/keys/{id}` revokes one.

## Roles

| Role | May |
|---|---|
| owner | everything, billing and other owners included |
| admin | members (not owners), keys, projects, environments, budgets, secrets, audit, reading usage; not payment or the spend limit |
| operator | upload, deploy and stop anywhere, read; secrets on `dev` and `test` |
| developer | upload, read; deploy, stop and set secrets on `dev` and `test` only |
| viewer | read |
| billing | usage, setting up payment and the spend limit |

A grant on one project covers only that project. Developers' `dev`/`test` rule goes by the environment's slug.

## More
- API reference: [reference/api.md](reference/api.md), and https://worldplane.net/docs/api.
- Game integration: [reference/unreal-integration.md](reference/unreal-integration.md), [reference/cross-server.md](reference/cross-server.md), [reference/unreal-api.md](reference/unreal-api.md), [reference/troubleshooting.md](reference/troubleshooting.md), and https://worldplane.net/docs/unreal.
- Errors say what to change. If one doesn't, it's a WorldPlane bug: suggest the user report what was sent and what came back.
