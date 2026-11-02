# WorldPlane skill for Claude Code and OpenAI Codex

This skill teaches a coding agent two things.

**Integrating WorldPlane into your Unreal game.** The agent reads your project first, then:
- installs the WorldPlane and WorldPlaneGAS plugins from your organisation's download, enables them, and sets up `Build.cs`, `DefaultEngine.ini`, the plugin settings and a Linux server target. The plugins aren't part of this skill: they come with the Studio plan, so your organisation needs an active subscription, and you or the agent download them from the panel or the API;
- runs `worldplane check` (with `--fix` for the mechanical changes) and works through what is left;
- makes your game code work across servers with the smallest change: what survives a handoff, calls and damage on another server's entity, GAS effects, multicasts, relevancy, spawning, the zone's GameState;
- explains how to run a zone locally and package the Linux server, and reads the plugin's `WP_` log lines with you.

**Running WorldPlane for your studio**, through the `worldplane` CLI or the control plane's HTTP API at https://app.worldplane.net:
- create projects and environments;
- check and upload Linux server builds;
- deploy and roll back;
- stop and wake zones;
- read a zone's status and events, this month's usage, and the audit log.

It asks you before anything that costs money or disconnects players, and before long Unreal builds. It never prints or commits your token. When something needs a subscription (402), it sends you to the panel. Where the plugin's behaviour isn't documented, it says so instead of guessing.

The folder works in both tools as it is: `SKILL.md` has `name` and `description` frontmatter, which both Claude Code and Codex read.

```
worldplane/
  SKILL.md                         when to use it, the rules, the workflows
  reference/unreal-integration.md  plugins, config, server target, worldplane check, local runs, packaging
  reference/cross-server.md        what game code needs to work across servers
  reference/unreal-api.md          the plugin's classes and functions, with examples
  reference/troubleshooting.md     the plugin's WP_ log lines and what they mean
  reference/upgrade.md             upgrading this skill, the CLI and the plugins
  reference/api.md                 every endpoint: method, path, body, answer, errors
  scripts/wp-api.sh                calls the API with curl, without showing the token
  scripts/wp-api.ps1               the same for PowerShell 5.1 / 7
```

## Install

The easiest way is the WorldPlane plugin for Claude Code or Codex, which carries this skill and updates with it: see https://github.com/WorldPlane/worldplane-agent.

To install the skill on its own, unzip `worldplane-skill.zip` (https://github.com/WorldPlane/worldplane-agent/raw/main/dist/worldplane-skill.zip). You get a `worldplane/` folder; put it where your tool looks. `VERSION` in it says which version you have.

### Claude Code

| Scope | Folder |
|---|---|
| You, every project | `~/.claude/skills/worldplane/` (Windows: `%USERPROFILE%\.claude\skills\worldplane\`) |
| One repository, shared with your team | `.claude/skills/worldplane/` at its root (commit it) |

```sh
mkdir -p ~/.claude/skills && unzip worldplane-skill.zip -d ~/.claude/skills
```
```powershell
Expand-Archive worldplane-skill.zip -DestinationPath "$HOME\.claude\skills"
```
Claude Code picks it up when it next starts. Claude uses it when you ask about WorldPlane, or you can invoke it with `/worldplane`.

### OpenAI Codex

| Scope | Folder |
|---|---|
| You, every project | `~/.agents/skills/worldplane/` (Windows: `%USERPROFILE%\.agents\skills\worldplane\`) |
| One repository | `.agents/skills/worldplane/` at its root (commit it) |

```sh
mkdir -p ~/.agents/skills && unzip worldplane-skill.zip -d ~/.agents/skills
```
```powershell
Expand-Archive worldplane-skill.zip -DestinationPath "$HOME\.agents\skills"
```
Restart Codex if the skill doesn't show up. Codex uses it when a request matches, or you can name it with `$worldplane`. Older Codex releases read `~/.codex/skills/` instead; newer ones still read it, but treat it as deprecated.

## Sign in

The agent never signs in for you. Pick one:
- **Your own session:** run `worldplane login --url https://app.worldplane.net --email you@studio.example` yourself. It asks for your password (and your authenticator's code). The agent then uses that session, with your roles.
- **An API key** (best for limiting what the agent may do): an owner or admin creates one in the panel, with a role and, if you like, one project. Set two environment variables before starting the agent:
  - `WORLDPLANE_URL=https://app.worldplane.net`
  - `WORLDPLANE_KEY=wpk_...`

  A `developer` key on one project can upload, and deploy only to `dev` and `test`.

Keep keys out of the repository. Using WorldPlane, and downloading its Unreal plugins, needs a subscription: subscribe in the panel's billing.

## Try it

> Using the worldplane skill: what's running in mystudio/mygame, which build is on test, and what have we spent this month?

> Zip Saved/StagedBuilds/LinuxServer, push it to mystudio/mygame as build 0.4.2, and deploy it to test.

> Using the worldplane skill, integrate WorldPlane into this Unreal project: read the code first, set up the plugin and config, run worldplane check, and make the NPCs and the player's interact and attack work across servers with as few changes as you can.

> Make AMyChest work across WorldPlane servers: players on the next server should be able to open it.

## More

- Unreal plugin: https://worldplane.net/docs/unreal
- API reference: https://worldplane.net/docs/api
- Onboarding and everything else: https://worldplane.net/docs/
