extends VBoxContainer

@onready var rev_summary_label: Label = $PrestigeCard/Margin/VBox/RevSummaryLabel
@onready var tt_reward_label: Label = $PrestigeCard/Margin/VBox/TTRewardLabel
@onready var sell_btn: Button = $PrestigeCard/Margin/VBox/Actions/SellBtn
@onready var sell_ad_btn: Button = $PrestigeCard/Margin/VBox/Actions/SellAdBtn
@onready var sites_container: VBoxContainer = $Scroll/SitesContainer

var selected_tier: int = 1
var rendered_tt: int = -1

func _ready() -> void:
	GameState.currency_changed.connect(_on_currency_changed)
	GameState.state_updated.connect(_update_progress)
	GameState.site_changed.connect(func(tier): selected_tier = tier; _update_view())
	
	sell_btn.pressed.connect(_on_sell_pressed)
	sell_ad_btn.pressed.connect(_on_sell_ad_pressed)
	
	selected_tier = GameState.state["site_tier"]
	_update_view()

func _update_view() -> void:
	_update_progress()
	rendered_tt = int(GameState.state.get("tech_tokens", 0))
	_populate_sites()

func _on_currency_changed(_cash: float, tech_tokens: int) -> void:
	_update_progress()
	if tech_tokens != rendered_tt:
		rendered_tt = tech_tokens
		call_deferred("_populate_sites")

func _update_progress() -> void:
	var lifetime_rev: float = float(GameState.state.get("lifetime_revenue_this_site", 0.0))
	var prestige_requirement: float = GameState.get_prestige_revenue_requirement()
	var tokens: int = GameState.calculate_prestige_tokens(lifetime_rev)
	var ad_tokens: int = int(floor(float(tokens) * 1.25))
	
	rev_summary_label.text = "Current Site Revenue: $%s / $%s" % [
		Economy.format_magnitude(lifetime_rev),
		Economy.format_magnitude(prestige_requirement)
	]
	
	if lifetime_rev < prestige_requirement:
		tt_reward_label.text = "PRESTIGE LOCKED (Reach $%s Lifetime Revenue)" % Economy.format_magnitude(prestige_requirement)
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
		sell_ad_btn.text = "SELL + 25%% AD BONUS (+%d TT)" % ad_tokens
	
func _populate_sites() -> void:
	for child in sites_container.get_children():
		child.queue_free()
	
	var current_tier: int = int(GameState.state.get("site_tier", 1))
	var current_tt: int = int(GameState.state.get("tech_tokens", 0))
	var unlocked_tiers: Array = GameState.state.get("unlocked_site_tiers", [1])
	
	for site in GameState.sites_data:
		var tier: int = int(site.get("tier", 1))
		var cost_tt: int = int(site.get("unlock_cost_tt", 0))
		var card := _create_site_card(site, tier, current_tier, cost_tt, current_tt, tier in unlocked_tiers)
		sites_container.add_child(card)

func _create_site_card(site: Dictionary, tier: int, current_tier: int, cost_tt: int, current_tt: int, is_unlocked: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 124)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)
	
	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.add_theme_constant_override("separation", 3)
	vbox.add_child(info_box)
	
	var name_label := Label.new()
	name_label.text = "Tier %d: %s" % [tier, site.get("name", "")]
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_box.add_child(name_label)
	
	var desc_label := Label.new()
	var climate_pct := int(float(site.get("climate_modifier", 0.0)) * 100.0)
	var contract_str := ""
	if float(site.get("contract_multiplier", 1.0)) > 1.0:
		contract_str = " | %.0fx Contract Rate" % float(site.get("contract_multiplier", 1.0))
	desc_label.text = "%s (Climate Eff: %d%%%s)" % [site.get("description", ""), climate_pct, contract_str]
	desc_label.add_theme_color_override("font_color", Color(0.58, 0.64, 0.72, 1))
	desc_label.add_theme_font_size_override("font_size", 8)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.max_lines_visible = 3
	desc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_box.add_child(desc_label)
	
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 40)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 9)
	vbox.add_child(btn)
	
	if tier == current_tier:
		btn.text = "ACTIVE SITE"
		btn.disabled = true
		btn.add_theme_color_override("font_color", Color(0.22, 0.77, 0.37, 1))
	elif is_unlocked:
		btn.text = "SELECT TIER"
		btn.disabled = false
		btn.pressed.connect(func():
			selected_tier = tier
			GameState.select_site_tier(tier)
			_update_view()
		)
	elif current_tt >= cost_tt and (tier == 1 or (tier - 1) in GameState.state.get("unlocked_site_tiers", [1])):
		btn.text = "UNLOCK | %d TT" % cost_tt
		btn.disabled = false
		btn.pressed.connect(func(): GameState.unlock_site_tier(tier))
	else:
		btn.text = "UNLOCK | %d TT" % cost_tt
		btn.disabled = true
	
	return panel

func _on_sell_pressed() -> void:
	if GameState.prestige_site_sale(false, selected_tier) > 0:
		SoundManager.play_prestige()
		SoundManager.play_haptic(60)
	_update_view()

func _on_sell_ad_pressed() -> void:
	Ads.show_rewarded_ad("site_sale_25pct", func():
		if GameState.prestige_site_sale(true, selected_tier) > 0:
			SoundManager.play_prestige()
			SoundManager.play_haptic(60)
		_update_view()
	)
