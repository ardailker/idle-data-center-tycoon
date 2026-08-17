extends RefCounted
class_name PixelIcons

## Procedurally generates blocky pixel-art icon textures at runtime.
## No image assets: each icon is an 8x8 glyph on a 1px border, baked into
## an Image where every logical pixel is drawn as a pixel_scale x pixel_scale
## solid block, keeping the project's zero-art-asset premise (GAME_SPEC.md §1).

const GRID_SIZE: int = 10 # 1px border + 8px interior + 1px border

static func _icon_rows(icon_id: String) -> Array:
	match icon_id:
		"rack_1u":
			return [
				"........",
				"........",
				"........",
				"AAAAAAAA",
				"........",
				"........",
				"........",
				"........",
			]
		"blade_chassis":
			return [
				"........",
				"AAAAAAAA",
				"........",
				"AAAAAAAA",
				"........",
				"AAAAAAAA",
				"........",
				"........",
			]
		"gpu_pod":
			return [
				".AAAAAA.",
				"A......A",
				"A.BBBB.A",
				"A.BBBB.A",
				"A.BBBB.A",
				"A.BBBB.A",
				"A......A",
				".AAAAAA.",
			]
		"edge_cluster":
			return [
				"AA....AA",
				".AA..AA.",
				"..AAAA..",
				"A.BBBB.A",
				"A.BBBB.A",
				"..AAAA..",
				".AA..AA.",
				"AA....AA",
			]
		"ai_superpod":
			return [
				"AAAAAAAA",
				"A.BBB..A",
				"A.BBB..A",
				"AAAAAAAA",
				"A..BBB.A",
				"A..BBB.A",
				"AAAAAAAA",
				".AA..AA.",
			]
		"pdu":
			return [
				"........",
				".A....A.",
				".A....A.",
				".AAAAAA.",
				".A....A.",
				".A....A.",
				".A....A.",
				"........",
			]
		"ups_transformer":
			return [
				"..AAAA..",
				".AAAAAA.",
				"A.BBBB.A",
				"A......A",
				"A.BBBB.A",
				"A......A",
				"A.BBBB.A",
				".AAAAAA.",
			]
		"diesel_gen":
			return [
				".AAAAAA.",
				"A.BBBB.A",
				"AAAAAAAA",
				"A......A",
				"AAAAAAAA",
				"A......A",
				"A.BBBB.A",
				".AAAAAA.",
			]
		"modular_substation":
			return [
				"..AAAA..",
				".AA..AA.",
				"AA.BB.AA",
				"AAAAAAAA",
				"AA.BB.AA",
				".AA..AA.",
				"..AAAA..",
				"AA....AA",
			]
		"battery_farm":
			return [
				"..AAAA..",
				"AAAAAAAA",
				"A......A",
				"A.BB...A",
				"A.BBBB.A",
				"A.BB...A",
				"A......A",
				"AAAAAAAA",
			]
		"crac_unit":
			return [
				"...AA...",
				"...AA...",
				"A..AA..A",
				"AAAAAAAA",
				"AAAAAAAA",
				"A..AA..A",
				"...AA...",
				"...AA...",
			]
		"chilled_water_plant":
			return [
				"...AA...",
				"..AAAA..",
				".AAAAAA.",
				"AAAAAAAA",
				"AAAAAAAA",
				".AAAAAA.",
				"..AAAA..",
				"...AA...",
			]
		"economizer":
			return [
				"A.......",
				".A......",
				"..AAAAA.",
				".......A",
				"A.......",
				".A......",
				"..AAAAA.",
				".......A",
			]
		"inrow_cooling":
			return [
				"A..AA..A",
				".A.AA.A.",
				"..AAAA..",
				"AAAAAAAA",
				"AAAAAAAA",
				"..AAAA..",
				".A.AA.A.",
				"A..AA..A",
			]
		"immersion_plant":
			return [
				"AAAAAAAA",
				"A......A",
				"A.B..B.A",
				"A.BBBB.A",
				"A.BBBB.A",
				"A.B..B.A",
				"A......A",
				"AAAAAAAA",
			]
		"settings_gear":
			return [
				"...AA...",
				".A.AA.A.",
				"AAA..AAA",
				".A....A.",
				".A....A.",
				"AAA..AAA",
				".A.AA.A.",
				"...AA...",
			]
		_:
			return [
				"........",
				".AAAAAA.",
				".A....A.",
				".A....A.",
				".A....A.",
				".A....A.",
				".AAAAAA.",
				"........",
			]

## Builds a fully opaque-per-pixel blocky icon texture for the given catalog id.
## accent_color is the border + primary glyph color; a lightened variant is used
## for the secondary "B" glyph pixels.
static func build_icon_texture(
	icon_id: String,
	accent_color: Color,
	pixel_scale: int = 4,
	draw_frame: bool = true
) -> ImageTexture:
	var interior: Array = _icon_rows(icon_id)
	var img_size: int = GRID_SIZE * pixel_scale
	var image := Image.create(img_size, img_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var highlight: Color = accent_color.lightened(0.55)

	# Optional outer frame used by equipment icons; UI symbols stay frameless.
	if draw_frame:
		for i in range(GRID_SIZE):
			_paint_cell(image, i, 0, accent_color, pixel_scale)
			_paint_cell(image, i, GRID_SIZE - 1, accent_color, pixel_scale)
			_paint_cell(image, 0, i, accent_color, pixel_scale)
			_paint_cell(image, GRID_SIZE - 1, i, accent_color, pixel_scale)

	# Interior glyph, offset by (1,1) inside the border
	for y in range(interior.size()):
		var row: String = interior[y]
		for x in range(row.length()):
			var ch: String = row[x]
			if ch == "A":
				_paint_cell(image, x + 1, y + 1, accent_color, pixel_scale)
			elif ch == "B":
				_paint_cell(image, x + 1, y + 1, highlight, pixel_scale)

	return ImageTexture.create_from_image(image)

static func _paint_cell(image: Image, cx: int, cy: int, color: Color, pixel_scale: int) -> void:
	var start_x: int = cx * pixel_scale
	var start_y: int = cy * pixel_scale
	for px in range(pixel_scale):
		for py in range(pixel_scale):
			image.set_pixel(start_x + px, start_y + py, color)
