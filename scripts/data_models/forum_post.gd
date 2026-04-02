## ForumPost.gd - نموذج المنشور
## تم استخراجه من ForumManager كملف مستقل
class_name ForumPost
extends RefCounted

enum PostType {
        TRADE_IDEA,      ## فكرة تداول / توصية
        TRADE_RESULT,     ## نتيجة صفقة
        SHOT_SCREEN,      ## لقطة شاشة
        GENERAL_DISCUSS   ## نقاش عام
}

var post_id: String = ""
var author_id: String = ""
var author_name: String = ""
var author_level: int = 1
var author_badge: String = ""
var content: String = ""
var post_type: PostType = PostType.GENERAL_DISCUSS
var attached_symbol: String = ""
var attached_image: String = ""
var trade_screenshot: Dictionary = {}
var likes_count: int = 0
var liked_by: Array[String] = []
var comments: Array = []
var comments_count: int = 0
var created_at: int = 0

func to_dictionary() -> Dictionary:
        return {
                "post_id": post_id,
                "author_id": author_id,
                "author_name": author_name,
                "author_level": author_level,
                "author_badge": author_badge,
                "content": content,
                "post_type": post_type,
                "attached_symbol": attached_symbol,
                "likes_count": likes_count,
                "comments_count": comments_count,
                "created_at": created_at
        }
