class_name EmojiDisplay
extends Node3D
## Floats an emoji label above a customer. Supports all 3 feedback tiers.

# Tier 0 — binary
const TIER0: Dictionary = {
	"happy": "😊",
	"_default": "😞",
	"too_expensive": "💸",
	"timeout": "⏰",
	"wrong_order": "❌",
	"too_strong": "😞",
	"not_enough_fruit": "😞",
	"too_cold": "😞",
	"not_cold_enough": "😞",
	"too_sweet": "😞",
	"not_sweet_enough": "😞",
}
# Tier 1 — category
const TIER1: Dictionary = {
	"happy": "😊",
	"too_sour": "🍋",
	"too_watery": "🍋",
	"too_strong": "🍋",
	"not_enough_fruit": "🍋",
	"too_sweet": "🍬",
	"not_sweet_enough": "🍬",
	"lukewarm": "🌡️",
	"freezing": "🌡️",
	"too_cold": "🌡️",
	"not_cold_enough": "🌡️",
	"wrong_order": "❌",
	"too_expensive": "💸",
	"timeout": "⏰",
	"_default": "😞",
}
# Tier 2 — specific
const TIER2: Dictionary = {
	"happy": "😊",
	"too_sour": "😖",
	"too_watery": "💧",
	"too_strong": "�",
	"not_enough_fruit": "�",
	"too_sweet": "🍯",
	"not_sweet_enough": "😐",
	"lukewarm": "🥵",
	"freezing": "🥶",
	"too_cold": "🥶",
	"not_cold_enough": "🥵",
	"wrong_order": "❌",
	"too_expensive": "💸",
	"timeout": "⏰",
	"_default": "😞",
}

@onready var label: Label3D = $Label

var _base_y: float = 0.0
var _emoji_tween: Tween = null


func _ready() -> void:
	_base_y = position.y


func show_emoji(outcome: String, tier: int) -> void:
	var lookup: Dictionary
	match tier:
		1:
			lookup = TIER1
		2:
			lookup = TIER2
		_:
			lookup = TIER0

	label.text = lookup.get(outcome, lookup.get("_default", "😞"))
	label.modulate = Color(1, 1, 1, 1)
	position.y = _base_y

	if _emoji_tween and _emoji_tween.is_valid():
		_emoji_tween.kill()
	_emoji_tween = create_tween()
	_emoji_tween.tween_property(self, "position:y", _base_y + 0.35, 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_emoji_tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6) \
			.set_delay(0.9)
