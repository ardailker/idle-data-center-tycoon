extends Control

@onready var label_title: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var label_status: Label = $CenterContainer/VBoxContainer/StatusLabel

func _ready() -> void:
	GameState.state_updated.connect(_on_state_updated)
	_update_display()

func _on_state_updated() -> void:
	_update_display()

func _update_display() -> void:
	if not label_status:
		return
	label_status.text = "Cash: $%s | TT: %d\nIT Load: %.1f kW | Power Cap: %.1f kW\nPUE: %.2f | Revenue: $%s/s" % [
		Economy.format_magnitude(GameState.state["cash"]),
		GameState.state["tech_tokens"],
		GameState.it_load_kw,
		GameState.power_capacity_kw,
		GameState.pue,
		Economy.format_magnitude(GameState.revenue_per_sec)
	]
