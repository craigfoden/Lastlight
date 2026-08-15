extends SceneTree
## Entry point for the art build. Deliberately a `--script` run rather than a
## dev CLI arg on the game: generating art has nothing to do with playing, and
## routing it through `game.gd` would mean booting a world, a network peer and
## a world-gen pass to write some PNGs.
##
##   godot --headless --path <project> --script res://tools/art/generate_art.gd
##
## Exits non-zero when the art is malformed so a build script can trust it.


func _initialize() -> void:
	quit(0 if ArtGenerator.generate_all() >= 0 else 1)
