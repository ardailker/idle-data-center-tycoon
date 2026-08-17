extends Range
class_name PixelGaugeBar

## Retro segmented meter (Game Boy / VU-meter style) replacing the smooth
## ProgressBar fill. Drop-in compatible with Range's min_value/max_value/value
## API so callers don't need to change beyond the node's class.

@export var segment_count: int = 16
@export var segment_gap: float = 2.0
@export var fill_color: Color = Color("#22c55e"):
	set(new_color):
		if fill_color == new_color:
			return
		fill_color = new_color
		queue_redraw()
@export var empty_color: Color = Color(0.13, 0.17, 0.14, 1)
@export var border_color: Color = Color(0.32, 0.42, 0.35, 1)

func _ready() -> void:
	changed.connect(queue_redraw) # Range limits affect ratio even if value is unchanged.
	resized.connect(queue_redraw)
	queue_redraw()

func _value_changed(_new_value: float) -> void:
	queue_redraw()

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or segment_count <= 0:
		return
	var seg_w: float = (size.x - segment_gap * float(segment_count - 1)) / float(segment_count)
	if seg_w <= 0.0:
		return
	var filled_segments: int = int(round(ratio * float(segment_count)))
	for i in range(segment_count):
		var x: float = i * (seg_w + segment_gap)
		var rect := Rect2(x, 0.0, seg_w, size.y)
		var color: Color = fill_color if i < filled_segments else empty_color
		draw_rect(rect, color, true)
		draw_rect(rect, border_color, false, 1.0)
