extends PanelContainer

@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var desc_label: Label = $Margin/VBox/DescLabel
@onready var timer_label: Label = $Margin/VBox/TimerLabel
@onready var actions_box: HBoxContainer = $Margin/VBox/Actions
@onready var ad_fix_btn: Button = $Margin/VBox/Actions/AdFixBtn
@onready var cash_fix_btn: Button = $Margin/VBox/Actions/CashFixBtn
@onready var dismiss_btn: Button = $Margin/VBox/Actions/DismissBtn

var active_event_data: Dictionary = {}

func _ready() -> void:
	visible = false
	GameState.event_started.connect(_on_event_started)
	GameState.event_ended.connect(_on_event_ended)
	
	ad_fix_btn.pressed.connect(_on_ad_fix_pressed)
	cash_fix_btn.pressed.connect(_on_cash_fix_pressed)
	dismiss_btn.pressed.connect(_on_dismiss_pressed)

func _process(_delta: float) -> void:
	if not visible or active_event_data.is_empty():
		return
	if GameState.active_event_time_remaining > 0.0:
		timer_label.text = "Duration Remaining: %ds" % int(GameState.active_event_time_remaining)
	else:
		timer_label.text = "Instant Resolution Event"

func _on_event_started(event: Dictionary) -> void:
	active_event_data = event
	var event_type: String = event.get("type", "hazard")
	var event_name: String = event.get("name", "Random Event")
	
	if event_type == "gift":
		title_label.text = "GIFT EVENT: %s" % event_name.to_upper()
		title_label.modulate = Color(0.22, 0.77, 0.37, 1)
	else:
		title_label.text = "INCIDENT ALERT: %s" % event_name.to_upper()
		title_label.modulate = Color(0.94, 0.27, 0.27, 1)
	
	desc_label.text = event.get("description", "")
	
	# Ad fix button
	if bool(event.get("ad_reward_fix", false)):
		ad_fix_btn.visible = true
	else:
		ad_fix_btn.visible = false
	
	# Cash fix button
	var cash_ratio: float = float(event.get("cash_repair_cost_ratio", 0.0))
	if cash_ratio > 0.0:
		var repair_cost: float = GameState.state["cash"] * cash_ratio
		cash_fix_btn.visible = true
		cash_fix_btn.text = "PAY $%s" % Economy.format_magnitude(repair_cost)
	else:
		cash_fix_btn.visible = false
	
	visible = true

func _on_event_ended(_event: Dictionary) -> void:
	active_event_data.clear()
	visible = false

func _on_ad_fix_pressed() -> void:
	Ads.show_rewarded_ad("event_fix", func():
		GameState.resolve_event(true, false)
		visible = false
	)

func _on_cash_fix_pressed() -> void:
	if GameState.resolve_event(false, true):
		visible = false

func _on_dismiss_pressed() -> void:
	# Instant gift events (no duration, no repair option) have already applied their
	# effect and have nothing left to "ride out" — clear them so the next event can spawn.
	var has_duration: bool = float(active_event_data.get("duration_sec", 0)) > 0.0
	var needs_repair: bool = bool(active_event_data.get("ad_reward_fix", false)) or float(active_event_data.get("cash_repair_cost_ratio", 0.0)) > 0.0
	if not has_duration and not needs_repair:
		GameState.resolve_event(false, false)
	visible = false
