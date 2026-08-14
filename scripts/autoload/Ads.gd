extends Node

# Mockable AdMob wrapper (§6.1, §6.2)
# In editor / desktop builds, signals trigger mock successes immediately.

signal rewarded_video_loaded()
signal rewarded_video_failed_to_load(error_code: int)
signal rewarded_video_closed()
signal rewarded_video_earned_reward(currency: String, amount: int)
signal interstitial_loaded()
signal interstitial_closed()

var is_rewarded_ready: bool = true
var is_interstitial_ready: bool = true

func _ready() -> void:
	pass

func show_rewarded_ad(placement_tag: String, on_success_callback: Callable) -> void:
	# In editor / non-mobile, simulate instant ad watch
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		if on_success_callback.is_valid():
			on_success_callback.call()
		rewarded_video_earned_reward.emit(placement_tag, 1)
		return
	
	# Future mobile plugin integration hooks in M4
	if on_success_callback.is_valid():
		on_success_callback.call()

func show_interstitial(placement_tag: String) -> void:
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		interstitial_closed.emit()
		return
	
	interstitial_closed.emit()
