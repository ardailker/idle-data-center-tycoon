extends SceneTree

const Economy = preload("res://scripts/autoload/Economy.gd")

# Headless 2-Hour Gameplay Balance Simulation (§10 M1 Deliverable)

func _init() -> void:
	print("==================================================")
	print("STARTING HEADLESS 2-HOUR GAMEPLAY SIMULATION (M1)")
	print("==================================================")
	
	var sim_result := run_simulation(7200) # 7200 seconds = 2 hours
	
	print("\n==================================================")
	print("SIMULATION COMPLETED IN %d SIMULATED SECONDS" % sim_result["total_seconds"])
	print("Lifetime Revenue: $%s (Raw: %.0f)" % [Economy.format_magnitude(sim_result["lifetime_revenue"]), sim_result["lifetime_revenue"]])
	print("Final Revenue Rate: $%s/s" % Economy.format_magnitude(sim_result["revenue_per_sec"]))
	print("Final PUE: %.3f" % sim_result["pue"])
	print("Time to $1B (First Prestige Target): %s" % (
		"%d mins (%d sec)" % [sim_result["time_to_prestige_sec"] / 60, sim_result["time_to_prestige_sec"]]
		if sim_result["time_to_prestige_sec"] > 0
		else "Not reached within 2h"
	))
	print("Prestige Tokens Available: %d TT" % sim_result["prestige_tokens"])
	print("Unit Counts: %s" % JSON.stringify(sim_result["unit_counts"]))
	print("==================================================")
	
	quit(0 if sim_result["sane"] else 1)

static func run_simulation(duration_seconds: int = 7200, log_checkpoints: bool = true) -> Dictionary:
	# Load catalog data
	var units_dict: Dictionary = _load_catalog("res://data/units.json").get("units_dict", {})
	var sites_dict: Dictionary = _load_catalog("res://data/sites.json").get("sites_dict", {})
	
	# Initial State
	var cash: float = 15.0
	var lifetime_revenue: float = 0.0
	var site_tier: int = 1
	var unit_counts: Dictionary = {
		"rack_1u": 1,
		"blade_chassis": 0,
		"gpu_pod": 0,
		"pdu": 1,
		"ups_transformer": 0,
		"diesel_gen": 0,
		"crac_unit": 1,
		"chilled_water_plant": 0,
		"economizer": 0
	}
	
	var time_to_prestige_sec: int = -1
	var climate_mod: float = float(sites_dict.get(site_tier, {}).get("climate_modifier", 0.2))
	var site_contract_mult: float = float(sites_dict.get(site_tier, {}).get("contract_multiplier", 1.0))
	
	var current_rev_sec: float = 0.0
	var current_pue: float = 2.0
	var checkpoint_interval: int = 900 # every 15 minutes
	
	for sec in range(1, duration_seconds + 1):
		# 1. Calculate current metrics
		var it_load: float = Economy.calculate_it_load_kw(unit_counts, units_dict)
		var mech_load: float = Economy.calculate_mech_load_kw(unit_counts, units_dict)
		var total_load: float = Economy.calculate_total_load_kw(it_load, mech_load)
		current_pue = Economy.calculate_pue(total_load, it_load)
		var heat_load: float = Economy.calculate_heat_load_kwth(unit_counts, units_dict)
		
		var power_cap: float = Economy.calculate_power_capacity(unit_counts, units_dict)
		var cooling_cap: float = Economy.calculate_cooling_capacity(unit_counts, units_dict, climate_mod)
		
		var throttle: float = Economy.calculate_throttle(power_cap, total_load)
		var compute: float = Economy.calculate_compute_rate(unit_counts, units_dict)
		var uptime: float = Economy.calculate_uptime(unit_counts, units_dict)
		
		current_rev_sec = Economy.calculate_revenue_per_sec(
			compute,
			throttle,
			1.0, # base contract
			uptime,
			site_contract_mult
		)
		
		# 2. Earn revenue for this second
		cash += current_rev_sec
		lifetime_revenue += current_rev_sec
		
		if time_to_prestige_sec == -1 and lifetime_revenue >= 1.0e9:
			time_to_prestige_sec = sec
		
		# 3. Intelligent player purchase strategy
		# Reinvest accumulating cash into capacity and IT
		var max_purchases_per_step: int = 20
		while max_purchases_per_step > 0 and cash > 10.0:
			var power_headroom: float = power_cap - total_load
			var cooling_headroom: float = cooling_cap - heat_load
			var bought_something: bool = false
			
			if power_headroom < 5.0 or throttle < 0.99:
				bought_something = _try_buy_best_unit(cash, unit_counts, units_dict, ["diesel_gen", "ups_transformer", "pdu"], func(cost):
					cash -= cost
				)
			elif cooling_headroom < 5.0:
				bought_something = _try_buy_best_unit(cash, unit_counts, units_dict, ["economizer", "chilled_water_plant", "crac_unit"], func(cost):
					cash -= cost
				)
			else:
				bought_something = _try_buy_best_unit(cash, unit_counts, units_dict, ["gpu_pod", "blade_chassis", "rack_1u"], func(cost):
					cash -= cost
				)
			
			if not bought_something:
				break
			
			# Recalculate dynamic loads after purchase
			it_load = Economy.calculate_it_load_kw(unit_counts, units_dict)
			mech_load = Economy.calculate_mech_load_kw(unit_counts, units_dict)
			total_load = Economy.calculate_total_load_kw(it_load, mech_load)
			heat_load = Economy.calculate_heat_load_kwth(unit_counts, units_dict)
			power_cap = Economy.calculate_power_capacity(unit_counts, units_dict)
			cooling_cap = Economy.calculate_cooling_capacity(unit_counts, units_dict, climate_mod)
			throttle = Economy.calculate_throttle(power_cap, total_load)
			compute = Economy.calculate_compute_rate(unit_counts, units_dict)
			uptime = Economy.calculate_uptime(unit_counts, units_dict)
			current_rev_sec = Economy.calculate_revenue_per_sec(compute, throttle, 1.0, uptime, site_contract_mult)
			max_purchases_per_step -= 1
		
		# 4. Checkpoint logging
		if log_checkpoints and (sec % checkpoint_interval == 0 or sec == duration_seconds):
			var mins: int = sec / 60
			print("[%3d min] Cash: $%8s | Rev/s: $%8s | PUE: %.2f | IT: %5.1f kW | Pwr: %5.1f kW | Cool: %5.1f kW | Lifetime: $%s" % [
				mins,
				Economy.format_magnitude(cash),
				Economy.format_magnitude(current_rev_sec),
				current_pue,
				it_load,
				power_cap,
				cooling_cap,
				Economy.format_magnitude(lifetime_revenue)
			])
	
	var sane: bool = not is_nan(cash) and not is_inf(cash) and cash >= 0.0 and current_pue >= 1.0 and current_pue <= 3.0
	var prestige_tokens: int = Economy.calculate_prestige_tokens(lifetime_revenue)
	
	return {
		"total_seconds": duration_seconds,
		"cash": cash,
		"lifetime_revenue": lifetime_revenue,
		"revenue_per_sec": current_rev_sec,
		"pue": current_pue,
		"time_to_prestige_sec": time_to_prestige_sec,
		"prestige_tokens": prestige_tokens,
		"unit_counts": unit_counts,
		"sane": sane
	}

static func _try_buy_best_unit(
	current_cash: float,
	unit_counts: Dictionary,
	units_dict: Dictionary,
	candidate_ids: Array,
	on_buy: Callable
) -> bool:
	for unit_id in candidate_ids:
		var u: Dictionary = units_dict.get(unit_id, {})
		if u.is_empty():
			continue
		var count: int = unit_counts.get(unit_id, 0)
		var growth: float = float(u.get("cost_growth", 1.12))
		var cost: float = Economy.calculate_unit_cost(float(u.get("base_cost", 10.0)), growth, count)
		if current_cash >= cost:
			unit_counts[unit_id] = count + 1
			on_buy.call(cost)
			return true
	return false

static func _load_catalog(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		var result_dict: Dictionary = {}
		for key in json.data:
			var arr = json.data[key]
			if arr is Array:
				for item in arr:
					if item is Dictionary and item.has("id"):
						result_dict[item["id"]] = item
					elif item is Dictionary and item.has("tier"):
						result_dict[item["tier"]] = item
		return {"data": json.data, "units_dict": result_dict, "sites_dict": result_dict}
	return {}
