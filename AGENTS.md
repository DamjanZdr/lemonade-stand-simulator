# Project Guide — Lemonade Stand Simulator

Godot 4.7.1 + GDScript + Steam multiplayer (planned).

## Build / Test

- **Run headless compile check**
  ```powershell
  D:\User\Desktop\Godot Projects\lemonade-stand-simulator\tools\godotsteam-editor\godotsteam.471.editor.win64.console.exe --headless --path "D:\User\Desktop\Godot Projects\lemonade-stand-simulator" --main-scene res://scenes/main.tscn
  ```
  Wait ~25s, then stop the process. Check stderr for `Parse Error` / `SCRIPT ERROR`.

- **Fruit parity regression:** run `tools/godotsteam-editor/godotsteam.471.editor.win64.console.exe --headless --path . --script res://tools/test_fruit_parity.gd`. Checks all six fruits' research-node availability, stand-isolated unlocks/orders, press transfer, pitcher ingredients, ten-cup pours, product icons, customer question-mark/fruit/count badges, and order-dialogue expiration without expiring feedback. This is not a live two-peer Steam test.
- Fruit research changes must update the owning `StandUnit.purchased_upgrade_nodes` before UI notification. Replicated stand research must also update the client's per-stand `UpgradeManager` storage; customer orders and board edits must read their own stand, not the globally active research tree or primary `GameState` recipes.

- **Lemonader regression:** run `tools/godotsteam-editor/godotsteam.471.editor.win64.console.exe --headless --path . --script res://tools/test_lemonader.gd`. Covers fruit locking, exact batch consumption, rejected/double starts, immutable recipes, running-batch snapshot/JSON restoration, and pitcher output for all six fruits.
- `scenes/objects/lemonader.tscn` is the single-fruit Squeeze-E-Z. Its imported `sqeeze-e-z.glb` has `Sugar`, `Fruit`, and `Ice` meshes, each with a `Key 1` blend shape (0 closed, 1 open). Preserve `Physics`, `PitcherPoint/PitcherPreview`, `PitcherPosition` (visual bottom), `SugarDrop`, `FruitDrop`, and `IceDrop`. The machine is plumbed — it has no water stock or deposits; batches fill the pitcher to capacity automatically and compute ice from `GameState.temperature` and the stand's `ice_degrees_per_scoop` at mix time. Empty-hand LMB mixes using the owning stand's board recipe; an unconfigured board shows "Please set a recipe on the board." on `MessageLabel`. Ingredients and the inserted pitcher are stored in `machine_state`; the preview is not a second world pitcher. The appliance is fixed after deployment and does not unload stock.
- **Squeeze-E-Z model/animation regression:** run the same headless executable with `--path . --script res://tools/test_lemonader_model.gd`. Checks pitcher bottom alignment, all three hopper shapes opening/closing, overlapping deposits, flight-visual cleanup, and stock-panel X/icon/count visibility for all six fruits. `StockPanels/Sugar`, `StockPanels/Fruit`, and `StockPanels/Ice` are editor-positionable instances of `lemonader_stock_panel.tscn`; stock updates refresh them through the existing host state broadcast. Deposit animations are cosmetic, broadcast only after host acceptance; they must not consume ingredients.

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
**Done:**
- `FruitBin`, `StandUnit` recipe/price, and `SupplyBox` despawn now all follow the request → host applies → broadcast pattern.
- `SupplyBox.release_delivery_slot()` is a shared helper used both for client-side prediction on pick-up and for host-authoritative release inside `WorldSync.despawn_networked()`. All clients also release the slot when they receive the despawn RPC, keeping every peer's delivery grid consistent.
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

### 4. Unified pickup/placement lifecycle — DONE
**Problem:** `pickup_container()` has a special workstation branch and separate paths for other containers. Every new placeable item repeats this.
**Target:** A `Pickupable` component or base class with `save_state()`, `restore_state()`, `on_pickup()`, `on_place(parent)` virtuals. Workstation only differs by child-attachment rule.
**Done:**
- [x] Create `scripts/components/pickupable.gd` base component with virtual methods and documentation.
- [x] Migrate `SupplyBox` to use `Pickupable`.
- [x] Migrate containers (`FruitBin`, `IngredientBin`, `Pitcher`, `CupStack`, `Press`) to use `Pickupable`.
- [x] Migrate workstation/table to use `Pickupable` with child-attachment rule.
- [x] Refactor `Player` pickup dispatch to check for `Pickupable` component first instead of branching by type.
- `WaterDispenser` is a fixed appliance — not pickupable, intentionally skipped.
- Internal container-to-container pickup calls (e.g. picking up a pitcher from a press) still call `pickup_container()` directly since they're internal interactions.
**Files:** `scripts/player/player_interaction.gd`, `scripts/components/pickupable.gd`, placeable object scripts.

### 5. Split `player.gd` — DONE
**Problem:** `scripts/player/player.gd` was ~3,000 lines and handled movement, camera, input, interaction, placement, inventory, MP sync, and serving.
**Done:**
- `HeldItem` enum extracted to a shared autoload.
- `PlayerInventory` (`scripts/player/player_inventory.gd`) — held item state, `set_held()` / `clear_held()` / `update_held_amount()` / `make_held_trash()`.
- `PlayerInteraction` (`scripts/player/player_interaction.gd`) — raycast, hint, primary/secondary interact dispatch, rapid-fire, frame lookups.
- `PlayerPlacement` (`scripts/player/player_placement.gd`) — ghost, placement validation, container pickup/place, supply box stacking, cup placement, trash drop, equipment placement.
- `PlayerController` (`scripts/player/player_controller.gd`) — movement, camera, input, body yaw catch-up, animation state, position sync RPCs, priceboard focus.
- `Player.gd` reduced to ~200 lines: `CharacterBody3D` authority, `_enter_tree`/`_ready`/`_configure_local_player`/`_setup_visuals`, `set_money_mode`, and `@onready` refs to the four child components.
- All four components are child nodes on `scenes/player/player.tscn`.
**Plan:** `.devin/plans/player_split_plan.md` (step-by-step extraction order, public APIs, gotchas).
**Files:** `scripts/player/player.gd`, `scripts/player/player_inventory.gd`, `scripts/player/player_interaction.gd`, `scripts/player/player_placement.gd`, `scripts/player/player_controller.gd`, `scenes/player/player.tscn`.

### 6. Replace deferred bone-pose hack for neck/head — DONE
**Problem:** `AnimationPlayer` overwrites procedural head/neck rotations, so we currently apply them twice (immediate + deferred).
**Target:** Apply procedural head/neck pose after the child AnimationPlayer has run.
**Done:** `Player._process` stores the look target via `PlayerVisuals.set_look_target()`; `PlayerVisuals._process` applies `update_look_bones()` after eye look-at, which is after the child AnimationPlayer updates.
**Files:** `scripts/player/player_visuals.gd`, `scripts/player/player.gd`.

### 7. Decouple save/snapshot from runtime groups — DONE
**Problem:** The world snapshot scans the `"container"` group, so default-scene objects that join the group get duplicated on client join.
**Done:**
- `WorldSync` now maintains a host-side `_placed_objects` registry keyed by `net_id`.
- `spawn_networked()` registers new objects; `tree_exited` unregisters them.
- `_collect_world_snapshot()` uses the registry instead of scanning groups.
- Default-scene objects not spawned through `WorldSync` are lazily registered on the first snapshot so they are included.
**Files:** `scripts/multiplayer/world_sync.gd`, `scripts/systems/save_manager.gd`.

### 8. Per-peer UI focus ownership — DONE
**Problem:** Global UI systems (blackboard, menus) sometimes assume only one player exists.
**Target:** Every UI-focus action carries the initiating player reference; focus release affects only that player.
**Done:**
- `Blackboard` and `PriceBoard` already tracked `_editing_player` and released focus for that specific player.
- `PlayerMirror` already checked `is_multiplayer_authority()`.
- Added `WorldSync.get_local_player()` static helper that finds the player this peer has authority over.
- Fixed `press.gd` highlight to use local player for held-item check.
- Fixed `audio_manager.gd` to play transaction sound at local player's position.
- Fixed `money_controller.gd` to assign local player when opening register.
- Fixed `morning_hub.gd` `_get_local_stand()` to use local player's `assigned_stand` instead of first StandUnit found.
- NPC visual look-at systems left as-is (visual nicety, not correctness).
**Files:** `scripts/multiplayer/world_sync.gd`, `scripts/objects/press.gd`, `scripts/autoloads/audio_manager.gd`, `scripts/player/money_controller.gd`, `scripts/ui/morning_hub.gd`.

## Common Bug Patterns

- **Duplication on client pick-up:** caller mutates locally and also waits for host replication. Fix: clients request, host applies + broadcasts.
- **Slot stacking in air:** local slot count is stale because host release RPC is delayed or crashes. Fix: slot reservation/release must be host-authoritative with idempotent RPCs.
- **Recipe/price desync:** UI writes to local `GameState` and the host overwrites it later. Fix: make `GameState` the single source of truth.

## Demo Analytics

- `scripts/autoloads/analytics.gd` owns participant reports, anonymous shared match IDs, and host-only stand snapshots. Do not sum co-op participant sales as separate stand sales.
- `tools/sheets_analytics.gs` is the Google Apps Script source. Changes require the owner to replace Code.gs, run `setupTelemetry`, and deploy a new version of the existing web app before releasing compatible game changes.
- Apps Script redirects POST responses to `script.googleusercontent.com`; Godot must explicitly fetch that acknowledgement using GET. A Python-only endpoint test does not verify Godot transport.
- Reports send during play (checkpoint every 30s, critical changes after 5s) plus one bounded quit flush (`QUIT_FLUSH_SECONDS`). The queue is in-memory only — anything unsent at process exit is lost; there is no next-launch retry. Checkpoint/end revisions update existing rows; no end received is not evidence of a crash.
- The private Sheets read key stays outside the repository at `%USERPROFILE%/lemonade-analytics-read-key.txt`. Never print it, commit it, or include it in game exports.
- Legacy imported reports have known stale-client/mode issues and receipt-time timestamps; do not mix them with schema-v2 match-level metrics.
- Tutorial and pitcher learning details use revisioned `learning` submissions, batched up to 10 rows per request. Deploy the matching Google receiver before shipping these game changes.
- Tutorial timing is per stand and observed match segment; automatic completions and resumed partial steps are excluded from completed-step timing medians. Unpaused time includes any active teammate but is not an AFK detector.
- A pitcher batch starts at its first pour; its anonymous batch/cup tags travel in recipe snapshots across placement, network sync, and saves. Free-sample feedback is separate from customer tastings. Carried-in/unattributed batches are excluded from aggregate learning curves.
- Run `node tools/test_sheets_analytics.cjs` for the standalone backend regression checks (no Google access required).

## Recipe Feedback

- Customers and free-sample pedestrians use deterministic ingredient complaints and shared 1 / 2 / 3+ unit wording in `scripts/systems/recipe_evaluator.gd`. Sugar still scales with fruit count; ice still follows current temperature. Mixed-cup orders label different feedback groups rather than presenting contradictory instructions for one drink.
- Run `tools/godotsteam-editor/godotsteam.471.editor.win64.console.exe --headless --path . --script res://tools/test_recipe_feedback.gd` for feedback regression checks. The standalone harness may also report the existing UpgradeManager missing-current-scene startup error; distinguish that from the explicit test result.

## Exports

- Release preset is `Windows Desktop` → `export/WhenLifeGivesYouLemons.exe`, using the custom GodotSteam templates in `tools/godotsteam-templates/win64/`. Export with `tools/godotsteam-editor/godotsteam.471.editor.win64.console.exe --headless --path . --export-release "Windows Desktop" export/WhenLifeGivesYouLemons.exe`. Keep `steam_api64.dll` and `steam_appid.txt` beside the exe.
- Export packs `.godot/exported/*.scn` conversions, not the `.tscn`/`.gd` sources. If a shipped build shows old UI or stale behavior despite current sources, delete `.godot/exported` and `.godot/imported` and re-export — cached scene conversions have served stale content.
- Release builds hide the F1 dev panel (`OS.is_debug_build()`); use `--export-debug` to a separate folder if a built binary needs it.
