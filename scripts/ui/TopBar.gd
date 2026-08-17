extends PanelContainer

signal settings_requested()

@onready var cash_label: Label = $VBox/Header/CashBox/CashLabel
@onready var rev_label: Label = $VBox/Header/CashBox/RevLabel
@onready var tt_label: Label = $VBox/Header/TTBox/TTLabel
@onready var boost_badge: Label = $VBox/Header/BoostBadge
@onready var settings_btn: Button = $VBox/Header/SettingsBtn

@onready var power_bar: PixelGaugeBar = $VBox/Gauges/PowerGauge/PowerBar
@onready var power_label: Label = $VBox/Gauges/PowerGauge/PowerLabel
@onready var cooling_bar: PixelGaugeBar = $VBox/Gauges/CoolingGauge/CoolingBar
@onready var cooling_label: Label = $VBox/Gauges/CoolingGauge/CoolingLabel

@onready var pue_label: Label = $VBox/Metrics/PUEBox/PUELabel
@onready var uptime_label: Label = $VBox/Metrics/UptimeBox/UptimeLabel
@onready var throttle_badge: Label = $VBox/Metrics/ThrottleBadge
@onready var it_power_label: Label = $VBox/Metrics/ITPowerBox/ITPowerLabel
@onready var pue_box: HBoxContainer = $VBox/Metrics/PUEBox
@onready var uptime_box: HBoxContainer = $VBox/Metrics/UptimeBox
@onready var metric_info_panel: PanelContainer = $VBox/MetricInfoPanel
@onready var metric_info_label: Label = $VBox/MetricInfoPanel/MetricInfoLabel

@onready var thermal_alert_banner: PanelContainer = $VBox/ThermalAlertBanner
@onready var thermal_alert_label: Label = $VBox/ThermalAlertBanner/ThermalAlertLabel

var alert_blink_timer: float = 0.0
var thermal_alert_was_active: bool = false
var active_metric_info: String = ""

func _ready() -> void:
	settings_btn.icon = PixelIcons.build_icon_texture("settings_gear", Color("#22c55e"), 3, false)
	GameState.state_updated.connect(_update_ui)
	GameState.thermal_alert.connect(_on_thermal_alert)
	settings_btn.pressed.connect(func(): settings_requested.emit())
	pue_box.gui_input.connect(func(event): _on_metric_input(event, "pue"))
	uptime_box.gui_input.connect(func(event): _on_metric_input(event, "uptime"))
	_update_ui()

func _on_metric_input(event: InputEvent, metric_id: String) -> void:
	var is_press: bool = (
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if not is_press:
		return
	active_metric_info = "" if active_metric_info == metric_id else metric_id
	metric_info_panel.visible = not active_metric_info.is_empty()
	_update_metric_explanation()

func _update_metric_explanation() -> void:
	if active_metric_info == "pue":
		metric_info_label.text = "PUE = TOTAL POWER / IT POWER\n%.1f kW / %.1f kW = %.2f PUE\nLower PUE raises offline earnings." % [
			GameState.total_load_kw,
			GameState.it_load_kw,
			GameState.pue
		]
	elif active_metric_info == "uptime":
		metric_info_label.text = "UP = SERVER AVAILABILITY\nBASE 99.000%% | REL +%.3f%% | POWER -%.3f%%\nCOOLING -%.3f%% | TRIPS -%.3f%% | OFFLINE BONUS" % [
			GameState.uptime_reliability_bonus * 100.0,
			GameState.uptime_power_penalty * 100.0,
			GameState.uptime_cooling_penalty * 100.0,
			GameState.uptime_trip_penalty * 100.0
		]

func _process(delta: float) -> void:
	# Blink thermal alert banner if active
	if GameState.thermal_alarm_timer > 0.0:
		alert_blink_timer += delta
		var alpha: float = 0.5 + 0.5 * sin(alert_blink_timer * 8.0)
		thermal_alert_banner.modulate = Color(1, 1, 1, alpha)
		var time_left: float = max(GameState.get_thermal_trip_grace_seconds() - GameState.thermal_alarm_timer, 0.0)
		thermal_alert_label.text = "THERMAL OVERLOAD | TRIP IN %.0fs" % time_left
	else:
		thermal_alert_banner.visible = false

func _on_thermal_alert(active: bool) -> void:
	thermal_alert_banner.visible = active
	if active and not thermal_alert_was_active:
		SoundManager.play_alarm()
		SoundManager.play_haptic(80)
	thermal_alert_was_active = active

func _gauge_color_for_load(load_ratio: float) -> Color:
	if load_ratio >= 1.0:
		return Color("#ef4444") # Alarm
	elif load_ratio >= 0.8:
		return Color("#f59e0b") # At capacity
	return Color("#22c55e") # Healthy

func _update_ui() -> void:
	# Currency & Rates
	cash_label.text = "$ %s" % Economy.format_magnitude(GameState.state["cash"])
	rev_label.text = "+$%s/s" % Economy.format_magnitude(GameState.revenue_per_sec)
	tt_label.text = "%d TT" % GameState.state["tech_tokens"]
	
	# Boost state
	if GameState.boost_time_remaining > 0.0:
		boost_badge.visible = true
		boost_badge.text = "2X"
	else:
		boost_badge.visible = false
	
	# Power Gauge
	var total_pwr: float = GameState.total_load_kw
	var cap_pwr: float = GameState.power_capacity_kw
	var pwr_load_ratio: float = total_pwr / max(cap_pwr, 0.001)
	power_bar.max_value = max(cap_pwr, total_pwr, 1.0)
	power_bar.value = total_pwr
	power_bar.fill_color = _gauge_color_for_load(pwr_load_ratio)
	power_label.text = "PWR  %.1f / %.1f kW  |  %.0f%%" % [
		total_pwr,
		cap_pwr,
		pwr_load_ratio * 100.0
	]

	# Cooling Gauge
	var heat_load: float = GameState.heat_load_kwth
	var cap_cool: float = GameState.cooling_capacity_kwth
	var cool_load_ratio: float = heat_load / max(cap_cool, 0.001)
	cooling_bar.max_value = max(cap_cool, heat_load, 1.0)
	cooling_bar.value = heat_load
	cooling_bar.fill_color = _gauge_color_for_load(cool_load_ratio)
	cooling_label.text = "COOL %.1f / %.1f kW-th | %.0f%%" % [
		heat_load,
		cap_cool,
		cool_load_ratio * 100.0
	]
	
	# PUE & Uptime
	it_power_label.text = "IT %.1f kW" % GameState.it_load_kw
	pue_label.text = "PUE %.2f [?]" % GameState.pue
	if GameState.pue <= 1.20:
		pue_label.modulate = Color("#22c55e") # Green
	elif GameState.pue <= 1.60:
		pue_label.modulate = Color("#38bdf8") # Cyan
	else:
		pue_label.modulate = Color("#f59e0b") # Yellow
	
	var uptime_pct: float = GameState.uptime_mult * 100.0
	uptime_label.text = "UP %.3f%% [?]" % uptime_pct
	if uptime_pct >= 99.9:
		uptime_label.modulate = Color("#22c55e")
	elif uptime_pct >= 99.0:
		uptime_label.modulate = Color("#f59e0b")
	else:
		uptime_label.modulate = Color("#ef4444")
	
	# Throttle badge
	if GameState.throttle_ratio < 0.999:
		throttle_badge.visible = true
		throttle_badge.text = "THROTTLE %.0f%%" % (GameState.throttle_ratio * 100.0)
	else:
		throttle_badge.visible = false

	if not active_metric_info.is_empty():
		_update_metric_explanation()
