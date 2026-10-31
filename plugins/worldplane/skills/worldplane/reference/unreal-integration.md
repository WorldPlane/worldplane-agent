# Integrating WorldPlane into an Unreal game

How a studio's Unreal Engine 5.8 project takes part in WorldPlane: the plugins, the settings, the server target, the check, local runs, packaging and the arguments servers get. What game code needs is in [cross-server.md](cross-server.md); the plugin's classes and functions are in [unreal-api.md](unreal-api.md); log lines are in [troubleshooting.md](troubleshooting.md). Public docs: https://worldplane.net/docs/unreal.

## The model in one paragraph

A zone (one environment's world) is one map served by several dedicated-server processes. The zone's **coordinator** gives each server areas of the map; every player and NPC belongs to the server whose area it stands in. When it goes far enough past a border, the old server **hands it off**: the actor is destroyed there and spawned again on the new server with the same entity id and network handle, so clients keep the same object. Players connect to one address, the **gateway** (WorldPlane's fork of Epic's multi-server proxy), which joins every player to every server of the zone, so a handoff needs no reconnect. Near a border each server shows its neighbour's entities as **ghosts**: non-authoritative copies, so gameplay on one side sees and targets what is on the other. Replication is Iris only.

A server is part of a zone only when started with `-WPServerId=N` (`WorldPlane::IsZoneServer`). Without it (an ordinary dedicated server, a listen server, PIE, standalone) the plugin's zone features stay off, so a game can ship the plugin and still run plain servers.

## 1. Install the plugins

Subscribers download one zip with both plugins from the panel, or with `GET /v1/tenants/T/downloads/unreal-plugin` (see [api.md](api.md); 402 without a subscription). Copy the folders into the project's `Plugins/`, next to the `.uproject`:

```
MyGame/
  MyGame.uproject
  Plugins/
    WorldPlane/        WorldPlane.uplugin, Source/, Binaries/
    WorldPlaneGAS/     WorldPlaneGAS.uplugin, Source/   (only with the Gameplay Ability System)
  Source/
  Config/
```

Enable them in the `.uproject` (both plugins are in the Networking category and marked experimental):

```json
"Plugins": [
  { "Name": "WorldPlane", "Enabled": true },
  { "Name": "WorldPlaneGAS", "Enabled": true }
]
```

- `WorldPlane` (`Version` 1 in its `.uplugin`) has three runtime modules: **WorldPlaneCore** (settings, entities, coordinator, telemetry, placed actors, events), **WorldPlaneIris** (handoff, ghosts, owner calls, restore providers, the handle generator) and **WorldPlaneProxy** (the gateway, per-player relevancy). It enables the engine plugins `Iris`, `MultiServerReplication` and `OnlineSubsystemUtils` itself.
- `WorldPlaneGAS` is off by default (`EnabledByDefault: false`). It needs `WorldPlane` and `GameplayAbilities`, which it enables. Add it only if the game uses GAS.
- **The native library.** WorldPlaneIris loads `wp_runtime` from `Plugins/WorldPlane/Binaries/ThirdParty/WPRuntime/`: `Win64/wp_runtime.dll` (editors and Windows servers) and `Linux/x86_64-unknown-linux-gnu/libwp_runtime.so` (Linux servers). It is in the download and staged into packaged servers by itself; client targets build without it. If it is missing, a server or editor build stops with `WorldPlane: ... is missing.` Re-copy the plugin from the download rather than building anything.
- Regenerate project files and build the editor target once so the plugin modules compile with the project. (An agent should not start an Unreal build or the editor without the user's go-ahead: say what to build and let them run it.)

## 2. Module dependencies (`Build.cs`)

Add only the modules whose headers the game includes:

| Module | Headers a game uses from it |
|---|---|
| `WorldPlaneCore` | `WorldPlaneRuntime.h`, `WorldPlaneCore.h` (`LogWorldPlane`), `WorldPlaneTypes.h`, `WPSettings.h`, `WPEntityComponent.h`, `WPEventsComponent.h`, `WPSpawners.h`, `WPGhostComponent.h`, `WPGhostActor.h`, `WPInteractionGroups.h`, `WPTelemetrySubsystem.h`, `WPCoordinatorSubsystem.h`, `WPLocalPlayer.h` |
| `WorldPlaneIris` | `WPOwnerCalls.h` (`WP_RUN_ON_OWNER`, `WorldPlane::ForwardDamageToOwner`), `WPHandoffTypes.h` (`FWPPlayerHandoffHooks`, `FWPRestoreProvider`), `WPGhostSubsystem.h`, `WPTargetRef.h` |
| `WorldPlaneProxy` | `WPGatewayClients.h` (`WorldPlane::Relevancy`, `WorldPlane::Gateway`) |
| `WorldPlaneGAS` | `WPGameplayEffects.h` (`WorldPlane::GAS::ForwardToOwner`) |

```csharp
public MyGame(ReadOnlyTargetRules Target) : base(Target)
{
    PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "WorldPlaneCore", "WorldPlaneIris" });
    // Every module that declares replicated FFastArraySerializer properties, third-party plugins included:
    SetupIrisSupport(Target);
}
```

`worldplane check --fix` adds `SetupIrisSupport(Target)` to modules with fast arrays, and `WorldPlaneIris` to a module it gives the damage line to. WorldPlane's own minimal test game (the "sandbox", referred to in these references; studios don't have its source) depends on all three WorldPlane modules and calls `SetupIrisSupport`.

## 3. Engine config (`Config/DefaultEngine.ini`)

```ini
[ConsoleVariables]
net.Iris.UseIrisReplication=1
net.EnableSupportForNoPawnConnection=1
net.SubObjects.DefaultUseSubObjectReplicationList=1

[/Script/IrisCore.ObjectReplicationBridgeConfig]
NetRefHandleGeneratorClass=/Script/WorldPlaneIris.WPNetRefHandleGenerator

[/Script/Engine.Engine]
LocalPlayerClassName=/Script/WorldPlaneCore.WPLocalPlayer
```

| Setting | Why |
|---|---|
| `net.Iris.UseIrisReplication=1` | WorldPlane replicates through Iris; under legacy replication each server's objects clash in the gateway. `worldplane check` error. |
| `NetRefHandleGeneratorClass` | An entity must have the same network handle on every server, or clients see it respawn at each handoff. Error. |
| `net.EnableSupportForNoPawnConnection=1` | The gateway joins every server with every player, and only one server has the player's pawn. Error. |
| `net.SubObjects.DefaultUseSubObjectReplicationList=1` | Iris replicates subobjects through registered lists. Warning. |
| `LocalPlayerClassName` | On the gateway, each login it makes to a server gets the zone's session key and the client options listed in `ForwardedLoginOptions`. **`worldplane check` neither checks nor sets this one**; add it by hand. A game with its own `ULocalPlayer` subclass instead appends `WorldPlane::GetGatewayLoginOptions(World, GetCachedUniqueNetId())` to its `GetGameLoginOptions()`, as `UWPLocalPlayer` does. |

`worldplane check --fix` writes the first four (in `[ConsoleVariables]` and `[/Script/IrisCore.ObjectReplicationBridgeConfig]`), keeping the file's byte-order mark and line endings.

Single-server games often have `[/Script/Engine.GameSession] MaxPlayers` at the engine default of 16. Zone servers raise their game session's `MaxPlayers` to at least `ZoneMaxPlayers` (1000) themselves, because every player in the zone has a connection on every server.

## 4. Plugin settings (`Config/DefaultGame.ini`)

Project Settings → Plugins → WorldPlane (`UWPSettings`, saved under `[/Script/WorldPlaneCore.WPSettings]`). The defaults suit most games; change only what the game needs.

| Setting | Default | What it does |
|---|---|---|
| `Scope` | `local/sandbox/dev` | `tenant/project/environment` this server belongs to. A coordinator refuses a server of another scope, and the server exits. Hosted zones pass `-WPScope=`, which overrides it. Set it to the studio's own for local runs. |
| `Areas` | two areas split at X = 0 (servers 1 and 2) | Static split for zones run **without** a coordinator. With `-WPCoordinator=` the coordinator's areas are used. Game code reads areas with `WorldPlane::GetAreas()`, never this setting. |
| `EntityClasses` | `APawn`, `APlayerController`, `APlayerState` | Actors of these classes get a `UWPEntityComponent` (named `WPEntity`) on zone servers, so they move between servers as themselves. A class with its own entity component keeps it. Empty: the game adds every one itself. |
| `NonEntityClasses` | empty | Subclasses of the above that stay on the server that spawned them (a turret). The actor tag `WPNotEntity` does the same. |
| `PlayerHysteresis` / `NpcHysteresis` | 1000 cm / 500 cm | How far past a border a player / NPC goes before it is handed off. |
| `MinResidenceSeconds` | 3 s | How long an entity stays on a server it just reached before it can move on. |
| `PlacedSpawnerClasses` | empty | Placed actors that spawn replicated actors (creatures, props): each runs on one server of the zone, and on another when that one dies. The tag `WPSpawner` does the same. |
| `PlacedActorsKeptEverywhere` | empty | Placed replicated actors every server keeps (level managers, static scenery). The tag `WPKeepEverywhere` does the same. Other placed replicated actors are held by one server of the zone and dormant on the others; placed entities move as entities, under their level names. |
| `ZoneWideActorClasses` | empty | Placed replicated actors that aren't always relevant but belong to the zone (a manager): held by the GameState's server and moved with it, like every always-relevant placed fixture (a sky, weather). The tag `WPZoneWide` does the same. |
| `NotZoneWideActorClasses` | empty | Always-relevant placed actors held by their area's server instead, as other fixtures are: one players interact with. The tag `WPNotZoneWide` does the same. |
| `GameStateServerId` | 1 | Only without a coordinator: the one server whose GameState replicates. 0 lets every server replicate its own. With a coordinator, the coordinator names it. |
| `ZoneMaxPlayers` | 1000 | Zone servers raise `MaxPlayers` to at least this. |
| `ForwardedLoginOptions` | `token` | Client login options the gateway passes on to the server login it makes for that player (the game's own login token, say). |
| `bRequirePlayerToken` | false | WorldPlane player accounts: every join must carry a `token=` for this environment, checked by the coordinator. Off for games with their own accounts. |
| `GhostBandWidth` | 15000 cm | Entities this close to another server's area appear there as ghosts. |
| `GhostRateHz` / `GhostTimeoutSeconds` | 10 / 1 s | Ghost updates per second; a ghost without updates this long is removed. |
| `bRealClassGhosts` | true | Ghosts are non-authoritative copies of the entity's own class, so casts, interfaces and components work on them. |
| `GhostClass`, `StandInKinds` | none, empty | A game's own `AWPGhostActor` subclass to use instead, for the kinds listed (all when empty), e.g. `+StandInKinds=Player`. |
| `GhostPawnBlocking` | `Players` | Which ghosts block pawns' movement: `Players` (NPCs' ghosts overlap pawns, so two servers' NPCs never push against each other's late copies), `All` or `None`. Traces, sight and overlap queries find every ghost either way. |
| `OwnerFunctions` | empty | Functions whose calls through reflection on a ghost run on the entity's owner, by path: `+OwnerFunctions=/Script/MyGame.MyInteractable:Interact`. |
| `bForwardEngineCalls` | true | Blueprint `ApplyDamage`, `ApplyPointDamage`, `LaunchCharacter`, and the character movement component's `AddImpulse` and `AddForce` on a ghost run on its owner. |
| `RecentlyDepartedSeconds` | 5 s | Damage for an entity that just left this server is passed on to its new server. |
| `TelemetryRateHz` | 5 | Telemetry samples per second. |

Soft class entries take class paths: `/Script/MyGame.AMyCamp` is written `/Script/MyGame.MyCamp` (no `A` prefix); a Blueprint is `/Game/Path/BP_Camp.BP_Camp_C`. The sandbox's `DefaultGame.ini` sets only `+OwnerFunctions=/Script/WorldPlaneSandbox.WPSandboxInteractable:Interact`.

## 5. A dedicated server target

WorldPlane runs the Linux x86-64 dedicated server. Servers and the gateway run the same build. A dedicated server needs a C++ project and a source-built engine, as with any Unreal dedicated server, plus the Linux cross-compile toolchain (`LINUX_MULTIARCH_ROOT`). If `Source/` has no `*Server.Target.cs`, add one:

```csharp
using UnrealBuildTool;

public class MyGameServerTarget : TargetRules
{
    public MyGameServerTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Server;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("MyGame");
    }
}
```

Match the project's existing `Target.cs` files (their `DefaultBuildSettings`, `IncludeOrderVersion`, `ExtraModuleNames`) rather than this template when they exist.

## 6. `worldplane check`

```
worldplane check path/to/MyGame          # or path/to/MyGame.uproject
worldplane check path/to/MyGame --fix    # make the mechanical changes first, then report
worldplane check path/to/MyGame --json   # findings as JSON
```

It reads the `.uproject`, `Config/DefaultEngine.ini`, `Config/DefaultGame.ini` and every module's C++ (no editor, no build), and prints each finding with a file and line. It exits 1 when there are errors. It parses C++ by its shape, not with a compiler: it can miss things and, rarely, flag what is fine. Blueprints and levels are binary and are not read.

| Check | Severity | What it looks for | `--fix` |
|---|---|---|---|
| `config` | error (one warning) | The plugin in `Plugins/WorldPlane` or the `.uproject`, not disabled; the four `DefaultEngine.ini` settings | lists or enables the plugin; writes the settings |
| `iris-module` | error | A module with `FFastArraySerializer` whose `Build.cs` lacks `SetupIrisSupport` | adds `SetupIrisSupport(Target);` |
| `multicast` | warning | `NetMulticast` UFUNCTIONs: the gateway drops them from actors no player owns | no (needs a decision) |
| `relevancy` | warning, or note when the class also sets Iris filters | `IsNetRelevantFor` overrides, which Iris never calls | no |
| `players-nearby` | warning | A search for players near something through each PlayerController's pawn (with a distance check), which misses players on the next server; files that already call `WorldPlane::IsAnyPlayerNear` or `ForEachPlayerPawn` are skipped | no (use `IsAnyPlayerNear`) |
| `entity` | warning | Pawns, player controllers and PlayerStates the settings leave without a `UWPEntityComponent` (in `NonEntityClasses`, or missing from a changed `EntityClasses`) | no |
| `damage` | warning, or note | A pawn's `TakeDamage` without the forwarding line; a note per pawn without `TakeDamage` when the game deals Unreal damage from C++ | adds the line (or a `TakeDamage` with it), the `#include "WPOwnerCalls.h"` and the `WorldPlaneIris` dependency |
| `owner-function` | error, warning or note | `OwnerFunctions` entries that aren't `/Script/Module.Class:Function`, return a value, name no UFUNCTION in the project, or are reached only through reflection | no |

`--fix` leaves files that aren't UTF-8 alone (Unreal also writes UTF-16), with the reason, under "Not fixed".

## 7. Running a zone locally

**What works for a studio, from the code and the public CLI docs.** The `worldplane` binary has a `coordinator` command (documented on https://worldplane.net/docs/cli under Local tools). The plugin reads the same arguments locally as on hosted zones. So a local zone is: one coordinator, two or more servers, one gateway, clients connecting to the gateway. WorldPlane's own launcher script is not part of the download.

1. A zone file, `zone.toml` (coordinator units are **metres** on Unreal X/Y; the plugin's are centimetres):
   ```toml
   bind = "127.0.0.1:8090"

   [zone]
   scope = "local/mygame/dev"     # must equal each server's -WPScope (or the Scope setting)
   name = "main"
   min_x = -1000.0
   max_x = 1000.0
   min_y = -1000.0
   max_y = 1000.0

   [mesh]
   servers = 2                    # strips along x, west to east
   ```
   Every key is optional. Instead of `[mesh]`, `[[areas]]` blocks (`server`, `min_x`, `max_x`, `min_y`, `max_y`) draw areas by hand; with neither, the zone is split in half at its middle x.
2. `worldplane coordinator --config zone.toml` (it answers `ok` on `GET /v1/health`).
3. Each server, from the editor binary with the uncooked project or from a packaged server, with its own `-WPServerId`, game port and transport port, and one session key shared by all processes:
   ```
   UnrealEditor.exe C:\Path\MyGame\MyGame.uproject /Game/Maps/World -server -log -unattended -nosteam -port=7778 ^
     -WPServerId=1 -WPCoordinator=http://127.0.0.1:8090 -WPScope=local/mygame/dev -WPTransportPort=9101 -WPSessionKey=<any shared string>
   ```
   Server 2: `-port=7779 -WPServerId=2 -WPTransportPort=9102`, the rest the same. Without `-WPTransportPort` a server logs `WP_TRANSPORT not started (no -WPTransportPort); this server hands nothing off`.
4. The gateway, the same build:
   ```
   UnrealEditor.exe C:\Path\MyGame\MyGame.uproject /Game/Maps/World -server -log -unattended -nosteam -port=7777 ^
     -ini:Engine:[ConsoleVariables]:wp.proxy.Enabled=1 -WPCoordinator=http://127.0.0.1:8090 -WPScope=local/mygame/dev -WPSessionKey=<the same string>
   ```
5. Clients: `UnrealEditor.exe C:\Path\MyGame\MyGame.uproject 127.0.0.1:7777 -game -log` (add `?token=...` to the address when the game forwards a login token).

Without a coordinator, servers take their areas from the `Areas` setting and their peers from `-WPPeers=127.0.0.1:9101,127.0.0.1:9102`, and the gateway takes `-ProxyGameServers=127.0.0.1:7778,127.0.0.1:7779` instead of `-WPCoordinator`; only `GameStateServerId`'s server replicates its GameState then.

**Cautions.**
- Uncertain: this recipe is assembled from the plugin's argument parsing and WorldPlane's own launcher; WorldPlane does not document it for studios as a supported workflow. If something in it fails, report the log lines rather than guessing.
- Servers started from the editor binary are `WITH_EDITOR` builds, and some engine behaviour differs on a cooked server (for example, outside the editor an actor iterator also finds dormant placed spawners; see [cross-server.md](cross-server.md)). Confirm behaviour on a packaged Linux server in a `dev` environment before calling something done.
- These are long-running processes. From a shell, start them in the background or in their own windows; never pipe their output into `head` or `tail`, which keeps the pipe open and stalls.
- A single PIE session or one plain server exercises none of WorldPlane: without `-WPServerId` the plugin's zone features are off.

## 8. Packaging the Linux server

```
Engine\Build\BatchFiles\RunUAT.bat BuildCookRun -project="C:\Path\MyGame\MyGame.uproject" -noP4 ^
  -noclient -server -serverplatform=Linux -serverconfig=Development ^
  -build -cook -stage -pak -map=/Game/Maps/World ^
  -stagingdirectory="C:\Builds\MyGame" -unattended -utf8output
```

(or package Linux Server from the editor's Platforms menu). The staged server is `C:\Builds\MyGame\LinuxServer`, with `MyGameServer.sh` at its top. Zip the `LinuxServer` folder, then `worldplane build check MyGameLinuxServer.zip`. An archive is accepted when it has exactly one `<Name>Server.sh`; a `<Name>Server` x86-64 Linux executable under `Binaries/Linux`; the WorldPlane plugin at `Version` 1 or later, loose (`Plugins/WorldPlane/WorldPlane.uplugin`) or listed in the staging manifest `Manifest_UFSFiles_*.txt`; no files that look like secrets (`.env`, `*.pem`, `*.key`, `id_rsa*`, `id_ed25519*`); at most 20 GiB.

A new build's first start runs the server alone, with none of the environment's arguments, and it must keep running for a minute. A server that needs a token from its arguments must log that it is missing and keep running, or the build is rejected.

Packaging is a long Unreal build: tell the user the command and let them run it unless they ask the agent to.

## 9. Arguments servers get on WorldPlane

Studios don't start hosted servers; the coordinator does. Every zone server gets the map, then:

```
-log -unattended -nosteam -port={game_port} -WPServerId={index} -WPScope={tenant}/{project}/{env}
-WPCoordinator={coordinator} -WPTransportPort={transport_port} -WPSessionKey=...
```

The gateway gets the map and `-log -unattended -nosteam -port=7777 -ini:Engine:[ConsoleVariables]:wp.proxy.Enabled=1 -WPScope=... -WPCoordinator=... -WPSessionKey=...`. The environment's `extra_args` (`--server-arg`) follow on every server and the gateway, with placeholders `{index}`, `{role}` (`server` or `gateway`) and `{env:NAME}` for an environment secret. Read one in game code:

```cpp
FString Token;
FParse::Value(FCommandLine::Get(), TEXT("ApiToken="), Token);
```

| Plugin argument | Meaning |
|---|---|
| `-WPServerId=N` | This zone server's id; makes the process a zone server. |
| `-WPCoordinator=URL` | The zone's coordinator: the server registers there before its first world has actors, and takes its areas and entity ids from it. A server that can't register within `-WPCoordinatorWait=` seconds (default 30) exits. |
| `-WPScope=t/p/e` | Overrides the `Scope` setting. |
| `-WPTransportPort=N` | The port servers use to talk to each other (handoffs, ghosts, forwarded calls). |
| `-WPSessionKey=KEY` | The zone's shared key; servers accept the gateway's own connection only with it. |
| `wp.proxy.Enabled=1` | Makes the process a gateway. |
| `-WPPeers=host:port,...` | Only without a coordinator: the other servers' transport addresses. |

## 10. Push and deploy

Once the build checks out, upload and deploy with the account workflows in [../SKILL.md](../SKILL.md): "Upload a build" and "Deploy, roll back" (confirm with the user first; both cost money or affect players). Secrets the servers need: "Secrets" there.
