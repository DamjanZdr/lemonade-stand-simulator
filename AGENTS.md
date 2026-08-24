# Project Guide — Lemonade Stand Simulator

Godot 4.7.1 + GDScript + Steam multiplayer (planned).

## Build / Test

- **Run headless compile check**
  ```powershell
  D:\User\Desktop\Godot Projects\lemonade-stand-simulator\tools\godotsteam-editor\godotsteam.471.editor.win64.console.exe --headless --path "D:\User\Desktop\Godot Projects\lemonade-stand-simulator" --main-scene res://scenes/main.tscn
  ```
  Wait ~25s, then stop the process. Check stderr for `Parse Error` / `SCRIPT ERROR`.

## Multiplayer Architecture Notes

The project began as single-player and was retrofitted for multiplayer. Host-authoritative networking is the target, but several subsystems still mix local authority with RPC sync.

## Refactoring Roadmap

Use this list to track cleanup that prevents recurring MP sync bugs.

### 1. Centralize WorldSync authority pattern
**Problem:** Mutation methods mutate locally *and* sync, with `is_host()` branches duplicated across call sites. This creates race conditions and double application.
**Target pattern:**
```gdscript
# Client-side: only send request
func request_do_thing(params) -> void:
    _rpc_do_thing.rpc_id(1, params)

# Host-side: validate, mutate, broadcast
@rpc("any_peer", "call_local", "reliable")
func _rpc_do_thing(params) -> void:
    if not is_multiplayer_authority():
        return
    _do_thing(params)
    _push_state_to_clients()
```
**Done:**
- `FruitBin` now routes `add_amount()` and `take_amount()` through host-only `_apply_*` helpers. Clients send `_rpc_request_*` and do not mutate locally.
- `StandUnit.set_recipe()` and `set_price()` now update `GameState` consistently via `GameState.set_*()` on the legacy primary stand.
- `Blackboard` and `morning_hub` no longer duplicate GameState writes; they send requests through `StandUnit.request_set_*()` and rely on the resulting state sync.
**Still TODO:** `SupplyBox` (already uses `request_despawn` for pick-up; slot release could be centralized).
**Files to refactor:** `scripts/objects/fruit_bin.gd`, `scripts/objects/supply_box.gd`, `scripts/objects/blackboard.gd`, `scripts/stand/stand_unit.gd`.

### 2. Stable network IDs for spawned objects — DONE
**Problem:** Objects are located by `name` + parent path. Reparenting and duplicate names break sync, causing missed despawns and duplicated placements.
**Done:**
- `WorldSync` assigns a unique integer `net_id` meta to every spawned object and to objects captured by snapshots.
- Spawn, despawn, property sync, method sync, transform sync, move/show, and reparent RPCs all carry and prefer `net_id`.
- `_find_node()` now tries `net_id` first, then name cache, then path, then tree search.
- Workstation item attachment sync passes `{ name, net_id }` dictionaries instead of just names.
**Files:** `scripts/multiplayer/world_sync.gd`, `scripts/player/player.gd`.

### 3. Stand stats ownership (GameState as read-only view)
**Problem:** Recipes and prices are stored in `StandUnit.recipes`, `GameState.recipes`, and the blackboard labels. They drift.
**Target:** `StandUnit` is authoritative for its own prices + recipes. The legacy primary stand writes through to `GameState` via `GameState.set_*()` so existing UI, save/load, and debug tools keep working. Non-primary stands stay isolated. UI callers send requests through `StandUnit.request_set_*()` instead of mutating `GameState` directly.
**Done:**
- `StandUnit.set_recipe()` and `set_price()` write through to `GameState` for the primary stand.
- `Blackboard` and `morning_hub` no longer call `GameState.set_*()` directly.
**Files:** `scripts/autoloads/game_state.gd`, `scripts/stand/stand_unit.gd`, `scripts/objects/blackboard.gd`, `scripts/ui/morning_hub.gd`.

### 4. Unified pickup/placement lifecycle
**Problem:** `pickup_container()` has a special workstation branch and separate paths for other containers. Every new placeable item repeats this.
**Target:** A `Pickupable` component or base class with `save_state()`, `restore_state()`, `on_pickup()`, `on_place(parent)` virtuals. Workstation only differs by child-attachment rule.
**Files:** `scripts/player/player.gd`, new `scripts/components/pickupable.gd`.

### 5. Split `player.gd`
**Problem:** `scripts/player/player.gd` is ~3,000 lines and handles movement, camera, input, interaction, placement, inventory, MP sync, and serving.
**Target:** Separate into focused scripts:
- `PlayerController` — movement + camera + input
- `PlayerInteraction` — raycast + hint + interact request
- `PlayerPlacement` — ghost + placement validation
- `PlayerInventory` / `PlayerHands` — held item state
**Files:** `scripts/player/player.gd`, new files under `scripts/player/`.

### 6. Replace deferred bone-pose hack for neck/head
**Problem:** `AnimationPlayer` overwrites procedural head/neck rotations, so we currently apply them twice (immediate + deferred).
**Target:** Use an `AnimationTree` additive blend track for head/neck, or set `AnimationPlayer.process_callback = ANIMATION_PROCESS_PHYSICS` and apply poses in `_process`.
**Files:** `scripts/player/player_visuals.gd`, `scripts/player/player.gd`.

### 7. Decouple save/snapshot from runtime groups — DONE
**Problem:** The world snapshot scans the `"container"` group, so default-scene objects that join the group get duplicated on client join.
**Done:**
- `WorldSync` now maintains a host-side `_placed_objects` registry keyed by `net_id`.
- `spawn_networked()` registers new objects; `tree_exited` unregisters them.
- `_collect_world_snapshot()` uses the registry instead of scanning groups.
- Default-scene objects not spawned through `WorldSync` are lazily registered on the first snapshot so they are included.
**Files:** `scripts/multiplayer/world_sync.gd`, `scripts/systems/save_manager.gd`.

### 8. Per-peer UI focus ownership
**Problem:** Global UI systems (blackboard, menus) sometimes assume only one player exists.
**Target:** Every UI-focus action carries the initiating player reference; focus release affects only that player.
**Files:** `scripts/objects/blackboard.gd`, UI scripts under `scripts/ui/`.

## Common Bug Patterns

- **Duplication on client pick-up:** caller mutates locally and also waits for host replication. Fix: clients request, host applies + broadcasts.
- **Slot stacking in air:** local slot count is stale because host release RPC is delayed or crashes. Fix: slot reservation/release must be host-authoritative with idempotent RPCs.
- **Recipe/price desync:** UI writes to local `GameState` and the host overwrites it later. Fix: make `GameState` the single source of truth.
