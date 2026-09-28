extends RefCounted
## Native cue sprite replacement. PERF-018/027: decode a bounded texture cache at
## startup, retain native geometry once per player, and write only on cue changes.

const CueModels = preload("cue_models.gd")
const CueCatalog = preload("cue_catalog.gd")
const ORIGINAL_META = "together_cue_original_sprite"
const APPLIED_META = "together_cue_visual_signature"
static var _warmed = false
static var _textures: Dictionary = {}


static func warm(directory: String) -> void:
	if _warmed:
		return
	_warmed = true
	for model in CueModels.entries():
		var path: String = directory.path_join(model.asset)
		var image = Image.new()
		if not FileAccess.file_exists(path) or image.load(path) != OK:
			continue
		var used: Rect2i = image.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		_textures[model.id] = ImageTexture.create_from_image(image.get_region(used))


static func texture(model_id: String) -> Texture2D:
	return _textures.get(model_id)


static func remember(player: Node) -> void:
	var cue = _sprite(player)
	if cue != null:
		_remember(cue)


static func apply(player: Node, model_id: String, finish_id: String) -> void:
	var cue = _sprite(player)
	if cue == null:
		return
	_remember(cue)
	var original: Dictionary = cue.get_meta(ORIGINAL_META)
	var finish: Dictionary = CueCatalog.style(finish_id)
	var tint: Color = original.self_modulate
	if finish.id != CueCatalog.DEFAULT_ID:
		tint *= finish.modulate
	# Native input owns Cue alpha (idle hide / active aim) independently of finish.
	# Preserve it so applying a finish never revives a hidden rest-pose stick.
	var inherited: Color = original.modulate
	inherited.a = cue.modulate.a
	var art: Texture2D = texture(model_id) if model_id != CueModels.DEFAULT_ID else null
	var signature = [model_id, finish.id, art]
	if (
		cue.get_meta(APPLIED_META, []) == signature
		and cue.modulate == inherited
		and cue.self_modulate == tint
		and cue.texture == (art if art != null else original.texture)
	):
		return
	if art == null:
		_restore_geometry(cue, original)
	else:
		var rect: Rect2 = original.rect
		var ratio: float = rect.size.x / art.get_width()
		if ratio <= 0.0:
			return
		cue.texture = art
		cue.hframes = 1
		cue.vframes = 1
		cue.frame = 0
		cue.region_enabled = false
		cue.centered = false
		# Native Cue lies behind the ball and points right. New art points left.
		cue.flip_h = true
		cue.flip_v = false
		cue.scale = original.scale * ratio
		_restore_shadow(original, ratio)
		# Keep the original right-hand tip and vertical center in sprite-local
		# space. Native scripts/animations remain in charge of position/rotation.
		cue.offset = Vector2(
			(rect.position.x + rect.size.x) / ratio - art.get_width(),
			rect.get_center().y / ratio - art.get_height() * 0.5
		)
	# Tint only this sprite: the parent keeps its native aiming fade and the
	# existing shadow keeps its own transform. self_modulate prevents multiplying
	# the finish onto the shadow as an inherited parent tint.
	if cue.modulate != inherited:
		cue.modulate = inherited
	if cue.self_modulate != tint:
		cue.self_modulate = tint
	cue.set_meta(APPLIED_META, signature)


static func restore(player: Node) -> void:
	var cue = _sprite(player)
	if cue == null or not cue.has_meta(ORIGINAL_META):
		return
	var original: Dictionary = cue.get_meta(ORIGINAL_META)
	_restore_geometry(cue, original)
	cue.modulate = original.modulate
	cue.self_modulate = original.self_modulate
	cue.remove_meta(APPLIED_META)


static func _sprite(player: Node) -> Sprite2D:
	if not is_instance_valid(player):
		return null
	return player.get_node_or_null("CuePivot/Cue") as Sprite2D


static func _remember(cue: Sprite2D) -> void:
	if cue.has_meta(ORIGINAL_META):
		return
	var shadow = cue.get_node_or_null("CueShadow") as Node2D
	cue.set_meta(
		ORIGINAL_META,
		{
			"texture": cue.texture,
			"rect": cue.get_rect(),
			"scale": cue.scale,
			"offset": cue.offset,
			"centered": cue.centered,
			"flip_h": cue.flip_h,
			"flip_v": cue.flip_v,
			"hframes": cue.hframes,
			"vframes": cue.vframes,
			"frame": cue.frame,
			"region_enabled": cue.region_enabled,
			"region_rect": cue.region_rect,
			"modulate": cue.modulate,
			"self_modulate": cue.self_modulate,
			"shadow": weakref(shadow) if shadow != null else null,
			"shadow_transform": shadow.transform if shadow != null else Transform2D.IDENTITY,
		}
	)


static func _restore_geometry(cue: Sprite2D, original: Dictionary) -> void:
	cue.texture = original.texture
	cue.hframes = original.hframes
	cue.vframes = original.vframes
	cue.frame = original.frame
	cue.region_enabled = original.region_enabled
	cue.region_rect = original.region_rect
	cue.centered = original.centered
	cue.flip_h = original.flip_h
	cue.flip_v = original.flip_v
	cue.scale = original.scale
	cue.offset = original.offset
	_restore_shadow(original)


static func _restore_shadow(original: Dictionary, parent_scale_ratio: float = 1.0) -> void:
	var reference = original.get("shadow")
	var shadow = reference.get_ref() if reference is WeakRef else null
	if not is_instance_valid(shadow):
		return
	var transform: Transform2D = original.shadow_transform
	# CueShadow is a child of Cue in the native scene. Counter the texture-size
	# scale so its original native silhouette never grows or shifts with new art.
	shadow.transform = Transform2D(
		transform.x / parent_scale_ratio,
		transform.y / parent_scale_ratio,
		transform.origin / parent_scale_ratio
	)
