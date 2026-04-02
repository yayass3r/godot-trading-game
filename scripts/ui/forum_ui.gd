## ============================================
## ForumUI.gd - واجهة المنتدى الاجتماعي
## تعرض منشورات المتداولين مع إعجابات وتعليقات
## ============================================
extends Control

const ForumPostClass = preload("res://scripts/data_models/forum_post.gd")
const NP = preload("res://scripts/enums/notification_priority.gd")

## ---- Node References ----
@onready var posts_container: ScrollContainer = $PostsContainer
@onready var post_list: VBoxContainer = $PostsContainer/PostList
@onready var new_post_input: TextEdit = $NewPostPanel/PostInput
@onready var symbol_input: LineEdit = $NewPostPanel/SymbolInput
@onready var post_type_option: OptionButton = $NewPostPanel/PostTypeOption
@onready var submit_button: Button = $NewPostPanel/SubmitButton
@onready var back_button: Button = $BackButton

## ---- Manager References ----
@onready var forum_manager: Node = get_node_or_null("/root/ForumManager")
@onready var profile_manager: Node = get_node_or_null("/root/ProfileManager")
@onready var challenge_manager: Node = get_node_or_null("/root/ChallengeManager")

## ============================================
## _ready() - Initialize UI and connect signals
## ============================================
func _ready() -> void:
        if back_button:
                back_button.pressed.connect(_on_back_pressed)
        if submit_button:
                submit_button.pressed.connect(_on_submit_post)

        ## Connect forum signals
        if forum_manager:
                forum_manager.post_created.connect(_on_post_created)
                forum_manager.post_liked.connect(_on_post_liked)

        ## Populate post type options
        if post_type_option:
                post_type_option.add_item("Trade Idea")
                post_type_option.add_item("Trade Result")
                post_type_option.add_item("General Discussion")

        _refresh_feed()

## ============================================
## Submit a new post
## ============================================
func _on_submit_post() -> void:
        if not forum_manager or not profile_manager or not new_post_input:
                return

        var content: String = new_post_input.text.strip_edges()
        if content.is_empty():
                NotificationManager.send_notification(
                        "Empty Post",
                        "Write something before posting!",
                        NP.WARNING
                )
                return

        ## Determine post type from option button
        var post_type := ForumPostClass.PostType.GENERAL_DISCUSS
        if post_type_option:
                match post_type_option.selected:
                        0:
                                post_type = ForumPostClass.PostType.TRADE_IDEA
                        1:
                                post_type = ForumPostClass.PostType.TRADE_RESULT
                        2:
                                post_type = ForumPostClass.PostType.GENERAL_DISCUSS

        ## Get optional symbol
        var symbol: String = ""
        if symbol_input:
                symbol = symbol_input.text.strip_edges().to_upper()

        ## Create the post via ForumManager
        forum_manager.create_post(
                profile_manager.player_id,
                profile_manager.player_name,
                content,
                post_type,
                symbol
        )

        ## Register social activity for challenges
        if challenge_manager and challenge_manager.has_method("register_social_post"):
                challenge_manager.register_social_post()

        ## Clear input
        new_post_input.text = ""

## ============================================
## Refresh the feed display
## ============================================
func _refresh_feed() -> void:
        if not forum_manager or not post_list:
                return

        ## Clear existing posts
        for child in post_list.get_children():
                child.queue_free()

        ## Fetch latest posts
        var feed: Array = forum_manager.get_feed(20)
        for post in feed:
                var post_card := _create_post_card(post)
                post_list.add_child(post_card)

## ============================================
## Create a single post card UI element
## ============================================
func _create_post_card(post) -> PanelContainer:
        var card := PanelContainer.new()
        card.add_theme_stylebox_override("panel", _get_card_style())

        var vbox := VBoxContainer.new()
        card.add_child(vbox)

        ## ---- Header: Author + Time ----
        var header := HBoxContainer.new()
        vbox.add_child(header)

        var name_lbl := Label.new()
        name_lbl.text = "%s (Lv.%d)" % [post.author_name, post.author_level]
        name_lbl.add_theme_font_size_override("font_size", 16)
        name_lbl.add_theme_color_override("font_color", Color.CYAN)
        header.add_child(name_lbl)

        header.add_child(Control.new())  ## spacer

        var time_lbl := Label.new()
        var time_diff: int = int(Time.get_unix_time_from_system()) - post.created_at
        time_lbl.text = _format_time_ago(time_diff)
        time_lbl.add_theme_color_override("font_color", Color.GRAY)
        header.add_child(time_lbl)

        ## ---- Attached Symbol ----
        if not post.attached_symbol.is_empty():
                var sym_lbl := Label.new()
                sym_lbl.text = "  %s" % post.attached_symbol
                sym_lbl.add_theme_color_override("font_color", Color.GOLD)
                vbox.add_child(sym_lbl)

        ## ---- Content ----
        var content_lbl := Label.new()
        content_lbl.text = post.content
        content_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        content_lbl.add_theme_font_size_override("font_size", 14)
        vbox.add_child(content_lbl)

        ## ---- Action Buttons ----
        var actions := HBoxContainer.new()
        vbox.add_child(actions)

        var like_btn := Button.new()
        like_btn.text = "%d" % post.likes_count
        like_btn.pressed.connect(func():
                if profile_manager and forum_manager:
                        forum_manager.like_post(post.post_id, profile_manager.player_id)
                        _refresh_feed()
        )
        actions.add_child(like_btn)

        var comment_btn := Button.new()
        comment_btn.text = "%d" % post.comments_count
        actions.add_child(comment_btn)

        return card

## ============================================
## Signal handlers
## ============================================
func _on_post_created(_post) -> void:
        _refresh_feed()

func _on_post_liked(_post_id: String, _user_id: String) -> void:
        _refresh_feed()

## ============================================
## Helpers
## ============================================
func _format_time_ago(seconds: int) -> String:
        if seconds < 60:
                return "just now"
        if seconds < 3600:
                return "%dm ago" % (seconds / 60)
        if seconds < 86400:
                return "%dh ago" % (seconds / 3600)
        return "%dd ago" % (seconds / 86400)

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
