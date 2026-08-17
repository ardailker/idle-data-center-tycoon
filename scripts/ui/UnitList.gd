extends VBoxContainer

const UnitCardScene = preload("res://scenes/ui/UnitCard.tscn")

@onready var facility_tap_panel: PanelContainer = $FacilityTapPanel
@onready var it_tab_btn: Button = $Controls/CategoryTabs/ITTabBtn
@onready var elec_tab_btn: Button = $Controls/CategoryTabs/ElecTabBtn
@onready var mech_tab_btn: Button = $Controls/CategoryTabs/MechTabBtn

@onready var mult_1_btn: Button = $Controls/MultiplierControls/Mult1Btn
@onready var mult_10_btn: Button = $Controls/MultiplierControls/Mult10Btn
@onready var mult_max_btn: Button = $Controls/MultiplierControls/MultMaxBtn

@onready var card_container: VBoxContainer = $Scroll/CardContainer

var current_category: String = "it"
var current_buy_multiplier: int = 1 # 1, 10, -1 (MAX)
var active_card_nodes: Array[Node] = []

func _ready() -> void:
	facility_tap_panel.job_requested.connect(_on_manual_job_requested)
	it_tab_btn.pressed.connect(func(): _select_category("it"))
	elec_tab_btn.pressed.connect(func(): _select_category("electrical"))
	mech_tab_btn.pressed.connect(func(): _select_category("mechanical"))
	
	mult_1_btn.pressed.connect(func(): _select_multiplier(1))
	mult_10_btn.pressed.connect(func(): _select_multiplier(10))
	mult_max_btn.pressed.connect(func(): _select_multiplier(-1))
	GameState.state_updated.connect(_update_facility_tap_panel)
	GameState.site_changed.connect(func(_tier): _update_facility_tap_panel())
	
	_update_facility_tap_panel()
	_select_category("it")
	_select_multiplier(1)

func _update_facility_tap_panel() -> void:
	var tier: int = int(GameState.state.get("site_tier", 1))
	var site: Dictionary = GameState.sites_dict.get(tier, {})
	var reward: float = Economy.calculate_manual_job_reward(
		GameState.revenue_per_sec,
		GameState.get_manual_job_reward_seconds()
	)
	facility_tap_panel.set_job_state(
		tier,
		String(site.get("name", "Data Center")),
		reward,
		int(floor(GameState.manual_job_charges)),
		int(GameState.get_manual_job_max_charges())
	)

func _on_manual_job_requested(click_position: Vector2) -> void:
	var reward: float = GameState.claim_manual_job()
	if reward <= 0.0:
		return
	SoundManager.play_cash()
	SoundManager.play_haptic(10)
	facility_tap_panel.show_job_feedback(reward, click_position)
	_update_facility_tap_panel()

func _select_category(cat: String) -> void:
	current_category = cat
	_highlight_active_tab()
	_populate_cards()

func _select_multiplier(mode: int) -> void:
	current_buy_multiplier = mode
	_highlight_active_multiplier()
	for card in active_card_nodes:
		if card.has_method("set_buy_multiplier"):
			card.set_buy_multiplier(current_buy_multiplier)

func _highlight_active_tab() -> void:
	it_tab_btn.modulate = Color(1, 1, 1, 1) if current_category == "it" else Color(0.6, 0.6, 0.6, 0.8)
	elec_tab_btn.modulate = Color(1, 1, 1, 1) if current_category == "electrical" else Color(0.6, 0.6, 0.6, 0.8)
	mech_tab_btn.modulate = Color(1, 1, 1, 1) if current_category == "mechanical" else Color(0.6, 0.6, 0.6, 0.8)

func _highlight_active_multiplier() -> void:
	mult_1_btn.modulate = Color(0.22, 0.74, 0.97, 1) if current_buy_multiplier == 1 else Color(0.6, 0.6, 0.6, 0.8)
	mult_10_btn.modulate = Color(0.22, 0.74, 0.97, 1) if current_buy_multiplier == 10 else Color(0.6, 0.6, 0.6, 0.8)
	mult_max_btn.modulate = Color(0.22, 0.74, 0.97, 1) if current_buy_multiplier == -1 else Color(0.6, 0.6, 0.6, 0.8)

func _populate_cards() -> void:
	for child in card_container.get_children():
		child.queue_free()
	active_card_nodes.clear()
	
	for unit in GameState.units_data:
		if unit.get("category", "") == current_category:
			var card = UnitCardScene.instantiate()
			card_container.add_child(card)
			card.setup(unit, current_buy_multiplier)
			active_card_nodes.append(card)
