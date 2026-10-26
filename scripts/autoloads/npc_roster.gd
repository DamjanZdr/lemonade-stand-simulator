extends Node
## NpcRoster — fixed roster of named NPCs loaded from
## resources/data/npc_roster.txt. Each entry is a complete appearance
## definition; to change an NPC's look, edit its line in that file —
## no code changes needed.
##
## Spawn selection is rarity-weighted and never returns an id that is
## currently alive (no same-name duplicates on screen at once).

const ROSTER_PATH := "res://resources/data/npc_roster.txt"

## Relative spawn weight per rarity tier — a tier's chance is
## weight / total-weight across tiers that still have free names.
const RARITY_WEIGHTS: Dictionary = { "common": 60.0, "community": 25.0, "rare": 10.0, "elite": 5.0 }

## Optional name-label tint per rarity (used by the NPC name tag).
const RARITY_NAME_COLORS: Dictionary = {
	"common": Color(1.0, 1.0, 1.0),
	"community": Color(0.55, 0.85, 1.0),
	"rare": Color(0.80, 0.55, 1.0),
	"elite": Color(1.0, 0.80, 0.20),
}

## Tip as a fraction of the sale, once a customer is a regular
## (10 perfect cups).
const RARITY_TIP_PCT: Dictionary = {
	"common": 0.20,
	"community": 0.40,
	"rare": 0.70,
	"elite": 1.00,
}

var _entries: Array[Dictionary] = []
var _by_tier: Dictionary = { }


func _ready() -> void:
	_load_roster()


func size() -> int:
	return _entries.size()


func has_id(npc_id: int) -> bool:
	return npc_id >= 0 and npc_id < _entries.size()


func get_entry(npc_id: int) -> Dictionary:
	if not has_id(npc_id):
		return { }
	return _entries[npc_id]


## Looks up a roster id by name — exact case-insensitive match first,
## then substring ("dani" finds DaniDev). -1 when nothing matches.
func find_id_by_name(query: String) -> int:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return -1
	for i in _entries.size():
		if str(_entries[i].get("name", "")).to_lower() == q:
			return i
	for i in _entries.size():
		if str(_entries[i].get("name", "")).to_lower().contains(q):
			return i
	return -1


## Picks a roster id that is not in [alive_ids]. -1 when the roster is
## empty or every name is currently alive (caller falls back to random).
func pick_id(alive_ids: Dictionary) -> int:
	var available_by_tier: Dictionary = { }
	var total := 0.0
	for tier in RARITY_WEIGHTS:
		var free_ids: Array = _by_tier.get(tier, []).filter(
			func(id):
				return not alive_ids.has(id),
		)
		if free_ids.is_empty():
			continue
		available_by_tier[tier] = free_ids
		total += RARITY_WEIGHTS[tier]
	if total <= 0.0:
		return -1
	var roll := randf() * total
	for tier in available_by_tier:
		roll -= RARITY_WEIGHTS[tier]
		if roll <= 0.0:
			var ids: Array = available_by_tier[tier]
			return int(ids[randi() % ids.size()])
	var last_ids: Array = available_by_tier.values()[-1]
	return int(last_ids[randi() % last_ids.size()])


func _load_roster() -> void:
	_entries.clear()
	_by_tier.clear()
	var file := FileAccess.open(ROSTER_PATH, FileAccess.READ)
	if file == null:
		push_warning("NpcRoster: roster file missing at %s" % ROSTER_PATH)
		return
	var tier := ""
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("["):
			tier = line.trim_prefix("[").trim_suffix("]").to_lower()
			continue
		var parts := line.split("|")
		if parts.size() != 10 or tier.is_empty():
			push_warning("NpcRoster: skipping malformed line '%s'" % line)
			continue
		var fields: Array[String] = []
		for p in parts:
			fields.append(p.strip_edges())
		var id := _entries.size()
		_entries.append(
			{
				"id": id,
				"name": fields[0],
				"rarity": tier,
				"gender": fields[1],
				"hair": int(fields[2]),
				"hair_color": fields[3],
				"skin": fields[4],
				"shirt": fields[5],
				"pants": fields[6],
				"shoes": fields[7],
				"height": float(fields[8]),
				"head": float(fields[9]),
			}
		)
		_by_tier.get_or_add(tier, []).append(id)
	if _entries.is_empty():
		push_warning("NpcRoster: no NPC entries loaded")
	else:
		GameLog.log(
			"[NpcRoster] Loaded %d NPCs: %s"
			% [
				_entries.size(),
				str(
					_by_tier.keys().map(
						func(t):
							return "%s=%d" % [t, _by_tier[t].size()],
					)
				),
			]
		)
