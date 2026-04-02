## ============================================
## ProfileUI.gd - واجهة الملف الشخصي
## تعرض المستوى والخبرة والأوسمة والإحصائيات
## ============================================
extends Control

## ---- عقد الواجهة ----
@onready var avatar_texture: TextureRect = $ProfileCard/AvatarTexture
@onready var name_label: Label = $ProfileCard/NameLabel
@onready var level_label: Label = $ProfileCard/LevelLabel
@onready var xp_bar: ProgressBar = $ProfileCard/XPBar
@onready var xp_label: Label = $ProfileCard/XPLabel
@onready var balance_label: Label = $StatsPanel/BalanceLabel
@onready var total_trades_label: Label = $StatsPanel/TotalTradesLabel
@onready var win_rate_label: Label = $StatsPanel/WinRateLabel
@onready var biggest_win_label: Label = $StatsPanel/BiggestWinLabel
@onready var profit_label: Label = $StatsPanel/ProfitLabel
@onready var streak_label: Label = $StatsPanel/StreakLabel
@onready var badge_grid: GridContainer = $BadgesPanel/BadgeGrid

## ---- مراجع الأنظمة ----
var profile_manager: Node

## ============================================
## التهيئة
## ============================================
func _ready() -> void:
        profile_manager = get_node_or_null("/root/GameManager/ProfileManager")
        
        if profile_manager:
                profile_manager.stats_updated.connect(_on_stats_updated)
                profile_manager.level_up.connect(_on_level_up)
                profile_manager.badge_earned.connect(_on_badge_earned)
                profile_manager.balance_updated.connect(_on_balance_updated)
        
        _refresh_display()

## ============================================
## تحديث كل البيانات المعروضة
## ============================================
func _refresh_display() -> void:
        if not profile_manager:
                return
        
        var stats = profile_manager.get_all_stats()
        
        ## البطاقة الشخصية
        if name_label:
                name_label.text = stats["player_name"]
        if level_label:
                level_label.text = "المستوى %d" % stats["level"]
        if xp_bar:
                xp_bar.max_value = profile_manager.xp_to_next_level
                xp_bar.value = profile_manager.current_level_xp
        if xp_label:
                xp_label.text = "%d / %d XP" % [profile_manager.current_level_xp, profile_manager.xp_to_next_level]
        
        ## الإحصائيات
        if balance_label:
                balance_label.text = "$%.2f" % stats["balance"]
        if total_trades_label:
                total_trades_label.text = "%d صفقة" % stats["total_trades"]
        if win_rate_label:
                win_rate_label.text = "%.1f%%" % stats["win_rate"]
        if biggest_win_label:
                biggest_win_label.text = "$%.2f" % stats["biggest_win"]
        if profit_label:
                var sign := "+" if stats["total_profit"] > 0 else ""
                profit_label.text = "%s$%.2f" % [sign, stats["total_profit"]]
        if streak_label:
                streak_label.text = "%d 🔥" % stats["current_streak"]
        
        ## الأوسمة
        _refresh_badges()

## ============================================
## تحديث عرض الأوسمة
## ============================================
func _refresh_badges() -> void:
        if not badge_grid or not profile_manager:
                return
        
        ## مسح الأوسمة القديمة
        for child in badge_grid.get_children():
                child.queue_free()
        
        ## عرض الأوسمة المكتسبة
        var all_badges = profile_manager.ALL_BADGES
        var earned = profile_manager.earned_badges
        
        for badge_id in all_badges:
                var badge_data = all_badges[badge_id]
                var is_earned = badge_id in earned
                
                var container := VBoxContainer.new()
                
                var icon := TextureRect.new()
                icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
                icon.custom_minimum_size = Vector2(48, 48)
                
                ## في الإنتاج: استبدل بأيقونات حقيقية
                var emoji := "🏆" if is_earned else "🔒"
                var label := Label.new()
                label.text = emoji
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                label.add_theme_font_size_override("font_size", 24)
                
                container.add_child(label)
                
                var name := Label.new()
                name.text = badge_data["name"]
                name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                name.add_theme_font_size_override("font_size", 10)
                if not is_earned:
                        name.modulate = Color(0.5, 0.5, 0.5)
                container.add_child(name)
                
                badge_grid.add_child(container)

## ============================================
## مستمعو الأحداث
## ============================================
func _on_stats_updated(_stats: Dictionary) -> void:
        _refresh_display()

func _on_level_up(new_level: int, rewards: Dictionary) -> void:
        _refresh_display()
        ## تأثير بصري عند الترقية
        var tween := create_tween()
        tween.tween_property(self, "modulate", Color.YELLOW, 0.3)
        tween.tween_property(self, "modulate", Color.WHITE, 0.5)

func _on_badge_earned(_badge_id: String, _badge_name: String) -> void:
        _refresh_badges()

func _on_balance_updated(new_balance: float, delta: float) -> void:
        if balance_label:
                balance_label.text = "$%.2f" % new_balance
        ## تأثير الارتفاع/الانخفاض
        var color := Color.GREEN if delta > 0 else Color.RED
        if balance_label:
                var tween := create_tween()
                tween.tween_property(balance_label, "modulate", color, 0.2)
                tween.tween_property(balance_label, "modulate", Color.WHITE, 0.3)
