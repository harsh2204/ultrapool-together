---
name: ultrapool-development
description: "Navigate, implement, review, and verify changes in Ultrapool Together. Use for gameplay and native input, host/client replication and table effects, shop/snackbar/mixer UI or transactions, new shop items or characters, and regression fixes. Routes to the actual authority, lifecycle, and test seams; preserves native behavior and distinguishes static checks from authorized native and multiplayer verification."
---

# Ultrapool development

Use this skill from a checkout of this repository. Read [AGENTS.md](../../../AGENTS.md) first. It defines runtime authorization, performance, and evidence requirements. Existing user authorization takes precedence; adding a test or changing documentation does not authorize executing the game.

## Establish the change

1. Inspect `git status`, the current branch/base, recent relevant commits, and the reported game/mod versions. An unmerged feature branch is not the implementation on `main`. Preserve unrelated work; use an isolated checkout when needed.
2. State the observable trigger and expected behavior, the affected role (room host, table leader, guest, spectator), phase, and last known good version. Read the relevant issue **and its remaining acceptance work**; a closed issue or merged PR is not proof of runtime verification.
3. Read [docs/PERFORMANCE.md](../../../docs/PERFORMANCE.md) before changing input, networking, client scenes, or shops. Select existing `PERF-*` / `GAP-*` IDs. For effect parity, also read [docs/TABLE_EFFECTS.md](../../../docs/TABLE_EFFECTS.md).
4. Use the [code map](references/code-map.md) to trace the complete path from real input or native callback through authority, serialization, guest application, and teardown. Inspect the native base class and scene where available: these scripts wrap the installed game, not a self-contained Godot project. Do not launch extraction tools without authorization or redistribute native source/assets.
5. For new content, fill the [shop character/item change template](assets/shop-content-change.md). Resolve whether “character” means a shopkeeper NPC, a purchasable item, or a new owned gameplay entity before selecting a schema. The repo does not provide a general character registry.

## Choose the smallest complete fix

- Keep presentation changes out of native gameplay gates. Initial mouse/controller aim is polled by inherited `PlayerBall._process`; changing `game.in_menu` to hide art can block the initial click. Preserve native fade, charge pullback, settings/popup gates, and off-turn rejection. Follow the actual input path in a regression fixture.
- Keep the **table leader** authoritative for shots, effects, money, inventory, transactions, readiness, and results. The **room host** routes and manages membership and may be a different peer. Guests predict eligible UI feedback and reconcile; presence is disposable presentation, never proof of ownership.
- Extend capture, validation, application, reliable transitions, resync, spectator behavior, and cleanup together when adding state. Define identity and bounded count/byte/time costs. Reject malformed or incompatible data before mutation. Never remove validation or silently truncate live identities to make a fixture pass.
- Distinguish durable state from transient animation. A ball's `flaming` flag does not represent a fire patch on the floor. A dynamic hole is not a fixed pocket just because both occur in one native Array. Do not replay native scoring, spawning, collision effects, or saves on a replica.
- Preserve existing native item nodes, focus, drags, animation, and immediate pending feedback. Update changed properties. Audit inherited setters, `_ready`, timers, signals, scene construction, and saves for side effects before calling them from packet/frame paths.
- Define cache/queue bounds and invalidation at shot, round, scene, match, disconnect, and rematch boundaries as appropriate. A targeted resync must not consume a reliable broadcast still owed to other clients.

## Verify behavior at the right seam

Read [regressions and validation](references/regressions-and-validation.md) and select checks for the changed behavior. Always distinguish:

- **Static:** source/contract review, parsing, path checks, package inspection; no game executed.
- **Isolated fixture tests:** installer/runner tests using inert or mocked executables; no gameplay evidence.
- **Authored runtime coverage:** assertions added but not run.
- **Authorized native coverage:** bounded Capture-Screens run, actual assertions, logs, gallery, process cleanup and save preservation reviewed.
- **Live multiplayer/platform coverage:** separate sessions with stated topology, versions, latency, and platforms. A single-process replay cannot establish it.

Before native runtime work, follow the current authorization in AGENTS.md and the session. Use the existing Capture-Screens harness for rendering; extend shared fixtures instead of inventing a launcher. Do not run standalone Godot probes, headless mode, concurrent instances, or GDRE as a substitute for authorization. Continue useful static work when runtime execution is unavailable.

For a bug fix, the fixture must reach the former failure through the relevant production boundary. Explain why it would fail before the change. Do not seed the desired final state and then claim to have tested the interaction that creates it. Run appropriate checks once; expand only for failures, changed scope, or unresolved concerns.

## Deliver and maintain

Update the affected feature/coverage docs and performance evidence with the actual checks, version/commit, limitations, and independent next step. Label runtime/performance changes **implemented, unmeasured** until the appropriate evidence exists. Leave unmet acceptance items open. No workflow guarantees bug-free output; make verification gaps visible.

Review the final diff and verify it still matches the tested commit after rebasing. State the user-visible behavior, authority/lifecycle tradeoff, checks performed, and checks not performed in the PR. For a release, follow both packaging paths and the installer preservation requirements; a successful build is not a native compatibility check. Keep this map updated when entrypoints move.
