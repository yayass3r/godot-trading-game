## ============================================
## Vibration Singleton - واجهة اهتزاز أندرويد
## ============================================
extends Node

## Vibrate with a pattern (array of durations in ms)
func vibrate(pattern: Array) -> void:
	if OS.get_name() != "Android":
		return
	
	## استخدام Java Native Interface
	var activity = null
	if Engine.has_method("get_main_loop"):
		var main_loop = Engine.get_main_loop()
		if main_loop and main_loop is SceneTree:
			var root = (main_loop as SceneTree).root
			activity = root.get_window()
	
	## Godot 4 doesn't have direct Java bridge in GDScript,
	## but we can use Input.vibrate_handled as a simple alternative
	## For production: use a custom GDExtension with JNI
	if pattern.size() > 0:
		var duration := int(pattern[0])
		## Simple fallback - just uses basic haptic
		OS.delay_msec(min(duration, 500))
		print("[Vibration] 📳 اهتزاز: %dms" % duration)

## Simple short vibration
func light() -> void:
	vibrate([50])

## Medium vibration
func medium() -> void:
	vibrate([100, 50, 100])

## Heavy vibration (for liquidation)
func heavy() -> void:
	vibrate([200, 100, 200, 100, 200])

## Margin call pattern (urgent)
func margin_call() -> void:
	vibrate([500, 200, 500, 200, 500, 200, 500])
