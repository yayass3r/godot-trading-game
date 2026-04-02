## ============================================
## ChallengesUI.gd - واجهة التحديات اليومية والأسبوعية
## تعرض التحديات النشطة مع تقدمها ومكافآتها
## ============================================
extends Control

const NP = preload("res://scripts/enums/notification_priority.gd")

## ---- Node References ----
@onready var back_button: Button = $BackButton
@onready var daily_title: Label = $ScrollContainer/VBoxContainer/DailySection/DailyTitle
@onready var daily_container: VBoxContainer = $ScrollContainer/VBoxContainer/DailySection/ChallengeContainer
@onready var weekly_title: Label = $ScrollContainer/VBoxContainer/WeeklySection/WeeklyTitle
@onready var weekly_container: VBoxContainer = $ScrollContainer/VBoxContainer/WeeklySection/ChallengeContainer
@onready var streak_label: Label = $ScrollContainer/VBoxContainer/StreakInfo/StreakLabel

## ---- Manager References ----
@onready var challenge_manager: Node = get_node_or_null("/root/ChallengeManager")

## ============================================
## _ready() - Initialize UI and connect signals
## ============================================
func _ready() -> void:
        if back_button:
                back_button.pressed.connect(_on_back_pressed)

        _connect_manager_signals()
        _refresh_challenges()

func _connect_manager_signals() -> void:
        if challenge_manager:
                challenge_manager.daily_challenges_refreshed.connect(_on_daily_refreshed)
                challenge_manager.weekly_challenges_refreshed.connect(_on_weekly_refreshed)
                challenge_manager.challenge_progress_updated.connect(_on_progress_updated)
                challenge_manager.challenge_completed.connect(_on_challenge_completed)
                challenge_manager.streak_updated.connect(_on_streak_updated)

## ============================================
## Refresh all challenge displays
## ============================================
func _refresh_challenges() -> void:
        _update_daily_section()
        _update_weekly_section()
        _update_streak()

## ============================================
## Update daily challenges section
## ============================================
func _update_daily_section() -> void:
        if not daily_container:
                return

        ## Clear existing cards
        for child in daily_container.get_children():
                child.queue_free()

        if not challenge_manager:
                return

        var challenges: Array = challenge_manager.active_daily_challenges
        for challenge in challenges:
                var card := _create_challenge_card(challenge)
                daily_container.add_child(card)

## ============================================
## Update weekly challenges section
## ============================================
func _update_weekly_section() -> void:
        if not weekly_container:
                return

        ## Clear existing cards
        for child in weekly_container.get_children():
                child.queue_free()

        if not challenge_manager:
                return

        var challenges: Array = challenge_manager.active_weekly_challenges
        for challenge in challenges:
                var card := _create_challenge_card(challenge)
                weekly_container.add_child(card)

## ============================================
## Create a single challenge card
## ============================================
func _create_challenge_card(challenge: Dictionary) -> PanelContainer:
        var card := PanelContainer.new()
        card.add_theme_stylebox_override("panel", _get_card_style())

        var vbox := VBoxContainer.new()
        card.add_child(vbox)

        ## Challenge name + difficulty
        var header := HBoxContainer.new()
        vbox.add_child(header)

        var title_lbl := Label.new()
        title_lbl.text = str(challenge.get("name", "Challenge"))
        title_lbl.add_theme_font_size_override("font_size", 18)
        header.add_child(title_lbl)

        header.add_child(Control.new())  ## spacer

        var diff_lbl := Label.new()
        var difficulty: int = challenge.get("difficulty", 0)
        var diff_names := ["Easy", "Medium", "Hard", "Expert"]
        diff_lbl.text = diff_names[difficulty] if difficulty < diff_names.size() else "Unknown"
        diff_lbl.add_theme_color_override("font_color", _difficulty_color(difficulty))
        header.add_child(diff_lbl)

        ## Description
        var desc_lbl := Label.new()
        desc_lbl.text = str(challenge.get("description", ""))
        desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        vbox.add_child(desc_lbl)

        ## Progress bar
        var progress := ProgressBar.new()
        var progress_data: Dictionary = _get_challenge_progress(challenge.get("id", ""))
        progress.max_value = float(challenge.get("target", 100))
        progress.value = float(progress_data.get("current", 0))
        progress.custom_minimum_size.y = 20
        vbox.add_child(progress)

        ## Progress text
        var progress_lbl := Label.new()
        progress_lbl.text = "%d / %d" % [int(progress.value), int(progress.max_value)]
        vbox.add_child(progress_lbl)

        ## Rewards
        var reward_lbl := Label.new()
        var xp_reward: int = challenge.get("xp_reward", 0)
        var balance_reward: float = challenge.get("balance_reward", 0.0)
        reward_lbl.text = "Reward: %d XP + $%.0f" % [xp_reward, balance_reward]
        reward_lbl.add_theme_color_override("font_color", Color.GOLD)
        vbox.add_child(reward_lbl)

        ## Completed overlay
        if progress_data.get("completed", false):
                var done_lbl := Label.new()
                done_lbl.text = "COMPLETED"
                done_lbl.add_theme_color_override("font_color", Color.GREEN)
                done_lbl.add_theme_font_size_override("font_size", 16)
                done_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                vbox.add_child(done_lbl)

        return card

## ============================================
## Get progress data for a challenge
## ============================================
func _get_challenge_progress(challenge_id: String) -> Dictionary:
        if not challenge_manager:
                return {"current": 0, "completed": false}
        if challenge_manager.challenge_progress is Dictionary and challenge_manager.challenge_progress.has(challenge_id):
                return challenge_manager.challenge_progress[challenge_id]
        return {"current": 0, "completed": false}

## ============================================
## Update streak display
## ============================================
func _update_streak() -> void:
        if not streak_label or not challenge_manager:
                return
        streak_label.text = "Daily Streak: %d (Best: %d)" % [
                challenge_manager.daily_streak,
                challenge_manager.best_daily_streak
        ]

## ============================================
## Signal handlers
## ============================================
func _on_daily_refreshed(_challenges: Array) -> void:
        _update_daily_section()

func _on_weekly_refreshed(_challenges: Array) -> void:
        _update_weekly_section()

func _on_progress_updated(_challenge_id: String, _current: int, _target: int) -> void:
        _refresh_challenges()

func _on_challenge_completed(challenge_id: String, rewards: Dictionary) -> void:
        NotificationManager.send_notification(
                "Challenge Completed!",
                "%s — %d XP + $%.0f" % [
                        challenge_id,
                        rewards.get("xp", 0),
                        rewards.get("balance", 0.0)
                ],
                NP.SUCCESS
        )
        _refresh_challenges()

func _on_streak_updated(current_streak: int, best_streak: int) -> void:
        _update_streak()

## ============================================
## Helpers
## ============================================
func _difficulty_color(difficulty: int) -> Color:
        match difficulty:
                0: return Color.GREEN     ## Easy
                1: return Color.YELLOW    ## Medium
                2: return Color.ORANGE    ## Hard
                3: return Color.RED       ## Expert
                _: return Color.WHITE

func _get_card_style() -> StyleBoxFlat:
        var style := StyleBoxFlat.new()
        style.bg_color = Color(0.12, 0.12, 0.18, 0.9)
        style.border_color = Color(0.3, 0.3, 0.4)
        style.border_width_top = 1
        style.border_width_bottom = 1
        style.set_corner_radius_all(8)
        style.content_margin_left = 12.0
        style.content_margin_right = 12.0
        style.content_margin_top = 8.0
        style.content_margin_bottom = 8.0
        return style

## ============================================
## Back to main menu
## ============================================
func _on_back_pressed() -> void:
        get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
