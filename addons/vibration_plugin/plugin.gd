## ============================================
## Android Vibration Plugin for Godot 4
## يوفر اهتزاز الهاتف (Haptic Feedback) على أندرويد
## ============================================
@tool
extends EditorPlugin

const VIBRATE_CLASS_NAME = "org.godotengine.plugin.vibration.GodotVibration"

func _enter_tree() -> void:
	if Engine.has_singleton("GodotVibration"):
		return
	
	## تسجيل الـ singleton
	if ProjectSettings.has_setting("android/modules/vibration_plugin"):
		add_autoload_singleton("GodotVibration", "res://addons/vibration_plugin/vibration_singleton.gd")
		print("[VibrationPlugin] ✅ تم تسجيل GodotVibration")
	else:
		print("[VibrationPlugin] ⚠️ اضف 'vibration_plugin' في Android modules")

func _exit_tree() -> void:
	remove_autoload_singleton("GodotVibration")
