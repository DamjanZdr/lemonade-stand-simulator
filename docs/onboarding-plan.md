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
instruction         Short objective text with named crossable spans
parts               Compound-task spans and the completion rule for each span
control_hint        Optional input hint
completion_event    Semantic gameplay event to observe
completion_rule     Event fields and required count/value
prerequisites       Normally the previous task; supports future branching
optional            Whether the task may be omitted without blocking completion
```

Compound objectives remain sentences rather than becoming bullet lists. Each independently completed
word or phrase is a named span that the UI can cross out. For example:

```text
Order a {crate}, {press}, {bucket}, {bowl}, and {pitcher}.

crate   -> equipment_ordered(crate)
press   -> equipment_ordered(press)
bucket  -> equipment_ordered(bucket)
bowl    -> equipment_ordered(bowl)
pitcher -> equipment_ordered(pitcher)
```

If only the crate and bowl have been ordered, only those two words are crossed out. The objective
advances after every named span is complete.

Per-stand runtime state:

```text
track_id                 DEMO or FULL
current_task_id          Active objective
completed_task_ids       Set/array of stable task IDs
completed_parts          Named spans completed in the active compound task
suspended_task_state     Task and parts hidden by the temporary day-end objective
completed                Whether the track is finished
started                  Whether onboarding has begun for this stand
skipped                  Whether the stand chose to skip it
revision                 Monotonic state revision for replication
```

Task IDs must remain stable after release. Text can change without invalidating saves.

## Proposed Demo Onboarding

The Demo starts from an unbuilt stand, teaches the complete physical workflow, and ends with the player
researching and mastering one additional fruit. The recipe-mastery finale is intentionally a longer-term
goal after the guided controls and service loop are understood.

### Phase A — Build the stand

| # | Task ID | Player-facing objective | Completion condition for this stand |
|---|---|---|---|
| 1 | `demo_order_workstation` | Order a workstation from your computer. | The host accepts and charges this stand for a workstation order. |
| 2 | `demo_place_workstation` | Place the workstation inside your stand. | The delivered workstation is validly placed on this stand's floor. |
| 3 | `demo_order_equipment` | Order a crate, press, bucket, bowl, and pitcher. | Cross out each equipment word when its order is accepted; advance when all five are ordered. |
| 4 | `demo_order_ingredients` | Order boxes of lemons, sugar, and ice. | Cross out each ingredient when its supply order is accepted for this stand. |
| 5 | `demo_stock_ingredients` | Place the lemons in the crate, sugar in the bowl, and ice in the bucket. | Cross out each full phrase after the matching delivery is deposited into this stand's matching container. |

### Phase B — Make the first pitcher

| # | Task ID | Player-facing objective | Completion condition for this stand |
|---|---|---|---|
| 6 | `demo_place_pitcher_press` | Place the pitcher beneath the press. | This stand's pitcher is placed in its press slot. |
| 7 | `demo_load_press` | Put at least one lemon into the press. | At least one lemon from this stand is loaded into the press. |
| 8 | `demo_squeeze_lemons` | Squeeze the lemons until they are completely dry. | Every lemon currently loaded in the press has been fully squeezed. |
| 9 | `demo_add_sugar_ice` | Add at least one scoop each of sugar and ice to the pitcher. | Cross out `sugar` and `ice` independently when at least one scoop of each enters the pitcher. |
| 10 | `demo_place_water_dispenser` | Place the pitcher on the water dispenser. | This stand's pitcher enters the water-dispenser slot. |
| 11 | `demo_fill_water` | Fill the rest of the pitcher with water. | The pitcher reaches its liquid capacity through the dispenser. |
| 12 | `demo_place_pitcher_stand` | Place the finished pitcher on your stand. | The prepared pitcher enters this stand's serving position. |

### Phase C — Make the first sale

| # | Task ID | Player-facing objective | Completion condition for this stand |
|---|---|---|---|
| 13 | `demo_order_place_cups` | Order cups and place them on your stand. | Cross out `Order cups` when accepted and `place them on your stand` when the delivered cups are validly placed there. |
| 14 | `demo_fill_cup` | Fill at least one cup with lemonade. | A cup is filled from this stand's serving pitcher. |
| 15 | `demo_ask_customer` | Ask a customer what they would like. | An assigned player asks a customer queued for this stand for their order. |
| 16 | `demo_serve_customer` | Serve the customer their order. | That customer accepts the requested drink from this stand. |
| 17 | `demo_correct_change` | Give the customer the correct change. | This stand completes the transaction with the correct change. |

### Phase D — Learn business and recipe controls

| # | Task ID | Player-facing objective | Completion condition for this stand |
|---|---|---|---|
| 18 | `demo_set_price` | Increase the lemonade price to $1.00. | The host accepts a $1.00 lemon price for this stand; the starting price should be $0.80. |
| 19 | `demo_record_recipe` | On the recipe board, record the lemons and sugar used in your latest pitcher. | Cross out `lemons` and `sugar` when each board value matches the most recently prepared lemon pitcher. |
| 20 | `demo_set_ice_ratio` | Set how many degrees the temperature must rise before adding another ice cube. | This stand changes its global degrees-per-additional-ice setting on the recipe board. |

### Phase E — Master lemonade

| # | Task ID | Player-facing objective | Completion condition for this stand |
|---|---|---|---|
| 21 | `demo_master_lemon` | Use customer feedback to perfect your lemon recipe. | Five consecutive eligible customers evaluate the same perfect lemon-and-sugar candidate without a strength or sweetness complaint. |
| 22 | `demo_set_perfect_lemon` | Set your perfected lemon recipe on the recipe board. | The lemon and sugar board values both match the now-discovered perfect lemon recipe. |
| 23 | `demo_master_ice` | Use customer feedback to perfect your ice setting. | Five consecutive eligible customers evaluate the same perfect global ice candidate without a temperature complaint. |
| 24 | `demo_set_perfect_ice` | Set your perfected ice ratio on the recipe board. | The global board value matches the now-discovered perfect ice ratio. |
| 25 | `demo_research_second_fruit` | Research and unlock a second fruit. | This stand purchases its one permitted Demo fruit unlock. |
| 26 | `demo_prepare_second_fruit` | Order, prepare, and serve lemonade made with your new fruit. | Cross out the three sentence phrases as this stand orders the fruit, prepares a pitcher, and serves an eligible customer. |
| 27 | `demo_master_second_fruit` | Use customer feedback to perfect your new fruit recipe. | Five consecutive eligible customers evaluate the same perfect fruit-and-sugar candidate without a strength or sweetness complaint. |
| 28 | `demo_set_second_recipe` | Save your perfected new fruit recipe on the recipe board. | Both board values for the selected second fruit match its discovered perfect recipe. |

### Demo scope decisions

- The Demo research tree permits exactly one fruit unlock. All remaining fruit and upgrade nodes are
  visibly reserved for the Full Game rather than appearing purchasable and failing silently.
- The player chooses the second fruit. Tasks bind dynamically to that fruit rather than prescribing
  blueberry or another fixed choice.
- Recipe discovery is the final mastery goal, not an early blocker before the basic service loop.
- Free lemonade tasting by non-customer NPCs remains a discoverable experimentation mechanic. Their
  feedback may guide adjustments, but it never changes mastery streaks or forced-feedback counters.
- The starting configuration and economy must guarantee that all required equipment, ingredients, and
  cups can be ordered without a tutorial dead end.

## Recipe Discovery and Mastery

Recipe knowledge is permanent, per-stand progression that continues beyond onboarding.

### Fruit recipes and global ice

- Every fruit has its own perfect combination of fruit amount and sugar amount.
- Strength and sweetness are separate feedback types but jointly validate that fruit's recipe.
- The ice-per-degree ratio is global across all fruits. Discovering it with lemon also discovers it for
  blueberry and every other fruit.
- A stand may have discovered some fruit recipes while rival stands have discovered different ones.

### Candidate and streak rules

The host evaluates the actual recipe snapshot in the cup when a customer reaches the feedback stage.
Editing the recipe board alone never changes a streak because an existing pitcher may contain different
values.

For each undiscovered fruit, the stand tracks one active fruit-and-sugar candidate. It separately tracks
one active global ice candidate until the ice ratio is discovered.

- If an evaluated cup matches the active candidate, a relevant complaint resets its streak to `0`; no
  relevant complaint increments it.
- If the cup contains a different candidate, that candidate replaces the old one. Its streak begins at
  `1` when the customer has no relevant complaint, or `0` when they complain.
- Returning to an earlier candidate does not restore its discarded streak.
- Fruit/sugar changes do not reset the ice candidate when the ice setting is unchanged.
- Ice changes do not reset the active fruit candidate.
- Five consecutive eligible evaluations of the same perfect candidate discover it permanently.

### Guaranteed corrective feedback

Imperfect candidates retain the existing distance-based probability of a complaint. Randomness cannot
allow an imperfect candidate to reach mastery:

- Track consecutive silent evaluations for each active incorrect category.
- If three eligible customers do not complain about an incorrect active candidate, the fourth is
  guaranteed to give the relevant complaint.
- A naturally occurring complaint before the fourth evaluation resets that candidate's streak and silent
  counter normally.
- Fruit-recipe and global-ice guarantees are independent. If the UI can show only one complaint, prioritize
  an overdue guaranteed category and keep the other category pending.

An eligible evaluation must be a real customer transaction for the correct requested fruit that reaches
recipe feedback. Wrong orders, incorrect change, excessive price, timeouts, and other transaction failures
neither increment nor reset recipe mastery. Non-customer NPC tasters are also ineligible.

### Discovery feedback and recipe board

When a fruit recipe is discovered, everyone assigned to that stand receives a prominent day-style message:

```text
Perfect Lemon Recipe Found
2 lemons · 4 scoops of sugar
```

After discovery, matching values on that fruit's recipe-board row use the exact display color of its
lemonade. Values that do not match remain in the normal color. Before discovery, correct values receive no
special color, preventing the board from revealing the answer. Color must not be the only indicator; when
both fields match, also show a checkmark or `Perfect recipe set` label.

The same rules apply to the global ice value after a separate `Perfect Ice Ratio Found` message. Once a
fruit recipe or the ice ratio is discovered, stop maintaining its mastery streak permanently. Discovery is
never revoked, although customers can still complain when later drinks are prepared incorrectly.

## Full-Game Onboarding

The Full Game uses the same initial sequence and permanent discovery system. Unlike the Demo, research and
progression continue after the first additional fruit: all remaining fruits, upgrades, and longer-term goals
become available through contextual objectives when their systems unlock. The initial onboarding should not
force a specific upgrade build beyond teaching the first fruit research action.

## Day-End Interruption

At 6 PM, the day flow temporarily takes priority over onboarding:

1. Suspend each stand's active task and preserve every completed sentence span, candidate, and counter.
2. Replace the visible objective with `End the day.`
3. Follow the normal authoritative multiplayer day-ending flow.
4. When the next morning becomes playable, restore each stand's suspended task and partial progress.

`End the day` is an interruption, not a permanent step in the task sequence. In Versus, both stands see the
day objective because the phase is global, but each independently restores its own previous task afterward.
Saving, loading, disconnecting, or late joining during the interruption must preserve both the suspended task
and the fact that the day-end objective is active.

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
computer_order_accepted(stand, order_id, item_types)
equipment_placed(stand, item_id, equipment_type)
supply_deposited(stand, box_id, ingredient_type, container_type, quantity)
pitcher_placed(stand, pitcher_id, slot_type)
fruit_loaded_into_press(stand, press_id, fruit_type, amount)
fruit_fully_pressed(stand, press_id, fruit_type, amount)
pitcher_ingredient_added(stand, pitcher_id, ingredient_type, amount)
pitcher_water_filled(stand, pitcher_id, current_amount, capacity)
cup_filled(stand, cup_id, pitcher_recipe_snapshot)
customer_order_requested(stand, customer_id, peer_id)
customer_served(stand, customer_id, cup_recipe_snapshot)
customer_feedback_resolved(stand, customer_id, feedback, cup_recipe_snapshot)
correct_change_given(stand, customer_id, amount)
price_changed(stand, fruit_type, value)
recipe_board_changed(stand, fruit_type, recipe)
ice_ratio_changed(stand, degrees_per_cube)
research_unlocked(stand, research_id)
recipe_discovered(stand, fruit_type, recipe)
ice_ratio_discovered(stand, degrees_per_cube)
day_phase_changed(phase, day)
```

These should be domain-level notifications, not UI button signals. A task should complete whether the action came from mouse input, keyboard input, a future controller binding, or another valid interaction path.

## Persistence

Onboarding progress should be saved per stand with the rest of the host's save data:

```text
onboarding:
  version: 1
  stands:
    Stand1:
      track_id: DEMO
      current_task_id: demo_master_lemon
      completed_task_ids: [...]
      completed_parts: {...}
      suspended_task_state: null
      active_recipe_candidates: {...}
      active_ice_candidate: {...}
      discovered_recipes: {...}
      discovered_ice_ratio: null
      selected_demo_fruit: ""
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
- tracks active recipe candidates, complaint guarantees, mastery streaks, and discoveries;
- suspends and restores tasks around day-end interruptions;
- serializes/deserializes progress;
- synchronizes state for initial joins and updates.

### Per-stand state

Store the runtime progress on `StandUnit` or in an `OnboardingManager` dictionary keyed by stable stand ID. Prefer manager-owned dictionaries initially if changing `StandUnit.push_state()` would resend unrelated economy data for every tutorial update. Regardless of storage location, the public API should be stand-scoped.

### `OnboardingPanel`

A presentation-only HUD component that:

- binds to `WorldSync.get_local_stand()`;
- displays the current sentence and crosses out completed named spans independently;
- displays recipe-mastery streaks and discovered-value confirmation without revealing hidden values;
- plays completion/transition and discovery-message animations;
- supports collapse and skip requests;
- never decides that a gameplay task is complete.

## Edge Cases and Anti-Exploits

- Events that occurred before a task became active do not retroactively complete it unless explicitly
  marked as state-based.
- Duplicate reliable RPCs or repeated signals are harmless because completion checks the active task,
  completed ID set, and named part state.
- Failed orders, unaffordable purchases, rejected placements, and invalid serves do not count.
- Interacting with rival objects does not count for either stand unless that interaction is an intentionally
  valid rival mechanic.
- A transaction cannot count twice if teammates act on it at nearly the same time.
- Recipe mastery uses the served cup's immutable recipe snapshot, never the current board or pitcher state.
- Alternating candidate recipes resets the applicable streak when the next customer reaches feedback.
- An imperfect candidate cannot reach five clean evaluations because its fourth silent evaluation forces
  a relevant complaint.
- Free samples given to non-customer NPCs provide feedback but cannot advance or reset official customer
  mastery counters.
- Once discovered, a recipe remains discovered even if the stand later serves or configures it incorrectly.
- Debug/cheat actions should not advance onboarding or mastery by default.
- Skipping onboarding never grants items, money, discoveries, upgrades, or task rewards.
- If a required object is missing or destroyed, onboarding should not hard-lock the save. Provide task
  recovery or a validated skip path.
- If two teammates complete the same objective during the same host frame, only the first accepted event
  advances it; the second must not accidentally satisfy the newly activated task.

## Analytics and Playtesting

Useful non-gameplay analytics per task:

- task and named part started/completed;
- elapsed time and skip point;
- recipe candidate changes, streak length, and complaint timing;
- number of failed/rejected attempts where available;
- solo/co-op/versus and team size.

Do not transmit analytics until the project's consent and telemetry policy is defined. Local debug logging
is sufficient during development.

Playtest matrices:

1. Solo Demo from an empty stand through second-fruit mastery.
2. Compound sentence tasks ordered one item at a time and in a single order.
3. Two-player co-op where teammates alternate task parts and prepare different pitchers.
4. Two-player co-op where both attempt the same task simultaneously.
5. Versus with both stands at different task indices, candidates, and discoveries.
6. Rival player interacting near the other stand's tutorial objects.
7. Late join and reassignment during a partially completed compound task.
8. Save/load midway through a mastery streak and during the day-end interruption.
9. Candidate changes after four clean customers; the next evaluation must begin at `0` or `1`.
10. Imperfect candidates with three silent customers; the fourth must complain.
11. Independent fruit and ice streaks when only one category is correct.
12. Free NPC samples provide feedback without changing mastery state.
13. Discovery messages and board coloring appear only for the owning stand.
14. Skip onboarding, then save/load.

## Implementation Phases

### Phase 1 — Foundation

- Finalize Demo/Full selection and shared-skip policy.
- Add stable sentence/span task definitions and per-stand runtime state.
- Add host-authoritative advancement, day-end suspension, and snapshot synchronization.
- Add save migration and persistence.

### Phase 2 — Guided Demo loop

- Add semantic events for stand construction, production, sales, pricing, and board configuration.
- Add the sentence-based HUD checklist and partial strike-through behavior.
- Verify solo, co-op, Versus isolation, late join, and day interruption.

### Phase 3 — Recipe discovery

- Add per-fruit and global-ice candidates, streaks, and guaranteed corrective feedback.
- Add persistent discoveries, stand-scoped notifications, and accessible recipe-board confirmation.
- Add one-choice Demo fruit research and the second-fruit finale.
- Verify free NPC samples remain useful but ineligible for mastery.

### Phase 4 — Full-game extension and polish

- Unlock the remaining research and upgrades in Full Game builds/saves.
- Add contextual objectives when later systems first become available.
- Add existing-save opt-in and post-onboarding tips.
- Add world markers only where playtesting shows players cannot locate an objective.
- Add accessibility options for animation speed, text size, color indicators, and panel visibility.

## Open Product Decisions

These should be decided before implementation:

1. How is Demo versus Full selected: separate build flag, save type, platform entitlement, or menu choice?
2. Does every new stand start onboarding, or only stands in a newly created save?
3. Who may skip shared onboarding: host only, stand leader, or unanimous stand vote?
4. Should an experienced player joining a new teammate's stand see the shared panel automatically or have
   it collapsed locally?
5. Are onboarding tasks purely instructional, or will any task grant rewards? Recommended: no rewards.
6. When should normal customer spawning begin so early construction cannot cause unavoidable timeouts?
7. Can one customer display strength/sweetness and temperature feedback together, or must guaranteed
   categories be queued across later customers?

## Recommended First-Version Decisions

For the smallest reliable implementation:

- Select the track from an explicit save/build field, not inferred content availability.
- Start each new stand empty and use the 28-task Demo sequence.
- In the Demo, permit one player-chosen fruit research unlock and reserve everything else for Full Game.
- Start onboarding once per stand on new saves.
- Make skip host-only and stand-wide.
- Keep experienced teammates' panel collapsible locally but progression shared.
- Do not grant onboarding rewards or discoveries for skipping.
- Delay normal customer spawning until the first pitcher reaches the stand, preventing customers from
  timing out while players learn construction and preparation.
