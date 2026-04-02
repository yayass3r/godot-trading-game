extends Control

func _ready():
		$Background.color = Color(0.08, 0.08, 0.12, 1.0)
		$VBoxContainer/TitleLabel.add_theme_font_size_override("font_size", 36)
		$VBoxContainer/TitleLabel.add_theme_color_override("font_color", Color(0.0, 0.9, 0.5, 1.0))

		for btn in $VBoxContainer.get_children():
				if btn is Button:
						btn.pressed.connect(_on_menu_button_pressed.bind(btn.name))
						btn.add_theme_font_size_override("font_size", 22)

func _on_menu_button_pressed(btn_name: String):
		match btn_name:
				"PlayButton":
						get_tree().change_scene_to_file("res://scenes/trading/trading_scene.tscn")
				"ChartsButton":
						get_tree().change_scene_to_file("res://scenes/charts/chart_scene.tscn")
				"ProfileButton":
						get_tree().change_scene_to_file("res://scenes/profile/profile_scene.tscn")
				"ForumButton":
						get_tree().change_scene_to_file("res://scenes/forum/forum_scene.tscn")
				"LeaderboardButton":
						get_tree().change_scene_to_file("res://scenes/leaderboard/leaderboard_scene.tscn")
				"ChallengesButton":
						get_tree().change_scene_to_file("res://scenes/challenges/challenges_scene.tscn")
				"TutorialsButton":
						get_tree().change_scene_to_file("res://scenes/tutorials/tutorial_scene.tscn")
				"SettingsButton":
						get_tree().change_scene_to_file("res://scenes/settings/settings_scene.tscn")
