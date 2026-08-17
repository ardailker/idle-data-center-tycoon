extends Node

const DEFAULT_SAVE_PATH: String = "user://savegame.json"
const CURRENT_SCHEMA_VERSION: int = 4
const BACKUP_SUFFIX: String = ".bak"
const TEMP_SUFFIX: String = ".tmp"

var save_path: String = DEFAULT_SAVE_PATH

signal offline_earnings_calculated(offline_data: Dictionary)
signal save_recovered_from_backup()

var pending_offline_data: Dictionary = {}

func _ready() -> void:
	load_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		call_deferred("_calculate_and_present_after_resume")

func save_game() -> bool:
	if not GameState:
		return false
	
	GameState.state["last_save_time"] = int(Time.get_unix_time_from_system())
	GameState.state["schema_version"] = CURRENT_SCHEMA_VERSION

	var temp_path := get_temporary_save_path()
	var json_string := JSON.stringify(GameState.state, "\t")
	if not _write_text_file(temp_path, json_string):
		push_error("Failed to write temporary save file: %s" % temp_path)
		return false

	var verification := _read_save_file(temp_path)
	if not bool(verification.get("ok", false)):
		_remove_file_if_present(temp_path)
		push_error("Temporary save verification failed: %s" % temp_path)
		return false

	if not _promote_temporary_save(temp_path):
		return false
	return true

func load_game() -> void:
	var backup_path := get_backup_save_path()
	if not FileAccess.file_exists(save_path) and not FileAccess.file_exists(backup_path):
		# Fresh game start
		_calculate_offline(0)
		return

	var load_result := _read_save_file(save_path)
	if not bool(load_result.get("ok", false)):
		var backup_result := _read_save_file(backup_path)
		if not bool(backup_result.get("ok", false)):
			push_error("Failed to load both the primary and backup save files.")
			return
		load_result = backup_result
		_restore_primary_from_backup()
		save_recovered_from_backup.emit()
		push_warning("Primary save was invalid; progress was recovered from backup.")

	var loaded_data: Dictionary = load_result["data"]
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
	if from_version < 4:
		# Existing players have already learned the current loop. Only genuinely
		# new games should show the three-tip onboarding sequence.
		result["onboarding_completed"] = true
		result["schema_version"] = 4

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
	result["schema_version"] = CURRENT_SCHEMA_VERSION
	return result

func get_backup_save_path() -> String:
	return save_path + BACKUP_SUFFIX

func get_temporary_save_path() -> String:
	return save_path + TEMP_SUFFIX

func _write_text_file(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(content)
	file.flush()
	file.close()
	return true

func _read_save_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {"ok": false, "data": {}}
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(content)
	if err != OK or not (json.data is Dictionary):
		return {"ok": false, "data": {}}
	return {"ok": true, "data": json.data}

func _promote_temporary_save(temp_path: String) -> bool:
	var primary_absolute := ProjectSettings.globalize_path(save_path)
	var backup_absolute := ProjectSettings.globalize_path(get_backup_save_path())
	var temp_absolute := ProjectSettings.globalize_path(temp_path)

	_remove_file_if_present(get_backup_save_path())
	if FileAccess.file_exists(save_path):
		var backup_error := DirAccess.rename_absolute(primary_absolute, backup_absolute)
		if backup_error != OK:
			_remove_file_if_present(temp_path)
			push_error("Failed to rotate the previous save to backup (error %d)." % backup_error)
			return false

	var promote_error := DirAccess.rename_absolute(temp_absolute, primary_absolute)
	if promote_error == OK:
		return true

	# If promotion fails after rotation, restore the last known-good save.
	if not FileAccess.file_exists(save_path) and FileAccess.file_exists(get_backup_save_path()):
		DirAccess.rename_absolute(backup_absolute, primary_absolute)
	_remove_file_if_present(temp_path)
	push_error("Failed to promote the temporary save (error %d)." % promote_error)
	return false

func _restore_primary_from_backup() -> void:
	var recovery_temp_path := get_temporary_save_path()
	_remove_file_if_present(recovery_temp_path)
	var copy_error := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(get_backup_save_path()),
		ProjectSettings.globalize_path(recovery_temp_path)
	)
	if copy_error != OK:
		push_warning("Loaded backup, but could not stage primary save recovery (error %d)." % copy_error)
		return
	_remove_file_if_present(save_path)
	var restore_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(recovery_temp_path),
		ProjectSettings.globalize_path(save_path)
	)
	if restore_error != OK:
		push_warning("Loaded backup, but could not restore the primary save (error %d)." % restore_error)

func _remove_file_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

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
