extends Node2D
## 游戏外壳：标题、选关、关卡流程、HUD、结局、存档。

const SAVE_PATH := "user://ripple_save.cfg"
const SHADER_BG := preload("res://shaders/background.gdshader")
const SHADER_MEDIUM := preload("res://shaders/medium.gdshader")

enum State { TITLE, PLAY, END }

var state := State.TITLE
var levels: Array
var cur := 0
var unlocked := 1
var level: Level
var sfx: Node
var deaths := 0
var level_time := 0.0
var best := {}
var restart_pending := -1.0
var advance_pending := -1.0

var bg: ColorRect
var world: Node2D
var hud: CanvasLayer
var lbl_level: Label
var lbl_poem: Label
var lbl_keys: Label
var lbl_stats: Label
var fade: ColorRect
var fade_a := 1.0
var fade_target := 0.0
var poem_t := 0.0

# 标题 / 结局用的装饰活膜
var deco: Node2D
var deco_medium: Medium
var deco_rect: ColorRect
var deco_tex: ImageTexture
var deco_buf := PackedFloat32Array()
var deco_t := 0.0
var deco_next := 0.0
var title_ui: Control
var title_sel := 0
var title_cells: Array = []
var end_ui: Control
var time := 0.0

# 调试 / 自动化
var auto_shots := ""
var shot_times: Array = []
var replay: Array = []
var replay_i := 0


func _ready() -> void:
	_setup_input()
	levels = Levels.all()
	_load()
	sfx = preload("res://scripts/sfx.gd").new()
	add_child(sfx)

	bg = ColorRect.new()
	bg.size = Vector2(1280, 720)
	var bm := ShaderMaterial.new()
	bm.shader = SHADER_BG
	bg.material = bm
	add_child(bg)

	world = Node2D.new()
	add_child(world)

	_build_hud()
	_parse_args()
	if state == State.TITLE:
		_enter_title()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			cur = clampi(int(a.substr(8)) - 1, 0, levels.size() - 1)
			unlocked = maxi(unlocked, cur + 1)
			state = State.PLAY
			_start_level(cur)
			fade_a = 0.0
		elif a.begins_with("--shots="):
			auto_shots = a.substr(8)
		elif a.begins_with("--shot-times="):
			for s in a.substr(13).split(","):
				shot_times.append(float(s))
		elif a.begins_with("--replay="):
			var f := FileAccess.open(a.substr(9), FileAccess.READ)
			if f:
				replay = JSON.parse_string(f.get_as_text())
		elif a == "--ending":
			_enter_end()
			fade_a = 0.0


func _setup_input() -> void:
	var map := {
		"left": [KEY_A, KEY_LEFT],
		"right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE, KEY_W, KEY_UP, KEY_K],
		"stomp": [KEY_J, KEY_S, KEY_DOWN, KEY_X],
		"restart": [KEY_R],
		"back": [KEY_ESCAPE],
		"mute": [KEY_M],
		"confirm": [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER],
	}
	for act in map:
		if not InputMap.has_action(act):
			InputMap.add_action(act)
		for k in map[act]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(act, e)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	lbl_level = _label(22, Color(0.85, 0.88, 1.0, 0.85))
	lbl_level.position = Vector2(28, 18)
	lbl_stats = _label(16, Color(0.7, 0.74, 0.95, 0.6))
	lbl_stats.position = Vector2(1280 - 330, 22)
	lbl_stats.size = Vector2(300, 30)
	lbl_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_poem = _label(24, Color(1.0, 0.95, 0.85, 0.0))
	lbl_poem.position = Vector2(0, 636)
	lbl_poem.size = Vector2(1280, 40)
	lbl_poem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_keys = _label(16, Color(0.75, 0.8, 1.0, 0.75))
	lbl_keys.position = Vector2(0, 680)
	lbl_keys.size = Vector2(1280, 30)
	lbl_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fade = ColorRect.new()
	fade.size = Vector2(1280, 720)
	fade.color = Color(0.02, 0.02, 0.05, 1.0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fade)


func _label(sz: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(l)
	return l


# ---------------- 存档 ----------------
func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		unlocked = clampi(cf.get_value("p", "unlocked", 1), 1, levels.size())
		best = cf.get_value("p", "best", {})


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("p", "unlocked", unlocked)
	cf.set_value("p", "best", best)
	cf.save(SAVE_PATH)


# ---------------- 关卡流程 ----------------
func _start_level(i: int, fresh := true) -> void:
	_clear_world()
	cur = i
	if fresh:
		deaths = 0
		level_time = 0.0
		poem_t = 0.0
	level = Level.new()
	world.add_child(level)
	level.build(levels[i], sfx)
	level.died.connect(_on_died)
	level.won.connect(_on_won)
	restart_pending = -1.0
	advance_pending = -1.0
	replay_i = 0
	var d: Dictionary = levels[i]
	lbl_level.text = "%02d  ·  %s" % [i + 1, d.name]
	lbl_poem.text = d.get("poem", "")
	lbl_keys.text = d.get("keys", "")
	lbl_level.visible = true
	lbl_stats.visible = true
	lbl_keys.visible = true
	lbl_poem.visible = true


func _clear_world() -> void:
	for c in world.get_children():
		c.queue_free()
	level = null
	deco = null


func _on_died() -> void:
	deaths += 1
	restart_pending = 0.55


func _on_won() -> void:
	var key := str(cur)
	var prev: float = best.get(key, 1e9)
	if level_time < prev:
		best[key] = level_time
	unlocked = maxi(unlocked, mini(cur + 2, levels.size()))
	_save()
	advance_pending = 1.1


func _physics_process(dt: float) -> void:
	if state == State.PLAY and level:
		var inp := _gather_input()
		level.physics(dt, inp)
		if not level.finished and level.dead_t < 0.0:
			level_time += dt


func _gather_input() -> Dictionary:
	if replay.size() > 0:
		return _replay_input()
	var x := 0.0
	if Input.is_action_pressed("left"):
		x -= 1.0
	if Input.is_action_pressed("right"):
		x += 1.0
	return {
		"x": x,
		"jump": Input.is_action_just_pressed("jump"),
		"jump_held": Input.is_action_pressed("jump"),
		"stomp": Input.is_action_just_pressed("stomp"),
	}


## 回放格式：[[时刻, "动作"], ...]，动作：L/R/N(停) J(跳) j(松跳) S(踩)
var _rp_x := 0.0
var _rp_hold := false


func _replay_input() -> Dictionary:
	var t := level.time
	var inp := {"x": _rp_x, "jump": false, "jump_held": _rp_hold, "stomp": false}
	while replay_i < replay.size() and replay[replay_i][0] <= t:
		var a: String = replay[replay_i][1]
		match a:
			"L": _rp_x = -1.0
			"R": _rp_x = 1.0
			"N": _rp_x = 0.0
			"J":
				inp.jump = true
				_rp_hold = true
			"j": _rp_hold = false
			"S": inp.stomp = true
		replay_i += 1
	inp.x = _rp_x
	inp.jump_held = _rp_hold
	return inp


func _process(dt: float) -> void:
	time += dt
	var bm: ShaderMaterial = bg.material
	bm.set_shader_parameter("time_s", time)
	fade_a = move_toward(fade_a, fade_target, dt * 3.0)
	fade.color.a = fade_a

	if Input.is_action_just_pressed("mute"):
		sfx.set_muted(not sfx.muted)

	match state:
		State.TITLE:
			_title_process(dt)
		State.PLAY:
			_play_process(dt)
		State.END:
			_end_process(dt)
	_auto_shot()


func _play_process(dt: float) -> void:
	if level == null:
		return
	level.visual_update(dt)
	var s := level.shake
	world.position = Vector2(randf_range(-s, s), randf_range(-s, s)) * 0.5
	bm_pulse(level.pulse * 0.3)
	poem_t += dt
	var pa := clampf(poem_t / 1.2, 0.0, 1.0) * clampf((7.0 - poem_t) / 1.5, 0.0, 1.0)
	lbl_poem.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, pa))
	lbl_stats.text = "回溯 %d    %s" % [deaths, _fmt_time(level_time)]

	if Input.is_action_just_pressed("restart") and advance_pending < 0.0:
		_start_level(cur, false)
		return
	if Input.is_action_just_pressed("back"):
		_enter_title()
		return
	if restart_pending >= 0.0:
		restart_pending -= dt
		if restart_pending < 0.0:
			_start_level(cur, false)
	if advance_pending >= 0.0:
		advance_pending -= dt
		fade_target = 1.0
		if advance_pending < 0.0:
			fade_target = 0.0
			if cur + 1 < levels.size():
				_start_level(cur + 1)
			else:
				_enter_end()


func bm_pulse(v: float) -> void:
	var bm: ShaderMaterial = bg.material
	bm.set_shader_parameter("pulse", v)


func _fmt_time(t: float) -> String:
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


# ---------------- 装饰活膜（标题 / 结局） ----------------
func _make_deco(shape: String) -> void:
	_clear_world()
	deco = Node2D.new()
	world.add_child(deco)
	deco_medium = Medium.new()
	var cx := Medium.W * 0.5
	var cy := Medium.H * 0.5
	for y in Medium.H:
		for x in Medium.W:
			var on := true
			if shape == "heart":
				var u := (x + 0.5 - cx) / 12.5
				var v := -(y + 0.5 - cy - 1.0) / 11.0
				on = pow(u * u + v * v - 1.0, 3.0) - u * u * v * v * v <= 0.02
			deco_medium.kind[deco_medium.idx(x, y)] = Medium.MED if on else Medium.EMPTY
	if shape == "heart":
		deco_medium.add_pacer(deco_medium.idx(int(cx) - 5, int(cy) - 4), 1.6, 0.6)
	deco_medium.reset_state()
	deco_tex = ImageTexture.create_from_image(Image.create(Medium.W, Medium.H, false, Image.FORMAT_RGBAF))
	deco_buf.resize(Medium.W * Medium.H * 4)
	deco_rect = ColorRect.new()
	deco_rect.size = Vector2(1280, 720)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_MEDIUM
	mat.set_shader_parameter("data", deco_tex)
	mat.set_shader_parameter("exc", Medium.EXC)
	mat.set_shader_parameter("refr", Medium.REF)
	mat.set_shader_parameter("speed", Medium.SPEED)
	if shape == "heart":
		mat.set_shader_parameter("smooth_edges", true)
		mat.set_shader_parameter("heart_c", Vector2(cx, cy + 1.0))
		mat.set_shader_parameter("heart_s", Vector2(12.5, 11.0))
	else:
		mat.set_shader_parameter("rest_col", Vector3(0.04, 0.045, 0.1))
		mat.set_shader_parameter("deep_col", Vector3(0.025, 0.03, 0.07))
		mat.set_shader_parameter("dim", 0.5)
	deco_rect.material = mat
	deco.add_child(deco_rect)
	deco_t = 0.0
	deco_next = 0.3
	deco_medium.cell_excited.connect(func(i, _t):
		if shape == "heart" and deco_medium.pdir[i] == 4:
			sfx.play("beat", 1.0, -4.0))


func _deco_update(dt: float, auto: bool) -> void:
	if deco == null:
		return
	deco_t += dt
	deco_medium.step(dt)
	if auto and deco_t > deco_next:
		deco_next = deco_t + randf_range(0.9, 2.2)
		var x := randi_range(4, Medium.W - 5)
		var y := randi_range(4, Medium.H - 5)
		deco_medium.stimulate(deco_medium.idx(x, y))
	deco_medium.pack_texture_data(deco_buf)
	deco_tex.update(Image.create_from_data(Medium.W, Medium.H, false, Image.FORMAT_RGBAF, deco_buf.to_byte_array()))
	var mat: ShaderMaterial = deco_rect.material
	mat.set_shader_parameter("time_s", time)


# ---------------- 标题 ----------------
func _enter_title() -> void:
	state = State.TITLE
	fade_target = 0.0
	_make_deco("field")
	lbl_level.visible = false
	lbl_stats.visible = false
	lbl_keys.visible = false
	lbl_poem.visible = false
	if end_ui:
		end_ui.queue_free()
		end_ui = null
	if title_ui:
		title_ui.queue_free()
	title_ui = Control.new()
	title_ui.size = Vector2(1280, 720)
	title_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(title_ui)
	hud.move_child(fade, -1)
	var t := Label.new()
	t.text = "涟"
	t.add_theme_font_size_override("font_size", 150)
	t.add_theme_color_override("font_color", Color(1.0, 0.97, 0.9))
	t.add_theme_color_override("font_shadow_color", Color(0.45, 0.9, 1.0, 0.22))
	t.add_theme_constant_override("shadow_offset_y", 0)
	t.add_theme_constant_override("shadow_outline_size", 14)
	t.size = Vector2(1280, 200)
	t.position = Vector2(0, 120)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_ui.add_child(t)
	var st := Label.new()
	st.text = "R I P P L E"
	st.add_theme_font_size_override("font_size", 20)
	st.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0, 0.8))
	st.size = Vector2(1280, 30)
	st.position = Vector2(0, 330)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_ui.add_child(st)
	var sub := Label.new()
	sub.text = "你的每一步都激起涟漪，涟漪就是你的路。"
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.85, 0.86, 1.0, 0.85))
	sub.size = Vector2(1280, 40)
	sub.position = Vector2(0, 372)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_ui.add_child(sub)
	# 选关格子
	title_cells.clear()
	var n := levels.size()
	var w := 54.0
	var gap := 12.0
	var total := n * w + (n - 1) * gap
	for k in n:
		var b := Label.new()
		b.text = "%02d" % (k + 1)
		b.add_theme_font_size_override("font_size", 20)
		b.size = Vector2(w, w)
		b.position = Vector2(640 - total * 0.5 + k * (w + gap), 470)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title_ui.add_child(b)
		title_cells.append(b)
	var nm := Label.new()
	nm.name = "LevelName"
	nm.add_theme_font_size_override("font_size", 20)
	nm.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75, 0.9))
	nm.size = Vector2(1280, 30)
	nm.position = Vector2(0, 540)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_ui.add_child(nm)
	var hint := Label.new()
	hint.text = "← →  选关      空格 / 回车  开始      M  静音"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.95, 0.65))
	hint.size = Vector2(1280, 30)
	hint.position = Vector2(0, 640)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_ui.add_child(hint)
	title_sel = clampi(mini(unlocked - 1, levels.size() - 1), 0, levels.size() - 1)
	title_ui.draw.connect(_draw_title_cells)


func _draw_title_cells() -> void:
	for k in title_cells.size():
		var b: Label = title_cells[k]
		var r := Rect2(b.position, b.size)
		var locked := k >= unlocked
		var col := Color(0.4, 0.42, 0.6, 0.4) if locked else Color(0.6, 0.9, 1.0, 0.6)
		if k == title_sel:
			col = Color(1.0, 0.9, 0.6, 1.0)
			title_ui.draw_rect(r.grow(4), Color(1.0, 0.85, 0.5, 0.12))
		title_ui.draw_rect(r, col, false, 2.0)
		if best.has(str(k)):
			title_ui.draw_circle(r.position + Vector2(r.size.x * 0.5, r.size.y - 9), 2.5, Color(1.0, 0.85, 0.5, 0.9))


func _title_process(dt: float) -> void:
	_deco_update(dt, true)
	if title_ui == null:
		return
	for k in title_cells.size():
		var b: Label = title_cells[k]
		var locked := k >= unlocked
		b.add_theme_color_override("font_color", Color(0.45, 0.48, 0.65, 0.6) if locked else (Color(1, 0.95, 0.8) if k == title_sel else Color(0.8, 0.88, 1.0)))
	var nm: Label = title_ui.get_node("LevelName")
	nm.text = levels[title_sel].name if title_sel < unlocked else "· · ·"
	title_ui.queue_redraw()
	if Input.is_action_just_pressed("left"):
		title_sel = maxi(0, title_sel - 1)
		sfx.play("ui", 0.9)
	if Input.is_action_just_pressed("right"):
		title_sel = mini(unlocked - 1, title_sel + 1)
		sfx.play("ui", 1.1)
	if Input.is_action_just_pressed("confirm"):
		sfx.play("stomp")
		title_ui.queue_free()
		title_ui = null
		state = State.PLAY
		fade_a = 1.0
		_start_level(title_sel)
	if Input.is_action_just_pressed("back"):
		get_tree().quit()


# ---------------- 结局 ----------------
func _enter_end() -> void:
	state = State.END
	fade_target = 0.0
	_make_deco("heart")
	lbl_level.visible = false
	lbl_stats.visible = false
	lbl_keys.visible = false
	lbl_poem.visible = false
	end_ui = Control.new()
	end_ui.size = Vector2(1280, 720)
	hud.add_child(end_ui)
	hud.move_child(fade, -1)
	var lines := [
		["它又跳起来了。", 30, 30.0],
		["没有谁规定心跳。每一格只知道：被点亮，传下去，然后休息。", 20, 610.0],
		["节律是从它们之间涌现出来的——就像你的路。", 20, 645.0],
	]
	for l in lines:
		var lb := Label.new()
		lb.text = l[0]
		lb.add_theme_font_size_override("font_size", l[1])
		lb.add_theme_color_override("font_color", Color(1.0, 0.95, 0.88))
		lb.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		lb.add_theme_constant_override("shadow_offset_y", 2)
		lb.size = Vector2(1280, 40)
		lb.position = Vector2(0, l[2])
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		end_ui.add_child(lb)
	var hint := Label.new()
	hint.text = "Esc  回到标题"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.95, 0.6))
	hint.size = Vector2(1280, 30)
	hint.position = Vector2(0, 688)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_ui.add_child(hint)


func _end_process(dt: float) -> void:
	_deco_update(dt, false)
	if end_ui:
		var a := clampf(deco_t / 2.0, 0.0, 1.0)
		end_ui.modulate.a = a
	if Input.is_action_just_pressed("back") or (Input.is_action_just_pressed("confirm") and deco_t > 3.0):
		_enter_title()


# ---------------- 自动截图（验证用） ----------------
func _auto_shot() -> void:
	if auto_shots == "" or shot_times.is_empty():
		return
	var t := level.time if (state == State.PLAY and level) else time
	if t >= shot_times[0]:
		var tt: float = shot_times.pop_front()
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(auto_shots)
		img.save_png("%s/L%02d_t%05.2f.png" % [auto_shots, cur + 1, tt])
		if shot_times.is_empty():
			get_tree().quit()
