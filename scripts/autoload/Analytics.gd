extends Node

# Mockable Analytics wrapper (§7)

func track_event(event_name: String, parameters: Dictionary = {}) -> void:
	if OS.is_debug_build():
		print_verbose("[Analytics] %s: %s" % [event_name, str(parameters)])

func track_purchase(item_id: String, price_usd: float) -> void:
	track_event("purchase", {"item_id": item_id, "price": price_usd})

func track_ad_impression(ad_type: String, placement: String) -> void:
	track_event("ad_impression", {"type": ad_type, "placement": placement})

func track_prestige(site_tier: int, tokens_gained: int) -> void:
	track_event("site_prestige", {"site_tier": site_tier, "tokens_gained": tokens_gained})
