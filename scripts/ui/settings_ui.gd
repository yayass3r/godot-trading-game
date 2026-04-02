## ============================================
## SettingsUI.gd - واجهة الإعدادات
## تتحكم في الصوت والحساب والمظهر مع حفظ محلي
## ============================================
extends Control

const NP = preload("res://scripts/enums/notification_priority.gd")

## ---- Node References ----
@onready var back_button: Button = $BackButton
@onready var save_button: Button = $ScrollContainer/MainVBox/AccountPanel/AccountContent/SaveButton
@onready var reset_button: Button = $ScrollContainer/MainVBox/AccountPanel/AccountContent/ResetButton

## Sound settings nodes
@onready var master_volume: HSlider = $ScrollContainer/MainVBox/SoundPanel/SoundContent/MasterVolumeRow/MasterVolumeSlider
@onready var sfx_volume: HSlider = $ScrollContainer/MainVBox/SoundPanel/SoundContent/SFXVolumeRow/SFXVolumeSlider
@onready var ambient_volume: HSlider = $ScrollContainer/MainVBox/SoundPanel/SoundContent/AmbientVolumeRow/AmbientVolumeSlider
@onready var mute_toggle: CheckButton = $ScrollContainer/MainVBox/SoundPanel/SoundContent/MuteToggle

## Account settings nodes
@onready var name_input: LineEdit = $ScrollContainer/MainVBox/AccountPanel/AccountContent/NameEditRow/NameInput

## Theme settings nodes
@onready var theme_option: OptionButton = $ScrollContainer/MainVBox/ThemePanel/ThemeContent/ThemeOptions

## ---- Manager References ----
@onready var profile_manager: Node = get_node_or_null("/root/ProfileManager")
@onready var sound_manager: Node = get_node_or_null("/root/SoundManager")

## ---- Settings file path ----
const SETTINGS_PATH: String = "user://settings.json"

## ---- Default settings ----
var settings: Dictionary = {
        "master_volume": 0.8,
        "sfx_volume": 0.7,
        "ambient_volume": 0.5,
        "muted": false,
        "player_name": "Trader",
        "theme": 0,
}

## ============================================
## _ready() - Load settings and connect buttons
## ============================================
func _ready() -> void:
        if back_button:
                back_button.pressed.connect(_on_back_pressed)
        if save_button:
                save_button.pressed.connect(_on_save_pressed)
        if reset_button:
                reset_button.pressed.connect(_on_reset_pressed)

        _load_settings()

## ============================================
## Load settings from local JSON file
## ============================================
func _load_settings() -> void:
        if not FileAccess.file_exists(SETTINGS_PATH):
                _apply_settings_to_ui()
                return

        var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
        if file == null:
                _apply_settings_to_ui()
                return

        var json := JSON.new()
        if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
                file.close()
                _apply_settings_to_ui()
                return

        file.close()
        var data: Dictionary = json.data
        for key in settings:
                if data.has(key):
                        settings[key] = data[key]

        _apply_settings_to_ui()

## ============================================
## Apply settings dictionary to UI controls
## ============================================
func _apply_settings_to_ui() -> void:
        if master_volume:
                master_volume.value = settings.get("master_volume", 0.8) * 100.0
        if sfx_volume:
                sfx_volume.value = settings.get("sfx_volume", 0.7) * 100.0
        if ambient_volume:
                ambient_volume.value = settings.get("ambient_volume", 0.5) * 100.0
        if mute_toggle:
                mute_toggle.button_pressed = settings.get("muted", false)
        if name_input:
                name_input.text = settings.get("player_name", "Trader")
        if theme_option:
                theme_option.selected = settings.get("theme", 0)

## ============================================
## Save settings to local JSON file
## ============================================
func _on_save_pressed() -> void:
        _read_settings_from_ui()
        _save_settings_to_file()
        _apply_player_name()

        NotificationManager.send_notification(
                "Settings Saved",
                "Your settings have been saved successfully",
                NP.SUCCESS
        )

func _read_settings_from_ui() -> void:
        if master_volume:
                settings["master_volume"] = master_volume.value / 100.0
        if sfx_volume:
                settings["sfx_volume"] = sfx_volume.value / 100.0
        if ambient_volume:
                settings["ambient_volume"] = ambient_volume.value / 100.0
        if mute_toggle:
                settings["muted"] = mute_toggle.button_pressed
        if name_input:
                settings["player_name"] = name_input.text
        if theme_option:
                settings["theme"] = theme_option.selected

func _save_settings_to_file() -> void:
        var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
        if file:
                file.store_string(JSON.stringify(settings, "\t"))
                file.close()
        else:
                push_error("[SettingsUI] Failed to save settings to %s" % SETTINGS_PATH)

## ============================================
## Apply player name to ProfileManager
## ============================================
func _apply_player_name() -> void:
        var new_name: String = settings.get("player_name", "")
        if profile_manager and not new_name.is_empty():
                profile_manager.player_name = new_name

## ============================================
## Reset all progress
## ============================================
func _on_reset_pressed() -> void:
        ## Reset profile balance and stats
        if profile_manager:
                profile_manager.balance = 100000.0
                profile_manager.total_trades = 0
                profile_manager.winning_trades = 0
                profile_manager.losing_trades = 0
                profile_manager.biggest_win = 0.0
                profile_manager.biggest_loss = 0.0
                profile_manager.total_profit = 0.0
                profile_manager.total_fees_paid = 0.0
                profile_manager.current_streak = 0
                profile_manager.best_streak = 0
                profile_manager.total_volume_traded = 0.0
                profile_manager.total_xp = 0
                profile_manager.current_level_xp = 0
                profile_manager.level = 1
                profile_manager.earned_badges.clear()
                if profile_manager.has_method("save_profile"):
                        profile_manager.save_profile()

        ## Clear portfolio open trades
        var portfolio_manager: Node = get_node_or_null("/root/PortfolioManager")
        if portfolio_manager:
                for trade in portfolio_manager.open_trades.duplicate():
                        if portfolio_manager.has_method("remove_trade"):
                                portfolio_manager.remove_trade(trade)

        ## Clear challenge progress
        var challenge_manager: Node = get_node_or_null("/root/ChallengeManager")
        if challenge_manager:
                challenge_manager.completed_challenges.clear()
                challenge_manager.challenge_progress.clear()
                if challenge_manager.has_method("save_challenge_data"):
                        challenge_manager.save_challenge_data()

        ## Reset settings to defaults
        settings = {
                "master_volume": 0.8,
                "sfx_volume": 0.7,
                "ambient_volume": 0.5,
                "muted": false,
                "player_name": "Trader",
                "theme": 0,
        }
        _apply_settings_to_ui()
        _save_settings_to_file()

        NotificationManager.send_notification(
                "Progress Reset",
                "All progress has been reset to defaults",
                NP.WARNING
        )

## ============================================
## Back to main menu
## ============================================
func _on_back_pressed() -> void:
        get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
