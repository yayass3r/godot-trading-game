## ============================================
## SmoothNumber.gd - أداة الأرقام المتحركة والتحويلات السلسة
## يوفر Tween للأسعار، أرقام عدّاد متحركة، تدرجات ألوان
## ============================================
extends Control

## ---- إعدادات ----
@export var prefix: String = ""
@export var suffix: String = ""
@export var decimals: int = 2
@export var animate_duration: float = 0.4
@export var use_color_gradient: bool = true

## ---- ألوان ----
var COLOR_POSITIVE: Color = Color(0.14, 0.83, 0.44, 1.0)   ## أخضر
var COLOR_NEGATIVE: Color = Color(0.90, 0.31, 0.27, 1.0)    ## أحمر
var COLOR_NEUTRAL: Color = Color(1.0, 1.0, 1.0, 1.0)        ## أبيض

## ---- حالة ----
var _current_value: float = 0.0
var _display_value: float = 0.0
var _target_value: float = 0.0
var _is_animating: bool = false
var _tween: SceneTreeTween = null
var _previous_value: float = 0.0

## ---- مرجع Label ----
var _label: Label = null

## ============================================
## _ready()
## ============================================
func _ready() -> void:
	## إنشاء Label داخلي
	_label = Label.new()
	_label.name = "NumberLabel"
	_label.anchors_preset = Control.PRESET_FULL_RECT
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)

	_update_label(_current_value, COLOR_NEUTRAL)

## ============================================
## تعيين قيمة جديدة مع تحريك
## ============================================
func set_value(new_value: float, immediate: bool = false) -> void:
	_previous_value = _current_value
	_target_value = new_value

	if immediate or _current_value == 0.0:
		_current_value = new_value
		_display_value = new_value
		var col := COLOR_NEUTRAL
		if use_color_gradient and _previous_value != 0:
			col = COLOR_POSITIVE if new_value > _previous_value else COLOR_NEGATIVE
		_update_label(_current_value, col)
		return

	_is_animating = true
	_start_tween()

## ============================================
## بدء Tween
## ============================================
func _start_tween() -> void:
	if _tween and _tween.is_running():
		_tween.kill()

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)

	var start := _current_value
	var end := _target_value

	_tween.tween_method(func(v: float) -> void:
		_display_value = v
		var col := COLOR_NEUTRAL
		if use_color_gradient and _previous_value != 0:
			var progress := (v - start) / (end - start) if end != start else 0.5
			if end > start:
				col = COLOR_NEUTRAL.lerp(COLOR_POSITIVE, progress)
			else:
				col = COLOR_NEUTRAL.lerp(COLOR_NEGATIVE, progress)
		_update_label(v, col)
	, start, end, animate_duration)

	_tween.tween_callback(func() -> void:
		_current_value = _target_value
		_display_value = _target_value
		_is_animating = false
	)

## ============================================
## تحديث نص Label
## ============================================
func _update_label(value: float, color: Color) -> void:
	if not _label:
		return
	_label.text = "%s%s%s" % [prefix, _format_number(value), suffix]
	_label.add_theme_color_override("font_color", color)

## ============================================
## تنسيق الرقم
## ============================================
func _format_number(value: float) -> String:
	if decimals <= 0:
		return "%d" % int(value)
	var format := "%%.%df" % decimals
	return format % value

## ============================================
## تعيين الأرقام العشرية
## ============================================
func set_decimals(d: int) -> void:
	decimals = d

## ============================================
## تعيين البادئة واللاحقة
## ============================================
func set_format(p: String, s: String) -> void:
	prefix = p
	suffix = s
	_update_label(_display_value, COLOR_NEUTRAL)

## ============================================
## الحصول على القيمة الحالية
## ============================================
func get_value() -> float:
	return _target_value
