# Onboarding Plan

## Purpose

Onboarding is a contextual checklist that teaches the lemonade stand loop by asking players to perform real actions in the world. Tasks appear one at a time. When the active task is completed, it is visibly crossed out, remains on screen briefly, and is then replaced by the next task.

Onboarding progression belongs to a **stand**, not an individual player:

- Solo has one onboarding progression.
- Co-op has one shared progression for everyone assigned to the stand.
- Versus has separate progression for each stand.
- Any assigned teammate can complete the stand's active task.
- Completion immediately updates the checklist for every player assigned to that stand.
- Rival players must never complete or receive another stand's tasks.

The system should teach normal gameplay rather than create tutorial-only versions of interactions.

## Design Principles

1. **Learn by doing.** A task completes only after the corresponding gameplay result is confirmed.
2. **One objective at a time.** Do not show a large list that competes with interaction hints.
3. **Stand-scoped, host-authoritative state.** The host validates completion against the stand that owns the action.
4. **No duplicated rewards or mutations.** Onboarding observes completed gameplay actions; it does not repeat them.
5. **Flexible co-op roles.** Teammates may split work. The system cares that their stand completed the objective, not which teammate did it.
6. **No forced failure.** The tutorial should not require making a bad drink, losing a customer, or wasting limited resources.
7. **Resumable and idempotent.** Repeated events cannot advance a task twice, and reconnecting restores the authoritative state.
8. **Action-based checks.** Avoid checking only inventory totals, money, or object presence when those values could have existed before the task began.
9. **Minimal blocking.** Normal play remains available. The onboarding guides players but does not disable unrelated interactions unless a later playtest proves that restriction necessary.

## Player Experience

### Checklist presentation

- Place a compact onboarding panel below or near the existing HUD objectives area.
- Show the active task with a short instruction and optional control hint.
- A completed task changes to a checked/struck-through state for approximately one second.
- The next task then slides or fades into the same location.
- Show progress such as `4 / 10` without revealing a long wall of future instructions.
- Allow players to collapse the panel without stopping progression.
- Include `Skip onboarding` behind a confirmation prompt.
- Only local UI is rendered; its data comes from the local player's assigned stand.

### Wording rules

- Describe the result, not implementation details: `Order lemon supplies`, not `Emit an order event`.
- Include the relevant input only when first introduced.
- Keep each task to one primary action or one tightly connected result.
- Use current game terminology from interaction hints and menus.

## Task Model

Each task definition should contain data rather than hardcoded UI logic:

```text
id                  Stable identifier used by saves and networking
track               DEMO or FULL
instruction         Short objective text
control_hint        Optional input hint
completion_event    Semantic gameplay event to observe
completion_rule     Event fields and required count/value
prerequisites       Normally the previous task; supports future branching
optional            Whether the task may be omitted without blocking completion
```

Per-stand runtime state:

```text
track_id             DEMO or FULL
current_task_id      Active objective
completed_task_ids   Set/array of stable task IDs
completed            Whether the track is finished
started              Whether onboarding has begun for this stand
skipped              Whether the stand chose to skip it
revision             Monotonic state revision for replication
```

Task IDs must remain stable after release. Text can change without invalidating saves.

## Proposed Demo Onboarding

The demo onboarding should teach one complete sale with the fewest necessary concepts. It should finish early enough that the player has time to play independently.

| # | Task ID | Player-facing objective | Completion condition for this stand | Why it exists |
|---|---|---|---|---|
| 1 | `demo_move` | Move around with WASD | An assigned player moves a minimum cumulative distance under their own input | Basic navigation |
| 2 | `demo_open_phone` | Open your phone with Tab | An assigned player opens the stand's phone/order menu | Introduces ordering |
| 3 | `demo_order_lemons` | Order lemon supplies | Host accepts an order containing lemons charged to this stand | Introduces supplies and stand money |
| 4 | `demo_stock_lemons` | Put the delivered lemons into the lemon bin | A lemon delivery box belonging to this stand deposits into this stand's lemon bin | Teaches delivery handling |
| 5 | `demo_add_lemon` | Add lemons to the pitcher | This stand's active pitcher receives lemon from its fruit bin | Starts drink preparation |
| 6 | `demo_add_water` | Add water to the pitcher | This stand's active pitcher receives water from its dispenser/bin | Teaches the liquid base |
| 7 | `demo_add_sugar` | Add sugar to the pitcher | This stand's active pitcher receives sugar | Introduces recipe quality |
| 8 | `demo_finish_pitcher` | Pick up the prepared pitcher | This stand's pitcher changes from preparing to sealed/held with lemonade in it | Teaches sealing the recipe |
| 9 | `demo_place_pitcher` | Place the pitcher at your serving area | The prepared pitcher enters this stand's serving state | Connects prep to service |
| 10 | `demo_fill_cup` | Fill an empty cup with lemonade | A cup is filled from this stand's serving pitcher | Teaches cup workflow |
| 11 | `demo_serve_customer` | Serve a waiting customer | This stand's customer accepts the filled cup | Completes the central loop |
| 12 | `demo_collect_payment` | Collect the customer's payment | Payment from that sale is collected for this stand | Completes the economy loop |

### Demo scope decisions

- Do not require upgrades, end-of-day flow, advanced fruit, equipment rearrangement, or trash cleanup.
- Do not require a happy outcome for the first sale. The player has learned the serving loop even if the recipe needs improvement.
- Give contextual recipe guidance in the task detail or existing UI, but keep the completion condition action-based.
- If the starting setup already includes enough lemons, task 3 can still require a small order so delivery is taught. The order quantity/cost may need a tutorial-safe minimum to avoid unnecessary resource pressure.
- If sugar or cups are not available in the starting stand configuration, the demo setup must guarantee them before this sequence is enabled.

## Proposed Full-Game Onboarding

The full-game track includes the demo's core service loop, then introduces management and the day cycle. Shared IDs should be used for shared tasks so migration and analytics remain understandable, but the full sequence may supply different text or prerequisites.

### Phase A — Learn the core loop

Use the same twelve tasks as the demo track.

### Phase B — Learn stand management

| # | Task ID | Player-facing objective | Completion condition for this stand | Why it exists |
|---|---|---|---|---|
| 13 | `full_set_price` | Set your lemonade price | The host accepts a price change for this stand | Introduces business control |
| 14 | `full_edit_recipe` | Review or update your lemonade recipe | The host accepts a recipe change for this stand | Introduces recipe planning |
| 15 | `full_place_order` | Place a supply order for your stand | Any non-tutorial-specific supply order is accepted and charged to this stand | Reinforces stock planning |
| 16 | `full_stock_delivery` | Stock one delivered supply box | A box from that order is deposited into a matching container owned by this stand | Reinforces delivery ownership |
| 17 | `full_serve_happy` | Serve a customer who enjoys the drink | This stand records a `happy` customer outcome | Teaches quality feedback |
| 18 | `full_handle_trash` | Throw away one piece of trash | Trash is authoritatively disposed in a trashcan by an assigned player | Introduces cleanup |

### Phase C — Learn progression

| # | Task ID | Player-facing objective | Completion condition for this stand | Why it exists |
|---|---|---|---|---|
| 19 | `full_buy_upgrade` | Purchase an upgrade for your stand | An upgrade purchase succeeds for this stand | Introduces long-term progression |
| 20 | `full_finish_day` | Finish the day | The authoritative day phase reaches evening after this stand participated in the day | Introduces the daily rhythm |
| 21 | `full_review_summary` | Review the day summary | An assigned player opens/acknowledges the summary for this stand | Teaches performance review |
| 22 | `full_start_next_day` | Prepare for the next day | The next morning begins and the stand returns to playable preparation | Closes the full loop |

### Full-game scope decisions

- Equipment placement should not be mandatory in the first onboarding unless the final starting flow requires players to build their initial stand. If initial equipment starts boxed, add a short setup phase before `demo_open_phone`:
  - `full_place_workstation`
  - `full_place_required_equipment`
- Research and advanced fruit should be taught contextually when first unlocked, not forced into the first-day checklist.
- A happy-sale task belongs after players can inspect/edit recipes; requiring it for the very first sale risks blocking progress on an unclear failure.
- Upgrade selection should be free-choice. Onboarding observes any valid stand upgrade instead of prescribing a build.

## Multiplayer and Stand Ownership

### Authority flow

Onboarding must follow the existing request/host-apply/broadcast model:

1. A gameplay system finishes a meaningful action and reports a semantic event with its stand identity.
2. The host resolves the event to a `StandUnit` and validates that the event belongs to that stand.
3. The host compares the event with only that stand's active task.
4. If it matches, the host marks the task complete once, advances the stand, increments its revision, and broadcasts the new state.
5. Each client updates only the onboarding UI bound to its local player's `assigned_stand`.

Clients must not request arbitrary task IDs as completed. At most, they request the underlying gameplay action; the host derives onboarding completion from the accepted result.

### Stand identity

- Use the authoritative `StandUnit` identity, not the local player's current location or the first stand in a group.
- Every completion event must carry or resolve an owning stand.
- Player-driven events must verify that the initiating peer is assigned to the event's stand.
- Object-driven events use the owning stand of the pitcher, box, bin, customer, payment, or trash interaction.
- In Versus, stand A and stand B maintain independent current/completed task sets.

### Co-op behavior

- All teammates assigned to a stand see the same active task and progress count.
- Any teammate may complete it.
- Completion broadcasts simultaneously to every teammate.
- Tasks must not depend on one player's held item carrying over to the next task. For example, if player A seals the pitcher and player B places it, both actions are valid for the shared sequence.
- Skip is a stand-level decision. Recommended policy: only the host may skip during the first implementation, avoiding a teammate unilaterally removing onboarding for everyone.

### Versus behavior

- Each stand starts and advances independently.
- A rival action cannot satisfy the local stand's task even if the action type is identical.
- The HUD only shows the assigned stand's onboarding. Rival onboarding progress should remain private unless the game later intentionally exposes it.
- Day-global tasks such as `full_finish_day` require careful handling because both stands share the day phase. Each eligible stand can complete that task when the host changes phase, but only if that stand reached/activated it before the transition.

### Late join and reassignment

- A late joiner receives the current onboarding state with the rest of the authoritative stand/world snapshot.
- Joining a stand already midway through onboarding shows that stand's current task; completed tasks are not replayed.
- Reassignment switches the local HUD to the new stand's state.
- Disconnecting the player who performed the last action does not change stand progress.
- An empty stand retains its onboarding state for reconnects and saves.

## Event Integration

Use semantic events emitted only after authoritative success. Suggested events include:

```text
player_moved(stand, peer_id, distance)
phone_opened(stand, peer_id)
order_accepted(stand, order_id, contents)
supply_deposited(stand, box_id, ingredient_type, quantity)
pitcher_ingredient_added(stand, pitcher_id, ingredient_type, amount)
pitcher_state_changed(stand, pitcher_id, old_state, new_state)
cup_filled(stand, cup_id, pitcher_id)
customer_served(stand, customer_id, outcome)
payment_collected(stand, payment_id, amount)
price_changed(stand, fruit_type, value)
recipe_changed(stand, fruit_type, recipe)
trash_disposed(stand, trash_id, trash_type, peer_id)
upgrade_purchased(stand, upgrade_id)
day_phase_changed(phase, day)
day_summary_acknowledged(stand, peer_id)
```

These should be domain-level notifications, not UI button signals. A task should complete whether the action came from mouse input, keyboard input, a future controller binding, or another valid interaction path.

## Persistence

Onboarding progress should be saved per stand with the rest of the host's save data:

```text
onboarding:
  version: 1
  stands:
    Stand1:
      track_id: FULL
      current_task_id: full_set_price
      completed_task_ids: [...]
      completed: false
      skipped: false
    Stand2:
      ...
```

Requirements:

- New saves start the appropriate track.
- Existing saves created before onboarding need an explicit policy. Recommended default: offer onboarding once rather than forcing it on.
- Demo saves use the demo track and do not silently migrate into later full-game tasks.
- Loading is host-only; clients receive state from the host.
- Unknown or removed task IDs should fall forward to the next valid task rather than corrupting the save.

## Recommended Architecture

### `OnboardingTask` resource/data definition

Stores immutable task metadata and matching rules. Definitions are shared by all stands and contain no live progress.

### `OnboardingManager`

A host-authoritative world-level coordinator that:

- owns the task catalog;
- receives semantic gameplay events;
- routes each event to the correct stand;
- advances only the matching active task;
- serializes/deserializes progress;
- synchronizes state for initial joins and updates.

### Per-stand state

Store the runtime progress on `StandUnit` or in an `OnboardingManager` dictionary keyed by stable stand ID. Prefer manager-owned dictionaries initially if changing `StandUnit.push_state()` would resend unrelated economy data for every tutorial update. Regardless of storage location, the public API should be stand-scoped.

### `OnboardingPanel`

A presentation-only HUD component that:

- binds to `WorldSync.get_local_stand()`;
- displays the current task and progress;
- plays completion/transition animation;
- supports collapse and skip requests;
- never decides that a gameplay task is complete.

## Edge Cases and Anti-Exploits

- Events that occurred before a task became active do not retroactively complete it unless explicitly marked as state-based.
- Duplicate reliable RPCs or repeated signals are harmless because completion checks the active task and completed ID set.
- Failed orders, unaffordable purchases, rejected placements, and invalid serves do not count.
- Interacting with rival objects does not count for either stand unless that interaction is an intentionally valid rival mechanic.
- A payment cannot count twice if two teammates click it at nearly the same time.
- Debug/cheat actions should not advance onboarding by default.
- Skipping onboarding never grants items, money, sales, upgrades, or task rewards.
- If a required object is missing or destroyed, onboarding should not hard-lock the save. Provide task recovery or a validated skip path.
- If two teammates complete the same objective during the same host frame, only the first accepted event advances it; the second must not accidentally satisfy the newly activated task.

## Analytics and Playtesting

Useful non-gameplay analytics per task:

- task started;
- task completed;
- elapsed time;
- skip point;
- number of failed/rejected attempts where available;
- solo/co-op/versus and team size.

Do not transmit analytics until the project's consent and telemetry policy is defined. Local debug logging is sufficient during development.

Playtest matrices:

1. Solo demo from a new save.
2. Two-player co-op where players alternate every task.
3. Two-player co-op where both attempt the same task simultaneously.
4. Versus with both stands at different task indices.
5. Rival player interacting near the other stand's tutorial objects.
6. Late join into a partially completed track.
7. Disconnect/reconnect of the player who completed a task.
8. Save/load midway through each phase.
9. Skip onboarding, then save/load.
10. Day transition while versus stands are on different tasks.

## Implementation Phases

### Phase 1 — Foundation

- Finalize task wording and demo/full track selection rules.
- Add stable task definitions and per-stand runtime state.
- Add host-authoritative advancement and snapshot synchronization.
- Add save migration and persistence.

### Phase 2 — Core demo track

- Add semantic events for the twelve demo tasks.
- Add the HUD checklist and completion transition.
- Verify solo, co-op, versus isolation, and late join.

### Phase 3 — Full-game extension

- Add management, upgrade, trash, and day-cycle events.
- Add the full-game continuation tasks.
- Add existing-save opt-in and contextual post-onboarding tips.

### Phase 4 — Polish

- Add highlighting or world markers only where playtesting shows players cannot locate an objective.
- Add accessibility options for animation speed, text size, and panel visibility.
- Tune wording and sequence from completion-time/drop-off data.

## Open Product Decisions

These should be decided before implementation:

1. How is Demo versus Full selected: separate build flag, save type, platform entitlement, or menu choice?
2. Does the demo begin with a prebuilt functional stand, or must players unpack/place equipment?
3. Does every new stand start onboarding, or only stands in a newly created save?
4. Who may skip shared onboarding: host only, stand leader, or unanimous stand vote?
5. Should an experienced player joining a new teammate's stand see the shared panel automatically or have it collapsed locally?
6. Should the full-game onboarding require the first happy customer, or accept any served customer and teach recipe improvement contextually?
7. Are onboarding tasks purely instructional, or will any task grant rewards? Recommended: no rewards in the first implementation.
8. Should onboarding pause or constrain the day/customer spawner? Recommended: allow the preparation tasks to finish before customer pressure begins, then start normal simulation.

## Recommended First-Version Decisions

For the smallest reliable implementation:

- Select the track from an explicit save/build field, not inferred content availability.
- Start with a prebuilt stand and the twelve-task demo sequence.
- Continue into the ten full-game tasks only in the full game.
- Start onboarding once per stand on new saves.
- Make skip host-only and stand-wide.
- Keep experienced teammates' panel collapsible locally but progression shared.
- Do not grant onboarding rewards.
- Delay normal customer spawning until the stand reaches `demo_place_pitcher`, preventing customers from timing out while players learn preparation.
