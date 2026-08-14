extends GutTest

const SimulationScript = preload("res://scripts/systems/Simulation.gd")

var sample_units: Dictionary = {
	"rack_1u": {
		"id": "rack_1u",
		"category": "it",
		"base_cost": 10.0,
		"cost_growth": 1.12,
		"base_compute": 1.0,
		"power_draw": 0.5,
		"heat_coefficient": 1.0
	},
	"blade_chassis": {
		"id": "blade_chassis",
		"category": "it",
		"base_cost": 150.0,
		"cost_growth": 1.12,
		"base_compute": 4.0,
		"power_draw": 1.5,
		"heat_coefficient": 1.0
	},
	"gpu_pod": {
		"id": "gpu_pod",
		"category": "it",
		"base_cost": 2000.0,
		"cost_growth": 1.12,
		"base_compute": 20.0,
		"power_draw": 6.0,
		"heat_coefficient": 2.0
	},
	"pdu": {
		"id": "pdu",
		"category": "electrical",
		"base_cost": 25.0,
		"cost_growth": 1.09,
		"power_capacity": 2.0,
		"uptime_bonus": 0.0
	},
	"ups_transformer": {
		"id": "ups_transformer",
		"category": "electrical",
		"base_cost": 300.0,
		"cost_growth": 1.09,
		"power_capacity": 10.0,
		"uptime_bonus": 0.02
	},
	"crac_unit": {
		"id": "crac_unit",
		"category": "mechanical",
		"base_cost": 40.0,
		"cost_growth": 1.10,
		"cooling_capacity": 2.5,
		"power_draw": 1.0,
		"climate_dependent": false
	},
	"economizer": {
		"id": "economizer",
		"category": "mechanical",
		"base_cost": 6000.0,
		"cost_growth": 1.10,
		"cooling_capacity": 60.0,
		"power_draw": 0.2,
		"climate_dependent": true
	}
}

func before_all() -> void:
	gut.p("Running Economy Unit Tests Suite (M1)...")

func test_unit_cost_formula() -> void:
	var cost_0 := Economy.calculate_unit_cost(10.0, 1.12, 0)
	var cost_1 := Economy.calculate_unit_cost(10.0, 1.12, 1)
	var cost_2 := Economy.calculate_unit_cost(10.0, 1.12, 2)
	assert_almost_eq(cost_0, 10.0, 0.001, "Cost at n=0 should equal base cost")
	assert_almost_eq(cost_1, 11.2, 0.001, "Cost at n=1 should match growth")
	assert_almost_eq(cost_2, 12.544, 0.001, "Cost at n=2 should match growth^2")

func test_bulk_unit_cost() -> void:
	var bulk_2 := Economy.calculate_bulk_unit_cost(10.0, 1.12, 0, 2)
	assert_almost_eq(bulk_2, 21.2, 0.001, "Bulk cost for 2 units from count 0")
	var bulk_0 := Economy.calculate_bulk_unit_cost(10.0, 1.12, 5, 0)
	assert_eq(bulk_0, 0.0, "Bulk cost for 0 units is 0.0")

func test_max_affordable_units() -> void:
	# At count 0, with $21.2 and base 10, growth 1.12 -> exactly 2 units
	var max_units_exact := Economy.calculate_max_affordable_units(10.0, 1.12, 0, 21.2)
	assert_eq(max_units_exact, 2, "Should afford exactly 2 units")
	var max_units_under := Economy.calculate_max_affordable_units(10.0, 1.12, 0, 9.99)
	assert_eq(max_units_under, 0, "Cannot afford 1 unit if cash < cost(0)")

func test_it_load_calculation() -> void:
	var counts := {"rack_1u": 4, "blade_chassis": 2, "gpu_pod": 1}
	# (4 * 0.5) + (2 * 1.5) + (1 * 6.0) = 2.0 + 3.0 + 6.0 = 11.0 kW
	var it_load := Economy.calculate_it_load_kw(counts, sample_units)
	assert_almost_eq(it_load, 11.0, 0.001, "Calculates accurate IT load")

func test_mech_load_and_reduction() -> void:
	var counts := {"crac_unit": 3, "economizer": 2}
	# (3 * 1.0) + (2 * 0.2) = 3.4 kW
	var raw_mech := Economy.calculate_mech_load_kw(counts, sample_units, 0.0)
	assert_almost_eq(raw_mech, 3.4, 0.001, "Raw mechanical load")
	
	# With 15% reduction tech
	var reduced_mech := Economy.calculate_mech_load_kw(counts, sample_units, 0.15)
	assert_almost_eq(reduced_mech, 3.4 * 0.85, 0.001, "Reduced mechanical load")

func test_total_load_and_loss_reduction() -> void:
	var it := 10.0
	var mech := 5.0
	# Base loss ratio is 5% -> total = 15.0 * 1.05 = 15.75 kW
	var total_base := Economy.calculate_total_load_kw(it, mech, 0.0)
	assert_almost_eq(total_base, 15.75, 0.001, "Total load with default 5% distribution losses")
	
	# With 10% loss reduction tech -> loss ratio becomes 5% * 0.9 = 4.5% -> 15 * 1.045 = 15.675
	var total_reduced := Economy.calculate_total_load_kw(it, mech, 0.10)
	assert_almost_eq(total_reduced, 15.675, 0.001, "Total load with reduced transmission losses")

func test_pue_calculation() -> void:
	var pue_normal := Economy.calculate_pue(20.0, 10.0)
	assert_almost_eq(pue_normal, 2.0, 0.001, "PUE should be 2.0")
	var pue_zero_it := Economy.calculate_pue(10.0, 0.0)
	assert_almost_eq(pue_zero_it, 2.0, 0.001, "PUE defaults to 2.0 when IT load is 0")

func test_heat_load_calculation() -> void:
	var counts := {"rack_1u": 2, "gpu_pod": 1} # 2 * (0.5 * 1.0) + 1 * (6.0 * 2.0) = 1.0 + 12.0 = 13.0 kW-th
	var heat_raw := Economy.calculate_heat_load_kwth(counts, sample_units, 0.0)
	assert_almost_eq(heat_raw, 13.0, 0.001, "Heat load raw")
	
	# With 20% immersion heat reduction
	var heat_reduced := Economy.calculate_heat_load_kwth(counts, sample_units, 0.20)
	assert_almost_eq(heat_reduced, 10.4, 0.001, "Heat load with immersion reduction")

func test_power_capacity_calculation() -> void:
	var counts := {"pdu": 5, "ups_transformer": 2} # (5 * 2.0) + (2 * 10.0) = 30.0 kW
	var cap_base := Economy.calculate_power_capacity(counts, sample_units, 0.0)
	assert_almost_eq(cap_base, 30.0, 0.001, "Base power capacity")
	
	# With 15% solar capacity bonus
	var cap_bonus := Economy.calculate_power_capacity(counts, sample_units, 0.15)
	assert_almost_eq(cap_bonus, 34.5, 0.001, "Power capacity with tech bonus")

func test_cooling_capacity_with_climate_modifier() -> void:
	var counts := {"crac_unit": 2, "economizer": 1} # CRAC: 2 * 2.5 = 5.0 kW-th. Economizer: 60 * climate
	# Climate = 0.2 (Rented Closet)
	var cool_closet := Economy.calculate_cooling_capacity(counts, sample_units, 0.2, 0.0)
	assert_almost_eq(cool_closet, 5.0 + (60.0 * 0.2), 0.001, "Cooling in Rented Closet (climate 0.2)")
	
	# Climate = 1.0 (Nordic Campus)
	var cool_nordic := Economy.calculate_cooling_capacity(counts, sample_units, 1.0, 0.0)
	assert_almost_eq(cool_nordic, 5.0 + (60.0 * 1.0), 0.001, "Cooling in Nordic Campus (climate 1.0)")

func test_throttle_calculation() -> void:
	var throttle_under := Economy.calculate_throttle(80.0, 100.0)
	assert_almost_eq(throttle_under, 0.8, 0.001, "Throttle under capacity")
	var throttle_over := Economy.calculate_throttle(120.0, 100.0)
	assert_almost_eq(throttle_over, 1.0, 0.001, "Throttle over capacity clamped to 1.0")

func test_compute_rate_calculation() -> void:
	var counts := {"rack_1u": 10, "blade_chassis": 3, "gpu_pod": 1} # (10 * 1) + (3 * 4) + (1 * 20) = 42
	var compute_base := Economy.calculate_compute_rate(counts, sample_units, 1.0)
	assert_almost_eq(compute_base, 42.0, 0.001, "Base compute rate")
	
	# With 1.5x tech compute multiplier
	var compute_boosted := Economy.calculate_compute_rate(counts, sample_units, 1.5)
	assert_almost_eq(compute_boosted, 63.0, 0.001, "Boosted compute rate")

func test_uptime_calculation() -> void:
	var counts := {"ups_transformer": 2} # 2 * +0.02 = +0.04 -> Base 0.99 + 0.04 = 1.03 -> clamped to 0.99999
	var uptime_healthy := Economy.calculate_uptime(counts, sample_units, 0.0, 0.0)
	assert_almost_eq(uptime_healthy, 0.99999, 0.0001, "Uptime clamped to max 99.999%")
	
	# With 50% thermal trip ratio
	var uptime_tripped := Economy.calculate_uptime(counts, sample_units, 0.0, 0.5)
	# 0.99999 - (0.5 * 0.15) = 0.99999 - 0.075 = ~0.955
	assert_true(uptime_tripped < 0.96 and uptime_tripped > 0.90, "Uptime penalizes tripping racks")

func test_revenue_per_sec_with_all_multipliers() -> void:
	# compute 100, throttle 1.0, contract 1.0, uptime 1.0, site 10.0, tech 1.25, boost 2.0
	var rev := Economy.calculate_revenue_per_sec(100.0, 1.0, 1.0, 1.0, 10.0, 1.25, 2.0)
	# 100 * 1 * 1 * 1 * 10 * 1.25 * 2 = 2500.0
	assert_almost_eq(rev, 2500.0, 0.001, "Revenue formula with all multipliers")

func test_offline_earnings() -> void:
	var rev_sec := 100.0
	var now := 10000
	var last_seen := now - 3600 # 1 hour (3600s) offline
	var result := Economy.calculate_offline_earnings(rev_sec, last_seen, now, false)
	# 3600s * $100/s * 0.5 = $180,000
	assert_almost_eq(float(result["revenue"]), 180000.0, 0.1, "1 hour offline earnings at 50% rate")
	assert_eq(float(result["effective_seconds"]), 3600.0, "Effective seconds should be 3600")

func test_offline_cap() -> void:
	var rev_sec := 10.0
	var now := 20000
	var last_seen := now - 10000 # 10,000s (> 7200s standard cap)
	var result_std := Economy.calculate_offline_earnings(rev_sec, last_seen, now, false)
	assert_eq(float(result_std["effective_seconds"]), 7200.0, "Standard offline cap is 7200s (2h)")
	
	var result_no_ads := Economy.calculate_offline_earnings(rev_sec, last_seen, now, true)
	assert_eq(float(result_no_ads["effective_seconds"]), 10000.0, "Extended cap (14400s) allows full 10000s")

func test_prestige_tokens() -> void:
	assert_eq(Economy.calculate_prestige_tokens(5e8), 0, "Prestige locked below 1e9")
	assert_eq(Economy.calculate_prestige_tokens(1e9), 12, "Prestige at 1e9 yields 12 TT")
	assert_eq(Economy.calculate_prestige_tokens(4e9), 24, "Prestige at 4e9 yields 24 TT")

func test_tech_multipliers_branch_stacking() -> void:
	# Rule: Multiplicative within branch, additive across branches
	var dummy_branches: Array = [
		{
			"id": "branch_a",
			"nodes": [
				{"id": "a1", "effect_type": "revenue_multiplier", "effect_value": 0.10},
				{"id": "a2", "effect_type": "revenue_multiplier", "effect_value": 0.20}
			]
		},
		{
			"id": "branch_b",
			"nodes": [
				{"id": "b1", "effect_type": "revenue_multiplier", "effect_value": 0.30}
			]
		}
	]
	var nodes_dict: Dictionary = {
		"a1": {"id": "a1", "effect_type": "revenue_multiplier", "effect_value": 0.10},
		"a2": {"id": "a2", "effect_type": "revenue_multiplier", "effect_value": 0.20},
		"b1": {"id": "b1", "effect_type": "revenue_multiplier", "effect_value": 0.30}
	}
	
	# Branch A unlocked: (1 + 0.10) * (1 + 0.20) = 1.32 (+32%)
	# Branch B unlocked: (1 + 0.30) = 1.30 (+30%)
	# Combined across branches: 1.0 + 0.32 + 0.30 = 1.62 (+62%)
	var mult := Economy.calculate_tech_multiplier(["a1", "a2", "b1"], nodes_dict, dummy_branches, "revenue_multiplier")
	assert_almost_eq(mult, 1.62, 0.001, "Multiplicative within branch, additive across branches")

func test_2hour_headless_simulation_sanity() -> void:
	var sim_result := SimulationScript.run_simulation(7200, false)
	assert_true(sim_result["sane"], "2-hour simulation produces sane values")
	assert_true(sim_result["lifetime_revenue"] > 1e6, "Lifetime revenue exceeds $1M in 2 hours")
	assert_true(sim_result["pue"] >= 1.0 and sim_result["pue"] <= 2.5, "PUE stays in realistic engineering range")

func test_playable_loop_constraint_triangle_and_save_load() -> void:
	# 1. Reset GameState to known initial state
	GameState.state["cash"] = 1000.0
	GameState.state["unit_counts"] = {
		"rack_1u": 1, "blade_chassis": 0, "gpu_pod": 0,
		"pdu": 1, "ups_transformer": 0, "diesel_gen": 0,
		"crac_unit": 1, "chilled_water_plant": 0, "economizer": 0
	}
	GameState.recalculate_all_metrics()
	
	# Initial: 1 rack (0.5kW), 1 PDU (2.0kW cap), 1 CRAC (2.5kW-th cap, 1.0kW draw)
	# Total load = (0.5 + 1.0) * 1.05 = 1.575 kW <= 2.0 kW -> throttle is 1.0
	assert_almost_eq(GameState.throttle_ratio, 1.0, 0.001, "Initial setup has sufficient power")
	assert_true(GameState.cooling_capacity_kwth >= GameState.heat_load_kwth, "Initial setup has sufficient cooling")
	
	# 2. Buy 6 more 1U racks -> IT load = 3.5 kW, Total load > 4.5 kW > 2.0 kW PDU capacity
	for i in range(6):
		var bought := GameState.buy_unit("rack_1u", 1)
		assert_true(bought, "Successfully bought 1U rack")
	
	# Verify constraint triangle: power throttles!
	assert_true(GameState.throttle_ratio < 1.0, "Power is throttled due to exceeding PDU capacity")
	
	# 3. Buy electrical capacity (PDU) to resolve power throttle
	var bought_pdu := GameState.buy_unit("pdu", 3)
	assert_true(bought_pdu, "Successfully bought PDUs")
	assert_almost_eq(GameState.throttle_ratio, 1.0, 0.001, "Buying PDUs resolves power throttling")
	
	# 4. Verify save and load lifecycle
	SaveManager.save_game()
	var saved_cash: float = float(GameState.state["cash"])
	var saved_racks: int = int(GameState.state["unit_counts"]["rack_1u"])
	
	GameState.state["cash"] = 0.0
	GameState.state["unit_counts"]["rack_1u"] = 0
	SaveManager.load_game()
	
	assert_almost_eq(GameState.state["cash"], saved_cash, 0.001, "Cash restored from save file")
	assert_eq(int(GameState.state["unit_counts"]["rack_1u"]), saved_racks, "Unit counts restored from save file")

func test_tech_tree_progression() -> void:
	GameState.state["tech_tokens"] = 10
	GameState.state["unlocked_techs"] = []
	
	# Node elec_1 costs 1 TT
	var unlocked_1 := GameState.unlock_tech_node("elec_1")
	assert_true(unlocked_1, "Successfully unlocked first node in branch")
	assert_eq(int(GameState.state["tech_tokens"]), 9, "TT deducted")
	assert_true("elec_1" in GameState.state["unlocked_techs"], "elec_1 registered in state")
	
	# Node elec_3 requires elec_2 first (prerequisite check)
	var locked_3 := GameState.unlock_tech_node("elec_3")
	assert_false(locked_3, "Cannot skip prerequisite node elec_2")
	
	# Node elec_2 costs 4 TT
	var unlocked_2 := GameState.unlock_tech_node("elec_2")
	assert_true(unlocked_2, "Successfully unlocked elec_2")
	assert_eq(int(GameState.state["tech_tokens"]), 5, "TT deducted for elec_2")

func test_site_sale_prestige_and_tier_unlock() -> void:
	GameState.state["lifetime_revenue_this_site"] = 4.0e9 # $4B -> 24 TT base
	GameState.state["tech_tokens"] = 10
	
	# Standard prestige
	var tokens_earned := GameState.prestige_site_sale(false, 1)
	assert_eq(tokens_earned, 24, "Earned 24 TT from $4B site sale")
	assert_eq(int(GameState.state["tech_tokens"]), 34, "Tokens added to TT balance")
	assert_almost_eq(GameState.state["lifetime_revenue_this_site"], 0.0, 0.001, "Site lifetime revenue reset")
	assert_eq(int(GameState.state["unit_counts"]["rack_1u"]), 1, "Racks reset to 1")
	
	# Unlock Colo Suite (Tier 2 costs 5 TT)
	var unlocked_tier_2 := GameState.unlock_site_tier(2)
	assert_true(unlocked_tier_2, "Unlocked Tier 2 site")
	assert_eq(int(GameState.state["site_tier"]), 2, "Site tier is now Colo Suite")

func test_random_events_trigger_and_resolve() -> void:
	GameState.state["cash"] = 1000.0
	GameState.trigger_random_event("traffic_spike")
	assert_eq(GameState.active_event.get("id", ""), "traffic_spike", "Triggered Traffic Spike event")
	assert_true(GameState.active_event_time_remaining > 0, "Event countdown active")
	
	# Resolve event
	var resolved := GameState.resolve_event(true, false)
	assert_true(resolved, "Resolved event")
	assert_true(GameState.active_event.is_empty(), "Active event cleared")
