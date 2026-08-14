extends Control

@onready var boost_btn: Button = $Margin/VBox/Footer/BoostBtn

func _ready() -> void:
	boost_btn.pressed.connect(_on_boost_pressed)
	GameState.state_updated.connect(_update_boost_button)
	_update_boost_button()

func _on_boost_pressed() -> void:
	# Rewarded ad boost: 2x revenue for 4 min (240s) (§6.1)
	Ads.show_rewarded_ad("boost_button_2x", func():
		GameState.boost_time_remaining = 240.0
		GameState.boost_multiplier = 2.0
		GameState.recalculate_all_metrics()
		_update_boost_button()
	)

func _update_boost_button() -> void:
	if not boost_btn:
		return
	if GameState.boost_time_remaining > 0.0:
		boost_btn.text = "BOOST ACTIVE (%ds)" % int(GameState.boost_time_remaining)
		boost_btn.disabled = true
	else:
		boost_btn.text = "ACTIVATE 2X BOOST (4 MIN)"
		boost_btn.disabled = false
