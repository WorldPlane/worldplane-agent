# Troubleshooting a WorldPlane game

The plugin logs under `LogWorldPlane`, every line starting with a `WP_` tag, so `grep WP_` in a server, gateway or client log shows WorldPlane's side. On a hosted zone there is no raw log endpoint: use the build's `reason` (a rejected first start includes its last log lines), the zone's events (`GET $B/environments/E/coordinator/v1/history?since=0`; for example `lost_write`, `damage_dropped`, `restore_failed`, `fleet_member_failed`) and the audit log ([../SKILL.md](../SKILL.md), "Status, logs and players"). Locally, read each process's log.

The `%s`/`%d` parts below are filled in at run time.

## Start with the zone's warnings

The plugin reports what it finds about the build (`WorldPlane::Warn`) to the coordinator, from every server and from the gateway (server 0). Read them before the logs: `GET $B/environments/E/coordinator/v1/warnings` lists one row per cause (`key` is `CODE Subject`, with `level`, `count`, `servers` and the latest `message`), errors first. The studio panel shows the same on the environment page. The codes and what to do are in `docs/game-integration.md`, "WorldPlane's warnings". The ones that explain the most:
- `SETUP`: a setting the zone needs is off.
- `FAST_ARRAY`: an inventory or list that looks empty on clients.
- `LOST_WRITE`: a change to another server's entity that didn't stick.
- `GATEWAY_STATE_WRITE`: game code on the gateway changed what it relays; the gateway puts the server's value back (ADR 0019), so look here when something on clients looked wrong before this was fixed.

## First lines to look for

| Line | Means |
|---|---|
| `WP_ROLE=<role> Server=<id> Iris=<0/1> Map=<map>` | Once per process at begin play. `Iris=0` means `net.Iris.UseIrisReplication` is off. Role `Backend` with `Server=0` is an ordinary server: WorldPlane's zone features are off without `-WPServerId`. |
| `WP_COORDINATOR registered server=<id> at <url> scope=<scope> ids=[a, b) generation=<n>` | The server joined its zone. |
| `WP_TRANSPORT server-<id> takes its peers from the coordinator` | Server-to-server links are coming from the coordinator. |
| `WP_GAMESTATE server <id> replicates its GameState` / `does not replicate its GameState; server <n> does` | Which server's GameState clients get. |
| `WP_PLACED level=... kept=... removed=... fixtures=... fixtures_parked=... spawners=... spawners_parked=...` | What this server kept of a level's placed entities, which placed replicated actors (fixtures) it holds or keeps dormant, and its spawners. |
| `WP_OWNER_FUNCTION <path>: calls on ghosts run on the entity's owner` | An `OwnerFunctions` entry took effect. |
| `WP_ENGINE_CALLS <n> engine functions called from Blueprint on ghosts run on the entity's owner` | `bForwardEngineCalls` took effect. |
| `WP_GATEWAY_LOGIN accepted gateway connection` | A server accepted the gateway's own connection (`IsTrustedGatewayLogin`). |

## Build and start

| Message | Cause and fix |
|---|---|
| `WorldPlane: <path> is missing. ...` (build error) | The `wp_runtime` library isn't in `Plugins/WorldPlane/Binaries/ThirdParty/WPRuntime/`. Copy the plugin again from the download; don't try to build the library. |
| `WP_RUNTIME cannot load <path>` / `WP_RUNTIME <path> has no <symbol>` / `WP_RUNTIME <path> is ABI version <n>; this plugin was built for <m>` | The library and the plugin's source come from different downloads. Replace the whole `Plugins/WorldPlane` folder with one download. |
| `WP_TRANSPORT cannot start without wp_runtime` / `WP_TRANSPORT this build has no wp_runtime: servers and editors on Win64 and Linux x86-64 have it` | No server-to-server transport, so no handoffs or ghosts: the process isn't a Win64 or Linux x86-64 server or editor, or the library failed to load (above). |
| `WP_TRANSPORT not started (no -WPTransportPort); this server hands nothing off` | Local run without `-WPTransportPort=N`. Hosted zones pass it. |
| `WP_TRANSPORT server-<id> has no coordinator and no -WPPeers: it only takes links other servers make` | Local run without `-WPCoordinator` or `-WPPeers`. |
| `WP_COORDINATOR waiting for <url>` then `WP_COORDINATOR server <id> could not register with <url>: <reason>. Exiting.` | The coordinator wasn't reachable within `-WPCoordinatorWait` (30 s), or refused the server. A refusal for another scope means `-WPScope` (or the `Scope` setting) doesn't match the coordinator's zone. |
| `WP_DECLARED_DEAD server <id>: ...; exiting` | The coordinator declared this server dead and other servers have rebuilt its entities, so it exits rather than duplicate them. Look earlier in its log for why the coordinator lost it (a long hitch, a breakpoint, lost connectivity). |
| `WP_GATEWAY no GameNetDriver definition to replace; the gateway is not enabled` | A process started with `wp.proxy.Enabled=1` found no `GameNetDriver` entry in the engine's `NetDriverDefinitions`. Check the project's engine config hasn't removed it. |
| `WP_GATEWAY both net.proxy.Enabled and wp.proxy.Enabled are set; the gateway runs WorldPlane's proxy` | Epic's proxy setting is also on; WorldPlane's wins. Drop `net.proxy.Enabled`. |
| `WP_PROXY_RPC_LIMIT net.Iris.ReplicationWriter.MaxUnsentOrderedUnreliableAttachmentAtEndOfTick is missing; ...` | The engine has no such Iris console variable, so client RPCs to servers are not bounded. The engine isn't the 5.8 the plugin expects. |
| Build `rejected` with a first start's last log lines | The server stopped by itself within its first minute, started alone and without the environment's arguments. A server that needs a token from its arguments must log that it's missing and keep running. |
| `worldplane build check` refuses the zip | Its message names the missing or forbidden item: one `<Name>Server.sh`, an x86-64 Linux `<Name>Server` under `Binaries/Linux`, the WorldPlane plugin at `Version` 1 or later (loose or in `Manifest_UFSFiles_*.txt`), no `.env`/`*.pem`/`*.key`/`id_rsa*`/`id_ed25519*`, at most 20 GiB. |

## Logins and the gateway

| Message | Cause and fix |
|---|---|
| `WP_GATEWAY_LOGIN refused: gateway login without the zone's session key` | A `?Proxy` login whose `WPProxyKey` doesn't match this server's `-WPSessionKey`. All servers and the gateway of a zone need the same key; locally, pass one string to every process. Also check `LocalPlayerClassName=/Script/WorldPlaneCore.WPLocalPlayer` (or the game's own local player appending `WorldPlane::GetGatewayLoginOptions`). |
| `WP_GATEWAY_JOIN_REFUSED server=<id> handshake=<n> reason="<reason>"; the gateway connection stays open` | The game's `PreLogin`, a full server or a failed spawn refused one player. Only that player is dropped. The reason is the game's own. If every player is refused, the game's login check probably needs `WorldPlane::IsTrustedGatewayLogin`, or the login token isn't listed in `ForwardedLoginOptions`. |
| `WP_PROXY_JOIN_REFUSED server=<id> ... reason=...` | The gateway side of the same refusal. |
| `WP_PROXY_ROUTES failed (<error>); keeping the current backends` | The gateway couldn't read its servers from the coordinator; it keeps the ones it has. |
| A client's controller has no player at login: `CreateWidget cannot be used on Player Controller with no attached player`, input and HUD missing, or a crash in game code that needs the local player (an input plugin's `check`) | The client received other controllers, and the last one took its player. Gateways on plugins 0.4.1 and 0.4.2 sent every client every controller, the gateway's own no-pawn ones included, and owner-only actors and components to everyone. Update the plugins to 0.4.3 or later and redeploy the server build (the gateway runs from it); clients need no change. To see it, run a client with `-ini:Engine:[Core.Log]:LogNet=Verbose`: each `<controller> setplayer <local player>` line is a controller it took. |
| Players see no camera or input after joining | A client begins play only when a replicated GameState says the server's has. Look for `WP_GAMESTATE` on the servers: none replicating (no coordinator answer yet, or without a coordinator `GameStateServerId`'s server is down) means no client begins play. |

## Handoffs and identity

| Message | Cause and fix |
|---|---|
| `WP_HANDOFF <actor> has no component <name>; its state was dropped` | The new actor lacks a component the old one had (added at run time, or named differently): its SaveGame state is lost. Create it in the constructor, with a stable name. |
| `WP_HANDOFF_RECV entity=<id> unknown class <path>` / `could not spawn <path>` | The receiving server can't load or spawn the entity's class: the servers run different builds, or the class isn't cooked into the server. |
| `WP_HANDOFF waiting for a link to server <n>` / `WP_HANDOFF no transport endpoint for server <n>` | The servers' transport isn't linked yet or at all; the entity waits on this server. Check `-WPTransportPort` and that servers can reach each other's transport ports. |
| `WP_PLAYER_HANDOFF entity=<id> cannot move to server <n>: endpoint=... connection=... controller entity=... playerstate entity=...` | A player can't move yet: no link, the target has no connection for the player, or the controller or PlayerState has no entity component (a 0 there: check `EntityClasses`/`NonEntityClasses`). |
| `WP_PLAYER_HANDOFF_RECV entity=<id> no connection with a no-pawn controller for player <id> ...` | The receiving server has no gateway connection for that player. Check `net.EnableSupportForNoPawnConnection=1`. |
| `WP_ADOPT_FAILED entity=<id> kind=... from=<n> could not spawn it` / `unreadable checkpoint (another build?)` | Crash recovery couldn't rebuild an entity of a server that died, usually during a deploy of a different build. |
| Clients see an entity vanish and reappear at each crossing | Handles aren't deterministic: `NetRefHandleGeneratorClass` is missing. `worldplane check` reports it. `WP_HANDLE_COLLISION <object> found no free entity serial; it gets a server-local handle` and `WP_HANDLE_GENERATOR ServerId <n> does not fit in <bits> bits; using Iris default handles.` are the generator's own failures. |
| State resets after a crossing | It isn't `SaveGame` and isn't a replicated plain value of the game's own class (an object reference, a fast array, an engine or GAS property, state on a subobject), `BeginPlay` re-initialised it, or (players) a restore provider failed: look for `WP_RESTORE_FAILED`. Check `WP_HANDOFF_CARRY game packages=…` at server start lists the module that declares it. See [cross-server.md](cross-server.md#crossing-borders-what-the-move-does-to-an-actor). |
| `WP_HANDOFF_CARRY game packages=<n> (<packages>)` | At server start: the modules whose replicated plain values handoffs carry (the project's and its project plugins'). `packages=0`: none travel; check the server finds its `.uproject`. |
| `WP_HANDOFF_PRELOAD entity=<id> classes=<n> loaded=<m> ms=<t>` | An arriving entity holds or owns actors of Blueprint classes this server hadn't loaded (a weapon); they were loaded before it arrived and stay loaded 10 minutes. A long `ms` is a hitch at the handoff. |
| An NPC that chased a player across a border stands frozen at the line, or forgets its fight | Its AI state wasn't SaveGame: the new server's controller gets only the old controller's SaveGame properties (and its components'). Keep "returning home", the leash anchor and its target's entity id as SaveGame, and make sure the game doesn't put an arriving NPC to sleep for want of players (next row). |
| Creatures near a border ignore a player standing just across it, or sleep with players next to them | The game looks for players by each PlayerController's pawn, which finds only this server's players. Use `WorldPlane::IsAnyPlayerNear` ([cross-server.md](cross-server.md#authority-and-the-gateway)). |
| One player counts as two in Atlas or the panel | A body the player left (a corpse after a respawn) counted as a player's. Fixed in the plugin since 2026-10-31: a pawn is a player's only while a player controls it, whatever entity component it has. |
| `WP_IDS out of leased entity ids; making ids locally until the coordinator answers` | The coordinator stopped answering for a whole lease of ids. Ids made meanwhile can repeat after a restart; find out why the coordinator didn't answer. |

## Restore providers

| Message | Cause and fix |
|---|---|
| `WP_RESTORE_SETUP provider=<name> refused: it needs a name, Gather, Apply and 1 <= MinVersion <= Version ...` | The provider is malformed and was not registered. |
| `WP_RESTORE_SETUP provider=<name> <problem>; it will never be restored` | It depends on a provider that isn't registered, or the dependencies form a cycle. |
| `WP_RESTORE_GATHER entity=<id> provider=<name> v=<n> sent nothing (Gather returned false / write error); the new server falls back` | Old server: `Gather` returned false or failed to write. |
| `WP_RESTORE_FAILED entity=<id> provider=<name> reason=<reason>: ...` (error, new server) | Not restored: `not_sent`, `version_mismatch` (outside `[MinVersion, Version]`), `apply_failed` (`Apply` returned false or read a different number of bytes than `Gather` wrote: state may be partly applied), `dependency_failed`, `scope_mismatch`. `(no fallback)` at the end means the provider has no `OnFailed`. |
| `WP_RESTORE_UNKNOWN entity=<id> provider=<name> ...: no provider here reads it; dropped` | The old server sent state no provider on this server reads: a provider missing from this build. |

## Ghosts, owner calls and damage

| Message | Cause and fix |
|---|---|
| `WP_LOST_WRITE property=<Class.Property> entity=<id> owner=<n>: game code on server <m> changed this copy of another server's entity, and the owner's update replaced the change. ...` | A function changed a ghost. List it in `OwnerFunctions` or begin it with `WP_RUN_ON_OWNER`. Reported once per property; `wp.Ghost.ReportLostWrites=0` silences it. |
| `WP_OWNER_FUNCTION <path> not found (OwnerFunctions)` | The entry names no function: check `/Script/Module.Class:Function` (class without its `A`/`U` prefix). `worldplane check` reports these too. |
| `WP_OWNER_FUNCTION <path> can't run on owners: <why>` | `it has no native code (a Blueprint function or event); use WP_RUN_ON_OWNER in a native one`, `it is static`, `it returns a value`, or `it has an output parameter`. |
| `WP_RUN_ON_OWNER in <Class>::<Function> runs on the ghost: <why>` | The macro couldn't forward: `it isn't a UFUNCTION`, `its arguments don't match its parameters; pass the function's own parameters, in order`, `it was given more arguments than it has parameters`, or one of the reasons above. Logged once per function. |
| `WP_OWNER_CALL_DROPPED entity=<id> function=<f> ...` | A forwarded call was given up: no transport to the owner, passed on too many times, the entity wasn't found, `no such object/function here` (builds differ), or `its parameters did not read`. |
| `WP_DAMAGE_DROPPED entity=<id> ...` | Forwarded damage was given up for the same kinds of reasons (no transport, too many hops, not here). |
| `WP_PAYLOAD_DROPPED entity=<id> kind=<k>: no handler here` / `it did not read` | A `ForwardPayload` kind has no `OnOwnerPayload` handler on the owner, or the struct differs between builds. |
| `WP_GAS_EFFECT_DROPPED entity=<id> effect=<e>: no ability system` / `no effect class` | The owner found no ability system on the entity's actor (an ability system on the PlayerState isn't found from the pawn) or the effect class didn't load. |
| `WorldPlane GhostClass <class> did not load; using AWPGhostActor` / `WP_GHOST class <path> did not load; a stand-in instead` | The configured ghost class, or the entity's own class, isn't loadable on this server. |
| `WP_GHOST_ALIAS entity=<id> has no Iris handle; references to it stay unresolved here` | References to that entity arrive as null on this server. |
| Damage from C++ to a player or NPC on the other server does nothing | The pawn's `TakeDamage` lacks `WorldPlane::ForwardDamageToOwner` (run `worldplane check --fix`). |
| An interaction works near its own server and fails across a border | The function runs on a ghost: see `WP_LOST_WRITE` and owner calls above. |

## Spawners and placed actors

| Message | Cause and fix |
|---|---|
| `WP_PLACED server <id>: the coordinator did not say which placed actors to keep (...); keeping all <n> in this server's area` | The coordinator didn't answer the claim; this server kept everything in its area, so duplicates are possible. |
| `WP_PLACED dormant spawner <name> began play with the world (no replication system held it back); removed` | A dormant spawner began play on a server that doesn't run it, and was removed so it doesn't run twice. |
| `WP_SPAWNER_TAKEOVER server=<id> ...` | A spawner's server died and this one took it over, or tried to. |
| `WP_UNLISTED_SPAWNER <spawner> spawned <class> with itself as the Owner, and its class is not in PlacedSpawnerClasses: ...` | A placed actor nothing named a spawner spawned a replicated actor or an entity. WorldPlane runs it once per zone from now on (its class too); other servers stopped their copies after that first spawn. Add the class to `PlacedSpawnerClasses` so copies are sorted before they spawn, or tag the actor `WPNotSpawner` if every server must run it. |
| `WP_SPAWNERS_FOUND server=<id> gateway=<0\|1> found=<n> stopped=<s> spawned_removed=<r> run=<k> claiming=<c>` | Spawners found as they spawned were sorted: `stopped` copies parked here (not this server's area, or the gateway), `spawned_removed` of their spawns destroyed, `run`/`claiming` kept here. `WP_SPAWNERS_FOUND_CLAIM` gives the coordinator's answer. |
| `WP_FIXTURE_SPAWNS fixture=<name> spawned=<class>` | A placed replicated actor spawns things. It is held once per zone already; what it spawned that is no entity goes with it when it moves. |
| `WP_SPAWNER_LOST server <id>: another server runs spawner <n> now; ...` | After a coordinator restart, another server holds the spawner; this copy stopped. |
| `WP_FIXTURE_TAKEOVER server=<id> asked=<n> started=<m>` | The server holding some placed replicated actors died; this one started its dormant copies of those in its area. |
| `WP_FIXTURE_LOST server <id>: another server holds fixture <n> now; stopped here` | After a coordinator restart, another server holds that placed actor; this copy stopped. |
| `WP_ZONE_WIDE_HOLD server=<id> holding=1\|0 named=<n> ...` | This server started or stopped holding the zone's zone-wide actors (always-relevant placed fixtures), following the GameState's server. |
| A sky, weather or zone-wide manager flips between two states on clients | Every server sends its own copy. Zone-wide actors come from the GameState's server only when they replicate at load and aren't kept everywhere: check `zone_wide=` in `WP_PLACED`. A sky that turns replication on in `BeginPlay`, or one in `PlacedActorsKeptEverywhere`, is sent by every server. |
| `WP_PLACED_NAME entity=<id>: <name> is held by a live object here, so it arrives under a new name` | A placed NPC arrived where something else holds its level name, so soft references to it miss on this server. Nothing should spawn actors under placed actors' names. |
| Twice the expected NPCs, or more with more servers | Spawning isn't gated by area (`WorldPlane::FindOwnerServer`): a GameMode or other spawned actor spawning in `BeginPlay` on every server. Placed actors that spawn are found (`WP_UNLISTED_SPAWNER`) unless they replicate, are kept everywhere, are tagged `WPNotSpawner`, or set the `Owner` only after spawning; list those in `PlacedSpawnerClasses` or tag them `WPSpawner`. |
| A level manager or other placed replicated actor is missing, or doesn't respond, on some servers | Placed replicated actors are held by one server of the zone and dormant on the others. Add the class to `PlacedActorsKeptEverywhere` or tag it `WPKeepEverywhere` if every server needs it. |

## Clients

| Symptom | Cause and fix |
|---|---|
| A NetMulticast never arrives behind the gateway | Dropped by design for actors no player owns. Use `UWPEventsComponent` or replicated state. |
| Per-player visibility ignored | `IsNetRelevantFor` isn't called under Iris: use `WorldPlane::Relevancy::Update`. |
| `WP_MOVE_CORRECTIONS corrections=<n> seconds=<s> fps=<f> pawn=<name>` (client warning) | The server corrected the player's own character 5 or more times in 10 s: their movement looks jerky to them and smooth to others. With a low `fps` (30 when the window is in the background), suspect the client's frame pacing; otherwise a speed or collision difference between client and server (a movement mode or speed set on one side only), or moves lost on the way. Run the client with `p.NetShowCorrections 1` to see them. |
| `WP_GATEWAY_SKIPOWNER mixed: <address> is connected straight to a server with a gateway, ...` | A client joined a server directly while a gateway is also connected; that client also receives its own `COND_SkipOwner` state. Connect clients through the gateway. |

If a message isn't listed here, quote it to the user with the surrounding lines; don't guess at its meaning.
