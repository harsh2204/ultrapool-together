extends RefCounted
## Vanilla-safe cue cosmetics: recolors / parametric tints of the native cue look.
## No new art pipeline. Default id restores native appearance (identity modulate).
## Refs #20. Host and guest both call apply(); guest replica wiring may be coordinator-owned.
##
## Important (#22): never rely on tinting the PlayerBall/Ball root modulate — replica
## apply_table writes body.modulate from state every snapshot and would wipe it. Tint
## only the cue art, never the native fade pivot. Preserve live animation alpha.
## Re-apply when child RGB diverges even if meta matches (PERF-027).

const DEFAULT_ID = "native"
const MAX_ID_LENGTH = 32

## Starter roster: tip / shaft / butt are presentation colors; modulate tints CanvasItems.
const CUES = [
	{
		"id": "native",
		"label": "Native",
		"tip": Color("d8c6a2"),
		"shaft": Color("c4a574"),
		"butt": Color("5a3c28"),
		"modulate": Color.WHITE,
	},
	{
		"id": "emerald",
		"label": "Emerald",
		"tip": Color("b8f0d8"),
		"shaft": Color("35d5ab"),
		"butt": Color("0f3d34"),
		"modulate": Color("9ef0d4"),
	},
	{
		"id": "coral",
		"label": "Coral",
		"tip": Color("ffd0c0"),
		"shaft": Color("ee9073"),
		"butt": Color("5a2418"),
		"modulate": Color("f0b09a"),
	},
	{
		"id": "gold",
		"label": "Gold",
		"tip": Color("fff0c8"),
		"shaft": Color("edc86b"),
		"butt": Color("5a4010"),
		"modulate": Color("f0d888"),
	},
	{
		"id": "violet",
		"label": "Violet",
		"tip": Color("e0d4ff"),
		"shaft": Color("a998e4"),
		"butt": Color("2e2458"),
		"modulate": Color("c4b4f0"),
	},
	{
		"id": "ice",
		"label": "Ice",
		"tip": Color("e8f6ff"),
		"shaft": Color("69bddb"),
		"butt": Color("143848"),
		"modulate": Color("a8d8ec"),
	},
	{
		"id": "rose",
		"label": "Rose",
		"tip": Color("ffe0ec"),
		"shaft": Color("ed91b8"),
		"butt": Color("4a1830"),
		"modulate": Color("f0b0cc"),
	},
	{
		"id": "chalk",
		"label": "Chalk",
		"tip": Color("f4f0e8"),
		"shaft": Color("c9b394"),
		"butt": Color("3a3428"),
		"modulate": Color("ddd4c4"),
	},
	{
		"id": "midnight",
		"label": "Midnight",
		"tip": Color("b8c8e0"),
		"shaft": Color("4a5a78"),
		"butt": Color("12161e"),
		"modulate": Color("6a7a98"),
	},
	{
		"id": "amber",
		"label": "Amber",
		"tip": Color("ffe8c0"),
		"shaft": Color("d4983c"),
		"butt": Color("3a2408"),
		"modulate": Color("e0b060"),
	},
]

const _CHILD_NAMES = [
	"Cue",
	"cue",
	"CueStick",
	"Stick",
	"cue_visual",
	"CueVisual",
	"CueSprite",
	"cue_sprite",
]


static func entries() -> Array:
	return CUES.duplicate(true)


static func ids() -> Array:
	var result: Array = []
	for entry in CUES:
		result.append(entry.id)
	return result


static func normalize(cue_id: String) -> String:
	var cleaned = cue_id.strip_edges().to_lower()
	if cleaned.is_empty() or cleaned.length() > MAX_ID_LENGTH:
		return DEFAULT_ID
	for entry in CUES:
		if entry.id == cleaned:
			return cleaned
	return DEFAULT_ID


static func is_known(cue_id: String) -> bool:
	var cleaned = cue_id.strip_edges().to_lower()
	if cleaned.is_empty() or cleaned.length() > MAX_ID_LENGTH:
		return false
	for entry in CUES:
		if entry.id == cleaned:
			return true
	return false


static func style(cue_id: String) -> Dictionary:
	var id = normalize(cue_id)
	for entry in CUES:
		if entry.id == id:
			return entry.duplicate(true)
	return CUES[0].duplicate(true)


static func tip_color(cue_id: String) -> Color:
	return style(cue_id).tip


static func swatch_color(cue_id: String) -> Color:
	var entry = style(cue_id)
	if entry.id == DEFAULT_ID:
		return entry.shaft
	return entry.modulate


static func cue_for_player(lobby: Dictionary, player_id: int, fallback: String = DEFAULT_ID) -> String:
	for player in lobby.get("players", []):
		if int(player.get("id", 0)) == player_id:
			return normalize(str(player.get("cue", fallback)))
	return normalize(fallback)


## Apply a catalog style to cue child nodes under a player-ball (or a bare cue root).
## Idempotent via together_cue_id meta, but re-tints when child modulate diverges (#22).
static func apply(cue_node: Node, cue_id: String) -> void:
	if cue_node == null or not is_instance_valid(cue_node):
		return
	var entry = style(cue_id)
	var targets: Array = _cue_targets(cue_node)
	var meta_match: bool = str(cue_node.get_meta("together_cue_id", "")) == entry.id
	if meta_match and _targets_match(targets, entry):
		return
	cue_node.set_meta("together_cue_id", entry.id)
	# Ball roots keep native modulate from table state; only tint cue chrome.
	if not _is_ball_root(cue_node) and targets.is_empty():
		_tint_canvas(cue_node, entry)
	for target in targets:
		_tint_canvas(target, entry)


static func _is_ball_root(node: Node) -> bool:
	return (
		node.get_node_or_null("CuePivot") != null
		or node.get_node_or_null("visuals") != null
		or node.get("is_player") != null
	)


static func _cue_targets(cue_node: Node) -> Array:
	var found: Array = []
	var seen: Dictionary = {}
	# CuePivot owns the native idle/aim fade; tinting it makes an idle cue opaque
	# and multiplies the Cue child's finish a second time. Shadows stay native too.
	var native_cue = cue_node.get_node_or_null("CuePivot/Cue")
	if native_cue != null:
		seen[native_cue] = true
		found.append(native_cue)
	for child_name in _CHILD_NAMES:
		var child = cue_node.get_node_or_null(child_name)
		if child != null and not seen.has(child):
			seen[child] = true
			found.append(child)
	for child in cue_node.get_children():
		if child is CanvasItem and _looks_like_cue(child.name) and not seen.has(child):
			seen[child] = true
			found.append(child)
	return found


static func _targets_match(targets: Array, entry: Dictionary) -> bool:
	if targets.is_empty():
		return false
	var expected: Color = entry.modulate if entry.id != DEFAULT_ID else Color.WHITE
	for target in targets:
		if not target is CanvasItem:
			continue
		var canvas := target as CanvasItem
		if entry.id == DEFAULT_ID:
			var base: Color = canvas.get_meta(
				"together_cue_base_modulate", expected
			)
			if not _same_rgb(canvas.modulate, base):
				return false
		elif not _same_rgb(canvas.modulate, expected):
			return false
	return true


static func _looks_like_cue(node_name: StringName) -> bool:
	var lower = String(node_name).to_lower()
	if "pivot" in lower or "shadow" in lower:
		return false
	return "cue" in lower or "stick" in lower


static func _same_rgb(left: Color, right: Color) -> bool:
	return left.r == right.r and left.g == right.g and left.b == right.b


static func _tint_canvas(node: Node, entry: Dictionary) -> void:
	if not node is CanvasItem:
		return
	var canvas := node as CanvasItem
	if not canvas.has_meta("together_cue_base_modulate"):
		canvas.set_meta("together_cue_base_modulate", canvas.modulate)
	var base_modulate: Color = canvas.get_meta("together_cue_base_modulate")
	var tint: Color = base_modulate if entry.id == DEFAULT_ID else entry.modulate
	tint.a = canvas.modulate.a
	if canvas.modulate != tint:
		canvas.modulate = tint
	if node is Line2D:
		var line := node as Line2D
		if not line.has_meta("together_cue_base_line_color"):
			line.set_meta("together_cue_base_line_color", line.default_color)
		var tip: Color = entry.tip if entry.id != DEFAULT_ID else line.get_meta("together_cue_base_line_color")
		if line.default_color != tip:
			line.default_color = tip
