# Upgrading WorldPlane

A studio has three things from WorldPlane, each with its own version. Upgrade them in this order, so each step runs with the newest instructions and tools:

| What | Where it is | Installed version | Latest version |
|---|---|---|---|
| **This skill**, as the `worldplane` plugin for Claude Code or Codex, or a `worldplane/` skill folder | the plugin, or `~/.claude/skills/`, `.claude/skills/`, `~/.agents/skills/`, `.agents/skills/` | `VERSION` beside `SKILL.md` | the first `## x.y.z` heading of https://raw.githubusercontent.com/WorldPlane/worldplane-agent/main/CHANGELOG.md |
| **The `worldplane` CLI** | on the PATH | `worldplane --version` | the panel's download (Engine integrations) |
| **The Unreal plugins** | `Plugins/WorldPlane` and `Plugins/WorldPlaneGAS` in the game project | `VersionName` in `WorldPlane.uplugin` | `VersionName` in the download (below) |

Reading versions needs no confirmation. Ask the user before replacing anything, and say what will change.

## 1. This skill

1. Read `VERSION` in this skill's folder. Without one, this is a development copy: say so and skip to step 2.
2. Fetch the changelog above. If its first version is newer, show the user the entries between the two versions.
3. With the user's go-ahead, update it the way it was installed:
   - **Claude Code plugin:** `claude plugin marketplace update worldplane`, then `claude plugin update worldplane@worldplane`.
   - **Codex plugin:** `codex plugin marketplace upgrade worldplane`.
   - **A skill folder:** download https://github.com/WorldPlane/worldplane-agent/raw/main/dist/worldplane-skill.zip, unzip it to a temporary folder, and replace this `worldplane/` folder with the one inside.
4. The new instructions load in a new session. Tell the user to restart Claude Code or start a new Codex session, then ask again to finish the upgrade. Stop here if the skill changed.

## 2. The CLI

1. `worldplane --version`. If it isn't on the PATH, skip this step; the rest works over HTTP.
2. With the user's go-ahead, download the current CLI over it. Download to a temporary file first, then replace the old binary:
   ```sh
   scripts/wp-api.sh -o worldplane.new GET /v1/downloads/cli/linux     # then chmod +x and move it over the old one
   ```
   ```powershell
   scripts/wp-api.ps1 GET /v1/downloads/cli/windows -OutFile worldplane.new.exe   # then move it over the old worldplane.exe
   ```

## 3. The Unreal plugins

1. **Find the project and its versions.** The `.uproject`, `Plugins/WorldPlane/WorldPlane.uplugin` and, if present, `Plugins/WorldPlaneGAS/WorldPlaneGAS.uplugin`: note each `VersionName`. If `Plugins/WorldPlane` is missing, this is a new integration: follow [unreal-integration.md](unreal-integration.md) instead.
2. **Check for local changes.** Run the project's version control status (`git status`, `svn status` or `p4 status`) on `Plugins/WorldPlane*`. If the studio changed plugin files, list them and ask before going on: the upgrade replaces them.
3. **Download** with the user's go-ahead (a member of a subscribed tenant `T`; 402 without a subscription), to a temporary folder outside the project:
   ```sh
   scripts/wp-api.sh -o /tmp/WorldPlane.zip GET /v1/tenants/T/downloads/unreal-plugin
   ```
   ```powershell
   scripts/wp-api.ps1 GET /v1/tenants/T/downloads/unreal-plugin -OutFile "$env:TEMP\WorldPlane.zip"
   ```
   Unzip it there. It holds `WorldPlane/` and `WorldPlaneGAS/`.
4. **Compare.** Read the new `VersionName`. Compare the new folders with the project's, leaving out `Binaries/Win64`, `Binaries/Linux`, `Intermediate`, `Saved` and `DerivedDataCache`. If nothing differs, tell the user the plugins are current and stop. Otherwise read the new `WorldPlane/CHANGELOG.md`, if the download has one, and list every entry newer than the installed version, with what each asks of the game.
5. **Replace,** after the user agrees and **closes the Unreal editor** for this project (it holds the plugin's DLLs open). Delete the project's `Plugins/WorldPlane` and, if the project uses it, `Plugins/WorldPlaneGAS`, then copy the new folders in. Don't add `WorldPlaneGAS` to a project that didn't have it, unless the project uses GAS and the user wants it ([unreal-integration.md](unreal-integration.md)). Don't keep the old `Binaries` or `Intermediate`: the editor rebuilds them.
6. **`worldplane check <project> --fix`.** Show the user its "Fixed" and "Still to do" lists, then work through what is left and through the changelog items that ask something of the game, following [cross-server.md](cross-server.md).
7. **Rebuild and ship.** The user rebuilds the editor and the server target. A zone only gets the new plugins from a new server build: package the Linux server, upload it, and deploy it to a `dev` or `test` environment first (SKILL.md, Upload a build and Deploy). Clients run the plugins too, so release a new client build together with the servers.

## Afterwards

Summarise for the user: each thing's version before and after, what you changed in the project, what `worldplane check` still reports, and what they have to do (rebuild, package, deploy, release clients).
