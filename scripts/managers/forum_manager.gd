## ============================================
## ForumManager.gd - مدير المنتدى الاجتماعي
## يتيح للاعبين نشر توصيات ومشاركة صفقاتهم
## ============================================
extends Node

const ForumPostClass = preload("res://scripts/data_models/forum_post.gd")
const ForumCommentClass = preload("res://scripts/data_models/forum_comment.gd")
const NP = preload("res://scripts/enums/notification_priority.gd")

## ---- إشارات ----
signal post_created(post)
signal post_liked(post_id: String, user_id: String)
signal post_commented(post_id: String, comment)
signal feed_updated(posts)

## ---- بيانات المنتدى ----
var posts: Array = []
var trending_symbols: Dictionary = {}  ## {symbol: mention_count}

## ============================================
## إنشاء منشور جديد
## ============================================
func create_post(
        author_id: String,
        author_name: String,
        content: String,
        post_type: int = ForumPostClass.PostType.TRADE_IDEA,
        attached_symbol: String = "",
        attached_image: String = "",
        trade_screenshot: Dictionary = {}
):
        var post := ForumPostClass.new()
        post.post_id = _generate_post_id()
        post.author_id = author_id
        post.author_name = author_name
        post.content = content
        post.post_type = post_type
        post.attached_symbol = attached_symbol
        post.attached_image = attached_image
        post.trade_screenshot = trade_screenshot
        post.created_at = Time.get_unix_time_from_system()
        
        posts.append(post)
        post_created.emit(post)
        
        ## تحديث الرموز الرائجة
        if not attached_symbol.is_empty():
                trending_symbols[attached_symbol] = trending_symbols.get(attached_symbol, 0) + 1
        
        ## إشعار نجاح
        NotificationManager.send_notification(
                "📝 تم النشر!",
                "تم نشر منشورك بنجاح في المنتدى",
                NP.SUCCESS
        )
        
        return post

## ============================================
## إعجاب بمنشور
## ============================================
func like_post(post_id: String, user_id: String) -> bool:
        for post in posts:
                if post.post_id == post_id:
                        if user_id in post.liked_by:
                                ## إلغاء الإعجاب
                                post.liked_by.erase(user_id)
                                post.likes_count -= 1
                        else:
                                ## إضافة إعجاب
                                post.liked_by.append(user_id)
                                post.likes_count += 1
                                post_liked.emit(post_id, user_id)
                        return true
        return false

## ============================================
## إضافة تعليق على منشور
## ============================================
func add_comment(post_id: String, user_id: String, user_name: String, text: String) -> bool:
        for post in posts:
                if post.post_id == post_id:
                        var comment := ForumCommentClass.new()
                        comment.comment_id = _generate_post_id()
                        comment.user_id = user_id
                        comment.user_name = user_name
                        comment.text = text
                        comment.created_at = Time.get_unix_time_from_system()
                        
                        post.comments.append(comment)
                        post.comments_count += 1
                        post_commented.emit(post_id, comment)
                        return true
        return false

## ============================================
## الحصول على آخر المنشورات (Feed)
## ============================================
func get_feed(limit: int = 20, offset: int = 0):
        var sorted := posts.duplicate()
        sorted.sort_custom(func(a, b): return a.created_at > b.created_at)
        
        if offset >= sorted.size():
                return []
        return sorted.slice(offset, offset + limit)

## ============================================
## الحصول على منشورات رمز معين
## ============================================
func get_posts_by_symbol(symbol: String):
        var result = []
        for post in posts:
                if post.attached_symbol == symbol:
                        result.append(post)
        return result

## ============================================
## الحصول على الرموز الرائجة
## ============================================
func get_trending_symbols(limit: int = 10) -> Array[Dictionary]:
        var sorted: Array = []
        for symbol in trending_symbols:
                sorted.append({"symbol": symbol, "mentions": trending_symbols[symbol]})
        sorted.sort_custom(func(a, b): return a["mentions"] > b["mentions"])
        return sorted.slice(0, limit)

## ============================================
## توليد معرّف فريد
## ============================================
func _generate_post_id() -> String:
        return "post_%d_%d" % [Time.get_ticks_msec(), randi() % 10000]



