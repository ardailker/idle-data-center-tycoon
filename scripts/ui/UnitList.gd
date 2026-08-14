extends VBoxContainer

const UnitCardScene = preload("res://scenes/ui/UnitCard.tscn")

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
	it_tab_btn.pressed.connect(func(): _select_category("it"))
	elec_tab_btn.pressed.connect(func(): _select_category("electrical"))
	mech_tab_btn.pressed.connect(func(): _select_category("mechanical"))
	
	mult_1_btn.pressed.connect(func(): _select_multiplier(1))
	mult_10_btn.pressed.connect(func(): _select_multiplier(10))
	mult_max_btn.pressed.connect(func(): _select_multiplier(-1))
	
	_select_category("it")
	_select_multiplier(1)

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
