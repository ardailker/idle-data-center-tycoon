extends GutTest

func before_all() -> void:
	gut.p("Running Economy Unit Tests for M0...")

func test_unit_cost_formula() -> void:
	# cost(0) = 10, cost(1) = 10 * 1.12 = 11.2, cost(2) = 10 * 1.12^2 = 12.544
	var cost_0 := Economy.calculate_unit_cost(10.0, 1.12, 0)
	var cost_1 := Economy.calculate_unit_cost(10.0, 1.12, 1)
	var cost_2 := Economy.calculate_unit_cost(10.0, 1.12, 2)
	assert_almost_eq(cost_0, 10.0, 0.001, "Cost at n=0 should equal base cost")
	assert_almost_eq(cost_1, 11.2, 0.001, "Cost at n=1 should match growth")
	assert_almost_eq(cost_2, 12.544, 0.001, "Cost at n=2 should match growth^2")

func test_bulk_unit_cost() -> void:
	# Buying 2 units starting at count 0: cost(0) + cost(1) = 10 + 11.2 = 21.2
	var bulk_2 := Economy.calculate_bulk_unit_cost(10.0, 1.12, 0, 2)
	assert_almost_eq(bulk_2, 21.2, 0.001, "Bulk cost for 2 units from count 0")

func test_pue_calculation() -> void:
	# PUE = total_load / it_load
	var pue_normal := Economy.calculate_pue(20.0, 10.0)
	assert_almost_eq(pue_normal, 2.0, 0.001, "PUE should be 2.0")
	var pue_zero_it := Economy.calculate_pue(10.0, 0.0)
	assert_almost_eq(pue_zero_it, 2.0, 0.001, "PUE should default to 2.0 when IT load is 0")

func test_throttle_calculation() -> void:
	# Capacity 80kW, Total Load 100kW -> throttle = 0.8
	var throttle_under := Economy.calculate_throttle(80.0, 100.0)
	assert_almost_eq(throttle_under, 0.8, 0.001, "Throttle under capacity")
	
	# Capacity 120kW, Total Load 100kW -> throttle = 1.0 (clamped)
	var throttle_over := Economy.calculate_throttle(120.0, 100.0)
	assert_almost_eq(throttle_over, 1.0, 0.001, "Throttle over capacity clamped to 1.0")

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
	# Below 1e9 -> 0 tokens
	assert_eq(Economy.calculate_prestige_tokens(5e8), 0, "Prestige locked below 1e9")
	# Exactly 1e9 -> floor(12 * sqrt(1)) = 12 tokens
	assert_eq(Economy.calculate_prestige_tokens(1e9), 12, "Prestige at 1e9 yields 12 TT")
	# 4e9 -> floor(12 * sqrt(4)) = 24 tokens
	assert_eq(Economy.calculate_prestige_tokens(4e9), 24, "Prestige at 4e9 yields 24 TT")

func test_format_magnitude() -> void:
	assert_eq(Economy.format_magnitude(500.0), "500.00", "Format sub-thousand")
	assert_eq(Economy.format_magnitude(1500.0), "1.50 K", "Format Thousands")
	assert_eq(Economy.format_magnitude(2500000.0), "2.50 M", "Format Millions")
	assert_eq(Economy.format_magnitude(1e9), "1.00 B", "Format Billions")
