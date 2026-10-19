extends CanvasLayer
## Shown once when the local player's stand finishes the demo onboarding
## chain — i.e. its progress reaches the terminal "demo_keep_running" task.
## Congratulates the player, shows credits, and offers a wishlist CTA.

## steam:// protocol opens the Steam client's store page directly instead of
## handing the link to the browser.
const STORE_URL := "steam://store/5000810"
const STORE_APP_ID := 5000810

## Per-stand baseline tracking: the first progress snapshot for each stand
## only records the current state, so a save that already finished the demo
## doesn't pop this screen on every load.
var _demo_done_seen: Dictionary = { }
var _shown := false

@onready var _backdrop: ColorRect = $Backdrop
@onready var _panel: PanelContainer = $Panel
@onready var _continue_btn: Button = $Panel/Margin/VBox/Buttons/ContinueButton
@onready var _wishlist_btn: Button = $Panel/Margin/VBox/Buttons/WishlistButton


func _ready() -> void:
	visible = false
	OnboardingManager.stand_progress_changed.connect(_on_stand_progress)
	_continue_btn.pressed.connect(_on_continue)
	_wishlist_btn.pressed.connect(_on_wishlist)


## Debug preview: F2 toggles the screen without consuming the one-shot
## flag, so the real trigger still fires later in the session.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F2 and event.pressed:
		if visible:
			_on_continue()
		else:
			_show(true)


func _on_stand_progress(stand: StandUnit, progress: Dictionary) -> void:
	if stand == null:
		return
	var key := stand.name
	var done: bool = (
		not progress.get("skipped", false)
		and progress.get("current_task_id", "") == "demo_keep_running"
	)
	if not _demo_done_seen.has(key):
		_demo_done_seen[key] = done
		return
	if done and not _demo_done_seen[key]:
		_demo_done_seen[key] = true
		if stand == WorldSync.get_local_stand():
			# Let the last task's completion moment breathe before the
			# celebration screen takes over.
			get_tree().create_timer(5.0).timeout.connect(_show)


func _show(debug: bool = false) -> void:
	if _shown and not debug:
		return
	# The timer is deferred — bail if the player left to a menu meanwhile.
	if not debug and WorldSync.get_local_player() == null:
		return
	if not debug:
		_shown = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	_backdrop.modulate = Color(1, 1, 1, 0)
	_panel.modulate = Color(1, 1, 1, 0)
	_panel.scale = Vector2(0.9, 0.9)
	_panel.pivot_offset = _panel.size / 2.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_backdrop, "modulate:a", 0.92, 0.3)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_continue() -> void:
	visible = false
	# Don't steal the cursor back if a menu is open over the game.
	if not EventBus.esc_menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_wishlist() -> void:
	# Prefer the in-game Steam overlay; fall back to the client store link
	# when Steam isn't running (e.g. exe launched directly).
	var running: bool = Steam.isSteamRunning()
	GameLog.log("[DemoComplete] wishlist: steam_running=%s" % running)
	if running:
		Steam.activateGameOverlayToStore(STORE_APP_ID)
	else:
		OS.shell_open(STORE_URL)
