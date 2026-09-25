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

## Achievements already unlocked this session so we don't spam Steam.
var _unlocked: Dictionary = { }


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

	if stand.total_money_spent >= 10.0:
		_unlock(ACH_START_SPENDING)
	if stand.total_fruit_pressed > 0:
		_unlock(ACH_SQUEEZE_EM)
	if stand.total_cups_sold >= 1:
		_unlock(ACH_FIRST_CUSTOMER)
	if stand.total_cups_sold >= 10:
		_unlock(ACH_DOUBLE_DIGITS)
	if stand.total_cups_sold >= 30:
		_unlock(ACH_SALES_EXPERT)
	if stand.total_cups_sold >= 100:
		_unlock(ACH_ENTREPRENEUR)
	if stand.total_money_earned_from_sales >= 20.0:
		_unlock(ACH_POCKET_CHANGE)
	if stand.total_money_earned_from_sales >= 50.0:
		_unlock(ACH_SPARE_MONEY)
	if stand.total_money_earned_from_sales >= 200.0:
		_unlock(ACH_DO_YOU_HAVE_A_PERMIT)
	if stand.customers_served_happy >= 1:
		_unlock(ACH_HAPPY_BEGINNING)
	if stand.perfect_recipes_set.has("lemon"):
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


func _unlock(id: String) -> void:
	if id in _unlocked:
		return
	_unlocked[id] = true

	var running: bool = Steam.isSteamRunning()
	GameLog.log("[Ach] attempting %s, Steam running=%s" % [id, running])

	var set_ok: bool = Steam.setAchievement(id)
	var store_ok: bool = Steam.storeStats()
	GameLog.log("[Ach] %s set=%s store=%s" % [id, set_ok, store_ok])
