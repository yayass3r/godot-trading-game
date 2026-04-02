## ============================================
## SoundManager.gd - مدير الأصوات وتأثيرات الأسواق
## يجعل تجربة التداول أكثر واقعية بأصوات ديناميكية
## ============================================
extends Node
class_name SoundManager

## ---- أنواع الأصوات ----
enum SoundType {
	BUY_ORDER,        ## تأكيد فتح صفقة شراء
	SELL_ORDER,       ## تأكيد فتح صفقة بيع
	TRADE_CLOSE_WIN,  ## إغلاق صفقة رابحة
	TRADE_CLOSE_LOSS, ## إغلاق صفقة خاسرة
	MARGIN_CALL,      ## تنبيه نداء الهامش
	LIQUIDATION,      ## تصفية
	TICK_UP,          ## ارتفاع السعر
	TICK_DOWN,        ## انخفاض السعر
	LEVEL_UP,         ## ترقية المستوى
	BADGE_EARNED,     ## ربح وسام
	NOTIFICATION,     ## إشعار عام
	AMBIENT_MARKET    ## صوت خلفي للسوق
}

## ---- إعدادات الصوت ----
var master_volume: float = 0.7 :
	set(value):
		master_volume = clampf(value, 0.0, 1.0)
		if _audio_master:
			_audio_master.volume_db = linear_to_db(master_volume)

var sfx_volume: float = 0.8 :
	set(value):
		sfx_volume = clampf(value, 0.0, 1.0)

var ambient_volume: float = 0.3 :
	set(value):
		ambient_volume = clampf(value, 0.0, 1.0)

var is_muted: bool = false

## ---- عقد صوتية ----
var _audio_master: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _ambient_player: AudioStreamPlayer
var _tick_cooldown: float = 0.0
const MAX_SFX_PLAYERS: int = 8

## ---- مؤشرات ----
var tick_intensity: float = 0.0  ## شدة تقلبات السوق (تؤثر على الأصوات)

## ============================================
## التهيئة
## ============================================
func _ready() -> void:
	## إنشاء AudioStream الرئيسي
	_audio_master = AudioStreamPlayer.new()
	_audio_master.bus = "Master"
	add_child(_audio_master)
	
	## إنشاء مجمع مؤثرات صوتية
	for i in range(MAX_SFX_PLAYERS):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_sfx_players.append(player)
	
	## مشغل الخلفية
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "Ambient"
	_ambient_player.volume_db = linear_to_db(ambient_volume)
	add_child(_ambient_player)
	
	print("[SoundManager] 🔊 مدير الأصوات جاهز")

## ============================================
## تشغيل مؤثر صوتي
## ============================================
func play_sound(sound_type: SoundType, pitch_variation: float = 0.0) -> void:
	if is_muted:
		return
	
	## البحث عن مشغل متاح
	var player: AudioStreamPlayer = null
	for p in _sfx_players:
		if not p.playing:
			player = p
			break
	
	if player == null:
		return  ## كل المشغلات مشغولة
	
	## توليد الصوت ديناميكياً
	var stream: AudioStream = _generate_sound(sound_type, pitch_variation)
	if stream == null:
		return
	
	player.stream = stream
	player.pitch_scale = 1.0 + pitch_variation
	player.volume_db = linear_to_db(sfx_volume)
	player.play()

## ============================================
## تشغيل صوت علامة السعر (tick)
## ============================================
func play_tick(is_up: bool, intensity: float = 1.0) -> void:
	## تقليل التردد لمنع التشويش
	var time_now := Time.get_ticks_msec() / 1000.0
	if time_now - _tick_cooldown < 0.1:  ## كل 100ms كحد أقصى
		return
	_tick_cooldown = time_now
	
	if is_up:
		play_sound(SoundType.TICK_UP, intensity * 0.1)
	else:
		play_sound(SoundType.TICK_DOWN, intensity * 0.1)

## ============================================
## تشغيل خلفية السوق
## ============================================
func play_ambient() -> void:
	if _ambient_player and not _ambient_player.playing:
		var stream := _generate_ambient()
		if stream:
			_ambient_player.stream = stream
			_ambient_player.play()

func stop_ambient() -> void:
	if _ambient_player:
		_ambient_player.stop()

## ============================================
## توليد الأصوات ديناميكياً (بدون ملفات خارجية)
## باستخدام AudioStreamGenerator في Godot 4
## ============================================
func _generate_sound(sound_type: SoundType, _variation: float) -> AudioStream:
	## استخدام Waveform بسيط
	var generator := AudioStreamWaveform.new()
	
	match sound_type:
		SoundType.BUY_ORDER:
			generator.waveform = AudioStreamWaveform.WAVEFORM_SINE
			generator.frequency = 880.0  ## A5
			generator.amplitude = 0.5
			generator.mix_rate = 44100
			generator.duration = 0.15
			
		SoundType.SELL_ORDER:
			generator.waveform = AudioStreamWaveform.WAVEFORM_SINE
			generator.frequency = 440.0  ## A4
			generator.amplitude = 0.5
			generator.duration = 0.15
			
		SoundType.TRADE_CLOSE_WIN:
			generator.waveform = AudioStreamWaveform.WAVEFORM_SINE
			generator.frequency = 1200.0  ## نغمة مرتفعة = ربح
			generator.amplitude = 0.4
			generator.duration = 0.3
			
		SoundType.TRADE_CLOSE_LOSS:
			generator.waveform = AudioStreamWaveform.WAVEFORM_SAWTOOTH
			generator.frequency = 200.0  ## نغمة منخفضة = خسارة
			generator.amplitude = 0.3
			generator.duration = 0.3
			
		SoundType.MARGIN_CALL:
			generator.waveform = AudioStreamWaveform.WAVEFORM_SQUARE
			generator.frequency = 600.0
			generator.amplitude = 0.4
			generator.duration = 0.5
			
		SoundType.LIQUIDATION:
			generator.waveform = AudioStreamWaveform.WAVEFORM_SAWTOOTH
			generator.frequency = 150.0
			generator.amplitude = 0.6
			generator.duration = 0.8
			
		SoundType.LEVEL_UP:
			generator.waveform = AudioStreamWaveform.WAVEFORM_SINE
			generator.frequency = 523.0  ## C5
			generator.amplitude = 0.4
			generator.duration = 0.2
			
		SoundType.BADGE_EARNED:
			generator.waveform = AudioStreamWaveform.WAVEFORM_SINE
			generator.frequency = 1047.0  ## C6
			generator.amplitude = 0.4
			generator.duration = 0.25
			
		SoundType.TICK_UP:
			generator.waveform = AudioStreamWaveform.WAVEFORM_SINE
			generator.frequency = 2000.0
			generator.amplitude = 0.1
			generator.duration = 0.05
			
		SoundType.TICK_DOWN:
			generator.waveform = AudioStreamWaveform.WAVEFORM_SINE
			generator.frequency = 1500.0
			generator.amplitude = 0.1
			generator.duration = 0.05
			
		SoundType.NOTIFICATION:
			generator.waveform = AudioStreamWaveform.WAVEFORM_TRIANGLE
			generator.frequency = 800.0
			generator.amplitude = 0.3
			generator.duration = 0.2
			
		_:
			return null
	
	return generator

## ============================================
## توليد صوت خلفية الأسواق
## ============================================
func _generate_ambient() -> AudioStream:
	var generator := AudioStreamWaveform.new()
	generator.waveform = AudioStreamWaveform.WAVEFORM_SINE
	generator.frequency = 80.0  ## همهمة منخفضة
	generator.amplitude = 0.1
	generator.mix_rate = 44100
	generator.duration = 30.0
	return generator

## ============================================
## _process - تحديث شدة التقلبات
## ============================================
func _process(delta: float) -> void:
	## تخفيف شدة التقلبات تدريجياً
	tick_intensity = lerpf(tick_intensity, 0.0, delta * 0.5)
