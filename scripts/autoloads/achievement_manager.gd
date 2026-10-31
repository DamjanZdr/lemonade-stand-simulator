extends Node
## Steam achievement unlocker.
## Listens to per-stand progress and calls Steam.setAchievement() when a
## threshold is crossed. Achievements are per-Steam-account, so every peer
## checks its own assigned stand and unlocks for itself.

const ACH_START_SPENDING := "ACH_START_SPENDING"
const ACH_SQUEEZE_EM := "ACH_SQUEEZE_EM"
const ACH_FIRST_CUSTOMER := "ACH_FIRST_CUSTOMER"
const ACH_DOUBLE_DIGITS := "ACH_DOUBLE_DIGITS"
const ACH_SALES_EXPERT := "ACH_SALES_EXPERT"
const ACH_ENTREPRENEUR := "ACH_ENTREPRENEUR"
const ACH_HYDRATING_THE_CITY := "ACH_HYDRATING_THE_CITY"
const ACH_POCKET_CHANGE := "ACH_POCKET_CHANGE"
const ACH_SPARE_MONEY := "ACH_SPARE_MONEY"
const ACH_DO_YOU_HAVE_A_PERMIT := "ACH_DO_YOU_HAVE_A_PERMIT"
const ACH_ROYAL_FLUSH := "ACH_ROYAL_FLUSH"
const ACH_HAPPY_BEGINNING := "ACH_HAPPY_BEGINNING"
const ACH_GOLDEN_SHOWER := "ACH_GOLDEN_SHOWER"
const ACH_LEMONADEER := "ACH_LEMONADEER"
const ACH_HE_WAS_HERE := "ACH_HE_WAS_HERE"
const ACH_HANDS_FREE := "ACH_HANDS_FREE"
const ACH_ALL_IN_ONE := "ACH_ALL_IN_ONE"
const ACH_GOTTA_SQUEEZE_EM_ALL := "ACH_GOTTA_SQUEEZE_EM_ALL"
const ACH_CLEAN_NEIGHBORHOOD := "ACH_CLEAN_NEIGHBORHOOD"
const ACH_SQUEAKY_CLEAN := "ACH_SQUEAKY_CLEAN"
const ACH_ECOLOGIST := "ACH_ECOLOGIST"
const ACH_FIRST_DISCOVERY := "ACH_FIRST_DISCOVERY"
const ACH_MASTER_OF_ONE := "ACH_MASTER_OF_ONE"
const ACH_MASTER_OF_ALL_TRADES := "ACH_MASTER_OF_ALL_TRADES"
const ACH_ACQUAINTANCE := "ACH_ACQUAINTANCE"
const ACH_EXTROVERT := "ACH_EXTROVERT"
const ACH_FRIEND_TO_ALL := "ACH_FRIEND_TO_ALL"
const ACH_COUPLE_OF_REGULARS := "ACH_COUPLE_OF_REGULARS"
const ACH_FAN_BASE := "ACH_FAN_BASE"
const ACH_NEIGHBORHOOD_FAVORITE := "ACH_NEIGHBORHOOD_FAVORITE"
const ACH_ROCKSTAR := "ACH_ROCKSTAR"

## Achievements already unlocked this session so we don't spam Steam.
var _unlocked: Dictionary = { }

## Per-stand stat baselines recorded when a client joins mid-game —
## thresholds are checked against progress made *since* the baseline so a
## late joiner doesn't instantly inherit every achievement the host
## already earned before they were present.
var _stand_baselines: Dictionary = { }


func set_stand_baseline(stand: StandUnit) -> void:
	if stand == null:
		return
	_stand_baselines[stand.get_instance_id()] = {
		"spent": stand.total_money_spent,
		"cups": stand.total_cups_sold,
		"sales": stand.total_money_earned_from_sales,
		"happy": stand.customers_served_happy,
		"pressed": stand.total_fruit_pressed,
		"perfect": stand.perfect_recipes_set.keys(),
		"trash": _trash_thrown(stand),
		"machine_pitchers": _machine_pitchers(stand, ""),
		"fruitomatic_pitchers": _machine_pitchers(stand, "fruitomatic"),
		"pressed_fruits": _pressed_fruits(stand).keys(),
		"npcs_met": stand.get_npc_collection().size(),
		"regulars": _regulars_count(stand),
		"claimed_levels": _claimed_levels(stand),
		"full_branches": _full_branches_count(stand),
	}


## lifetime_stats counters — the whole dict syncs and saves with the
## stand, so achievement inputs persist across sessions and peers.
func _trash_thrown(stand: StandUnit) -> int:
	return int(stand.lifetime_stats.get("trash_thrown", 0))


func _machine_pitchers(stand: StandUnit, machine_type: String) -> int:
	var m: Dictionary = stand.lifetime_stats.get("machine_pitchers", { })
	if machine_type != "":
		return int(m.get(machine_type, 0))
	var total := 0
	for k in m:
		total += int(m[k])
	return total


func _pressed_fruits(stand: StandUnit) -> Dictionary:
	return stand.lifetime_stats.get("pressed_fruits", { })


func _regulars_count(stand: StandUnit) -> int:
	var n := 0
	var collection := stand.get_npc_collection()
	for id in collection:
		if float(collection[id].get("affinity", 0.0)) >= 10.0:
			n += 1
	return n


func _claimed_levels(stand: StandUnit) -> int:
	var n := 0
	for b in UpgradeManager.get_branches():
		n += UpgradeManager.get_branch_level(str(b.get("id", "")), stand)
	return n


func _full_branches_count(stand: StandUnit) -> int:
	var n := 0
	for b in UpgradeManager.get_branches():
		var prog := UpgradeManager.get_branch_progress(str(b.get("id", "")), stand)
		if int(prog.get("max_level", 0)) > 0 \
				and int(prog.get("level", 0)) >= int(prog["max_level"]):
			n += 1
	return n


func _ready() -> void:
	if Engine.is_editor_hint():
		return


func check_stand_thresholds(stand: StandUnit) -> void:
	if stand == null:
		GameLog.log("[Ach] check skipped: stand is null")
		return
	var local_stand: Node = WorldSync.get_local_stand()
	if local_stand == null or local_stand != stand:
		return

	GameLog.log(
		"[Ach] stand cups=%d sales=$%.2f spent=$%.2f happy=%d pressed=%d perfect=%s"
		% [
			stand.total_cups_sold,
			stand.total_money_earned_from_sales,
			stand.total_money_spent,
			stand.customers_served_happy,
			stand.total_fruit_pressed,
			str(stand.perfect_recipes_set.keys()),
		]
	)

	var base: Dictionary = _stand_baselines.get(stand.get_instance_id(), { })
	var spent: float = stand.total_money_spent - float(base.get("spent", 0.0))
	var cups: int = stand.total_cups_sold - int(base.get("cups", 0))
	var sales: float = (stand.total_money_earned_from_sales - float(base.get("sales", 0.0)))
	var happy: int = stand.customers_served_happy - int(base.get("happy", 0))
	var pressed: int = stand.total_fruit_pressed - int(base.get("pressed", 0))
	var trash: int = _trash_thrown(stand) - int(base.get("trash", 0))
	var machine: int = _machine_pitchers(stand, "") - int(base.get("machine_pitchers", 0))
	var fruitomatic: int = _machine_pitchers(stand, "fruitomatic") \
			- int(base.get("fruitomatic_pitchers", 0))
	var npcs_met: int = stand.get_npc_collection().size() - int(base.get("npcs_met", 0))
	var regulars: int = _regulars_count(stand) - int(base.get("regulars", 0))
	var claimed: int = _claimed_levels(stand) - int(base.get("claimed_levels", 0))
	var full_branches: int = _full_branches_count(stand) - int(base.get("full_branches", 0))
	var base_perfect: Array = base.get("perfect", [])
	var base_fruits: Array = base.get("pressed_fruits", [])
	var new_perfect := false
	for fruit in stand.perfect_recipes_set:
		if not base_perfect.has(fruit):
			new_perfect = true

	if spent >= 10.0:
		_unlock(ACH_START_SPENDING)
	if pressed > 0:
		_unlock(ACH_SQUEEZE_EM)
	if cups >= 1:
		_unlock(ACH_FIRST_CUSTOMER)
	if cups >= 10:
		_unlock(ACH_DOUBLE_DIGITS)
	if cups >= 30:
		_unlock(ACH_SALES_EXPERT)
	if cups >= 100:
		_unlock(ACH_ENTREPRENEUR)
	if cups >= 1000:
		_unlock(ACH_HYDRATING_THE_CITY)
	if sales >= 20.0:
		_unlock(ACH_POCKET_CHANGE)
	if sales >= 50.0:
		_unlock(ACH_SPARE_MONEY)
	if sales >= 200.0:
		_unlock(ACH_DO_YOU_HAVE_A_PERMIT)
	if sales >= 1000.0:
		_unlock(ACH_ROYAL_FLUSH)
	if happy >= 1:
		_unlock(ACH_HAPPY_BEGINNING)
	if new_perfect and stand.perfect_recipes_set.has("lemon"):
		_unlock(ACH_GOLDEN_SHOWER)
	# Set-completion checks use absolute coverage, gated on it not already
	# being complete at baseline — the final piece must happen on this
	# player's watch.
	var all_perfect := true
	var all_pressed := true
	for ft in GameState.FRUIT_TYPES:
		if not stand.perfect_recipes_set.has(ft):
			all_perfect = false
		if not _pressed_fruits(stand).has(ft):
			all_pressed = false
	if all_perfect and base_perfect.size() < GameState.FRUIT_TYPES.size():
		_unlock(ACH_LEMONADEER)
	if all_pressed and base_fruits.size() < GameState.FRUIT_TYPES.size():
		_unlock(ACH_GOTTA_SQUEEZE_EM_ALL)
	if machine > 0:
		_unlock(ACH_HANDS_FREE)
	if fruitomatic > 0:
		_unlock(ACH_ALL_IN_ONE)
	if trash >= 10:
		_unlock(ACH_CLEAN_NEIGHBORHOOD)
	if trash >= 50:
		_unlock(ACH_SQUEAKY_CLEAN)
	if trash >= 200:
		_unlock(ACH_ECOLOGIST)
	if claimed > 0:
		_unlock(ACH_FIRST_DISCOVERY)
	if full_branches > 0:
		_unlock(ACH_MASTER_OF_ONE)
	var branch_count := UpgradeManager.get_branches().size()
	if branch_count > 0 and _full_branches_count(stand) >= branch_count \
			and int(base.get("full_branches", 0)) < branch_count:
		_unlock(ACH_MASTER_OF_ALL_TRADES)
	if npcs_met >= 20:
		_unlock(ACH_ACQUAINTANCE)
	if npcs_met >= 50:
		_unlock(ACH_EXTROVERT)
	if npcs_met >= 100:
		_unlock(ACH_FRIEND_TO_ALL)
	if regulars >= 10:
		_unlock(ACH_COUPLE_OF_REGULARS)
	if regulars >= 30:
		_unlock(ACH_FAN_BASE)
	var roster_size := NpcRoster.size()
	if roster_size > 0 and _regulars_count(stand) >= roster_size \
			and int(base.get("regulars", 0)) < roster_size:
		_unlock(ACH_NEIGHBORHOOD_FAVORITE)
	if stand.popularity >= Balancing.MAX_POPULARITY:
		_unlock(ACH_ROCKSTAR)


## Legacy primary stand: GameState is the source of truth for single-player / the host's primary stand.
func check_game_state_thresholds() -> void:
	GameLog.log(
		"[Ach] GameState cups=%d sales=$%.2f spent=$%.2f happy=%d"
		% [
			GameState.total_cups_sold,
			GameState.total_money_earned_from_sales,
			GameState.total_money_spent,
			GameState.customers_served_happy,
		]
	)

	if GameState.total_money_spent >= 10.0:
		_unlock(ACH_START_SPENDING)
	if GameState.total_cups_sold >= 1:
		_unlock(ACH_FIRST_CUSTOMER)
	if GameState.total_cups_sold >= 10:
		_unlock(ACH_DOUBLE_DIGITS)
	if GameState.total_cups_sold >= 30:
		_unlock(ACH_SALES_EXPERT)
	if GameState.total_cups_sold >= 100:
		_unlock(ACH_ENTREPRENEUR)
	if GameState.total_cups_sold >= 1000:
		_unlock(ACH_HYDRATING_THE_CITY)
	if GameState.total_money_earned_from_sales >= 20.0:
		_unlock(ACH_POCKET_CHANGE)
	if GameState.total_money_earned_from_sales >= 50.0:
		_unlock(ACH_SPARE_MONEY)
	if GameState.total_money_earned_from_sales >= 200.0:
		_unlock(ACH_DO_YOU_HAVE_A_PERMIT)
	if GameState.total_money_earned_from_sales >= 1000.0:
		_unlock(ACH_ROYAL_FLUSH)
	if GameState.customers_served_happy >= 1:
		_unlock(ACH_HAPPY_BEGINNING)
	if GameState.popularity >= Balancing.MAX_POPULARITY:
		_unlock(ACH_ROCKSTAR)


## Public unlock for one-off achievements not driven by stand stats
## (e.g. easter eggs). Safe to call repeatedly — deduped per session.
func unlock(id: String) -> void:
	_unlock(id)


func _unlock(id: String) -> void:
	if id in _unlocked:
		return
	_unlocked[id] = true

	# isSteamRunning() can be true even when steamInit failed (e.g. Steam
	# client up but the app not registered) — UserStats is nullptr then and
	# setAchievement/storeStats error out. is_steam_initialized tracks the
	# actual init result.
	var inited: bool = NetworkManager.is_steam_initialized()
	GameLog.log("[Ach] attempting %s, Steam initialized=%s" % [id, inited])
	if not inited:
		return

	var set_ok: bool = Steam.setAchievement(id)
	var store_ok: bool = Steam.storeStats()
	GameLog.log("[Ach] %s set=%s store=%s" % [id, set_ok, store_ok])


## Ids unlocked this session — used by Analytics session summaries.
func get_unlocked_ids() -> Array:
	return _unlocked.keys()


## Clears every tracked achievement on the local Steam account. Useful for testing.
func reset_all_achievements() -> void:
	var ids: Array = [
		ACH_START_SPENDING,
		ACH_SQUEEZE_EM,
		ACH_FIRST_CUSTOMER,
		ACH_DOUBLE_DIGITS,
		ACH_SALES_EXPERT,
		ACH_ENTREPRENEUR,
		ACH_HYDRATING_THE_CITY,
		ACH_POCKET_CHANGE,
		ACH_SPARE_MONEY,
		ACH_DO_YOU_HAVE_A_PERMIT,
		ACH_ROYAL_FLUSH,
		ACH_HAPPY_BEGINNING,
		ACH_GOLDEN_SHOWER,
		ACH_LEMONADEER,
		ACH_HE_WAS_HERE,
		ACH_HANDS_FREE,
		ACH_ALL_IN_ONE,
		ACH_GOTTA_SQUEEZE_EM_ALL,
		ACH_CLEAN_NEIGHBORHOOD,
		ACH_SQUEAKY_CLEAN,
		ACH_ECOLOGIST,
		ACH_FIRST_DISCOVERY,
		ACH_MASTER_OF_ONE,
		ACH_MASTER_OF_ALL_TRADES,
		ACH_ACQUAINTANCE,
		ACH_EXTROVERT,
		ACH_FRIEND_TO_ALL,
		ACH_COUPLE_OF_REGULARS,
		ACH_FAN_BASE,
		ACH_NEIGHBORHOOD_FAVORITE,
		ACH_ROCKSTAR,
	]
	_unlocked.clear()
	if not NetworkManager.is_steam_initialized():
		GameLog.log("[Ach] Steam not running; achievements only cleared locally.")
		return
	for id in ids:
		var ok: bool = Steam.clearAchievement(id)
		GameLog.log("[Ach] cleared %s: %s" % [id, ok])
	var store_ok: bool = Steam.storeStats()
	GameLog.log("[Ach] reset storeStats: %s" % store_ok)
