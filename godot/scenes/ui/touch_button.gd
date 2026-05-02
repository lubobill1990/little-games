extends TouchScreenButton
## A `TouchScreenButton` configured to drive a semantic action via the
## InputManager pipeline. The `action` exported below is what `InputMap`
## also looks at, so pressing the on-screen button feeds the same engine
## as kbd / gamepad without a separate code path.
##
## Visibility / layout decisions live in the parent overlay; this node just
## knows about one action.

@export var action: StringName = &""

func _ready() -> void:
	if action != &"":
		action_name = action
