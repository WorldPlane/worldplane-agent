# Game code across servers: what works unchanged, what needs care

WorldPlane's aim is that plain single-server game code works across servers, with the plugin doing the work. Most of a game needs no change. This page lists, from the plugin's code and docs, what holds as it is and the patterns that only hold on one server. Items marked **Uncertain** are inferred from the code and not documented or tested by WorldPlane: say so to the user, and confirm in a run rather than presenting them as fact.

The functions named here are in [unreal-api.md](unreal-api.md).

## Needs nothing

- **Entity identity.** Zone servers give every pawn, player controller and PlayerState a `UWPEntityComponent` as it spawns or loads (`EntityClasses`). A pawn is a player's while a player controls it, otherwise an NPC. Don't add entity components by hand.
- **Network handles** are deterministic (`WPNetRefHandleGenerator` in the config): a handed-off entity keeps its handle, so clients keep the same actor.
- **Moving players.** Pawn, PlayerController and PlayerState move together with their SaveGame properties, the replicated plain values the game's own classes declare on them and their components, movement mode and character movement timestamps. The plugin waits until the new server has the player's connection and the client acknowledged the pawn. The player stays connected.
- **Moving NPCs.** An NPC pawn moves with its SaveGame properties, the game's replicated plain values and velocity; the new server gives it its default AI controller (`AIControllerClass`) with the old controller's SaveGame properties (and its components').
- **Equipment classes.** The Blueprint classes of actors attached to or owned by a moving entity (a held weapon) are loaded on the new server before it arrives, and kept loaded a while, so equipment spawned from a soft class on arrival finds its class (`WP_HANDOFF_PRELOAD`).
- **Registering with the coordinator**, Agones health and ready signals on hosted zones: no code.
- **Plain references across a border.** An `AActor*` or `UObject*` in a client RPC or a replicated property naming another server's entity resolves, on the player's server, to its ghost there, and reaches clients as the real entity. Around each handoff of that entity (about 3 s) it still arrives as null: handle null as "not available right now".
- **Blueprint damage and movement on a ghost** (`ApplyDamage`, `ApplyPointDamage`, `LaunchCharacter`, `AddImpulse`, `AddForce`) run on the owner.
- **Unreal damage to non-pawn ghosts** goes to the owner with no code.
- **Owner-only state.** `COND_OwnerOnly` and `COND_SkipOwner` properties reach the right clients through the gateway, as on one server.
- **Ghosts look like the real class**, so casts, interfaces and component lookups on nearby entities from the next server work. Use `WorldPlane::IsGhost(Actor)` where the difference matters.

## Authority, and the gateway

- On a zone server, `HasAuthority()` is true only for entities this server owns. **Ghosts are not authorities** (`ROLE_SimulatedProxy`), so code already guarded by `HasAuthority()` skips them, as it would on a client.
- **The gateway runs the game's world too** (GameMode, `BeginPlay`, ticks) without simulating anything. Gate gameplay that spawns, damages or changes state with `WorldPlane::ShouldRunGameplay(GetWorld())`, not with `HasAuthority()` alone: the gateway is an authority for actors it spawns itself, such as its own GameMode. Skip local UI and input on the gateway (`WorldPlane::GetRole(World) == EWPRole::Proxy`).
- **Replication callbacks run on the gateway for every player.** The gateway is each player's owner connection to their server, so the game's `OnRep_`, fast-array `PostReplicatedAdd`/`PostReplicatedChange` and `PostNetReceive` run there with every player's state, in the order the server wrote each packet's objects (one actor with its subobjects at a time). A callback that dereferences another replicated object before that object's state has arrived (an equipment entry on the pawn naming an item on the PlayerState) crashes the gateway and disconnects everyone, where one client might crash alone or not at all; a `check` is no guard in Shipping. Null-check what another object should carry, fall back to what the entry itself replicates, or finish from that object's own `OnRep` ([troubleshooting](troubleshooting.md): the gateway dies when a player gains an item).
- An actor iterator on a server (`TActorIterator<APawn>`) also finds ghosts. Code that counts or targets "every pawn here" sees the neighbour's entities near the border: usually what gameplay wants (AI can target a player on the next server), but filter with `HasAuthority()` or `WorldPlane::IsGhost` for counts, saves and anything that must see each entity once in the zone.
- **Looking for players near something** by each PlayerController's pawn (`GetPlayerControllerIterator`, `GetPlayerPawn`, `GetAllActorsOfClass(APlayerController)` then `GetPawn()`) finds only this server's players. A player another server simulates has a no-pawn controller here, and their pawn is a ghost. Code that wakes, hibernates, spawns or aggroes for nearby players (spawner activation, creature sleep, ambient spawns) must ask `WorldPlane::IsAnyPlayerNear(World, Location, Radius)` instead, or `WorldPlane::ForEachPlayerPawn` for an actor to aim at. Otherwise creatures beside a player across the border sleep and never notice them, and a creature that chased a player over the line freezes there.

## Calls and writes on another server's entity

A function called on a ghost that changes the entity must run on the owner, or nothing happens there:
- guarded code (`if (!HasAuthority()) return;`) silently does nothing on the ghost;
- unguarded writes to replicated properties are overwritten by the owner's next update and logged as `WP_LOST_WRITE property=Class.Property ...`, once per property.

Fix each such function one of these ways, in order of preference:
1. Called from Blueprint, a `BlueprintNativeEvent`, an interface `Execute_`, or a dynamic delegate: list it, `+OwnerFunctions=/Script/MyGame.MyClass:Function`, no code change.
2. Called directly from C++: `WP_RUN_ON_OWNER(Params...)` as the first line of the `UFUNCTION`.
3. Not a function call (a struct of data): `WorldPlane::ForwardPayload` plus a handler registered with `WorldPlane::OnOwnerPayload`.

Forwarded functions must return `void`, not be static, and have no non-const reference or output parameters; Blueprint-only functions and events can't be listed (`WP_OWNER_FUNCTION ... it has no native code`): give them a native `UFUNCTION` with `WP_RUN_ON_OWNER`. Calls arrive in order with that server's other calls and damage for the entity, and are passed on if the entity moved.

## Damage

- **C++ damage to a pawn** needs the line at the top of the pawn's `TakeDamage` (`WorldPlane::ForwardDamageToOwner`; `worldplane check --fix` adds it). Each `TakeDamage` definition needs it on its own, even when a base class has it, if it calls `Super` and then changes the pawn.
- **Damage that is not Unreal damage** (a game's own health component called directly) is a call on another server's entity: give the function `WP_RUN_ON_OWNER`, or use `UWPGhostSubsystem::ForwardDamage` on the attacker's side and apply `UWPEntityComponent::OnRemoteDamage` on the owner, as the sandbox's `UWPHealthComponent` does.
- On the owner, forwarded Unreal damage arrives through `ApplyDamage` without the instigating controller (it is on the other server); `DamageCauser` is this server's actor or ghost for the attacker.
- Damage from a level actor every server loads (a pain volume, a trap) is dealt by the owner's own copy and is not sent again, so it isn't doubled.

## GAS

- With `WorldPlaneGAS`, one line at the top of the game's `ApplyGameplayEffectSpecToSelf` sends an effect applied to a copy to the owner, which rebuilds it from the instigator's ghost and applies it. The game needs its own `UAbilitySystemComponent` subclass for the override.
- **Ability system on the PlayerState:** a ghost is a copy of the pawn, and PlayerStates have no ghosts, so the copy has no ability system for effects to land on. The plugin's answer is a stand-in ghost class for players: `GhostClass` set to the game's `AWPGhostActor` subclass and `+StandInKinds=Player`, with whatever that class needs (its own ability system, attributes) filled from `FWPGhostHooks::DescribeAttributes`. A stand-in has no entity component, so `ForwardToOwner` returns false for it; the game handles effects on it itself. **Uncertain:** WorldPlane documents this setup but ships no example of it.
- **GAS state does not travel by itself.** Handoffs carry SaveGame properties and the game's replicated plain values; attribute values, active effects, granted abilities and cooldowns are the ability system's and are not carried. What grants abilities on the new server (an equipped weapon set, a stance) arrives if it is a plain replicated or SaveGame value, so the game's own code can grant from it again. Carry what the game needs with a restore provider (`FWPPlayerHandoffHooks::RegisterRestoreProvider`) for players. For NPCs there is no restore-provider hook; SaveGame properties and replicated plain values on the pawn, its components and its AI controller are what travel. **Uncertain:** how much GAS state a game must carry depends on the game; nothing in the plugin does it.

## Crossing borders: what the move does to an actor

Read this before trusting any state on an entity that moves. From `UWPHandoffSubsystem`:

1. The old server snapshots the actor: class, transform, velocity, the **SaveGame** properties of the actor and of each component that has any (components are matched by name), the **replicated plain values** the game's own classes declare on the actor and its components, an NPC's AI controller's SaveGame properties, and the classes of what it holds (ADR 0021).
2. It destroys the actor there (`Destroy()`, so `EndPlay` and `OnDestroyed` run on the old server) without logging the player out.
3. The new server loads the held classes, spawns a **new actor** of the same class (`SpawnActorDeferred`), restores the SaveGame properties before `FinishSpawning`, puts the replicated values on it as its entity component initializes (all components exist, none has begun play; no RepNotify), and then the actor's `BeginPlay` runs on the new server. An NPC's AI controller gets its SaveGame state as it spawns, before it possesses the pawn.

So:
- **What travels:** SaveGame properties (they win), and replicated properties that are plain values (bools, numbers, enums, names, strings, gameplay tags, vectors, and the game's structs and arrays of these) declared by the game's own classes (Blueprints, and C++ in the project's modules or its project plugins) on the actor or its components. They arrive as clients saw them: an active weapon set, a stance, a counter. `WP_HANDOFF_CARRY game packages=…` at server start lists the modules; `bHandoffCarriesReplicatedValues=False` turns it off.
- **What doesn't:** object references (a target, an item object), fast arrays (inventories), subobjects (attribute sets), and the engine's and engine plugins' own replicated state (an ability system's abilities and effects, a character's crouch). Mark such state `UPROPERTY(..., SaveGame)` where it is plain, or carry it in a restore provider (players). The sandbox NPC's patrol points and `AttackSeq` are SaveGame.
- **Time stamps:** a value holding a server's world time (`GetWorld()->GetTimeSeconds()`) means another instant on the next server. Stamp with `GetServerWorldTimeSeconds()`, the zone's clock.
- **A replicated "initialized" flag arrives set.** Keep one-time initialisation flags unreplicated, or SaveGame with the state they guard.
- **`BeginPlay` runs again on each server the actor reaches.** Initialisation that must happen once per life (rolling stats, granting starting items, full health) must check whether the state arrived already, as the sandbox health component does: `if (Health < 0.f) { Health = MaxHealth; }` with `Health` SaveGame and defaulting to -1.
- **`EndPlay`/`OnDestroyed` on the old server are not a death.** Code that drops loot, writes a save, decrements a population count or announces "left" there runs on every crossing. There is no public "being handed off" flag at that moment. **Uncertain** how best to tell: for spawned NPCs use the spawner functions below; for players, the game's persistence should stop writing after its `OnGather`/`CanHandOff` fence (the plugin's rule: the old server writes nothing after the handoff).
- **Timers, latent actions, delegates bound by other actors, and running AI** belong to the old actor and world: they are gone. The NPC's AI controller is destroyed with it, and the new server spawns a fresh default controller that has the old one's SaveGame properties (and its components') before it possesses the pawn; behaviour trees and StateTrees still start over and blackboards are empty. Keep what the brain must remember (fighting whom, going home, the leash anchor) as SaveGame on the controller or the pawn, and resume from it in `OnPossess` or `BeginPlay` (a "cooldown ends at" value as `GetServerWorldTimeSeconds()`, re-read as remaining time). State that isn't a property (a threat list of actors, an NPC's loose GAS tags) doesn't travel.
- **Actors the entity owns or has attached that are not entities themselves** (a weapon actor, a carried prop, a projectile) are not moved. **Uncertain** (from the code, not documented): they stay on the old server, and a SaveGame object reference to one does not find it on the new server. Prefer components, or spawning the weapon from SaveGame data in `BeginPlay`; their classes are loaded on the new server for that. For players, `CanHandOff` can hold the move while something is attached or in progress.
- **Components added at run time** are not on the new actor; their SaveGame state is dropped with `WP_HANDOFF <actor> has no component <name>; its state was dropped`.
- **Players: the new server doesn't run the GameMode's login path again.** It spawns the controller, PlayerState and pawn and calls the pawn's `PossessedBy`; it does not call `APlayerController::OnPossess` (that would restart the client's pawn), `PostLogin`, `RestartPlayer` or `HandleStartingNewPlayer`. Per-player setup that lives there must also run from `FWPPlayerHandoffHooks::OnApply` or a restore provider's `Apply`.
- **Uncertain:** a player has a connection on every zone server, held by an engine no-pawn controller (`ANoPawnPlayerController`) where the player doesn't play. Whether the game's `PostLogin` runs on those servers for that controller is engine behaviour WorldPlane does not document; guard per-player work there (loading a character from the backend) so it happens once, where the pawn is spawned.
- Ids: name players and entities by `WorldPlane::GetEntityId`, not `PlayerId` or `GetUniqueID()`.

## Player state and persistence

- The plugin has **no save system**. It carries state between servers (SaveGame properties, `OnGather`/`OnApply` blobs, restore providers) and keeps crash-recovery checkpoints in the coordinator, but anything that must outlive the zone belongs in the game's own backend.
- **The persistence fence.** A game that saves must make sure the old server writes nothing for a player after the handoff, or a late save overwrites the new server's. Refuse the move in `CanHandOff` while a save is in flight; flush in `OnGather`; write nothing after.
- **Restore providers** carry a system's player state in memory so the new server reads nothing from the backend. `Gather` also runs every `wp.CheckpointSeconds` (2 s) with `Context.bCheckpoint` set, for crash recovery: keep it cheap and free of side effects. `OnGather` is not called for checkpoints, so state only `OnGather` carries is lost when a server dies. `Apply` runs before the arriving actors first replicate and must not wait for anything. Use `OnFailed` to fall back to the backend.
- **Two builds at once** (a rolling deploy): raise `Version` when a raw provider's format changes, and keep `MinVersion` so the new build reads the old format. `ForStruct` providers tolerate added and removed properties without a new version.

## Spawning

- **Replicated actors are best spawned at run time by the server that owns their location.** Gate with `WorldPlane::FindOwnerServer(Location) == WorldPlane::GetLocalServerId()` (and `ShouldRunGameplay`), as the sandbox's GameMode does. Without the gate, every server spawns one.
- **Uncertain:** servers join a running hosted zone (the autoscaler, a replaced server) and run `BeginPlay` like any other. A GameMode that populates its area in `BeginPlay` would then spawn a second set where the joining server's area already has entities that walked or were handed in. For world population that must happen once per zone, use placed spawners.
- **Placed spawners** (a camp keeping its creatures topped up, or one placing props such as ore or rubbish): put the class in `PlacedSpawnerClasses` or tag it `WPSpawner`. One server of the zone runs it; the others keep a dormant copy that never begins play; when its server dies, the server whose area now holds it starts its copy (`BeginPlay` runs then, not at load). A placed actor that doesn't replicate and spawns a replicated actor or an entity with itself as the `Owner` is found the first time it does (`WP_UNLISTED_SPAWNER`) and treated the same from then on, its class too. The other servers' copies stop and their spawns are destroyed, but only after that first spawn, so list the class anyway. Tag an actor `WPNotSpawner` if every server must run it. Then:
  - spawn its entities with the spawner as their `Owner` (each then reports `UWPEntityComponent::GetSpawnerId`);
  - keep each entity's id beside its pointer (`WorldPlane::GetEntityId`). A creature handed to another server is destroyed here, but the plugin removes the spawner's own `OnDestroyed`/`OnEndPlay` bindings first, so the spawner isn't told; the pointer just goes null;
  - free a slot only when `WorldPlane::IsSpawnedEntityAlive(*this, Id, &Local)` says false; when it gives `Local`, the creature is back here: bind to it again;
  - in `BeginPlay`, count `WorldPlane::GetSpawnedEntities(*this)` (creatures an earlier copy made, alive anywhere) in the slots before spawning more;
  - a `SaveGame` reference from the creature to its spawner finds each server's copy, running or dormant.
- **Replicated actors placed in levels** exist once per zone:
  - a placed entity (an NPC) is loaded by the server whose area holds it and moves like any entity. Wherever it goes it keeps its level name and path, so a soft reference (`TSoftObjectPtr`) to it resolves on every server and client, and it keeps the level's per-instance settings (properties and components edited on the instance). Runtime state moves only where it is `SaveGame`. A hard `AActor*` from another level actor isn't retargeted: use a soft reference or the entity id;
  - any other placed replicated actor (a crafting station, a lamp, a quest marker) is held by one server of the zone and kept dormant on the others: no `BeginPlay`, no collision, no gameplay there. It never moves; when its server dies, the server whose area holds it takes it over with the level's values;
  - a zone-wide one (`bAlwaysRelevant`: a sky, weather, a zone's board) is held by the GameState's server instead, and moves with it; clients keep their actor across the move (ADR 0017). `ZoneWideActorClasses` (tag `WPZoneWide`) adds classes; `NotZoneWideActorClasses` (tag `WPNotZoneWide`) keeps an always-relevant one players interact with on its area's server. It must replicate at load: a sky that turns replication on in `BeginPlay` is sent by every server, and clients flip between them;
  - level managers and scenery that every server needs go in `PlacedActorsKeptEverywhere` or get the tag `WPKeepEverywhere`. Non-replicated placed actors are untouched.
- Actors that should never move (turrets, vehicles that stay in their area): `NonEntityClasses` or the tag `WPNotEntity`.
- Keeping several actors on one server while they interact (a trade, a grapple, a mount): `UWPInteractionGroups::BeginInteraction` / `EndInteraction`.

## World-wide state: GameState, GameMode, singletons

- **Every server has its own GameMode, GameState, world subsystems and game instance.** Nothing in them is shared across servers.
- **Only one server's GameState replicates** (`WorldPlane::GetGameStateServer()`): with a coordinator, a live server it names, which changes when that server stops. When it moves, clients receive a new GameState actor, its `OnRep` handlers run again with the new server's values, and for up to `wp.proxy.ReclaimTimeoutSeconds` (10 s) clients briefly hold both.
- **Look the GameState up each time** (`GetWorld()->GetGameState()`); a pointer kept from `BeginPlay` points at a destroyed actor after a move.
- **Zone-wide state** (match phase, scores, weather, a world boss's timer) kept in the GameState, the GameMode or a subsystem must be the same on every server, or live elsewhere: the game's backend, or a replicated actor every server keeps (`PlacedActorsKeptEverywhere`). **Uncertain:** WorldPlane has no zone-wide shared-state service; keeping such values equal across servers is the game's job.
- `GetServerWorldTimeSeconds` follows the replicating server's clock, so it jumps once when the GameState moves. Use it for client display, not for timestamps that must compare across servers.
- `PlayerArray` on a client is complete after a move (the new GameState gathers the client's PlayerStates).

## Clients and cosmetics

- **No NetMulticast from actors without an owning player.** The gateway drops them. Use replicated state, or `UWPEventsComponent::Emit` / `OnEvent` for one-off cosmetic events (last 8 kept). `worldplane check` lists every `NetMulticast`. Multicasts on actors a player owns (their pawn) are not dropped by that rule. **Uncertain** whether they reach other clients behind the gateway the same as on one server; prefer events or replicated state there too.
- **No `IsNetRelevantFor`.** Iris never calls it. Per-player relevancy (phasing, stealth, private instances) goes through `WorldPlane::Relevancy::Update`, called on servers and the gateway alike, again whenever the answer changes. Use entity ids in the rule.
- Client RPCs reach the player's current server only, as on one server.

## Unsupported or limited

- Legacy (non-Iris) replication.
- `NetMulticast` RPCs from actors no player owns (by design).
- `IsNetRelevantFor` (Iris).
- A sub-object registered with `COND_SkipOwner`, and a `COND_Dynamic` property set to `COND_SkipOwner` at run time, through the gateway (documented as not covered yet).
- Forwarded calls that return a value or have output parameters.
- References to another server's entity resolve as null for about 3 s around that entity's handoff.
- `wp_runtime` exists for Win64 and Linux x86-64 servers and editors only; hosted zones run Linux x86-64.
- **Uncertain / not covered by the code read for this skill:** seamless or server travel to another map within a zone, Shipping and Test server configurations, World Partition data layers, and mounts or vehicles carrying a player across a border. Test them on a `dev` environment before relying on them.

## Testing it

- `worldplane check` after each change; it exits 1 on errors.
- Local zone with two servers and a gateway ([unreal-integration.md](unreal-integration.md#7-running-a-zone-locally)), then a `dev` environment on a packaged Linux build, since editor-run servers hide some cooked-server behaviour (for example, outside the editor an actor iterator also finds dormant placed spawners).
- Walk a player and an NPC across a border, damage across it, use each changed function on an entity owned by the other server, and read the logs for `WP_LOST_WRITE`, `WP_RESTORE_FAILED`, `WP_HANDOFF` and `WP_OWNER_CALL_DROPPED` ([troubleshooting.md](troubleshooting.md)).
- Atlas (the panel's Open in Atlas on a running environment) shows each server's area and which server owns each entity.
