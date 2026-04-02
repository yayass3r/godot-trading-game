extends Control

func _ready():
	_connect_signals()
	_refresh_challenges()

func _connect_signals():
	if ChallengeManager:
		ChallengeManager.challenges_updated.connect(_on_challenges_updated)
		ChallengeManager.challenge_completed.connect(_on_challenge_completed)

func _refresh_challenges():
	if ChallengeManager:
		_update_daily_section()
		_update_weekly_section()

func _update_daily_section():
	var container = $ScrollContainer/VBoxContainer/DailySection/ChallengeContainer
	if container:
		for child in container.get_children():
			child.queue_free()
		var challenges = ChallengeManager.get_daily_challenges()
		for challenge in challenges:
			_create_challenge_card(container, challenge)

func _update_weekly_section():
	var container = $ScrollContainer/VBoxContainer/WeeklySection/ChallengeContainer
	if container:
		for child in container.get_children():
			child.queue_free()
		var challenges = ChallengeManager.get_weekly_challenges()
		for challenge in challenges:
			_create_challenge_card(container, challenge)

func _create_challenge_card(parent: Control, challenge: Dictionary):
	var card = PanelContainer.new()
	var vbox = VBoxContainer.new()
	var title = Label.new()
	title.text = challenge.get("title", "Challenge")
	title.add_theme_font_size_override("font_size", 18)
	var progress = ProgressBar.new()
	progress.max_value = challenge.get("target", 100)
	progress.value = challenge.get("progress", 0)
	var reward = Label.new()
	reward.text = "Reward: %d XP + $%.0f" % [challenge.get("xp_reward", 0), challenge.get("cash_reward", 0.0)]
	vbox.add_child(title)
	vbox.add_child(progress)
	vbox.add_child(reward)
	card.add_child(vbox)
	parent.add_child(card)

func _on_challenges_updated():
	_refresh_challenges()

func _on_challenge_completed(challenge_id: String):
	if NotificationManager:
		NotificationManager.show_notification("Challenge Completed!", "Challenge %s finished!" % challenge_id)

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
