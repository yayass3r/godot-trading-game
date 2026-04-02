extends Control

func _ready():
	_load_settings()
	_connect_buttons()

func _load_settings():
	if GameManager:
		var settings = GameManager.settings
		$ScrollContainer/VBoxContainer/SoundPanel/MasterVolume.value = settings.get("master_volume", 0.8)
		$ScrollContainer/VBoxContainer/SoundPanel/SFXVolume.value = settings.get("sfx_volume", 0.7)
		$ScrollContainer/VBoxContainer/SoundPanel/AmbientVolume.value = settings.get("ambient_volume", 0.5)
		$ScrollContainer/VBoxContainer/SoundPanel/MuteToggle.button_pressed = settings.get("muted", false)
		$ScrollContainer/VBoxContainer/AccountPanel/NameInput.text = settings.get("player_name", "Trader")
		$ScrollContainer/VBoxContainer/ThemePanel/ThemeOption.selected = settings.get("theme", 0)

func _connect_buttons():
	$VBoxContainer/BackButton.pressed.connect(_on_back_pressed)
	$ScrollContainer/VBoxContainer/SaveButton.pressed.connect(_on_save_pressed)
	$ScrollContainer/VBoxContainer/AccountPanel/ResetButton.pressed.connect(_on_reset_pressed)

func _on_save_pressed():
	if GameManager:
		GameManager.settings["master_volume"] = $ScrollContainer/VBoxContainer/SoundPanel/MasterVolume.value
		GameManager.settings["sfx_volume"] = $ScrollContainer/VBoxContainer/SoundPanel/SFXVolume.value
		GameManager.settings["ambient_volume"] = $ScrollContainer/VBoxContainer/SoundPanel/AmbientVolume.value
		GameManager.settings["muted"] = $ScrollContainer/VBoxContainer/SoundPanel/MuteToggle.button_pressed
		GameManager.settings["player_name"] = $ScrollContainer/VBoxContainer/AccountPanel/NameInput.text
		GameManager.settings["theme"] = $ScrollContainer/VBoxContainer/ThemePanel/ThemeOption.selected
		GameManager.save_settings()

func _on_reset_pressed():
	if PortfolioManager:
		PortfolioManager.reset_portfolio()
	if ProfileManager:
		ProfileManager.reset_profile()
	if NotificationManager:
		NotificationManager.show_notification("Reset", "All progress has been reset!")

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
