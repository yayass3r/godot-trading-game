## ============================================
## ForumUI.gd - واجهة المنتدى الاجتماعي
## تعرض منشورات المتداولين مع إعجابات وتعليقات
## ============================================
extends Control

## ---- عقد الواجهة ----
@onready var posts_container: ScrollContainer = $PostsContainer
@onready var post_list: VBoxContainer = $PostsContainer/PostList
@onready var new_post_input: TextEdit = $NewPostPanel/PostInput
@onready var symbol_input: LineEdit = $NewPostPanel/SymbolInput
@onready var post_type_option: OptionButton = $NewPostPanel/PostTypeOption
@onready var submit_button: Button = $NewPostPanel/SubmitButton
@onready var tab_container: TabBar = $TabContainer

## ---- مراجع الأنظمة ----
var forum_manager: Node
var profile_manager: Node

## ============================================
## التهيئة
## ============================================
func _ready() -> void:
        forum_manager = get_node_or_null("/root/GameManager/ForumManager")
        profile_manager = get_node_or_null("/root/GameManager/ProfileManager")
        
        if forum_manager:
                forum_manager.post_created.connect(_on_post_created)
                forum_manager.post_liked.connect(_on_post_liked)
        
        if submit_button:
                submit_button.pressed.connect(_on_submit_post)
        
        ## أنواع المنشورات
        if post_type_option:
                post_type_option.add_item("💡 فكرة تداول")
                post_type_option.add_item("📈 نتيجة صفقة")
                post_type_option.add_item("💬 نقاش عام")
        
        _refresh_feed()

## ============================================
## إرسال منشور جديد
## ============================================
func _on_submit_post() -> void:
        if not forum_manager or not profile_manager or not new_post_input:
                return
        
        var content: String = new_post_input.text.strip_edges()
        if content.is_empty():
                NotificationManager.send_notification(
                        "⚠️ فارغ",
                        "اكتب شيئاً قبل النشر!",
                        NotificationPriority.WARNING
                )
                return
        
        var post_type := ForumPost.PostType.GENERAL_DISCUSS
        if post_type_option:
                match post_type_option.selected:
                        0: post_type = ForumPost.PostType.TRADE_IDEA
                        1: post_type = ForumPost.PostType.TRADE_RESULT
                        2: post_type = ForumPost.PostType.GENERAL_DISCUSS
        
        var symbol: String = ""
        if symbol_input:
                symbol = symbol_input.text.strip_edges().to_upper()
        
        forum_manager.create_post(
                profile_manager.player_id,
                profile_manager.player_name,
                content,
                post_type,
                symbol
        )
        
        ## مسح حقل الإدخال
        new_post_input.text = ""

## ============================================
## تحديث قائمة المنشورات
## ============================================
func _refresh_feed() -> void:
        if not forum_manager or not post_list:
                return
        
        ## مسح المنشورات القديمة
        for child in post_list.get_children():
                child.queue_free()
        
        ## جلب آخر المنشورات
        var feed: Array = forum_manager.get_feed(20)
        for post in feed:
                var post_card := _create_post_card(post)
                post_list.add_child(post_card)

## ============================================
## إنشاء بطاقة منشور واحدة
## ============================================
func _create_post_card(post: ForumPost) -> PanelContainer:
        var card := PanelContainer.new()
        card.add_theme_stylebox_override("panel", _get_card_style())
        
        var vbox := VBoxContainer.new()
        card.add_child(vbox)
        
        ## ---- رأس المنشور ----
        var header := HBoxContainer.new()
        vbox.add_child(header)
        
        var name_lbl := Label.new()
        name_lbl.text = "👤 %s (مستوى %d)" % [post.author_name, post.author_level]
        name_lbl.add_theme_font_size_override("font_size", 16)
        name_lbl.add_theme_color_override("font_color", Color.CYAN)
        header.add_child(name_lbl)
        
        header.add_child(Control.new())  ## spacer
        
        var time_lbl := Label.new()
        var time_diff := Time.get_unix_time_from_system() - post.created_at
        time_lbl.text = _format_time_ago(time_diff)
        time_lbl.add_theme_color_override("font_color", Color.GRAY)
        header.add_child(time_lbl)
        
        ## ---- رمز الأداة ----
        if not post.attached_symbol.is_empty():
                var sym_lbl := Label.new()
                sym_lbl.text = "📈 %s" % post.attached_symbol
                sym_lbl.add_theme_color_override("font_color", Color.GOLD)
                vbox.add_child(sym_lbl)
        
        ## ---- محتوى المنشور ----
        var content_lbl := Label.new()
        content_lbl.text = post.content
        content_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        content_lbl.add_theme_font_size_override("font_size", 14)
        vbox.add_child(content_lbl)
        
        ## ---- أزرار التفاعل ----
        var actions := HBoxContainer.new()
        vbox.add_child(actions)
        
        var like_btn := Button.new()
        like_btn.text = "❤️ %d" % post.likes_count
        like_btn.pressed.connect(func():
                if profile_manager:
                        forum_manager.like_post(post.post_id, profile_manager.player_id)
                        _refresh_feed()
        )
        actions.add_child(like_btn)
        
        var comment_btn := Button.new()
        comment_btn.text = "💬 %d" % post.comments_count
        actions.add_child(comment_btn)
        
        return card

## ============================================
## مستمعو الأحداث
## ============================================
func _on_post_created(_post: ForumPost) -> void:
        _refresh_feed()

func _on_post_liked(_post_id: String, _user_id: String) -> void:
        _refresh_feed()

## ============================================
## أدوات مساعدة
## ============================================
func _format_time_ago(seconds: int) -> String:
        if seconds < 60: return "الآن"
        if seconds < 3600: return "منذ %d دقيقة" % (seconds / 60)
        if seconds < 86400: return "منذ %d ساعة" % (seconds / 3600)
        return "منذ %d يوم" % (seconds / 86400)

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
