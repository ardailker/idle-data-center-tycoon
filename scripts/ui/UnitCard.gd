extends PanelContainer

@onready var name_label: Label = $Margin/HBox/InfoBox/Header/NameLabel
@onready var count_label: Label = $Margin/HBox/InfoBox/Header/CountLabel
@onready var desc_label: Label = $Margin/HBox/InfoBox/DescLabel
@onready var stat_label: Label = $Margin/HBox/InfoBox/StatLabel
@onready var buy_button: Button = $Margin/HBox/BuyButton

var unit_id: String = ""
var unit_data: Dictionary = {}
var current_buy_multiplier: int = 1 # 1, 10, or -1 (MAX)

func _ready() -> void:
	GameState.currency_changed.connect(_on_currency_changed)
	GameState.units_changed.connect(_on_units_changed)
	buy_button.pressed.connect(_on_buy_pressed)

func setup(data: Dictionary, buy_mode: int = 1) -> void:
	unit_data = data
	unit_id = data.get("id", "")
	current_buy_multiplier = buy_mode
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
		stat_label.text = "+%.1f TFLOPs | -%.1f kW | -%.1f kW-th" % [
			float(unit_data.get("base_compute", 0.0)),
			float(unit_data.get("power_draw", 0.0)),
			float(unit_data.get("power_draw", 0.0)) * float(unit_data.get("heat_coefficient", 1.0))
		]
	elif category == "electrical":
		var uptime_str := ""
		if float(unit_data.get("uptime_bonus", 0.0)) > 0:
			uptime_str = " | +%.1f%% Uptime" % (float(unit_data.get("uptime_bonus", 0.0)) * 100.0)
		stat_label.text = "+%.1f kW Capacity%s" % [
			float(unit_data.get("power_capacity", 0.0)),
			uptime_str
		]
	elif category == "mechanical":
		var cap_text := "+%.1f kW-th Cooling" % float(unit_data.get("cooling_capacity", 0.0))
		if unit_data.get("climate_dependent", false):
			cap_text += " (Climate Scaled)"
		stat_label.text = "%s | -%.1f kW" % [cap_text, float(unit_data.get("power_draw", 0.0))]
	
	# Calculate purchase quantity & cost
	var base_cost: float = float(unit_data.get("base_cost", 10.0))
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
	
	buy_button.text = "BUY +%d\n$%s" % [buy_qty, Economy.format_magnitude(total_cost)]
	buy_button.disabled = (cash < total_cost)

func _on_buy_pressed() -> void:
	var base_cost: float = float(unit_data.get("base_cost", 10.0))
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
	
	GameState.buy_unit(unit_id, buy_qty)
