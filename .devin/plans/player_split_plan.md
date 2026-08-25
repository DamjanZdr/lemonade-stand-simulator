# Player.gd Split Plan

## Goal

Split `scripts/player/player.gd` (~3,000 lines) into focused sub-scripts so the rest of the multiplayer/pickupable refactor becomes easier and `Player.gd` is only a thin coordinator.

Target modules (all attached as child nodes under the `Player` scene `res://scenes/player/player.tscn`):

- `PlayerInventory` — held item state and hand mesh
- `PlayerInteraction` — raycast, hint, primary/secondary interact dispatch
- `PlayerPlacement` — placement ghost and place/drop logic
- `PlayerController` — movement, camera, input

`Player.gd` keeps:

- `CharacterBody3D` / authority / position replication
- `MultiplayerSynchronizer` setup
- `@onready` vars for child components
- orchestration (`_ready`, `_process`, `_physics_process` hooks)

## Order of work

Do the modules in this order. Each step must compile and pass the headless
compile check before committing.

### Step 1 — Extract `PlayerInventory`

New file: `scripts/player/player_inventory.gd` (extends `Node`, class name `PlayerInventory`).

Move from `Player.gd`:

- `var held_item: int = HeldItem.NONE`
- `var held_item_data: Dictionary = { }`
- `var _held_mesh: Node3D = null`
- `func _get_held_item_name() -> String`
- `func set_held(item_type: int, data: Dictionary, mesh: Node3D = null) -> void`
- `func update_held_amount(new_amount: float) -> void`
- `func clear_held() -> void`
- `func make_held_trash(refund: float, trash_type: String) -> void`

Public API:

```gdscript
var held_item: int = HeldItem.NONE
var held_item_data: Dictionary = { }

func set_held(item_type: int, data: Dictionary, mesh: Node3D = null) -> void
func update_held_amount(new_amount: float) -> void
func clear_held() -> void
func make_held_trash(refund: float, trash_type: String) -> void
func get_held_item_name() -> String
func get_hand_mesh() -> Node3D
```

Implementation notes:

- `set_held` frees old `_held_mesh`, attaches new mesh to `player.hand_slot`, updates `hud.set_held_item`.
- `make_held_trash` reuses `set_held(HeldItem.TRASH, { ... }, trash_mesh)`.
- Keep `held_item` and `held_item_data` as public vars so other modules can read them via `player.inventory.held_item`.

In `Player.gd`:

- Add `@onready var inventory: PlayerInventory = $PlayerInventory`.
- Add the child node `PlayerInventory` to `scenes/player/player.tscn`.
- Remove the vars/functions listed above from `Player.gd`.
- Replace every `held_item` reference in `Player.gd` with `inventory.held_item` (read) or call `inventory.set_held(...)` etc.
- Replace every `held_item_data` reference with `inventory.held_item_data`.
- `_held_mesh` becomes `inventory.get_hand_mesh()`.

Known read sites in `Player.gd`:

- `_get_held_item_name` -> `inventory.get_held_item_name()`
- `_poll_hint` and primary/secondary interact branches read `held_item`/`held_item_data`
- `_place_*`, `_drop_trash`, `_update_ghost`, `pickup_container`, `_place_equipment_from_box` read `held_item`/`held_item_data`
- `set_held` calls update hud -> move to `PlayerInventory`
- `clear_held` -> `inventory.clear_held()`
- `update_held_amount` -> `inventory.update_held_amount(...)`
- `make_held_trash` -> `inventory.make_held_trash(...)`

Commit message: `Extract PlayerInventory from Player.gd`.

### Step 2 — Extract `PlayerInteraction`

New file: `scripts/player/player_interaction.gd` (extends `Node`, class name `PlayerInteraction`).

Move from `Player.gd`:

- `var _last_hint: String = ""`
- `var _hovered: Interactable = null`
- `var _last_press_holding_fruit: bool = false`
- `var last_interact_hit: Node = null`
- `var _primary_held: bool = false`
- `var _rapid_fire_timer: float = 0.0`
- `var _rapid_fire_cup_target: CupStack = null`
- `func _poll_hint() -> void`
- `func _get_looked_at_interactable() -> Interactable`
- `func _primary_interact() -> void`
- `func _secondary_interact() -> void`
- `func _update_rapid_fire(delta: float) -> void`
- `func _frame_lookup_*` helpers (currently `_frame_press`, `_frame_dispenser`, `_frame_lookups_done`)

Public API:

```gdscript
var hovered: Interactable = null
var last_interact_hit: Node = null

func poll_hint() -> void
func get_looked_at_interactable() -> Interactable
func primary_interact() -> void
func secondary_interact() -> void
func update_rapid_fire(delta: float) -> void
func update_frame_lookups() -> void
```

Implementation notes:

- `PlayerInteraction` needs references to `player.head`, `player.ray`, `player.inventory`, `player.hud`.
- Pass `player: Player` in `_ready` or use `@onready`.
- `primary_interact`/`secondary_interact` still need access to placement functions; call `player.placement.place_...()` for the place branches.
- Keep hint text emission (`EventBus.interaction_hint_changed.emit`) in this module.

In `Player.gd`:

- Add `@onready var interaction: PlayerInteraction = $PlayerInteraction`.
- In `_process`, call `interaction.poll_hint()` and `interaction.update_rapid_fire(delta)`.
- In `_physics_process`, call `interaction.update_frame_lookups()` (or do it inside `poll_hint`).
- Remove `_unhandled_input` branches for primary/secondary and route to `interaction.primary_interact()` etc.

Commit message: `Extract PlayerInteraction from Player.gd`.

### Step 3 — Extract `PlayerPlacement`

New file: `scripts/player/player_placement.gd` (extends `Node`, class name `PlayerPlacement`).

Move from `Player.gd`:

- `var _ghost: Node3D = null`
- `var _ghost_valid: bool = false`
- `static var _ghost_mat_valid`
- `static var _ghost_mat_invalid`
- `var _last_ghost_mat`
- `var _stack_target_id`, `_stack_offset`, `_stack_yaw`
- `CONTAINER_SCENES`, `CONTAINER_SCENE_PATHS`, `CONTAINER_PLACEMENT_SCALE`
- `func _update_ghost() -> void`
- `func pickup_container(...) -> void`
- `func _place_held_supply_box_on(...) -> SupplyBox`
- `func _place_held_supply_box_on_grid(...) -> void`
- `func _place_held_supply_box_on_stack(...) -> void`
- `func _place_equipment_from_box() -> void`
- `func _place_cup_stack_from_box() -> void`
- `func _place_single_cup(...) -> void`
- `func _place_filled_cup() -> void`
- `func _drop_trash(...) -> void`
- All other `_place_*` helpers.

Public API:

```gdscript
func update_ghost() -> void
func place_primary() -> void
func place_secondary() -> void
func pickup_container(interactable: Interactable, container_type: String) -> void
```

Implementation notes:

- `PlayerPlacement` needs `player`, `player.inventory`, `player.ray`, `player.head`/`camera`.
- It should not know about `Player.gd` internals other than through `player` and `player.inventory`.
- Calls `player.set_ghost(...)` if `Player.gd` keeps ghost ownership, or keep `_ghost` inside `PlayerPlacement` and expose `ghost_visible`.
- `WorldSync.spawn_networked` calls stay here.

In `Player.gd`:

- Add `@onready var placement: PlayerPlacement = $PlayerPlacement`.
- `_process` calls `placement.update_ghost()`.
- `_primary_interact` in `PlayerInteraction` calls `player.placement.place_primary()` when the held item is a placeable.

Commit message: `Extract PlayerPlacement from Player.gd`.

### Step 4 — Extract `PlayerController`

New file: `scripts/player/player_controller.gd` (extends `Node`, class name `PlayerController`).

Move from `Player.gd`:

- `_look_yaw`, `_look_pitch`
- `_unhandled_input` mouse/camera logic
- `_update_body_yaw(delta)`
- `wrap_angle(angle)`
- movement input calculation
- `NECK_YAW_MAX`, `NECK_YAW_CATCHUP_SPEED`, `MOUSE_SENSITIVITY`, etc.

Public API:

```gdscript
var look_yaw: float = 0.0
var look_pitch: float = 0.0

func _ready() -> void
func _unhandled_input(event: InputEvent) -> void
func _physics_process(delta: float) -> void
func get_move_direction() -> Vector3
```

Implementation notes:

- `PlayerController` must call `player.move_and_slide()` because `player` is the `CharacterBody3D`.
- Keep `player.velocity.y` gravity in `Player._physics_process` or move it to `PlayerController` with `player.velocity = ...; player.move_and_slide()`.
- Input mouse handling sets `player.head.rotation = Vector3(look_pitch, look_yaw, 0)`.
- Body catch-up rotates `player` directly and updates `look_yaw`.

In `Player.gd`:

- Remove `_unhandled_input` and `_physics_process` movement code.
- Add child `PlayerController`.
- Forward `_unhandled_input` to `controller._unhandled_input` (or connect `get_viewport().unhandled_input`? The controller is a child Node and can receive `_unhandled_input` only if it is the focused or if Player forwards. Easiest: `Player._unhandled_input` calls `controller.handle_input(event)` and returns.)
- `Player._physics_process` calls `controller._physics_process(delta)` or `controller.tick(delta)` and does nothing else.

Commit message: `Extract PlayerController from Player.gd`.

## Common gotchas

1. **Onready coupling**: `Player.gd` uses `@onready var head`, `camera`, `ray`, `visuals`, `hand_slot`, `hud`. Each new module gets these via `@onready` or an exported `player: Player` and then reads the child nodes.
2. **Multiplayer authority**: `Player._ready` must still set `multiplayer_authority` and spawn the `PositionSync`. Other modules should only run on the local-authority peer, but they can check `player.is_multiplayer_authority()`.
3. **HUD access**: `hud` is a sibling in `main.tscn`. `Player.gd` can keep an `@onready var hud: Control` and pass it to modules, or modules can find it via `get_tree().get_first_node_in_group("hud")`.
4. **HeldItem enum**: Already extracted to `scripts/autoloads/held_item.gd`. Do NOT move it back.
5. **Commit rule**: compile after every step.
6. **Fallback**: if a step is too large, split it into smaller commits (e.g., inventory fields before inventory methods).

## Testing after each commit

```powershell
D:\User\Desktop\Godot Projects\lemonade-stand-simulator\tools\godotsteam-editor\godotsteam.471.editor.win64.console.exe --headless --path "D:\User\Desktop\Godot Projects\lemonade-stand-simulator" --main-scene res://scenes/main.tscn
```

Stop after ~25s and check stderr for `Parse Error` / `SCRIPT ERROR`.

## Notes for the next agent

- The `Pickupable` refactor in `AGENTS.md` depends on `PlayerInteraction` and `PlayerPlacement`. Finish the Player split before migrating more containers to `Pickupable`.
- Do not start the `Player.gd` split unless you have enough tokens to complete at least one full step and commit it cleanly.
