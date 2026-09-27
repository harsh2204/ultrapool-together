extends Panel
## Embedded Together options overlay (#19).
## Replaces PopupPanel (a Window) so the panel stays inside the lobby Control tree
## under the CRT CanvasLayer. Without gui_embed_subwindows, a PopupPanel can draw
## above the CRT pass or as an OS-level window; fixtures previously forced embed
## only for screenshots. Keep popup()/popup_hide API for callers and Capture-Screens.

signal popup_hide


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)


func popup(_rect: Rect2i = Rect2i()) -> void:
	show()
	move_to_front()


func _on_visibility_changed() -> void:
	if not visible:
		popup_hide.emit()
