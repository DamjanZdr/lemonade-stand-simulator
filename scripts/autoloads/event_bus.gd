extends Node
## Central signal dispatcher. The ONLY channel for cross-system communication.
## No script holds a direct reference to another system's script.

# --- Player ---
signal held_item_changed(item_type: int, item_data: Dictionary)
signal interaction_hint_changed(hint: String)

# --- Bins ---
signal bin_amount_changed(ingredient_type: String, new_amount: float)
signal ingredient_scoop_grabbed(ingredient_type: String, amount: float)
signal supply_box_deposited(ingredient_type: String, amount: float)

# --- Cups ---
signal cup_stack_changed(new_count: int)

# --- Pitcher ---
signal pitcher_ingredient_added(ingredient_type: String, amount: float)
signal pitcher_state_changed(new_state: int)
signal pitcher_cleared()
signal pitcher_cup_filled(recipe: Dictionary)

# --- Delivery ---
signal supply_order_placed(ingredient_type: String, quantity: float, cost: float)
signal supply_box_spawned(box: Node)

# --- Customer ---
signal customer_arrived(customer: Node)
signal customer_patience_changed(customer: Node, ratio: float)
signal customer_served(customer: Node, outcome: String)
signal customer_left(customer: Node, outcome: String)
signal cash_dropped(position: Vector3, payment: float, change_due: float)
signal sale_initiated(payment: float, change_due: float)
signal change_finalized(earned: float)
signal cash_collected(amount: float)

# --- Containers ---
signal container_placed(container_type: String, container: Node)
signal container_picked_up(container_type: String, container: Node)

# --- Economy ---
signal money_changed(new_amount: float)
signal price_changed(new_price: float)
signal popularity_changed(new_rating: float)

# --- Upgrades ---
signal feedback_tier_changed(new_tier: int)
signal upgrade_purchased(upgrade: int, cost: float)

# --- Weather ---
signal weather_changed(temperature: float)

# --- Day Cycle ---
signal day_phase_changed(phase: int, day_number: int)
signal day_timer_updated(time_left: float, total_time: float)

# --- Save ---
signal game_saved()
signal game_reset()

# --- Debug ---
signal debug_add_money(amount: float)
signal debug_refill_all_bins()
signal debug_empty_pitcher()
signal debug_force_spawn_customer()
signal debug_set_temperature(temp: float)
signal debug_set_feedback_tier(tier: int)
signal debug_set_spawn_rate(per_minute: float)
signal debug_set_queue_max(max_size: int)
signal debug_set_outline_width(width: float)
signal debug_set_outline_color(color: Color)
signal debug_force_happy_serve()
signal debug_set_popularity(value: float)
