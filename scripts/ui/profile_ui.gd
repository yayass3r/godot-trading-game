## ============================================
## ProfileUI.gd - واجهة الملف الشخصي
## تعرض المستوى والخبرة والأوسمة والإحصائيات
## ============================================
extends Control

## ---- Node References ----
@onready var avatar_texture: TextureRect = $ScrollContainer/MainVBox/ProfileCard/CardContent/AvatarTexture
@onready var name_label: Label = $ScrollContainer/MainVBox/ProfileCard/CardContent/NameLabel
@onready var level_label: Label = $ScrollContainer/MainVBox/ProfileCard/CardContent/LevelLabel
@onready var xp_bar: ProgressBar = $ScrollContainer/MainVBox/ProfileCard/CardContent/XPBar
@onready var xp_label: Label = $ScrollContainer/MainVBox/ProfileCard/CardContent/XPLabel
@onready var balance_label: Label = $ScrollContainer/MainVBox/StatsPanel/StatsGrid/BalanceLabel
@onready var total_trades_label: Label = $ScrollContainer/MainVBox/StatsPanel/StatsGrid/TotalTradesLabel
@onready var win_rate_label: Label = $ScrollContainer/MainVBox/StatsPanel/StatsGrid/WinRateLabel
@onready var biggest_win_label: Label = $ScrollContainer/MainVBox/StatsPanel/StatsGrid/BiggestWinLabel
@onready var profit_label: Label = $ScrollContainer/MainVBox/StatsPanel/StatsGrid/ProfitLabel
@onready var streak_label: Label = $ScrollContainer/MainVBox/StatsPanel/StatsGrid/StreakLabel
@onready var badge_grid: GridContainer = $ScrollContainer/MainVBox/BadgesPanel/BadgeGrid
@onready var back_button: Button = $BackButton

## ---- Manager References ----
@onready var profile_manager: Node = get_node_or_null("/root/ProfileManager")

## ============================================
## _ready() - Initialize UI and connect signals
## ============================================
func _ready() -> void:
        if back_button:
                back_button.pressed.connect(_on_back_pressed)

        if profile_manager:
                profile_manager.stats_updated.connect(_on_stats_updated)
                profile_manager.level_up.connect(_on_level_up)
                profile_manager.badge_earned.connect(_on_badge_earned)
                profile_manager.balance_updated.connect(_on_balance_updated)

        _refresh_display()

## ============================================
## Refresh all displayed data
## ============================================
func _refresh_display() -> void:
        if not profile_manager:
                return

        var stats: Dictionary = profile_manager.get_all_stats()

        ## Profile Card
        if name_label:
                name_label.text = str(stats.get("player_name", ""))
        if level_label:
                level_label.text = "Level %d" % stats.get("level", 1)
        if xp_bar:
                xp_bar.max_value = profile_manager.xp_to_next_level
                xp_bar.value = profile_manager.current_level_xp
        if xp_label:
                xp_label.text = "%d / %d XP" % [profile_manager.current_level_xp, profile_manager.xp_to_next_level]

        ## Stats
        if balance_label:
                balance_label.text = "$%.2f" % stats.get("balance", 0.0)
        if total_trades_label:
                total_trades_label.text = "%d trades" % stats.get("total_trades", 0)
        if win_rate_label:
                win_rate_label.text = "%.1f%%" % stats.get("win_rate", 0.0)
        if biggest_win_label:
                biggest_win_label.text = "$%.2f" % stats.get("biggest_win", 0.0)
        if profit_label:
                var sign := "+" if stats.get("total_profit", 0.0) > 0 else ""
                profit_label.text = "%s$%.2f" % [sign, stats.get("total_profit", 0.0)]
        if streak_label:
                streak_label.text = "%d streak" % stats.get("current_streak", 0)

        ## Badges
        _refresh_badges()

## ============================================
## Refresh badge display
## ============================================
func _refresh_badges() -> void:
        if not badge_grid or not profile_manager:
                return

        for child in badge_grid.get_children():
                child.queue_free()

        var all_badges: Dictionary = profile_manager.ALL_BADGES
        var earned: Array = profile_manager.earned_badges

        for badge_id in all_badges:
                var badge_data: Dictionary = all_badges[badge_id]
                var is_earned: bool = badge_id in earned

                var container := VBoxContainer.new()

                var emoji := "🏆" if is_earned else "🔒"
                var label := Label.new()
                label.text = emoji
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                label.add_theme_font_size_override("font_size", 24)
                container.add_child(label)

                var badge_name := Label.new()
                badge_name.text = str(badge_data.get("name", ""))
                badge_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                badge_name.add_theme_font_size_override("font_size", 10)
                if not is_earned:
                        badge_name.modulate = Color(0.5, 0.5, 0.5)
                container.add_child(badge_name)

                badge_grid.add_child(container)

## ============================================
## Signal handlers
## ============================================
func _on_stats_updated(_stats: Dictionary) -> void:
        _refresh_display()

func _on_level_up(_new_level: int, _rewards: Dictionary) -> void:
        _refresh_display()
        var tween := create_tween()
        tween.tween_property(self, "modulate", Color.YELLOW, 0.3)
        tween.tween_property(self, "modulate", Color.WHITE, 0.5)

func _on_badge_earned(_badge_id: String, _badge_name: String) -> void:
        _refresh_badges()

func _on_balance_updated(new_balance: float, delta: float) -> void:
        if balance_label:
                balance_label.text = "$%.2f" % new_balance
        var color := Color.GREEN if delta > 0 else Color.RED
        if balance_label:
                var tween := create_tween()
                tween.tween_property(balance_label, "modulate", color, 0.2)
                tween.tween_property(balance_label, "modulate", Color.WHITE, 0.3)

## ============================================
## Back to main menu
## ============================================
func _on_back_pressed() -> void:
        get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
