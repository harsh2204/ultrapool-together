# Agent rules

## Runtime boundaries

- Do not launch Ultrapool, Godot, GDRE, graphics benchmarks, or runtime probes without explicit user authorization for that test. This includes `--headless` and concurrent game instances. Apply these restrictions to delegated work.
- Use file inspection, static checks, and installer tests with isolated fixtures by default. Report their limits; syntax checks do not prove engine compatibility or smooth gameplay.
- For authorized rendering tests, use `Capture-Screens.ps1` on Windows or `Capture-Screens.py` on macOS and the shared fixtures documented in `docs/screenshots.md`. Each runs one bounded, muted game process with isolated saves and produces a screenshot gallery; extend its fixtures instead of creating separate runtime launchers.
- Do not change graphics drivers, display settings, GPU settings, or Windows TDR settings as part of mod development.
- Keep public documentation focused on the project. Do not include conversation history, personal machine details, or internal agent workflow commentary.

## Performance is part of correctness

- Before changing networking, client scenes, shops, or input, read `docs/PERFORMANCE.md`. Reference the relevant issue IDs in the change and update their evidence, remaining work, and verification status.
- Protect local input and rendering first. Give immediate local hover, drag, focus, and pending feedback. Keep purchases, shared money, turn ownership, votes, and run outcomes authoritative; speculative visuals must reconcile or roll back.
- Choose bounded work over cleverness. Put explicit packet, byte, and elapsed-time limits on receive loops; include synchronous handlers in the budget. Preserve reliable actions and channel fairness. Treat a single over-budget packet or scene construction as an unresolved gap.
- Make UI updates depend on changed data. Retain item nodes and resources, preserve focus and active drags, and update only affected properties. Explain any full rebuild, repeated traversal, or native setter in a frame/snapshot hot path.
- Keep disk I/O, resource discovery/loading, synchronous save work, full-scene construction, and bulk node destruction off recurring input/render paths. Cache or stage necessary work at lifecycle boundaries; document unavoidable native calls.
- Separate reliable transitions and transactions from disposable motion and presence. Reduce redundant snapshots before increasing tick rates, compression, or buffering. Any coalescing must preserve match, scene, phase, and action barriers.
- Bound queues and caches, define overflow/recovery behavior, and clear them on disconnect, scene change, and rematch. Never fix a frame spike by hiding it in an unbounded backlog or adding arbitrary delays.
- Preserve data validation, actor identity, revision checks, and replay protection when optimizing. Remove duplicate work at a trusted internal boundary, not at the network boundary.
- Prefer the smallest reversible change with a clear invalidation rule. State the tradeoff: CPU, bytes, memory, responsiveness, or correctness. A feature that stalls a client or silently loses an action is incomplete.

## Evidence and completion

- Use static evidence to identify work and form hypotheses. Label changes **implemented, unmeasured** until authorized runtime checks demonstrate the intended improvement; never claim an FPS or latency gain from code inspection.
- For an authorized performance check, compare the same fixture, renderer/frame cap, item count, peer topology, and latency before/after. Record frame-time p50/p95/p99/max, input-to-feedback and input-to-confirmation latency, packet bytes/rates, queue growth, and relevant scene/UI call counts. Average FPS alone is insufficient.
- Exercise initial sync, delayed/reordered updates, rejection/rollback, simultaneous shopping, disconnect, and rematch at the appropriate existing test seam. Add regression coverage for meaningful behavioral changes; do not create tests that merely repeat implementation constants.
- Keep a tracker item open while its acceptance criteria, platform verification, or correctness coverage remain unmet. Mark partial fixes honestly and leave an independent next step so another contributor can continue.
- Installers must preserve vanilla files and saves, support repeatable updates/uninstall, and use isolated fixtures. macOS and Windows share gameplay/protocol semantics; platform-specific launch code must not silently change them.
