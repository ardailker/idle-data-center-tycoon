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
var balance_data: Dictionary = {}

# Active State Structure
var state: Dictionary = {
	"schema_version": 3,
	"cash": 15.0, # Initial starting cash for first rack
	"tech_tokens": 0,
	"site_tier": 1,
	"unlocked_site_tiers": [1],
	"lifetime_revenue_this_site": 0.0,
	"lifetime_revenue_all_time": 0.0,
	"prestige_count": 0,
	"unit_counts": {
		"rack_1u": 1,
		"blade_chassis": 0,
		"gpu_pod": 0,
		"edge_cluster": 0,
		"ai_superpod": 0,
		"pdu": 1,
		"ups_transformer": 0,
		"diesel_gen": 0,
		"modular_substation": 0,
		"battery_farm": 0,
		"crac_unit": 1,
		"chilled_water_plant": 0,
		"economizer": 0,
		"inrow_cooling": 0,
		"immersion_plant": 0
	},
	"unlocked_techs": [],
	"job_upgrade_levels": {},
	"remove_ads_owned": false,
	"starter_pack_owned": false,
	"boost_end_time": 0,
	"rewarded_boost_day": "",
	"rewarded_boost_count": 0,
	"interstitial_day": "",
	"interstitial_count": 0,
	"last_interstitial_time": 0,
	"pending_offline_data": {},
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
var uptime_reliability_bonus: float = 0.0
var uptime_power_penalty: float = 0.0
var uptime_cooling_penalty: float = 0.0
var uptime_trip_penalty: float = 0.0
var fuel_cost_per_sec: float = 0.0
var balance_revenue_multiplier: float = 1.0
var revenue_per_sec: float = 0.0

# Boosts & Events State
var boost_time_remaining: float = 0.0
var boost_multiplier: float = 1.0
var active_event: Dictionary = {}
var active_event_time_remaining: float = 0.0
var thermal_alarm_timer: float = 0.0
var thermal_tripped_count: int = 0
var thermal_recovery_timer: float = 0.0

# Random event scheduler (§4.6: one every 6-12 min of active play)
var event_spawn_timer: float = 0.0
var next_event_spawn_interval: float = 0.0

# Timers
var tick_accumulator: float = 0.0
var auto_save_accumulator: float = 0.0

const MANUAL_JOB_MAX_CHARGES: float = 5.0
const MANUAL_JOB_REGEN_PER_SECOND: float = 4.0
const MANUAL_JOB_REWARD_SECONDS: float = 0.25
var manual_job_charges: float = MANUAL_JOB_MAX_CHARGES

func _ready() -> void:
	load_all_catalogs()
	_reset_event_spawn_timer()
	recalculate_all_metrics()

func load_all_catalogs() -> void:
	units_data = _load_json_file("res://data/units.json").get("units", [])
	for u in units_data:
		units_dict[u["id"]] = u
	
	sites_data = _load_json_file("res://data/sites.json").get("sites", [])
	for s in sites_data:
		var tier_int: int = int(s.get("tier", 1))
		s["tier"] = tier_int
		sites_dict[tier_int] = s
	
	tech_branches = _load_json_file("res://data/tech_tree.json").get("branches", [])
	for b in tech_branches:
		for n in b.get("nodes", []):
			tech_nodes_dict[n["id"]] = n
	
	events_data = _load_json_file("res://data/events.json").get("events", [])
	for e in events_data:
		events_dict[e["id"]] = e

	balance_data = _load_json_file("res://data/balance.json")

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
	recharge_manual_jobs(delta)
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

func recharge_manual_jobs(delta: float) -> void:
	var max_charges: float = get_manual_job_max_charges()
	if delta <= 0.0 or manual_job_charges >= max_charges:
		return
	manual_job_charges = min(manual_job_charges + delta * get_manual_job_regen_per_second(), max_charges)

func claim_manual_job() -> float:
	if manual_job_charges < 1.0:
		return 0.0
	manual_job_charges -= 1.0
	var reward: float = Economy.calculate_manual_job_reward(revenue_per_sec, get_manual_job_reward_seconds())
	state["cash"] += reward
	state["lifetime_revenue_this_site"] += reward
	state["lifetime_revenue_all_time"] += reward
	currency_changed.emit(state["cash"], state["tech_tokens"])
	state_updated.emit()
	return reward

func get_manual_job_upgrades() -> Array:
	return balance_data.get("manual_jobs", {}).get("upgrades", [])

func get_manual_job_upgrade(upgrade_id: String) -> Dictionary:
	for upgrade in get_manual_job_upgrades():
		if String(upgrade.get("id", "")) == upgrade_id:
			return upgrade
	return {}

func get_manual_job_upgrade_level(upgrade_id: String) -> int:
	return max(int(state.get("job_upgrade_levels", {}).get(upgrade_id, 0)), 0)

func get_manual_job_upgrade_cost(upgrade_id: String) -> float:
	var upgrade: Dictionary = get_manual_job_upgrade(upgrade_id)
	if upgrade.is_empty():
		return INF
	return Economy.calculate_unit_cost(
		float(upgrade.get("base_cost", 1.0)),
		float(upgrade.get("cost_growth", 1.0)),
		get_manual_job_upgrade_level(upgrade_id)
	)

func get_manual_job_reward_seconds() -> float:
	var config: Dictionary = balance_data.get("manual_jobs", {})
	var reward_seconds: float = float(config.get("base_reward_seconds", MANUAL_JOB_REWARD_SECONDS))
	for upgrade in get_manual_job_upgrades():
		if upgrade.get("effect_type", "") == "reward_multiplier":
			var level: int = get_manual_job_upgrade_level(String(upgrade.get("id", "")))
			reward_seconds *= 1.0 + float(upgrade.get("effect_per_level", 0.0)) * level
	return reward_seconds

func get_manual_job_max_charges() -> float:
	var config: Dictionary = balance_data.get("manual_jobs", {})
	var max_charges: float = float(config.get("base_max_charges", MANUAL_JOB_MAX_CHARGES))
	for upgrade in get_manual_job_upgrades():
		if upgrade.get("effect_type", "") == "max_charges":
			var level: int = get_manual_job_upgrade_level(String(upgrade.get("id", "")))
			max_charges += float(upgrade.get("effect_per_level", 0.0)) * level
	return max(max_charges, 1.0)

func get_manual_job_regen_per_second() -> float:
	var config: Dictionary = balance_data.get("manual_jobs", {})
	var regen_per_second: float = float(config.get("base_regen_per_second", MANUAL_JOB_REGEN_PER_SECOND))
	for upgrade in get_manual_job_upgrades():
		if upgrade.get("effect_type", "") == "regen_multiplier":
			var level: int = get_manual_job_upgrade_level(String(upgrade.get("id", "")))
			regen_per_second *= 1.0 + float(upgrade.get("effect_per_level", 0.0)) * level
	return max(regen_per_second, 0.0)

func purchase_manual_job_upgrade(upgrade_id: String) -> bool:
	var upgrade: Dictionary = get_manual_job_upgrade(upgrade_id)
	if upgrade.is_empty():
		return false
	var level: int = get_manual_job_upgrade_level(upgrade_id)
	if level >= int(upgrade.get("max_level", 1)):
		return false
	var cost: float = get_manual_job_upgrade_cost(upgrade_id)
	if float(state.get("cash", 0.0)) < cost:
		return false

	var old_max_charges: float = get_manual_job_max_charges()
	state["cash"] = float(state.get("cash", 0.0)) - cost
	var levels: Dictionary = state.get("job_upgrade_levels", {}).duplicate()
	levels[upgrade_id] = level + 1
	state["job_upgrade_levels"] = levels
	var new_max_charges: float = get_manual_job_max_charges()
	manual_job_charges = min(manual_job_charges + max(new_max_charges - old_max_charges, 0.0), new_max_charges)
	currency_changed.emit(state["cash"], state["tech_tokens"])
	state_updated.emit()
	if SaveManager:
		SaveManager.save_game()
	return true

func _economy_tick(dt: float) -> void:
	# Update active boosts and events
	_refresh_boost_state()
	
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
		thermal_recovery_timer = 0.0
		# N+1 Redundancy extends the grace period before racks trip.
		if thermal_alarm_timer >= get_thermal_trip_grace_seconds():
			_trip_one_rack()
			thermal_alarm_timer = get_thermal_trip_grace_seconds() - 10.0
	else:
		if thermal_alarm_timer > 0.0:
			thermal_alarm_timer = 0.0
			thermal_alert.emit(false)
		# Cooling has headroom again: recover tripped racks one by one (§4.2, "recoverable... no permanent loss")
		if thermal_tripped_count > 0:
			thermal_recovery_timer += dt
			if thermal_recovery_timer >= 10.0:
				thermal_recovery_timer = 0.0
				thermal_tripped_count = max(thermal_tripped_count - 1, 0)
				rack_tripped.emit("rack_recovered")
		else:
			thermal_recovery_timer = 0.0

	# Spawn a random event roughly every 6-12 min of active play (§4.6), never overlapping one already active
	if active_event.is_empty():
		event_spawn_timer += dt
		if event_spawn_timer >= next_event_spawn_interval:
			trigger_random_event()
			_reset_event_spawn_timer()

	# Accumulate revenue
	var earned: float = revenue_per_sec * dt
	if earned > 0.0:
		state["cash"] += earned
		state["lifetime_revenue_this_site"] += earned
		state["lifetime_revenue_all_time"] += earned
		currency_changed.emit(state["cash"], state["tech_tokens"])

func recalculate_all_metrics() -> void:
	_refresh_boost_state()
	var counts: Dictionary = state["unit_counts"]
	
	# Tech modifiers (§5: intra-branch multiplicative, cross-branch additive)
	var tech_power_loss_red: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "power_loss_reduction")
	var tech_mech_power_red: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "mech_power_reduction")
	var tech_power_cap_bonus: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "power_capacity_bonus")
	var tech_cool_cap_bonus: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "cooling_capacity_bonus")
	tech_cool_cap_bonus += Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "cooling_efficiency_bonus")
	var tech_heat_red: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "heat_reduction")
	var tech_event_mitigation: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "event_mitigation")
	var tech_compute_mult: float = Economy.calculate_tech_multiplier(state["unlocked_techs"], tech_nodes_dict, tech_branches, "compute_multiplier")
	var tech_uptime_bonus: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "uptime_bonus")
	var tech_rev_mult: float = Economy.calculate_tech_multiplier(state["unlocked_techs"], tech_nodes_dict, tech_branches, "revenue_multiplier")
	var tech_contract_mult: float = Economy.calculate_tech_multiplier(state["unlocked_techs"], tech_nodes_dict, tech_branches, "contract_rate_multiplier")
	
	# Current site
	var active_site_tier: int = int(state.get("site_tier", 1))
	var site: Dictionary = sites_dict.get(active_site_tier, {})
	var climate_mod: float = float(site.get("climate_modifier", 1.0))
	var site_contract_mult: float = float(site.get("contract_multiplier", 1.0))
	
	# Event modifiers
	var event_power_mult: float = 1.0
	var event_cool_mult: float = 1.0
	var event_compute_mult: float = 1.0
	if not active_event.is_empty():
		var target: String = active_event.get("effect_target", "")
		var mult: float = float(active_event.get("effect_multiplier", 1.0))
		if active_event.get("type", "") == "hazard" and mult < 1.0:
			var severity: float = 1.0 - mult
			mult = 1.0 - (severity * (1.0 - clamp(tech_event_mitigation, 0.0, 1.0)))
		if target == "power_capacity":
			event_power_mult = mult
		elif target == "cooling_capacity":
			event_cool_mult = mult
		elif target == "compute_demand":
			event_compute_mult = mult
	
	# Tripped racks (§4.2): produce no compute and draw no power/heat while offline
	var total_it_racks: int = 0
	for unit_id in counts:
		if units_dict.get(unit_id, {}).get("category", "") == "it":
			total_it_racks += int(counts.get(unit_id, 0))
	thermal_tripped_count = clamp(thermal_tripped_count, 0, total_it_racks)
	var trip_ratio: float = 0.0
	if total_it_racks > 0:
		trip_ratio = float(thermal_tripped_count) / float(total_it_racks)
	var it_capacity_ratio: float = 1.0 - trip_ratio

	var operating_counts: Dictionary = counts
	if active_event.get("effect_target", "") == "cooling_unit_offline":
		var offline_unit_id: String = active_event.get("offline_unit_id", "")
		if not offline_unit_id.is_empty() and int(counts.get(offline_unit_id, 0)) > 0:
			operating_counts = counts.duplicate()
			operating_counts[offline_unit_id] = int(counts[offline_unit_id]) - 1

	it_load_kw = Economy.calculate_it_load_kw(counts, units_dict) * it_capacity_ratio
	mech_load_kw = Economy.calculate_mech_load_kw(operating_counts, units_dict, tech_mech_power_red)
	total_load_kw = Economy.calculate_total_load_kw(it_load_kw, mech_load_kw, tech_power_loss_red)
	pue = Economy.calculate_pue(total_load_kw, it_load_kw)
	heat_load_kwth = Economy.calculate_heat_load_kwth(counts, units_dict, tech_heat_red) * it_capacity_ratio

	power_capacity_kw = Economy.calculate_power_capacity(counts, units_dict, tech_power_cap_bonus) * event_power_mult
	cooling_capacity_kwth = Economy.calculate_cooling_capacity(operating_counts, units_dict, climate_mod, tech_cool_cap_bonus) * event_cool_mult

	throttle_ratio = Economy.calculate_throttle(power_capacity_kw, total_load_kw)
	compute_rate = Economy.calculate_compute_rate(counts, units_dict, tech_compute_mult) * event_compute_mult * it_capacity_ratio

	var cooling_capacity_ratio: float = 1.0
	if heat_load_kwth > 0.001:
		cooling_capacity_ratio = cooling_capacity_kwth / heat_load_kwth
	var uptime_details: Dictionary = Economy.calculate_uptime_details(
		counts,
		units_dict,
		tech_uptime_bonus,
		trip_ratio,
		throttle_ratio,
		cooling_capacity_ratio
	)
	uptime_mult = float(uptime_details["uptime"])
	uptime_reliability_bonus = float(uptime_details["reliability_bonus"])
	uptime_power_penalty = float(uptime_details["power_penalty"])
	uptime_cooling_penalty = float(uptime_details["cooling_penalty"])
	uptime_trip_penalty = float(uptime_details["trip_penalty"])
	
	var base_contract_rate: float = 1.0 * tech_contract_mult
	var economy_balance: Dictionary = balance_data.get("economy", {})
	balance_revenue_multiplier = float(economy_balance.get("revenue_multiplier", 1.0))
	var gross_revenue_per_sec: float = Economy.calculate_revenue_per_sec(
		compute_rate,
		throttle_ratio,
		base_contract_rate,
		uptime_mult,
		site_contract_mult,
		tech_rev_mult * balance_revenue_multiplier,
		boost_multiplier
	)
	fuel_cost_per_sec = Economy.calculate_fuel_cost_per_sec(counts, units_dict)
	revenue_per_sec = max(gross_revenue_per_sec - fuel_cost_per_sec, 0.0)
	
	state_updated.emit()

func _sum_tech_effects(effect_type: String) -> float:
	var total: float = 0.0
	for tech_id in state["unlocked_techs"]:
		var node: Dictionary = tech_nodes_dict.get(tech_id, {})
		if node.get("effect_type", "") == effect_type:
			total += float(node.get("effect_value", 0.0))
	return total

func get_prestige_revenue_requirement() -> float:
	return float(balance_data.get("prestige", {}).get("revenue_requirement", 1.0e6))

func get_prestige_base_tokens() -> int:
	return int(balance_data.get("prestige", {}).get("base_tokens", 12))

func calculate_prestige_tokens(lifetime_revenue: float) -> int:
	return Economy.calculate_prestige_tokens(
		lifetime_revenue,
		get_prestige_revenue_requirement(),
		get_prestige_base_tokens()
	)

func get_thermal_trip_grace_seconds() -> float:
	var bonus: float = Economy.calculate_tech_additive_bonus(
		state["unlocked_techs"],
		tech_nodes_dict,
		"trip_time_bonus"
	)
	return 30.0 * (1.0 + max(bonus, 0.0))

func activate_revenue_boost(duration_seconds: float) -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var current_end: int = int(state.get("boost_end_time", 0))
	state["boost_end_time"] = max(current_end, now) + int(max(duration_seconds, 0.0))
	_refresh_boost_state()
	recalculate_all_metrics()
	if SaveManager:
		SaveManager.save_game()

func can_activate_rewarded_boost() -> bool:
	_refresh_daily_counter("rewarded_boost_day", "rewarded_boost_count")
	return int(state.get("rewarded_boost_count", 0)) < 6

func activate_rewarded_boost() -> bool:
	if not can_activate_rewarded_boost():
		return false
	state["rewarded_boost_count"] = int(state.get("rewarded_boost_count", 0)) + 1
	activate_revenue_boost(240.0)
	return true

func get_rewarded_boosts_remaining() -> int:
	_refresh_daily_counter("rewarded_boost_day", "rewarded_boost_count")
	return max(6 - int(state.get("rewarded_boost_count", 0)), 0)

func try_record_interstitial_impression() -> bool:
	if bool(state.get("remove_ads_owned", false)):
		return false
	_refresh_daily_counter("interstitial_day", "interstitial_count")
	var now: int = int(Time.get_unix_time_from_system())
	if int(state.get("interstitial_count", 0)) >= 8:
		return false
	if now - int(state.get("last_interstitial_time", 0)) < 180:
		return false
	state["interstitial_count"] = int(state.get("interstitial_count", 0)) + 1
	state["last_interstitial_time"] = now
	return true

func _refresh_daily_counter(day_key: String, count_key: String) -> void:
	var today: String = Time.get_date_string_from_system()
	if String(state.get(day_key, "")) != today:
		state[day_key] = today
		state[count_key] = 0

func _refresh_boost_state() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var end_time: int = int(state.get("boost_end_time", 0))
	boost_time_remaining = float(max(end_time - now, 0))
	boost_multiplier = 2.0 if boost_time_remaining > 0.0 else 1.0

func _trip_one_rack() -> void:
	thermal_tripped_count += 1
	rack_tripped.emit("rack_tripped")

func _reset_event_spawn_timer() -> void:
	event_spawn_timer = 0.0
	next_event_spawn_interval = randf_range(360.0, 720.0) # 6-12 min of active play (§4.6)

func get_facility_cost_discount(category: String) -> float:
	var discount: float = 0.0
	for tech_id in state.get("unlocked_techs", []):
		var node: Dictionary = tech_nodes_dict.get(tech_id, {})
		var discount_category: String = String(node.get("facility_category", ""))
		if discount_category == category or discount_category == "all":
			discount += float(node.get("facility_cost_discount", 0.0))
	return clamp(discount, 0.0, 0.60)

func get_unit_effective_base_cost(unit_id: String) -> float:
	var unit: Dictionary = units_dict.get(unit_id, {})
	if unit.is_empty():
		return 0.0
	var category: String = String(unit.get("category", ""))
	var discount: float = get_facility_cost_discount(category)
	return float(unit.get("base_cost", 10.0)) * (1.0 - discount)

func get_current_site_climate_modifier() -> float:
	var active_site_tier: int = int(state.get("site_tier", 1))
	return float(sites_dict.get(active_site_tier, {}).get("climate_modifier", 1.0))

func get_unit_effective_cooling_capacity(unit_id: String) -> float:
	var unit: Dictionary = units_dict.get(unit_id, {})
	if unit.get("category", "") != "mechanical":
		return 0.0
	var capacity: float = float(unit.get("cooling_capacity", 0.0))
	if bool(unit.get("climate_dependent", false)):
		capacity *= get_current_site_climate_modifier()
	return capacity

func get_purchase_constraint_warnings(unit_id: String, amount: int) -> Array[String]:
	var warnings: Array[String] = []
	if amount <= 0 or not units_dict.has(unit_id):
		return warnings

	var current_constraints: Dictionary = _calculate_constraint_snapshot(state["unit_counts"])
	var projected_counts: Dictionary = state["unit_counts"].duplicate()
	projected_counts[unit_id] = int(projected_counts.get(unit_id, 0)) + amount
	var projected_constraints: Dictionary = _calculate_constraint_snapshot(projected_counts)

	if float(projected_constraints["power_deficit"]) > float(current_constraints["power_deficit"]) + 0.001:
		warnings.append("POWER")
	if float(projected_constraints["cooling_deficit"]) > float(current_constraints["cooling_deficit"]) + 0.001:
		warnings.append("COOLING")
	return warnings

func _calculate_constraint_snapshot(counts: Dictionary) -> Dictionary:
	var power_loss_reduction: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "power_loss_reduction")
	var mech_power_reduction: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "mech_power_reduction")
	var power_capacity_bonus: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "power_capacity_bonus")
	var cooling_capacity_bonus: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "cooling_capacity_bonus")
	cooling_capacity_bonus += Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "cooling_efficiency_bonus")
	var heat_reduction: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "heat_reduction")

	var operating_counts: Dictionary = counts
	if active_event.get("effect_target", "") == "cooling_unit_offline":
		var offline_unit_id: String = String(active_event.get("offline_unit_id", ""))
		if not offline_unit_id.is_empty() and int(counts.get(offline_unit_id, 0)) > 0:
			operating_counts = counts.duplicate()
			operating_counts[offline_unit_id] = int(counts[offline_unit_id]) - 1

	var projected_it_load: float = Economy.calculate_it_load_kw(counts, units_dict)
	var projected_mech_load: float = Economy.calculate_mech_load_kw(operating_counts, units_dict, mech_power_reduction)
	var projected_total_load: float = Economy.calculate_total_load_kw(projected_it_load, projected_mech_load, power_loss_reduction)
	var projected_heat_load: float = Economy.calculate_heat_load_kwth(counts, units_dict, heat_reduction)

	var site: Dictionary = sites_dict.get(int(state.get("site_tier", 1)), {})
	var climate_modifier: float = float(site.get("climate_modifier", 1.0))
	var projected_power_capacity: float = Economy.calculate_power_capacity(counts, units_dict, power_capacity_bonus)
	var projected_cooling_capacity: float = Economy.calculate_cooling_capacity(operating_counts, units_dict, climate_modifier, cooling_capacity_bonus)

	var event_power_multiplier: float = 1.0
	var event_cooling_multiplier: float = 1.0
	if not active_event.is_empty():
		var event_target: String = String(active_event.get("effect_target", ""))
		var event_multiplier: float = float(active_event.get("effect_multiplier", 1.0))
		if active_event.get("type", "") == "hazard" and event_multiplier < 1.0:
			var event_mitigation: float = Economy.calculate_tech_additive_bonus(state["unlocked_techs"], tech_nodes_dict, "event_mitigation")
			var event_severity: float = 1.0 - event_multiplier
			event_multiplier = 1.0 - (event_severity * (1.0 - clamp(event_mitigation, 0.0, 1.0)))
		if event_target == "power_capacity":
			event_power_multiplier = event_multiplier
		elif event_target == "cooling_capacity":
			event_cooling_multiplier = event_multiplier
	projected_power_capacity *= event_power_multiplier
	projected_cooling_capacity *= event_cooling_multiplier

	return {
		"power_deficit": max(projected_total_load - projected_power_capacity, 0.0),
		"cooling_deficit": max(projected_heat_load - projected_cooling_capacity, 0.0)
	}

func buy_unit(unit_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var unit: Dictionary = units_dict.get(unit_id, {})
	if unit.is_empty():
		return false
	
	var current_count: int = state["unit_counts"].get(unit_id, 0)
	var total_cost: float = Economy.calculate_bulk_unit_cost(
		get_unit_effective_base_cost(unit_id),
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

func unlock_tech_node(tech_id: String) -> bool:
	if tech_id in state["unlocked_techs"]:
		return false
	var node: Dictionary = tech_nodes_dict.get(tech_id, {})
	if node.is_empty():
		return false
	
	var cost_tt: int = int(node.get("cost_tt", 1))
	if state["tech_tokens"] < cost_tt:
		return false
	
	# Prerequisite: ensure previous node in branch is unlocked
	for branch in tech_branches:
		var branch_nodes: Array = branch.get("nodes", [])
		for i in range(branch_nodes.size()):
			if branch_nodes[i].get("id", "") == tech_id:
				if i > 0:
					var prev_id: String = branch_nodes[i - 1].get("id", "")
					if not (prev_id in state["unlocked_techs"]):
						return false # Prerequisite not met
				break
	
	state["tech_tokens"] -= cost_tt
	state["unlocked_techs"].append(tech_id)
	currency_changed.emit(state["cash"], state["tech_tokens"])
	recalculate_all_metrics()
	if SaveManager:
		SaveManager.save_game()
	return true

func unlock_site_tier(tier: int) -> bool:
	var site: Dictionary = sites_dict.get(tier, {})
	if site.is_empty():
		return false
	var unlocked_tiers: Array = state.get("unlocked_site_tiers", [1])
	if tier in unlocked_tiers:
		return select_site_tier(tier)
	if tier > 1 and not ((tier - 1) in unlocked_tiers):
		return false
	var cost_tt: int = int(site.get("unlock_cost_tt", 0))
	if state["tech_tokens"] < cost_tt:
		return false
	state["tech_tokens"] -= cost_tt
	unlocked_tiers.append(tier)
	state["unlocked_site_tiers"] = unlocked_tiers
	state["site_tier"] = tier
	currency_changed.emit(state["cash"], state["tech_tokens"])
	site_changed.emit(tier)
	recalculate_all_metrics()
	if SaveManager:
		SaveManager.save_game()
	return true

func select_site_tier(tier: int) -> bool:
	var unlocked_tiers: Array = state.get("unlocked_site_tiers", [1])
	if not (tier in unlocked_tiers) or not sites_dict.has(tier):
		return false
	state["site_tier"] = tier
	site_changed.emit(tier)
	recalculate_all_metrics()
	if SaveManager:
		SaveManager.save_game()
	return true

func prestige_site_sale(apply_ad_bonus: bool = false, target_tier: int = -1) -> int:
	var lifetime_rev: float = float(state.get("lifetime_revenue_this_site", 0.0))
	if lifetime_rev < get_prestige_revenue_requirement():
		return 0
	
	var tokens: int = calculate_prestige_tokens(lifetime_rev)
	if apply_ad_bonus:
		# +25% TT from rewarded ad (§6.1)
		tokens = int(floor(float(tokens) * 1.25))
	
	state["tech_tokens"] += tokens
	state["prestige_count"] = int(state.get("prestige_count", 0)) + 1
	if target_tier > 0 and target_tier in state.get("unlocked_site_tiers", [1]):
		state["site_tier"] = target_tier
	
	# Reset site per §3 & §5
	state["cash"] = 15.0
	state["job_upgrade_levels"] = {}
	manual_job_charges = get_manual_job_max_charges()
	state["lifetime_revenue_this_site"] = 0.0
	state["unit_counts"] = {
		"rack_1u": 1,
		"blade_chassis": 0,
		"gpu_pod": 0,
		"edge_cluster": 0,
		"ai_superpod": 0,
		"pdu": 1,
		"ups_transformer": 0,
		"diesel_gen": 0,
		"modular_substation": 0,
		"battery_farm": 0,
		"crac_unit": 1,
		"chilled_water_plant": 0,
		"economizer": 0,
		"inrow_cooling": 0,
		"immersion_plant": 0
	}
	thermal_tripped_count = 0
	thermal_alarm_timer = 0.0
	thermal_recovery_timer = 0.0
	active_event.clear()
	active_event_time_remaining = 0.0
	_reset_event_spawn_timer()

	recalculate_all_metrics()
	currency_changed.emit(state["cash"], state["tech_tokens"])
	site_changed.emit(state["site_tier"])
	
	if Analytics:
		Analytics.track_prestige(state["site_tier"], tokens)
	if Ads and try_record_interstitial_impression():
		Ads.show_interstitial("site_sale")
	if SaveManager:
		SaveManager.save_game()
	return tokens

func trigger_random_event(event_id: String = "") -> void:
	var selected: Dictionary = {}
	if not event_id.is_empty() and events_dict.has(event_id):
		selected = events_dict[event_id]
	elif events_data.size() > 0:
		selected = events_data[randi() % events_data.size()]
	
	if selected.is_empty():
		return
	
	active_event = selected.duplicate()
	if active_event.get("effect_target", "") == "cooling_unit_offline":
		active_event["offline_unit_id"] = _select_mechanical_unit_for_outage()
	var duration: float = float(selected.get("duration_sec", 0))
	active_event_time_remaining = duration
	
	# Instant event handling
	var target: String = selected.get("effect_target", "")
	if target == "instant_offline_seconds":
		# Audit passed (+1 hour offline accrual §4.6)
		var bonus_cash: float = revenue_per_sec * 3600.0 * 0.5
		state["cash"] += bonus_cash
		state["lifetime_revenue_this_site"] += bonus_cash
		state["lifetime_revenue_all_time"] += bonus_cash
		currency_changed.emit(state["cash"], state["tech_tokens"])
	
	event_started.emit(active_event)
	recalculate_all_metrics()

func _select_mechanical_unit_for_outage() -> String:
	var selected_id: String = ""
	var highest_capacity: float = -1.0
	for unit_id in state["unit_counts"]:
		if int(state["unit_counts"].get(unit_id, 0)) <= 0:
			continue
		var unit: Dictionary = units_dict.get(unit_id, {})
		if unit.get("category", "") != "mechanical":
			continue
		var capacity: float = float(unit.get("cooling_capacity", 0.0))
		if capacity > highest_capacity:
			highest_capacity = capacity
			selected_id = unit_id
	return selected_id

func resolve_event(with_ad: bool = false, with_cash: bool = false) -> bool:
	if active_event.is_empty():
		return false
	
	if with_cash:
		var ratio: float = float(active_event.get("cash_repair_cost_ratio", 0.0))
		var cost: float = state["cash"] * ratio
		if cost > 0.0 and state["cash"] >= cost:
			state["cash"] -= cost
			currency_changed.emit(state["cash"], state["tech_tokens"])
		else:
			return false
	
	var finished_event := active_event.duplicate()
	active_event.clear()
	active_event_time_remaining = 0.0
	event_ended.emit(finished_event)
	recalculate_all_metrics()
	return true

func process_iap_purchase(sku: String, purchase_verified: bool = false) -> bool:
	# Debug builds act as a billing sandbox. Release builds require a verified
	# purchase callback from the platform billing integration.
	if not OS.is_debug_build() and not purchase_verified:
		push_warning("Rejected unverified purchase: %s" % sku)
		return false
	# IAP Catalog (§6.3)
	if sku == "remove_ads":
		if bool(state.get("remove_ads_owned", false)):
			return false
		state["remove_ads_owned"] = true
		if Analytics:
			Analytics.track_purchase(sku, 2.99)
	elif sku == "starter_pack":
		if bool(state.get("starter_pack_owned", false)):
			return false
		if int(state.get("prestige_count", 0)) < 1:
			return false
		state["starter_pack_owned"] = true
		state["tech_tokens"] += 10
		state["boost_end_time"] = int(Time.get_unix_time_from_system()) + 86400
		_refresh_boost_state()
		currency_changed.emit(state["cash"], state["tech_tokens"])
		if Analytics:
			Analytics.track_purchase(sku, 4.99)
	elif sku == "tt_small":
		state["tech_tokens"] += 15
		currency_changed.emit(state["cash"], state["tech_tokens"])
		if Analytics:
			Analytics.track_purchase(sku, 4.99)
	elif sku == "tt_large":
		state["tech_tokens"] += 75
		currency_changed.emit(state["cash"], state["tech_tokens"])
		if Analytics:
			Analytics.track_purchase(sku, 19.99)
	else:
		return false
	
	recalculate_all_metrics()
	if SaveManager:
		SaveManager.save_game()
	return true
