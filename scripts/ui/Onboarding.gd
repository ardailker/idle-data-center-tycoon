extends Control
class_name Onboarding

const TIPS: Array[Dictionary] = [
	{
		"title": "RUN JOBS",
		"body": "Tap the data center to complete jobs and earn extra cash. Jobs recharge automatically, so use them whenever you check in."
	},
	{
		"title": "BALANCE THE LOAD",
		"body": "Every server needs power and cooling. Watch both gauges: amber means headroom is low, and red means production or uptime is at risk."
	},
	{
		"title": "SELL AND SCALE",
		"body": "Reach the Site Sale target to earn Tech Tokens. Equipment and cash reset, while research and unlocked sites stay with you."
	}
]

@onready var step_label: Label = $Center/Card/Margin/VBox/StepLabel
@onready var title_label: Label = $Center/Card/Margin/VBox/TitleLabel
@onready var body_label: Label = $Center/Card/Margin/VBox/BodyLabel
@onready var skip_btn: Button = $Center/Card/Margin/VBox/Actions/SkipBtn
@onready var next_btn: Button = $Center/Card/Margin/VBox/Actions/NextBtn

var current_tip: int = 0

func _ready() -> void:
	visible = false
	skip_btn.pressed.connect(func(): _complete(true))
	next_btn.pressed.connect(_advance)
	call_deferred("begin_if_needed")

func begin_if_needed() -> void:
	if bool(GameState.state.get("onboarding_completed", false)):
		visible = false
		return
	current_tip = 0
	visible = true
	_render_tip()

func _advance() -> void:
	if current_tip >= TIPS.size() - 1:
		_complete(false)
		return
	current_tip += 1
	_render_tip()

func _render_tip() -> void:
	var tip: Dictionary = TIPS[current_tip]
	step_label.text = "SYSTEM BRIEFING  %d / %d" % [current_tip + 1, TIPS.size()]
	title_label.text = String(tip.get("title", ""))
	body_label.text = String(tip.get("body", ""))
	next_btn.text = "GOT IT" if current_tip == TIPS.size() - 1 else "NEXT"

func _complete(skipped: bool) -> void:
	GameState.state["onboarding_completed"] = true
	visible = false
	if Analytics:
		Analytics.track_event(
			"onboarding_finished",
			{"skipped": skipped, "tips_viewed": current_tip + 1}
		)
	if SaveManager:
		SaveManager.save_game()
