extends Node
## 喵态 · 声音全部在运行时合成：喵、呼噜、拍手、炸毛、蹦床、八音盒小曲

const RATE := 22050

var sfx := {}
var players: Array = []
var next_player := 0
var purr_player: AudioStreamPlayer
var purr_target := -60.0
var music_player: AudioStreamPlayer
var music_pb: AudioStreamGeneratorPlayback
var music_on := true
var muted := false
var _last_play := {}

# 八音盒
var table := PackedFloat32Array()
var voices: Array = []
var seq_t := 0.0
var seq_i := 0
const BEAT := 0.42
const MELODY := [
	# [拍内八分音符序号, MIDI 音高, 力度]  每小节 8 个八分音符，共 8 小节
	[0, 76, 0.8], [1, 79, 0.6], [2, 81, 0.7], [3, 79, 0.5], [4, 76, 0.7], [5, 74, 0.5], [6, 72, 0.7],
	[8, 74, 0.7], [9, 76, 0.6], [10, 79, 0.7], [11, 76, 0.5], [12, 74, 0.8],
	[16, 72, 0.7], [17, 76, 0.6], [18, 81, 0.8], [19, 79, 0.5], [20, 76, 0.6], [21, 74, 0.5], [22, 72, 0.6], [23, 74, 0.5],
	[24, 76, 0.8],
	[32, 81, 0.8], [33, 79, 0.6], [34, 76, 0.6], [35, 74, 0.5], [36, 72, 0.7], [37, 74, 0.5], [38, 76, 0.7],
	[40, 79, 0.7], [41, 76, 0.5], [42, 74, 0.6], [43, 72, 0.5], [44, 69, 0.8],
	[48, 79, 0.7], [49, 81, 0.6], [50, 79, 0.6], [51, 76, 0.5], [52, 74, 0.6], [53, 76, 0.5], [54, 74, 0.6], [55, 72, 0.5],
	[56, 74, 0.8],
]
const BASS := [[0, 48], [16, 45], [32, 41], [48, 43]]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_table()
	_make_sfx()
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	purr_player = AudioStreamPlayer.new()
	purr_player.stream = sfx["purr"]
	purr_player.volume_db = -60.0
	add_child(purr_player)
	purr_player.play()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.4
	music_player = AudioStreamPlayer.new()
	music_player.stream = gen
	music_player.volume_db = -11.0
	add_child(music_player)
	music_player.play()
	music_pb = music_player.get_stream_playback()


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)


func play(name: String, pitch: float = 1.0, vol: float = 0.0, min_gap: float = 0.0) -> void:
	if not sfx.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if min_gap > 0.0 and now - float(_last_play.get(name, -9.0)) < min_gap:
		return
	_last_play[name] = now
	var p: AudioStreamPlayer = players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = sfx[name]
	p.pitch_scale = pitch
	p.volume_db = vol
	p.play()


func set_purr(level: float) -> void:
	# level 0..1：脚下呼噜声
	purr_target = lerpf(-40.0, -9.0, clampf(level, 0.0, 1.0)) if level > 0.01 else -60.0


func _process(delta: float) -> void:
	purr_player.volume_db = lerpf(purr_player.volume_db, purr_target, minf(1.0, delta * 3.0))
	_fill_music()


# ---------------------------------------------------------------- 八音盒

func _build_table() -> void:
	table.resize(1024)
	for i in 1024:
		var ph := TAU * float(i) / 1024.0
		table[i] = (sin(ph) + 0.32 * sin(2.0 * ph) + 0.1 * sin(3.0 * ph) + 0.05 * sin(5.0 * ph)) / 1.3


func _note(midi: int, vel: float, decay: float, bell: bool) -> void:
	var f := 440.0 * pow(2.0, float(midi - 69) / 12.0)
	voices.append({"ph": 0.0, "inc": f / float(RATE), "amp": vel, "decay": decay, "t": 0.0, "bell": bell, "ph2": 0.0})
	if voices.size() > 10:
		voices.pop_front()


func _fill_music() -> void:
	if music_pb == null:
		return
	var n := music_pb.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var dt := 1.0 / float(RATE)
	var eighth := BEAT * 0.5
	for i in n:
		if music_on:
			seq_t += dt
			while seq_t >= eighth:
				seq_t -= eighth
				_step_seq()
		var s := 0.0
		for v in voices:
			v["t"] += dt
			v["ph"] = fmod(v["ph"] + v["inc"], 1.0)
			var env: float = v["amp"] * exp(-v["t"] / v["decay"])
			var x: float = table[int(v["ph"] * 1024.0) & 1023]
			if v["bell"]:
				v["ph2"] = fmod(v["ph2"] + v["inc"] * 2.76, 1.0)
				x += 0.25 * table[int(v["ph2"] * 1024.0) & 1023] * exp(-v["t"] / 0.12)
			s += x * env
		s *= 0.22
		buf[i] = Vector2(s, s)
	music_pb.push_buffer(buf)
	# 回收已经听不见的音
	var keep: Array = []
	for v in voices:
		if v["t"] < v["decay"] * 6.0:
			keep.append(v)
	voices = keep


func _step_seq() -> void:
	var pos := seq_i % 64
	for m in MELODY:
		if m[0] == pos:
			_note(m[1], m[2], 0.55, true)
	for b in BASS:
		if b[0] == pos or b[0] + 8 == pos:
			_note(b[1], 0.55, 1.4, false)
			_note(b[1] + 7, 0.25, 1.1, false)
	seq_i += 1


func chime(notes: Array) -> void:
	# 过关：几声八音盒
	for i in notes.size():
		get_tree().create_timer(0.13 * float(i)).timeout.connect(_note.bind(int(notes[i]), 0.9, 0.9, true))


# ---------------------------------------------------------------- 音效合成

func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _make_sfx() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	sfx["meow"] = _wav(_meow(0.42, 560.0, 800.0, 470.0, rng))
	sfx["mew"] = _wav(_meow(0.2, 900.0, 1180.0, 980.0, rng))
	sfx["old_meow"] = _wav(_meow(0.62, 330.0, 430.0, 260.0, rng))
	sfx["purr"] = _wav(_purr(rng), true)
	sfx["clap"] = _wav(_clap(rng))
	sfx["hiss"] = _wav(_hiss(rng))
	sfx["boing"] = _wav(_sweep(0.55, 170.0, 560.0, 0.9))
	sfx["pop"] = _wav(_sweep(0.09, 620.0, 980.0, 0.5))
	sfx["doze"] = _wav(_sweep(0.3, 520.0, 330.0, 0.35))
	sfx["step"] = _wav(_thump(0.09, 120.0, 0.6, rng))
	sfx["land"] = _wav(_thump(0.12, 90.0, 0.8, rng))
	sfx["box"] = _wav(_thump(0.35, 70.0, 1.0, rng))
	sfx["click"] = _wav(_sweep(0.03, 1400.0, 1200.0, 0.35))
	sfx["laser"] = _wav(_sweep(0.05, 2200.0, 2600.0, 0.18))
	sfx["sparkle"] = _wav(_bells([84, 88, 91], 0.07, 0.6))
	sfx["win"] = _wav(_bells([72, 76, 79, 84, 88], 0.12, 0.8))


func _meow(dur: float, f0: float, f1: float, f2: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var u := t / dur
		var f := lerpf(f0, f1, smoothstep(0.0, 0.35, u)) if u < 0.35 else lerpf(f1, f2, smoothstep(0.35, 1.0, u))
		f *= 1.0 + 0.012 * sin(t * TAU * 6.0)
		ph += f / float(RATE)
		var a := TAU * ph
		# 元音从“咿”到“呜”：高次谐波逐渐减弱
		var bright := lerpf(0.9, 0.25, u)
		var x := sin(a) + 0.55 * bright * sin(2.0 * a) + 0.35 * bright * sin(3.0 * a) + 0.18 * bright * sin(4.0 * a)
		var env := smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.7, 1.0, u))
		out[i] = (x * 0.32 + rng.randf_range(-0.03, 0.03)) * env
	return out


func _purr(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 1.6
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var pulse := pow(maxf(0.0, sin(TAU * 25.0 * t)), 3.0)
		var breath := 0.6 + 0.4 * sin(TAU * t / dur)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		var x := lp * 2.2 * pulse + 0.25 * sin(TAU * 50.0 * t) * pulse
		out[i] = x * 0.55 * breath
	return out


func _clap(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.3
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var env := exp(-t / 0.035) + 0.6 * exp(-maxf(0.0, t - 0.011) / 0.03) * float(t > 0.011) + 0.3 * exp(-maxf(0.0, t - 0.022) / 0.05) * float(t > 0.022)
		var w := rng.randf_range(-1.0, 1.0)
		hp = 0.85 * (hp + w - prev)
		prev = w
		out[i] = hp * env * 0.7
	return out


func _hiss(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.38
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var u := float(i) / float(n)
		var w := rng.randf_range(-1.0, 1.0)
		hp = 0.92 * (hp + w - prev)
		prev = w
		var env := smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.45, 1.0, u))
		out[i] = hp * env * 0.38
	return out


func _sweep(dur: float, f0: float, f1: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var u := float(i) / float(n)
		var f := lerpf(f0, f1, u) * (1.0 + 0.03 * sin(u * 40.0))
		ph += f / float(RATE)
		var env := smoothstep(0.0, 0.05, u) * pow(1.0 - u, 1.6)
		out[i] = (sin(TAU * ph) + 0.2 * sin(TAU * ph * 2.0)) * env * vol * 0.6
	return out


func _thump(dur: float, f: float, vol: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.25
		var env := exp(-t / (dur * 0.25))
		out[i] = (sin(TAU * f * t * (1.0 - t * 1.5)) * 0.8 + lp * 0.5) * env * vol * 0.7
	return out


func _bells(notes: Array, gap: float, vol: float) -> PackedFloat32Array:
	var dur := gap * float(notes.size()) + 1.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for j in notes.size():
		var f := 440.0 * pow(2.0, float(int(notes[j]) - 69) / 12.0)
		var start := int(gap * float(j) * RATE)
		for i in range(start, n):
			var t := float(i - start) / float(RATE)
			var env := exp(-t / 0.35)
			if env < 0.002:
				break
			out[i] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.76 * t) * exp(-t / 0.08)) * env * vol * 0.3
	return out
