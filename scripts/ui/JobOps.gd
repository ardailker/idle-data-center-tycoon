extends VBoxContainer

@onready var summary_label: Label = $Header/Margin/VBox/Summary
@onready var cards_container: VBoxContainer = $Scroll/Cards

var rendered_cards: Dictionary = {}

func _ready() -> void:
	_build_cards()
	GameState.state_updated.connect(_refresh_view)
	_refresh_view()

func _build_cards() -> void:
	for child in cards_container.get_children():
		child.queue_free()
	rendered_cards.clear()
	for upgrade in GameState.get_manual_job_upgrades():
		var card: PanelContainer = _create_upgrade_card(upgrade)
		cards_container.add_child(card)

func _create_upgrade_card(upgrade: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 108)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var heading := HBoxContainer.new()
	vbox.add_child(heading)
	var name_label := Label.new()
	name_label.text = String(upgrade.get("name", "JOB UPGRADE")).to_upper()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 10)
	heading.add_child(name_label)
	var level_label := Label.new()
	level_label.add_theme_color_override("font_color", _effect_color(String(upgrade.get("effect_type", ""))))
	level_label.add_theme_font_size_override("font_size", 8)
	heading.add_child(level_label)

	var description := Label.new()
	description.text = String(upgrade.get("description", ""))
	description.add_theme_color_override("font_color", Color(0.58, 0.64, 0.72, 1))
	description.add_theme_font_size_override("font_size", 8)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 2
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(description)

	var effect_label := Label.new()
	effect_label.add_theme_color_override("font_color", _effect_color(String(upgrade.get("effect_type", ""))))
	effect_label.add_theme_font_size_override("font_size", 8)
	effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(effect_label)

	var buy_button := Button.new()
	buy_button.custom_minimum_size = Vector2(0, 36)
	buy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_button.add_theme_font_size_override("font_size", 9)
	vbox.add_child(buy_button)

	var upgrade_id: String = String(upgrade.get("id", ""))
	buy_button.pressed.connect(func(): _purchase_upgrade(upgrade_id))
	rendered_cards[upgrade_id] = {
		"upgrade": upgrade,
		"level_label": level_label,
		"effect_label": effect_label,
		"buy_button": buy_button
	}
	return panel

func _refresh_view() -> void:
	var reward: float = Economy.calculate_manual_job_reward(
		GameState.revenue_per_sec,
		GameState.get_manual_job_reward_seconds()
	)
	summary_label.text = "TAP +$%s  |  QUEUE %d/%d  |  %.1f/s" % [
		Economy.format_magnitude(reward),
		int(floor(GameState.manual_job_charges)),
		int(GameState.get_manual_job_max_charges()),
		GameState.get_manual_job_regen_per_second()
	]

	var cash: float = float(GameState.state.get("cash", 0.0))
	for upgrade_id in rendered_cards:
		var card: Dictionary = rendered_cards[upgrade_id]
		var upgrade: Dictionary = card["upgrade"]
		var level: int = GameState.get_manual_job_upgrade_level(upgrade_id)
		var max_level: int = int(upgrade.get("max_level", 1))
		var level_label: Label = card["level_label"]
		var effect_label: Label = card["effect_label"]
		var buy_button: Button = card["buy_button"]
		level_label.text = "LV %d/%d" % [level, max_level]
		effect_label.text = _format_effect(upgrade, level, level >= max_level)
		if level >= max_level:
			buy_button.text = "MAX LEVEL"
			buy_button.disabled = true
		else:
			var cost: float = GameState.get_manual_job_upgrade_cost(upgrade_id)
			buy_button.text = "UPGRADE  |  $%s" % Economy.format_magnitude(cost)
			buy_button.disabled = cash < cost

func _format_effect(upgrade: Dictionary, level: int, is_maxed: bool) -> String:
	var effect_type: String = String(upgrade.get("effect_type", ""))
	var effect: float = float(upgrade.get("effect_per_level", 0.0))
	var next_level: int = min(level + 1, int(upgrade.get("max_level", 1)))
	if effect_type == "reward_multiplier":
		if is_maxed:
			return "JOB VALUE +%d%%  |  MAXED" % roundi(level * effect * 100.0)
		return "JOB VALUE +%d%%  >  +%d%%" % [roundi(level * effect * 100.0), roundi(next_level * effect * 100.0)]
	if effect_type == "max_charges":
		var base_capacity: int = int(GameState.balance_data.get("manual_jobs", {}).get("base_max_charges", 5))
		if is_maxed:
			return "QUEUE %d CHARGES  |  MAXED" % (base_capacity + roundi(level * effect))
		return "QUEUE %d  >  %d CHARGES" % [base_capacity + roundi(level * effect), base_capacity + roundi(next_level * effect)]
	if effect_type == "regen_multiplier":
		var base_regen: float = float(GameState.balance_data.get("manual_jobs", {}).get("base_regen_per_second", 4.0))
		if is_maxed:
			return "RECHARGE %.1f/s  |  MAXED" % (base_regen * (1.0 + level * effect))
		return "RECHARGE %.1f/s  >  %.1f/s" % [base_regen * (1.0 + level * effect), base_regen * (1.0 + next_level * effect)]
	return "UPGRADE EFFECT"

func _effect_color(effect_type: String) -> Color:
	if effect_type == "reward_multiplier":
		return Color("#6bff8f")
	if effect_type == "max_charges":
		return Color("#61d1ff")
	return Color("#b69cff")

func _purchase_upgrade(upgrade_id: String) -> void:
	if not GameState.purchase_manual_job_upgrade(upgrade_id):
		return
	SoundManager.play_cash()
	SoundManager.play_haptic(20)
	_refresh_view()
