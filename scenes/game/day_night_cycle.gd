class_name DayNightCycle
extends Node
## Drives the day/night loop. The host advances time authoritatively and a
## MultiplayerSynchronizer pushes (day_number, phase, time_in_phase) to clients
## a few times per second; clients advance time locally in between so the clock
## and lighting stay smooth ("dead reckoning" — drift is corrected by each sync).

signal phase_changed(new_phase: Phase)

enum Phase { DAY, NIGHT }

## Pacing (seconds). Targets from the design doc: ~5 min days, ~3 min nights,
## 7 days per run (~60 min). All tunable.
@export var day_length := 300.0
@export var night_length := 180.0
@export var final_day := 7

## Ambient colors the world lighting lerps between.
@export var day_color := Color(1.0, 1.0, 1.0)
@export var night_color := Color(0.16, 0.17, 0.30)
## Seconds spent fading into the next phase's color before the boundary.
@export var transition_time := 12.0

var day_number := 1
var time_in_phase := 0.0
var phase := Phase.DAY:
	set(value):
		if phase == value:
			return
		phase = value
		phase_changed.emit(value)
		print("[DayNight] Day %d: %s begins" % [day_number, Phase.keys()[value]])


func _process(delta: float) -> void:
	time_in_phase += delta
	if not multiplayer.is_server():
		# Clients never flip the phase themselves — they wait for the sync.
		time_in_phase = minf(time_in_phase, phase_length())
		return
	if time_in_phase >= phase_length():
		_advance_phase()


func phase_length() -> float:
	return day_length if phase == Phase.DAY else night_length


func time_remaining() -> float:
	return maxf(phase_length() - time_in_phase, 0.0)


## Color for the CanvasModulate right now. Fades toward the next phase's color
## as the boundary approaches, so dusk/dawn roll in instead of snapping.
func ambient_color() -> Color:
	var current := day_color if phase == Phase.DAY else night_color
	var next := night_color if phase == Phase.DAY else day_color
	var fade := clampf(time_remaining() / transition_time, 0.0, 1.0)
	return next.lerp(current, fade)


func _advance_phase() -> void:
	time_in_phase = 0.0
	if phase == Phase.DAY:
		phase = Phase.NIGHT
	else:
		day_number += 1
		phase = Phase.DAY
