# Agent rules

- Do not launch Ultrapool, Godot, GDRE, graphics benchmarks, or runtime probes without explicit user authorization for that test. This includes `--headless` and concurrent game instances.
- Use file inspection, static checks, and installer tests with isolated fixtures. Apply these restrictions to delegated work.
- For authorized rendering tests, use `Capture-Screens.ps1` and the fixtures documented in `docs/screenshots.md`. It runs one bounded game process with isolated saves and produces a screenshot gallery; extend its fixtures instead of creating separate runtime launchers.
- Do not change graphics drivers, display settings, GPU settings, or Windows TDR settings as part of mod development.
- Keep public documentation focused on the project. Do not include conversation history, personal machine details, or internal agent workflow commentary.
