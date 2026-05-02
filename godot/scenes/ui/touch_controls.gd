extends CanvasLayer
## On-screen touch overlay: D-pad + 4 action buttons. Default-hidden on
## desktop / web-with-mouse; default-visible on mobile when no gamepad
## is connected. Caller can `add_child` this to any game scene.
##
## Visibility rules (see issue #2 truth table):
##   - mobile + no gamepad → visible after first input
##   - mobile + gamepad    → hidden
##   - desktop / web-mouse → hidden
##
## The overlay starts hidden and a game can show it via `set_visible(true)`.

@export var force_visible: bool = false

func _ready() -> void:
	visible = force_visible or _default_visible()

func _default_visible() -> bool:
	if force_visible:
		return true
	if not _is_mobile():
		return false
	return Input.get_connected_joypads().is_empty()

func _is_mobile() -> bool:
	var name := OS.get_name()
	return name == "Android" or name == "iOS"
