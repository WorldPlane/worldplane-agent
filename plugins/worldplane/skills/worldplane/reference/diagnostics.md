# Offline multiplayer diagnostics

WorldPlane Multiplayer Diagnostics is a standalone UE 5.8 / Windows x64 editor plugin. It works without a WorldPlane subscription, SDK, server, CLI or Rust installation. Click **Multiplayer Diagnostics** on the main toolbar to open the report and scan, or use Window > Multiplayer Diagnostics to view it.

The default profile checks general Unreal/Iris patterns and Blueprint replication defaults. Enable **WorldPlane readiness** for integration-specific checks; missing WorldPlane requirements must never appear in the general profile. Findings contain evidence, suggested actions and links to source or Blueprint nodes. They are static review guidance, not performance estimates or proof of correctness. Maps are not inspected. Explain skipped inputs and coverage limits.

Repairs use selected groups: WorldPlane settings, Iris build support and damage forwarding. Preview diffs before applying. WorldPlane-specific dependency/settings repairs require an installed SDK; never add a missing paid-plugin dependency. Blueprint repairs remain manual. Apply checks original content and permissions, retains backups under Saved/WorldPlaneDiagnostics/Backups, then rescans. It does not compile, restart or publish anything.

`worldplane check <project>` retains the WorldPlane profile by default. Use `--profile unreal` for general source/configuration checks, `--json` for structured results, and `--fix` to apply the same supported text repairs. The CLI cannot inspect Blueprint assets and reports that limitation. The editor supplies effective Iris settings; CLI general checks rely on explicit project settings.

For maintainers: `crates/wp-diagnostics` is the single rule and repair owner; `fab/WorldPlaneDiagnostics` contains only the Unreal adapter and panel. Add new policy in Rust and expose engine facts through the versioned metadata contract. Reuse plan/apply and the shared distribution export profile. See `docs/diagnostics-plugin.md` for ABI lifetime, development junctions, packaging and validation. Do not introduce a dependency on the runtime, gateway or control plane.
