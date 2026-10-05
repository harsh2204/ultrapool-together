extends RefCounted
## Shared presentation for TOGETHER and expansion ability state (MOD-01..12).
## Draws host-authoritative display state only; never computes an ability.
## The playing table and the spectator view call the same drawing code with
## their own ball-position resolver, so both sides show identical indicators.
## Implemented, unmeasured: authored for the existing capture harness.

const CALL_COLOR = Color(0.65, 0.88, 1.0)
const BOUNTY_COLOR = Color(1.0, 0.76, 0.25)
const SET_COLOR = Color(0.93, 0.9, 0.76)
const SPREAD_COLOR = Color(0.86, 0.72, 1.0)
const PANEL_COLOR = Color(0.06, 0.06, 0.09, 0.72)
const FONT_SIZE = 13
const PANEL_LINE = 17.0
const MAX_BALLS = 128
const PHASE_NAMES = ["New", "Waxing", "Full", "Waning"]


class Overlay:
	extends Control
	## Owner-supplied draw callback; the Control itself stores no state.
	var draw_callback: Callable

	func _draw() -> void:
		if draw_callback.is_valid():
			draw_callback.call(self)


static func make_overlay(callback: Callable) -> Overlay:
	var overlay = Overlay.new()
	overlay.draw_callback = callback
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return overlay


## Cheap-to-compare identity of everything the drawing reads except ball
## positions. Callers add resolved positions, then redraw only on change.
static func signature(balls: Dictionary, expansion: Dictionary, extra: Array = []) -> Array:
	var result: Array = [balls.get("call", {}), balls.get("pending", false), extra]
	for ball in balls.get("balls", []):
		if ball is Dictionary:
			result.append([ball.get("id", 0), ball.get("alive", false), ball.get("marker", 0), ball.get("charge", 0), ball.get("kinds", [])])
	result.append(expansion.get("sets", {}))
	for ball in expansion.get("balls", []):
		if ball is Dictionary:
			result.append([ball.get("id", 0), ball.get("alive", false), ball.get("extra", {}), ball.get("kinds", [])])
	for pocket in balls.get("pockets", []):
		if pocket is Dictionary:
			result.append([pocket.get("index", -1), pocket.get("open", false)])
	return result


## [id, raw host position] pairs whose resolved position affects the drawing.
static func tracked_balls(balls: Dictionary, expansion: Dictionary) -> Array:
	var pairs: Array = []
	var seen: Dictionary = {}
	for state in [balls, expansion]:
		for ball in state.get("balls", []):
			if not ball is Dictionary or not ball.get("alive", false) or seen.has(ball.get("id", 0)):
				continue
			seen[ball.get("id", 0)] = true
			pairs.append([ball.get("id", 0), ball.get("position", Vector2.ZERO)])
			if pairs.size() >= MAX_BALLS:
				return pairs
	return pairs


## Draw every indicator. `transform` maps resolver space to canvas space,
## `resolve(id, raw_position)` returns a ball's current position in resolver space,
## `offset` is subtracted from raw host positions (pockets, fallbacks), and
## `name_for(id)` labels relay owners. `selected` / `choosing` feed the local
## called-shot selection ring (playing table only).
static func draw(canvas: CanvasItem, font: Font, transform: Transform2D, resolve: Callable,
		offset: Vector2, name_for: Callable, balls: Dictionary, expansion: Dictionary,
		selected: int = 0, choosing: bool = false) -> void:
	var called: Dictionary = balls.get("call", {})
	for pocket in balls.get("pockets", []):
		if not pocket is Dictionary or not pocket.get("open", false):
			continue
		var index: int = int(pocket.get("index", -1))
		if index < 0 or index >= 6:
			continue
		if index == int(called.get("pocket", -1)):
			canvas.draw_circle(transform * (pocket.position - offset), 21.0, CALL_COLOR, false, 2.0, true)
	var drawn = 0
	for ball in balls.get("balls", []):
		if not ball is Dictionary or not ball.get("alive", false):
			continue
		drawn += 1
		if drawn > MAX_BALLS:
			break
		var position: Vector2 = transform * resolve.call(ball.id, ball.position - offset)
		var kinds: Array = ball.get("kinds", [])
		if "TOGETHER_RELAY" in kinds and int(ball.get("marker", 0)) > 0:
			var color = Color.from_hsv(posmod(hash(str(ball.marker)), 360) / 360.0, 0.55, 1.0)
			canvas.draw_circle(position, 14.0, color, false, 1.5, true)
			caption(canvas, font, position + Vector2(17, 20), str(name_for.call(int(ball.marker))), color)
		if "TOGETHER_PATIENCE" in kinds:
			pips(canvas, position + Vector2(0, -19), int(ball.get("charge", 0)), 3, CALL_COLOR)
		if "TOGETHER_BOUNTY" in kinds:
			canvas.draw_circle(position, 13.0, BOUNTY_COLOR, false, 1.5, true)
			for axis in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
				canvas.draw_line(position + axis * 10, position + axis * 17, BOUNTY_COLOR, 1.5)
		if ball.id == int(called.get("ball", -1)) or (choosing and ball.id == selected):
			canvas.draw_circle(position, 17.0, CALL_COLOR, false, 1.5, true)
	drawn = 0
	for ball in expansion.get("balls", []):
		if not ball is Dictionary or not ball.get("alive", false):
			continue
		drawn += 1
		if drawn > MAX_BALLS:
			break
		var position: Vector2 = transform * resolve.call(ball.id, ball.position - offset)
		var extra: Dictionary = ball.get("extra", {})
		_draw_expansion_ball(canvas, position, extra)
	_draw_shared_panel(canvas, font, expansion.get("sets", {}))


static func _draw_expansion_ball(canvas: CanvasItem, position: Vector2, extra: Dictionary) -> void:
	var morph: Dictionary = extra.get("MORPH", {})
	if not morph.is_empty():
		if int(morph.get("form", 0)) == 1:
			canvas.draw_arc(position, 15.0, 0.0, TAU, 24, SET_COLOR, 1.5, true)
		if bool(morph.get("marked", false)):
			canvas.draw_circle(position + Vector2(0, -21), 2.5, SET_COLOR)
		pips(canvas, position + Vector2(0, 21), int(morph.get("charge", 0)), 3, SET_COLOR)
	var tarot: Dictionary = extra.get("TAROT", {})
	if not tarot.is_empty():
		var up: bool = bool(tarot.get("upright", true))
		var tip = position + Vector2(0, -24 if up else -14)
		var base_y = -14 if up else -24
		canvas.draw_colored_polygon(
			PackedVector2Array([tip, position + Vector2(-4, base_y), position + Vector2(4, base_y)]),
			SPREAD_COLOR
		)
		if bool(tarot.get("in_spread", false)):
			canvas.draw_arc(position, 16.0, 0.0, TAU, 24, SPREAD_COLOR, 1.5, true)
		pips(canvas, position + Vector2(0, 21), int(tarot.get("charge", 0)), 3, SPREAD_COLOR)
	var zodiac: Dictionary = extra.get("ZODIAC", {})
	if not zodiac.is_empty():
		pips(canvas, position + Vector2(0, 21), int(zodiac.get("charge", 0)), 2, SET_COLOR)
	var relic: Dictionary = extra.get("RELIC", {})
	if not relic.is_empty():
		pips(canvas, position + Vector2(0, 21), int(relic.get("dig", 0)), 3, SET_COLOR)


static func _draw_shared_panel(canvas: CanvasItem, font: Font, sets: Dictionary) -> void:
	var lines: Array = shared_lines(sets)
	if lines.is_empty():
		return
	var width = 0.0
	for line in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var height = lines.size() * PANEL_LINE + 10
	# Bottom-left, above the status ribbon / hint row, clear of the native HUD.
	var origin = Vector2(16, maxf(canvas.get_viewport_rect().size.y - height - 72, 0.0))
	canvas.draw_rect(Rect2(origin, Vector2(width + 16, height)), PANEL_COLOR)
	var y = origin.y + PANEL_LINE
	for line in lines:
		canvas.draw_string(font, Vector2(origin.x + 8, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, SET_COLOR)
		y += PANEL_LINE


## One short ASCII line per enabled set with shared state. Pure function.
static func shared_lines(sets: Dictionary) -> Array:
	var lines: Array = []
	if sets.has("PHASES"):
		var phase: Dictionary = sets.PHASES
		var index: int = clampi(int(phase.get("phase", 0)), 0, PHASE_NAMES.size() - 1)
		lines.append("PHASES  %s moon  -  Silent x%d" % [PHASE_NAMES[index], int(phase.get("silent", 0))])
	if sets.has("TIDE"):
		lines.append("TIDE  height %d/3" % int(sets.TIDE.get("height", 0)))
	if sets.has("MORPH"):
		var morph: Dictionary = sets.MORPH
		lines.append("MORPH  changes %d%s" % [int(morph.get("form_changes", 0)), "  -  Prime ready" if bool(morph.get("prime", false)) else ""])
	if sets.has("RELIC"):
		var relic: Dictionary = sets.RELIC
		var temps = relic.get("idol_temps", 0)
		var temps_text = str(temps.size()) if temps is Array or temps is Dictionary else str(temps)
		lines.append("RELIC  digs %s  -  Idol %s" % ["persist" if bool(relic.get("persist", false)) else "clear on pot", temps_text])
	if sets.has("TAROT"):
		var names: Array = []
		for kind in sets.TAROT.get("spread", []):
			names.append(pretty_kind(str(kind)))
		lines.append("TAROT  spread: %s" % (", ".join(names) if not names.is_empty() else "none"))
	if sets.has("ZODIAC"):
		var parts: Array = []
		var align = sets.ZODIAC.get("align", {})
		if align is Dictionary:
			for key in align:
				parts.append("%s %s" % [pretty_kind(str(key)), str(align[key])])
		lines.append("ZODIAC  %s" % (", ".join(parts) if not parts.is_empty() else "no alignment"))
	return lines


static func pretty_kind(kind: String) -> String:
	var text = kind
	var underscore = text.find("_")
	if underscore >= 0:
		text = text.substr(underscore + 1)
	return text.replace("_", " ").capitalize()


static func pips(canvas: CanvasItem, center: Vector2, count: int, maximum: int, color: Color) -> void:
	var shown = clampi(count, 0, maximum)
	for pip in range(shown):
		canvas.draw_circle(center + Vector2((pip - (shown - 1) * 0.5) * 6.0, 0), 2.0, color)


static func caption(canvas: CanvasItem, font: Font, position: Vector2, text: String, color: Color) -> void:
	canvas.draw_string_outline(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, Color.BLACK)
	canvas.draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
