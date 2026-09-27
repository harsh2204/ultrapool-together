extends RefCounted
## Vanilla-safe cue cosmetics: recolors / parametric tints of the native cue look.
## No new art pipeline. Default id restores native appearance (identity modulate).
## Refs #20. Host and guest both call apply(); guest replica wiring may be coordinator-owned.

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


## Apply a catalog style to a cue root or player-ball subtree.
## Idempotent via together_cue_id meta. Restores native look for DEFAULT_ID.
## Safe when the native cue node tree is missing — no-ops beyond root modulate.
static func apply(cue_node: Node, cue_id: String) -> void:
	if cue_node == null or not is_instance_valid(cue_node):
		return
	var entry = style(cue_id)
	if str(cue_node.get_meta("together_cue_id", "")) == entry.id:
		return
	cue_node.set_meta("together_cue_id", entry.id)
	_tint_canvas(cue_node, entry)
	for child_name in _CHILD_NAMES:
		var child = cue_node.get_node_or_null(child_name)
		if child != null:
			_tint_canvas(child, entry)
	for child in cue_node.get_children():
		if child is CanvasItem and _looks_like_cue(child.name):
			_tint_canvas(child, entry)


static func _looks_like_cue(node_name: StringName) -> bool:
	var lower = String(node_name).to_lower()
	return "cue" in lower or "stick" in lower


static func _tint_canvas(node: Node, entry: Dictionary) -> void:
	if not node is CanvasItem:
		return
	var canvas := node as CanvasItem
	if not canvas.has_meta("together_cue_base_modulate"):
		canvas.set_meta("together_cue_base_modulate", canvas.modulate)
	if not canvas.has_meta("together_cue_base_self_modulate"):
		canvas.set_meta("together_cue_base_self_modulate", canvas.self_modulate)
	var base_modulate: Color = canvas.get_meta("together_cue_base_modulate")
	var base_self: Color = canvas.get_meta("together_cue_base_self_modulate")
	if entry.id == DEFAULT_ID:
		if canvas.modulate != base_modulate:
			canvas.modulate = base_modulate
		if canvas.self_modulate != base_self:
			canvas.self_modulate = base_self
	else:
		var tint: Color = entry.modulate
		if canvas.modulate != tint:
			canvas.modulate = tint
		# Keep self_modulate at base so nested sprites do not double-tint.
		if canvas.self_modulate != base_self:
			canvas.self_modulate = base_self
	if node is Line2D:
		var line := node as Line2D
		if not line.has_meta("together_cue_base_line_color"):
			line.set_meta("together_cue_base_line_color", line.default_color)
		var tip: Color = entry.tip if entry.id != DEFAULT_ID else line.get_meta("together_cue_base_line_color")
		if line.default_color != tip:
			line.default_color = tip
