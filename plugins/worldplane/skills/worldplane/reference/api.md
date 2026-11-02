# WorldPlane control plane API

Base URL: `https://app.worldplane.net`. JSON in and out. Authenticate with `Authorization: Bearer <session token or wpk_ API key>`; the panel uses the `wp_session` cookie instead.

**Errors** are `{"error": "<a sentence for people>"}` with:

| Status | Meaning |
|---|---|
| 400 | the request is wrong; the sentence says how |
| 401 | no or unknown token (`sign in, or send an API key`), or a wrong password or code |
| 402 | needs an active subscription, deploys are on hold for an unpaid invoice, or the spend limit is reached: the user sorts it out in the panel's billing |
| 403 | the caller's roles don't allow it (it is not said whether the tenant exists) |
| 404 | `no such <thing>`, or `the API has no /v1/...` for a path that doesn't exist |
| 409 | a conflict: exists already, wrong state, a missing secret... |
| 429 | too many wrong sign-ins for that e-mail; try again in the minutes given |
| 5xx | the control plane or a zone failed; the sentence says which |

Requests the server can't read are refused the same way: 400 for invalid JSON, 415 without `Content-Type: application/json`, 422 for a missing or mistyped field, 405 for a method a path doesn't take, 413 for a body over 2 MB.

"Role" below is the least that the call needs (see the roles in SKILL.md). `T`, `P`, `E` are the tenant, project and environment slugs. `$B` = `/v1/tenants/T/projects/P`.

## Accounts and sessions

| Method and path | Body | Answer |
|---|---|---|
| `GET /v1/health` | | `ok` (text) |
| `POST /v1/accounts` | `{"email","name","password"}` (password at least 10 characters) | `{"account":{"id","email","name"},"token"}` and the cookie. 403 if sign-up is closed, 409 if the e-mail has an account |
| `POST /v1/sessions` | `{"email","password","code"?}` (`code`: the 6-digit authenticator code, once one is set up) | as above. 401 when wrong or when the code is needed, 429 after 5 wrong tries (15 minutes) |
| `DELETE /v1/sessions/current` | | 204; ends the bearer's session and clears the cookie |
| `POST /v1/password-resets` | `{"email"}` | 202 `{"message"}`, the same whether or not the e-mail has an account; a link valid for an hour is mailed |
| `POST /v1/password-resets/confirm` | `{"token","password"}` | 204; ends every session of that account. 400 when the link expired |
| `GET /v1/me` | | `{"account"` (null for a key)`,"actor","grants":[{"tenant","project","role"}],"tenants":[...]}` |
| `POST /v1/me/totp` | | `{"secret","uri","next"}`: an authenticator setup, pending (people only, not keys) |
| `POST /v1/me/totp/confirm` | `{"code"}` | 204 |
| `POST /v1/me/totp/remove` | `{"code"}` | 204 |
| `GET /v1/regions` | | `{"regions":[{"id","name"}]}` (any signed-in caller) |

Sessions last 30 days. Agents should not call the sign-up, sign-in, reset or authenticator endpoints on a user's behalf: the user runs `worldplane login`.

## Tenants, members, keys, audit

| Method and path | Role | Body | Answer |
|---|---|---|---|
| `POST /v1/tenants` | a signed-in person (not a key) | `{"slug","name"}` | 201 `{"slug","name"}`; the caller is its owner. 400 for a bad or reserved slug, 409 if taken |
| `GET /v1/tenants/T` | viewer or billing | | `{"tenant":{"slug","name"},"projects":[{"tenant","slug","name"}]}` (projects the caller can read) |
| `GET /v1/tenants/T/members` | viewer | | `{"members":[{"email","name","role","project"}],"invited":[{"email","role","project"}]}` |
| `POST /v1/tenants/T/members` | admin (owner to grant `owner`) | `{"email","role","project"?}` | 201 granted, or 202 invited (no account yet; the role is theirs when they sign up). 404 for an unknown project |
| `DELETE /v1/tenants/T/members/{email}` | admin (owner to remove an owner) | | 204. 409 to remove the last owner |
| `GET /v1/tenants/T/keys` | admin | | `[{"id","tenant","name","prefix","role","project","created_at","revoked"}]` (never the secret) |
| `POST /v1/tenants/T/keys` | admin | `{"name","role","project"?}` (role not `owner`) | 201 `{"key":{...},"secret":"wpk_...","note":"shown once: store it now"}` |
| `DELETE /v1/tenants/T/keys/{id}` | admin | | 204 |
| `GET /v1/tenants/T/audit?before=<seq>&limit=<n>` | admin | | `{"records":[{"seq","at","tenant","actor","action","target","detail"}]}`, newest first; limit 100 by default, at most 1000 |

Roles: `owner`, `admin`, `operator`, `developer`, `viewer`, `billing`. Times are Unix seconds.

## Downloads

| Method and path | Role | Body | Answer |
|---|---|---|---|
| `GET /v1/downloads/cli/{windows\|linux}` | anyone signed in, or an API key | | the `worldplane` CLI binary for x86-64, saved as `worldplane.exe` or `worldplane` (`curl -fOJ`; `chmod +x` on Linux). 404 for another platform |
| `GET /v1/tenants/T/downloads/unreal-plugin` | any member, or an API key | | `application/zip` of the `WorldPlane` and `WorldPlaneGAS` plugins (save it with `curl -fOJ`). 402 without an active subscription; 404 if the control plane has no plugin to serve. Recorded in the audit log as `plugin.download` |

## Billing and usage

| Method and path | Role | Body | Answer |
|---|---|---|---|
| `GET /v1/tenants/T/usage` | billing, admin or owner | | `{"since","environments":[{"project","environment","server_hours","usd"}],"usd","billing","subscribed","subscription_status","checkout","plan","active","portal","max_per_month"}`. This month, since the 1st (UTC). `active` is whether builds, deploys and wakes are allowed |
| `PUT /v1/tenants/T/spend-limit` | billing or owner | `{"max_per_month": <usd> \| null}` | `{"max_per_month"}`. When the month's spend reaches it, deploys answer 402; running zones keep running |
| `POST /v1/tenants/T/billing/checkout` | billing or owner | | `{"url"}`: a Stripe Checkout page. Panel only: it needs the panel's `Origin` (400 otherwise). 409 if already subscribed |
| `POST /v1/tenants/T/billing/portal` | billing or owner | | `{"url"}`: Stripe's Customer Portal. Panel only, as above |
| `POST /v1/billing/stripe/webhook` | Stripe only | | not for clients |

Agents send users to the panel to subscribe rather than calling checkout.

## Projects and environments

| Method and path | Role | Body | Answer |
|---|---|---|---|
| `GET /v1/tenants/T/projects` | viewer | | `[{"tenant","slug","name"}]` (only those the caller can read) |
| `POST /v1/tenants/T/projects` | admin | `{"slug","name"}` | 201 project. 409 if it exists |
| `GET $B/environments` | viewer | | `[Environment]` |
| `POST $B/environments` | admin | `{"slug","name","region","max_per_hour"?,"zone":Zone}` | 201 Environment (state `stopped`). 400 for a bad slug, an unknown region, `smoke`, or a bad zone; 404 for an unknown project |
| `GET $B/environments/E` | viewer | | `{"environment":Environment,"zone":{...},"players":{"accounts","public_key","sign_up","sign_in"}}` |
| `PATCH $B/environments/E` | admin | any of `{"name","max_per_hour" (null removes it),"zone":Zone (whole)}`; other fields are refused | Environment. A running zone takes it at its next deploy; the region never changes |
| `POST $B/environments/E/deploy` | operator; developer on `dev`/`test` | `{"build":"<id>"}` | `{"zone":{...}}`, state `running`. 404 for an unknown environment or build; 409 if the build isn't `ready` or a `{env:NAME}` secret is missing; 402 for no subscription, an unpaid invoice or the spend limit; 500 `the zone did not start: ...` (state `failed`) |
| `POST $B/environments/E/stop` | operator; developer on `dev`/`test` | | 204, state `stopped` |

**Environment**: `{"tenant","project","slug","name","region","max_per_hour","zone":Zone,"build","state"}`. `state` is `stopped`, `starting`, `running`, `sleeping` or `failed`. `build` is the id it runs.

**Zone** (defaults in brackets):
```json
{
  "name": "main",
  "map": "/Game/Maps/World",
  "half_size_m": 1000,
  "extra_args": [],
  "min_servers": 1,
  "max_servers": 4,
  "server_capacity": 100,
  "server_size": "small",
  "warm_servers": 1,
  "sleep_after_minutes": null
}
```
- `map` is required. It is an Unreal package path that starts with `/` and has no `:` or `\`.
- 1 ≤ `min_servers` ≤ `max_servers`, and `half_size_m` > 0.
- `server_size` is `tiny` (1 vCPU, 2 GiB), `small` (2, 4 GiB; the default), `standard` (4, 8 GiB), `plus` (8, 16 GiB) or `max` (16, 32 GiB). `large` and `xlarge` are read as `small` and `standard`. Before 2026-10-31 the names were `standard` (1 vCPU), `plus` (2) and `max` (4); stored environments kept their resources under the new names.
- `extra_args` go to every server and the gateway. Placeholders: `{index}`, `{role}` (`server` or `gateway`), and `{env:NAME}` for an environment secret.
- `sleep_after_minutes`: the zone sleeps after that long with no players; null means it never sleeps.
- `max_per_hour` is the most, in USD an hour, that the zone may spend.

**`zone` in the environment's answer**: `running`, `gateway` (`host:port` once up), and `fleet`, with `fleets[].members[]` of `{name, state}` on hosted zones. Other fields vary by where zones run.

## Secrets

Answers never contain a value.

| Method and path | Role | Body | Answer |
|---|---|---|---|
| `GET $B/environments/E/secrets` | viewer | | `[{"name","updated"}]` |
| `PUT $B/environments/E/secrets/{NAME}` | admin; operator/developer on `dev`/`test` | `{"value":"..."}` (1 byte to 4 KiB, no NUL) | 201 new, or 200 replaced: `{"name","updated"}`. 400 for a bad name (1 to 64 of `A-Z 0-9 _`, starting with a letter) or one starting `WP_` |
| `DELETE $B/environments/E/secrets/{NAME}` | as PUT | | 204; 404 if there is none |

Changes reach servers at the next deploy (or when a sleeping zone wakes).

## Builds

| Method and path | Role | Body | Answer |
|---|---|---|---|
| `GET $B/builds` | viewer | | `[Build]` |
| `GET $B/builds/{id}` | viewer | | Build |
| `POST $B/builds` | developer | `{"label","kind":"archive"}` | 201 Build, state `uploading`. 402 without a subscription; 404 for an unknown project |
| `POST $B/builds/{id}/archive` | developer | the zip's bytes, `Content-Type: application/octet-stream` | Build, after its checks. 409 where the control plane takes uploads in parts, or if the build takes no upload |
| `POST $B/builds/{id}/uploads` | developer | `{"size": <bytes>}` (at most 20 GiB) | `{"part_size","parts":[{"number","url"}]}`: PUT each part's bytes to its `url` and keep the `ETag` response header. 409 where the control plane takes the archive itself (use `.../archive`) |
| `POST $B/builds/{id}/uploads/complete` | developer | `{"parts":[{"number","etag"}]}` | Build, after its checks. 409 if no upload is under way |
| `POST $B/builds/{id}/image` | developer | | Build: retries a `failed` build's imaging from the kept archive. 409 otherwise |

On app.worldplane.net, uploads go in parts (`.../uploads`, then `.../uploads/complete`). `worldplane build push` picks the right way by itself.

**Build**: `{"id","tenant","project","label","kind","state","reason","size","digest","program","uploaded_by","created_at"}`. `state` goes:

`uploading` → `checking` → (`imaging` → `starting`, where zones run images) → `ready`

or ends as `rejected` (with a plain `reason`, including a first start's last log lines) or `failed` (imaging or the first start could not run; retry with `.../image`).

## A zone's coordinator (read-only relay)

| Method and path | Role | Answer |
|---|---|---|
| `GET $B/environments/E/coordinator/v1/{path}` | viewer | the zone coordinator's own answer |
| `GET $B/environments/E/coordinator/v0/live` | viewer | a WebSocket: Atlas's live feed |

503 if the zone can't be reached, 502 if its coordinator didn't answer. Useful paths:
- `fleet`: `{provider, fleets, endpoints, error, players}`;
- `servers`;
- `zone`: the area map;
- `history?since=<seconds>`: `{now, events, metrics, snapshots}`. Events have `kind`, `detail`, `server` and `value`; for example, `fleet_member_failed` is a member that died and was replaced, with its exit summary in `detail` and, in `lines`, its last log lines (oldest first, as the provider read them before replacing it; the game's crash callstack when it crashed, since there is no log endpoint);
- `replay?from=&limit=`, `routes`, `entities/{id}`.

## Players (for the game's launcher or login service)

No studio token. These are per environment.

| Method and path | Body | Answer |
|---|---|---|
| `POST /v1/play/T/P/E/accounts` | `{"email","name","password"}` | `{"player":{"id","name"},"token","expires"}`: a player token valid for an hour |
| `POST /v1/play/T/P/E/sessions` | `{"email","password"}` | as above. 401 when wrong, 429 when locked out |
| `POST /v1/play/T/P/E/wake` | | 202 `{"state":"starting"}` while waking or not ready; 200 `{"state":"running","gateway":"host:port"}`; 409 if not deployed; 402 if a sleeping zone's tenant has no subscription; 404 for an unknown environment |

## Agents: OAuth and the MCP server

Agents sign in with OAuth 2.1 and act through `POST /mcp` (Streamable HTTP, JSON answers, MCP 2025-03-26 to 2026-07-28). Clients find everything from the 401 `/mcp` answers without a token; you don't call these yourself.

| Path | What |
|---|---|
| `GET /.well-known/oauth-protected-resource/mcp` | the resource (`https://app.worldplane.net/mcp`), its issuer and scopes (`admin`, `operator`, `developer`, `viewer`: the cap the user picks) |
| `GET /.well-known/oauth-authorization-server` | the endpoints: `/oauth/authorize`, `/oauth/token`, `/oauth/register`, `/oauth/revoke`; PKCE `S256`; client ID metadata documents and dynamic registration |
| `POST /mcp` | the tools (SKILL.md, How to call WorldPlane). Takes an OAuth access token, or an API key (`Authorization: Bearer wpk_...`), never a session token |
| `PUT /v1/uploads/{token}` | the upload link `start_build_upload` gives on a control plane without S3: one archive for one build, no other authorization. On app.worldplane.net the link is a presigned S3 URL instead |
| `GET /v1/me/agents`, `DELETE /v1/me/agents/{id}` | the person's connected agents, and disconnecting one (a signed-in person only) |

An agent's access token lasts an hour and works only at `/mcp`; the client refreshes it. What an agent does is in the audit log as `agent:<email> (<program>)`; `agent.connect` and `agent.disconnect` record the sign-ins themselves.
