class_name ArtPalette
extends RefCounted
## The one colour set every pixel sprite in Lastlight is drawn from.
##
## Cohesion is what separates art that reads as a game from art that reads as a
## pile of assets, and cohesion at this scale is a palette rule, not a drawing
## skill: if the ranger's leather and a camp hut's timber are literally the same
## three browns, they look like they belong to one world even when the drawing
## underneath is rough. So there is exactly one palette, it is small, and no
## sprite is allowed a colour that is not in it.
##
## Every colour is a single character, because that is what makes the art data
## in `art_sprites.gd` readable as a picture in the source file and diffable in
## git. Ramps are three steps — dark / mid / light — keyed lower-case for the
## light step, upper-case for the mid, and a third letter for the dark, so a
## ramp is always "the same letter, shouting or not".
##
## Lighting convention: the key light is TOP-LEFT on every sprite. Light steps
## go up and left, dark steps down and right. Break it and the sprite will look
## wrong next to its neighbours even if nobody can say why.

## Character -> RGBA hex. Eight digits where alpha matters (the drop shadow).
## `.` is reserved for "leave transparent" and is not in this table.
const COLORS := {
	# Ink. Outlines are `0`; `1` is the softened outline used where a shape
	# meets light, and `2` is the darkest usable fill (cloth in deep shadow).
	"0": "0d0b12",
	"1": "1c1a26",
	"2": "2e2b3d",

	# Living skin.
	"s": "f2c9a0", "S": "d9a276", "k": "a06e4c",

	# Dead skin. Deliberately a green-grey ramp rather than a desaturated skin
	# ramp — at 32 px the only reliable way to say "this one is not alive".
	"r": "8fae72", "R": "6b8a55", "e": "46603a",

	# Bone, cloth-that-was-white, camp ruins.
	"b": "ede4cf", "B": "c9bda1", "n": "9a8d72",

	# Wood, leather, rope.
	"w": "a4713f", "W": "7a5029", "x": "4e321a",

	# Green cloth and foliage (the Ranger's ramp).
	"g": "5f9e4a", "G": "3e7d3a", "h": "27512a",

	# Steel, stone, walls (the Paladin's ramp).
	"l": "cdd6e0", "L": "97a3b5", "d": "5c6678",

	# Gold: Paladin trim and Radiant Essence. Used sparingly on purpose — it is
	# the game's "this is valuable" colour and spending it on decoration spends
	# the signal too.
	"y": "ffd97a", "Y": "e0a63c", "u": "9c6b1e",

	# Arcane violet (the Mage's ramp, and arcane bolts).
	"v": "c49bf0", "V": "8f5fd4", "m": "563093",

	# Cold blue: Bright Essence, frost, the night tint's own colour.
	"c": "9fe8f5", "C": "4fb8d9", "j": "23698f",

	# Blood and marauder cloth.
	"f": "e2604b", "F": "b03327", "q": "6d1a18",

	# Fire and embers.
	"o": "ffb05c", "O": "f0722c", "p": "a53c14",

	# Bare earth, dry grass, dirt decals.
	"t": "7d7a5e", "T": "5b5943", "z": "3a3a2c",

	# Pure white. Specular pips and nothing else.
	"#": "ffffff",

	# Soft blacks for the ground shadow, which is a texture rather than a
	# drawing and needs real alpha rather than a dark colour.
	",": "0000002b", ";": "00000055", ":": "00000085",
}

## Reserved in art data: this pixel is not drawn at all.
const TRANSPARENT := "."


## The colour a single art-data character stands for. Unknown characters are a
## mistake in the art rather than something to render, so they come back as
## magenta and shout — a sprite with a typo should be impossible to miss in a
## frame, not quietly a slightly wrong brown.
static func color_of(key: String) -> Color:
	if not COLORS.has(key):
		push_warning("[Art] Unknown palette key '%s' — drawn as magenta." % key)
		return Color.MAGENTA
	return Color.html(COLORS[key])
