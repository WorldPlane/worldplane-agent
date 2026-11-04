# The WorldPlane plugin's API for game code

What a game calls, binds or configures, by header. Signatures are copied from the plugin's public headers. Most games need only a few of these: start from [cross-server.md](cross-server.md), which says when each one is needed. Everything here is game thread unless it says otherwise. Examples credited to "the sandbox" are adapted from WorldPlane's own minimal test game; its source isn't part of the download, and the snippets stand on their own.

Module per header: see the table in [unreal-integration.md](unreal-integration.md#2-module-dependencies-buildcs). Log category: `LogWorldPlane` (`WorldPlaneCore.h`).

## Where am I running? (`WorldPlaneRuntime.h`, `WorldPlaneTypes.h`)

```cpp
enum class EWPRole : uint8 { Standalone, Client, Backend, Proxy };   // Proxy = the gateway

namespace WorldPlane
{
    EWPRole GetRole(const UWorld* World);
    bool ShouldRunGameplay(const UWorld* World);   // true on backends and standalone; never on the gateway or a client
    bool IsZoneServer(const UWorld* World);        // a backend started with -WPServerId=N
    int32 GetLocalServerId();                      // -WPServerId, 0 when absent
}
```

**The gateway runs the game's world too** (GameMode, BeginPlay, ticks) but simulates nothing: it only forwards the servers' actors. `HasAuthority()` is true there for the actors it spawns itself, such as its own GameMode. Gate server-side gameplay that spawns, damages or changes state with `ShouldRunGameplay`, as the sandbox does:

```cpp
void AMyGameMode::BeginPlay()
{
    Super::BeginPlay();
    // The gateway runs this GameMode too; only servers that simulate the world spawn NPCs.
    if (WorldPlane::ShouldRunGameplay(GetWorld()))
    {
        SpawnNpcs();
    }
}
```

UI and input setup that runs for local player controllers should skip the gateway: `if (WorldPlane::GetRole(GetWorld()) == EWPRole::Proxy) { return; }` (the sandbox's player controller does this in `BeginPlay` and `SetupInputComponent`).

## Areas and ids (`WorldPlaneRuntime.h`)

```cpp
namespace WorldPlane
{
    const TArray<FWPServerArea>& GetAreas();          // every server's areas (cm): the coordinator's, else the Areas setting
    int32 FindOwnerServer(const FVector& Location);   // the server whose area holds Location; 0 when none does
    uint64 AllocateEntityId();                        // a zone-unique id from the coordinator's lease
    int32 GetGameStateServer();                       // the server whose GameState replicates (see cross-server.md)
}
```

`FWPServerArea` has `ServerId`, `MinX`, `MaxX`, `MinY`, `MaxY` (cm, half-open), `Contains(Location)` and `DistanceTo(Location)`. Areas change while a hosted zone runs (load balancing, servers joining and leaving), so never cache them or hard-code borders.

Spawning only where this server owns the location (sandbox `AWorldPlaneSandboxGameMode::SpawnNpcs`):

```cpp
const int32 ServerId = WorldPlane::GetLocalServerId();
// A standalone world (server 0) spawns everything; a zone server only inside its own area.
if (ServerId != 0 && WorldPlane::FindOwnerServer(SpawnLocation) != ServerId)
{
    return;
}
GetWorld()->SpawnActor<AMyNpc>(SpawnLocation, FRotator::ZeroRotator, Params);
```

## Players nearby (`WPPlayers.h`)

```cpp
namespace WorldPlane
{
    // A player within Radius (cm, 3D): this server's players' pawns, players' ghosts, and players another server
    // simulates, at the view the gateway keeps for them here (any distance from the border).
    bool IsAnyPlayerNear(const UWorld& World, const FVector& Location, float Radius);

    // This server's players' pawns, and the ghosts of other servers' players' pawns near its borders (copies or stand-ins).
    void ForEachPlayerPawn(const UWorld& World, TFunctionRef<void(AActor& Pawn)> Visit);
}
```

Use these wherever code looks for players to wake, hibernate, spawn or aggro: a plain search through each PlayerController's pawn finds only this server's players. On a plain server they are the plain search.

```cpp
// A spawner that sleeps with no player near
const bool bAwake = WorldPlane::IsAnyPlayerNear(*GetWorld(), GetActorLocation(), ActivationRadius);
```

## Logging in through the gateway (`WorldPlaneRuntime.h`, `WPLocalPlayer.h`)

```cpp
namespace WorldPlane
{
    // Server side, in the game's PreLogin: true for the gateway's own connection (?Proxy with the zone's session key).
    bool IsTrustedGatewayLogin(const UWorld* World, const FString& Options);
    // Gateway side: the options to add to a login it makes (session key; forwarded client options for a player).
    // Client side (plugins 0.4.10): where the client's pawn last stood (WPReturn, WPReturnMap), for the gateway's admission.
    FString GetGatewayLoginOptions(const UWorld* World, const FUniqueNetIdRepl& PlayerId);
}
class UWPLocalPlayer : public ULocalPlayer { virtual FString GetGameLoginOptions() const override; };
```

A game whose `PreLogin` checks credentials admits the gateway's own connection without them:

```cpp
void AMyGameMode::PreLogin(const FString& Options, const FString& Address, const FUniqueNetIdRepl& UniqueId, FString& ErrorMessage)
{
    if (WorldPlane::IsTrustedGatewayLogin(GetWorld(), Options))
    {
        return;   // the gateway's connection; players still log in one by one with their own options
    }
    Super::PreLogin(Options, Address, UniqueId, ErrorMessage);
    // ... the game's own token check, reading the option named in ForwardedLoginOptions ...
}
```

With WorldPlane player accounts (`bRequirePlayerToken`), the coordinator checks `token=` on the first join, and the game reads the player from the login options `WPPlayer=` (stable id) and `WPPlayerName=` in `PreLogin`, `Login` or `PostLogin`. `UWPCoordinatorSubsystem::VerifyPlayerToken(Token, Done)` checks a token itself.

## Entities (`WPEntityComponent.h`, `WPEntitySubsystem.h`, `WPSpawners.h`)

`UWPEntityComponent` is an actor's WorldPlane identity: it lets the actor move between servers as itself. Zone servers add one, named `WPEntity`, to every actor of a class in `EntityClasses` (pawns, player controllers, PlayerStates) as it spawns or loads. **Games normally add none.** A class that creates its own (C++ or Blueprint) keeps it.

```cpp
class UWPEntityComponent : public UActorComponent
{
public:
    uint64 GetEntityId() const;
    int32 GetOwnerServerId() const;
    EWPEntityKind GetKind() const;               // Player, Npc, Controller, PlayerState
    uint64 GetSpawnerId() const;                 // the placed spawner that made it; 0 for none

    UPROPERTY(BlueprintReadWrite) float TelemetryHealth = 1.f;    // 0..1, shown in telemetry and Atlas, sent with ghosts
    UPROPERTY(BlueprintAssignable) FWPOnRemoteDamage OnRemoteDamage;
};
// (float Amount, const FString& DamageType, int64 InstigatorEntityId, int32 FromServer)
DECLARE_DYNAMIC_MULTICAST_DELEGATE_FourParams(FWPOnRemoteDamage, float, Amount, const FString&, DamageType, int64, InstigatorEntityId, int32, FromServer);

namespace WorldPlane { uint64 GetEntityId(const AActor* Actor); }   // 0 for an actor that is not an entity
```

Use entity ids, not `PlayerId`, to name players across servers: each server numbers its own players, and a handed-off player's `PlayerId` is 0 there.

`OnRemoteDamage` fires on the owning server when gameplay on another server damaged this entity's ghost through `UWPGhostSubsystem::ForwardDamage`. Apply it as local damage (sandbox `UWPHealthComponent::BeginPlay`):

```cpp
if (GetOwner()->HasAuthority())
{
    if (UWPEntityComponent* Entity = GetOwner()->FindComponentByClass<UWPEntityComponent>())
    {
        Entity->OnRemoteDamage.AddDynamic(this, &UMyHealthComponent::HandleRemoteDamage);
    }
}
```

Plain Unreal damage (`ApplyDamage`) on a ghost does not use this delegate: it arrives on the owner as ordinary `TakeDamage` / `OnTakeAnyDamage` (see Owner calls below).

## Ghosts (`WPGhostComponent.h`, `WPGhostActor.h`, `WPGhostSubsystem.h`)

```cpp
namespace WorldPlane
{
    bool IsGhost(const AActor* Actor);              // stands for an entity another server owns
    uint64 GetGhostEntityId(const AActor* Actor);
    int32 GetGhostOwnerServer(const AActor* Actor);
    double GetGhostLastUpdate(const AActor* Actor);
}
```

- By default a ghost is a copy of the entity's own class with a `UWPGhostComponent` (added by WorldPlane; games never add it): `HasAuthority()` false (`ROLE_SimulatedProxy`), no controller, position following the owner, replicated properties arriving about twice a second with their RepNotifies.
- Ghosts of the kinds `GhostPawnBlocking` leaves out (by default NPCs) don't block pawns: each primitive component that blocks the Pawn channel (or a custom object type the ghost's root uses) overlaps it instead, reapplied with every update. `WorldPlane::ApplyGhostCollision(Ghost, Kind)` is the rule; other responses stay the class's, so traces and overlap queries still find the ghost.
- With `GhostClass` set, the kinds in `StandInKinds` get the game's `AWPGhostActor` subclass instead: server-local, never replicated, no entity component, a capsule. `AWPGhostActor` has `GetEntityId()`, `GetOwnerServerId()`, `GetKind()`, `GetHealth()`, `GetAttribute(Key, Default)`, `GetAttributeText(Key)` and a virtual `ApplyState(const FWPGhostState&, int32 FromServer)`.
- `FWPGhostHooks` (owning server) adds game data to ghost updates: `FWPGhostHooks::Describe` (`FString(const AActor&)`, sent as `FWPGhostState::Profile`) and `FWPGhostHooks::DescribeAttributes` (`void(const AActor&, TArray<FWPGhostAttribute>&)`). Keep it small: it travels `GhostRateHz` times a second.

`UWPGhostSubsystem` (a world subsystem):

```cpp
bool ForwardDamage(const AActor* Target, float Amount, const AActor* Instigator, const FString& DamageType = FString());
AWPGhostActor* FindGhost(uint64 EntityId) const;     // a stand-in only
AActor* FindGhostActor(uint64 EntityId) const;       // either kind
```

`ForwardDamage` returns true when `Target` is a ghost and the damage went to its owner (raised there as `OnRemoteDamage`), false when the caller applies it locally.

## Owner calls (`WPOwnerCalls.h`)

A call that changes another server's entity must run on that entity's owner. Three ways, from no code to one line:

1. **Built in:** Unreal damage to a ghost that isn't a pawn; Blueprint `ApplyDamage`/`ApplyPointDamage` on any ghost; Blueprint `LaunchCharacter`, `AddImpulse`, `AddForce` (`bForwardEngineCalls`).
2. **Config:** `+OwnerFunctions=/Script/MyGame.MyInteractable:Interact` forwards calls that go through reflection: Blueprint, `BlueprintNativeEvent` called from C++, interface `Execute_` calls, dynamic delegates. A direct C++ call of a plain function is not caught.
3. **One line:** `WP_RUN_ON_OWNER(Params...)` as the first statement of a `UFUNCTION`, passing the function's own parameters in order. Catches every call, C++ included.

In a `BlueprintNativeEvent`, put the macro in `Name_Implementation`; it finds the UFUNCTION without the suffix. Forwarded functions return nothing, aren't static and have no output parameters (the call is sent, not awaited). They arrive in order with the server's other calls and damage for that entity.

```cpp
// MyNpc.h
UFUNCTION(BlueprintCallable, Category = "Interaction")
void Greet(APawn* By);

// MyNpc.cpp (sandbox AWPNpcCharacter::Greet)
void AMyNpc::Greet(APawn* By)
{
    WP_RUN_ON_OWNER(By);
    // runs only on the NPC's own server from here on
}
```

The pawn damage line (the engine refuses C++ damage to a pawn without authority before anything can see it). `worldplane check --fix` adds it:

```cpp
float AMyCharacter::TakeDamage(float Damage, const FDamageEvent& DamageEvent, AController* EventInstigator, AActor* DamageCauser)
{
    if (WorldPlane::ForwardDamageToOwner(this, Damage, DamageEvent, EventInstigator, DamageCauser))
    {
        return Damage;
    }
    return Super::TakeDamage(Damage, DamageEvent, EventInstigator, DamageCauser);
}
```

The owner applies forwarded damage with `UGameplayStatics::ApplyDamage` on the real actor; the instigating controller stays on the other server, and `DamageCauser` is this server's actor or ghost for the attacker, or null.

Lower level, for what isn't one function call:

```cpp
namespace WorldPlane
{
    bool RunOnOwner(UFunction* Function);          // what OwnerFunctions does, at run time
    bool IsGhostObject(const UObject* Object);     // a ghost or part of one, on a zone server
    bool ForwardCall(UObject& Object, UFunction& Function, const void* Params);
    bool ForwardPayload(AActor& Ghost, FName Kind, const UScriptStruct& Struct, const void* Data);
    void OnOwnerPayload(FName Kind, const UScriptStruct& Struct, TFunction<void(AActor& Owner, const void* Data)> Handler);
}
```

## GAS (`WorldPlaneGAS` plugin, `WPGameplayEffects.h`)

```cpp
namespace WorldPlane::GAS
{
    // True when Target belongs to a copy of another server's entity and the effect went to its owner.
    bool ForwardToOwner(UAbilitySystemComponent& Target, const FGameplayEffectSpec& Spec);
}
```

One line at the top of the game's ability system component override:

```cpp
FActiveGameplayEffectHandle UMyAbilitySystemComponent::ApplyGameplayEffectSpecToSelf(const FGameplayEffectSpec& Spec, FPredictionKey PredictionKey)
{
    if (WorldPlane::GAS::ForwardToOwner(*this, Spec))
    {
        return FActiveGameplayEffectHandle();
    }
    return Super::ApplyGameplayEffectSpecToSelf(Spec, PredictionKey);
}
```

What travels: the effect class, level, stack count, set-by-caller magnitudes (names and tags), dynamic asset and granted tags, instigator and causer (as entities). The owner rebuilds the spec from the instigator's ability system there (its ghost's) and applies it with `ApplyGameplayEffectSpecToTarget`; magnitudes calculated from attributes are calculated again there. The game needs a `UAbilitySystemComponent` subclass to override in (and `WorldPlaneGAS` in its `Build.cs`). In UE 5.8 the virtual is `virtual FActiveGameplayEffectHandle ApplyGameplayEffectSpecToSelf(const FGameplayEffectSpec& GameplayEffect, FPredictionKey PredictionKey = FPredictionKey());`. A game whose ability system component lives on the PlayerState: see [cross-server.md](cross-server.md#gas).

## Events instead of multicasts (`WPEventsComponent.h`)

```cpp
USTRUCT(BlueprintType) struct FWPEvent { int32 Seq; FName Name; TArray<float> Values; };

class UWPEventsComponent : public UActorComponent
{
public:
    UFUNCTION(BlueprintCallable, BlueprintAuthorityOnly) void Emit(FName Name, const TArray<float>& Values);  // owning server
    UPROPERTY(BlueprintAssignable) FWPOnEvent OnEvent;    // clients, once per event, in order
    static constexpr int32 Capacity = 8;
};
```

Add it as a default subobject; the owning server emits, clients bind (sandbox `AWPNpcCharacter`):

```cpp
AMyNpc::AMyNpc()
{
    Events = CreateDefaultSubobject<UWPEventsComponent>(TEXT("Events"));
}

void AMyNpc::BeginPlay()
{
    Super::BeginPlay();
    if (GetNetMode() == NM_Client)
    {
        Events->OnEvent.AddDynamic(this, &AMyNpc::HandleEvent);   // UFUNCTION() void HandleEvent(const FWPEvent& Event);
    }
}

// on the owning server, where a NetMulticast used to be called:
Events->Emit(TEXT("hit"), { Damage, static_cast<float>(TargetEntityId) });
```

Lossy by design: the last 8 events are kept; a client that falls further behind loses the oldest, and one that first sees the actor gets only later events. For hit reactions, damage numbers and sounds, not state.

## Player handoffs and restore providers (`WPHandoffTypes.h`)

```cpp
struct FWPPlayerHandoffHooks
{
    static void RegisterRestoreProvider(FWPRestoreProvider Provider);
    static void UnregisterRestoreProvider(FName Name);
    static FCanHandOff CanHandOff;   // bool(const APlayerController&, const APawn&): old server; false = not now, asked again later
    static FGather OnGather;         // multicast (APlayerController&, APawn&, TArray<FWPHandoffBlob>& OutState): old server, before its actors stop
    static FApply OnApply;           // multicast (APlayerController&, APawn&, const TArray<FWPHandoffBlob>& State): new server, after spawn and possession
};

struct FWPRestoreContext { APlayerController* Controller; APawn* Pawn; APlayerState* PlayerState; uint64 EntityId; int32 OtherServer; bool bCheckpoint; };
enum class EWPRestoreFailure : uint8 { NotSent, VersionMismatch, ApplyFailed, DependencyFailed, ScopeMismatch };

struct FWPRestoreProvider
{
    FName Name;                 // unique and stable, "game.system"
    int32 Version = 1;          // the format Gather writes
    int32 MinVersion = 0;       // oldest format Apply reads; 0 = Version only
    TArray<FName> DependsOn;    // applied first
    TFunction<bool(const FWPRestoreContext&, FArchive&)> Gather;
    TFunction<bool(const FWPRestoreContext&, FArchive&, int32 SentVersion)> Apply;
    TFunction<void(const FWPRestoreContext&, EWPRestoreFailure)> OnFailed;

    template <typename TState>
    static FWPRestoreProvider ForStruct(FName InName, int32 InVersion,
        TFunction<bool(const FWPRestoreContext&, TState& Out)> InGather,
        TFunction<bool(const FWPRestoreContext&, const TState&, int32 SentVersion)> InApply);
};
```

Register once, at module startup (the sandbox does it in its module's `StartupModule`):

```cpp
USTRUCT()
struct FMySkills
{
    GENERATED_BODY()
    UPROPERTY() TArray<FName> Unlocked;
    UPROPERTY() float GlobalCooldownEnds = 0.f;
};

void FMyGameModule::StartupModule()
{
    FWPRestoreProvider Provider = FWPRestoreProvider::ForStruct<FMySkills>(TEXT("mygame.skills"), /*Version*/ 1,
        [](const FWPRestoreContext& Context, FMySkills& Out)
        {
            const AMyCharacter* Character = Cast<AMyCharacter>(Context.Pawn);
            if (Character == nullptr) { return false; }
            Out = Character->Skills;      // old server; also every wp.CheckpointSeconds with Context.bCheckpoint set
            return true;
        },
        [](const FWPRestoreContext& Context, const FMySkills& In, int32 /*SentVersion*/)
        {
            AMyCharacter* Character = Cast<AMyCharacter>(Context.Pawn);
            if (Character == nullptr) { return false; }
            Character->Skills = In;       // new server, before the actors first replicate; must not wait
            return true;
        });
    Provider.OnFailed = [](const FWPRestoreContext& Context, EWPRestoreFailure Reason) { /* read the game's backend instead */ };
    FWPPlayerHandoffHooks::RegisterRestoreProvider(MoveTemp(Provider));
}
```

`ForStruct` writes the USTRUCT by its properties (not Transient ones), each tagged by name and type, so adding or removing a property needs no new `Version`. A raw provider sets `Gather`/`Apply` itself and writes the archive directly. On the new server `OnApply` runs first, then providers in dependency order (ties by name).

## Placed spawners (`WPSpawners.h`)

```cpp
namespace WorldPlane
{
    bool IsPlacedSpawner(const AActor& Actor);
    bool IsSpawnedEntityAlive(const AActor& Spawner, uint64 EntityId, AActor** OutLocal = nullptr);
    TArray<uint64> GetSpawnedEntities(const AActor& Spawner);   // alive anywhere in the zone, ascending
    uint64 GetSpawnerId(const AActor& Spawner);
    AActor* FindSpawner(uint64 SpawnerId);                      // this server's copy, running or dormant
}
```

How a spawner uses them is in [cross-server.md](cross-server.md#spawning).

## Keeping actors together (`WPInteractionGroups.h`)

Blueprint function library `UWPInteractionGroups` (server only; without a coordinator it does nothing):

```cpp
static void BeginInteraction(const TArray<AActor*>& Actors, float Seconds = 60.f, const FString& Reason = TEXT("interaction"));
static void EndInteraction(const TArray<AActor*>& Actors);
static bool IsInInteraction(const AActor* Actor);
```

The coordinator moves every member to the server that owns most of them and keeps them there, whatever the areas say, until `EndInteraction` or until `Seconds` pass. For trades, grapples, mounts, looting together. Members need an entity component.

## Per-player relevancy (`WPGatewayClients.h`, module `WorldPlaneProxy`)

```cpp
namespace WorldPlane::Relevancy
{
    void Update(AActor& Actor, TFunctionRef<bool(const APlayerController&)> IsRelevant);
    void Release(AActor& Actor);
}
namespace WorldPlane::Gateway
{
    bool IsGateway(const UWorld& World);
    UReplicationSystem* GetClientReplicationSystem(const UWorld& World);
    void ForEachClient(const UWorld& World, TFunctionRef<void(const FClient&)> Visit);   // FClient { uint32 ConnectionId; const APlayerController* PlayerController; }
    FOnClientChanged& OnClientChanged();   // (const UWorld& GatewayWorld, const FClient& Client)
}
```

Call `Update` from code that runs on servers and the gateway alike (a tick not gated on authority), and again whenever the answer can change and on `OnClientChanged`. The sandbox NPC, ticking where `GetNetMode() != NM_Client`:

```cpp
WorldPlane::Relevancy::Update(*this, [](const APlayerController& PlayerController)
{
    const APawn* Pawn = PlayerController.GetPawn();
    const uint64 PawnId = WorldPlane::GetEntityId(Pawn);
    return PawnId == 0 || MyGame::CanSee(PawnId);   // the game's own rule; no pawn yet (mid-handoff): keep the answer steady
});
```

## Targets by id (`WPTargetRef.h`, optional)

Plain `AActor*` RPC parameters and replicated references to another server's entity already resolve to its ghost. `FWPTargetRef` is the explicit form, for code that wants the id:

```cpp
UFUNCTION(Server, Reliable) void ServerUseAbility(FWPTargetRef Target);   // client: ServerUseAbility(FWPTargetRef::Make(TargetActor));
AActor* Resolved = Target.Resolve(GetWorld());                            // server: the actor, its ghost, or null
```

## Telemetry and the coordinator (`WPTelemetrySubsystem.h`, `WPCoordinatorSubsystem.h`)

```cpp
// A game event in the coordinator's history (GET .../coordinator/v1/history). Kind: short, stable snake_case.
void UWPTelemetrySubsystem::ReportEvent(const TCHAR* Kind, uint64 EntityId = 0, int32 OtherServer = 0, TOptional<double> Value = {}, const FString& Detail = FString());

static const FString& UWPCoordinatorSubsystem::GetScope();   // the scope in effect
static bool UWPCoordinatorSubsystem::IsRegistered();
```

```cpp
if (UWPTelemetrySubsystem* Telemetry = GetWorld()->GetSubsystem<UWPTelemetrySubsystem>())
{
    Telemetry->ReportEvent(TEXT("boss_spawned"), WorldPlane::GetEntityId(Boss));
}
```

## Blueprint-visible surface

`UWPEventsComponent::Emit` and `OnEvent`; `UWPEntityComponent::OnRemoteDamage` and `TelemetryHealth`; `UWPInteractionGroups::BeginInteraction`, `EndInteraction`, `IsInInteraction`; the `FWPEvent`, `FWPServerArea`, `FWPGhostState`, `EWPRole` and `EWPEntityKind` types. Everything else is C++ only. Blueprint calls of damage and movement on ghosts are forwarded without nodes of their own (`bForwardEngineCalls`), and so are Blueprint calls of functions listed in `OwnerFunctions`.

## Not for game code

The plugin's subsystems (`UWPHandoffSubsystem`, `UWPBackendSubsystem`, `UWPPlacedActorsSubsystem`, `UWPEntitySubsystem`, `UWPAgonesSubsystem`, `UWPPerfSubsystem`, `UWPClientProbeSubsystem`, `UWPBotSubsystem`), the transport, the handle generator, and functions documented as called by the plugin itself (`SetCoordinatorAreas`, `SetZonePeers`, `NoteSpawnerRuns`, `MarkLeavingServer` and the like) run themselves. Games don't call them.
