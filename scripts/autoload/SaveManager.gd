extends Node

const SAVE_PATH: String = "user://savegame.json"
const CURRENT_SCHEMA_VERSION: int = 1

signal offline_earnings_calculated(offline_data: Dictionary)

func _ready() -> void:
	load_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()

func save_game() -> void:
	if not GameState:
		return
	
	GameState.state["last_save_time"] = int(Time.get_unix_time_from_system())
	GameState.state["schema_version"] = CURRENT_SCHEMA_VERSION
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var json_string := JSON.stringify(GameState.state, "\t")
		file.store_string(json_string)
		file.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		# Fresh game start
		_calculate_offline(0)
		return
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
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
	
	# Apply loaded state to GameState
	for key in migrated_data:
		GameState.state[key] = migrated_data[key]
	
	GameState.recalculate_all_metrics()
	
	var last_seen: int = int(migrated_data.get("last_save_time", 0))
	_calculate_offline(last_seen)

func _migrate_save_data(data: Dictionary, from_version: int) -> Dictionary:
	var result := data.duplicate(true)
	# Schema migration ladder (§7.6)
	if from_version < 1:
		result["schema_version"] = 1
	return result

func _calculate_offline(last_seen: int) -> void:
	if last_seen <= 0:
		return
	var now: int = int(Time.get_unix_time_from_system())
	var remove_ads: bool = bool(GameState.state.get("remove_ads_owned", false))
	var offline_data: Dictionary = Economy.calculate_offline_earnings(
		GameState.revenue_per_sec,
		last_seen,
		now,
		remove_ads
	)
	
	if offline_data["revenue"] > 0.0:
		offline_earnings_calculated.emit(offline_data)

func claim_offline_earnings(multiplier: float = 1.0) -> float:
	var last_seen: int = int(GameState.state.get("last_save_time", 0))
	var now: int = int(Time.get_unix_time_from_system())
	var remove_ads: bool = bool(GameState.state.get("remove_ads_owned", false))
	var offline_data: Dictionary = Economy.calculate_offline_earnings(
		GameState.revenue_per_sec,
		last_seen,
		now,
		remove_ads
	)
	
	var awarded: float = float(offline_data.get("revenue", 0.0)) * multiplier
	if awarded > 0.0:
		GameState.state["cash"] += awarded
		GameState.state["lifetime_revenue_this_site"] += awarded
		GameState.state["lifetime_revenue_all_time"] += awarded
		GameState.currency_changed.emit(GameState.state["cash"], GameState.state["tech_tokens"])
		save_game()
	return awarded
