## ============================================
## SoundManager.gd - مدير الأصوات وتأثيرات الأسواق
## ============================================
extends Node
class_name SoundManager

enum SoundType {
	BUY_ORDER, SELL_ORDER, TRADE_CLOSE_WIN, TRADE_CLOSE_LOSS,
	MARGIN_CALL, LIQUIDATION, TICK_UP, TICK_DOWN,
	LEVEL_UP, BADGE_EARNED, NOTIFICATION, AMBIENT_MARKET
}

var master_volume: float = 0.7
var sfx_volume: float = 0.8
var ambient_volume: float = 0.3
var is_muted: bool = false

var _sfx_players: Array = []
var _ambient_player: AudioStreamPlayer
var _tick_cooldown: float = 0.0
var tick_intensity: float = 0.0
const MAX_SFX_PLAYERS: int = 8

func _ready() -> void:
	for i in range(MAX_SFX_PLAYERS):
		var player = AudioStreamPlayer.new()
		add_child(player)
		_sfx_players.append(player)
	_ambient_player = AudioStreamPlayer.new()
	add_child(_ambient_player)
	print("[SoundManager] Ready")

func play_sound(_sound_type: int, _pitch: float = 0.0) -> void:
	if is_muted: return
	for p in _sfx_players:
		if not p.playing:
			p.pitch_scale = 1.0 + _pitch
			p.volume_db = linear_to_db(sfx_volume)
			p.play()
			break

func play_tick(is_up: bool, intensity: float = 1.0) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - _tick_cooldown < 0.1: return
	_tick_cooldown = now
	play_sound(SoundType.TICK_UP if is_up else SoundType.TICK_DOWN, intensity * 0.1)

func play_ambient() -> void:
	pass

func stop_ambient() -> void:
	if _ambient_player: _ambient_player.stop()

func _process(delta: float) -> void:
	tick_intensity = lerpf(tick_intensity, 0.0, delta * 0.5)
