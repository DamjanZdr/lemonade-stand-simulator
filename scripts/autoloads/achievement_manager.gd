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
		print("[Ach] check skipped: stand is null")
		return
	var local_stand: Node = WorldSync.get_local_stand()
	print("[Ach] local_stand=", local_stand, " stand=", stand, " match=", local_stand == stand)
	if local_stand == null or local_stand != stand:
		return

	print(
		"[Ach] cups=",
		stand.total_cups_sold,
		" sales=$",
		stand.total_money_earned_from_sales,
		" spent=$",
		stand.total_money_spent,
		" happy=",
		stand.customers_served_happy,
		" pressed=",
		stand.total_fruit_pressed,
		" perfect=",
		stand.perfect_recipes_set,
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


func _unlock(id: String) -> void:
	if id in _unlocked:
		return
	_unlocked[id] = true

	# Steam.isSteamRunning() is available on the Steam singleton. If it isn't
	# running (editor without Steam, non-Steam build), just log locally.
	if not Steam.isSteamRunning():
		print("[Ach][Offline] Would unlock: ", id)
		return

	Steam.setAchievement(id)
	Steam.storeStats()
	print("[Ach] Unlocked: ", id)
