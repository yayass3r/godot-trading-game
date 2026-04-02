## ============================================
## LeaderboardUI.gd - واجهة لوحة المتصدرين
## تعرض تصنيفات اللاعبين حسب فئات مختلفة
## ============================================
extends Control

const LBC = preload("res://scripts/enums/leaderboard_category.gd")

## ---- Node References ----
@onready var category_tabs: TabBar = $CategoryTabs
@onready var entries_container: VBoxContainer = $EntriesContainer
@onready var player_rank_label: Label = $PlayerRankLabel
@onready var back_button: Button = $BackButton

## ---- Manager References ----
@onready var leaderboard_manager: Node = get_node_or_null("/root/LeaderboardManager")

## ---- State ----
var current_category: int = LBC.BALANCE

## ============================================
## _ready() - Initialize UI and connect signals
## ============================================
func _ready() -> void:
        if back_button:
                back_button.pressed.connect(_on_back_pressed)

        if leaderboard_manager:
                leaderboard_manager.leaderboard_updated.connect(_on_leaderboard_updated)
                leaderboard_manager.player_rank_updated.connect(_on_rank_updated)

        ## Tab selection
        if category_tabs:
                category_tabs.tab_clicked.connect(_on_tab_changed)

        refresh()

## ============================================
## Request leaderboard data refresh
## ============================================
func refresh() -> void:
        if leaderboard_manager and leaderboard_manager.has_method("refresh_leaderboard"):
                leaderboard_manager.refresh_leaderboard(current_category)

## ============================================
## Category tab changed
## ============================================
func _on_tab_changed(tab: int) -> void:
        current_category = tab
        refresh()

## ============================================
## Display leaderboard entries
## ============================================
func _on_leaderboard_updated(_category: String, entries: Array) -> void:
        if not entries_container:
                return

        ## Clear old entries
        for child in entries_container.get_children():
                child.queue_free()

        for i in range(entries.size()):
                var entry: Dictionary = entries[i]
                var rank: int = entry.get("rank", i + 1)
                var is_player: bool = entry.get("is_real_player", false)

                var row := HBoxContainer.new()

                ## Rank column
                var rank_lbl := Label.new()
                var medal := ""
                match rank:
                        1: medal = "#1"
                        2: medal = "#2"
                        3: medal = "#3"
                        _: medal = "#%d" % rank
                rank_lbl.text = "%s  " % medal
                rank_lbl.custom_minimum_size.x = 50
                row.add_child(rank_lbl)

                ## Player name column
                var name_lbl := Label.new()
                name_lbl.text = str(entry.get("player_name", "???"))
                if is_player:
                        name_lbl.add_theme_color_override("font_color", Color.GOLD)
                        name_lbl.text = "* %s" % name_lbl.text
                row.add_child(name_lbl)

                ## Spacer
                row.add_child(Control.new())

                ## Value column (depends on category)
                var value_lbl := Label.new()
                match current_category:
                        LBC.BALANCE:
                                value_lbl.text = "$%.2f" % entry.get("balance", 0.0)
                        LBC.PROFIT:
                                value_lbl.text = "$%.2f" % entry.get("total_profit", 0.0)
                        LBC.WIN_RATE:
                                value_lbl.text = "%.1f%%" % entry.get("win_rate", 0.0)
                        LBC.LEVEL:
                                value_lbl.text = "Lv.%d" % entry.get("level", 0)
                        LBC.STREAK:
                                value_lbl.text = "%d" % entry.get("best_streak", 0)
                        LBC.VOLUME:
                                value_lbl.text = "$%.0f" % entry.get("total_volume", 0.0)
                value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                row.add_child(value_lbl)

                ## Highlight player row
                if is_player:
                        var style := StyleBoxFlat.new()
                        style.bg_color = Color(0.2, 0.15, 0.0, 0.5)
                        style.set_corner_radius_all(4)

                entries_container.add_child(row)

## ============================================
## Update player rank display
## ============================================
func _on_rank_updated(category: String, rank: int, total: int) -> void:
        if player_rank_label:
                player_rank_label.text = "Your %s rank: #%d of %d" % [category, rank, total]

## ============================================
## Back to main menu
## ============================================
func _on_back_pressed() -> void:
        get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
