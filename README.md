# WorldPlane for Claude Code and Codex

[WorldPlane](https://worldplane.net) hosts an Unreal Engine 5.8 game's dedicated servers as zones: several servers share one seamless world, players and NPCs are handed between them at area borders, and players connect through one gateway.

This plugin teaches Claude Code or OpenAI Codex to work with WorldPlane for your studio:

- **Integrate WorldPlane into your Unreal game.** The agent reads your project, installs and enables the WorldPlane plugins, sets up the config and a Linux server target, runs `worldplane check --fix`, and makes your game code work across servers with the smallest change.
- **Keep it up to date.** "Upgrade WorldPlane" brings this plugin, the `worldplane` CLI and your project's WorldPlane plugins to the latest versions, then works through what changed.
- **Run your account.** Create projects and environments, upload Linux server builds, deploy and roll back, stop and wake zones, and read status, usage, spend and the audit log, through WorldPlane's MCP server (`https://app.worldplane.net/mcp`), which the plugin adds.

It asks you before anything that costs money, disconnects players or replaces files, and it never prints or commits your token.

## Install

### Claude Code

In a Claude Code session:

```
/plugin marketplace add https://github.com/WorldPlane/worldplane-agent.git
/plugin install worldplane@worldplane
```

Or from a shell:

```sh
claude plugin marketplace add https://github.com/WorldPlane/worldplane-agent.git
claude plugin install worldplane@worldplane
```

Restart Claude Code. The skills are `/worldplane:worldplane` and `/worldplane:upgrade`, and Claude also uses them by itself when you ask about WorldPlane.

### Codex

```sh
codex plugin marketplace add WorldPlane/worldplane-agent
codex plugin add worldplane@worldplane
```

Or, after adding the marketplace, open `/plugins` in Codex, choose the WorldPlane marketplace and install **WorldPlane**. Start a new session to use it.

### Other agents, or by hand

[`dist/worldplane-skill.zip`](dist/worldplane-skill.zip) is the `worldplane` skill on its own. It unzips to a `worldplane/` folder: put it in `~/.claude/skills/` or `.claude/skills/` (Claude Code), `~/.agents/skills/` or `.agents/skills/` (Codex), or wherever your agent reads skills.

## Sign in

The plugin adds WorldPlane's MCP server. Sign in to it once, in your browser:

- **Claude Code:** run `/mcp`, choose `plugin:worldplane:worldplane`, and Authenticate;
- **Codex:** `codex mcp login worldplane`, or Authenticate in `/mcp`.

WorldPlane's sign-in page asks for your password (and authenticator code), then what the agent may do: everything you can do except billing, deleting things, API keys and members; deploy and operate; develop; or read only. You can also limit it to one organisation or one project. The agent never gets more than your own roles, and what it does shows in your audit log as `agent:<you> (<program>)`. Disconnect it any time in the [panel](https://app.worldplane.net) (Connected agents).

Without the MCP server (another agent, or CI), the agent uses the `worldplane` CLI or the HTTP API instead. It never signs in for you, so pick one:

- run `worldplane login --url https://app.worldplane.net --email you@studio.example` yourself (download the CLI from the [panel](https://app.worldplane.net)); the agent then acts as you;
- create an API key in the panel and set `WORLDPLANE_URL=https://app.worldplane.net` and `WORLDPLANE_KEY=wpk_...` before starting the agent. A key can be limited to a role and one project.

## Updates

Each release raises the plugin's version. [CHANGELOG.md](CHANGELOG.md) lists every version with its date, and each has a tag (`v0.1.0`) whose files, `dist/worldplane-skill.zip` included, stay available.

- **Claude Code:** turn on auto-update for the marketplace under `/plugin` → Marketplaces → `worldplane` → Enable auto-update, or update by hand with `claude plugin marketplace update worldplane` and `claude plugin update worldplane@worldplane`.
- **Codex:** `codex plugin marketplace upgrade worldplane`.
- **Either:** ask the agent to "upgrade WorldPlane".

## License

Proprietary: free to use with WorldPlane, not to redistribute. See [LICENSE](LICENSE).
