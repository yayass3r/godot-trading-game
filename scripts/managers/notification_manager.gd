## ============================================
## NotificationManager.gd - مدير الإشعارات وهز الهاتف
## يرسل إشعارات بصرية + يهز الهاتف (Vibrate) عند الأحداث المهمة
## ============================================
extends Node

const NP = preload("res://scripts/enums/notification_priority.gd")

## ---- إشارات ----
signal notification_shown(title: String, message: String, priority: int)
signal vibration_triggered(pattern: String)

## ---- ثوابت الاهتزاز ----
## أنماط الاهتزاز المختلفة (بالمللي ثانية)
const VIBRATION_PATTERNS: Dictionary = {
        "light": [50],                           ## اهتزاز خفيف
        "medium": [100, 50, 100],                ## اهتزاز متوسط
        "heavy": [200, 100, 200, 100, 200],      ## اهتزاز قوي
        "margin_call": [500, 200, 500, 200, 500, 200, 500],  ## نداء الهامش
        "liquidation": [1000, 300, 1000, 300, 1000, 300, 1000, 300, 1000],  ## تصفية
        "success": [100, 50, 100, 50, 200],      ## نجاح
        "alert": [300, 100, 300]                 ## تنبيه
}

## ---- تخزين الإشعارات الأخيرة ----
var notification_history: Array[Dictionary] = []
const MAX_HISTORY: int = 50

## ---- مرجع للواجهة ----
var notification_ui: Control = null

## ---- مرجع الاهتزاز ----
var _vibrator_plugin: Object = null  ## سيتم ربطه بـ Android Plugin

## ============================================
## إرسال إشعار كامل (بصري + اهتزاز)
## ============================================
static func send_notification(
        title: String,
        message: String,
        priority: int = NP.INFO,
        show_vibration: bool = true
) -> void:
        var manager: Node = Engine.get_main_loop().root.get_node_or_null("/root/NotificationManager")
        if manager == null:
                manager = load("res://scripts/managers/notification_manager.gd").new()
                Engine.get_main_loop().root.add_child(manager)
        
        manager._show_notification(title, message, priority, show_vibration)

## ============================================
## عرض الإشعار داخلياً
## ============================================
func _show_notification(
        title: String,
        message: String,
        priority: int,
        show_vibration: bool
) -> void:
        ## حفظ في السجل
        var record := {
                "title": title,
                "message": message,
                "priority": priority,
                "timestamp": Time.get_unix_time_from_system()
        }
        notification_history.append(record)
        if notification_history.size() > MAX_HISTORY:
                notification_history.pop_front()
        
        ## إرسال إشعار بصري
        notification_shown.emit(title, message, priority)
        
        ## تحديث واجهة الإشعارات
        if notification_ui and is_instance_valid(notification_ui):
                notification_ui.show_notification(title, message, priority)
        
        ## اهتزاز الهاتف
        if show_vibration and OS.get_name() == "Android":
                _vibrate_for_priority(priority)
        
        ## طباعة في الكونسول
        var icon := _get_priority_icon(priority)
        print("[Notification] %s %s | %s" % [icon, title, message])

## ============================================
## اهتزاز الهاتف حسب أولوية الإشعار
## ============================================
func _vibrate_for_priority(priority: int) -> void:
        var pattern_key: String
        
        match priority:
                NP.INFO:
                        pattern_key = "light"
                NP.SUCCESS:
                        pattern_key = "success"
                NP.WARNING:
                        pattern_key = "medium"
                NP.HIGH:
                        pattern_key = "margin_call"
                NP.CRITICAL:
                        pattern_key = "liquidation"
                _:
                        pattern_key = "light"
        
        _vibrate(pattern_key)

## ============================================
## اهتزاز الهاتف باستخدام Android Java API
## ============================================
func _vibrate(pattern_key: String = "light") -> void:
        if OS.get_name() != "Android":
                print("[Notification] 🔇 الاهتزاز غير متاح إلا على أندرويد")
                return
        
        var pattern: Array = VIBRATION_PATTERNS.get(pattern_key, [50])
        
        ## استخدام Godot 4 Native Interface للوصول إلى Java Vibrator
        if Engine.has_singleton("GodotVibration"):
                Engine.get_singleton("GodotVibration").vibrate(pattern)
                vibration_triggered.emit(pattern_key)
                return
        
        ## طريقة بديلة عبر Java Class مباشرة
        if true:
                var vibe_service: Object = _get_android_vibrator()
                if vibe_service != null:
                        _android_vibrate_long(vibe_service, pattern)
                        vibration_triggered.emit(pattern_key)

## ============================================
## الحصول على خدمة Vibrator من أندرويد
## ============================================
func _get_android_vibrator() -> Object:
        if Engine.has_method("get_jni_singleton"):
                return null  ## Godot 4 يستخدم طريقة مختلفة
        
        ## في Godot 4 نستخدم JavaClass
        return null

## ============================================
## تنفيذ الاهتزاز عبر JNI (Godot 4)
## ============================================
func _android_vibrate_long(_vibrator: Object, _pattern: Array) -> void:
        ## الطريقة المباشرة في Godot 4:
        ## var jni = JavaClass.new("android.os.Vibrator")
        ## أو استخدام Godot's built-in haptic feedback
        if Engine.has_singleton("GodotHapticFeedback"):
                Engine.get_singleton("GodotHapticFeedback").heavy_impact()
                return
        
        ## Fallback: استخدام Input.vibrate_handled أو Input.vibrate
        ## Godot 4 doesn't have built-in vibrate, use plugin

## ============================================
## أيقونة حسب الأولوية
## ============================================
func _get_priority_icon(priority: int) -> String:
        match priority:
                NP.INFO: return "ℹ️"
                NP.SUCCESS: return "✅"
                NP.WARNING: return "⚠️"
                NP.HIGH: return "🚨"
                NP.CRITICAL: return "💥"
                _: return "📌"
