extends VBoxContainer

@onready var rev_summary_label: Label = $PrestigeCard/Margin/VBox/RevSummaryLabel
@onready var tt_reward_label: Label = $PrestigeCard/Margin/VBox/TTRewardLabel
@onready var sell_btn: Button = $PrestigeCard/Margin/VBox/Actions/SellBtn
@onready var sell_ad_btn: Button = $PrestigeCard/Margin/VBox/Actions/SellAdBtn
@onready var sites_container: VBoxContainer = $Scroll/SitesContainer

var selected_tier: int = 1

func _ready() -> void:
	GameState.currency_changed.connect(func(_c, _tt): _update_view())
	GameState.state_updated.connect(_update_view)
	GameState.site_changed.connect(func(tier): selected_tier = tier; _update_view())
	
	sell_btn.pressed.connect(_on_sell_pressed)
	sell_ad_btn.pressed.connect(_on_sell_ad_pressed)
	
	selected_tier = GameState.state["site_tier"]
	_update_view()

func _update_view() -> void:
	var lifetime_rev: float = float(GameState.state.get("lifetime_revenue_this_site", 0.0))
	var tokens: int = Economy.calculate_prestige_tokens(lifetime_rev)
	var ad_tokens: int = int(floor(float(tokens) * 1.25))
	
	rev_summary_label.text = "Current Site Revenue: $%s / $1.00 B" % Economy.format_magnitude(lifetime_rev)
	
	if lifetime_rev < 1.0e9:
		tt_reward_label.text = "PRESTIGE LOCKED (Reach $1.00 B Lifetime Revenue)"
		tt_reward_label.modulate = Color(0.96, 0.62, 0.04, 1)
		sell_btn.disabled = true
		sell_btn.text = "SELL FACILITY (LOCKED)"
		sell_ad_btn.disabled = true
		sell_ad_btn.text = "+25% REWARDED AD (LOCKED)"
	else:
		tt_reward_label.text = "REWARD: +%d TECH TOKENS" % tokens
		tt_reward_label.modulate = Color(0.66, 0.53, 0.98, 1)
		sell_btn.disabled = false
		sell_btn.text = "SELL FACILITY (+%d TT)" % tokens
		sell_ad_btn.disabled = false
		sell_ad_btn.text = "SELL + 25% AD BONUS (+%d TT)" % ad_tokens
	
	_populate_sites()

func _populate_sites() -> void:
	for child in sites_container.get_children():
		child.queue_free()
	
	var current_tier: int = int(GameState.state.get("site_tier", 1))
	var current_tt: int = int(GameState.state.get("tech_tokens", 0))
	
	for site in GameState.sites_data:
		var tier: int = int(site.get("tier", 1))
		var cost_tt: int = int(site.get("unlock_cost_tt", 0))
		var card := _create_site_card(site, tier, current_tier, cost_tt, current_tt)
		sites_container.add_child(card)

func _create_site_card(site: Dictionary, tier: int, current_tier: int, cost_tt: int, current_tt: int) -> PanelContainer:
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
	name_label.text = "Tier %d: %s" % [tier, site.get("name", "")]
	name_label.add_theme_font_size_override("font_size", 15)
	info_box.add_child(name_label)
	
	var desc_label := Label.new()
	var climate_pct := int(float(site.get("climate_modifier", 0.0)) * 100.0)
	var contract_str := ""
	if float(site.get("contract_multiplier", 1.0)) > 1.0:
		contract_str = " | %.0fx Contract Rate" % float(site.get("contract_multiplier", 1.0))
	desc_label.text = "%s (Climate Eff: %d%%%s)" % [site.get("description", ""), climate_pct, contract_str]
	desc_label.add_theme_color_override("font_color", Color(0.58, 0.64, 0.72, 1))
	desc_label.add_theme_font_size_override("font_size", 11)
	info_box.add_child(desc_label)
	
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120, 44)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(btn)
	
	if tier == current_tier:
		btn.text = "ACTIVE SITE"
		btn.disabled = true
		btn.add_theme_color_override("font_color", Color(0.22, 0.77, 0.37, 1))
	elif tier < current_tier or cost_tt == 0:
		btn.text = "SELECT TIER"
		btn.disabled = false
		btn.pressed.connect(func():
			selected_tier = tier
			GameState.state["site_tier"] = tier
			GameState.recalculate_all_metrics()
			_update_view()
		)
	elif current_tt >= cost_tt:
		btn.text = "UNLOCK\n%d TT" % cost_tt
		btn.disabled = false
		btn.pressed.connect(func(): GameState.unlock_site_tier(tier))
	else:
		btn.text = "UNLOCK\n%d TT" % cost_tt
		btn.disabled = true
	
	return panel

func _on_sell_pressed() -> void:
	GameState.prestige_site_sale(false, selected_tier)
	_update_view()

func _on_sell_ad_pressed() -> void:
	Ads.show_rewarded_ad("site_sale_25pct", func():
		GameState.prestige_site_sale(true, selected_tier)
		_update_view()
	)
