extends Node

const DEFAULT_SAVE_PATH: String = "user://savegame.json"
const CURRENT_SCHEMA_VERSION: int = 3

var save_path: String = DEFAULT_SAVE_PATH

signal offline_earnings_calculated(offline_data: Dictionary)

var pending_offline_data: Dictionary = {}

func _ready() -> void:
	load_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		call_deferred("_calculate_and_present_after_resume")

func save_game() -> void:
	if not GameState:
		return
	
	GameState.state["last_save_time"] = int(Time.get_unix_time_from_system())
	GameState.state["schema_version"] = CURRENT_SCHEMA_VERSION
	
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var json_string := JSON.stringify(GameState.state, "\t")
		file.store_string(json_string)
		file.close()

func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		# Fresh game start
		_calculate_offline(0)
		return
	
	var file := FileAccess.open(save_path, FileAccess.READ)
	if not file:
		return
	
	var content := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var err := json.parse(content)
	if err != OK or not (json.data is Dictionary):
		push_error("Failed to parse save game JSON.")
		return
	
	var loaded_data: Dictionary = json.data
	var version: int = int(loaded_data.get("schema_version", 1))
	var migrated_data := _migrate_save_data(loaded_data, version)
	var current_tier: int = int(migrated_data.get("site_tier", 1))
	var unlocked_tiers: Array = migrated_data.get("unlocked_site_tiers", [1])
	for tier in range(1, current_tier + 1):
		if not (tier in unlocked_tiers):
			unlocked_tiers.append(tier)
	migrated_data["unlocked_site_tiers"] = unlocked_tiers
	
	# Apply loaded state to GameState
	for key in migrated_data:
		GameState.state[key] = migrated_data[key]
	pending_offline_data = GameState.state.get("pending_offline_data", {}).duplicate(true)
	
	GameState.recalculate_all_metrics()
	
	var last_seen: int = int(migrated_data.get("last_save_time", 0))
	_calculate_offline(last_seen)

func _migrate_save_data(data: Dictionary, from_version: int) -> Dictionary:
	var result := data.duplicate(true)
	# Schema migration ladder (§7.6)
	if from_version < 1:
		result["schema_version"] = 1
	if from_version < 2:
		var current_tier: int = int(result.get("site_tier", 1))
		var unlocked_tiers: Array = []
		for tier in range(1, current_tier + 1):
			unlocked_tiers.append(tier)
		result["unlocked_site_tiers"] = unlocked_tiers
		result["starter_pack_owned"] = false
		result["prestige_count"] = 0
		result["boost_end_time"] = 0
		result["rewarded_boost_day"] = ""
		result["rewarded_boost_count"] = 0
		result["interstitial_day"] = ""
		result["interstitial_count"] = 0
		result["last_interstitial_time"] = 0
		result["pending_offline_data"] = {}
		result["schema_version"] = 2
	if from_version < 3:
		result["job_upgrade_levels"] = {}
		result["schema_version"] = 3

	# JSON numbers load as floats. Normalize catalog identifiers and remove
	# duplicate tiers so Dictionary lookups always use the integer tier keys.
	var current_tier: int = int(result.get("site_tier", 1))
	result["site_tier"] = current_tier
	var normalized_tiers: Array = []
	for saved_tier in result.get("unlocked_site_tiers", [1]):
		var tier: int = int(saved_tier)
		if tier > 0 and not (tier in normalized_tiers):
			normalized_tiers.append(tier)
	for tier in range(1, current_tier + 1):
		if not (tier in normalized_tiers):
			normalized_tiers.append(tier)
	normalized_tiers.sort()
	result["unlocked_site_tiers"] = normalized_tiers

	if result.has("unit_counts"):
		var normalized_counts: Dictionary = result["unit_counts"].duplicate()
		for unit_id in normalized_counts:
			normalized_counts[unit_id] = int(normalized_counts[unit_id])
		result["unit_counts"] = normalized_counts

	var normalized_job_levels: Dictionary = {}
	for upgrade_id in result.get("job_upgrade_levels", {}):
		normalized_job_levels[String(upgrade_id)] = max(int(result["job_upgrade_levels"][upgrade_id]), 0)
	result["job_upgrade_levels"] = normalized_job_levels
	return result

func _calculate_offline(last_seen: int) -> Dictionary:
	if not pending_offline_data.is_empty():
		return pending_offline_data
	if last_seen <= 0:
		return {}
	var now: int = int(Time.get_unix_time_from_system())
	var remove_ads: bool = bool(GameState.state.get("remove_ads_owned", false))
	var offline_data: Dictionary = Economy.calculate_offline_earnings(
		GameState.revenue_per_sec,
		last_seen,
		now,
		remove_ads,
		GameState.pue,
		GameState.uptime_mult
	)
	
	if offline_data["revenue"] > 0.0:
		pending_offline_data = offline_data
		GameState.state["pending_offline_data"] = offline_data.duplicate(true)
	return offline_data

func present_pending_offline_earnings() -> void:
	if not pending_offline_data.is_empty():
		offline_earnings_calculated.emit(pending_offline_data.duplicate(true))

func _calculate_and_present_after_resume() -> void:
	var last_seen: int = int(GameState.state.get("last_save_time", 0))
	_calculate_offline(last_seen)
	present_pending_offline_earnings()

func claim_offline_earnings(multiplier: float = 1.0) -> float:
	if pending_offline_data.is_empty():
		return 0.0
	var awarded: float = float(pending_offline_data.get("revenue", 0.0)) * max(multiplier, 0.0)
	pending_offline_data.clear()
	GameState.state["pending_offline_data"] = {}
	if awarded > 0.0:
		GameState.state["cash"] += awarded
		GameState.state["lifetime_revenue_this_site"] += awarded
		GameState.state["lifetime_revenue_all_time"] += awarded
		GameState.currency_changed.emit(GameState.state["cash"], GameState.state["tech_tokens"])
		save_game()
	return awarded
