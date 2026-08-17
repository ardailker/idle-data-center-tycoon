extends Control

@onready var boost_btn: Button = $Margin/VBox/Footer/BoostBtn
@onready var facility_nav_btn: Button = $Margin/VBox/NavBar/FacilityNavBtn
@onready var job_nav_btn: Button = $Margin/VBox/NavBar/JobNavBtn
@onready var tech_nav_btn: Button = $Margin/VBox/NavBar/TechNavBtn
@onready var site_nav_btn: Button = $Margin/VBox/NavBar/SiteNavBtn

@onready var unit_list_view: Control = $Margin/VBox/ViewContainer/UnitList
@onready var job_ops_view: Control = $Margin/VBox/ViewContainer/JobOps
@onready var tech_tree_view: Control = $Margin/VBox/ViewContainer/TechTree
@onready var site_sale_view: Control = $Margin/VBox/ViewContainer/SiteSale
@onready var event_card: Control = $Margin/VBox/EventCard

@onready var top_bar: PanelContainer = $Margin/VBox/TopBar
@onready var settings_dialog: PanelContainer = $Settings

var current_view: String = "facility"

func _ready() -> void:
	boost_btn.pressed.connect(_on_boost_pressed)
	facility_nav_btn.pressed.connect(func(): _switch_view("facility"))
	job_nav_btn.pressed.connect(func(): _switch_view("job_ops"))
	tech_nav_btn.pressed.connect(func(): _switch_view("tech_tree"))
	site_nav_btn.pressed.connect(func(): _switch_view("site_sale"))
	top_bar.settings_requested.connect(func(): settings_dialog.open_settings())
	
	GameState.state_updated.connect(_update_boost_button)
	_update_boost_button()
	_switch_view("facility")

func _switch_view(view_name: String) -> void:
	current_view = view_name
	
	unit_list_view.visible = (view_name == "facility")
	job_ops_view.visible = (view_name == "job_ops")
	tech_tree_view.visible = (view_name == "tech_tree")
	site_sale_view.visible = (view_name == "site_sale")
	
	facility_nav_btn.modulate = Color(0.22, 0.74, 0.97, 1) if view_name == "facility" else Color(0.6, 0.6, 0.6, 0.8)
	job_nav_btn.modulate = Color(0.42, 1.0, 0.56, 1) if view_name == "job_ops" else Color(0.6, 0.6, 0.6, 0.8)
	tech_nav_btn.modulate = Color(0.66, 0.53, 0.98, 1) if view_name == "tech_tree" else Color(0.6, 0.6, 0.6, 0.8)
	site_nav_btn.modulate = Color(0.22, 0.77, 0.37, 1) if view_name == "site_sale" else Color(0.6, 0.6, 0.6, 0.8)

func _on_boost_pressed() -> void:
	if not GameState.can_activate_rewarded_boost():
		_update_boost_button()
		return
	# Rewarded ad boost: 2x revenue for 10 min (§6.1)
	Ads.show_rewarded_ad("boost_button_2x", func():
		GameState.activate_rewarded_boost()
		_update_boost_button()
	)

func _update_boost_button() -> void:
	if not boost_btn:
		return
	if GameState.boost_time_remaining > 0.0:
		boost_btn.text = "2X ACTIVE  |  %s" % _format_boost_time(GameState.boost_time_remaining)
		boost_btn.disabled = true
	elif not GameState.can_activate_rewarded_boost():
		boost_btn.text = "BOOST LIMIT REACHED"
		boost_btn.disabled = true
	else:
		var duration_minutes: int = int(GameState.REWARDED_BOOST_DURATION_SECONDS / 60.0)
		boost_btn.text = "2X BOOST %d MIN  |  %d LEFT" % [duration_minutes, GameState.get_rewarded_boosts_remaining()]
		boost_btn.disabled = false

func _format_boost_time(seconds: float) -> String:
	var total_seconds: int = max(int(seconds), 0)
	if total_seconds >= 3600:
		return "%dh %02dm" % [total_seconds / 3600, (total_seconds % 3600) / 60]
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]
