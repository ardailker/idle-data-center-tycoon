extends PanelContainer

@onready var time_label: Label = $Margin/VBox/TimeLabel
@onready var earnings_label: Label = $Margin/VBox/EarningsLabel
@onready var claim_btn: Button = $Margin/VBox/Actions/ClaimBtn
@onready var double_btn: Button = $Margin/VBox/Actions/DoubleBtn

var offline_data: Dictionary = {}

func _ready() -> void:
	visible = false
	SaveManager.offline_earnings_calculated.connect(_on_offline_earnings)
	claim_btn.pressed.connect(_on_claim_pressed)
	double_btn.pressed.connect(_on_double_pressed)

func _on_offline_earnings(data: Dictionary) -> void:
	offline_data = data
	var effective_sec: int = int(data.get("effective_seconds", 0))
	var cap_sec: int = int(data.get("offline_cap", 7200))
	var rev: float = float(data.get("revenue", 0.0))
	
	var mins: int = effective_sec / 60
	var hours: int = mins / 60
	var rem_mins: int = mins % 60
	
	time_label.text = "You were offline for %dh %dm (Cap: %dh)" % [hours, rem_mins, cap_sec / 3600]
	earnings_label.text = "+$%s" % Economy.format_magnitude(rev)
	visible = true

func _on_claim_pressed() -> void:
	SaveManager.claim_offline_earnings(1.0)
	visible = false

func _on_double_pressed() -> void:
	Ads.show_rewarded_ad("return_screen_2x", func():
		SaveManager.claim_offline_earnings(2.0)
		visible = false
	)
