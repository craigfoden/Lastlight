class_name Camp
extends Node3D
## One guarded site out in the wilds: a garrison standing in a ruin, and a
## locked cache at the middle of it. Clearing the garrison unlocks the cache;
## looting the cache pays the whole reward into the shared pool at once.
##
## **Where the split falls.** WorldGen owns the *layout* — it stamps the ruined
## walls, reserves the courtyard and creates this node, all from the baked seed,
## identically on every peer and with nothing synced (the same contract the
## resource scatter has always had). Camp owns the *state*, which cannot work
## that way: guards are Enemies, and Enemies are host-simulated. So the host
## spawns the garrison through the WaveDirector's spawner (the one place an
## Enemy is ever created), counts it down as guards are killed, and broadcasts
## the tally. Clients never simulate a guard; they are told how many are left.
##
## The cache is a child rather than a sibling so its NodePath is
## `.../WorldGen/Camp_<n>/Cache` — deterministic on every peer, which is what
## its inherited harvest RPCs resolve against (see GOTCHAS on WorldGen naming).

const LootCacheScene := preload("res://scenes/world/loot_cache.tscn")

## Fired on the host the moment the last guard falls.
signal cleared

var type: CampType
## Guards still standing. Host-authoritative, mirrored to clients by _sync_guards.
var guards_remaining := 0

var _wave_director: WaveDirector
var _cache: LootCache
var _cache_visual: PackedScene


## Called by WorldGen before add_child, on every peer.
func configure(camp_type: CampType, cache_visual: PackedScene) -> void:
	type = camp_type
	_cache_visual = cache_visual


func _ready() -> void:
	add_to_group("camps")
	_cache = LootCacheScene.instantiate() as LootCache
	_cache.name = "Cache"
	_cache.material_type = _headline_material()
	_cache.visual_scene = _cache_visual
	# One interact empties it: the cache is a reward, not a job of work.
	_cache.starting_amount = 1
	_cache.yield_per_harvest = 1
	_cache.loot = type.loot.duplicate()
	_cache.camp_display_name = type.display_name
	add_child(_cache)
	# Locked until told otherwise, so a client that has not yet received the
	# tally shows a sealed cache rather than a lootable one.
	_cache.set_guards_remaining(maxi(type.guard_count, 0))


## Injected by the Game scene on every peer once the WaveDirector is wired up
## (it needs the build grid and the tower, which are set in Game._ready — this
## is why the garrison cannot be posted from WorldGen's own _ready).
func setup(wave_director: WaveDirector) -> void:
	_wave_director = wave_director


## Host only, and called explicitly by the Game scene from its *host* branch
## rather than guarded with `multiplayer.is_server()` here. A joining client has
## no multiplayer peer yet while Game._ready runs, and a peerless
## `multiplayer.is_server()` answers TRUE — so a self-guarded version had every
## client posting its own garrison into a spawner it has no authority over (see
## GOTCHAS, session 15).
##
## Guards are posted evenly around the courtyard. The ring is inside the
## footprint, whose interior WorldGen leaves clear, so a post can never land in
## a wall — that is the contract between the two halves of a camp.
func host_post_garrison() -> void:
	var posted := 0
	for i in type.guard_count:
		var angle := float(i) * TAU / float(maxi(type.guard_count, 1))
		var post := global_position \
				+ Vector3(type.guard_post_radius, 0, 0).rotated(Vector3.UP, angle)
		var guard := _wave_director.host_spawn_guard(
				type.guard_type, post, global_position, type.guard_leash)
		if guard == null:
			continue
		# Killed, not despawned: Enemy only emits `died` on a real death, so a
		# dawn wipe or a run-end clear can never read as "the players cleared it".
		guard.died.connect(_on_guard_died)
		posted += 1
	guards_remaining = posted
	_sync_guards.rpc(posted)
	print("[Camp] %s garrisoned at %v with %d %s"
			% [type.id, global_position, posted,
			type.guard_type.id if type.guard_type != null else &"<none>"])


## Host only: bring a late joiner's cache lock up to date. Guards themselves
## replicate through the enemy spawner like every other monster.
func host_send_snapshot(peer_id: int) -> void:
	_sync_guards.rpc_id(peer_id, guards_remaining)


func is_cleared() -> bool:
	return guards_remaining <= 0


func _on_guard_died() -> void:
	if not multiplayer.is_server():
		return
	guards_remaining = maxi(guards_remaining - 1, 0)
	_sync_guards.rpc(guards_remaining)
	if guards_remaining == 0:
		cleared.emit()


# The game root's authority is the server and so is this node's, so plain
# "authority" is right here (unlike anything hanging off a player node, whose
# authority is the owning client — see GOTCHAS).
@rpc("authority", "call_local", "reliable")
func _sync_guards(remaining: int) -> void:
	guards_remaining = remaining
	if _cache != null:
		_cache.set_guards_remaining(remaining)
	if remaining == 0:
		print("[Camp] %s at %v cleared - the cache is open" % [type.id, global_position])


# What the cache is *for*, used as its map colour: the rarest thing it holds,
# where rarity is Materials.ALL's own display order (wood first, radiant last).
func _headline_material() -> MaterialType:
	var best: MaterialType = null
	var best_rank := -1
	for material_id: StringName in type.loot:
		var material := Materials.by_id(material_id)
		if material == null:
			continue
		var rank := Materials.ALL.find(material)
		if rank > best_rank:
			best_rank = rank
			best = material
	return best if best != null else Materials.ALL[0]
