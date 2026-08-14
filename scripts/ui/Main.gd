extends Control

@onready var boost_btn: Button = $Margin/VBox/Footer/BoostBtn
@onready var facility_nav_btn: Button = $Margin/VBox/NavBar/FacilityNavBtn
@onready var tech_nav_btn: Button = $Margin/VBox/NavBar/TechNavBtn
@onready var site_nav_btn: Button = $Margin/VBox/NavBar/SiteNavBtn

@onready var unit_list_view: Control = $Margin/VBox/ViewContainer/UnitList
@onready var tech_tree_view: Control = $Margin/VBox/ViewContainer/TechTree
@onready var site_sale_view: Control = $Margin/VBox/ViewContainer/SiteSale
@onready var event_card: Control = $Margin/VBox/EventCard

@onready var top_bar: PanelContainer = $Margin/VBox/TopBar
@onready var settings_dialog: PanelContainer = $Settings

var current_view: String = "facility"

func _ready() -> void:
	boost_btn.pressed.connect(_on_boost_pressed)
	facility_nav_btn.pressed.connect(func(): _switch_view("facility"))
	tech_nav_btn.pressed.connect(func(): _switch_view("tech_tree"))
	site_nav_btn.pressed.connect(func(): _switch_view("site_sale"))
	top_bar.settings_requested.connect(func(): settings_dialog.open_settings())
	
	GameState.state_updated.connect(_update_boost_button)
	_update_boost_button()
	_switch_view("facility")

func _switch_view(view_name: String) -> void:
	current_view = view_name
	
	unit_list_view.visible = (view_name == "facility")
	tech_tree_view.visible = (view_name == "tech_tree")
	site_sale_view.visible = (view_name == "site_sale")
	
	facility_nav_btn.modulate = Color(0.22, 0.74, 0.97, 1) if view_name == "facility" else Color(0.6, 0.6, 0.6, 0.8)
	tech_nav_btn.modulate = Color(0.66, 0.53, 0.98, 1) if view_name == "tech_tree" else Color(0.6, 0.6, 0.6, 0.8)
	site_nav_btn.modulate = Color(0.22, 0.77, 0.37, 1) if view_name == "site_sale" else Color(0.6, 0.6, 0.6, 0.8)

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
