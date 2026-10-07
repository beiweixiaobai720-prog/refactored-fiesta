class_name Level
extends Node2D
## 一个关卡：解析字符地图，驱动活膜与玩家，画出墙、钟、门、坝、起搏器与出口。
##
## 地图字符：
##   .  空气        #  墙          ~  活膜
##   ^  地刺(朝上)  v  顶刺(朝下)
##   P  出生点(空气) p  出生点(活膜中)
##   E  出口(空气)   B  钟(活膜)：被波点亮后敲响
##   G  门：所有钟响后打开，变成空气
##   D  坝：所有钟响后打开，变成活膜
##   *  起搏器(活膜)：按固定周期自己点亮

signal died
signal won
signal bell_rung(count: int, total: int)

const C := Medium.CELL
const SHADER_MEDIUM := preload("res://shaders/medium.gdshader")

var data: Dictionary
var medium := Medium.new()
var player: Player
var start_pos := Vector2.ZERO
var exit_rect := Rect2()
var bells: Array = []          # [{i, pos, rung, t}]
var gates: Array = []          # cell indices
var dams: Array = []
var gates_open := false
var open_t := 0.0
var spikes: Array = []         # [{rect, down}]
var finished := false
var dead_t := -1.0
var time := 0.0
var pulse := 0.0

var _tex: ImageTexture
var _img_buf := PackedFloat32Array()
var _medium_rect: ColorRect
var _walls: Node2D
var _objects: Node2D
var _fx: Node2D
var fx_rings: Array = []
var fx_sparks: Array = []
var shake := 0.0
var sfx: Node


func build(d: Dictionary, sfx_node: Node) -> void:
	data = d
	sfx = sfx_node
	var rows: Array = d.map
	for y in Medium.H:
		var row: String = rows[y] if y < rows.size() else ""
		for x in Medium.W:
			var ch := row[x] if x < row.length() else "."
			var i := medium.idx(x, y)
			var k := Medium.EMPTY
			match ch:
				"#":
					k = Medium.WALL
				"~":
					k = Medium.MED
				"^":
					k = Medium.SPIKE
					spikes.append({"rect": Rect2(x * C + 3, y * C + C * 0.45, C - 6, C * 0.55), "down": false, "x": x, "y": y})
				"v":
					k = Medium.SPIKE_DOWN
					spikes.append({"rect": Rect2(x * C + 3, y * C, C - 6, C * 0.55), "down": true, "x": x, "y": y})
				"P":
					start_pos = Vector2(x * C + C * 0.5, (y + 1) * C - Player.HH - 0.01)
				"p":
					k = Medium.MED
					start_pos = Vector2(x * C + C * 0.5, (y + 1) * C - Player.HH - 0.01)
				"E":
					exit_rect = Rect2(x * C + 2, (y - 1) * C, C - 4, C * 2)
				"B":
					k = Medium.MED
					bells.append({"i": i, "pos": Vector2(x * C + C * 0.5, y * C + C * 0.5), "rung": false, "t": 0.0})
				"G":
					k = Medium.GATE
					gates.append(i)
				"D":
					k = Medium.DAM
					dams.append(i)
				"*":
					k = Medium.MED
			medium.kind[i] = k
	# 起搏器（按阅读顺序对应 pacers 配置）
	var pc: Array = d.get("pacers", [])
	var n := 0
	for y in Medium.H:
		var row: String = rows[y] if y < rows.size() else ""
		for x in mini(row.length(), Medium.W):
			if row[x] == "*":
				var cfg: Dictionary = pc[n] if n < pc.size() else {}
				medium.add_pacer(medium.idx(x, y), cfg.get("period", 2.5), cfg.get("first", 1.0))
				n += 1
	medium.reset_state()
	medium.cell_excited.connect(_on_cell_excited)

	_walls = Node2D.new()
	_walls.draw.connect(_draw_walls)
	add_child(_walls)

	_tex = ImageTexture.create_from_image(Image.create(Medium.W, Medium.H, false, Image.FORMAT_RGBAF))
	_img_buf.resize(Medium.W * Medium.H * 4)
	_medium_rect = ColorRect.new()
	_medium_rect.size = Vector2(Medium.W * C, Medium.H * C)
	_medium_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_MEDIUM
	mat.set_shader_parameter("data", _tex)
	mat.set_shader_parameter("grid", Vector2(Medium.W, Medium.H))
	mat.set_shader_parameter("exc", Medium.EXC)
	mat.set_shader_parameter("refr", Medium.REF)
	mat.set_shader_parameter("speed", Medium.SPEED)
	_medium_rect.material = mat
	add_child(_medium_rect)

	_objects = Node2D.new()
	_objects.draw.connect(_draw_objects)
	add_child(_objects)

	player = Player.new()
	add_child(player)
	player.setup(medium, start_pos)
	player.stomped.connect(_on_stomp)
	player.jumped.connect(func(): _sfx("jump", randf_range(0.95, 1.08), -8.0))
	player.landed.connect(_on_land)

	_fx = Node2D.new()
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_update_texture()


func _sfx(n: String, pitch := 1.0, vol := 0.0) -> void:
	if sfx:
		sfx.play(n, pitch, vol)


func physics(dt: float, inp: Dictionary) -> void:
	time += dt
	if dead_t >= 0.0:
		dead_t += dt
		medium.step(dt)
		return
	if finished:
		medium.step(dt)
		return
	medium.step(dt)
	player.resolve_wave_push()
	player.physics(dt, inp)
	if gates_open:
		open_t += dt
	_check_hazards()


func _check_hazards() -> void:
	var r := player.rect_at(player.position).grow(-1.5)
	for s in spikes:
		if r.intersects(s.rect):
			_die()
			return
	if player.position.y > Medium.H * C + 60.0:
		_die()
		return
	if exit_rect.size.x > 0 and r.intersects(exit_rect):
		finished = true
		_sfx("win")
		_burst(exit_rect.get_center(), Color(1.0, 0.9, 0.6), 40, 260.0)
		_ring(exit_rect.get_center(), Color(1.0, 0.92, 0.7), 900.0, 0.9)
		won.emit()


func _die() -> void:
	if dead_t >= 0.0:
		return
	dead_t = 0.0
	player.dead = true
	player.queue_redraw()
	shake = 9.0
	_sfx("die")
	_burst(player.position, player.color, 30, 320.0)
	_burst(player.position, Color(1, 0.4, 0.55), 14, 200.0)
	died.emit()


func _on_stomp(hit: bool) -> void:
	var feet := player.position + Vector2(0, Player.HH)
	if hit:
		_sfx("stomp", randf_range(0.92, 1.08) * (1.25 - feet.y / (Medium.H * C) * 0.5))
		_ring(feet, Color(0.6, 0.95, 1.0), 260.0, 0.45)
		_burst(feet, Color(0.7, 0.95, 1.0), 10, 160.0)
		shake = maxf(shake, 2.5)
		pulse = 1.0
	else:
		_sfx("thud", randf_range(0.9, 1.1), -4.0)
		_burst(feet, Color(0.6, 0.6, 0.8), 5, 90.0)


func _on_land(v: float) -> void:
	_sfx("land", randf_range(0.9, 1.1), -14.0 + v / 120.0)
	_burst(player.position + Vector2(0, Player.HH), Color(0.8, 0.8, 1.0, 0.6), 4, 80.0)


func _on_cell_excited(i: int, _t: float) -> void:
	for b in bells:
		if b.i == i and not b.rung:
			b.rung = true
			b.t = time
			_sfx("bell", 1.0 + 0.12 * bells.filter(func(x): return x.rung).size())
			_ring(b.pos, Color(1.0, 0.85, 0.45), 380.0, 0.9)
			_burst(b.pos, Color(1.0, 0.85, 0.5), 16, 200.0)
			var cnt := bells.filter(func(x): return x.rung).size()
			bell_rung.emit(cnt, bells.size())
			if cnt == bells.size():
				_open_gates()


func _open_gates() -> void:
	if gates_open:
		return
	gates_open = true
	open_t = 0.0
	_sfx("gate", 1.0, -2.0)
	for g in gates:
		medium.kind[g] = Medium.EMPTY
		_burst(Vector2(g % Medium.W * C + C * 0.5, g / Medium.W * C + C * 0.5), Color(1.0, 0.5, 0.75), 3, 120.0)
	for dm in dams:
		medium.open_dam(dm)
		_burst(Vector2(dm % Medium.W * C + C * 0.5, dm / Medium.W * C + C * 0.5), Color(0.6, 0.7, 1.0), 3, 100.0)
	_walls.queue_redraw()


func visual_update(dt: float) -> void:
	pulse = maxf(0.0, pulse - dt * 2.5)
	shake = maxf(0.0, shake - dt * 30.0)
	player.update_visual(dt)
	_update_texture()
	var mat: ShaderMaterial = _medium_rect.material
	mat.set_shader_parameter("time_s", time)
	_update_fx(dt)
	_objects.queue_redraw()
	_fx.queue_redraw()


func _update_texture() -> void:
	medium.pack_texture_data(_img_buf)
	var img := Image.create_from_data(Medium.W, Medium.H, false, Image.FORMAT_RGBAF, _img_buf.to_byte_array())
	_tex.update(img)


# ---------------- 特效 ----------------
func _ring(p: Vector2, col: Color, speed: float, life: float) -> void:
	fx_rings.append({"p": p, "r": 4.0, "s": speed, "life": life, "max": life, "c": col})


func _burst(p: Vector2, col: Color, n: int, spd: float) -> void:
	for k in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * spd * randf_range(0.3, 1.0)
		fx_sparks.append({"p": p, "v": v, "life": randf_range(0.35, 0.8), "max": 0.8, "c": col, "s": randf_range(1.5, 3.5)})


func _update_fx(dt: float) -> void:
	for r in fx_rings:
		r.r += r.s * dt
		r.s *= exp(-dt * 2.0)
		r.life -= dt
	fx_rings = fx_rings.filter(func(r): return r.life > 0.0)
	for s in fx_sparks:
		s.p += s.v * dt
		s.v *= exp(-dt * 3.5)
		s.v.y += 120.0 * dt
		s.life -= dt
	fx_sparks = fx_sparks.filter(func(s): return s.life > 0.0)


func _draw_fx() -> void:
	for r in fx_rings:
		var a: float = clampf(r.life / r.max, 0.0, 1.0)
		_fx.draw_arc(r.p, r.r, 0.0, TAU, 48, Color(r.c, a * 0.7), 2.0 + a * 2.0, true)
	for s in fx_sparks:
		var a: float = clampf(s.life / s.max, 0.0, 1.0)
		_fx.draw_rect(Rect2(s.p - Vector2.ONE * s.s * 0.5, Vector2.ONE * s.s), Color(s.c, a))


# ---------------- 静态绘制 ----------------
const WALL_COL := Color(0.105, 0.115, 0.19)
const WALL_EDGE := Color(0.27, 0.30, 0.50)
const WALL_SIDE := Color(0.16, 0.18, 0.30)
const SPIKE_COL := Color(1.0, 0.38, 0.47)


func _is_wallish(x: int, y: int) -> bool:
	if x < 0 or x >= Medium.W or y < 0 or y >= Medium.H:
		return true
	var k := medium.kind[medium.idx(x, y)]
	return k == Medium.WALL


func _draw_walls() -> void:
	for y in Medium.H:
		for x in Medium.W:
			if medium.kind[medium.idx(x, y)] != Medium.WALL:
				continue
			var r := Rect2(x * C, y * C, C, C)
			var shade := 1.0 - float(y) / Medium.H * 0.25
			_walls.draw_rect(r, WALL_COL * Color(shade, shade, shade))
			# 细纹理
			if (x * 7 + y * 13) % 5 == 0:
				_walls.draw_rect(Rect2(r.position + Vector2(6, 8), Vector2(3, 3)), Color(0.2, 0.22, 0.36, 0.5))
			if not _is_wallish(x, y - 1):
				_walls.draw_rect(Rect2(r.position, Vector2(C, 3)), WALL_EDGE)
				_walls.draw_rect(Rect2(r.position + Vector2(0, 3), Vector2(C, 3)), Color(WALL_EDGE, 0.25))
			if not _is_wallish(x - 1, y):
				_walls.draw_rect(Rect2(r.position, Vector2(2, C)), WALL_SIDE)
			if not _is_wallish(x + 1, y):
				_walls.draw_rect(Rect2(r.position + Vector2(C - 2, 0), Vector2(2, C)), WALL_SIDE)
			if not _is_wallish(x, y + 1):
				_walls.draw_rect(Rect2(r.position + Vector2(0, C - 2), Vector2(C, 2)), Color(0.06, 0.06, 0.12))
	for s in spikes:
		var x0: float = s.x * C
		var y0: float = s.y * C
		for k in 2:
			var bx := x0 + k * C * 0.5
			var pts: PackedVector2Array
			if s.down:
				pts = PackedVector2Array([Vector2(bx + 1, y0), Vector2(bx + C * 0.5 - 1, y0), Vector2(bx + C * 0.25, y0 + C * 0.7)])
			else:
				pts = PackedVector2Array([Vector2(bx + 1, y0 + C), Vector2(bx + C * 0.5 - 1, y0 + C), Vector2(bx + C * 0.25, y0 + C * 0.3)])
			_walls.draw_colored_polygon(pts, SPIKE_COL)
		var gy := y0 + (0.0 if s.down else C)
		_walls.draw_rect(Rect2(x0, gy - (0.0 if s.down else 2.0), C, 2), Color(1.0, 0.5, 0.55, 0.6))


func _draw_objects() -> void:
	var o := _objects
	# 钟到门的连线（提示两者相关）
	var targets := gates + dams
	if bells.size() > 0 and targets.size() > 0:
		var tc := Vector2.ZERO
		for g in targets:
			tc += Vector2(g % Medium.W * C + C * 0.5, g / Medium.W * C + C * 0.5)
		tc /= targets.size()
		for b in bells:
			var a := 0.5 if b.rung else 0.13
			if gates_open:
				a *= maxf(0.0, 1.0 - open_t * 0.8)
			_dashed(o, b.pos, tc, Color(1.0, 0.85, 0.5, a))
	# 门
	for g in gates:
		var r := Rect2(g % Medium.W * C, g / Medium.W * C, C, C)
		if gates_open:
			var k := clampf(1.0 - open_t * 2.5, 0.0, 1.0)
			if k > 0.0:
				o.draw_rect(r.grow(-C * 0.5 * (1.0 - k)), Color(1.0, 0.45, 0.72, k))
			continue
		o.draw_rect(r, Color(0.25, 0.08, 0.2))
		for bx in 3:
			o.draw_rect(Rect2(r.position.x + 3 + bx * 6, r.position.y, 2, C), Color(1.0, 0.45, 0.72, 0.85 + 0.15 * sin(time * 3.0 + bx)))
	# 坝
	for dm in dams:
		var r := Rect2(dm % Medium.W * C, dm / Medium.W * C, C, C)
		if gates_open:
			var k := clampf(1.0 - open_t * 1.5, 0.0, 1.0)
			if k > 0.0:
				o.draw_rect(r, Color(0.55, 0.65, 1.0, k * 0.6))
			continue
		o.draw_rect(r, Color(0.13, 0.12, 0.26))
		for k in 3:
			var yy := r.position.y + 3 + k * 6
			o.draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy + 3), Color(0.55, 0.62, 1.0, 0.7), 2.0)
	# 钟
	for b in bells:
		var p: Vector2 = b.pos
		if b.rung:
			var age: float = time - b.t
			var glow := 0.5 + 0.5 * sin(time * 2.0)
			o.draw_circle(p, 12.0 + glow * 3.0, Color(1.0, 0.8, 0.4, 0.15))
			o.draw_circle(p, 7.5, Color(1.0, 0.86, 0.5))
			o.draw_arc(p, 10.0, 0, TAU, 32, Color(1.0, 0.95, 0.8), 2.0, true)
			if age < 0.6:
				o.draw_arc(p, 10.0 + age * 40.0, 0, TAU, 32, Color(1, 0.9, 0.6, 1.0 - age / 0.6), 2.0, true)
		else:
			var wob := sin(time * 2.4 + p.x * 0.05) * 0.6
			o.draw_arc(p, 8.0 + wob, 0, TAU, 32, Color(1.0, 0.82, 0.45, 0.9), 2.0, true)
			o.draw_circle(p, 2.5, Color(1.0, 0.82, 0.45, 0.8))
	# 起搏器
	for pc in medium.pacers:
		var i: int = pc.idx
		var p := Vector2(i % Medium.W * C + C * 0.5, i / Medium.W * C + C * 0.5)
		var phase := 1.0 - clampf((pc.next - medium.now) / pc.period, 0.0, 1.0)
		var beat := clampf(1.0 - (medium.now - (pc.next - pc.period)) * 4.0, 0.0, 1.0)
		o.draw_arc(p, 9.0, -PI * 0.5, -PI * 0.5 + TAU * phase, 32, Color(1.0, 0.55, 0.75, 0.8), 2.0, true)
		var s := 4.0 + beat * 4.0
		o.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]), Color(1.0, 0.7, 0.85))
	# 出口
	if exit_rect.size.x > 0:
		var er := exit_rect
		var cx := er.get_center().x
		for k in 5:
			var w := 3.0 + k * 4.0
			o.draw_rect(Rect2(cx - w * 0.5, er.position.y - 4, w, er.size.y + 4), Color(1.0, 0.9, 0.65, 0.18 - k * 0.03))
		o.draw_rect(Rect2(cx - 2, er.position.y - 4, 4, er.size.y + 4), Color(1.0, 0.97, 0.85))
		for k in 4:
			var t := fmod(time * 0.6 + k * 0.25, 1.0)
			var yy := er.end.y - t * (er.size.y + 16)
			o.draw_rect(Rect2(cx - 1 + sin(time * 3.0 + k) * 6.0, yy, 2, 2), Color(1, 0.95, 0.8, 1.0 - t))


func _dashed(o: Node2D, a: Vector2, b: Vector2, col: Color) -> void:
	var L := a.distance_to(b)
	if L < 1.0:
		return
	var d := (b - a) / L
	var s := fmod(time * 12.0, 12.0)
	while s < L:
		o.draw_line(a + d * s, a + d * minf(s + 5.0, L), col, 1.5)
		s += 12.0
