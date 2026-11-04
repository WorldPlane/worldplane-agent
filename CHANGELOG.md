# Changelog

Each version of the WorldPlane plugin for Claude Code and Codex, and of the `worldplane` skill inside it, newest first. Every version is also a tag (`v0.1.0`), so its files stay available.

## 0.2.18 (2026-11-04)

- Crossings, from plugins 0.4.12: an entity's new actor exists before its old one goes, on both servers (ADR 0030).
  - The cross-server reference explains `WorldPlane::OnActorReplaced` and `GetReplacement`, and what the plugin moves for you: AI focus and Blackboard keys.
  - Troubleshooting covers NPCs that give up a fight when a player crosses, damage refused because `FindGhost` (now deprecated) finds stand-ins only, and the new `WP_ACTOR_REPLACED`, `WP_GHOST_ADD ... (departed)` and `WP_GHOST_REMOVE` lines.
  - The API reference documents the event.

## 0.2.17 (2026-11-04)

- Handoffs, from plugins 0.4.11: values replicated only to the owning client stay behind, and the new `HandoffCarryExclude` setting names others. The cross-server reference explains why owner-only "loaded" flags must not travel. Troubleshooting covers a system that arrives "loaded" but empty after a crossing, the `WP_HANDOFF_CARRY excluded=` line, and checkpoint refusals that no longer warn. The integration reference lists `bHandoffCarriesReplicatedValues` and `HandoffCarryExclude`.

## 0.2.16 (2026-11-04)

- Logins: from plugins 0.4.10 the gateway joins each login to the server that owns where the player will spawn (where the client's pawn last stood, else the level's player starts, else load), instead of always one server. The cross-server reference says what games must not assume; troubleshooting explains `WP_ADMISSION`, `WP_ADMISSION_MISS` and `WP_RETURN_POINT`, and a zone where every login lands on one server and is handed off right after.

## 0.2.15 (2026-11-03)

- Troubleshooting: a zone that never sleeps because players who crossed a border and then left are still counted (the gateway logged `Cannot send NMT_CloseChildConnection`). Fixed in plugins 0.4.9; rebuild and deploy the server package.

## 0.2.14 (2026-11-03)

- Maintenance notices: a `window` policy has `notice` (0 to 60 minutes, default 10; `worldplane env update --notice`, MCP `set_update_policy` with `notice`). Before the window restarts a zone with players, its servers raise `UWPMaintenanceSubsystem::OnMaintenanceNotice(SecondsLeft)`, and the zone restarts as the window opens. The cross-server reference says how a game warns its players (each server its own; not a GameState multicast). Needs the control plane deployed on or after this day and plugins 0.4.8.

## 0.2.13 (2026-11-03)

- Update policies: an environment chooses when changes reach its running zone. `automatic` (the default) waits until the zone has no players or wakes; `window` also applies them in a weekly UTC window; `pinned` waits for your next deploy. A build can be deployed `later` (`worldplane deploy --later`, MCP `deploy` with `when: later`) so nobody is disconnected now. The skill offers `later` when players are on a zone, and describes `set_update_policy`, `worldplane env update --updates/--window` and the `updates` status. Needs the control plane deployed on or after this day.

## 0.2.12 (2026-11-02)

- A `fleet_member_failed` event in a zone's history (`get_zone_events`, `GET .../coordinator/v1/history`) now carries the dead server's or gateway's last log lines in `lines`, with the game's crash callstack when it crashed; the API reference describes it. Needs the control plane deployed on or after this day.
- Troubleshooting: the gateway dying with exit 139 when a player gains an item during play, and the rule behind it in the cross-server reference: replication callbacks run on the gateway for every player, in the server's write order, so one that reads another replicated object before its state arrived must tolerate it. How to symbolize a Linux Shipping stack from the build's `.debug` file.

## 0.2.11 (2026-11-02)

- Says plainly where the WorldPlane Unreal plugins come from: they come with the Studio plan, and only a member of a subscribed organisation can download them, from the organisation's page in the panel or the same download in the API. This plugin and its skill don't contain them, and the MCP server doesn't serve them. The agent asks you to download the zip from the panel (the only way with the MCP server alone), or fetches it through the API with your go-ahead. On a 402 it stops and sends you to the panel to subscribe, and it never takes the plugins from anywhere else.

## 0.2.10 (2026-11-02)

- Hosted servers and gateways now receive environment secrets as process variables, including SDK credentials read outside Unreal INI settings. Updated guidance explains deployment/rotation and preserves legacy argument substitution.

## 0.2.9 (2026-11-02)

- Documents paired source/native-library updates for WorldPlane 0.4.7 and smaller customer plugin downloads.
- Adds guidance for the standalone Multiplayer Diagnostics editor plugin, including Blueprint inspection and repair previews.

## 0.2.8 (2026-11-01)

- The skill's troubleshooting covers predicted gameplay effects or abilities that stay on a client after the server ended them, for every player but the first to connect through the gateway (fixed in plugins 0.4.6: the gateway re-owns relayed prediction keys to their client).

## 0.2.7 (2026-11-01)

- The troubleshooting covers the `LogIris: Warning: Generating descriptor for struct ... that has custom serialization` line that marks a struct Iris replicates by reflection (see 0.2.6).
- The `WP_MOVE_CORRECTIONS` entry covers a steady correction count on the ground with smooth jumps (a speed difference between client and server) and the ping the line carries from plugins 0.4.5.
- The troubleshooting covers a gateway that dies with exit code 139 as a player logs back in (gateways before plugins 0.4.5 ran the game's local-player subsystems).

## 0.2.6 (2026-11-01)

- Structs with their own `NetSerialize` under Iris: Iris replicates them by reflection, so every wire member must be a `UPROPERTY` and `TMap`/`TSet` members don't travel (Exordium's tracking selection arrived as zeros). The integration reference has the rule (§2), and `worldplane check` finds such structs: `iris-custom-struct`, an error per struct naming the members declared without `UPROPERTY` and the `UPROPERTY` map and set members, third-party plugins included. No `--fix`: a `UPROPERTY()` on a member of a type the header tool can't reflect breaks the build. The check is in the CLI from the panel's download of 2026-11-01 on.

## 0.2.5 (2026-11-01)

- The skill's troubleshooting covers an equipped weapon or other attached actor that disappears behind the gateway when the player walks away from where it was equipped, and comes back when they return (fixed in plugins 0.4.4).

## 0.2.4 (2026-11-01)

- The skill's troubleshooting covers a client whose controller has no player at login: gateways on plugins 0.4.1 and 0.4.2 sent every client every controller (fixed in 0.4.3), and how to see which controllers a client took.

## 0.2.3 (2026-10-31)

- The plugin's Codex listing is in the Developer Tools category, one OpenAI's plugin directory accepts.

## 0.2.2 (2026-10-31)

- The plugin's listing links to its documentation, support, privacy and terms pages, and its README says where your data goes.

## 0.2.1 (2026-10-31)

- Codex finds the WorldPlane MCP server: its entry in `mcp.json` is only the type and URL. Codex 0.165 dropped an entry with the OpenAI `auth` block, and finds OAuth by itself.

## 0.2.0 (2026-10-31)

- The plugin adds WorldPlane's MCP server, `https://app.worldplane.net/mcp`, for Claude Code (`.mcp.json`) and Codex (`mcp.json`). Sign in once in the browser (Claude Code: `/mcp`; Codex: `codex mcp login worldplane`), choose what the agent may do and, if you like, the one organisation or project it may touch. Disconnect it any time in the panel.
- Its tools read projects, environments, zone status and events, builds, usage and spend and the audit log, and create environments, upload builds (through a short-lived link, not the conversation), deploy, roll back, stop and wake zones and set secrets. The agent still asks you first before anything that costs money or disconnects players.
- The `worldplane` skill prefers the tools when they are there, and keeps the CLI and the API for archives over 5 GiB and for agents without MCP.

## 0.1.2 (2026-10-31)

- The plugin has an icon, and its Codex listing has a short description and starter prompts.

## 0.1.1 (2026-10-31)

- For WorldPlane plugins 0.4.0: `PlacedSpawnerClasses` is optional, since a placed actor that spawns with itself as the Owner is found and run once per zone. The skill explains `WP_UNLISTED_SPAWNER`, `WP_SPAWNERS_FOUND` and `WP_FIXTURE_SPAWNS`, and the `WPNotSpawner` tag that keeps an actor running on every server.

## 0.1.0 (2026-10-31)

- The `worldplane` plugin for Claude Code and Codex, with two skills:
  - `worldplane`: integrate WorldPlane into an Unreal Engine 5.8 game, and run the studio's projects, builds, deploys and zones through the `worldplane` CLI or the HTTP API.
  - `upgrade`: bring this plugin, the `worldplane` CLI and a project's WorldPlane plugins up to date, then run `worldplane check --fix` and work through what changed.
- The API helper scripts save downloads to a file: `wp-api.sh -o FILE ...` and `wp-api.ps1 ... -OutFile FILE`.
- The skill on its own, for other agents or a manual install: `dist/worldplane-skill.zip`.
