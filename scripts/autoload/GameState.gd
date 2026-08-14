extends Node

# Signals
signal state_updated()
signal currency_changed(cash: float, tech_tokens: int)
signal units_changed(unit_id: String, new_count: int)
signal site_changed(tier: int)
signal thermal_alert(active: bool)
signal rack_tripped(unit_id: String)
signal event_started(event_data: Dictionary)
signal event_ended(event_data: Dictionary)

# Loaded Catalog Definitions
var units_data: Array = []
var units_dict: Dictionary = {}
var sites_data: Array = []
var sites_dict: Dictionary = {}
var tech_branches: Array = []
var tech_nodes_dict: Dictionary = {}
var events_data: Array = []
var events_dict: Dictionary = {}

# Active State Structure
var state: Dictionary = {
	"schema_version": 1,
	"cash": 15.0, # Initial starting cash for first rack
	"tech_tokens": 0,
	"site_tier": 1,
	"lifetime_revenue_this_site": 0.0,
	"lifetime_revenue_all_time": 0.0,
	"unit_counts": {
		"rack_1u": 1,
		"blade_chassis": 0,
		"gpu_pod": 0,
		"pdu": 1,
		"ups_transformer": 0,
		"diesel_gen": 0,
		"crac_unit": 1,
		"chilled_water_plant": 0,
		"economizer": 0
	},
	"unlocked_techs": [],
	"remove_ads_owned": false,
	"last_save_time": 0,
	"settings": {
		"sfx_enabled": true,
		"music_enabled": true,
		"haptics_enabled": true
	}
}

# Realtime dynamic calculations & modifiers
var it_load_kw: float = 0.0
var mech_load_kw: float = 0.0
var total_load_kw: float = 0.0
var pue: float = 2.0
var heat_load_kwth: float = 0.0
var power_capacity_kw: float = 0.0
var cooling_capacity_kwth: float = 0.0
var throttle_ratio: float = 1.0
var compute_rate: float = 0.0
var uptime_mult: float = 0.99
var revenue_per_sec: float = 0.0

# Boosts & Events State
var boost_time_remaining: float = 0.0
var boost_multiplier: float = 1.0
var active_event: Dictionary = {}
var active_event_time_remaining: float = 0.0
var thermal_alarm_timer: float = 0.0
var thermal_tripped_count: int = 0

# Timers
var tick_accumulator: float = 0.0
var auto_save_accumulator: float = 0.0

func _ready() -> void:
	load_all_catalogs()
	recalculate_all_metrics()

func load_all_catalogs() -> void:
	units_data = _load_json_file("res://data/units.json").get("units", [])
	for u in units_data:
		units_dict[u["id"]] = u
	
	sites_data = _load_json_file("res://data/sites.json").get("sites", [])
	for s in sites_data:
		sites_dict[s["tier"]] = s
	
	tech_branches = _load_json_file("res://data/tech_tree.json").get("branches", [])
	for b in tech_branches:
		for n in b.get("nodes", []):
			tech_nodes_dict[n["id"]] = n
	
	events_data = _load_json_file("res://data/events.json").get("events", [])
	for e in events_data:
		events_dict[e["id"]] = e

func _load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("JSON file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var content := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(content)
	if err == OK and json.data is Dictionary:
		return json.data
	return {}

func _process(delta: float) -> void:
	# Tick economy at 10 Hz (0.1s interval) per §7.4
	tick_accumulator += delta
	while tick_accumulator >= 0.1:
		tick_accumulator -= 0.1
		_economy_tick(0.1)
	
	# Auto-save every 30s per §7.5
	auto_save_accumulator += delta
	if auto_save_accumulator >= 30.0:
		auto_save_accumulator = 0.0
		if SaveManager:
			SaveManager.save_game()

func _economy_tick(dt: float) -> void:
	# Update active boosts and events
	if boost_time_remaining > 0.0:
		boost_time_remaining = max(boost_time_remaining - dt, 0.0)
		if boost_time_remaining <= 0.0:
			boost_multiplier = 1.0
	
	if active_event_time_remaining > 0.0:
		active_event_time_remaining = max(active_event_time_remaining - dt, 0.0)
		if active_event_time_remaining <= 0.0:
			var finished_event := active_event.duplicate()
			active_event.clear()
			event_ended.emit(finished_event)
			recalculate_all_metrics()
	
	recalculate_all_metrics()
	
	# Handle thermal alarm & tripping (§4.2)
	if cooling_capacity_kwth < heat_load_kwth:
		thermal_alarm_timer += dt
		thermal_alert.emit(true)
		# After 30s of thermal alarm, racks start tripping offline
		if thermal_alarm_timer >= 30.0:
			_trip_one_rack()
			thermal_alarm_timer = 20.0 # Repeatedly trip every 10s if unaddressed
	else:
		if thermal_alarm_timer > 0.0:
			thermal_alarm_timer = 0.0
			thermal_alert.emit(false)
	
	# Accumulate revenue
	var earned: float = revenue_per_sec * dt
	if earned > 0.0:
		state["cash"] += earned
		state["lifetime_revenue_this_site"] += earned
		state["lifetime_revenue_all_time"] += earned
		currency_changed.emit(state["cash"], state["tech_tokens"])

func recalculate_all_metrics() -> void:
	var counts: Dictionary = state["unit_counts"]
	
	# Tech modifiers (§5: intra-branch multiplicative, cross-branch additive)
	var tech_power_loss_red: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "power_loss_reduction")
	var tech_mech_power_red: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "mech_power_reduction")
	var tech_power_cap_bonus: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "power_capacity_bonus")
	var tech_cool_cap_bonus: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "cooling_capacity_bonus")
	var tech_heat_red: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "heat_reduction")
	var tech_compute_mult: float = Economy.calculate_tech_multiplier(state["unlocked_techs"], tech_nodes_dict, tech_branches, "compute_multiplier")
	var tech_uptime_bonus: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "uptime_bonus")
	var tech_rev_mult: float = Economy.calculate_tech_multiplier(state["unlocked_techs"], tech_nodes_dict, tech_branches, "revenue_multiplier")
	var tech_contract_mult: float = Economy.calculate_tech_multiplier(state["unlocked_techs"], tech_nodes_dict, tech_branches, "contract_rate_multiplier")
	
	# Current site
	var site: Dictionary = sites_dict.get(state["site_tier"], {})
	var climate_mod: float = float(site.get("climate_modifier", 1.0))
	var site_contract_mult: float = float(site.get("contract_multiplier", 1.0))
	
	# Event modifiers
	var event_power_mult: float = 1.0
	var event_cool_mult: float = 1.0
	var event_compute_mult: float = 1.0
	if not active_event.is_empty():
		var target: String = active_event.get("effect_target", "")
		var mult: float = float(active_event.get("effect_multiplier", 1.0))
		if target == "power_capacity":
			event_power_mult = mult
		elif target == "cooling_capacity":
			event_cool_mult = mult
		elif target == "compute_demand":
			event_compute_mult = mult
	
	it_load_kw = Economy.calculate_it_load_kw(counts, units_dict)
	mech_load_kw = Economy.calculate_mech_load_kw(counts, units_dict, tech_mech_power_red)
	total_load_kw = Economy.calculate_total_load_kw(it_load_kw, mech_load_kw, tech_power_loss_red)
	pue = Economy.calculate_pue(total_load_kw, it_load_kw)
	heat_load_kwth = Economy.calculate_heat_load_kwth(counts, units_dict, tech_heat_red)
	
	power_capacity_kw = Economy.calculate_power_capacity(counts, units_dict, tech_power_cap_bonus) * event_power_mult
	cooling_capacity_kwth = Economy.calculate_cooling_capacity(counts, units_dict, climate_mod, tech_cool_cap_bonus) * event_cool_mult
	
	throttle_ratio = Economy.calculate_throttle(power_capacity_kw, total_load_kw)
	compute_rate = Economy.calculate_compute_rate(counts, units_dict, tech_compute_mult) * event_compute_mult
	
	var trip_ratio: float = 0.0
	var total_it_racks: int = counts.get("rack_1u", 0) + counts.get("blade_chassis", 0) + counts.get("gpu_pod", 0)
	if total_it_racks > 0:
		trip_ratio = float(thermal_tripped_count) / float(total_it_racks)
	uptime_mult = Economy.calculate_uptime(counts, units_dict, tech_uptime_bonus, trip_ratio)
	
	var base_contract_rate: float = 1.0 * tech_contract_mult
	revenue_per_sec = Economy.calculate_revenue_per_sec(
		compute_rate,
		throttle_ratio,
		base_contract_rate,
		uptime_mult,
		site_contract_mult,
		tech_rev_mult,
		boost_multiplier
	)
	
	state_updated.emit()

func _sum_tech_effects(effect_type: String) -> float:
	var total: float = 0.0
	for tech_id in state["unlocked_techs"]:
		var node: Dictionary = tech_nodes_dict.get(tech_id, {})
		if node.get("effect_type", "") == effect_type:
			total += float(node.get("effect_value", 0.0))
	return total

func _trip_one_rack() -> void:
	thermal_tripped_count += 1
	rack_tripped.emit("rack_tripped")

func buy_unit(unit_id: String, amount: int = 1) -> bool:
	var unit: Dictionary = units_dict.get(unit_id, {})
	if unit.is_empty():
		return false
	
	var current_count: int = state["unit_counts"].get(unit_id, 0)
	var total_cost: float = Economy.calculate_bulk_unit_cost(
		float(unit.get("base_cost", 10.0)),
		float(unit.get("cost_growth", 1.12)),
		current_count,
		amount
	)
	
	if state["cash"] < total_cost:
		return false
	
	state["cash"] -= total_cost
	state["unit_counts"][unit_id] = current_count + amount
	units_changed.emit(unit_id, state["unit_counts"][unit_id])
	currency_changed.emit(state["cash"], state["tech_tokens"])
	recalculate_all_metrics()
	
	# Save immediately on purchase per §7.5
	if SaveManager:
		SaveManager.save_game()
	return true
