extends Node
## Project-wide constants and metadata.
##
## Lightweight autoload so other tasks have a stable place to add cross-cutting
## info (build number, feature flags, etc.) without touching `project.godot`.

const PROJECT_NAME := "little-games"
const VERSION := "0.1.0-bootstrap"

func _ready() -> void:
	print("[%s] %s starting" % [PROJECT_NAME, VERSION])
