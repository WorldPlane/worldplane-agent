# Changelog

Each version of the WorldPlane plugin for Claude Code and Codex, and of the `worldplane` skill inside it, newest first. Every version is also a tag (`v0.1.0`), so its files stay available.

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
