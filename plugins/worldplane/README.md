# WorldPlane

[WorldPlane](https://worldplane.net) hosts an Unreal Engine 5.8 game's dedicated servers as zones: several servers share one seamless world, and players connect through one gateway. This plugin teaches Claude Code or Codex to integrate WorldPlane into your Unreal game, keep it up to date, and run your studio's projects, builds and zones.

- **Skills:** `worldplane` (integrating the WorldPlane Unreal plugins, cross-server game code, packaging, running the account) and `upgrade` (this plugin, the `worldplane` CLI and your project's WorldPlane plugins).
- **MCP server:** `https://app.worldplane.net/mcp`. Sign in once in your browser (Claude Code: `/mcp`; Codex: `codex mcp login worldplane`) and choose what the agent may do. Disconnect it any time under **Connected agents** in the panel.

The agent asks you first before anything that costs money, disconnects players or replaces files.

## Install

Claude Code, in a terminal (2.1.292 or later; in a session, `/plugin install` with the same arguments):

```sh
claude plugin install worldplane --marketplace https://github.com/WorldPlane/worldplane-agent.git
```

Codex:

```sh
codex plugin marketplace add WorldPlane/worldplane-agent
codex plugin add worldplane@worldplane
```

## Where your data goes

- **app.worldplane.net**, WorldPlane's control plane and MCP server: everything the agent reads or changes in your WorldPlane account.
- **WorldPlane's build storage at Amazon Web Services** (`amazonaws.com`): build archives the agent uploads, through a short-lived link the control plane gives it for that one upload.
- **Downloads only:** github.com for this plugin's updates and changelog, and app.worldplane.net for the WorldPlane Unreal plugins and the `worldplane` CLI. Nothing of yours is sent there.

Without the MCP server, the skill's helper scripts send your WorldPlane session or API key (`WORLDPLANE_KEY`) only to the address in `WORLDPLANE_URL`, `https://app.worldplane.net`. The plugin itself has no telemetry and sends nothing anywhere else.

## Links

- Documentation: https://worldplane.net/docs/agents
- Support: https://worldplane.net/support
- Privacy policy: https://worldplane.net/privacy
- Terms of service: https://worldplane.net/terms
- Versions and changelog: https://github.com/WorldPlane/worldplane-agent
