extends Node2D
## 喵态 · 一关的运行、表现与界面

const Sim = preload("res://scripts/sim.gd")
const Art = preload("res://scripts/art.gd")
const Deco = preload("res://scripts/deco.gd")
const Levels = preload("res://scripts/levels.gd")
const Discover = preload("res://scripts/discover.gd")
const UI = preload("res://scripts/ui.gd")
const Layer = preload("res://scripts/draw_layer.gd")
const Autoplay = preload("res://scripts/autoplay.gd")

signal request(action: String)

var app = null
var lv: Dictionary = {}
var level_index := 0
var sim
var disc
var demo := false

var root: Node2D
var L_bg: Node2D
var L_light: Node2D
var L_furn: Node2D
var L_sun: Node2D
var L_goal: Node2D
var L_act: Node2D
var L_fxn: Node2D
var L_fx: Node2D
var L_front: Node2D
var ui_layer: CanvasLayer
var vignette: ColorRect

# 输入
var holding := false
var hold_time := 0.0
var mouse := Vector2(640, 360)
var clap_queue: Array = []
var dot_vis := Vector2(640, 360)
var trail: Array = []

# 表现
var vis: Array = []
var prev_pos: Array = []
var old_prev := Vector2.ZERO
var old_vis_y := 0.0
var old_phase := 0.0
var particles: Array = []
var shake := 0.0
var t := 0.0
var won_t := -1.0
var finished := false
var level_time := 0.0
var snapshots: Array = []
var was_quiet := true
var new_finds: Array = []
var hint_i := 0
var tips: Array = []
var tip_text := ""
var used_clap := false
var used_wake := false
var demo_t := 0.0
var paused := false
var autoplay: Dictionary = {}
var auto_runner = null

# 界面
var hud: Control
var title_lbl: Label
var chap_lbl: Label
var meter_lbls: Array = []
var tip_panel: PanelContainer
var tip_lbl: Label
var hint_panel: PanelContainer
var hint_lbl: Label
var toast_box: VBoxContainer
var card: Control
var pause_menu: Control


func setup(app_ref, index: int, is_demo: bool = false) -> void:
	app = app_ref
	level_index = index
	demo = is_demo
	lv = Levels.demo() if demo else Levels.LEVELS[index]


func _ready() -> void:
	UI.load_fonts()
	root = Node2D.new()
	add_child(root)
	L_bg = _layer(_draw_bg)
	L_light = _layer(_draw_light, true)
	L_furn = _layer(_draw_furn)
	L_sun = _layer(_draw_sun)
	L_goal = _layer(_draw_goal)
	L_act = _layer(_draw_actors)
	L_front = _layer(_draw_front)
	L_fxn = _layer(_draw_fxn)
	L_fx = _layer(_draw_fx, true)
	var vl := CanvasLayer.new()
	vl.layer = 1
	add_child(vl)
	vignette = ColorRect.new()
	vignette.size = Vector2(1280, 720)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.28, 0.08, 0.14, 0.38);
void fragment() {
	vec2 uv = UV - 0.5;
	float v = smoothstep(0.38, 0.86, length(uv * vec2(1.0, 0.92)));
	COLOR = vec4(tint.rgb, tint.a * v);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	if lv.get("theme", "") == "roof":
		mat.set_shader_parameter("tint", Color(0.05, 0.04, 0.15, 0.5))
	vignette.material = mat
	vl.add_child(vignette)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	if not demo:
		_build_hud()
	_load()


func _layer(fn: Callable, additive: bool = false) -> Node2D:
	var n := Layer.new()
	n.drawer = fn
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		n.material = m
	root.add_child(n)
	return n


# ================================================================ 载入 / 重来 / 回退

func _load() -> void:
	sim = Sim.new()
	sim.setup(lv, int(lv.get("seed", 7)))
	if lv.get("old_goal", false) and sim.old != null:
		sim.old.mode = Sim.O_GOAL
	disc = Discover.new()
	disc.setup(sim)
	vis.clear()
	prev_pos.clear()
	particles.clear()
	trail.clear()
	snapshots.clear()
	won_t = -1.0
	finished = false
	level_time = 0.0
	hint_i = 0
	used_clap = false
	used_wake = false
	was_quiet = true
	holding = false
	clap_queue.clear()
	_sync_vis()
	if sim.old != null:
		old_prev = sim.old.pos
		old_vis_y = sim.old.pos.y
	snapshots.append(sim.snapshot())
	tips = _make_tips()
	tip_text = ""
	if card != null:
		card.queue_free()
		card = null
	if hint_panel != null:
		hint_panel.visible = false
	for n in [L_bg, L_light, L_furn, L_sun, L_goal, L_front]:
		n.queue_redraw()
	if title_lbl != null:
		chap_lbl.text = Levels.chapter_name(lv)
		title_lbl.text = "%s  %s" % [lv["id"], lv["name"]]


func restart() -> void:
	if app != null:
		app.audio.play("click")
	_load()


func rewind() -> void:
	if snapshots.size() == 0 or won_t >= 0.0:
		return
	var snap: Dictionary = snapshots[snapshots.size() - 1]
	if snapshots.size() > 1 and absf(float(snap["time"]) - sim.time) < 0.6:
		snapshots.pop_back()
		snap = snapshots[snapshots.size() - 1]
	sim.restore(snap)
	vis.clear()
	prev_pos.clear()
	_sync_vis()
	if sim.old != null:
		old_prev = sim.old.pos
		old_vis_y = sim.old.pos.y
	holding = false
	was_quiet = true
	L_furn.queue_redraw()
	if app != null:
		app.audio.play("doze", 1.2)
	_toast_plain("回到上一次安静的时刻")


func _sync_vis() -> void:
	while vis.size() < sim.kits.size():
		var k = sim.kits[vis.size()]
		vis.append({"phase": randf() * 6.0, "sq": Vector2.ONE, "look": Vector2(k.facing, 0), "look_t": 0.0,
			"was_g": true, "vy": 0.0, "z_t": randf() * 3.0, "excl": 0.0, "lastst": k.state})
		prev_pos.append(k.pos)


# ================================================================ 输入

func _unhandled_input(ev: InputEvent) -> void:
	if demo:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and card == null and not paused:
				holding = true
				hold_time = 0.0
				if app != null:
					app.audio.play("laser", 1.0, -14.0)
			elif not mb.pressed:
				if holding:
					disc.note_release(sim.time)
				holding = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and card == null and not paused:
			clap_queue.append(get_global_mouse_position())
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		var k := ev as InputEventKey
		match k.keycode:
			KEY_R:
				restart()
			KEY_Z, KEY_BACKSPACE:
				rewind()
			KEY_H:
				show_hint()
			KEY_ESCAPE:
				toggle_pause()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if card != null:
					request.emit("next")


# ================================================================ 主循环

func _physics_process(_d: float) -> void:
	if paused:
		return
	if autoplay.is_empty():
		mouse = get_global_mouse_position()
	if holding and autoplay.is_empty() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		holding = false
		disc.note_release(sim.time)
	var inp := {"dot_on": holding}
	if demo:
		inp = _demo_input()
	elif not autoplay.is_empty():
		if auto_runner == null:
			auto_runner = Autoplay.Runner.new(autoplay)
		inp = auto_runner.input(sim, level_time, Sim.DT)
		if holding and not inp["dot_on"]:
			disc.note_release(sim.time)
		holding = inp["dot_on"]
		if inp.has("dot"):
			mouse = inp["dot"]
		if holding:
			hold_time += Sim.DT
	else:
		inp["dot"] = mouse
		if not clap_queue.is_empty():
			inp["clap"] = clap_queue.pop_front()
	if holding and autoplay.is_empty():
		hold_time += Sim.DT
	# 记录插值起点
	for i in sim.kits.size():
		prev_pos[i] = sim.kits[i].pos
		vis[i]["vy"] = sim.kits[i].vel.y
		vis[i]["was_g"] = sim.kits[i].grounded
	if sim.old != null:
		old_prev = sim.old.pos
	sim.step(inp)
	level_time += Sim.DT
	_sync_vis()
	_handle_events()
	if not demo:
		var finds: Array = disc.update()
		for f in finds:
			_on_discovery(f)
		_update_tips()
		_check_quiet()
		if sim.won and won_t < 0.0:
			won_t = 0.0
			_on_win()
	if won_t >= 0.0:
		won_t += Sim.DT
		if won_t > 1.7 and not finished:
			finished = true
			_show_card()
	if app != null and app.audio != null:
		var purr := 0.0
		if sim.old != null and sim.old.on_kit and sim.old.mode == Sim.O_WALK:
			purr = 0.75
		var ns := 0
		for k in sim.kits:
			if k.state == Sim.SLEEP:
				ns += 1
		purr = maxf(purr, minf(0.35, float(ns) / 40.0))
		app.audio.set_purr(purr if not demo else purr * 0.5)


func _check_quiet() -> void:
	var q: bool = sim.all_quiet()
	if q and not was_quiet:
		snapshots.append(sim.snapshot())
		if snapshots.size() > 16:
			snapshots.pop_front()
	was_quiet = q


func _handle_events() -> void:
	var au = app.audio if app != null else null
	for e in sim.events:
		match e["t"]:
			"jump":
				if au != null and randf() < 0.12:
					au.play("mew", randf_range(0.9, 1.3), -16.0, 0.12)
			"sleep":
				var k = sim.kits[e["id"]]
				if au != null:
					au.play("doze", randf_range(0.9, 1.15), -20.0, 0.08)
				vis[e["id"]]["sq"] = Vector2(1.12, 0.86)
				if e["why"] == "sun":
					_spark(k.pos + Vector2(0, -14), Color(1, 0.85, 0.4), 3)
			"wake":
				var k2 = sim.kits[e["id"]]
				vis[e["id"]]["sq"] = Vector2(0.86, 1.16)
				if e["why"] == "dot":
					used_wake = true
					if au != null:
						au.play("pop", randf_range(0.95, 1.2), -8.0, 0.05)
						au.play("mew", randf_range(1.0, 1.25), -12.0, 0.1)
					_spark(k2.pos + Vector2(0, -16), Color(1, 0.5, 0.45), 4)
				elif e["why"] == "fall" and au != null:
					au.play("mew", randf_range(1.1, 1.4), -12.0, 0.08)
			"spook":
				var k3 = sim.kits[e["id"]]
				vis[e["id"]]["excl"] = 0.6
				if au != null:
					au.play("hiss", randf_range(0.85, 1.25), -9.0, 0.06)
				for i in 3:
					particles.append({"k": "fur", "p": k3.pos, "v": Vector2(randf_range(-90, 90), randf_range(-140, -30)), "life": 0.6, "max": 0.6, "c": Art.COATS[k3.coat % Art.COATS.size()]["base"]})
			"clap":
				used_clap = true
				shake = maxf(shake, 5.0)
				if au != null:
					au.play("clap", randf_range(0.95, 1.05), -2.0)
				particles.append({"k": "ring", "p": e["p"], "life": 0.45, "max": 0.45, "r": Sim.CLAP_RADIUS})
				particles.append({"k": "text", "p": e["p"] + Vector2(0, -30), "v": Vector2(0, -50), "life": 0.6, "max": 0.6, "s": "啪!"})
			"launch":
				shake = maxf(shake, 7.0)
				if au != null:
					au.play("boing", 1.0, -3.0)
					au.play("old_meow", 1.05, -6.0)
				for i in 10:
					particles.append({"k": "puff", "p": sim.old.pos + Vector2(randf_range(-26, 26), 0), "v": Vector2(randf_range(-60, 60), randf_range(-40, 10)), "life": 0.5, "max": 0.5})
			"land":
				if au != null:
					au.play("land", 1.0, -6.0)
				for i in 6:
					particles.append({"k": "puff", "p": sim.old.pos + Vector2(randf_range(-24, 24), 0), "v": Vector2(randf_range(-70, 70), randf_range(-30, 0)), "life": 0.4, "max": 0.4})
			"step_up":
				if au != null:
					au.play("step", randf_range(0.9, 1.1), -10.0, 0.1)
			"old_wait":
				pass
			"box":
				shake = maxf(shake, 4.0)
				if au != null:
					au.play("box", 1.0, -2.0)
					au.play("meow", 1.25, -8.0)
			"pour":
				if au != null and randf() < 0.3:
					au.play("mew", randf_range(1.0, 1.4), -14.0, 0.06)
			"goal":
				pass


# ================================================================ 演示（标题界面）

func _demo_input() -> Dictionary:
	demo_t += Sim.DT
	var cyc := fmod(demo_t, 16.0)
	var inp := {"dot_on": false}
	if cyc < 9.0:
		var a := demo_t * 0.42
		inp["dot_on"] = true
		inp["dot"] = Vector2(640.0 + sin(a) * 420.0, 470.0 + sin(a * 2.1) * 120.0 - absf(cos(a * 0.7)) * 120.0)
	elif cyc > 12.0 and cyc < 12.0 + Sim.DT * 1.5:
		var c := Vector2(640, 560)
		var n := 0
		for k in sim.kits:
			c += k.pos
			n += 1
		if n > 0:
			c /= float(n + 1)
		inp["clap"] = c + Vector2(0, 20)
	return inp


# ================================================================ 绘制

func _process(delta: float) -> void:
	t += delta
	shake = maxf(0.0, shake - delta * 30.0)
	root.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	var a := Engine.get_physics_interpolation_fraction()
	var target := mouse
	if demo:
		target = sim.dot
	dot_vis = target
	if (holding or (demo and sim.dot_on)):
		trail.push_front(sim.dot)
		if trail.size() > 7:
			trail.pop_back()
	else:
		trail.clear()
	for i in sim.kits.size():
		var k = sim.kits[i]
		var vs: Dictionary = vis[i]
		if k.grounded and k.state == Sim.AWAKE:
			vs["phase"] += absf(k.vel.x) * delta * 0.085
		var sq: Vector2 = vs["sq"]
		vs["sq"] = sq + (Vector2.ONE - sq) * minf(1.0, delta * 10.0)
		# 看向
		var look: Vector2 = vs["look"]
		var want := Vector2(k.facing, 0.1)
		if k.state == Sim.AWAKE and k.sees:
			want = (sim.dot - k.pos).normalized()
		elif k.state == Sim.AWAKE:
			vs["look_t"] -= delta
			if vs["look_t"] <= 0.0:
				vs["look_t"] = randf_range(0.4, 1.2)
				vs["look_rand"] = Vector2(randf_range(-1, 1), randf_range(-1, 0.4)).normalized()
			want = vs.get("look_rand", want)
		vs["look"] = look.lerp(want, minf(1.0, delta * 10.0))
		vs["excl"] = maxf(0.0, vs["excl"] - delta)
		if k.state == Sim.SLEEP and not demo:
			vs["z_t"] -= delta
			if vs["z_t"] <= 0.0:
				vs["z_t"] = randf_range(2.5, 5.0)
				if particles.size() < 80:
					particles.append({"k": "z", "p": k.pos + Vector2(6 * k.facing, -18), "v": Vector2(14, -22), "life": 1.6, "max": 1.6})
	if sim.old != null:
		var o = sim.old
		old_vis_y = lerpf(old_vis_y, lerpf(old_prev.y, o.pos.y, a), minf(1.0, delta * 16.0)) if o.mode != Sim.O_AIR else lerpf(old_prev.y, o.pos.y, a)
		if o.mode == Sim.O_WALK:
			old_phase += delta * 5.2
		if o.mode == Sim.O_GOAL and randf() < delta * 2.0 and particles.size() < 80:
			particles.append({"k": "heart", "p": o.pos + Vector2(randf_range(-10, 20), -50), "v": Vector2(randf_range(-10, 10), -36), "life": 1.4, "max": 1.4})
	# 粒子
	var keep: Array = []
	for p in particles:
		p["life"] -= delta
		if p["life"] > 0.0:
			if p.has("v"):
				p["p"] += p["v"] * delta
				if p["k"] == "fur" or p["k"] == "puff":
					p["v"] *= 0.94
					p["v"].y += 200.0 * delta
			keep.append(p)
	particles = keep
	L_act.queue_redraw()
	L_fx.queue_redraw()
	L_fxn.queue_redraw()
	L_sun.queue_redraw()
	L_goal.queue_redraw()
	if int(t * 20.0) != int((t - delta) * 20.0):
		L_light.queue_redraw()
		L_bg.queue_redraw()
	if not demo:
		_update_hud()


func _kpos(i: int) -> Vector2:
	var a := Engine.get_physics_interpolation_fraction()
	var k = sim.kits[i]
	if k.state == Sim.SLEEP:
		return k.pos
	return (prev_pos[i] as Vector2).lerp(k.pos, a)


func _draw_bg(ci: Node2D) -> void:
	Deco.background(ci, lv, t)


func _draw_light(ci: Node2D) -> void:
	Deco.lights(ci, lv, t)


func _draw_sun(ci: Node2D) -> void:
	if not sim.suns.is_empty():
		Deco.sunbeams(ci, sim.suns, t)


func _draw_furn(ci: Node2D) -> void:
	var tn: String = lv.get("theme", "living")
	var floor_y := float(lv.get("floor_y", 640))
	# 先画地面，再画家具
	for b in sim.blocks:
		if b.kind == "floor":
			Deco.furniture(ci, b.kind, b.r, tn, b.opts)
	var th := Deco.theme(tn)
	for d in lv.get("deco", []):
		if d["type"] == "rug":
			Deco._deco(ci, d, th, tn, t)
	for b in sim.blocks:
		if b.kind == "bound" or b.kind == "floor" or b.kind == "curtain":
			continue
		var opts: Dictionary = b.opts.duplicate()
		opts["floor"] = floor_y
		Deco.furniture(ci, b.kind, b.r, tn, opts)


func _draw_goal(ci: Node2D) -> void:
	if sim.old == null or lv.get("old_goal", false):
		return
	var g: Rect2 = sim.goal
	var c := Vector2(g.get_center().x, g.end.y)
	var pulse := 0.5 + 0.5 * sin(t * 2.6)
	var kind: String = lv.get("goal_kind", "cushion")
	if kind == "moon":
		return
	Art.blob(ci, Art.ellipse(c + Vector2(0, -7), 30, 9, 18), Color("f7a8b8"), Art.OUTLINE, 1.6)
	Art.blob(ci, Art.ellipse(c + Vector2(0, -11), 24, 6, 16), Color("ffc8d3"), Color(0, 0, 0, 0), 0.0)
	if sim.old.mode != Sim.O_GOAL:
		for i in 3:
			var pp := c + Vector2(-18 + i * 18, -34 - pulse * 6.0 - absf(float(i) - 1.0) * 4.0)
			_paw(ci, pp, Color(1.0, 0.55, 0.62, 0.35 + 0.35 * pulse))


func _paw(ci: CanvasItem, p: Vector2, col: Color) -> void:
	ci.draw_circle(p, 4.2, col)
	for j in 3:
		ci.draw_circle(p + Vector2(-4.2 + j * 4.2, -5.6 + absf(float(j) - 1.0) * 1.6), 1.8, col)


func _draw_actors(ci: Node2D) -> void:
	# 影子
	for i in sim.kits.size():
		var k = sim.kits[i]
		if k.grounded or k.state == Sim.SLEEP:
			var p := _kpos(i)
			ci.draw_colored_polygon(Art.ellipse(p + Vector2(0, 14), 15, 3.5, 12), Color(0.2, 0.05, 0.1, 0.13))
	# 睡着的先画（在后面），醒着的、受惊的后画
	var order: Array = []
	for i in sim.kits.size():
		order.append(i)
	order.sort_custom(func(a, b): return _zrank(a) < _zrank(b))
	if sim.old != null:
		_draw_old(ci)
	for i in order:
		var k = sim.kits[i]
		var vs: Dictionary = vis[i]
		var s := {
			"state": k.state, "facing": k.facing, "vx": k.vel.x, "vy": k.vel.y, "grounded": k.grounded,
			"t": t, "phase": vs["phase"], "coat": k.coat, "look": vs["look"], "seed": k.seed,
			"dwell": clampf(k.dwell / Sim.WAKE_DWELL, 0.0, 1.0), "idle": maxf(0.0, k.idle_t) if not k.sees else 0.0,
			"sees": k.sees, "squash": vs["sq"], "spook_t": k.spook_t,
		}
		Art.kitten(ci, _kpos(i), s)


func _zrank(i: int) -> int:
	var st: int = sim.kits[i].state
	if st == Sim.SLEEP:
		return 0
	if st == Sim.FALL:
		return 1
	if st == Sim.AWAKE:
		return 2
	return 3


func _draw_old(ci: CanvasItem) -> void:
	var o = sim.old
	var a := Engine.get_physics_interpolation_fraction()
	var x := lerpf(old_prev.x, o.pos.x, a)
	var feet := Vector2(x, old_vis_y)
	ci.draw_colored_polygon(Art.ellipse(feet + Vector2(0, 1), 28, 5, 16), Color(0.2, 0.05, 0.1, 0.16))
	var s := {"mode": o.mode, "facing": o.dir, "t": t, "phase": old_phase, "wait_t": o.wait_t, "vy": o.vel.y,
		"seed": 1.7, "night": lv.get("theme", "") == "roof"}
	Art.old_cat(ci, feet, s)


func _draw_front(ci: Node2D) -> void:
	for b in sim.blocks:
		if b.kind == "curtain":
			var r: Rect2 = b.r
			var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x + 4, r.end.y), Vector2(r.position.x - 4, r.end.y)])
			Art.blob(ci, pts, Color(0.95, 0.62, 0.66, 0.93), Art.OUTLINE, 1.6)
			for x in range(int(r.position.x) + 8, int(r.end.x) - 2, 12):
				ci.draw_line(Vector2(x, r.position.y + 4), Vector2(x + 2, r.end.y - 4), Color(0.85, 0.48, 0.55, 0.8), 2.0)
			ci.draw_rect(Rect2(r.position.x - 10, r.position.y - 6, r.size.x + 20, 7), Color("c98d5f"))


func _draw_fxn(ci: Node2D) -> void:
	var font: Font = UI.font_title
	# 叫醒进度环
	for i in sim.kits.size():
		var k = sim.kits[i]
		if k.state == Sim.SLEEP and k.dwell > 0.02:
			var p := _kpos(i)
			var fr := clampf(k.dwell / Sim.WAKE_DWELL, 0.0, 1.0)
			ci.draw_arc(p, 21, -PI * 0.5, -PI * 0.5 + TAU * fr, 24, Color(1, 0.35, 0.4, 0.9), 3.0, true)
		elif k.state == Sim.AWAKE and not demo:
			var p2 := _kpos(i)
			if sim.dot_on and not k.sees and k.mem_t > Sim.MEMORY:
				ci.draw_string(font, p2 + Vector2(-4, -26), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.45, 0.35, 0.55, 0.85))
		if vis[i]["excl"] > 0.0:
			var p3 := _kpos(i)
			ci.draw_string(font, p3 + Vector2(-3, -34), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.25, 0.3, minf(1.0, vis[i]["excl"] * 3.0)))
	# 阿黄的念头
	if sim.old != null and sim.old.mode == Sim.O_WAIT and sim.old.wait_t > 0.6 and not demo:
		_bubble(ci, Vector2(sim.old.pos.x + 14 * sim.old.dir, old_vis_y - 74), sim.old.why)
	# 粒子
	for p in particles:
		var a: float = clampf(p["life"] / p["max"], 0.0, 1.0)
		match p["k"]:
			"z":
				ci.draw_string(font, p["p"], "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 + (1.0 - a) * 8), Color(0.42, 0.38, 0.7, a * 0.8))
			"heart":
				_heart(ci, p["p"], 6.0, Color(1, 0.45, 0.55, a))
			"fur":
				var c: Color = p["c"]
				ci.draw_circle(p["p"], 3.0 * a + 1.0, Color(c.r, c.g, c.b, a))
			"puff":
				ci.draw_circle(p["p"], 7.0 * (1.2 - a), Color(1, 0.95, 0.9, a * 0.7))
			"ring":
				var rr: float = p["r"] * (1.0 - a * 0.65)
				ci.draw_arc(p["p"], rr, 0.0, TAU, 48, Color(1, 1, 1, a * 0.9), 3.0, true)
			"text":
				ci.draw_string(font, p["p"] + Vector2(-18, 0), p["s"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.4, 0.35, a))
			"spark":
				var sc: Color = p["c"]
				var q: Vector2 = p["p"]
				var s := 5.0 * a
				ci.draw_line(q + Vector2(-s, 0), q + Vector2(s, 0), Color(sc.r, sc.g, sc.b, a), 2.0, true)
				ci.draw_line(q + Vector2(0, -s), q + Vector2(0, s), Color(sc.r, sc.g, sc.b, a), 2.0, true)
	# 红点本体 / 光标
	if not demo:
		if holding:
			var d: Vector2 = sim.dot
			ci.draw_circle(d, 4.2, Color(1, 0.12, 0.18))
			ci.draw_circle(d + Vector2(-0.8, -0.8), 1.7, Color(1, 0.9, 0.9))
		else:
			ci.draw_arc(mouse, 9.0, 0.0, TAU, 24, Color(0.95, 0.3, 0.35, 0.65), 1.6, true)
			ci.draw_circle(mouse, 1.6, Color(0.95, 0.3, 0.35, 0.8))
	elif sim.dot_on:
		ci.draw_circle(sim.dot, 4.2, Color(1, 0.12, 0.18))


func _bubble(ci: CanvasItem, p: Vector2, why: String) -> void:
	Art.blob(ci, Art.ellipse(p, 19, 15, 18), Color(1, 1, 1, 0.92), Art.OUTLINE, 1.4)
	ci.draw_circle(p + Vector2(-8, 19), 3.5, Color(1, 1, 1, 0.92))
	ci.draw_circle(p + Vector2(-12, 26), 2.2, Color(1, 1, 1, 0.92))
	var c := Color("6a5a8a")
	match why:
		"noisy":
			for i in 3:
				ci.draw_circle(p + Vector2(-8 + i * 8, 1), 2.4, c)
		"high":
			ci.draw_rect(Rect2(p.x + 2, p.y - 8, 7, 15), Color("c9a58a"))
			ci.draw_line(p + Vector2(-7, 7), p + Vector2(-7, -8), c, 2.4, true)
			ci.draw_line(p + Vector2(-7, -8), p + Vector2(-11, -3), c, 2.4, true)
			ci.draw_line(p + Vector2(-7, -8), p + Vector2(-3, -3), c, 2.4, true)
		"cold":
			for i in 3:
				var a := PI * float(i) / 3.0
				ci.draw_line(p - Vector2(cos(a), sin(a)) * 9.0, p + Vector2(cos(a), sin(a)) * 9.0, Color("6fa6e6"), 2.2, true)
			ci.draw_circle(p, 2.4, Color("6fa6e6"))
		_:
			ci.draw_line(p + Vector2(-12, -2), p + Vector2(-3, -2), Color("c9a58a"), 3.0)
			ci.draw_line(p + Vector2(5, -8), p + Vector2(5, 8), c, 2.4, true)
			ci.draw_line(p + Vector2(5, 8), p + Vector2(1, 3), c, 2.4, true)
			ci.draw_line(p + Vector2(5, 8), p + Vector2(9, 3), c, 2.4, true)


func _heart(ci: CanvasItem, p: Vector2, s: float, c: Color) -> void:
	ci.draw_circle(p + Vector2(-s * 0.5, 0), s * 0.6, c)
	ci.draw_circle(p + Vector2(s * 0.5, 0), s * 0.6, c)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 1.08, s * 0.2), p + Vector2(s * 1.08, s * 0.2), p + Vector2(0, s * 1.4)]), c)


func _draw_fx(ci: Node2D) -> void:
	var on: bool = holding if not demo else sim.dot_on
	if on:
		var d: Vector2 = sim.dot
		for i in trail.size():
			var a := 1.0 - float(i) / float(trail.size() + 1)
			Art.glow(ci, trail[i], 10.0 * a + 4.0, Color(1, 0.15, 0.2, 0.25 * a))
		var fl := 0.9 + 0.1 * sin(t * 37.0)
		Art.glow(ci, d, 30.0, Color(1, 0.12, 0.18, 0.55 * fl))
		Art.glow(ci, d, 11.0, Color(1, 0.55, 0.55, 0.9))
	for p in particles:
		if p["k"] == "ring":
			var a2: float = clampf(p["life"] / p["max"], 0.0, 1.0)
			Art.glow(ci, p["p"], p["r"] * (1.0 - a2 * 0.5), Color(1, 0.9, 0.8, a2 * 0.18))
	if sim.old != null and sim.old.mode == Sim.O_GOAL and lv.get("goal_kind", "") != "moon":
		Art.glow(ci, sim.old.pos + Vector2(0, -20), 70.0, Color(1, 0.75, 0.5, 0.25))


func _spark(p: Vector2, c: Color, n: int) -> void:
	for i in n:
		particles.append({"k": "spark", "p": p + Vector2(randf_range(-10, 10), randf_range(-8, 8)), "v": Vector2(randf_range(-40, 40), randf_range(-60, -10)), "life": 0.5, "max": 0.5, "c": c})


# ================================================================ 界面

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.theme = UI.theme()
	ui_layer.add_child(hud)
	# 左上：关卡名
	var tbg := PanelContainer.new()
	tbg.position = Vector2(18, 12)
	tbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := UI.box(Color(0.32, 0.16, 0.2, 0.32), 16, Color(0, 0, 0, 0), 0, 14)
	tsb.shadow_size = 0
	tbg.add_theme_stylebox_override("panel", tsb)
	hud.add_child(tbg)
	var tl := VBoxContainer.new()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_theme_constant_override("separation", -2)
	tbg.add_child(tl)
	chap_lbl = UI.label("", 16, Color(1, 1, 1, 0.9))
	chap_lbl.add_theme_color_override("font_outline_color", Color(0.3, 0.15, 0.15, 0.6))
	chap_lbl.add_theme_constant_override("outline_size", 4)
	tl.add_child(chap_lbl)
	title_lbl = UI.label("", 30, Color.WHITE, true)
	title_lbl.add_theme_color_override("font_outline_color", Color(0.35, 0.16, 0.16, 0.75))
	title_lbl.add_theme_constant_override("outline_size", 6)
	tl.add_child(title_lbl)
	# 右上：按钮
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 8)
	tr.position = Vector2(1280 - 26 - 430, 18)
	tr.size = Vector2(430, 40)
	tr.alignment = BoxContainer.ALIGNMENT_END
	hud.add_child(tr)
	for item in [["提示 H", show_hint], ["回退 Z", rewind], ["重来 R", restart], ["菜单 Esc", toggle_pause]]:
		var b := UI.button(item[0], 17)
		b.pressed.connect(item[1])
		tr.add_child(b)
	# 左下：物态计
	var meter := HBoxContainer.new()
	meter.position = Vector2(26, 720 - 54)
	meter.add_theme_constant_override("separation", 8)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(meter)
	meter_lbls.clear()
	for m in [["液", UI.LIQ], ["固", UI.SOL], ["气", UI.GAS]]:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.pill(Color(m[1].r, m[1].g, m[1].b, 0.92)))
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lb := UI.label("%s 0" % m[0], 18, Color.WHITE, true)
		pc.add_child(lb)
		meter.add_child(pc)
		meter_lbls.append(lb)
	# 下方：提示条
	tip_panel = PanelContainer.new()
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.add_theme_stylebox_override("panel", UI.box(Color(1.0, 0.97, 0.92, 0.92), 18, UI.CORAL, 2, 18))
	tip_lbl = UI.label("", 20)
	tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_lbl.custom_minimum_size = Vector2(0, 0)
	tip_panel.add_child(tip_lbl)
	tip_panel.visible = false
	hud.add_child(tip_panel)
	# 提示面板
	hint_panel = PanelContainer.new()
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_theme_stylebox_override("panel", UI.box(Color(0.99, 0.95, 1.0, 0.95), 18, Color("b9a3e3"), 2, 18))
	hint_lbl = UI.label("", 19, Color("4a3a66"))
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.custom_minimum_size = Vector2(420, 0)
	hint_panel.add_child(hint_lbl)
	hint_panel.position = Vector2(1280 - 26 - 470, 70)
	hint_panel.visible = false
	hud.add_child(hint_panel)
	# 右侧：发现提示
	toast_box = VBoxContainer.new()
	toast_box.position = Vector2(1280 - 26 - 360, 130)
	toast_box.size = Vector2(360, 300)
	toast_box.add_theme_constant_override("separation", 8)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(toast_box)


func _update_hud() -> void:
	if hud == null:
		return
	var c: Array = sim.count_states()
	meter_lbls[0].text = "液 %d" % c[0]
	meter_lbls[1].text = "固 %d" % (c[1] + c[2])
	meter_lbls[2].text = "气 %d" % c[3]
	if tip_text != "":
		if tip_lbl.text != tip_text:
			tip_lbl.text = tip_text
			var tw := UI.font_body.get_string_size(tip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 4.0
			# 一行放得下就不折行；放不下再按 500 宽折行
			tip_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF if tw <= 500.0 else TextServer.AUTOWRAP_WORD_SMART
			tip_lbl.custom_minimum_size = Vector2(minf(tw, 500.0), 0)
		tip_panel.visible = true
		# 折行的标签要排过版才知道自己多高：每帧按内容收一次尺寸，免得卡在一个过高的框里
		tip_panel.reset_size()
		tip_panel.position = Vector2(clampf(560.0 - tip_panel.size.x * 0.5, 250.0, 830.0 - tip_panel.size.x), 20)
	else:
		tip_panel.visible = false
	if hint_panel.visible:
		hint_panel.reset_size()


func show_hint() -> void:
	if hud == null:
		return
	var hs: Array = lv.get("hints", [])
	if hs.is_empty():
		return
	if app != null:
		app.audio.play("click")
	if hint_panel.visible and hint_i >= hs.size():
		hint_panel.visible = false
		hint_i = 0
		return
	hint_i = mini(hint_i + 1, hs.size())
	var txt := ""
	for i in hint_i:
		txt += ("提示 %d：" % (i + 1)) + hs[i] + ("\n" if i < hint_i - 1 else "")
	if hint_i < hs.size():
		txt += "\n（再按 H 看下一条）"
	hint_lbl.text = txt
	hint_panel.visible = true
	hint_panel.reset_size()


func _toast_plain(text: String) -> void:
	if toast_box == null:
		return
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.box(Color(1.0, 0.97, 0.92, 0.94), 14, UI.CORAL, 2, 12))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lb := UI.label(text, 18)
	pc.add_child(lb)
	toast_box.add_child(pc)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(pc, "modulate:a", 0.0, 0.5)
	tw.tween_callback(pc.queue_free)


func _on_discovery(id: String) -> void:
	var d := Discover.info(id)
	if d.is_empty():
		return
	var fresh := true
	if app != null:
		fresh = app.add_discovery(id)
		app.audio.play("sparkle", 1.0, -6.0 if fresh else -14.0)
	new_finds.append(id)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.box(Color(1.0, 0.97, 0.92, 0.96), 16, Color("f4c06a"), 3, 14))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(vb)
	vb.add_child(UI.label(("★ 新发现 · " if fresh else "★ 又看见了 · ") + d["name"], 20, Color("c86a2a"), true))
	vb.add_child(UI.label(d["line"], 18))
	toast_box.add_child(pc)
	pc.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.2 if fresh else 1.6)
	tw.tween_property(pc, "modulate:a", 0.0, 0.6)
	tw.tween_callback(pc.queue_free)


func _on_win() -> void:
	if app != null:
		app.audio.play("win", 1.0, -3.0)
		app.audio.play("old_meow", 1.0, -6.0)
		app.level_done(level_index, level_time)
	for i in 8:
		particles.append({"k": "heart", "p": sim.old.pos + Vector2(randf_range(-30, 30), randf_range(-60, -30)), "v": Vector2(randf_range(-30, 30), randf_range(-70, -30)), "life": 1.6, "max": 1.6})
	tip_text = ""


func _show_card() -> void:
	card = Control.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.theme = UI.theme()
	ui_layer.add_child(card)
	var dim := ColorRect.new()
	dim.color = Color(0.25, 0.1, 0.15, 0.28)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(dim)
	var pc := PanelContainer.new()
	card.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(vb)
	var head := UI.label("阿黄到啦", 22, UI.CORAL, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)
	var line := UI.label(lv.get("line", ""), 34)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(line)
	var finds: Array = disc.found.keys()
	if not finds.is_empty():
		var fl := HFlowContainer.new()
		fl.alignment = FlowContainer.ALIGNMENT_CENTER
		fl.add_theme_constant_override("h_separation", 8)
		fl.add_theme_constant_override("v_separation", 6)
		fl.custom_minimum_size = Vector2(520, 0)
		for f in finds:
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", UI.pill(Color("fde2b8")))
			chip.add_child(UI.label("★ " + Discover.info(f)["name"], 17, Color("a0522d")))
			fl.add_child(chip)
		vb.add_child(UI.label("这一关里冒出来的：", 16, UI.INK_L))
		vb.add_child(fl)
	var stat := UI.label("用时 %d:%02d   ·   小猫 %d 只" % [int(level_time) / 60, int(level_time) % 60, sim.kits.size()], 16, UI.INK_L)
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(stat)
	var other := UI.label(lv.get("other", "同一关还有别的办法吗？换一种试试。"), 16, Color("8a6cae"))
	other.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(other)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	var b1 := UI.button("再玩一次  R", 20)
	b1.pressed.connect(restart)
	hb.add_child(b1)
	var b3 := UI.button("选关", 20)
	b3.pressed.connect(func(): request.emit("select"))
	hb.add_child(b3)
	var last := level_index >= Levels.LEVELS.size() - 1
	var b2 := UI.button("看结尾  Enter" if last else "下一关  Enter", 20)
	b2.pressed.connect(func(): request.emit("next"))
	hb.add_child(b2)
	pc.reset_size()
	await get_tree().process_frame
	pc.reset_size()
	pc.position = Vector2(640, 360) - pc.size * 0.5
	pc.modulate.a = 0.0
	pc.scale = Vector2(0.96, 0.96)
	pc.pivot_offset = pc.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(pc, "modulate:a", 1.0, 0.35)
	tw.tween_property(pc, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func toggle_pause() -> void:
	if hud == null:
		return
	if card != null:
		request.emit("select")
		return
	paused = not paused
	if app != null:
		app.audio.play("click")
	if paused:
		holding = false
		pause_menu = Control.new()
		pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
		pause_menu.theme = UI.theme()
		ui_layer.add_child(pause_menu)
		var dim := ColorRect.new()
		dim.color = Color(0.2, 0.08, 0.14, 0.35)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		pause_menu.add_child(dim)
		var pc := PanelContainer.new()
		pause_menu.add_child(pc)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 10)
		pc.add_child(vb)
		var ttl := UI.label("歇一会儿", 28, UI.CORAL, true)
		ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(ttl)
		var items := [["继续  Esc", toggle_pause], ["重来这一关  R", func(): toggle_pause(); restart()],
			["选关", func(): request.emit("select")], ["喵态图鉴", func(): request.emit("notebook")],
			["静音 / 取消静音  M", func(): app.toggle_mute()], ["全屏 / 窗口  F11", func(): app.toggle_fullscreen()],
			["回到标题", func(): request.emit("title")]]
		for it in items:
			var b := UI.button(it[0], 20)
			b.custom_minimum_size = Vector2(300, 0)
			b.pressed.connect(it[1])
			vb.add_child(b)
		var help := UI.label("左键按住：红点　松开：猫会睡着\n右键：拍手　R 重来　Z 回到上次安静时", 15, UI.INK_L)
		help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(help)
		pc.reset_size()
		await get_tree().process_frame
		if is_instance_valid(pc):
			pc.reset_size()
			pc.position = Vector2(640, 360) - pc.size * 0.5
	else:
		if pause_menu != null:
			pause_menu.queue_free()
			pause_menu = null


# ================================================================ 操作式引导

func _make_tips() -> Array:
	var out: Array = []
	for tp in lv.get("tips", []):
		out.append({"text": tp["text"], "when": tp.get("when", "start"), "until": tp.get("until", ""), "state": 0, "t": 0.0, "min": float(tp.get("min", 2.5))})
	return out


func _cond(c: String) -> bool:
	match c:
		"start":
			return true
		"held":
			return hold_time > 1.0
		"box":
			for s in sim.spawners:
				if s["open"]:
					return true
			return false
		"crowd":
			var n := 0
			for k in sim.kits:
				if k.state == Sim.AWAKE:
					n += 1
			return n >= 8
		"released":
			return not holding and hold_time > 0.5
		"asleep_all":
			return sim.all_quiet() and sim.kits.size() > 0
		"waiting":
			return sim.old != null and sim.old.mode == Sim.O_WAIT and sim.old.wait_t > 4.0 and sim.all_quiet()
		"walking":
			return sim.old != null and sim.old.mode == Sim.O_WALK
		"woke":
			return used_wake
		"clapped":
			return used_clap
		"time10":
			return level_time > 10.0
		"time20":
			return level_time > 20.0
		"won":
			return sim.won
		"never":
			return false
	return false


func _update_tips() -> void:
	tip_text = ""
	if sim.won:
		return
	for tp in tips:
		if tp["state"] == 0 and _cond(tp["when"]):
			tp["state"] = 1
			tp["t"] = 0.0
		if tp["state"] == 1:
			tp["t"] += Sim.DT
			if tp["until"] != "" and _cond(tp["until"]) and tp["t"] > tp["min"]:
				tp["state"] = 2
			elif tp["until"] == "" and tp["t"] > 6.0:
				tp["state"] = 2
			else:
				tip_text = tp["text"]
				return
