extends GutTest

const PixelGaugeBarScript = preload("res://scripts/ui/PixelGaugeBar.gd")
const TopBarScene = preload("res://scenes/ui/TopBar.tscn")
const OnboardingScene = preload("res://scenes/ui/Onboarding.tscn")

const HEALTHY_COLOR := Color("#22c55e")
const WARNING_COLOR := Color("#f59e0b")
const ALARM_COLOR := Color("#ef4444")

var original_meter_state: Dictionary
var original_onboarding_completed: bool
var original_save_path: String

func before_each() -> void:
	original_onboarding_completed = bool(GameState.state.get("onboarding_completed", false))
	original_save_path = SaveManager.save_path
	original_meter_state = {
		"total_load_kw": GameState.total_load_kw,
		"power_capacity_kw": GameState.power_capacity_kw,
		"heat_load_kwth": GameState.heat_load_kwth,
		"cooling_capacity_kwth": GameState.cooling_capacity_kwth,
	}

func after_each() -> void:
	_cleanup_onboarding_test_saves()
	SaveManager.save_path = original_save_path
	GameState.state["onboarding_completed"] = original_onboarding_completed
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

func test_onboarding_shows_exactly_three_tips_and_persists_completion() -> void:
	SaveManager.save_path = "user://test_onboarding_save.json"
	_cleanup_onboarding_test_saves()
	GameState.state["onboarding_completed"] = false
	var onboarding = OnboardingScene.instantiate()
	add_child_autofree(onboarding)
	await wait_process_frames(2)

	assert_true(onboarding.visible, "New players see onboarding")
	assert_eq(onboarding.TIPS.size(), 3, "Scope-locked onboarding contains exactly three tips")
	assert_string_contains(onboarding.step_label.text, "1 / 3")
	onboarding._advance()
	assert_string_contains(onboarding.step_label.text, "2 / 3")
	onboarding._advance()
	assert_string_contains(onboarding.step_label.text, "3 / 3")
	assert_eq(onboarding.next_btn.text, "GOT IT", "Final tip has a clear completion action")
	onboarding._advance()

	assert_false(onboarding.visible, "Onboarding closes after the third tip")
	assert_true(bool(GameState.state["onboarding_completed"]), "Completion is stored in game state")
	assert_true(FileAccess.file_exists(SaveManager.save_path), "Completion is persisted immediately")

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

func _cleanup_onboarding_test_saves() -> void:
	for path in [SaveManager.save_path, SaveManager.get_backup_save_path(), SaveManager.get_temporary_save_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
