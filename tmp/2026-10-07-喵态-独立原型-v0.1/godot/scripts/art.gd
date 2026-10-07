extends RefCounted
## 喵态 · 代码绘制：小猫三态（液/固/气）与阿黄
## 坐标约定：以脚底中心为原点，+x 朝前，y 向下；朝向用 x 镜像实现。

const OUTLINE := Color("3a2829")
const BLUSH := Color(1.0, 0.45, 0.5, 0.42)
const NOSE := Color("f08a96")
const EAR_IN := Color("f6a9b2")

const COATS := [
	{"name": "橘", "base": Color("f4a75c"), "dark": Color("d9823a"), "belly": Color("ffe4c6"), "pat": "tabby", "eye": Color("3a2a22"), "iris": false},
	{"name": "三花", "base": Color("fff7ec"), "dark": Color("e9dccb"), "belly": Color("ffffff"), "pat": "calico", "p1": Color("f0a052"), "p2": Color("4b424b"), "eye": Color("3a2a22"), "iris": false},
	{"name": "黑", "base": Color("413a47"), "dark": Color("2c2732"), "belly": Color("4d4654"), "pat": "none", "eye": Color("f2cf4a"), "iris": true},
	{"name": "狸花", "base": Color("aeb4bd"), "dark": Color("7c8592"), "belly": Color("e6e9ee"), "pat": "tabby", "eye": Color("3a2a22"), "iris": false},
	{"name": "奶油", "base": Color("f7e5c6"), "dark": Color("e6c493"), "belly": Color("fff7e8"), "pat": "tabby", "eye": Color("3a2a22"), "iris": false},
	{"name": "奶牛", "base": Color("38333e"), "dark": Color("27232c"), "belly": Color("fbf7f0"), "pat": "tux", "eye": Color("b6e06a"), "iris": true},
	{"name": "暹罗", "base": Color("f6ebdc"), "dark": Color("7d5d4a"), "belly": Color("fcf6ee"), "pat": "point", "eye": Color("6cb4ef"), "iris": true},
	{"name": "玳瑁", "base": Color("5f4538"), "dark": Color("432f27"), "belly": Color("6f5246"), "pat": "tortie", "p1": Color("de8f3e"), "eye": Color("f0c04a"), "iris": true},
	{"name": "白", "base": Color("ffffff"), "dark": Color("ebe6ee"), "belly": Color("ffffff"), "pat": "none", "eye": Color("6cb4ef"), "iris": true},
]

static var _glow: Texture2D = null


static func glow_tex() -> Texture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		g.add_point(0.7, Color(1, 1, 1, 0.12))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_glow = t
	return _glow


static func glow(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_texture_rect(glow_tex(), Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


static func ellipse(c: Vector2, rx: float, ry: float, n: int = 22, rot: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(n)
	var cr := cos(rot)
	var sr := sin(rot)
	for i in n:
		var a := TAU * float(i) / float(n)
		var x := cos(a) * rx
		var y := sin(a) * ry
		pts[i] = c + Vector2(x * cr - y * sr, x * sr + y * cr)
	return pts


static func rrect(r: Rect2, rad: float, seg: int = 4) -> PackedVector2Array:
	var pts := PackedVector2Array()
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var cs := [
		[Vector2(r.end.x - rad, r.position.y + rad), -PI * 0.5],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5],
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
	]
	for c in cs:
		for i in seg + 1:
			var a: float = c[1] + PI * 0.5 * float(i) / float(seg)
			pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	return pts


static func blob(ci: CanvasItem, pts: PackedVector2Array, fill: Color, line: Color = OUTLINE, w: float = 1.6) -> void:
	ci.draw_colored_polygon(pts, fill)
	if w > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, line, w, true)


static func stroke(ci: CanvasItem, pts: PackedVector2Array, fill: Color, w: float, line: Color = OUTLINE, lw: float = 1.6) -> void:
	# 带描边的粗线（尾巴、腿）
	ci.draw_polyline(pts, line, w + lw * 2.0, true)
	ci.draw_polyline(pts, fill, w, true)
	ci.draw_circle(pts[0], w * 0.5, fill)
	ci.draw_circle(pts[pts.size() - 1], w * 0.5 + lw * 0.5, line)
	ci.draw_circle(pts[pts.size() - 1], w * 0.5, fill)


static func curve(a: Vector2, b: Vector2, c: Vector2, n: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		pts.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return pts


static func tri(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, fill: Color, line: Color = OUTLINE, w: float = 1.4) -> void:
	blob(ci, PackedVector2Array([a, b, c]), fill, line, w)


# ================================================================ 小猫

## s: state, facing, vx, vy, grounded, t, phase, coat, look(Vector2), seed, dwell(0..1),
##    breath, idle, sees, sun, squash(Vector2), spook_t
static func kitten(ci: CanvasItem, center: Vector2, s: Dictionary) -> void:
	var feet := center + Vector2(0, 15)
	var f: float = s["facing"]
	var coat: Dictionary = COATS[int(s["coat"]) % COATS.size()]
	var sq: Vector2 = s.get("squash", Vector2.ONE)
	var st: int = s["state"]
	var line := OUTLINE
	if st == 1:
		_loaf(ci, feet, f, sq, coat, s)
	elif st == 2:
		_ball(ci, feet, f, coat, s)
	elif st == 3:
		_puff(ci, feet, f, coat, s)
	else:
		if not s["grounded"]:
			_air(ci, feet, f, sq, coat, s)
		elif absf(s["vx"]) > 34.0:
			_run(ci, feet, f, sq, coat, s)
		else:
			_sit(ci, feet, f, sq, coat, s)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _xf(ci: CanvasItem, feet: Vector2, f: float, sq: Vector2, rot: float = 0.0) -> void:
	ci.draw_set_transform(feet, rot * f, Vector2(f * sq.x, sq.y))


static func _pattern(ci: CanvasItem, coat: Dictionary, c: Vector2, rx: float, ry: float, kind: String) -> void:
	var pat: String = coat["pat"]
	match pat:
		"tabby":
			for i in 3:
				var x := c.x - rx * 0.55 + float(i) * rx * 0.42
				var top := c.y - ry * 0.95
				ci.draw_polyline(curve(Vector2(x - 1.5, top + 0.5), Vector2(x + 1.0, c.y - ry * 0.55), Vector2(x - 0.5, c.y - ry * 0.15), 5), coat["dark"], 2.4, true)
		"calico":
			blob(ci, ellipse(c + Vector2(-rx * 0.35, -ry * 0.35), rx * 0.36, ry * 0.42, 14), coat["p1"], Color(0, 0, 0, 0), 0.0)
			blob(ci, ellipse(c + Vector2(rx * 0.25, -ry * 0.45), rx * 0.24, ry * 0.32, 14), coat["p2"], Color(0, 0, 0, 0), 0.0)
		"tortie":
			blob(ci, ellipse(c + Vector2(-rx * 0.3, -ry * 0.3), rx * 0.3, ry * 0.36, 12), coat["p1"], Color(0, 0, 0, 0), 0.0)
			blob(ci, ellipse(c + Vector2(rx * 0.32, -ry * 0.1), rx * 0.18, ry * 0.26, 12), coat["p1"], Color(0, 0, 0, 0), 0.0)
		"tux":
			if kind != "loaf":
				blob(ci, ellipse(c + Vector2(rx * 0.55, ry * 0.25), rx * 0.32, ry * 0.5, 14), coat["belly"], Color(0, 0, 0, 0), 0.0)


static func _ears(ci: CanvasItem, hc: Vector2, r: float, coat: Dictionary, flat: float = 0.0, perk: float = 0.0) -> void:
	var col: Color = coat["base"]
	if coat["pat"] == "point":
		col = coat["dark"]
	# 后耳
	var back_tip := hc + Vector2(-r * 0.55 - flat * 6.0, -r * 1.55 - perk * 1.5 + flat * 7.0)
	tri(ci, hc + Vector2(-r * 0.85, -r * 0.45), back_tip, hc + Vector2(-r * 0.05, -r * 0.85), col)
	# 前耳
	var front_tip := hc + Vector2(r * 0.45 - flat * 7.0, -r * 1.7 - perk * 2.0 + flat * 8.0)
	tri(ci, hc + Vector2(-r * 0.1, -r * 0.9), front_tip, hc + Vector2(r * 0.85, -r * 0.5), col)
	tri(ci, hc + Vector2(r * 0.05, -r * 0.85), front_tip.lerp(hc, 0.28), hc + Vector2(r * 0.6, -r * 0.58), EAR_IN, Color(0, 0, 0, 0), 0.0)


static func _head(ci: CanvasItem, hc: Vector2, r: float, coat: Dictionary, s: Dictionary, mood: String) -> void:
	var look: Vector2 = s.get("look", Vector2.ZERO)
	var f: float = s["facing"]
	var ll := Vector2(look.x * f, look.y)
	blob(ci, ellipse(hc, r * 1.04, r * 0.95, 20), coat["base"])
	if coat["pat"] == "point":
		blob(ci, ellipse(hc + Vector2(r * 0.42, r * 0.18), r * 0.58, r * 0.55, 16), coat["dark"].lerp(coat["base"], 0.25), Color(0, 0, 0, 0), 0.0)
	elif coat["pat"] == "tux":
		blob(ci, ellipse(hc + Vector2(r * 0.55, r * 0.42), r * 0.42, r * 0.35, 14), coat["belly"], Color(0, 0, 0, 0), 0.0)
	elif coat["pat"] == "calico":
		blob(ci, ellipse(hc + Vector2(-r * 0.35, -r * 0.4), r * 0.45, r * 0.38, 14), coat["p1"], Color(0, 0, 0, 0), 0.0)
	elif coat["pat"] == "tabby":
		ci.draw_line(hc + Vector2(-r * 0.1, -r * 0.9), hc + Vector2(-r * 0.05, -r * 0.45), coat["dark"], 1.8, true)
		ci.draw_line(hc + Vector2(r * 0.18, -r * 0.92), hc + Vector2(r * 0.18, -r * 0.5), coat["dark"], 1.8, true)
	var e1 := hc + Vector2(r * 0.52, -r * 0.08)
	var e2 := hc + Vector2(r * 0.02, -r * 0.12)
	var eye_col: Color = coat["eye"]
	var iris: bool = coat["iris"]
	match mood:
		"sleep":
			ci.draw_arc(e1 + Vector2(0, -0.6), r * 0.2, 0.15 * PI, 0.85 * PI, 6, OUTLINE, 1.5, true)
			ci.draw_arc(e2 + Vector2(0, -0.6), r * 0.18, 0.15 * PI, 0.85 * PI, 6, OUTLINE, 1.4, true)
		"drowsy":
			var k: float = clampf(s.get("drowse", 0.5), 0.0, 1.0)
			var h := lerpf(2.6, 0.7, k)
			blob(ci, ellipse(e1, 2.0, h, 10), eye_col if not iris else OUTLINE, Color(0, 0, 0, 0), 0.0)
			blob(ci, ellipse(e2, 1.7, h * 0.92, 10), eye_col if not iris else OUTLINE, Color(0, 0, 0, 0), 0.0)
			ci.draw_line(e1 + Vector2(-2.6, -h + 0.2), e1 + Vector2(2.6, -h + 0.2), OUTLINE, 1.2, true)
			ci.draw_line(e2 + Vector2(-2.2, -h * 0.92 + 0.2), e2 + Vector2(2.2, -h * 0.92 + 0.2), OUTLINE, 1.2, true)
		"shock":
			blob(ci, ellipse(e1, 3.4, 3.6, 12), Color.WHITE, OUTLINE, 1.2)
			blob(ci, ellipse(e2, 2.9, 3.2, 12), Color.WHITE, OUTLINE, 1.2)
			ci.draw_circle(e1 + Vector2(0.6, 0.0), 1.1, OUTLINE)
			ci.draw_circle(e2 + Vector2(0.4, 0.0), 1.0, OUTLINE)
		_:
			var off := ll * 0.9
			if iris:
				blob(ci, ellipse(e1, 2.5, 2.9, 12), eye_col, OUTLINE, 1.0)
				blob(ci, ellipse(e2, 2.1, 2.6, 12), eye_col, OUTLINE, 1.0)
				var pw := 0.8 if mood != "hunt" else 1.5
				blob(ci, ellipse(e1 + off * 0.7, pw, 2.3, 8), OUTLINE, Color(0, 0, 0, 0), 0.0)
				blob(ci, ellipse(e2 + off * 0.6, pw * 0.9, 2.0, 8), OUTLINE, Color(0, 0, 0, 0), 0.0)
			else:
				var big := 1.0 if mood != "hunt" else 1.18
				blob(ci, ellipse(e1 + off * 0.5, 2.2 * big, 2.8 * big, 12), eye_col, Color(0, 0, 0, 0), 0.0)
				blob(ci, ellipse(e2 + off * 0.4, 1.9 * big, 2.5 * big, 12), eye_col, Color(0, 0, 0, 0), 0.0)
			ci.draw_circle(e1 + off * 0.5 + Vector2(-0.6, -1.0), 0.85, Color(1, 1, 1, 0.95))
			ci.draw_circle(e2 + off * 0.4 + Vector2(-0.5, -0.9), 0.7, Color(1, 1, 1, 0.9))
	# 鼻子、嘴、腮红、胡须
	var nose := hc + Vector2(r * 0.98, r * 0.18)
	tri(ci, nose + Vector2(-1.6, -1.0), nose + Vector2(1.2, -1.0), nose + Vector2(-0.1, 0.9), NOSE, Color(0, 0, 0, 0), 0.0)
	if mood == "shock":
		blob(ci, ellipse(hc + Vector2(r * 0.72, r * 0.62), 2.0, 2.4, 10), Color("5a2a30"), OUTLINE, 1.0)
	else:
		ci.draw_arc(nose + Vector2(-1.4, 1.8), 1.4, 0.0, PI, 5, OUTLINE, 1.0, true)
	ci.draw_circle(hc + Vector2(r * 0.42, r * 0.42), r * 0.2, BLUSH)
	var wc := Color(1, 1, 1, 0.75) if coat["base"].get_luminance() < 0.45 else Color(0.25, 0.18, 0.18, 0.45)
	ci.draw_line(nose + Vector2(-1.0, 1.0), nose + Vector2(7.0, -0.5), wc, 0.9, true)
	ci.draw_line(nose + Vector2(-1.0, 1.8), nose + Vector2(7.0, 2.8), wc, 0.9, true)


static func _tail(ci: CanvasItem, pts: PackedVector2Array, coat: Dictionary, w: float = 4.6) -> void:
	var col: Color = coat["base"]
	if coat["pat"] == "point" or coat["pat"] == "tabby":
		col = coat["dark"] if coat["pat"] == "point" else coat["base"]
	stroke(ci, pts, col, w)
	if coat["pat"] == "tabby" and pts.size() > 4:
		for i in range(2, pts.size() - 1, 2):
			ci.draw_circle(pts[i], w * 0.42, coat["dark"])


static func _run(ci: CanvasItem, feet: Vector2, f: float, sq: Vector2, coat: Dictionary, s: Dictionary) -> void:
	var ph: float = s["phase"]
	var t: float = s["t"]
	var bob := -absf(sin(ph)) * 2.2
	_xf(ci, feet, f, sq)
	var seed: float = s["seed"]
	# 尾巴（身后，跑起来向后飘）
	var sway := sin(t * 7.0 + seed) * 2.5
	_tail(ci, curve(Vector2(-13, -13 + bob), Vector2(-24, -16 + sway), Vector2(-29, -26 + sway), 8), coat)
	# 后侧的腿
	var legs := [[-9.0, 0.0], [7.0, PI]]
	for lg in legs:
		var a: float = ph + lg[1]
		var lx: float = lg[0] + sin(a) * 4.5
		var lift := maxf(0.0, -cos(a)) * 3.2
		stroke(ci, PackedVector2Array([Vector2(lg[0], -7 + bob), Vector2(lx, -2.0 - lift)]), coat["dark"], 3.8)
	var stretch := 1.0 + 0.07 * sin(ph * 2.0)
	var bc := Vector2(-1, -11.5 + bob)
	blob(ci, ellipse(bc, 15.5 * stretch, 9.8 / sqrt(stretch), 22), coat["base"])
	blob(ci, ellipse(bc + Vector2(3, 5.0), 9.5, 3.4, 14), coat["belly"], Color(0, 0, 0, 0), 0.0)
	_pattern(ci, coat, bc, 15.5, 9.8, "run")
	# 前侧的腿
	var legs2 := [[-5.0, PI], [10.5, 0.0]]
	for lg in legs2:
		var a2: float = ph + lg[1]
		var lx2: float = lg[0] + sin(a2) * 4.5
		var lift2 := maxf(0.0, -cos(a2)) * 3.2
		stroke(ci, PackedVector2Array([Vector2(lg[0], -7 + bob), Vector2(lx2, -2.0 - lift2)]), coat["base"], 3.8)
	var hc := Vector2(12.5, -19.0 + bob * 0.5)
	_ears(ci, hc, 8.6, coat, 0.35, 0.0)
	_head(ci, hc, 8.6, coat, s, "hunt" if s.get("sees", false) else "")


static func _sit(ci: CanvasItem, feet: Vector2, f: float, sq: Vector2, coat: Dictionary, s: Dictionary) -> void:
	var t: float = s["t"]
	var seed: float = s["seed"]
	var idle: float = s.get("idle", 0.0)
	var sees: bool = s.get("sees", false)
	var breathe := 1.0 + 0.02 * sin(t * 3.0 + seed)
	_xf(ci, feet, f, Vector2(sq.x, sq.y * breathe))
	# 尾巴：看见红点时末梢快速甩动，犯困时盘在身边
	var tip := sin(t * (9.0 if sees else 2.2) + seed) * (5.0 if sees else 2.0)
	if idle > 0.45:
		_tail(ci, curve(Vector2(-11, -5), Vector2(-17, 0), Vector2(-6, -0.5), 8), coat)
	else:
		_tail(ci, curve(Vector2(-11, -6), Vector2(-21, -6), Vector2(-22 + tip * 0.3, -19 + tip), 8), coat)
	var bc := Vector2(-3, -12.5)
	blob(ci, ellipse(bc, 11.8, 11.6, 22), coat["base"])
	blob(ci, ellipse(bc + Vector2(5.5, 3.5), 5.0, 6.5, 14), coat["belly"], Color(0, 0, 0, 0), 0.0)
	_pattern(ci, coat, bc + Vector2(-2, 0), 10.0, 11.0, "sit")
	# 前爪
	blob(ci, ellipse(Vector2(3.0, -1.8), 3.2, 2.2, 10), coat["base"], OUTLINE, 1.2)
	blob(ci, ellipse(Vector2(7.6, -1.8), 3.2, 2.2, 10), coat["base"], OUTLINE, 1.2)
	var look: Vector2 = s.get("look", Vector2.ZERO)
	var tilt := Vector2(look.x * f, look.y) * 1.8
	var hc := Vector2(5.5, -24.0) + tilt
	var mood := "hunt" if sees else ""
	var flat := 0.0
	if idle > 0.15 and not sees:
		mood = "drowsy"
		s["drowse"] = clampf((idle - 0.15) / 0.8, 0.0, 1.0)
		flat = 0.15
	_ears(ci, hc, 9.0, coat, flat, 1.0 if sees else 0.0)
	_head(ci, hc, 9.0, coat, s, mood)


static func _air(ci: CanvasItem, feet: Vector2, f: float, sq: Vector2, coat: Dictionary, s: Dictionary) -> void:
	var vx: float = s["vx"]
	var vy: float = s["vy"]
	var rot := clampf(atan2(vy, maxf(absf(vx), 60.0)) * 0.55, -0.6, 0.6)
	_xf(ci, feet + Vector2(0, -2), f, sq, rot)
	var rising := vy < 0.0
	_tail(ci, curve(Vector2(-13, -13), Vector2(-24, -15), Vector2(-30, -10 if rising else -24), 8), coat)
	stroke(ci, PackedVector2Array([Vector2(-8, -8), Vector2(-17, -3 if rising else -6)]), coat["dark"], 3.8)
	var bc := Vector2(0, -12.5)
	blob(ci, ellipse(bc, 16.5, 9.0, 22), coat["base"])
	blob(ci, ellipse(bc + Vector2(3, 4.5), 9.5, 3.0, 14), coat["belly"], Color(0, 0, 0, 0), 0.0)
	_pattern(ci, coat, bc, 16.5, 9.0, "air")
	stroke(ci, PackedVector2Array([Vector2(-4, -8), Vector2(-12, -2 if rising else -5)]), coat["base"], 3.8)
	stroke(ci, PackedVector2Array([Vector2(8, -9), Vector2(18, -8 if rising else -2)]), coat["base"], 3.8)
	var hc := Vector2(14, -19.5)
	_ears(ci, hc, 8.6, coat, 0.55, 0.0)
	_head(ci, hc, 8.6, coat, s, "hunt")


static func _loaf(ci: CanvasItem, feet: Vector2, f: float, sq: Vector2, coat: Dictionary, s: Dictionary) -> void:
	var t: float = s["t"]
	var seed: float = s["seed"]
	var br := 1.0 + 0.035 * sin(t * 2.3 + seed)
	var dw: float = s.get("dwell", 0.0)
	_xf(ci, feet, f, Vector2(sq.x * (1.0 + dw * 0.04), sq.y * br))
	var body := Rect2(-16.5, -19.5, 33.0, 19.5)
	blob(ci, rrect(body, 9.5, 4), coat["base"])
	_pattern(ci, coat, Vector2(-3, -9), 13.0, 9.5, "loaf")
	if coat["pat"] == "tux":
		blob(ci, ellipse(Vector2(9, -5), 6.0, 4.5, 12), coat["belly"], Color(0, 0, 0, 0), 0.0)
	# 尾巴绕在身前（揣手）
	var tc: Color = coat["dark"] if coat["pat"] == "point" else coat["base"]
	stroke(ci, curve(Vector2(-14.5, -4.5), Vector2(-4, 1.5), Vector2(9, -1.5), 8), tc, 4.0)
	var hc := Vector2(10.0, -14.0)
	var twitch := dw * sin(t * 40.0) * 0.4
	_ears(ci, hc, 8.0, coat, 0.25 - twitch, 0.0)
	_head(ci, hc, 8.0, coat, s, "sleep")


static func _ball(ci: CanvasItem, feet: Vector2, f: float, coat: Dictionary, s: Dictionary) -> void:
	var t: float = s["t"]
	_xf(ci, feet + Vector2(0, -15), f, Vector2.ONE, sin(t * 9.0) * 0.5)
	blob(ci, ellipse(Vector2.ZERO, 14.5, 13.5, 22), coat["base"])
	_pattern(ci, coat, Vector2(-2, 2), 12.0, 11.0, "ball")
	stroke(ci, curve(Vector2(-12, 6), Vector2(0, 15), Vector2(10, 7), 8), coat["base"], 4.0)
	var hc := Vector2(6, -1)
	_ears(ci, hc, 7.6, coat, 0.6, 0.0)
	_head(ci, hc, 7.6, coat, s, "sleep")


static func _puff(ci: CanvasItem, feet: Vector2, f: float, coat: Dictionary, s: Dictionary) -> void:
	var t: float = s["t"]
	var seed: float = s["seed"]
	var k: float = clampf(s.get("spook_t", 0.5) / 0.8, 0.0, 1.0)
	var jit := sin(t * 47.0 + seed) * 0.08
	_xf(ci, feet + Vector2(0, -16), f, Vector2.ONE, jit)
	# 炸起来的尾巴
	var tail := PackedVector2Array([Vector2(-9, -6), Vector2(-13, -18), Vector2(-14, -30)])
	stroke(ci, tail, coat["base"], 6.5 + 2.0 * k)
	for i in 5:
		var p := Vector2(-11.5 - float(i) * 0.6, -10 - float(i) * 4.5)
		ci.draw_line(p, p + Vector2(-4, -1.5), OUTLINE, 1.2, true)
		ci.draw_line(p, p + Vector2(4, -1.5), OUTLINE, 1.2, true)
	# 炸毛的身体：锯齿轮廓
	var pts := PackedVector2Array()
	var n := 22
	for i in n:
		var a := TAU * float(i) / float(n)
		var rr := (16.0 if i % 2 == 0 else 20.5 + 2.5 * k) + sin(seed + float(i) * 1.7) * 1.2
		pts.append(Vector2(cos(a) * rr, sin(a) * rr * 0.92))
	blob(ci, pts, coat["base"])
	_pattern(ci, coat, Vector2(-3, 2), 13.0, 12.0, "puff")
	# 绷直的腿
	for lx in [-8.0, -3.0, 4.0, 9.0]:
		stroke(ci, PackedVector2Array([Vector2(lx, 10), Vector2(lx * 1.15, 16)]), coat["base"], 3.0)
	var hc := Vector2(7, -5)
	_ears(ci, hc, 8.2, coat, 1.0, 0.0)
	_head(ci, hc, 8.2, coat, s, "shock")


# ================================================================ 阿黄（老橘猫）

const AH_BASE := Color("f0a04e")
const AH_DARK := Color("cc7a30")
const AH_BELLY := Color("ffe6c8")
const SCARF := Color("e4535a")
const SCARF_D := Color("b83a44")

## s: mode(0 walk,1 wait,2 air,3 goal), facing, t, phase, look, wait_t, vy, goal_t, night
static func old_cat(ci: CanvasItem, feet: Vector2, s: Dictionary) -> void:
	var f: float = s["facing"]
	var mode: int = s["mode"]
	var t: float = s["t"]
	match mode:
		1:
			_old_sit(ci, feet, f, t, s)
		2:
			_old_air(ci, feet, f, t, s)
		3:
			_old_happy(ci, feet, f, t, s)
		_:
			_old_walk(ci, feet, f, t, s)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _old_head(ci: CanvasItem, hc: Vector2, t: float, mood: String, s: Dictionary) -> void:
	var r := 12.5
	# 耳朵
	tri(ci, hc + Vector2(-r * 0.9, -r * 0.3), hc + Vector2(-r * 0.75, -r * 1.45), hc + Vector2(-r * 0.05, -r * 0.85), AH_BASE)
	tri(ci, hc + Vector2(-r * 0.1, -r * 0.9), hc + Vector2(r * 0.42, -r * 1.55), hc + Vector2(r * 0.85, -r * 0.45), AH_BASE)
	tri(ci, hc + Vector2(r * 0.05, -r * 0.82), hc + Vector2(r * 0.38, -r * 1.22), hc + Vector2(r * 0.6, -r * 0.55), EAR_IN, Color(0, 0, 0, 0), 0.0)
	blob(ci, ellipse(hc, r * 1.08, r * 0.96, 22), AH_BASE)
	# 额头条纹
	for i in 3:
		var x := -r * 0.35 + float(i) * r * 0.28
		ci.draw_line(hc + Vector2(x, -r * 0.92), hc + Vector2(x + 0.5, -r * 0.5), AH_DARK, 2.0, true)
	# 白嘴套
	blob(ci, ellipse(hc + Vector2(r * 0.62, r * 0.32), r * 0.55, r * 0.45, 16), AH_BELLY, Color(0, 0, 0, 0), 0.0)
	var e1 := hc + Vector2(r * 0.5, -r * 0.12)
	var e2 := hc + Vector2(r * 0.0, -r * 0.16)
	match mood:
		"happy":
			ci.draw_arc(e1, 2.6, 1.15 * PI, 1.85 * PI, 7, OUTLINE, 1.6, true)
			ci.draw_arc(e2, 2.3, 1.15 * PI, 1.85 * PI, 7, OUTLINE, 1.5, true)
		"wow":
			blob(ci, ellipse(e1, 3.2, 3.4, 12), Color.WHITE, OUTLINE, 1.2)
			blob(ci, ellipse(e2, 2.8, 3.0, 12), Color.WHITE, OUTLINE, 1.2)
			ci.draw_circle(e1 + Vector2(0.5, 0), 1.3, OUTLINE)
			ci.draw_circle(e2 + Vector2(0.4, 0), 1.2, OUTLINE)
		_:
			# 老猫的耷拉眼皮：半睁
			var blink := 1.0
			var bt := fmod(t + float(s.get("seed", 0.0)), 4.3)
			if bt < 0.14:
				blink = 0.15
			blob(ci, ellipse(e1 + Vector2(0, 0.6), 2.4, 2.0 * blink, 10), Color("3a2a22"), Color(0, 0, 0, 0), 0.0)
			blob(ci, ellipse(e2 + Vector2(0, 0.6), 2.1, 1.8 * blink, 10), Color("3a2a22"), Color(0, 0, 0, 0), 0.0)
			ci.draw_line(e1 + Vector2(-3.0, -0.6), e1 + Vector2(3.0, -0.2), OUTLINE, 1.6, true)
			ci.draw_line(e2 + Vector2(-2.6, -0.7), e2 + Vector2(2.6, -0.3), OUTLINE, 1.5, true)
	# 白眉毛（老了）
	ci.draw_polyline(curve(e1 + Vector2(-2.5, -4.2), e1 + Vector2(0.5, -6.2), e1 + Vector2(3.5, -4.6), 5), Color(1, 1, 1, 0.95), 1.6, true)
	ci.draw_polyline(curve(e2 + Vector2(-2.5, -4.4), e2 + Vector2(0.2, -6.0), e2 + Vector2(3.0, -4.8), 5), Color(1, 1, 1, 0.9), 1.5, true)
	var nose := hc + Vector2(r * 1.02, r * 0.12)
	tri(ci, nose + Vector2(-2.0, -1.2), nose + Vector2(1.4, -1.2), nose + Vector2(-0.2, 1.1), NOSE, Color(0, 0, 0, 0), 0.0)
	ci.draw_arc(nose + Vector2(-1.8, 2.2), 1.7, 0.0, PI, 5, OUTLINE, 1.1, true)
	ci.draw_circle(hc + Vector2(r * 0.4, r * 0.45), 2.6, BLUSH)
	for i in 3:
		var yy := 0.6 + float(i) * 1.6
		ci.draw_line(nose + Vector2(-1.5, yy), nose + Vector2(11.0, yy - 2.0 + float(i) * 1.8), Color(1, 1, 1, 0.9), 1.0, true)


static func _scarf(ci: CanvasItem, nc: Vector2, t: float, flap: float) -> void:
	# 红围巾：一圈加一条飘带
	var tail := PackedVector2Array([nc + Vector2(-5, 1), nc + Vector2(-13, 4 + sin(t * 3.0) * flap), nc + Vector2(-20, 6 + sin(t * 3.0 + 1.0) * flap * 1.4)])
	stroke(ci, tail, SCARF, 5.0, OUTLINE, 1.3)
	var band := rrect(Rect2(nc.x - 7, nc.y - 4, 15, 8.5), 4.0, 3)
	blob(ci, band, SCARF, OUTLINE, 1.4)
	ci.draw_line(nc + Vector2(-3, -3), nc + Vector2(-3, 4), SCARF_D, 1.4, true)
	ci.draw_line(nc + Vector2(2, -3), nc + Vector2(2, 4), SCARF_D, 1.4, true)


static func _old_walk(ci: CanvasItem, feet: Vector2, f: float, t: float, s: Dictionary) -> void:
	var ph: float = s["phase"]
	var bob := -absf(sin(ph)) * 1.6
	ci.draw_set_transform(feet, 0.0, Vector2(f, 1.0))
	stroke(ci, curve(Vector2(-23, -20 + bob), Vector2(-35, -18), Vector2(-36, -31 + sin(t * 1.4) * 2.0), 9), AH_BASE, 6.0)
	for lg in [[-14.0, 0.0], [10.0, PI]]:
		var a: float = ph + lg[1]
		var lx: float = lg[0] + sin(a) * 3.5
		var lift := maxf(0.0, -cos(a)) * 2.4
		stroke(ci, PackedVector2Array([Vector2(lg[0], -9 + bob), Vector2(lx, -2.5 - lift)]), AH_DARK, 5.4)
	var bc := Vector2(-3, -17 + bob)
	blob(ci, ellipse(bc, 24.5, 14.5, 26), AH_BASE)
	blob(ci, ellipse(bc + Vector2(3, 7), 15, 5.5, 16), AH_BELLY, Color(0, 0, 0, 0), 0.0)
	for i in 4:
		var x := -16.0 + float(i) * 8.0
		ci.draw_polyline(curve(Vector2(x - 1, -30 + bob), Vector2(x + 2, -24 + bob), Vector2(x, -18 + bob), 5), AH_DARK, 2.6, true)
	for lg2 in [[-8.0, PI], [15.0, 0.0]]:
		var a2: float = ph + lg2[1]
		var lx2: float = lg2[0] + sin(a2) * 3.5
		var lift2 := maxf(0.0, -cos(a2)) * 2.4
		stroke(ci, PackedVector2Array([Vector2(lg2[0], -9 + bob), Vector2(lx2, -2.5 - lift2)]), AH_BASE, 5.4)
	_scarf(ci, Vector2(15, -24 + bob), t, 1.5)
	_old_head(ci, Vector2(22, -31 + bob * 0.6), t, "", s)


static func _old_sit(ci: CanvasItem, feet: Vector2, f: float, t: float, s: Dictionary) -> void:
	ci.draw_set_transform(feet, 0.0, Vector2(f, 1.0 + 0.012 * sin(t * 2.0)))
	stroke(ci, curve(Vector2(-14, -5), Vector2(-26, -1), Vector2(-12, -0.5), 9), AH_BASE, 6.0)
	var bc := Vector2(-4, -19)
	blob(ci, ellipse(bc, 17.5, 18.5, 26), AH_BASE)
	blob(ci, ellipse(bc + Vector2(7, 5), 8, 10, 16), AH_BELLY, Color(0, 0, 0, 0), 0.0)
	for i in 3:
		var y := -32.0 + float(i) * 7.0
		ci.draw_polyline(curve(Vector2(-18, y), Vector2(-12, y + 2), Vector2(-8, y + 1), 5), AH_DARK, 2.6, true)
	blob(ci, ellipse(Vector2(4, -2.5), 4.5, 3.0, 10), AH_BASE, OUTLINE, 1.3)
	blob(ci, ellipse(Vector2(10, -2.5), 4.5, 3.0, 10), AH_BASE, OUTLINE, 1.3)
	_scarf(ci, Vector2(8, -33), t, 0.6)
	var look_up := clampf(float(s.get("wait_t", 0.0)) * 0.6, 0.0, 1.0)
	_old_head(ci, Vector2(12, -42 - look_up * 1.5), t, "", s)


static func _old_air(ci: CanvasItem, feet: Vector2, f: float, t: float, s: Dictionary) -> void:
	var vy: float = s.get("vy", 0.0)
	var rot := clampf(vy / 1500.0, -0.35, 0.35)
	ci.draw_set_transform(feet + Vector2(0, -4), rot * f, Vector2(f, 1.0))
	stroke(ci, curve(Vector2(-23, -20), Vector2(-34, -28), Vector2(-33, -40), 9), AH_BASE, 6.0)
	stroke(ci, PackedVector2Array([Vector2(-14, -10), Vector2(-24, -2)]), AH_DARK, 5.4)
	stroke(ci, PackedVector2Array([Vector2(10, -10), Vector2(20, -3)]), AH_DARK, 5.4)
	var bc := Vector2(-3, -18)
	blob(ci, ellipse(bc, 25, 14, 26), AH_BASE)
	blob(ci, ellipse(bc + Vector2(3, 7), 15, 5, 16), AH_BELLY, Color(0, 0, 0, 0), 0.0)
	stroke(ci, PackedVector2Array([Vector2(-8, -10), Vector2(-16, -1)]), AH_BASE, 5.4)
	stroke(ci, PackedVector2Array([Vector2(15, -10), Vector2(26, -6)]), AH_BASE, 5.4)
	_scarf(ci, Vector2(15, -25), t * 3.0, 4.0)
	_old_head(ci, Vector2(22, -33), t, "wow", s)


static func _old_happy(ci: CanvasItem, feet: Vector2, f: float, t: float, s: Dictionary) -> void:
	ci.draw_set_transform(feet, 0.0, Vector2(f, 1.0 + 0.02 * sin(t * 1.6)))
	stroke(ci, curve(Vector2(-16, -5), Vector2(-28, 0), Vector2(-10, -1), 9), AH_BASE, 6.0)
	var bc := Vector2(-4, -19)
	blob(ci, ellipse(bc, 17.5, 18.5, 26), AH_BASE)
	blob(ci, ellipse(bc + Vector2(7, 5), 8, 10, 16), AH_BELLY, Color(0, 0, 0, 0), 0.0)
	for i in 3:
		var y := -32.0 + float(i) * 7.0
		ci.draw_polyline(curve(Vector2(-18, y), Vector2(-12, y + 2), Vector2(-8, y + 1), 5), AH_DARK, 2.6, true)
	blob(ci, ellipse(Vector2(4, -2.5), 4.5, 3.0, 10), AH_BASE, OUTLINE, 1.3)
	blob(ci, ellipse(Vector2(10, -2.5), 4.5, 3.0, 10), AH_BASE, OUTLINE, 1.3)
	_scarf(ci, Vector2(8, -33), t, 0.6)
	var up := 3.0 if s.get("night", false) else 0.0
	_old_head(ci, Vector2(12, -43 - up), t, "happy", s)


# ================================================================ 小工具

static func zzz(ci: CanvasItem, font: Font, p: Vector2, a: float, size: int) -> void:
	ci.draw_string(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.42, 0.36, 0.62, a))


static func ring(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float) -> void:
	ci.draw_arc(c, r, 0.0, TAU, 40, col, w, true)
