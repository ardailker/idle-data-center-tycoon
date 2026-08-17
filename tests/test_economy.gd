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
		"uptime_bonus": 0.00025
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
	SaveManager.save_path = "user://test_savegame.json"
	_remove_test_save_files()
	gut.p("Running Economy Unit Tests Suite (M1)...")

func after_all() -> void:
	_remove_test_save_files()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH

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
	var counts := {"ups_transformer": 2}
	var uptime_healthy := Economy.calculate_uptime(counts, sample_units, 0.0, 0.0)
	assert_almost_eq(uptime_healthy, 0.9905, 0.0001, "Redundant equipment provides a measured uptime improvement")

	var uptime_power_limited := Economy.calculate_uptime(counts, sample_units, 0.0, 0.0, 0.8, 1.0)
	assert_almost_eq(uptime_power_limited, 0.9705, 0.0001, "A 20% power deficit removes 2 percentage points of uptime")

	var uptime_cooling_limited := Economy.calculate_uptime(counts, sample_units, 0.0, 0.0, 1.0, 0.75)
	assert_almost_eq(uptime_cooling_limited, 0.9705, 0.0001, "A 25% cooling deficit removes 2 percentage points of uptime")
	
	# With 50% thermal trip ratio
	var uptime_tripped := Economy.calculate_uptime(counts, sample_units, 0.0, 0.5)
	assert_almost_eq(uptime_tripped, 0.9155, 0.0001, "Thermal trips apply the strongest uptime penalty")

	var capped_reliability := Economy.calculate_uptime({"ups_transformer": 100}, sample_units)
	assert_almost_eq(capped_reliability, 0.99999, 0.00001, "Reliability improvements remain capped at 99.999%")

func test_revenue_per_sec_with_all_multipliers() -> void:
	# compute 100, throttle 1.0, contract 1.0, uptime 1.0, site 10.0, tech 1.25, boost 2.0
	var rev := Economy.calculate_revenue_per_sec(100.0, 1.0, 1.0, 1.0, 10.0, 1.25, 2.0)
	# 100 * 1 * 1 * 1 * 10 * 1.25 * 2 = 2500.0
	assert_almost_eq(rev, 2500.0, 0.001, "Revenue formula with all multipliers")
	assert_almost_eq(Economy.calculate_manual_job_reward(100.0), 25.0, 0.001, "RUN JOB earns one quarter-second of current revenue")
	assert_almost_eq(Economy.calculate_manual_job_reward(0.0), 1.0, 0.001, "RUN JOB always earns at least one dollar")

func test_offline_earnings() -> void:
	var rev_sec := 100.0
	var now := 10000
	var last_seen := now - 3600 # 1 hour (3600s) offline
	var result := Economy.calculate_offline_earnings(rev_sec, last_seen, now, false)
	# 3600s * $100/s * 0.5 = $180,000
	assert_almost_eq(float(result["revenue"]), 180000.0, 0.1, "1 hour offline earnings at 50% rate")
	assert_eq(float(result["effective_seconds"]), 3600.0, "Effective seconds should be 3600")

func test_pue_and_uptime_improve_offline_earnings() -> void:
	var efficient := Economy.calculate_offline_earnings(100.0, 0, 3600, false, 1.0, 0.99999)
	assert_almost_eq(float(efficient["offline_rate"]), 0.90, 0.001, "Excellent PUE and uptime reach the 90% offline cap")
	assert_almost_eq(float(efficient["pue_bonus"]), 0.25, 0.001, "PUE contributes up to 25%")
	assert_almost_eq(float(efficient["uptime_bonus"]), 0.15, 0.001, "Uptime contributes up to 15%")
	assert_almost_eq(float(efficient["revenue"]), 324000.0, 0.1, "Engineering efficiency increases offline revenue")

func test_offline_cap() -> void:
	var rev_sec := 10.0
	var now := 20000
	var last_seen := now - 10000 # 10,000s (> 7200s standard cap)
	var result_std := Economy.calculate_offline_earnings(rev_sec, last_seen, now, false)
	assert_eq(float(result_std["effective_seconds"]), 7200.0, "Standard offline cap is 7200s (2h)")
	
	var result_no_ads := Economy.calculate_offline_earnings(rev_sec, last_seen, now, true)
	assert_eq(float(result_no_ads["effective_seconds"]), 10000.0, "Extended cap (14400s) allows full 10000s")

func test_prestige_tokens() -> void:
	assert_eq(Economy.calculate_prestige_tokens(4e6, 5e6, 30), 0, "Prestige locked below the configured requirement")
	assert_eq(Economy.calculate_prestige_tokens(5e6, 5e6, 30), 30, "Prestige at the requirement yields base TT")
	assert_eq(Economy.calculate_prestige_tokens(20e6, 5e6, 30), 60, "Four times the requirement yields twice the TT")

func test_diesel_fuel_cost() -> void:
	var counts := {"diesel_gen": 3}
	var units := {
		"diesel_gen": {"category": "electrical", "fuel_cost_per_sec": 0.5}
	}
	assert_almost_eq(Economy.calculate_fuel_cost_per_sec(counts, units), 1.5, 0.001, "Diesel fuel cost is charged per generator")

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

func test_first_prestige_reachable_in_target_window() -> void:
	var sim_result := SimulationScript.run_simulation(1800, false)
	assert_true(sim_result["sane"], "30-minute simulation produces sane values")
	assert_true(sim_result["time_to_prestige_sec"] >= 1200, "First prestige does not arrive before 20 minutes")
	assert_true(sim_result["time_to_prestige_sec"] <= 1800, "First prestige arrives by 30 minutes")
	assert_true(sim_result["pue"] >= 1.0 and sim_result["pue"] <= 2.5, "PUE stays in realistic engineering range")

func test_first_site_sale_makes_next_facility_run_faster() -> void:
	var first_run := SimulationScript.run_simulation(1800, false)
	var second_run := SimulationScript.run_simulation(1800, false, {
		"site_tier": 2,
		"compute_multiplier": 1.265,
		"facility_discounts": {"it": 0.30}
	})
	assert_true(second_run["time_to_prestige_sec"] > 0, "Post-prestige run reaches another Site Sale")
	assert_true(second_run["time_to_prestige_sec"] < first_run["time_to_prestige_sec"], "Site and research choices make the next run faster")

func test_very_active_manual_jobs_reach_prestige_in_10_to_15_minutes() -> void:
	var active_run := SimulationScript.run_simulation(900, false, {"manual_income_multiplier": 2.0})
	assert_true(active_run["time_to_prestige_sec"] >= 600, "RUN JOB does not reduce first prestige below 10 minutes")
	assert_true(active_run["time_to_prestige_sec"] <= 900, "Very active RUN JOB play reaches first prestige within 15 minutes")

func test_manual_job_charges_and_revenue() -> void:
	GameState.state["job_upgrade_levels"] = {}
	GameState.state["cash"] = 0.0
	GameState.state["lifetime_revenue_this_site"] = 0.0
	GameState.state["lifetime_revenue_all_time"] = 0.0
	GameState.revenue_per_sec = 100.0
	GameState.manual_job_charges = GameState.MANUAL_JOB_MAX_CHARGES
	assert_almost_eq(GameState.claim_manual_job(), 25.0, 0.001, "RUN JOB awards current revenue-based cash")
	assert_almost_eq(float(GameState.state["cash"]), 25.0, 0.001, "RUN JOB adds cash")
	assert_almost_eq(float(GameState.state["lifetime_revenue_this_site"]), 25.0, 0.001, "RUN JOB advances Site Sale revenue")
	for i in range(4):
		assert_true(GameState.claim_manual_job() > 0.0, "Remaining RUN JOB charge can be spent")
	assert_almost_eq(GameState.claim_manual_job(), 0.0, 0.001, "RUN JOB is rate-limited when charges are empty")
	GameState.recharge_manual_jobs(0.25)
	assert_almost_eq(GameState.claim_manual_job(), 25.0, 0.001, "One charge regenerates in a quarter second")

func test_manual_job_upgrades_change_value_queue_and_recharge() -> void:
	GameState.state["job_upgrade_levels"] = {}
	GameState.state["cash"] = 100000.0
	GameState.revenue_per_sec = 100.0
	GameState.manual_job_charges = GameState.get_manual_job_max_charges()

	assert_almost_eq(GameState.get_manual_job_upgrade_cost("contract_optimizer"), 250.0, 0.001, "First job-value upgrade uses balanced cash cost")
	assert_true(GameState.purchase_manual_job_upgrade("contract_optimizer"), "Job-value upgrade can be purchased")
	assert_eq(GameState.get_manual_job_upgrade_level("contract_optimizer"), 1, "Job-value level persists in state")
	assert_almost_eq(GameState.claim_manual_job(), 26.25, 0.001, "Job-value upgrade raises the click reward by 5%")
	assert_almost_eq(GameState.get_manual_job_upgrade_cost("contract_optimizer"), 1750.0, 0.001, "Next upgrade cost follows configured growth")

	GameState.manual_job_charges = 5.0
	assert_true(GameState.purchase_manual_job_upgrade("queue_expansion"), "Queue upgrade can be purchased")
	assert_almost_eq(GameState.get_manual_job_max_charges(), 7.0, 0.001, "Queue upgrade adds two stored jobs")
	assert_almost_eq(GameState.manual_job_charges, 7.0, 0.001, "New queue slots arrive charged")

	assert_true(GameState.purchase_manual_job_upgrade("dispatch_firmware"), "Recharge upgrade can be purchased")
	assert_almost_eq(GameState.get_manual_job_regen_per_second(), 4.2, 0.001, "Recharge upgrade raises jobs per second by 5%")
	GameState.manual_job_charges = 0.0
	GameState.recharge_manual_jobs(0.25)
	assert_almost_eq(GameState.manual_job_charges, 1.05, 0.001, "Dynamic recharge speed is applied")

	GameState.state["job_upgrade_levels"] = {}
	GameState.manual_job_charges = GameState.get_manual_job_max_charges()

func test_max_job_upgrades_preserve_active_pacing_floor() -> void:
	GameState.state["job_upgrade_levels"] = {
		"contract_optimizer": 5,
		"dispatch_firmware": 4
	}
	var maximum_active_multiplier: float = 1.0 + (
		GameState.get_manual_job_reward_seconds() * GameState.get_manual_job_regen_per_second()
	)
	assert_almost_eq(maximum_active_multiplier, 2.5, 0.001, "Fully upgraded sustained clicking is capped at 2.5x total income")
	var max_active_run := SimulationScript.run_simulation(900, false, {"manual_income_multiplier": maximum_active_multiplier})
	assert_true(max_active_run["time_to_prestige_sec"] >= 600, "Maximum clicking upgrades keep first Site Sale at ten minutes or longer")
	GameState.state["job_upgrade_levels"] = {}

func test_purchase_constraint_warnings_are_projected_before_buying() -> void:
	GameState.state["site_tier"] = 1
	GameState.state["unlocked_techs"] = []
	GameState.active_event.clear()
	GameState.state["unit_counts"] = {
		"rack_1u": 1,
		"pdu": 1,
		"crac_unit": 1
	}
	var safe_capacity_purchase := GameState.get_purchase_constraint_warnings("pdu", 1)
	assert_true(safe_capacity_purchase.is_empty(), "Capacity purchase is not falsely marked as risky")

	var power_warning := GameState.get_purchase_constraint_warnings("rack_1u", 1)
	assert_true("POWER" in power_warning, "Purchase warns when projected load exceeds power capacity")
	assert_false("COOLING" in power_warning, "Cooling is not warned while projected heat still fits")

	var combined_warning := GameState.get_purchase_constraint_warnings("rack_1u", 5)
	assert_true("POWER" in combined_warning, "Bulk purchase warns about power")
	assert_true("COOLING" in combined_warning, "Bulk purchase warns about cooling")

	GameState.state["unit_counts"] = {
		"gpu_pod": 2,
		"pdu": 20,
		"crac_unit": 1,
		"chilled_water_plant": 0
	}
	var helpful_cooling_purchase := GameState.get_purchase_constraint_warnings("chilled_water_plant", 1)
	assert_false("COOLING" in helpful_cooling_purchase, "Cooling purchase is not warned when it reduces an existing deficit")
	var worsening_it_purchase := GameState.get_purchase_constraint_warnings("rack_1u", 1)
	assert_true("COOLING" in worsening_it_purchase, "IT purchase still warns when it worsens an existing cooling deficit")

func test_float_site_tier_from_json_uses_catalog_climate() -> void:
	GameState.state["site_tier"] = 1.0
	GameState.state["unlocked_techs"] = []
	GameState.active_event.clear()
	GameState.state["unit_counts"] = {"economizer": 1}
	GameState.recalculate_all_metrics()
	assert_almost_eq(GameState.cooling_capacity_kwth, 12.0, 0.001, "Float tier 1 still applies the 20% Rented Closet climate modifier")
	assert_almost_eq(GameState.get_unit_effective_cooling_capacity("economizer"), 12.0, 0.001, "Facility card reports effective Economizer capacity")
	GameState.state["site_tier"] = 2
	assert_almost_eq(GameState.get_unit_effective_cooling_capacity("economizer"), 24.0, 0.001, "Effective capacity updates for the active site's climate")

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
	assert_almost_eq(GameState.get_facility_cost_discount("electrical"), 0.30, 0.001, "First two electrical upgrades reduce equipment costs by 30%")
	assert_almost_eq(GameState.get_unit_effective_base_cost("pdu"), 17.5, 0.001, "Facility shop uses the researched discount")

func test_expanded_facility_catalog_is_soft_gated() -> void:
	var category_counts := {"it": 0, "electrical": 0, "mechanical": 0}
	for unit in GameState.units_data:
		var category: String = String(unit.get("category", ""))
		if category_counts.has(category):
			category_counts[category] += 1
	assert_eq(int(category_counts["it"]), 5, "IT has five equipment tiers")
	assert_eq(int(category_counts["electrical"]), 5, "Electrical has five equipment tiers")
	assert_eq(int(category_counts["mechanical"]), 5, "Mechanical has five equipment tiers")

	GameState.state["prestige_count"] = 0
	GameState.state["unlocked_techs"] = []
	GameState.state["unit_counts"]["edge_cluster"] = 0
	GameState.state["cash"] = GameState.get_unit_effective_base_cost("edge_cluster")
	assert_true(GameState.buy_unit("edge_cluster"), "Advanced equipment is expensive but never hard-locked behind prestige")

func test_mechanical_and_ops_tech_effects_are_active() -> void:
	GameState.state["unit_counts"]["crac_unit"] = 2
	GameState.state["unlocked_techs"] = []
	GameState.active_event.clear()
	GameState.recalculate_all_metrics()
	var base_cooling: float = GameState.cooling_capacity_kwth

	GameState.state["unlocked_techs"] = ["mech_1", "ops_2"]
	GameState.recalculate_all_metrics()
	assert_almost_eq(GameState.cooling_capacity_kwth, base_cooling * 1.10, 0.001, "Hot-Aisle Containment improves cooling")
	assert_almost_eq(GameState.get_thermal_trip_grace_seconds(), 45.0, 0.001, "N+1 Redundancy extends trip grace by 50%")

	GameState.state["unlocked_techs"] = ["ops_3"]
	GameState.trigger_random_event("grid_sag")
	var mitigated_capacity: float = GameState.power_capacity_kw
	GameState.resolve_event(true, false)
	GameState.state["unlocked_techs"] = []
	GameState.trigger_random_event("grid_sag")
	var unmitigated_capacity: float = GameState.power_capacity_kw
	assert_true(mitigated_capacity > unmitigated_capacity, "Predictive Maintenance reduces grid-sag severity")
	GameState.resolve_event(true, false)

func test_site_sale_prestige_and_tier_unlock() -> void:
	var prestige_requirement := GameState.get_prestige_revenue_requirement()
	var prestige_base_tokens := GameState.get_prestige_base_tokens()
	GameState.state["lifetime_revenue_this_site"] = prestige_requirement
	GameState.state["tech_tokens"] = 10
	GameState.state["unlocked_site_tiers"] = [1]
	
	# Standard prestige
	var tokens_earned := GameState.prestige_site_sale(false, 1)
	assert_eq(tokens_earned, prestige_base_tokens, "Earned configured base TT at the prestige threshold")
	assert_eq(int(GameState.state["tech_tokens"]), 10 + prestige_base_tokens, "Tokens added to TT balance")
	assert_almost_eq(GameState.state["lifetime_revenue_this_site"], 0.0, 0.001, "Site lifetime revenue reset")
	assert_eq(int(GameState.state["unit_counts"]["rack_1u"]), 1, "Racks reset to 1")
	assert_eq(int(GameState.state["unit_counts"]["ai_superpod"]), 0, "Advanced equipment resets with the sold facility")
	
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

func test_coolant_leak_takes_a_cooling_unit_offline() -> void:
	GameState.state["unit_counts"]["crac_unit"] = 2
	GameState.state["unit_counts"]["chilled_water_plant"] = 0
	GameState.state["unit_counts"]["economizer"] = 0
	GameState.state["unlocked_techs"] = []
	GameState.active_event.clear()
	GameState.recalculate_all_metrics()
	var healthy_capacity: float = GameState.cooling_capacity_kwth
	GameState.trigger_random_event("coolant_leak")
	assert_eq(GameState.active_event.get("offline_unit_id", ""), "crac_unit", "Leak identifies an owned mechanical unit")
	assert_true(GameState.cooling_capacity_kwth < healthy_capacity, "Leaked unit stops providing cooling")
	GameState.resolve_event(true, false)

func test_previously_unlocked_site_can_be_reselected_for_free() -> void:
	GameState.state["site_tier"] = 1
	GameState.state["unlocked_site_tiers"] = [1]
	GameState.state["tech_tokens"] = 20
	assert_true(GameState.unlock_site_tier(2), "Tier 2 unlocks")
	var tokens_after_unlock: int = int(GameState.state["tech_tokens"])
	assert_true(GameState.select_site_tier(1), "Can return to Tier 1")
	assert_true(GameState.select_site_tier(2), "Can reselect Tier 2")
	assert_eq(int(GameState.state["tech_tokens"]), tokens_after_unlock, "Reselecting an owned site costs no TT")

func test_pending_offline_earnings_can_only_be_claimed_once() -> void:
	GameState.state["cash"] = 0.0
	SaveManager.pending_offline_data = {"revenue": 100.0}
	GameState.state["pending_offline_data"] = {"revenue": 100.0}
	assert_almost_eq(SaveManager.claim_offline_earnings(1.0), 100.0, 0.001, "Pending earnings are awarded")
	assert_almost_eq(SaveManager.claim_offline_earnings(1.0), 0.0, 0.001, "Claimed earnings cannot be awarded twice")

func test_invalid_primary_save_recovers_last_known_good_backup() -> void:
	_remove_test_save_files()
	SaveManager.pending_offline_data.clear()
	GameState.state["pending_offline_data"] = {}
	GameState.state["cash"] = 111.0
	assert_true(SaveManager.save_game(), "First atomic save succeeds")
	GameState.state["cash"] = 222.0
	assert_true(SaveManager.save_game(), "Second atomic save succeeds and rotates a backup")
	assert_true(FileAccess.file_exists(SaveManager.get_backup_save_path()), "Previous valid save is retained as backup")

	var corrupt_file := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	assert_not_null(corrupt_file, "Primary save can be opened for corruption test")
	corrupt_file.store_string("{not valid json")
	corrupt_file.close()

	GameState.state["cash"] = 0.0
	watch_signals(SaveManager)
	SaveManager.load_game()
	assert_almost_eq(float(GameState.state["cash"]), 111.0, 0.001, "Backup restores the last known-good cash value")
	assert_signal_emitted(SaveManager, "save_recovered_from_backup")
	assert_true(bool(SaveManager._read_save_file(SaveManager.save_path).get("ok", false)), "Recovered primary save is valid JSON")

func test_rewarded_revenue_boost_lasts_ten_minutes() -> void:
	GameState.state["boost_end_time"] = 0
	GameState.state["rewarded_boost_day"] = Time.get_date_string_from_system()
	GameState.state["rewarded_boost_count"] = 0
	assert_true(GameState.activate_rewarded_boost(), "Rewarded boost activates")
	assert_true(GameState.boost_time_remaining > 598.0, "Rewarded boost has approximately 10 minutes remaining")
	assert_true(GameState.boost_time_remaining <= 600.0, "Rewarded boost does not exceed 10 minutes")

func test_v1_save_migration_preserves_site_progress() -> void:
	var migrated := SaveManager._migrate_save_data({"schema_version": 1, "site_tier": 3}, 1)
	assert_eq(int(migrated["schema_version"]), 4, "Save migrates to schema 4")
	assert_eq(migrated["unlocked_site_tiers"], [1, 2, 3], "Previously reached sites remain unlocked")
	assert_eq(migrated["job_upgrade_levels"], {}, "Existing saves receive empty site-specific job upgrades")
	assert_true(bool(migrated["onboarding_completed"]), "Existing players do not receive first-run onboarding")
	var normalized := SaveManager._migrate_save_data({
		"schema_version": 3,
		"site_tier": 2.0,
		"unlocked_site_tiers": [1.0, 1, 2.0, 2],
		"unit_counts": {"rack_1u": 3.0},
		"job_upgrade_levels": {"contract_optimizer": 2.0}
	}, 3)
	assert_eq(normalized["site_tier"], 2, "JSON site tier is normalized to an integer")
	assert_eq(normalized["unlocked_site_tiers"], [1, 2], "Duplicate float and integer tiers are normalized")
	assert_eq(normalized["unit_counts"]["rack_1u"], 3, "JSON unit counts are normalized to integers")
	assert_eq(normalized["job_upgrade_levels"]["contract_optimizer"], 2, "Job upgrade levels normalize to integers")
	assert_true(bool(normalized["onboarding_completed"]), "Schema 3 players migrate past onboarding")

func test_iap_purchases_and_offline_cap() -> void:
	GameState.state["tech_tokens"] = 0
	GameState.state["remove_ads_owned"] = false
	GameState.state["starter_pack_owned"] = false
	GameState.state["prestige_count"] = 1
	
	# Buy remove_ads
	var bought_ads := GameState.process_iap_purchase("remove_ads")
	assert_true(bought_ads, "Processed remove_ads IAP")
	assert_true(GameState.state["remove_ads_owned"], "remove_ads_owned is true")
	
	# Verify offline cap doubled from 2h (7200s) to 4h (14400s)
	var offline_calc := Economy.calculate_offline_earnings(100.0, 0, 20000, GameState.state["remove_ads_owned"])
	assert_eq(float(offline_calc["offline_cap"]), 14400.0, "Offline cap extended to 4 hours (14,400s)")
	
	# Buy starter_pack
	var bought_pack := GameState.process_iap_purchase("starter_pack")
	assert_true(bought_pack, "Processed starter_pack IAP")
	assert_false(GameState.process_iap_purchase("starter_pack"), "Starter pack cannot be purchased twice")
	assert_eq(int(GameState.state["tech_tokens"]), 10, "10 TT awarded from starter pack")
	assert_almost_eq(GameState.boost_multiplier, 2.0, 0.001, "2x revenue multiplier active")
	assert_true(GameState.boost_time_remaining > 80000.0, "24h boost duration set")
	
	# Buy small and large TT packs
	GameState.process_iap_purchase("tt_small")
	assert_eq(int(GameState.state["tech_tokens"]), 25, "15 TT added from tt_small")
	GameState.process_iap_purchase("tt_large")
	assert_eq(int(GameState.state["tech_tokens"]), 100, "75 TT added from tt_large")

func test_sound_manager_synth() -> void:
	# Verify SoundManager audio triggers execute without crashing
	GameState.state["settings"]["sfx_enabled"] = true
	GameState.state["settings"]["music_enabled"] = true
	SoundManager.play_click()
	SoundManager.play_alarm()
	SoundManager.play_research()
	SoundManager.play_prestige()
	SoundManager.play_cash()
	SoundManager.update_audio_settings()
	assert_true(true, "SoundManager executed all procedural audio without errors")

func _remove_test_save_files() -> void:
	for path in [SaveManager.save_path, SaveManager.get_backup_save_path(), SaveManager.get_temporary_save_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
