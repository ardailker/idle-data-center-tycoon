extends GutTest

const PixelGaugeBarScript = preload("res://scripts/ui/PixelGaugeBar.gd")
const TopBarScene = preload("res://scenes/ui/TopBar.tscn")

const HEALTHY_COLOR := Color("#22c55e")
const WARNING_COLOR := Color("#f59e0b")
const ALARM_COLOR := Color("#ef4444")

var original_meter_state: Dictionary

func before_each() -> void:
	original_meter_state = {
		"total_load_kw": GameState.total_load_kw,
		"power_capacity_kw": GameState.power_capacity_kw,
		"heat_load_kwth": GameState.heat_load_kwth,
		"cooling_capacity_kwth": GameState.cooling_capacity_kwth,
	}

func after_each() -> void:
	GameState.total_load_kw = original_meter_state["total_load_kw"]
	GameState.power_capacity_kw = original_meter_state["power_capacity_kw"]
	GameState.heat_load_kwth = original_meter_state["heat_load_kwth"]
	GameState.cooling_capacity_kwth = original_meter_state["cooling_capacity_kwth"]

func test_fill_color_change_requests_redraw_without_value_change() -> void:
	var gauge: PixelGaugeBar = PixelGaugeBarScript.new()
	gauge.size = Vector2(160.0, 8.0)
	add_child_autofree(gauge)
	await wait_process_frames(2)

	watch_signals(gauge)
	gauge.fill_color = WARNING_COLOR
	await wait_process_frames(2)

	assert_eq(gauge.fill_color, WARNING_COLOR)
	assert_signal_emitted(gauge.draw)

func test_power_and_cooling_colors_cover_all_load_thresholds() -> void:
	var top_bar: PanelContainer = TopBarScene.instantiate()
	add_child_autofree(top_bar)
	await wait_process_frames(2)

	_assert_meter_colors(top_bar, 0.79, HEALTHY_COLOR, "healthy")
	_assert_meter_colors(top_bar, 0.80, WARNING_COLOR, "warning")
	_assert_meter_colors(top_bar, 1.00, ALARM_COLOR, "alarm")

func _assert_meter_colors(
	top_bar: PanelContainer,
	load_ratio: float,
	expected_color: Color,
	state_name: String
) -> void:
	GameState.power_capacity_kw = 100.0
	GameState.total_load_kw = 100.0 * load_ratio
	GameState.cooling_capacity_kwth = 100.0
	GameState.heat_load_kwth = 100.0 * load_ratio
	top_bar._update_ui()

	var power_bar: PixelGaugeBar = top_bar.get_node("VBox/Gauges/PowerGauge/PowerBar")
	var cooling_bar: PixelGaugeBar = top_bar.get_node("VBox/Gauges/CoolingGauge/CoolingBar")
	assert_eq(power_bar.fill_color, expected_color, "Power meter should be %s" % state_name)
	assert_eq(cooling_bar.fill_color, expected_color, "Cooling meter should be %s" % state_name)
