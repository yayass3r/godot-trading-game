## ============================================
## LeaderboardUI.gd - واجهة لوحة المتصدرين
## ============================================
extends Control

## ---- عقد الواجهة ----
@onready var category_tabs: TabBar = $CategoryTabs
@onready var entries_container: VBoxContainer = $EntriesContainer
@onready var player_rank_label: Label = $PlayerRankLabel

## ---- مراجع ----
var leaderboard_manager: Node
var current_category: int = LeaderboardCategory.BALANCE

## ============================================
## التهيئة
## ============================================
func _ready() -> void:
        leaderboard_manager = get_node_or_null("/root/GameManager/LeaderboardManager")
        
        if leaderboard_manager:
                leaderboard_manager.leaderboard_updated.connect(_on_leaderboard_updated)
                leaderboard_manager.player_rank_updated.connect(_on_rank_updated)
        
        ## تبويبات التصنيفات
        if category_tabs:
                category_tabs.tab_clicked.connect(_on_tab_changed)
        
        refresh()

## ============================================
## تحديث اللوحة
## ============================================
func refresh() -> void:
        if leaderboard_manager:
                leaderboard_manager.refresh_leaderboard(current_category)

## ============================================
## عند تغيير التبويب
## ============================================
func _on_tab_changed(tab: int) -> void:
        current_category = tab as int
        refresh()

## ============================================
## عرض المتصدرين
## ============================================
func _on_leaderboard_updated(_category: String, entries: Array[Dictionary]) -> void:
        if not entries_container:
                return
        
        for child in entries_container.get_children():
                child.queue_free()
        
        for i in range(entries.size()):
                var entry = entries[i]
                var rank: int = entry.get("rank", i + 1)
                var is_player: bool = entry.get("is_real_player", false)
                
                var row := HBoxContainer.new()
                
                ## ترتيب
                var rank_lbl := Label.new()
                var medal := ""
                match rank:
                        1: medal = "🥇"
                        2: medal = "🥈"
                        3: medal = "🥉"
                        _: medal = "#%d" % rank
                rank_lbl.text = "%s  " % medal
                rank_lbl.custom_minimum_size.x = 50
                row.add_child(rank_lbl)
                
                ## اسم اللاعب
                var name_lbl := Label.new()
                name_lbl.text = entry.get("player_name", "???")
                if is_player:
                        name_lbl.add_theme_color_override("font_color", Color.GOLD)
                        name_lbl.text = "⭐ %s" % name_lbl.text
                row.add_child(name_lbl)
                
                ## القيمة حسب الفئة
                row.add_child(Control.new())  ## spacer
                var value_lbl := Label.new()
                
                match current_category:
                        LeaderboardCategory.BALANCE:
                                value_lbl.text = "$%.2f" % entry.get("balance", 0.0)
                        LeaderboardCategory.PROFIT:
                                value_lbl.text = "$%.2f" % entry.get("total_profit", 0.0)
                        LeaderboardCategory.WIN_RATE:
                                value_lbl.text = "%.1f%%" % entry.get("win_rate", 0.0)
                        LeaderboardCategory.LEVEL:
                                value_lbl.text = "Lv.%d" % entry.get("level", 0)
                        LeaderboardCategory.STREAK:
                                value_lbl.text = "%d 🔥" % entry.get("best_streak", 0)
                        LeaderboardCategory.VOLUME:
                                value_lbl.text = "$%.0f" % entry.get("total_volume", 0.0)
                
                value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                row.add_child(value_lbl)
                
                ## تنسيق الصف الخاص باللاعب
                if is_player:
                        var style := StyleBoxFlat.new()
                        style.bg_color = Color(0.2, 0.15, 0.0, 0.5)
                        style.set_corner_radius_all(4)
                        entries_container.add_child(row)
                else:
                        entries_container.add_child(row)

## ============================================
## تحديث ترتيب اللاعب
## ============================================
func _on_rank_updated(category: String, rank: int, total: int) -> void:
        if player_rank_label:
                player_rank_label.text = "ترتيبك في %s: #%d من %d" % [category, rank, total]
