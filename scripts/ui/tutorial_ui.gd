extends Control

var current_tutorial: int = 0
var current_step: int = 0

@onready var _tutorial_mgr = get_node_or_null("/root/TutorialManager")
@onready var _profile_mgr = get_node_or_null("/root/ProfileManager")

func _ready():
	_connect_signals()
	_load_tutorials_list()

func _connect_signals():
	if _tutorial_mgr:
		_tutorial_mgr.tutorial_completed.connect(_on_tutorial_completed)

func _load_tutorials_list():
	var container = $VBoxContainer/TutorialsList
	if container:
		for child in container.get_children():
			child.queue_free()
		var tutorials = _tutorial_mgr.tutorials if _tutorial_mgr else []
		for i in range(tutorials.size()):
			var btn = Button.new()
			btn.text = tutorials[i].get("title", "Tutorial %d" % (i + 1))
			btn.pressed.connect(_select_tutorial.bind(i))
			container.add_child(btn)

func _select_tutorial(index: int):
	current_tutorial = index
	current_step = 0
	_show_lesson()

func _show_lesson():
	var tutorials = _tutorial_mgr.tutorials if _tutorial_mgr else []
	if current_tutorial < tutorials.size():
		var tutorial = tutorials[current_tutorial]
		var lessons = tutorial.get("lessons", [])
		if current_step < lessons.size():
			$VBoxContainer/LessonOverlay.visible = true
			$VBoxContainer/LessonOverlay/StepLabel.text = "Step %d/%d" % [current_step + 1, lessons.size()]
			$VBoxContainer/LessonOverlay/ContentLabel.text = lessons[current_step].get("content", "")
			var kp = lessons[current_step].get("key_points", [])
			$VBoxContainer/LessonOverlay/KeyPointsLabel.text = str(kp)

func _on_next_pressed():
	current_step += 1
	var tutorials = _tutorial_mgr.tutorials if _tutorial_mgr else []
	if current_tutorial < tutorials.size():
		var lessons = tutorials[current_tutorial].get("lessons", [])
		if current_step >= lessons.size():
			if _tutorial_mgr:
				_tutorial_mgr.complete_lesson(tutorials[current_tutorial].get("id", ""), current_step - 1)
			$VBoxContainer/LessonOverlay.visible = false
		else:
			_show_lesson()

func _on_prev_pressed():
	if current_step > 0:
		current_step -= 1
		_show_lesson()

func _on_tutorial_completed(_tutorial_id: String, _xp_earned: int):
	if _profile_mgr:
		_profile_mgr.add_experience(50)

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
