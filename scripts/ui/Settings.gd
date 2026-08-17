extends PanelContainer

@onready var sfx_check: CheckBox = $Margin/VBox/AudioSection/SFXCheck
@onready var music_check: CheckBox = $Margin/VBox/AudioSection/MusicCheck
@onready var haptics_check: CheckBox = $Margin/VBox/AudioSection/HapticsCheck

@onready var remove_ads_btn: Button = $Margin/VBox/IAPSection/RemoveAdsBtn
@onready var starter_pack_btn: Button = $Margin/VBox/IAPSection/StarterPackBtn
@onready var tt_small_btn: Button = $Margin/VBox/IAPSection/TTSmallBtn
@onready var tt_large_btn: Button = $Margin/VBox/IAPSection/TTLargeBtn

@onready var restore_btn: Button = $Margin/VBox/MetaSection/RestoreBtn
@onready var privacy_btn: Button = $Margin/VBox/MetaSection/PrivacyBtn
@onready var close_btn: Button = $Margin/VBox/CloseBtn

func _ready() -> void:
	visible = false
	
	sfx_check.toggled.connect(_on_sfx_toggled)
	music_check.toggled.connect(_on_music_toggled)
	haptics_check.toggled.connect(_on_haptics_toggled)
	
	remove_ads_btn.pressed.connect(func(): _buy_iap("remove_ads"))
	starter_pack_btn.pressed.connect(func(): _buy_iap("starter_pack"))
	tt_small_btn.pressed.connect(func(): _buy_iap("tt_small"))
	tt_large_btn.pressed.connect(func(): _buy_iap("tt_large"))
	
	restore_btn.pressed.connect(_on_restore_pressed)
	privacy_btn.pressed.connect(_on_privacy_pressed)
	close_btn.pressed.connect(func(): visible = false)
	
	_load_settings_ui()

func open_settings() -> void:
	_load_settings_ui()
	visible = true

func _load_settings_ui() -> void:
	var settings: Dictionary = GameState.state.get("settings", {})
	sfx_check.button_pressed = bool(settings.get("sfx_enabled", true))
	music_check.button_pressed = bool(settings.get("music_enabled", true))
	haptics_check.button_pressed = bool(settings.get("haptics_enabled", true))
	
	var remove_ads_owned: bool = bool(GameState.state.get("remove_ads_owned", false))
	if remove_ads_owned:
		remove_ads_btn.text = "REMOVE ADS — OWNED"
		remove_ads_btn.disabled = true
	else:
		remove_ads_btn.text = "REMOVE ADS ($2.99)\nNo Interstitials + 4h Offline Cap"
		remove_ads_btn.disabled = false

	var starter_owned: bool = bool(GameState.state.get("starter_pack_owned", false))
	if starter_owned:
		starter_pack_btn.text = "STARTER PACK — OWNED"
		starter_pack_btn.disabled = true
	elif int(GameState.state.get("prestige_count", 0)) < 1:
		starter_pack_btn.text = "STARTER PACK — UNLOCKS AFTER FIRST SITE SALE"
		starter_pack_btn.disabled = true
	else:
		starter_pack_btn.text = "STARTER PACK ($4.99)\n10 TT + 24h 2X Revenue Multiplier"
		starter_pack_btn.disabled = false

func _on_sfx_toggled(toggled_on: bool) -> void:
	GameState.state["settings"]["sfx_enabled"] = toggled_on
	if SaveManager:
		SaveManager.save_game()

func _on_music_toggled(toggled_on: bool) -> void:
	GameState.state["settings"]["music_enabled"] = toggled_on
	SoundManager.update_audio_settings()
	if SaveManager:
		SaveManager.save_game()

func _on_haptics_toggled(toggled_on: bool) -> void:
	GameState.state["settings"]["haptics_enabled"] = toggled_on
	if SaveManager:
		SaveManager.save_game()

func _buy_iap(sku: String) -> void:
	if GameState.process_iap_purchase(sku):
		SoundManager.play_cash()
	_load_settings_ui()

func _on_restore_pressed() -> void:
	# In mobile production, invokes Play Billing restorePurchases
	_load_settings_ui()

func _on_privacy_pressed() -> void:
	OS.shell_open("https://suyapi.com.tr/privacy-policy")
