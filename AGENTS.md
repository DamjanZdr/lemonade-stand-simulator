# Project Guide — Lemonade Stand Simulator

Godot 4.7.1 + GDScript + Steam multiplayer (planned).

## RESOLVED — interaction frame spikes (2026-10-31)

**TWO REAL BUGS, both fixed:**
1. `morning_hub.gd` `_on_stand_progress_changed` + `_on_fruit_research_changed` (CONNECT_DEFERRED) rebuilt the entire shop/upgrades UI on EVERY action — gated on `visible` which stays true while the computer is closed (SubViewport hides, Control doesn't). Fix: `panel.visible`.
2. `computer.gd` `_hide_morning_hub(true)` + `UPDATE_WHEN_VISIBLE` kept the whole fat hub UI stepping + rendering every frame while the screen was on camera. Fix: `UPDATE_ONCE` + full hide on exit.

**APPROACH:** reverted everything to `b41a20b` (verified smooth), forward-ported every feature batch of the bad commit `6a19689` with user A/B tests per batch. Full parity now at HEAD-minus-two-bugs, all confirmed smooth. Everything else in that commit was innocent.

**Still TODO before release:**
- GameLog instrumentation (`_process` spike dump neutered but `mark()`/`time_log` calls still live — strip or gate)
- `GameState.DEV_TOOLS = true` left enabled (gate for release)
- stand_unit still has synchronous `push_state` (deferred variant never retested — keep sync)
- `upgrade_bar_column`/`PreviewViewport` fine as-is
- pitcher-from-box placement had a small residual drop at one point — may need LiquidFill-era review if it resurfaces
**Prior investigation data preserved below.**
- Bisect worktrees: `../wlgl-bisect-1022`, `../wlgl-bisect-1027`, `../wlgl-bisect-head` (copy `tools/godotsteam-templates/win64/*` + `mkdir export`, then headless `--export-release "Windows Desktop" export/WhenLifeGivesYouLemons.exe`; add `steam_api64.dll` + `steam_appid.txt` beside exe).
- Steam uploads do NOT set a branch live (VDF has no setlive) — user sets BuildID live on test branch in Steamworks manually.

**RULED OUT (tested builds):** pipeline warmup (WARMUP_SCENES still in world_sync — keep or remove), fps cap unlimited, graphics=low, house-LOD disabled, enhanced lighting disabled, PreviewViewport WHEN_VISIBLE, physics catch-up (`max_physics_steps_per_frame=1` still stutters — REVERT that project.godot line before release), fullscreen (predates), Discord/mouse (old build smooth same env).

**SIGNAL:** `adraw`≈frame on big stalls (post_draw→next _process = present/vsync + OS events + process lead-in); proc≈10ms phys≈1ms rblock≈5ms pticks=1, nodes static even in 4.5s frames. One frame showed adraw=4 (sync-block variant). Not script, not physics, not measured draw block.

**bgap/pticks data (build 26347745):** most stalls show `bgap≈frame` (post_draw→process_frame) — vsync OFF still stalls → present isn't the blocker; remaining in-window: `DisplayServer::process_events`/input dispatch (NOT counted in proc!) or SceneTree housekeeping. A second variant `adraw≈frame bgap≈0` = stall between process_frame and _process → deferred-queue/`queue_free`/`NOTIFICATION` flush territory. `fruitomatic._unhandled_input` early-returns — dead end. `max_physics_steps_per_frame=1` set in project.godot (7d866db) — still stalls, revert before release.
**Next split (in order):** (a) disable `_screen_ui`/computer screen entirely — user can't buy without it; throttle test failed → need dev-spawn path or keep screen on but skip hub._process; (b) `player_placement.gd` +464 revert-or-stub; (c) `upgrade_bar_column.gd`/`morning_hub.gd` stub _process; (d) `customer.gd`/`assistant.gd` order-indicator + AI stubs.

**REMAINING SUSPECTS in 6a19689:** computer `_screen_ui` SubViewport UPDATE_WHEN_VISIBLE re-rendering heavy new morning_hub UI per frame while on-camera (TEST BUILD READY: `../wlgl-bisect-head/export` = HEAD + `_screen_ui` UPDATE_DISABLED). Then: `player_placement.gd` +464, `morning_hub.gd` +1394 rewrite, `upgrade_bar_column.gd` +562 new, `customer.gd` +125 order indicators, `assistant.gd` +282, `upgrade_manager.gd` rewrite, `stand_unit.gd` +94.

**Symptom:** 30-3800ms hitches on nearly every interaction — shop buy button, all placements (table/press/Squeeze-E-Z/crate/cup stack), trashcan, pitcher↔dispenser/table/stand, cup fills, NPC serve/order — solo AND multiplayer.

**Proven so far:**
- Spike dump in `GameLog._process` (`[SPIKE] frame Xms proc=P phys=Y nav=N draw=D nodes=N marks=...`):
  `proc`+`phys` ≈ 10-30ms inside 400-3800ms frames → **the time is render/driver-side, NOT GDScript or physics.** Some frames have zero action marks.
- Function timers only explain ≤80ms (`spawn_networked:lemonader.tscn` 83ms worst; `_try_place_container` ~30ms; `_do_save` ~3ms).
- Fixed already (not the cause): pitcher/dispenser CSG liquid replaced with `scale.y` meshes (`c5946e9`); release `print()` removed; hidden debug-console label rebuild skipped; achievement checks coalesced per frame; analytics HTTP moved to `use_threads=true` + `analytics.connect` mark (`a2306b7`).
- World uses **baked** LightmapGI + 2×VoxelGI + ReflectionProbe (check its `update_mode`), glow+fog enabled, occlusion culling on, `physics_interpolation=true`. `outline_overlay.tscn` is a separate SubViewport rendering only layer-2 `_Outline` fill meshes, UPDATE_ALWAYS only while a highlight exists.
- **Remaining suspects (render-side):** Forward+ Vulkan pipeline compilation on first draw of new spawns/materials (each object type hitches first placement; but user reports repeats hitch too); texture upload on first visibility; delivery-truck spawn after shop orders (`equipment_ordered` → 1800ms frame, no other spawn marks); ReflectionProbe re-render; GPU present/queue stalls (draw calls ~2000-2400, nodes ~13k).
- **Next diagnostic step:** add `RenderingServer.viewport_set_measure_render_time(root, true)` → log `viewport_get_measured_render_time_cpu/gpu()` in the spike dump to split submit vs GPU. Consider a no-analytics / no-glow / no-outline A-B build. If pipeline-compile confirmed: warm pipelines at load (spawn every placeable hidden + force render), or evaluate renderer change.

**REGRESSION to fix:** pitcher liquid `scale.y` mesh "fully mismatches" the fill level vs the old CSG eraser look. Mesh AABB probe claimed bottom≈0.02, height≈3.45 — verify actual pivot/scale mapping in `pitcher.gd` fill update (`_update_eraser_position` replacement). Old eraser_y range ~1.75↔? Check `scenes/objects/pitcher.tscn` Lemonade MeshInstance transform.

**Pitcher wipe:** `[DIAG]` watcher + `empty_held_pitcher` logging still active; held copies use `is_held_copy` + name `HeldPitcher` (f11baed). Unconfirmed whether wipe still occurs.

**Instrumentation active in build:** `GameLog.mark()`, `GameLog.time_log()`, `[SPIKE]`, `[DIAG]` — strip or gate before final release.

## Steam / Upload

- Demo app `5337670` / depot `5337671` → `tools/app_build_5337670.vdf`. Upload: `powershell tools/steam_upload_playtest.ps1 -SteamUser damiandevz -SteamCmd "D:\User\Desktop\SteamworksSDK\sdk\tools\ContentBuilder\builder\steamcmd.exe" -AppId 5337670 -AppBuildVdf tools/app_build_5337670.vdf -Branch default`
- Full game app `5000810` (depot unverified, VDF `app_build_5000810.vdf` exists). Private/beta branches need no review; both MP peers must run same app.
- Latest demo build: **26345747** (has proc-attribution spikes). Skip broken 26345233.
- Session log: `%APPDATA%\Godot\app_userdata\Lemonade Stand Simulator\game_log.txt`
- 32 achievements wired in `achievement_manager.gd`; Steam-side entries are manual per-app (API names must exist in Steamworks or `setAchievement` fails silently).
- Achievements flagged: Neighborhood Favorite = all 100 roster NPCs (roster file has 141 lines but exactly 100 entries); Squeeze 'Em All counts press OR either machine; trash counts `is_regular_trash_type` only; "It's Delicious" = zero-complaint serve.
- Known unresolved: held-pitcher recipe wipe diagnostics pending; cumulative fruit branch bar = sum of all fruits' perfect serves.

## Build / Test

- **Stand/save access regression:** run the headless executable with `--path . --script res://tools/test_stand_access.gd`. Covers save-restore request coalescing/completion, per-stand lobby capacity, selection validation, reassignment, shared boxes, stale hand-mesh clearing, and actual local ENet RPC acceptance/rejection. It is not a full two-machine Steam session.
- Save application starts at the camera midpoint; keep the transition covered until `SaveManager.world_restore_completed`. Do not schedule a second default-layout restore after applying loaded container data.
- Headless runs never emit the rendered-frame signal needed by the held-pitcher reveal gate. Bypass that visual gate only for the headless display server; pending render callbacks previously caused the Squeeze-E-Z fixture to crash during engine teardown despite passing assertions. Use target-bound callables or weak references for delayed reveal callbacks when carried meshes can be freed before the timer runs.
- `PlayerInventory.set_held()` must reset its cached mesh even when the previous mesh was already freed. Godot compares a freed object equal to null, so the regression checks `typeof(...) == TYPE_NIL` to distinguish an actual cleared reference.
- Current bar progression is stored in each stand's `onboarding_progress["progress"]` and saved/restored through `OnboardingManager.serialize()/deserialize()` under the save's `onboarding` key. Empty legacy purchase-tree compatibility methods in `UpgradeManager` are not the current persistence path. The fruit-parity regression now JSON-round-trips both stands' progression and verifies that restored fruit unlocks remain isolated.

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

## Visual-lifecycle follow-up (2026-11-03)

- Hand-item transfer tweens must keep a nonzero scale; setting the whole carried scene to zero also gives its disabled physics bodies a singular transform. The stand-access regression samples transfer animations and checks cancelled placement-pop recovery and early object destruction.
- Timer lambdas capturing freed nodes fail before `is_instance_valid()` in their body can run. Delayed hand/world pitcher diagnostics and placement diagnostics now resolve weak references; placement-pop recovery uses the same lifetime-safe pattern.
- Deferred ghost cleanup must pass a weak reference, not a typed Node argument: a destroyed ghost otherwise fails argument conversion before the cleanup method starts.
- The box-placement regression now runs three actual press cycles, takes each lemon-only pitcher, destroys its ghost, and uses the real raycast/primary-interaction path to snap into a dispenser. It replaces AchievementManager with `tools/achievement_test_harness.gd` before creating stands so test actions cannot unlock/store real Steam achievements. APPDATA isolation alone does not isolate Steam account state.
- These fixes remove reproduced visual/callback errors; they do not establish the cause of the live pitcher lock, freezes, device loss, or heap corruption. Shutdown ObjectDB/resource warnings remain intermittent.

## Pitcher batch pickup regression (2026-11-03)

- The latest 10:11 host session proves the original batch was 2 lemons, 4 sugar, 2 ice, and 8 water. After four pours, pickup preserved that frozen serving recipe in saved_recipe, but the held mesh omitted serving_recipe/state. Subsequent placement copied the incomplete live mesh back over saved_recipe; cup five restarted the batch at remaining totals 1.2 fruit/2.4 sugar and initial volume 6 instead of 10.
- The hand-seeding omission also exists in demo baseline c573af0, but that baseline restores placement from saved_recipe directly. The later live-held-mesh snapshot path amplified it into a persistent cup-recipe regression. Preserve both the frozen serving_recipe (deep copy) and state when seeding a held pitcher; do not revert live-volume tracking or normalize ingredient counts.
- The box-placement regression reproduces the failure with four initial pours followed by three pickup/place/pour cycles, then drains the rest. Before the fix, 18 assertions failed; afterward the held label and every cup retain the original recipe and the pitcher yields exactly ten cups, with no extra pour. AchievementManager remains replaced by the test harness.

## Native-crash evidence (2026-11-02)

- Windows Application Error 1000 records the installed main-game executable faulting at 22:02:57 in `nvoglv64.dll` with `0xc0000005`, followed by a separate 22:08:09 fault in `ntdll.dll` with `0xc0000374` (heap corruption). These are observations, not identified gameplay triggers; do not collapse both into a single VRAM/driver explanation or equate them with the headless fixture teardown issue.
- The intermittent live pitcher-placement lock and the live crash trigger remain unconfirmed. The stale hand-mesh reset regression passing does not prove that reported interaction fixed.
- Native dumps exist in `%LOCALAPPDATA%/CrashDumps/WhenLifeGivesYouLemons.exe.<pid>.dmp`. November 2 PID 8512 matches the 22:02 NVIDIA crash; PID 103932 matches the 22:08 heap crash. PIDs 105152 (21:51) and 78312 (21:14) have the identical heap-corruption call chain, so group those as one repeated failure path, not independent bugs.
- The NVIDIA dump's caller constructs `VkDeviceFaultCountsEXT` (sType 1000341001) and calls the device-fault query with a null fault-info pointer. The driver AV therefore occurs while collecting diagnostics after device loss; it does not identify the initial GPU-loss trigger. Do not mistake the nearest exported symbol `vkGetInstanceProcAddr+...` for the actual internal driver function.
- Heap dumps detect corruption in `msvcrt!free` on the main thread, with repeated executable return RVAs `0x407a013 -> 0x2acea8c -> 0x26b4eb3 -> 0x62bc5 -> 0x65647 -> 0x5dcf7`. This is a cleanup/free detection site, not evidence of where the original bad write happened. The pointed-to heap objects are not available in these minidumps.
- The matching release template has PE timestamp `0x6a6425fa`, image size `0x6b37000`, no COFF symbols, and no PDB record. Debugger `NoHotPatch+...` labels are export-relative placeholders, not resolved C++ function names. Installed Windows `dbgeng.dll` can read the dumps without installing WinDbg; the SDK header is under Windows Kits 10/Include/10.0.19041.0/um/DbgEng.h. Read-only helpers are currently in `%LOCALAPPDATA%/Temp/diagnose_dump_stack.py` and `diagnose_pe_symbols.py`.
- MultiMesh transform-format errors reproduce using `ResourceLoader.CACHE_MODE_REPLACE` on either neighborhood scene with no gameplay nodes instantiated; initial loads are clean and both files already serialize transform_format before instance_count. Do not alter authored grass buffers to mask an editor/cache-reload warning. Full Vulkan main-scene startup exits normally but still reports seven leaked texture RIDs at shutdown.

## Shutdown diagnostic isolation (2026-11-03)

- Verbose box-placement teardown identifies the intermittent two ObjectDB leaks as AudioStreamMP3 and AudioStreamPlaybackMP3 for `Autumn Day.mp3`, not gameplay nodes. An autoload-only/no-gameplay fixture reproduced the warning in three runs; stopping music, clearing its stream, and waiting 0.2 seconds before quitting avoided it in three comparison runs. This is teardown evidence, not proof of the live native-crash cause; no production audio shutdown behavior has been changed.
- The seven leaked Texture RIDs reproduce in a temporary scene containing only a box, camera, and UPDATE_ONCE ReflectionProbe under both Vulkan and D3D12. The same scene without the probe exits without that warning. No authored neighborhoods, gameplay nodes, or main-world scripts are instantiated in that minimal scene (project autoloads still run). Loading main.tscn without instantiation is clean; instantiating and freeing the main world five frames before quit still produces seven leaked textures. Removing reflection probes before rendering prevents it. Do not disable shipped reflections or attribute the live GPU-loss/heap crashes to this shutdown warning without further evidence.
- Temporary reproduction scripts are `%LOCALAPPDATA%/Temp/diagnose_audio_shutdown.gd`, `diagnose_main_resource_shutdown.gd`, and `diagnose_reflection_shutdown.gd`; these are diagnostics, not shipped fixes. The first direct main-instantiation attempt had fixture current_scene timing errors; subsequent tests use change_scene_to_packed and scene_changed and do not emit those errors.
- User approved temporary full-crash capture on November 3. This terminal is not elevated; no Windows WER registry settings were changed. Instead, Microsoft-signed ProcDump 12.02 was downloaded to `%LOCALAPPDATA%/Temp/LemonadeCrashCapture-20261103-110019`. `%LOCALAPPDATA%/Temp/watch_lemonade_crash.ps1` invokes `-ma -e -n 1 -w WhenLifeGivesYouLemons.exe`: one unhandled-exception full dump, no normal-exit dump, overwrite, upload, persistent debugger registration, or process-kill flag. It restores the prior ProcDump EULA preference on exit. Capture folder/state/log are `%LOCALAPPDATA%/CrashDumps/LemonadeFull-20261103-110343`. Never delete collected dumps without asking.
- A fresh local export of pushed c0d0a97 was built for that session; Steam was not uploaded. The temporary launcher `%LOCALAPPDATA%/Temp/launch_lemonade_crash_test.ps1` explicitly sets full-game SteamAppId/SteamAppID=5000810 and passes `-- --diagnose-stalls`. The bundled ignored steam_appid.txt could not be read through agent tools, so do not infer its contents. ProcDump confirmed attachment to the local export (PID 4640 at 11:04), not the Steam-installed copy. Normal game exit ends one-shot monitoring; rearm explicitly for another test if needed.

## Captured full shutdown crash (2026-11-03, local c0d0a97)

- User reported gameplay seemed fine with no visible crash. ProcDump nevertheless caught unhandled C0000374 at 11:06:49 after the game log reached `[Quit] teardown: steamShutdown 23ms`. Do not describe this as a proven mid-game crash; user was asked whether they had clicked Quit. Dump completed at 11:07:52: 5957 MB at `%LOCALAPPDATA%/CrashDumps/LemonadeFull-20261103-110343/WhenLifeGivesYouLemons.exe_261103_110649.dmp`. Capture has exited; EULA preference restoration ran. No WER crash settings changed, no upload/deletion, no monitor remains armed.
- The full dump matches the retained heap-crash stack. Unlike the minidumps, its memory permits native RTTI identification: caller object at 0x160dfb923f0 has RTTI `17RendererSceneCull`; its allocator diagnostic string is `N17RendererSceneCull8InstanceE`. The detected free occurs during renderer instance destruction/DependencyTracker dependency removal, not in an identified pitcher callback or audio destructor. This narrows the detection site; it does not yet prove the original bad write/free or a safe fix.
- Dump-specific pointers for continued analysis: native image base 0x7ff7a5780000; free return RVAs 0x407a013 -> 0x2acea8c -> 0x26b4eb3 -> 0x62bc5 -> 0x65647 -> 0x5dcf7. Renderer instance 0x161f87311a0 has base_type=1 (mesh), base RID 0x000129230000035e, dependency tracker at +0x250 (0x161f87313f0). Its probable object_id at +0x200 is 0x15dc9003399 (layout checked against renderer_scene_cull.h; source revision is not yet proven identical). Dependency map 0x160c6b251c8; failing HashMap element user pointer 0x161ca79eee0. Heap failure record 0x7ffeb046e0e0 contains version/size 2/0x6d0, failure type 8, heap 0x160dcc10000, and heap-entry pointer 0x161ca79eed0.
- `%LOCALAPPDATA%/Temp/diagnose_dump_stack.py` accepts the dump path and additional debugger commands; inspect bounded structural metadata/code/RTTI, not arbitrary private heap strings. System dbgeng works, but Windows symbols/extensions are currently missing; `.reload /f ntdll.dll` with `.symfix .../Temp/LemonadeSymbols` failed. SDK has `C:/Program Files (x86)/Windows Kits/10/App Certification Kit/symsrv.dll`; no ext.dll/cdb.exe/dbghelp.dll found under that SDK tree. Nearest-export labels such as ntdll RtlpMuiRegCreateRegistryInfo are not resolved private function names.
- Latest gameplay log independently confirms original batch initial volume stays 10 through pickup after four cups and all ten pours complete; no recipe rebase to volume 6. It also contains isolated placement rejections (lemon-only pitcher over PrepTable, and a full pitcher over dispenser); these are not proof of the previously reported persistent lock, which the user did not observe in this run.
- Latest engine log `user://logs/godot.log` explicitly confirms normal quit: line 217 `[Main] quit: exiting after 2784ms total`, then lines 219-221 the three teardown messages. No SCRIPT ERROR or RID leak text appears before the captured fatal error. This was detected after normal Quit, not a user-observed gameplay crash. Do not conflate this with the separate Vulkan device-loss crash or claim all older failures were normal quits.
- Trying the SDK App Certification Kit symsrv.dll with Python AMD64 failed WinError 193 (wrong architecture). The temporary ctypes helper was restored to its working original form afterward. Windows symbols are still unresolved. Native RTTI evidence comes from bounded module typeinfo reads, not guessed nearest exports: RendererSceneCull vtable 0x7ff7ab917550 -> typeinfo 0x7ff7ab8005c0 -> static name at 0x7ff7ab85cb40. Current upstream renderer_scene_cull.h and storage/utilities.h were read for layout/context only; their exact revision match to the custom July 25 engine is not established.

## Save coverage audit (2026-11-03)

- Quit saves synchronously before analytics and SceneTree.quit: main.gd _on_esc_quit_game flushes upgrades, calls SaveManager.save_game(true), then awaits Analytics.send_and_wait. Latest real session logged save+flush=6ms, then exit after 2784ms. Its actual `saves/test.json` is valid JSON with saved_at=1793700406.972 (quit log rounded epoch=1793700407.0), money=87.15, 10 placed containers, and 9 supply boxes. The later renderer shutdown failure did not prevent that save being written; do not generalize this to a crash during file writing.
- Temporary `%LOCALAPPDATA%/Temp/audit_save_coverage.gd` exercises production _build_save_dict -> JSON -> apply_save_to_game_state -> deferred world restoration with isolated APPDATA and the achievement harness installed before stand fixtures. Both stands retain NPC affinities, perfect-cup progress and fixed requirements (JSON keys normalized through get_npc_collection), current progression counters/claimed tiers, isolated fruit unlocks, computed press-speed effects, discovered recipes, board recipes and prices. All 12 registered placed-object types are serialized/restored; stock checks cover fruit/sugar/ice bins, cup count, press fruit load, dispenser fillings, machine sugar stock/inserted pitcher, and a partially poured pitcher's original batch. These are headless controlled-fixture checks, not a fresh live two-peer reload test or exhaustive validation of every legacy save.
- Confirmed unresolved content-loss gap: production pickup_container removes ordinary containers from the world; held meshes are deliberately excluded from world groups/scans, and _build_save_dict has no held-inventory recovery block. Actual pitcher pickup leaves zero saved pitcher entries. Actual SupplyBox._pick_up_player likewise despawns an equipment box; the carried box is absent from supply_boxes. Saving/leaving while carrying these can omit owned contents/purchases independently of the shutdown crash. No gameplay fix has been made during this audit. Do not re-add hand meshes to world groups as a shortcut; that previously caused interaction/network lookup regressions.
- Write durability gap: SaveManager._do_save opens the live JSON path with FileAccess.WRITE, stores/closes directly, and has no atomic replacement/backup scheme. A failure during that write could damage the previous file. This is a code-inspection risk, not observed corruption in the captured session.
- Final audit assertions passed and process exited 0, with six ObjectDB/three resource cleanup warnings remaining. Initial matrix fixture errors were corrected: typed FruitBin dictionaries require element assignment, and direct scene instantiation of Press/Cup must explicitly add the container group to emulate deployment; those fixture errors were not established gameplay bugs. The real save was read only; all fixture saves were disabled (empty current slot).

## Computer UI exposure and locked names (2026-11-03)

- Computer screen shader must clamp texture-linear RGB BEFORE applying inverse-exposure `boost`. Clamping after boost clips bright UI pixels at low day/night exposure and crushes contrast. Rendered probes reproduced a 0.349 brightness spread before correction and zero afterward; white and grey probes passed with glow enabled, including Vulkan and D3D12 white checks. Do not change world lighting or viewport update scheduling for this fix.
- Morning hub locked machine cards use `Unknown Equipment`; real names appear at claimed technology tier 1 (Squeeze-E-Z) and 2 (Fruit-O-Matic). Locked fruits remain `Unknown Fruit`. Nine native card checks passed. Temporary probes: `C:/Users/sw3at/AppData/Local/Temp/test_computer_colors.gd` and `test_locked_equipment_names.gd`; isolate APPDATA and fake achievement writes.
- Previous save fixes were pushed as `bddad52` and uploaded to full-game App 5000810, BuildID 26405522 (manual branch activation). These newer UI changes are local until separately committed/exported/uploaded.

## Implemented locally — carried-item persistence and safe writes (2026-11-03)

- Supersedes the audit gaps above. User rule: restore the same player's hands, transfer the item to their newly assigned stand, never restore old stand privileges or auto-place ordinary carried items at pickup positions. World-placement recovery was removed.
- Save `player_inventories` uses server-resolved Steam identity (`get_steam_id_for_peer_id` on SteamMultiplayerPeer), with local fallback only for the local offline player. Cache identity before disconnect; preserve disconnected players' records. Host writes only. Inventory RPC restoration accepts host sender only and waits for world/stand readiness.
- Retained tables/trays/appliances remain single hidden source objects, with attached objects linked in the save and snapshot. Hand models and ghost descendants must not enter placed-object saves/snapshots. Machine colors are encoded recursively for JSON.
- Atomic writer validates `.tmp`, preserves valid previous JSON through `.bak.tmp` -> `.bak`, then replaces primary. Load falls back to backup; backup-only slots list once; deletion removes companions. Do not execute deletion tests against user saves.
- Verified `tools/test_save_persistence.gd`: actual pitcher/box pickup, live poured amounts and original recipe, partial supply stock, cup colors, table plus attached cup, held appliance stock/output, stand transfer/access, no duplication/new-save inheritance, two-local-peer restore RPC and client-forgery rejection, final-rename failure, corrupt/missing primary fallback, good-backup preservation, backup-only listing and deletion.
- Five suites pass: save persistence, stand access, box placement, fruit parity, lemonader. Main-scene headless startup reaches menu without parse/script errors; dummy-renderer emoji texture errors remain. Headless cleanup still reports two ObjectDB instances/one resource in some suites. `gdlint` is unavailable in this shell. These are not a full Steam reconnect/rendered release sign-off.
- Command: `tools/godotsteam-editor/godotsteam.471.editor.win64.console.exe --headless --path . --script res://tools/test_save_persistence.gd`, isolated APPDATA=`C:/Users/sw3at/AppData/Local/Temp/LemonadePersistenceTests`. Achievement test harness prevents real Steam unlocks. Inventory RPC fixture overrides only outgoing global-singleton mirroring because its peers use subtree MultiplayerAPIs.
- LOCAL, UNCOMMITTED, not exported/uploaded. Existing upload logs remain unstaged. Native renderer crash, intermittent live lock, audio/reflection teardown and release gates remain separate unresolved tasks. No user saves or crash dumps were modified/deleted. User explicitly requests tighter scope, less narration and finishing verification rather than expanding investigations.

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

## Multiplayer / Stall Diagnostics

- Known-good demo Steam BuildID `26100722` (App `5337670`) is paired with Git commit `c573af0aa2764973e846ed2de138499162c95fd0`. Evidence: the push → export → BuildID sequence in `history_62a5057d6d474565.md` (CLI summaries, messages 184–191) and SteamCMD `ContentBuilder/builder/logs/console_log.txt`, which records successful upload on 2026-10-21 at 10:05:28 local time (UTC+2, equivalent to 01:05 PDT). Do not substitute the later smooth `b41a20b` baseline for this exact demo revision.
- Run `tools/test_box_placement.gd`, `tools/test_dispenser_snapshot.gd`, `tools/test_local_player_identity.gd`, and `tools/test_invite_popup.gd` with the headless Godot executable and `--path . --script res://<test path>`.
- Pass `-- --diagnose-stalls` to opt into GameLog frame-stall tracing and viewport CPU/GPU render timing. Samples can lag the reported frame. The box-placement test also checks this mode using an intentional 300 ms pause; it is not a performance benchmark.
- `test_box_placement.gd` checks host placement of a lemon-only pitcher onto a dispenser without emptying it. This exercises recipe restoration and snap placement, not the complete camera/raycast or live two-peer flow.
- Preserve rotated `user://logs/godot*.log` files when investigating crashes; `game_log.txt` does not capture all native engine errors. A Vulkan fence error with result `-4` means device loss, not proof of a specific script fault. The November 2 test had a matching NVIDIA driver event 153 at 22:02:56; the trigger remains unconfirmed.
