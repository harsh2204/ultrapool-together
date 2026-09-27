# Custom cues

Per-player cue stick cosmetics for Ultrapool Together (issue #20). Visuals only — no gameplay stats.

## Roster

| Id | Label | Look |
| --- | --- | --- |
| `native` | Native | Default / identity (vanilla cue) |
| `emerald` | Emerald | Felt-green tint |
| `coral` | Coral | Warm coral tint |
| `gold` | Gold | Brass / gold tint |
| `violet` | Violet | Soft violet tint |
| `ice` | Ice | Cool cyan tint |
| `rose` | Rose | Pink tint |
| `chalk` | Chalk | Pale chalkwood tint |
| `midnight` | Midnight | Dark slate tint |
| `amber` | Amber | Deep amber tint |

All styles are parametric recolors of the native cue (modulate / tip color). No new art assets and no vanilla file writes.

## Selection

Open **Together options** in the lobby. The **Your cue** swatches are a personal setting (each player chooses their own), unlike host-only lobby toggles. The choice is written to `user://together_cue.cfg` inside the mod’s isolated `UltrapoolTogether` user folder so it survives restarts without touching vanilla saves.

## Sync

1. **Lobby field** `players[].cue` — authoritative when the controller wires `cue_requested` → `lobby_model.set_cue` (see integration notes below). Dirty-gated; does not clear Ready.
2. **Presence** — each presence sample carries a dirty-gated `cue` string so table peers see updates even mid-match. Aim overlays prefer the cue tip color when a non-native style is active.

## Application

- **Host:** `game_adapter` applies `CueCatalog.apply(player_ball, cue_id)` when the turn owner’s cue changes.
- **Guest replica:** call `CueCatalog.apply(cue_node, cue_id)` at the replica cue-visual update site (coordinator-owned file; do not silently diverge).

```gdscript
CueCatalog.apply(body, CueCatalog.cue_for_player(lobby, turn_owner))
```

## Status

**Implemented, unmeasured.** Parser checks cover new scripts; live table rendering and multi-peer cue visibility still need an authorized session.
