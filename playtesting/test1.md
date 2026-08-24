### Multiplayer & Synchronization Fixes

- **Object Placement & Scaling: Fix scaling bugs where objects and items placed by either the client or host become giant for the other player.**
  - **Cause:** When a player places an object (like a lemon box), the game shrinks it down to fit on the stand. But the network message that tells the other player about the new object only sent the position and rotation — not the shrunken size. So the other player's game created the object at full size.
  - **Solution:** The network message now includes the object's size, so when the other player's game creates the object, it matches the host's shrunken size exactly.
  - **Status:** Fixed

- **World State on Startup: Ensure that saved game states (including instantiated items, objects, and world structures) are properly synced and visible to the client immediately upon joining or starting the game, rather than only appearing after the host moves something.**
  - **Cause:** The game only sent object updates to clients when the host actively moved or changed something. Objects that were already placed before the client joined were never sent over.
  - **Solution:** When a client joins, the host now packages up all placed objects (their position, rotation, size, and contents) and sends them as a batch to the new client. The client's game then creates all of them at once so everything appears immediately.
  - **Status:** Fixed

- **Position & Movement Syncing: Resolve issues where moving objects, items, or general entities around the world fails to update properly for the other player.**
  - **Cause:** Moving an object only changed its position on the player's own screen. The other player's game was never told the object moved, so it stayed in the old spot.
  - **Solution:** The host now sends a "this object moved here" message whenever an object is moved, and the other player's game updates the object's position. This works for tables, containers, and other world objects.
  - **Status:** Fixed

- **Item Pickups: Fix duplicate item availability; picking up an item should correctly remove it in the world for all players instead of allowing multiple players to pick up the same visible item.**
  - **Cause:** When a player picks up an object, the game destroyed it on that player's screen but didn't tell the other player's game to destroy it too. So the other player still saw it and could pick it up again.
  - **Solution:** Picking up an object now sends a "remove this object" message to all other players. The object disappears for everyone at the same time.
  - **Status:** Fixed

- **Reparented Nodes: Ensure reparented nodes (such as tables and containers that can hold other items) properly sync across the network, unlike standard instantiated ones.**
  - **Cause:** Tables can hold items on top of them. When a table is picked up and placed somewhere else, the items on top should move with it. But the network sync only handled newly created objects — it didn't handle objects that had been reorganized (items moved onto a table, table moved to a new spot).
  - **Solution:** The host now sends a "this object is now sitting on top of this other object" message so both players see the same hierarchy. When a table is picked up, moved, and placed back down, all players see the items on top move with it.
  - **Status:** Fixed

- **Inventory & Slot Glitches: Fix slot synchronization bugs (e.g., when a client picks up a box from a slot and tries to place it back into the newly emptied slot, it incorrectly registers or stacks as a second box instead of recognizing the empty slot).**
  - **Cause:** When a player picks up a box from a delivery slot, the slot is freed locally on their screen. But the other player's game doesn't know the slot is empty. When the player tries to put the box back, the game gets confused about whether the slot is occupied.
  - **Solution:** The slot's occupied/empty state is now synced across players. When a box is picked up from or placed into a slot, all players' games update the slot status so everyone agrees on which slots are full and which are empty.
  - **Status:** Fixed

- **RMB Placement Issues: Remove the ability to place boxes with RMB entirely, or fix the bug where placing a box with RMB leaves behind a persistent green placement ghost/blueprint that stays until picked up again.**
  - **Cause:** When dropping a supply box with right-click, the game dropped the box and cleared the held item, but forgot to destroy the green placement preview (the ghost outline showing where the box would go). So the green outline stayed on screen floating in the air.
  - **Solution:** The drop function now always cleans up the green ghost immediately after dropping the box, matching the cleanup that already happened in other placement paths.
  - **Status:** Fixed

- **Post-Load Movement: Ensure items that have been moved by the host show up properly for the client after loading into the world.**
  - **Cause:** Same root cause as "World State on Startup" — the client didn't receive information about objects that were moved before they joined.
  - **Solution:** Fixed alongside the world state sync. When a client joins, they receive the current position of all objects, including ones the host moved earlier.
  - **Status:** Fixed

### Client Connection & UI Bugs

- **Recipes Panel: Fix a bug on the client side where players get stuck and cannot exit the recipes panel.**
  - **Cause:** The recipes panel is part of the morning hub, which shows during the "morning" phase. When the host clicked "Start Day", the game switched from morning to day phase on the host's screen, which hid the panel. But this phase change was never sent to clients — they stayed stuck in the morning phase with the panel open and no way to close it.
  - **Solution:** The host now sends a "the phase changed" message to all clients whenever the game switches between morning, day, and evening. When clients receive this, their game hides the morning panel automatically.
  - **Status:** Fixed

- **Player Disconnection Handling: Ensure that when a client quits or leaves the game, they are properly removed from the session and world instead of lingering behind.**
  - **Cause:** When a client disconnected, the host was notified but didn't clean up the disconnected player's character from the world. The player's body stayed visible and frozen.
  - **Solution:** The host now listens for disconnection events and immediately removes the disconnected player's character from the world and cleans up any cached references to it.
  - **Status:** Fixed

- **Initial Camera Position: Fix the client's starting camera position, which currently defaults to looking at the price sign at the start of the game.**
  - **Cause:** When a client loaded into the game, the lobby roster hadn't arrived over the network yet (timing issue), so the game thought there was no lobby and skipped straight to gameplay — starting the camera at the default price board position instead of the lobby.
  - **Solution:** The game now checks whether the player is actually connected to a server before skipping the lobby. Clients with an active connection wait for the roster to arrive instead of jumping straight to gameplay. Also fixed the host's player spawner not being ready when clients requested spawns.
  - **Status:** Fixed

- **NPC Interaction & Animations: Fix client-side issues where players cannot interact with NPCs (outlines fail to highlight) and npc animations glitch or randomly restart.**
  - **Cause:** Two separate issues. (1) The FPS optimization that reduced client lag had disabled NPC collision shapes entirely on clients — but the interaction system uses a raycast that needs those shapes to detect NPCs. Without them, clients couldn't highlight or talk to NPCs. (2) The animation player always restarted an animation from the beginning even if it was already playing. When clients received state updates from the host (even if the state hadn't changed), the animation would restart from frame 0, causing visible glitches.
  - **Solution:** (1) Instead of disabling collision shapes, the NPC bodies are now set to not physically collide with anything (collision layers set to 0) while keeping the shapes enabled for raycast detection. Clients can now highlight and interact with NPCs. (2) The animation player now skips the restart if the same animation is already playing, so state sync updates no longer cause glitches.
  - **Status:** Fixed

- **Trash Pickup: Fix client-side functionality so players can successfully pick up trash.**
  - **Cause:** Two separate issues. (1) Trash items on the ground were explicitly set to be non-interactable on clients — they removed themselves from the interactable group and disabled their collision, so clients couldn't even click on them. (2) When trashing an item in the trashcan, the money refund and trash visual only worked on the host because money is host-authoritative. Clients' trash interactions did nothing.
  - **Solution:** (1) Trash items are now interactable on all players. When a client picks up trash, the pickup request goes to the host, which removes the trash for everyone. (2) The trashcan now routes disposal through the host via a network message — the host handles the money refund and spawns the trash visual, so it works correctly for clients.
  - **Status:** Fixed

- **Ending the Day: Fix client-side progression issues where clients cannot end the day (receiving an "it's not 6 pm yet" error incorrectly) and cannot see the "Day Complete" menu after the host finishes the day.**
  - **Cause:** The day timer was synced to clients, but the day phase changes (morning to day to evening) were not. When the host's day ended and the game switched to the evening phase (which triggers the "Day Complete" summary screen), clients never received that change. They stayed in the day phase, unable to end the day or see the summary.
  - **Solution:** The host now sends the phase change to all clients (same fix as the recipes panel). When clients receive the "evening" phase, their game shows the "Day Complete" summary screen automatically.
  - **Status:** Fixed

### Quality of Life & Additions

- **FPS Counter & Debug Generator: Add an FPS counter and debug generator in the bottom-left corner, toggleable via the F key (and mention this shortcut in the debug panel).**
  - **Cause:** Not a bug — this is a new feature request.
  - **Solution:** Added a small FPS counter in the bottom-left corner that shows the current frames per second. It updates 4 times per second and can be toggled on/off with the F key. It's hidden by default. The developer panel title now also mentions "F1" so that shortcut is discoverable.
  - **Status:** Fixed (F key toggles FPS counter, F1 toggles dev panel)

- **Dev Panel: Bring back the F1 key toggle to show the developer panel.**
  - **Cause:** The developer panel (with sliders for temperature, money buttons, etc.) was visible by default and couldn't be hidden. We fixed it to be hidden by default, but the F1 toggle was already there — it just wasn't obvious because the panel was always showing.
  - **Solution:** The F1 toggle already exists and works. The panel is now hidden by default and F1 shows/hides it. The panel title now says "DEV PANEL (F1)" to make the shortcut obvious.
  - **Status:** Fixed (F1 toggle already works)

- **Player Animations & Look constraints: Adjust player animations so that the neck spins on the Y-axis up to 0.2 and -0.2 before the entire player model starts to spin, and make the head rotate on the X-axis up to 0.5 when looking down and up to -0.5 when looking up.**
  - **Cause:** Not a bug — this is a new feature request for more realistic head/neck movement.
  - **Solution:** The player model's neck bone now rotates left/right (up to about 11 degrees) before the body starts to turn, and the head bone tilts up/down (up to about 29 degrees) based on where the camera is looking. The camera look direction is synced to other players over the network, so everyone sees where you're looking.
  - **Status:** Fixed

- **Character Customization: Add a skin color slider.**
  - **Cause:** Not a bug — this is a new feature request.
  - **Solution:** Added a skin color slider in the lobby customization panel (right column, below roof color). It ranges from lightest to darkest skin tone. The color is applied to all skin surfaces on the body mesh and is included in the customization data that gets synced to other players. The Randomize button also randomizes skin color.
  - **Status:** Fixed

### Additional Fixes Made During Testing (Not in Original List)

- **Host Left Popup:** When the host quits, clients now get a popup saying "Host Left" with a "Back to Menu" button instead of getting stuck.
  - **Status:** Fixed

- **NPC FPS Drop on Clients:** Clients had massive FPS drops when many NPCs were on screen. Fixed by batching all NPC position updates into one network message per tick (instead of one per NPC) and removing NPC physical collision on clients since their positions come from the host. Collision shapes remain enabled so clients can still interact with NPCs.
  - **Status:** Fixed

- **Remote Player Jitter:** Looking at other players was jittery. Fixed by smoothly sliding remote players toward their updated positions instead of teleporting them, and using faster (unreliable) network messages for position updates.
  - **Status:** Fixed

- **Debug Panel Visible by Default:** The developer panel (sliders, money buttons) was showing on screen by default. Fixed — now hidden by default, toggled with F1.
  - **Status:** Fixed

- **Water Dispenser Pickable:** The water dispenser could be picked up and moved. Fixed — it's now a fixed appliance that can't be picked up.
  - **Status:** Fixed

- **Lobby Camera / Player Spawn:** Players spawn at the lobby character preview's position so the camera transition from lobby to gameplay is seamless.
  - **Status:** Fixed
