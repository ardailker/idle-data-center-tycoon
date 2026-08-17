extends Node

# Magnitude symbols for numbers > 1e3
const SUFFIXES: Array[String] = [
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td"
]

## Pure economy calculation functions (§5 of GAME_SPEC.md)

static func format_magnitude(value: float) -> String:
	if is_nan(value) or is_inf(value):
		return "0.00"
	if value < 0.0:
		return "-" + format_magnitude(-value)
	if value < 1000.0:
		return "%.2f" % value
	
	var exp_index: int = int(floor(log(value) / log(1000.0)))
	if exp_index >= SUFFIXES.size():
		return "%.2e" % value
	
	var scaled: float = value / pow(1000.0, exp_index)
	return "%.2f %s" % [scaled, SUFFIXES[exp_index]]


static func calculate_unit_cost(base_cost: float, cost_growth: float, count: int) -> float:
	# cost(n) = base_cost * pow(cost_growth, n)
	return base_cost * pow(cost_growth, float(count))


static func calculate_bulk_unit_cost(base_cost: float, cost_growth: float, current_count: int, buy_amount: int) -> float:
	if buy_amount <= 0:
		return 0.0
	if is_equal_approx(cost_growth, 1.0):
		return base_cost * float(buy_amount)
	# Sum of geometric series: base_cost * cost_growth^current_count * (cost_growth^buy_amount - 1) / (cost_growth - 1)
	var first_term: float = calculate_unit_cost(base_cost, cost_growth, current_count)
	return first_term * (pow(cost_growth, float(buy_amount)) - 1.0) / (cost_growth - 1.0)


static func calculate_max_affordable_units(base_cost: float, cost_growth: float, current_count: int, available_cash: float) -> int:
	if available_cash <= 0.0:
		return 0
	var first_term: float = calculate_unit_cost(base_cost, cost_growth, current_count)
	if available_cash < first_term:
		return 0
	if is_equal_approx(cost_growth, 1.0):
		return int(floor(available_cash / base_cost))
	var factor: float = 1.0 + (available_cash * (cost_growth - 1.0) / first_term)
	if factor <= 0.0:
		return 0
	var count_est: int = int(floor((log(factor) / log(cost_growth)) + 0.0000001))
	while calculate_bulk_unit_cost(base_cost, cost_growth, current_count, count_est + 1) <= available_cash:
		count_est += 1
	while count_est > 0 and calculate_bulk_unit_cost(base_cost, cost_growth, current_count, count_est) > available_cash:
		count_est -= 1
	return count_est


static func calculate_it_load_kw(unit_counts: Dictionary, units_dict: Dictionary) -> float:
	var total: float = 0.0
	for unit_id in unit_counts:
		var count: int = unit_counts[unit_id]
		if count <= 0:
			continue
		var unit: Dictionary = units_dict.get(unit_id, {})
		if unit.get("category", "") == "it":
			total += float(unit.get("power_draw", 0.0)) * float(count)
	return total


static func calculate_mech_load_kw(unit_counts: Dictionary, units_dict: Dictionary, mech_power_reduction: float = 0.0) -> float:
	var total: float = 0.0
	for unit_id in unit_counts:
		var count: int = unit_counts[unit_id]
		if count <= 0:
			continue
		var unit: Dictionary = units_dict.get(unit_id, {})
		if unit.get("category", "") == "mechanical":
			total += float(unit.get("power_draw", 0.0)) * float(count)
	var reduction: float = clamp(mech_power_reduction, 0.0, 0.9)
	return total * (1.0 - reduction)


static func calculate_total_load_kw(it_load_kw: float, mech_load_kw: float, loss_reduction: float = 0.0) -> float:
	# Base electrical transmission / transformer loss ~5%
	var base_loss_ratio: float = 0.05 * (1.0 - clamp(loss_reduction, 0.0, 1.0))
	var base_load: float = it_load_kw + mech_load_kw
	return base_load + (base_load * base_loss_ratio)


static func calculate_pue(total_load_kw: float, it_load_kw: float) -> float:
	if it_load_kw <= 0.001:
		return 2.0 # Default starting baseline PUE
	return total_load_kw / it_load_kw


static func calculate_heat_load_kwth(unit_counts: Dictionary, units_dict: Dictionary, heat_reduction: float = 0.0) -> float:
	var total_heat: float = 0.0
	for unit_id in unit_counts:
		var count: int = unit_counts[unit_id]
		if count <= 0:
			continue
		var unit: Dictionary = units_dict.get(unit_id, {})
		if unit.get("category", "") == "it":
			var power: float = float(unit.get("power_draw", 0.0))
			var heat_coeff: float = float(unit.get("heat_coefficient", 1.0))
			total_heat += power * heat_coeff * float(count)
	var reduction: float = clamp(heat_reduction, 0.0, 0.9)
	return total_heat * (1.0 - reduction)


static func calculate_power_capacity(unit_counts: Dictionary, units_dict: Dictionary, power_capacity_bonus: float = 0.0) -> float:
	var capacity: float = 0.0
	for unit_id in unit_counts:
		var count: int = unit_counts[unit_id]
		if count <= 0:
			continue
		var unit: Dictionary = units_dict.get(unit_id, {})
		if unit.get("category", "") == "electrical":
			capacity += float(unit.get("power_capacity", 0.0)) * float(count)
	return capacity * (1.0 + max(power_capacity_bonus, 0.0))


static func calculate_cooling_capacity(unit_counts: Dictionary, units_dict: Dictionary, climate_modifier: float = 1.0, cooling_bonus: float = 0.0) -> float:
	var capacity: float = 0.0
	for unit_id in unit_counts:
		var count: int = unit_counts[unit_id]
		if count <= 0:
			continue
		var unit: Dictionary = units_dict.get(unit_id, {})
		if unit.get("category", "") == "mechanical":
			var base_cap: float = float(unit.get("cooling_capacity", 0.0))
			if unit.get("climate_dependent", false):
				base_cap *= climate_modifier
			capacity += base_cap * float(count)
	return capacity * (1.0 + max(cooling_bonus, 0.0))


static func calculate_throttle(power_capacity: float, total_load_kw: float) -> float:
	if total_load_kw <= 0.001:
		return 1.0
	return clamp(power_capacity / total_load_kw, 0.0, 1.0)


static func calculate_compute_rate(unit_counts: Dictionary, units_dict: Dictionary, tech_compute_mult: float = 1.0) -> float:
	var base_compute: float = 0.0
	for unit_id in unit_counts:
		var count: int = unit_counts[unit_id]
		if count <= 0:
			continue
		var unit: Dictionary = units_dict.get(unit_id, {})
		if unit.get("category", "") == "it":
			base_compute += float(unit.get("base_compute", 0.0)) * float(count)
	return base_compute * max(tech_compute_mult, 0.0)


static func calculate_uptime_details(
	unit_counts: Dictionary,
	units_dict: Dictionary,
	tech_uptime_bonus: float = 0.0,
	trip_ratio: float = 0.0,
	power_throttle: float = 1.0,
	cooling_capacity_ratio: float = 1.0
) -> Dictionary:
	var reliability_bonus: float = 0.0
	for unit_id in unit_counts:
		var count: int = unit_counts[unit_id]
		if count <= 0:
			continue
		var unit: Dictionary = units_dict.get(unit_id, {})
		if unit.get("category", "") == "electrical":
			reliability_bonus += float(unit.get("uptime_bonus", 0.0)) * float(count)
	reliability_bonus = clamp(reliability_bonus + tech_uptime_bonus, 0.0, 0.00999)
	var power_penalty: float = (1.0 - clamp(power_throttle, 0.0, 1.0)) * 0.10
	var cooling_penalty: float = (1.0 - clamp(cooling_capacity_ratio, 0.0, 1.0)) * 0.08
	var trip_penalty: float = clamp(trip_ratio, 0.0, 1.0) * 0.15
	return {
		"uptime": clamp(0.99 + reliability_bonus - power_penalty - cooling_penalty - trip_penalty, 0.50, 0.99999),
		"reliability_bonus": reliability_bonus,
		"power_penalty": power_penalty,
		"cooling_penalty": cooling_penalty,
		"trip_penalty": trip_penalty
	}


static func calculate_uptime(
	unit_counts: Dictionary,
	units_dict: Dictionary,
	tech_uptime_bonus: float = 0.0,
	trip_ratio: float = 0.0,
	power_throttle: float = 1.0,
	cooling_capacity_ratio: float = 1.0
) -> float:
	return float(calculate_uptime_details(
		unit_counts,
		units_dict,
		tech_uptime_bonus,
		trip_ratio,
		power_throttle,
		cooling_capacity_ratio
	)["uptime"])


static func calculate_fuel_cost_per_sec(unit_counts: Dictionary, units_dict: Dictionary) -> float:
	var total: float = 0.0
	for unit_id in unit_counts:
		var count: int = int(unit_counts[unit_id])
		if count <= 0:
			continue
		var unit: Dictionary = units_dict.get(unit_id, {})
		if unit.get("category", "") == "electrical":
			total += float(unit.get("fuel_cost_per_sec", 0.0)) * float(count)
	return total


static func calculate_revenue_per_sec(
	compute_rate: float,
	throttle: float,
	contract_rate: float,
	uptime_mult: float,
	site_mult: float,
	tech_revenue_mult: float = 1.0,
	boost_mult: float = 1.0
) -> float:
	# revenue_per_sec = compute_rate * throttle * contract_rate * uptime_mult * site_mult
	return compute_rate * throttle * contract_rate * uptime_mult * site_mult * tech_revenue_mult * boost_mult


static func calculate_manual_job_reward(revenue_per_sec: float, reward_seconds: float = 0.25) -> float:
	return max(revenue_per_sec * max(reward_seconds, 0.0), 1.0)


static func calculate_offline_efficiency(pue: float, uptime: float) -> Dictionary:
	var pue_score: float = clamp((2.0 - pue) / 1.0, 0.0, 1.0)
	var uptime_score: float = clamp((uptime - 0.99) / 0.00999, 0.0, 1.0)
	var pue_bonus: float = pue_score * 0.25
	var uptime_bonus: float = uptime_score * 0.15
	return {
		"rate": clamp(0.50 + pue_bonus + uptime_bonus, 0.50, 0.90),
		"pue_bonus": pue_bonus,
		"uptime_bonus": uptime_bonus
	}


static func calculate_offline_earnings(
	revenue_per_sec: float,
	last_seen: int,
	now: int,
	remove_ads_owned: bool = false,
	pue: float = 2.0,
	uptime: float = 0.99
) -> Dictionary:
	var elapsed_seconds: float = float(max(now - last_seen, 0))
	var offline_cap: float = 7200.0 # 2 hours default
	if remove_ads_owned:
		offline_cap += 7200.0 # 4 hours total
	
	var effective_seconds: float = clamp(elapsed_seconds, 0.0, offline_cap)
	var efficiency: Dictionary = calculate_offline_efficiency(pue, uptime)
	var offline_rate: float = float(efficiency["rate"])
	var base_revenue: float = revenue_per_sec * effective_seconds * offline_rate
	return {
		"elapsed_seconds": elapsed_seconds,
		"effective_seconds": effective_seconds,
		"offline_cap": offline_cap,
		"revenue": base_revenue,
		"offline_rate": offline_rate,
		"pue_bonus": efficiency["pue_bonus"],
		"uptime_bonus": efficiency["uptime_bonus"],
		"pue": pue,
		"uptime": uptime
	}


static func calculate_prestige_tokens(
	lifetime_revenue_this_site: float,
	revenue_requirement: float,
	base_tokens: int
) -> int:
	if revenue_requirement <= 0.0 or lifetime_revenue_this_site < revenue_requirement:
		return 0
	return int(floor(float(base_tokens) * sqrt(lifetime_revenue_this_site / revenue_requirement)))


static func calculate_tech_multiplier(
	unlocked_tech_ids: Array,
	tech_nodes_dict: Dictionary,
	tech_branches: Array,
	effect_type: String
) -> float:
	# §5: "Tech multipliers stack multiplicatively within a branch, additively across branches"
	var total_cross_branch_bonus: float = 0.0
	for branch in tech_branches:
		var branch_nodes: Array = branch.get("nodes", [])
		var branch_mult: float = 1.0
		var branch_has_effect: bool = false
		for node in branch_nodes:
			var node_id: String = node.get("id", "")
			if node_id in unlocked_tech_ids and node.get("effect_type", "") == effect_type:
				var val: float = float(node.get("effect_value", 0.0))
				branch_mult *= (1.0 + val)
				branch_has_effect = true
		if branch_has_effect:
			total_cross_branch_bonus += (branch_mult - 1.0)
	return 1.0 + total_cross_branch_bonus


static func calculate_tech_additive_bonus(
	unlocked_tech_ids: Array,
	tech_nodes_dict: Dictionary,
	effect_type: String
) -> float:
	var total: float = 0.0
	for tech_id in unlocked_tech_ids:
		var node: Dictionary = tech_nodes_dict.get(tech_id, {})
		if node.get("effect_type", "") == effect_type:
			total += float(node.get("effect_value", 0.0))
	return total
