extends Node
## 程序合成音效：不依赖任何音频文件。

const RATE := 22050

var streams := {}
var players: Array = []
var _rr := 0
var muted := false
var amb: AudioStreamPlayer


func _ready() -> void:
	for k in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players.append(p)
	streams["stomp"] = _make(0.55, _stomp)
	streams["thud"] = _make(0.25, _thud)
	streams["jump"] = _make(0.12, _jump)
	streams["land"] = _make(0.12, _land)
	streams["bell"] = _make(2.2, _bell)
	streams["gate"] = _make(0.9, _gate)
	streams["die"] = _make(0.7, _die)
	streams["win"] = _make(1.6, _win)
	streams["beat"] = _make(0.45, _beat)
	streams["tick"] = _make(0.08, _tick)
	streams["ui"] = _make(0.1, _ui)
	amb = AudioStreamPlayer.new()
	amb.stream = _make_loop(8.0, _ambient)
	amb.volume_db = -20.0
	add_child(amb)
	amb.play()


func play(name: String, pitch := 1.0, vol_db := 0.0) -> void:
	if muted or not streams.has(name):
		return
	var p: AudioStreamPlayer = players[_rr]
	_rr = (_rr + 1) % players.size()
	p.stream = streams[name]
	p.pitch_scale = pitch
	p.volume_db = vol_db
	p.play()


func set_muted(m: bool) -> void:
	muted = m
	amb.stream_paused = m


func _make(dur: float, fn: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(fn.call(t, dur), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _make_loop(dur: float, fn: Callable) -> AudioStreamWAV:
	var s := _make(dur, fn)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(dur * RATE)
	return s


static func _env(t: float, a: float, d: float) -> float:
	if t < a:
		return t / a
	return exp(-(t - a) / d)


func _stomp(t: float, _d: float) -> float:
	# 低沉的"咚" + 玻璃般的"叮"
	var low := sin(TAU * (90.0 + 60.0 * exp(-t * 30.0)) * t) * _env(t, 0.004, 0.09) * 0.7
	var ping := (sin(TAU * 880.0 * t) * 0.5 + sin(TAU * 1320.0 * t) * 0.25 + sin(TAU * 2217.0 * t) * 0.12) * _env(t, 0.002, 0.22) * 0.45
	return low + ping


func _thud(t: float, _d: float) -> float:
	return sin(TAU * (70.0 + 40.0 * exp(-t * 40.0)) * t) * _env(t, 0.003, 0.06) * 0.6 + (randf() * 2.0 - 1.0) * _env(t, 0.001, 0.02) * 0.15


func _jump(t: float, _d: float) -> float:
	var f := 380.0 + 900.0 * t
	return sin(TAU * f * t) * _env(t, 0.004, 0.04) * 0.25


func _land(t: float, _d: float) -> float:
	return (randf() * 2.0 - 1.0) * _env(t, 0.001, 0.025) * 0.25 + sin(TAU * 110.0 * t) * _env(t, 0.002, 0.04) * 0.3


func _bell(t: float, _d: float) -> float:
	var f := 660.0
	var v := 0.0
	var partials := [[1.0, 1.0, 1.2], [2.76, 0.5, 0.6], [5.4, 0.25, 0.3], [0.5, 0.35, 1.6], [4.07, 0.15, 0.25]]
	for p in partials:
		v += sin(TAU * f * p[0] * t) * p[1] * exp(-t / p[2])
	return v * _env(t, 0.003, 10.0) * 0.32


func _gate(t: float, d: float) -> float:
	var f := 220.0 + 440.0 * (t / d)
	return (sin(TAU * f * t) * 0.3 + sin(TAU * f * 1.5 * t) * 0.15) * sin(PI * t / d) * 0.6


func _die(t: float, _d: float) -> float:
	var f := 300.0 * exp(-t * 3.0) + 50.0
	return (sin(TAU * f * t) * 0.5 + (randf() * 2.0 - 1.0) * 0.3 * exp(-t * 8.0)) * _env(t, 0.003, 0.22)


func _win(t: float, _d: float) -> float:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var v := 0.0
	for k in notes.size():
		var st := k * 0.11
		if t > st:
			var tt := t - st
			v += (sin(TAU * notes[k] * tt) + 0.3 * sin(TAU * notes[k] * 2.0 * tt)) * _env(tt, 0.005, 0.5) * 0.22
	return v


func _beat(t: float, _d: float) -> float:
	# 心跳：两下
	var v := sin(TAU * (60.0 + 30.0 * exp(-t * 25.0)) * t) * _env(t, 0.004, 0.07)
	if t > 0.18:
		var tt := t - 0.18
		v += 0.7 * sin(TAU * (55.0 + 25.0 * exp(-tt * 25.0)) * tt) * _env(tt, 0.004, 0.08)
	return v * 0.8


func _tick(t: float, _d: float) -> float:
	return sin(TAU * 1760.0 * t) * _env(t, 0.001, 0.015) * 0.2


func _ui(t: float, _d: float) -> float:
	return sin(TAU * 990.0 * t) * _env(t, 0.002, 0.03) * 0.25


func _ambient(t: float, d: float) -> float:
	# 柔和的长音铺底（无缝循环：频率取 1/d 的整数倍）
	var base := 1.0 / d
	var v := 0.0
	var fs := [110.0, 164.8, 220.0, 277.2]
	for k in fs.size():
		var f: float = round(fs[k] / base) * base
		var lfo := 0.5 + 0.5 * sin(TAU * base * (k + 1) * t + k)
		v += sin(TAU * f * t) * lfo * 0.12
	return v
