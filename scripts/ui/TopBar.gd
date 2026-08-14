extends PanelContainer

signal settings_requested()

@onready var cash_label: Label = $VBox/Header/CashBox/CashLabel
@onready var rev_label: Label = $VBox/Header/CashBox/RevLabel
@onready var tt_label: Label = $VBox/Header/TTBox/TTLabel
@onready var boost_badge: Label = $VBox/Header/BoostBadge
@onready var settings_btn: Button = $VBox/Header/SettingsBtn

@onready var power_bar: ProgressBar = $VBox/Gauges/PowerGauge/PowerBar
@onready var power_label: Label = $VBox/Gauges/PowerGauge/PowerLabel
@onready var cooling_bar: ProgressBar = $VBox/Gauges/CoolingGauge/CoolingBar
@onready var cooling_label: Label = $VBox/Gauges/CoolingGauge/CoolingLabel

@onready var pue_label: Label = $VBox/Metrics/PUEBox/PUELabel
@onready var uptime_label: Label = $VBox/Metrics/UptimeBox/UptimeLabel
@onready var throttle_badge: Label = $VBox/Metrics/ThrottleBadge

@onready var thermal_alert_banner: PanelContainer = $VBox/ThermalAlertBanner
@onready var thermal_alert_label: Label = $VBox/ThermalAlertBanner/ThermalAlertLabel

var alert_blink_timer: float = 0.0

func _ready() -> void:
	GameState.state_updated.connect(_update_ui)
	GameState.thermal_alert.connect(_on_thermal_alert)
	settings_btn.pressed.connect(func(): settings_requested.emit())
	_update_ui()

func _process(delta: float) -> void:
	# Blink thermal alert banner if active
	if GameState.thermal_alarm_timer > 0.0:
		alert_blink_timer += delta
		var alpha: float = 0.5 + 0.5 * sin(alert_blink_timer * 8.0)
		thermal_alert_banner.modulate = Color(1, 1, 1, alpha)
		var time_left: float = max(30.0 - GameState.thermal_alarm_timer, 0.0)
		thermal_alert_label.text = "CRITICAL THERMAL OVERLOAD! TRIPPING IN %.1fs" % time_left
	else:
		thermal_alert_banner.visible = false

func _on_thermal_alert(active: bool) -> void:
	thermal_alert_banner.visible = active

func _update_ui() -> void:
	# Currency & Rates
	cash_label.text = "$ %s" % Economy.format_magnitude(GameState.state["cash"])
	rev_label.text = "+$%s/s" % Economy.format_magnitude(GameState.revenue_per_sec)
	tt_label.text = "%d TT" % GameState.state["tech_tokens"]
	
	# Boost state
	if GameState.boost_time_remaining > 0.0:
		boost_badge.visible = true
		boost_badge.text = "2X BOOST: %ds" % int(GameState.boost_time_remaining)
	else:
		boost_badge.visible = false
	
	# Power Gauge
	var total_pwr: float = GameState.total_load_kw
	var cap_pwr: float = GameState.power_capacity_kw
	power_bar.max_value = max(cap_pwr, total_pwr, 1.0)
	power_bar.value = total_pwr
	power_label.text = "PWR: %.1f / %.1f kW (%.0f%%)" % [
		total_pwr,
		cap_pwr,
		(total_pwr / max(cap_pwr, 0.001)) * 100.0
	]
	
	# Cooling Gauge
	var heat_load: float = GameState.heat_load_kwth
	var cap_cool: float = GameState.cooling_capacity_kwth
	cooling_bar.max_value = max(cap_cool, heat_load, 1.0)
	cooling_bar.value = heat_load
	cooling_label.text = "COOL: %.1f / %.1f kW-th (%.0f%%)" % [
		heat_load,
		cap_cool,
		(heat_load / max(cap_cool, 0.001)) * 100.0
	]
	
	# PUE & Uptime
	pue_label.text = "PUE: %.2f" % GameState.pue
	if GameState.pue <= 1.20:
		pue_label.modulate = Color("#22c55e") # Green
	elif GameState.pue <= 1.60:
		pue_label.modulate = Color("#38bdf8") # Cyan
	else:
		pue_label.modulate = Color("#f59e0b") # Yellow
	
	var uptime_pct: float = GameState.uptime_mult * 100.0
	uptime_label.text = "UPTIME: %.3f%%" % uptime_pct
	if uptime_pct >= 99.9:
		uptime_label.modulate = Color("#22c55e")
	elif uptime_pct >= 99.0:
		uptime_label.modulate = Color("#f59e0b")
	else:
		uptime_label.modulate = Color("#ef4444")
	
	# Throttle badge
	if GameState.throttle_ratio < 0.999:
		throttle_badge.visible = true
		throttle_badge.text = "THROTTLED: %.0f%%" % (GameState.throttle_ratio * 100.0)
	else:
		throttle_badge.visible = false
