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
const ACH_POCKET_CHANGE := "ACH_POCKET_CHANGE"
const ACH_SPARE_MONEY := "ACH_SPARE_MONEY"
const ACH_DO_YOU_HAVE_A_PERMIT := "ACH_DO_YOU_HAVE_A_PERMIT"
const ACH_HAPPY_BEGINNING := "ACH_HAPPY_BEGINNING"
const ACH_GOLDEN_SHOWER := "ACH_GOLDEN_SHOWER"
const ACH_HE_WAS_HERE := "ACH_HE_WAS_HERE"

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
	}


func _ready() -> void:
	if Engine.is_editor_hint():
		return


func check_stand_thresholds(stand: StandUnit) -> void:
	if stand == null:
		GameLog.log("[Ach] check skipped: stand is null")
		return
	var local_stand: Node = WorldSync.get_local_stand()
	GameLog.log(
		"[Ach] local_stand=%s stand=%s match=%s" % [local_stand, stand, local_stand == stand]
	)
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
	var base_perfect: Array = base.get("perfect", [])
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
	if sales >= 20.0:
		_unlock(ACH_POCKET_CHANGE)
	if sales >= 50.0:
		_unlock(ACH_SPARE_MONEY)
	if sales >= 200.0:
		_unlock(ACH_DO_YOU_HAVE_A_PERMIT)
	if happy >= 1:
		_unlock(ACH_HAPPY_BEGINNING)
	if new_perfect and stand.perfect_recipes_set.has("lemon"):
		_unlock(ACH_GOLDEN_SHOWER)


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
	if GameState.total_money_earned_from_sales >= 20.0:
		_unlock(ACH_POCKET_CHANGE)
	if GameState.total_money_earned_from_sales >= 50.0:
		_unlock(ACH_SPARE_MONEY)
	if GameState.total_money_earned_from_sales >= 200.0:
		_unlock(ACH_DO_YOU_HAVE_A_PERMIT)
	if GameState.customers_served_happy >= 1:
		_unlock(ACH_HAPPY_BEGINNING)


## Public unlock for one-off achievements not driven by stand stats
## (e.g. easter eggs). Safe to call repeatedly — deduped per session.
func unlock(id: String) -> void:
	_unlock(id)


func _unlock(id: String) -> void:
	if id in _unlocked:
		return
	_unlocked[id] = true

	var running: bool = Steam.isSteamRunning()
	GameLog.log("[Ach] attempting %s, Steam running=%s" % [id, running])

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
		ACH_POCKET_CHANGE,
		ACH_SPARE_MONEY,
		ACH_DO_YOU_HAVE_A_PERMIT,
		ACH_HAPPY_BEGINNING,
		ACH_GOLDEN_SHOWER,
		ACH_HE_WAS_HERE,
	]
	_unlocked.clear()
	if not Steam.isSteamRunning():
		GameLog.log("[Ach] Steam not running; achievements only cleared locally.")
		return
	for id in ids:
		var ok: bool = Steam.clearAchievement(id)
		GameLog.log("[Ach] cleared %s: %s" % [id, ok])
	var store_ok: bool = Steam.storeStats()
	GameLog.log("[Ach] reset storeStats: %s" % store_ok)
