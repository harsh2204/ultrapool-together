# Local runtime testing restriction

On 2026-09-20 this PC suffered a black screen with repeated NVIDIA driver timeouts and required a forced restart. The triggering application has not been established.

- Do not launch Ultrapool, Godot, GDRE, graphics benchmarks, or runtime probes on this PC without explicit user authorization for that test after this incident. This includes `--headless` and concurrent game instances.
- Use file inspection, static checks, and installer tests with fake executable fixtures while runtime testing is suspended. Tell delegated agents about this restriction.
- Do not change graphics drivers, display settings, GPU settings, or Windows TDR settings as part of mod development.
