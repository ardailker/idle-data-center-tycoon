extends PanelContainer
class_name FacilityTapPanel

signal job_requested(click_position: Vector2)

@onready var site_label: Label = $Margin/VBox/SiteLabel
@onready var art_spacer: Control = $Margin/VBox/ArtSpacer
@onready var action_label: Label = $Margin/VBox/ActionLabel

var site_tier: int = 1
var site_name: String = "RENTED CLOSET"
var reward: float = 1.0
var charges: int = 5
var max_charges: int = 5
var activity_flash: float = 0.0:
	set(value):
		activity_flash = value
		queue_redraw()
var flash_tween: Tween

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	queue_redraw()

func set_job_state(
	new_site_tier: int,
	new_site_name: String,
	new_reward: float,
	new_charges: int,
	new_max_charges: int
) -> void:
	var site_changed_value: bool = site_tier != new_site_tier
	site_tier = new_site_tier
	site_name = new_site_name.to_upper()
	reward = new_reward
	charges = new_charges
	max_charges = new_max_charges
	site_label.text = "SITE %d  |  %s" % [site_tier, site_name]
	site_label.add_theme_color_override(
		"font_color",
		Color("#b69cff") if site_tier == 5 else Color("#61d1ff")
	)
	action_label.text = "TAP DATA CENTER  +$%s  |  %d/%d" % [
		Economy.format_magnitude(reward),
		charges,
		max_charges
	]
	action_label.modulate = Color("#22c55e") if charges > 0 else Color("#6b736d")
	mouse_filter = Control.MOUSE_FILTER_STOP if charges > 0 else Control.MOUSE_FILTER_IGNORE
	if site_changed_value:
		queue_redraw()

func show_job_feedback(earned: float, click_position: Vector2) -> void:
	_spawn_floating_reward(earned, click_position)
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
	activity_flash = 1.0
	flash_tween = create_tween()
	flash_tween.tween_property(self, "activity_flash", 0.0, 0.45)

func _spawn_floating_reward(earned: float, click_position: Vector2) -> void:
	var floating_reward := Label.new()
	floating_reward.text = "+$%s" % Economy.format_magnitude(earned)
	floating_reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floating_reward.z_index = 10
	floating_reward.add_theme_color_override("font_color", Color("#6bff8f"))
	floating_reward.add_theme_color_override("font_outline_color", Color("#031008"))
	floating_reward.add_theme_constant_override("outline_size", 2)
	floating_reward.add_theme_font_size_override("font_size", 11)
	art_spacer.add_child(floating_reward)
	floating_reward.reset_size()
	var click_global: Vector2 = get_global_transform() * click_position
	var click_in_art: Vector2 = art_spacer.get_global_transform().affine_inverse() * click_global
	floating_reward.position = click_in_art - floating_reward.size * 0.5
	var reward_tween := create_tween().set_parallel(true)
	reward_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	reward_tween.tween_property(floating_reward, "position", floating_reward.position + Vector2(0.0, -38.0), 0.65)
	reward_tween.tween_property(floating_reward, "modulate:a", 0.0, 0.5).set_delay(0.15)
	reward_tween.chain().tween_callback(floating_reward.queue_free)

func _gui_input(event: InputEvent) -> void:
	var is_press: bool = (
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if is_press and charges > 0:
		job_requested.emit(event.position)
		accept_event()

func _draw() -> void:
	if size.x <= 0.0 or not is_instance_valid(art_spacer):
		return
	# Match the fixed VBox art slot. Using global child coordinates here can
	# capture the pre-layout position during the first draw on some devices.
	var art := Rect2(8.0, 16.0, size.x - 16.0, 61.0)
	var background := Color("#07120d")
	var frame := Color("#22563a")
	var structure := Color("#4d6b59")
	var accent := Color("#22c55e").lerp(Color("#b8ffca"), activity_flash)
	var cool := Color("#22b8e6").lerp(Color("#b8f4ff"), activity_flash)
	draw_rect(art, background)
	draw_rect(art, frame, false, 2.0)

	match site_tier:
		1:
			_draw_rented_closet(art, structure, accent)
		2:
			_draw_colo_suite(art, structure, accent, cool)
		3:
			_draw_purpose_built(art, structure, accent, cool)
		4:
			_draw_nordic_campus(art, structure, accent, cool)
		_:
			_draw_hyperscale(art, structure, accent, cool)

func _draw_rack(rect: Rect2, body: Color, lights: Color) -> void:
	draw_rect(rect, body)
	draw_rect(Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4)), Color("#091711"))
	var row_height: float = max(floor((rect.size.y - 6.0) / 4.0), 2.0)
	for row in range(4):
		var y: float = rect.position.y + 3.0 + row * row_height
		draw_rect(Rect2(rect.position.x + 3.0, y, rect.size.x - 6.0, 2.0), body.lightened(0.25))
		draw_rect(Rect2(rect.end.x - 6.0, y, 2.0, 2.0), lights)

func _draw_rented_closet(art: Rect2, structure: Color, accent: Color) -> void:
	var room := Rect2(art.position + Vector2(16, 8), Vector2(art.size.x - 32, art.size.y - 16))
	draw_rect(room, structure, false, 2.0)
	_draw_rack(Rect2(room.position + Vector2(10, 7), Vector2(30, room.size.y - 14)), structure, accent)
	var door := Rect2(room.end - Vector2(38, room.size.y - 7), Vector2(24, room.size.y - 7))
	draw_rect(door, Color("#14251b"))
	draw_rect(door, structure, false, 2.0)
	draw_rect(Rect2(door.end - Vector2(6, door.size.y / 2), Vector2(2, 2)), accent)

func _draw_colo_suite(art: Rect2, structure: Color, accent: Color, cool: Color) -> void:
	draw_rect(Rect2(art.position + Vector2(8, 8), Vector2(art.size.x - 16, art.size.y - 16)), structure, false, 2.0)
	for i in range(3):
		_draw_rack(Rect2(art.position + Vector2(24 + i * 56, 15), Vector2(34, 38)), structure, accent)
	for i in range(3):
		draw_rect(Rect2(art.end.x - 52 + i * 12, art.position.y + 18, 6, 6), cool)

func _draw_purpose_built(art: Rect2, structure: Color, accent: Color, cool: Color) -> void:
	# One large, purpose-built shell with rooftop plant, a central entrance,
	# and utility equipment on both sides.
	draw_rect(Rect2(art.position + Vector2(10, 57), Vector2(art.size.x - 20, 3)), structure.darkened(0.2))
	var building := Rect2(art.position + Vector2(32, 19), Vector2(art.size.x - 64, 38))
	draw_rect(building, Color("#10231c"))
	draw_rect(building, structure, false, 2.0)
	draw_rect(Rect2(building.position + Vector2(2, 7), Vector2(building.size.x - 4, 3)), cool.darkened(0.25))
	for i in range(3):
		var roof_unit := Rect2(building.position + Vector2(26 + i * 82, -8), Vector2(34, 8))
		draw_rect(roof_unit, Color("#172b21"))
		draw_rect(roof_unit, structure, false, 2.0)
		draw_rect(Rect2(roof_unit.position + Vector2(6, 2), Vector2(5, 4)), cool)
		draw_rect(Rect2(roof_unit.position + Vector2(22, 2), Vector2(5, 4)), cool)
	for i in range(3):
		draw_rect(Rect2(building.position + Vector2(13 + i * 31, 16), Vector2(15, 7)), accent)
		draw_rect(Rect2(building.position + Vector2(174 + i * 31, 16), Vector2(15, 7)), accent)
	var entrance := Rect2(building.position + Vector2(building.size.x / 2 - 14, 17), Vector2(28, 21))
	draw_rect(entrance, Color("#07120d"))
	draw_rect(entrance, cool, false, 2.0)
	draw_rect(Rect2(entrance.position + Vector2(12, 5), Vector2(4, 16)), accent)
	var transformer := Rect2(art.position + Vector2(10, 36), Vector2(17, 19))
	draw_rect(transformer, Color("#172b21"))
	draw_rect(transformer, structure, false, 2.0)
	draw_rect(Rect2(transformer.position + Vector2(5, 5), Vector2(7, 3)), accent)
	var cooling_tank := Rect2(art.end - Vector2(27, 28), Vector2(17, 26))
	draw_rect(cooling_tank, Color("#172b21"))
	draw_rect(cooling_tank, cool, false, 2.0)
	draw_rect(Rect2(cooling_tank.position + Vector2(3, 7), Vector2(11, 3)), cool)

func _draw_nordic_campus(art: Rect2, structure: Color, accent: Color, cool: Color) -> void:
	# A cold-climate campus: two long data halls, snow-covered roofs,
	# rooftop air handlers, snowy ground, and pine trees.
	for i in range(8):
		draw_rect(Rect2(art.position + Vector2(20 + i * 39, 5 + (i % 3) * 3), Vector2(2, 2)), cool.lightened(0.3))
	var rear_hall := Rect2(art.position + Vector2(35, 17), Vector2(126, 27))
	_draw_nordic_hall(rear_hall, structure, accent, cool, 5)
	var front_hall := Rect2(art.position + Vector2(132, 27), Vector2(165, 29))
	_draw_nordic_hall(front_hall, structure, accent, cool, 7)
	for i in range(3):
		var air_handler := Rect2(rear_hall.position + Vector2(18 + i * 34, -10), Vector2(22, 7))
		draw_rect(air_handler, Color("#172b21"))
		draw_rect(air_handler, cool, false, 2.0)
	for i in range(4):
		var air_handler := Rect2(front_hall.position + Vector2(17 + i * 35, -9), Vector2(23, 7))
		draw_rect(air_handler, Color("#172b21"))
		draw_rect(air_handler, cool, false, 2.0)
	draw_rect(Rect2(art.position + Vector2(5, 57), Vector2(art.size.x - 10, 4)), cool.lightened(0.25))
	_draw_pixel_pine(art.position + Vector2(17, 56), structure, cool)
	_draw_pixel_pine(art.position + Vector2(314, 56), structure, cool)

func _draw_nordic_hall(hall: Rect2, structure: Color, accent: Color, cool: Color, window_count: int) -> void:
	draw_rect(hall, Color("#0d211b"))
	draw_rect(hall, structure, false, 2.0)
	draw_rect(Rect2(hall.position + Vector2(-4, -5), Vector2(hall.size.x + 8, 3)), cool.darkened(0.1))
	draw_rect(Rect2(hall.position + Vector2(0, -8), Vector2(hall.size.x, 3)), cool.lightened(0.2))
	var spacing: float = (hall.size.x - 16.0) / float(window_count)
	for i in range(window_count):
		draw_rect(Rect2(hall.position + Vector2(8 + i * spacing, 12), Vector2(8, 6)), accent if i % 2 == 0 else cool)

func _draw_pixel_pine(base: Vector2, trunk: Color, snow: Color) -> void:
	draw_rect(Rect2(base + Vector2(-1, -8), Vector2(3, 8)), trunk)
	draw_rect(Rect2(base + Vector2(-7, -13), Vector2(15, 4)), snow.darkened(0.35))
	draw_rect(Rect2(base + Vector2(-5, -17), Vector2(11, 4)), snow.darkened(0.25))
	draw_rect(Rect2(base + Vector2(-3, -21), Vector2(7, 4)), snow)

func _draw_hyperscale(art: Rect2, structure: Color, accent: Color, cool: Color) -> void:
	# Four large data halls form a region-scale campus. Each hall has its own
	# rooftop cooling skids and alternating compute/network activity lights.
	var region_accent: Color = Color("#9d7cff").lerp(Color("#e3dbff"), activity_flash)
	for row in range(2):
		for col in range(2):
			var hall := Rect2(art.position + Vector2(10 + col * 158, 14 + row * 23), Vector2(148, 18))
			_draw_hyperscale_hall(hall, structure, accent, cool, region_accent, row + col)
	draw_rect(Rect2(art.position + Vector2(6, 58), Vector2(art.size.x - 12, 3)), structure.darkened(0.2))
	for marker in range(8):
		var marker_color: Color = region_accent if marker % 2 == 0 else cool
		draw_rect(Rect2(art.position + Vector2(19 + marker * 40, 59), Vector2(14, 1)), marker_color.darkened(0.2))
	draw_rect(Rect2(art.position + Vector2(5, 6), Vector2(3, 3)), region_accent)
	draw_rect(Rect2(art.end - Vector2(8, 55), Vector2(3, 3)), region_accent)

func _draw_hyperscale_hall(
	hall: Rect2,
	structure: Color,
	accent: Color,
	cool: Color,
	region_accent: Color,
	phase: int
) -> void:
	draw_rect(hall, Color("#0d211b"))
	draw_rect(hall, structure, false, 2.0)
	draw_rect(Rect2(hall.position + Vector2(3, 3), Vector2(hall.size.x - 6, 2)), region_accent.darkened(0.2))
	for unit in range(4):
		var cooling_skid := Rect2(hall.position + Vector2(11 + unit * 32, -5), Vector2(20, 5))
		draw_rect(cooling_skid, Color("#172b21"))
		draw_rect(cooling_skid, cool if unit % 2 == 0 else region_accent, false, 1.0)
	for light in range(9):
		var light_cycle: int = (light + phase) % 4
		var light_color: Color = region_accent if light_cycle == 0 else (cool if light_cycle == 1 else accent)
		draw_rect(Rect2(hall.position + Vector2(8 + light * 14, 8), Vector2(7, 5)), light_color)
	var service_door := Rect2(hall.end - Vector2(17, 7), Vector2(10, 7))
	draw_rect(service_door, Color("#07120d"))
	draw_rect(service_door, region_accent, false, 1.0)
