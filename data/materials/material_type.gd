class_name MaterialType
extends Resource
## One gatherable material (wood, stone, an essence tier...).
## Data-driven: adding a material = adding a .tres file, no code changes.

## Stable identifier used in the shared pool dictionary and save data.
## Never rename an id once shipped — display_name is the safe-to-change one.
@export var id: StringName

@export var display_name: String

## Shown in the HUD; a colored chip until real icons arrive.
@export var hud_color: Color = Color.WHITE

## Optional icon; placeholder art phase leaves this empty and uses hud_color.
@export var icon: Texture2D
