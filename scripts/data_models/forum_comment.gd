## ForumComment.gd - نموذج التعليق
## تم استخراجه من ForumManager كملف مستقل
class_name ForumComment
extends RefCounted

var comment_id: String = ""
var user_id: String = ""
var user_name: String = ""
var text: String = ""
var created_at: int = 0
