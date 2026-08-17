extends PanelContainer

const CATEGORY_COLORS: Dictionary = {
	"it": Color("#818cf8"),
	"electrical": Color("#f59e0b"),
	"mechanical": Color("#38bdf8"),
}

@onready var icon_rect: TextureRect = $Margin/VBox/Header/IconRect
@onready var name_label: Label = $Margin/VBox/Header/NameLabel
@onready var count_label: Label = $Margin/VBox/Header/CountLabel
@onready var desc_label: Label = $Margin/VBox/DescLabel
@onready var warning_panel: PanelContainer = $Margin/VBox/WarningPanel
@onready var warning_label: Label = $Margin/VBox/WarningPanel/WarningLabel
@onready var stat_label: Label = $Margin/VBox/Footer/StatLabel
@onready var buy_button: Button = $Margin/VBox/Footer/BuyButton

var unit_id: String = ""
var unit_data: Dictionary = {}
var current_buy_multiplier: int = 1 # 1, 10, or -1 (MAX)
var overload_confirmation_until_msec: int = 0
var overload_confirmation_qty: int = 0
var overload_confirmation_signature: String = ""

func _ready() -> void:
	GameState.currency_changed.connect(_on_currency_changed)
	GameState.units_changed.connect(_on_units_changed)
	GameState.site_changed.connect(func(_tier): update_card())
	buy_button.pressed.connect(_on_buy_pressed)

func setup(data: Dictionary, buy_mode: int = 1) -> void:
	unit_data = data
	unit_id = data.get("id", "")
	current_buy_multiplier = buy_mode
	var category: String = data.get("category", "")
	var accent: Color = CATEGORY_COLORS.get(category, Color.WHITE)
	icon_rect.texture = PixelIcons.build_icon_texture(unit_id, accent)
	update_card()

func set_buy_multiplier(mode: int) -> void:
	current_buy_multiplier = mode
	update_card()

func _on_currency_changed(_cash: float, _tt: int) -> void:
	update_card()

func _on_units_changed(changed_id: String, _new_count: int) -> void:
	if changed_id == unit_id:
		update_card()

func update_card() -> void:
	if unit_data.is_empty():
		return
	
	var current_count: int = GameState.state["unit_counts"].get(unit_id, 0)
	name_label.text = unit_data.get("name", "Unit")
	count_label.text = "x%d" % current_count
	desc_label.text = unit_data.get("description", "")
	
	# Display specific engineering stat delta
	var category: String = unit_data.get("category", "")
	if category == "it":
		stat_label.text = "+%.1f TF | -%.1f kW | -%.1f kWth" % [
			float(unit_data.get("base_compute", 0.0)),
			float(unit_data.get("power_draw", 0.0)),
			float(unit_data.get("power_draw", 0.0)) * float(unit_data.get("heat_coefficient", 1.0))
		]
	elif category == "electrical":
		var uptime_str := ""
		if float(unit_data.get("uptime_bonus", 0.0)) > 0:
			uptime_str = " | +%.3f%% UP" % (float(unit_data.get("uptime_bonus", 0.0)) * 100.0)
		stat_label.text = "+%.1f kW CAP%s" % [
			float(unit_data.get("power_capacity", 0.0)),
			uptime_str
		]
	elif category == "mechanical":
		var base_capacity: float = float(unit_data.get("cooling_capacity", 0.0))
		var effective_capacity: float = GameState.get_unit_effective_cooling_capacity(unit_id)
		if unit_data.get("climate_dependent", false):
			var climate_pct: int = int(round(GameState.get_current_site_climate_modifier() * 100.0))
			stat_label.text = "+%.1f kWth EFFECTIVE | -%.1f kW\n%.1f BASE x %d%% SITE CLIMATE" % [
				effective_capacity,
				float(unit_data.get("power_draw", 0.0)),
				base_capacity,
				climate_pct
			]
		else:
			stat_label.text = "+%.1f kWth COOL | -%.1f kW" % [effective_capacity, float(unit_data.get("power_draw", 0.0))]
	var cost_discount: float = GameState.get_facility_cost_discount(category)
	if cost_discount > 0.0:
		stat_label.text += " | -%d%% COST" % int(round(cost_discount * 100.0))
	
	# Calculate purchase quantity & cost
	var base_cost: float = GameState.get_unit_effective_base_cost(unit_id)
	var growth: float = float(unit_data.get("cost_growth", 1.12))
	var cash: float = GameState.state["cash"]
	
	var buy_qty: int = 1
	var total_cost: float = 0.0
	
	if current_buy_multiplier == 1:
		buy_qty = 1
		total_cost = Economy.calculate_unit_cost(base_cost, growth, current_count)
	elif current_buy_multiplier == 10:
		buy_qty = 10
		total_cost = Economy.calculate_bulk_unit_cost(base_cost, growth, current_count, 10)
	elif current_buy_multiplier == -1: # MAX
		var affordable: int = Economy.calculate_max_affordable_units(base_cost, growth, current_count, cash)
		if affordable <= 0:
			buy_qty = 1
			total_cost = Economy.calculate_unit_cost(base_cost, growth, current_count)
		else:
			buy_qty = affordable
			total_cost = Economy.calculate_bulk_unit_cost(base_cost, growth, current_count, affordable)
	
	var warnings: Array[String] = GameState.get_purchase_constraint_warnings(unit_id, buy_qty)
	var warning_signature: String = "+".join(warnings)
	var confirmation_active: bool = (
		not warning_signature.is_empty()
		and Time.get_ticks_msec() <= overload_confirmation_until_msec
		and overload_confirmation_qty == buy_qty
		and overload_confirmation_signature == warning_signature
	)
	if not warning_signature.is_empty():
		custom_minimum_size.y = 148.0
		warning_panel.visible = true
		warning_label.text = _format_overload_warning(warnings)
		buy_button.add_theme_color_override("font_color", Color(1.0, 0.42, 0.45, 1))
		if confirmation_active:
			buy_button.text = "CONFIRM +%d\nOVERLOAD" % buy_qty
		else:
			buy_button.text = "BUY +%d (RISK)\n$%s" % [buy_qty, Economy.format_magnitude(total_cost)]
	else:
		custom_minimum_size.y = 116.0
		warning_panel.visible = false
		buy_button.remove_theme_color_override("font_color")
		buy_button.text = "BUY +%d\n$%s" % [buy_qty, Economy.format_magnitude(total_cost)]
	buy_button.disabled = (cash < total_cost)

func _on_buy_pressed() -> void:
	var base_cost: float = GameState.get_unit_effective_base_cost(unit_id)
	var growth: float = float(unit_data.get("cost_growth", 1.12))
	var current_count: int = GameState.state["unit_counts"].get(unit_id, 0)
	var cash: float = GameState.state["cash"]
	
	var buy_qty: int = 1
	if current_buy_multiplier == 1:
		buy_qty = 1
	elif current_buy_multiplier == 10:
		buy_qty = 10
	elif current_buy_multiplier == -1: # MAX
		var affordable: int = Economy.calculate_max_affordable_units(base_cost, growth, current_count, cash)
		buy_qty = max(affordable, 1)

	var warnings: Array[String] = GameState.get_purchase_constraint_warnings(unit_id, buy_qty)
	var warning_signature: String = "+".join(warnings)
	var now_msec: int = Time.get_ticks_msec()
	if not warning_signature.is_empty():
		var confirmation_active: bool = (
			now_msec <= overload_confirmation_until_msec
			and overload_confirmation_qty == buy_qty
			and overload_confirmation_signature == warning_signature
		)
		if not confirmation_active:
			overload_confirmation_until_msec = now_msec + 4000
			overload_confirmation_qty = buy_qty
			overload_confirmation_signature = warning_signature
			SoundManager.play_haptic(50)
			update_card()
			return

	overload_confirmation_until_msec = 0
	overload_confirmation_qty = 0
	overload_confirmation_signature = ""
	
	if GameState.buy_unit(unit_id, buy_qty):
		SoundManager.play_cash()
		SoundManager.play_haptic(20)

func _format_overload_warning(warnings: Array[String]) -> String:
	if "POWER" in warnings and "COOLING" in warnings:
		return "WARNING: PURCHASE WILL EXCEED\nPOWER AND COOLING CAPACITY"
	if "POWER" in warnings:
		return "WARNING: PURCHASE WILL EXCEED POWER CAPACITY"
	return "WARNING: PURCHASE WILL EXCEED COOLING CAPACITY"
