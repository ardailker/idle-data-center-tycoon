extends VBoxContainer

@onready var tt_header_label: Label = $Header/TTLabel
@onready var elec_tab_btn: Button = $BranchTabs/ElecBtn
@onready var mech_tab_btn: Button = $BranchTabs/MechBtn
@onready var comp_tab_btn: Button = $BranchTabs/CompBtn
@onready var ops_tab_btn: Button = $BranchTabs/OpsBtn
@onready var nodes_container: VBoxContainer = $Scroll/NodesContainer

var current_branch_id: String = "electrical"

func _ready() -> void:
	elec_tab_btn.pressed.connect(func(): _select_branch("electrical"))
	mech_tab_btn.pressed.connect(func(): _select_branch("mechanical"))
	comp_tab_btn.pressed.connect(func(): _select_branch("compute"))
	ops_tab_btn.pressed.connect(func(): _select_branch("ops"))
	
	GameState.currency_changed.connect(func(_c, _tt): _update_view())
	GameState.state_updated.connect(_update_view)
	
	_select_branch("electrical")

func _select_branch(branch_id: String) -> void:
	current_branch_id = branch_id
	_highlight_tabs()
	_populate_nodes()

func _highlight_tabs() -> void:
	elec_tab_btn.modulate = Color(1, 1, 1, 1) if current_branch_id == "electrical" else Color(0.6, 0.6, 0.6, 0.8)
	mech_tab_btn.modulate = Color(1, 1, 1, 1) if current_branch_id == "mechanical" else Color(0.6, 0.6, 0.6, 0.8)
	comp_tab_btn.modulate = Color(1, 1, 1, 1) if current_branch_id == "compute" else Color(0.6, 0.6, 0.6, 0.8)
	ops_tab_btn.modulate = Color(1, 1, 1, 1) if current_branch_id == "ops" else Color(0.6, 0.6, 0.6, 0.8)

func _update_view() -> void:
	tt_header_label.text = "RESEARCH VAULT: %d TECH TOKENS" % GameState.state["tech_tokens"]
	_populate_nodes()

func _populate_nodes() -> void:
	tt_header_label.text = "RESEARCH VAULT: %d TECH TOKENS" % GameState.state["tech_tokens"]
	for child in nodes_container.get_children():
		child.queue_free()
	
	var branch_data: Dictionary = {}
	for b in GameState.tech_branches:
		if b.get("id", "") == current_branch_id:
			branch_data = b
			break
	
	if branch_data.is_empty():
		return
	
	var nodes: Array = branch_data.get("nodes", [])
	var unlocked_list: Array = GameState.state["unlocked_techs"]
	var current_tt: int = int(GameState.state["tech_tokens"])
	
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		var node_id: String = node.get("id", "")
		var cost_tt: int = int(node.get("cost_tt", 1))
		var is_unlocked: bool = (node_id in unlocked_list)
		var prev_unlocked: bool = (i == 0) or (nodes[i - 1].get("id", "") in unlocked_list)
		
		var card := _create_node_card(node, is_unlocked, prev_unlocked, current_tt)
		nodes_container.add_child(card)

func _create_node_card(node: Dictionary, is_unlocked: bool, prev_unlocked: bool, current_tt: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 80)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)
	
	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_box)
	
	var name_label := Label.new()
	name_label.text = node.get("name", "")
	name_label.add_theme_font_size_override("font_size", 15)
	info_box.add_child(name_label)
	
	var desc_label := Label.new()
	desc_label.text = node.get("description", "")
	desc_label.add_theme_color_override("font_color", Color(0.58, 0.64, 0.72, 1))
	desc_label.add_theme_font_size_override("font_size", 12)
	info_box.add_child(desc_label)
	
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120, 48)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(btn)
	
	var node_id: String = node.get("id", "")
	var cost_tt: int = int(node.get("cost_tt", 1))
	
	if is_unlocked:
		btn.text = "RESEARCHED"
		btn.disabled = true
		btn.add_theme_color_override("font_color", Color(0.22, 0.77, 0.37, 1))
	elif not prev_unlocked:
		btn.text = "LOCKED\n(%d TT)" % cost_tt
		btn.disabled = true
	elif current_tt < cost_tt:
		btn.text = "RESEARCH\n%d TT" % cost_tt
		btn.disabled = true
	else:
		btn.text = "RESEARCH\n%d TT" % cost_tt
		btn.disabled = false
		btn.pressed.connect(func(): GameState.unlock_tech_node(node_id))
	
	return panel
