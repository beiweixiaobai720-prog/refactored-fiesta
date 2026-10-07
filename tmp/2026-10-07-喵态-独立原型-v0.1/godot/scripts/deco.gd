extends RefCounted
## 喵态 · 场景绘制：四个房间的背景、家具与光
const Art = preload("res://scripts/art.gd")

const OUT := Color("4a3434")

const THEMES := {
	"living": {
		"wall_top": Color("f5cdb9"), "wall_bot": Color("e6a7a3"), "base": Color("f8e3d3"),
		"floor": Color("b97a57"), "floor_line": Color("9e6447"), "floor_hi": Color("d4956c"),
		"sky": [Color("6f6fb5"), Color("e78aa3"), Color("ffbb70")], "light": Color(1.0, 0.72, 0.5, 0.20),
		"paper": Color(1, 1, 1, 0.07),
	},
	"kitchen": {
		"wall_top": Color("fff3dc"), "wall_bot": Color("fbe2bd"), "base": Color("f2d3a8"),
		"floor": Color("e9dccb"), "floor_line": Color("c9d8e6"), "floor_hi": Color("fff6ea"),
		"sky": [Color("7cc4f0"), Color("b8e2f7"), Color("fff1c8")], "light": Color(1.0, 0.88, 0.55, 0.22),
		"paper": Color(0.6, 0.78, 0.9, 0.18),
	},
	"stairs": {
		"wall_top": Color("c7b6e6"), "wall_bot": Color("a897d2"), "base": Color("e6dcf4"),
		"floor": Color("8f6a5d"), "floor_line": Color("74544a"), "floor_hi": Color("a98274"),
		"sky": [Color("2e3a7a"), Color("5b5aa8"), Color("e48aa0")], "light": Color(1.0, 0.75, 0.45, 0.20),
		"paper": Color(1, 1, 1, 0.06),
	},
	"roof": {
		"wall_top": Color("1d2150"), "wall_bot": Color("6a4f97"), "base": Color("2a2a58"),
		"floor": Color("8d5a63"), "floor_line": Color("6e4450"), "floor_hi": Color("a56e74"),
		"sky": [Color("1b1f4c"), Color("3d3a86"), Color("9a64a4")], "light": Color(0.75, 0.8, 1.0, 0.14),
		"paper": Color(1, 1, 1, 0.0),
	},
}


static func theme(name: String) -> Dictionary:
	return THEMES.get(name, THEMES["living"])


static func vgrad(ci: CanvasItem, r: Rect2, top: Color, bot: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bot, bot]))


static func hgrad(ci: CanvasItem, r: Rect2, left: Color, right: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([left, right, right, left]))


# ================================================================ 背景（墙、窗、装饰）

static func background(ci: CanvasItem, lv: Dictionary, t: float) -> void:
	var th := theme(lv.get("theme", "living"))
	var tname: String = lv.get("theme", "living")
	var floor_y := float(lv.get("floor_y", 640))
	if tname == "roof":
		_night_sky(ci, lv, t)
	else:
		vgrad(ci, Rect2(0, 0, 1280, floor_y), th["wall_top"], th["wall_bot"])
		_wallpaper(ci, tname, th, floor_y)
	for d in lv.get("deco", []):
		if d["type"] != "rug":
			_deco(ci, d, th, tname, t)
	if tname != "roof":
		# 踢脚线
		ci.draw_rect(Rect2(0, floor_y - 12, 1280, 12), th["base"])
		ci.draw_line(Vector2(0, floor_y - 12), Vector2(1280, floor_y - 12), th["base"].darkened(0.12), 1.5)


static func _wallpaper(ci: CanvasItem, tname: String, th: Dictionary, floor_y: float) -> void:
	var col: Color = th["paper"]
	match tname:
		"living":
			for y in range(40, int(floor_y) - 30, 56):
				var off := 28 if (y / 56) % 2 == 0 else 0
				for x in range(off, 1300, 56):
					var p := Vector2(x, y)
					ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(5, 0), p + Vector2(0, 6), p + Vector2(-5, 0)]), col)
		"kitchen":
			# 墙砖（上半截）
			var top := 250.0
			ci.draw_rect(Rect2(0, top, 1280, floor_y - top), Color(0.86, 0.93, 0.97, 0.55))
			for y in range(int(top), int(floor_y), 32):
				ci.draw_line(Vector2(0, y), Vector2(1280, y), col, 1.5)
			for x in range(0, 1280, 32):
				ci.draw_line(Vector2(x, top), Vector2(x, floor_y), col, 1.5)
			ci.draw_rect(Rect2(0, top - 6, 1280, 6), Color("f4c98f"))
		"stairs":
			ci.draw_rect(Rect2(0, floor_y - 190, 1280, 178), Color(1, 1, 1, 0.08))
			ci.draw_line(Vector2(0, floor_y - 190), Vector2(1280, floor_y - 190), Color(1, 1, 1, 0.25), 3.0)
			for x in range(30, 1280, 160):
				ci.draw_rect(Rect2(x, floor_y - 170, 120, 140), Color(1, 1, 1, 0.12), false, 2.0)


static func _night_sky(ci: CanvasItem, lv: Dictionary, t: float) -> void:
	var th := theme("roof")
	var sky: Array = th["sky"]
	vgrad(ci, Rect2(0, 0, 1280, 380), sky[0], sky[1])
	vgrad(ci, Rect2(0, 380, 1280, 340), sky[1], sky[2])
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 140:
		var p := Vector2(rng.randf() * 1280.0, rng.randf() * 520.0)
		var tw := 0.55 + 0.45 * sin(t * (1.0 + rng.randf() * 2.0) + rng.randf() * 6.0)
		var s := rng.randf_range(0.6, 1.8)
		ci.draw_circle(p, s, Color(1, 0.97, 0.9, 0.35 + 0.5 * tw * rng.randf()))


static func _deco(ci: CanvasItem, d: Dictionary, th: Dictionary, tname: String, t: float) -> void:
	var kind: String = d["type"]
	match kind:
		"window":
			var r := _r(d["rect"])
			var sky: Array = th["sky"]
			ci.draw_rect(r.grow(10), Color("fff4e6"))
			ci.draw_rect(r.grow(10), OUT, false, 2.0)
			var h3 := r.size.y / 2.0
			vgrad(ci, Rect2(r.position, Vector2(r.size.x, h3)), sky[0], sky[1])
			vgrad(ci, Rect2(r.position + Vector2(0, h3), Vector2(r.size.x, r.size.y - h3)), sky[1], sky[2])
			if d.get("sun", false):
				var sc := Vector2(r.position.x + r.size.x * 0.62, r.end.y - 6)
				ci.draw_circle(sc, 34, Color(1.0, 0.9, 0.62, 0.95))
				ci.draw_circle(sc, 44, Color(1.0, 0.9, 0.62, 0.25))
			if d.get("moon", false):
				var mc := Vector2(r.position.x + r.size.x * 0.7, r.position.y + r.size.y * 0.3)
				ci.draw_circle(mc, 20, Color(1.0, 0.97, 0.85, 1.0))
				ci.draw_circle(mc + Vector2(7, -4), 17, sky[0].lerp(sky[1], 0.25))
			if d.get("clouds", true) and tname != "stairs":
				var cx := r.position.x + fmod(t * 6.0 + 40.0, r.size.x + 120.0) - 60.0
				for i in 2:
					var cp := Vector2(cx + float(i) * r.size.x * 0.5, r.position.y + r.size.y * (0.35 + 0.2 * float(i)))
					var cc := Color(1, 0.86, 0.9, 0.6) if tname == "living" else Color(1, 1, 1, 0.8)
					for j in 3:
						var q := cp + Vector2(float(j) * 16.0 - 16.0, -absf(float(j) - 1.0) * -6.0)
						if r.has_point(q):
							ci.draw_circle(q, 14.0 - absf(float(j) - 1.0) * 3.0, cc)
			if tname == "stairs":
				for i in 12:
					var sp := r.position + Vector2(fmod(float(i) * 73.0, r.size.x), fmod(float(i) * 41.0, r.size.y * 0.6))
					ci.draw_circle(sp, 1.2, Color(1, 1, 0.9, 0.5 + 0.4 * sin(t * 2.0 + float(i))))
			# 窗棂
			ci.draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), Color("fff4e6"), 8.0)
			ci.draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Color("fff4e6"), 8.0)
			ci.draw_rect(r, OUT, false, 1.5)
			if d.get("curtains", true):
				var cc2 := Color("f3a0a6") if tname == "living" else Color("f6d89a")
				if tname == "stairs":
					cc2 = Color("8c7cc8")
				for side in [-1, 1]:
					var x0 := r.position.x - 24.0 if side < 0 else r.end.x - 8.0
					var pts := PackedVector2Array([Vector2(x0, r.position.y - 22), Vector2(x0 + 32, r.position.y - 22),
						Vector2(x0 + 32 - side * 6.0, r.end.y + 20), Vector2(x0, r.end.y + 26)])
					Art.blob(ci, pts, cc2, OUT, 1.5)
					for k in 3:
						var fx := x0 + 7.0 + float(k) * 8.0
						ci.draw_line(Vector2(fx, r.position.y - 18), Vector2(fx - side * 2.0, r.end.y + 18), cc2.darkened(0.12), 1.5)
				ci.draw_rect(Rect2(r.position.x - 40, r.position.y - 28, r.size.x + 80, 6), Color("c98d5f"))
		"frame":
			var fr := _r(d["rect"])
			ci.draw_rect(fr.grow(5), Color("d9a46d"))
			ci.draw_rect(fr.grow(5), OUT, false, 1.5)
			ci.draw_rect(fr, Color(d.get("bg", "fff3df")))
			var art: String = d.get("art", "moon")
			var c := fr.get_center()
			if art == "moon":
				ci.draw_circle(c, fr.size.y * 0.28, Color("ffe7a3"))
				ci.draw_circle(c + Vector2(fr.size.y * 0.1, -fr.size.y * 0.06), fr.size.y * 0.24, Color(d.get("bg", "fff3df")))
			elif art == "fish":
				Art.blob(ci, Art.ellipse(c, fr.size.x * 0.28, fr.size.y * 0.18, 16), Color("7fb3e0"), OUT, 1.2)
				Art.tri(ci, c + Vector2(fr.size.x * 0.25, 0), c + Vector2(fr.size.x * 0.42, -fr.size.y * 0.16), c + Vector2(fr.size.x * 0.42, fr.size.y * 0.16), Color("7fb3e0"))
				ci.draw_circle(c + Vector2(-fr.size.x * 0.15, -2), 2.0, OUT)
			elif art == "cat":
				ci.draw_circle(c + Vector2(0, 6), fr.size.y * 0.22, Color("f0a04e"))
				ci.draw_circle(c + Vector2(0, -fr.size.y * 0.12), fr.size.y * 0.16, Color("f0a04e"))
				Art.tri(ci, c + Vector2(-9, -fr.size.y * 0.2), c + Vector2(-7, -fr.size.y * 0.38), c + Vector2(-2, -fr.size.y * 0.25), Color("f0a04e"), Color(0, 0, 0, 0), 0.0)
				Art.tri(ci, c + Vector2(2, -fr.size.y * 0.25), c + Vector2(7, -fr.size.y * 0.38), c + Vector2(9, -fr.size.y * 0.2), Color("f0a04e"), Color(0, 0, 0, 0), 0.0)
			else:
				for i in 3:
					ci.draw_rect(Rect2(fr.position.x + 8 + float(i) * fr.size.x * 0.28, fr.end.y - 10 - float(i) * 9.0, fr.size.x * 0.22, 10 + float(i) * 9.0), [Color("f19c79"), Color("8fc1d9"), Color("f4d27a")][i])
		"lamp":
			var x: float = d["x"]
			var fy: float = d["floor"]
			var h: float = d.get("h", 210.0)
			ci.draw_line(Vector2(x, fy), Vector2(x, fy - h + 20), Color("6b5148"), 4.0)
			Art.blob(ci, Art.ellipse(Vector2(x, fy - 3), 22, 5, 14), Color("6b5148"), OUT, 1.2)
			var shade := PackedVector2Array([Vector2(x - 20, fy - h + 20), Vector2(x + 20, fy - h + 20), Vector2(x + 30, fy - h + 62), Vector2(x - 30, fy - h + 62)])
			Art.blob(ci, shade, Color("ffe1a8"), OUT, 1.6)
		"rug":
			var x0: float = d["x0"]
			var x1: float = d["x1"]
			var y: float = d["y"]
			ci.draw_rect(Rect2(x0, y - 7, x1 - x0, 9), Color("e5866f"))
			ci.draw_rect(Rect2(x0, y - 7, x1 - x0, 3), Color("f3b08e"))
			for xx in range(int(x0), int(x1), 9):
				ci.draw_line(Vector2(xx, y + 2), Vector2(xx + 2, y + 6), Color("e5866f"), 1.5)
		"plant":
			var pp := Vector2(d["x"], d["y"])
			for i in 7:
				var a := -PI * 0.5 + (float(i) - 3.0) * 0.32 + sin(t * 1.2 + float(i)) * 0.03
				var tip := pp + Vector2(cos(a), sin(a)) * (46.0 - absf(float(i) - 3.0) * 6.0)
				Art.blob(ci, Art.ellipse(pp.lerp(tip, 0.55), 6.5, 19.0, 12, a + PI * 0.5), Color("9fcca6").lerp(Color("c4e3b5"), float(i % 2) * 0.5), OUT, 1.1)
			Art.blob(ci, PackedVector2Array([pp + Vector2(-18, -4), pp + Vector2(18, -4), pp + Vector2(13, 28), pp + Vector2(-13, 28)]), Color("d98a5f"), OUT, 1.5)
		"clock":
			var cc := Vector2(d["x"], d["y"])
			ci.draw_circle(cc, 22, Color("fff6ea"))
			Art.ring(ci, cc, 22, OUT, 2.0)
			var hh := t * 0.05
			ci.draw_line(cc, cc + Vector2(sin(hh), -cos(hh)) * 12.0, OUT, 2.5)
			ci.draw_line(cc, cc + Vector2(sin(t * 0.6), -cos(t * 0.6)) * 17.0, OUT, 1.5)
		"pots":
			var px: float = d["x"]
			var py: float = d["y"]
			ci.draw_line(Vector2(px - 70, py), Vector2(px + 70, py), Color("b08060"), 4.0)
			for i in 3:
				var hx := px - 50.0 + float(i) * 50.0
				ci.draw_line(Vector2(hx, py), Vector2(hx, py + 12), OUT, 1.5)
				Art.blob(ci, Art.ellipse(Vector2(hx, py + 26), 14.0 + float(i) * 2.0, 12, 16), [Color("f19c79"), Color("8fc1d9"), Color("f4d27a")][i], OUT, 1.5)
		"sconce":
			var sp := Vector2(d["x"], d["y"])
			Art.blob(ci, PackedVector2Array([sp + Vector2(-12, -14), sp + Vector2(12, -14), sp + Vector2(8, 8), sp + Vector2(-8, 8)]), Color("ffe1a8"), OUT, 1.5)
			ci.draw_rect(Rect2(sp.x - 3, sp.y + 8, 6, 10), Color("6b5148"))
		"moon":
			var mc := Vector2(d["x"], d["y"])
			var mr: float = d.get("r", 70.0)
			ci.draw_circle(mc, mr, Color("fff2cf"))
			ci.draw_circle(mc + Vector2(-mr * 0.3, -mr * 0.2), mr * 0.16, Color(0.93, 0.86, 0.7, 0.6))
			ci.draw_circle(mc + Vector2(mr * 0.25, mr * 0.3), mr * 0.12, Color(0.93, 0.86, 0.7, 0.5))
			ci.draw_circle(mc + Vector2(mr * 0.35, -mr * 0.35), mr * 0.08, Color(0.93, 0.86, 0.7, 0.5))
		"city":
			var base_y: float = d.get("y", 560.0)
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var x := 0.0
			while x < 1280.0:
				var w := rng.randf_range(50, 120)
				var hh2 := rng.randf_range(60, 200)
				ci.draw_rect(Rect2(x, base_y - hh2, w, hh2 + 200), Color("2a2758"))
				for wy in range(int(base_y - hh2 + 12), int(base_y), 18):
					for wx in range(int(x + 8), int(x + w - 8), 14):
						if rng.randf() < 0.32:
							ci.draw_rect(Rect2(wx, wy, 6, 8), Color(1.0, 0.82, 0.45, 0.6 + 0.3 * rng.randf()))
				x += w + rng.randf_range(0, 18)
		"shelfbg":
			var sr := _r(d["rect"])
			ci.draw_rect(sr, Color(1, 1, 1, 0.12))
			for i in 3:
				var yy := sr.position.y + sr.size.y * (float(i) + 1.0) / 3.0
				ci.draw_line(Vector2(sr.position.x, yy), Vector2(sr.end.x, yy), Color(0.4, 0.25, 0.2, 0.25), 3.0)


static func _r(a: Array) -> Rect2:
	return Rect2(a[0], a[1], a[2], a[3])


# ================================================================ 光（叠加层）

static func lights(ci: CanvasItem, lv: Dictionary, t: float) -> void:
	var th := theme(lv.get("theme", "living"))
	var lc: Color = th["light"]
	for d in lv.get("deco", []):
		var kind: String = d["type"]
		if kind == "window":
			var r := _r(d["rect"])
			var dir: float = d.get("light_dir", 1.0)
			var fy := float(lv.get("floor_y", 640))
			var spread := 320.0 * dir
			var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x + spread, fy), Vector2(r.position.x + spread * 0.55, fy)])
			var c0 := Color(lc.r, lc.g, lc.b, lc.a * 0.9)
			var c1 := Color(lc.r, lc.g, lc.b, 0.0)
			ci.draw_polygon(pts, PackedColorArray([c0, c0, c1, c1]))
			Art.glow(ci, r.get_center(), r.size.x * 0.9, Color(lc.r, lc.g, lc.b, lc.a * 1.2))
		elif kind == "lamp":
			var x: float = d["x"]
			var fy2: float = d["floor"]
			var h: float = d.get("h", 210.0)
			var flick := 0.95 + 0.05 * sin(t * 7.3) * sin(t * 3.1)
			Art.glow(ci, Vector2(x, fy2 - h + 50), 190.0, Color(1.0, 0.75, 0.42, 0.42 * flick))
			Art.glow(ci, Vector2(x, fy2 - h + 50), 60.0, Color(1.0, 0.85, 0.6, 0.55 * flick))
		elif kind == "sconce":
			Art.glow(ci, Vector2(d["x"], d["y"]), 150.0, Color(1.0, 0.72, 0.42, 0.42))
			Art.glow(ci, Vector2(d["x"], d["y"]), 40.0, Color(1.0, 0.88, 0.65, 0.6))
		elif kind == "moon":
			var mr: float = d.get("r", 70.0)
			Art.glow(ci, Vector2(d["x"], d["y"]), mr * 4.5, Color(0.75, 0.75, 1.0, 0.22))
			Art.glow(ci, Vector2(d["x"], d["y"]), mr * 2.0, Color(1.0, 0.95, 0.8, 0.3))


static func sunbeams(ci: CanvasItem, suns: Array, t: float) -> void:
	# 阳光区：暖黄的一块光，带斜斜的光纹和浮尘，玩家一眼能看出“这里会秒睡”
	for poly in suns:
		var p: PackedVector2Array = poly
		var bb := Rect2(p[0], Vector2.ZERO)
		for q in p:
			bb = bb.expand(q)
		var cols := PackedColorArray()
		for q in p:
			var k := clampf((q.y - bb.position.y) / maxf(bb.size.y, 1.0), 0.0, 1.0)
			cols.append(Color(1.0, 0.80, 0.32, lerpf(0.16, 0.34, k)))
		ci.draw_polygon(p, cols)
		# 光纹
		var step := 26.0
		var x := bb.position.x - bb.size.y
		while x < bb.end.x:
			var a := Vector2(x + fmod(t * 6.0, step), bb.position.y)
			var b := a + Vector2(bb.size.y * 0.45, bb.size.y)
			var seg := Geometry2D.clip_polyline_with_polygon(PackedVector2Array([a, b]), p)
			for sg in seg:
				ci.draw_polyline(sg, Color(1.0, 0.97, 0.8, 0.22), 5.0, true)
			x += step
		# 边缘的亮线
		var closed := p.duplicate()
		closed.append(p[0])
		ci.draw_polyline(closed, Color(1.0, 0.85, 0.4, 0.55), 1.5, true)
		# 光里的浮尘
		for i in 16:
			var fx := bb.position.x + fmod(float(i) * 37.3 + t * (6.0 + float(i % 3)), maxf(bb.size.x, 1.0))
			var fy := bb.position.y + fmod(float(i) * 53.1 + t * (9.0 + float(i % 4) * 2.0), maxf(bb.size.y, 1.0))
			var q2 := Vector2(fx, fy)
			if Geometry2D.is_point_in_polygon(q2, p):
				ci.draw_circle(q2, 1.8, Color(1, 0.98, 0.85, 0.65 + 0.3 * sin(t * 3.0 + float(i))))


# ================================================================ 家具

static func furniture(ci: CanvasItem, kind: String, r: Rect2, tname: String, opts: Dictionary) -> void:
	var th := theme(tname)
	match kind:
		"floor":
			_floor(ci, r, th, tname)
		"pouf":
			_shadow(ci, r)
			var col := Color(opts.get("color", "e8b24a"))
			Art.blob(ci, Art.rrect(r, 16.0, 5), col, OUT, 2.0)
			Art.blob(ci, Art.rrect(Rect2(r.position.x + 4, r.position.y + 3, r.size.x - 8, 12), 6.0, 3), col.lightened(0.18), Color(0, 0, 0, 0), 0.0)
			for i in 4:
				var bx := r.position.x + r.size.x * (float(i) + 0.5) / 4.0
				ci.draw_circle(Vector2(bx, r.position.y + r.size.y * 0.55), 2.4, col.darkened(0.25))
		"sofa":
			_sofa(ci, r, opts)
		"sill":
			ci.draw_rect(r, Color("fbeee2"))
			ci.draw_rect(Rect2(r.position.x, r.position.y + 14, r.size.x, r.size.y - 14), Color("f4ddcb"))
			for i in range(1, int(r.size.y / 34.0) + 1):
				var yy := r.position.y + 14 + float(i) * 34.0
				if yy < r.end.y - 6:
					ci.draw_line(Vector2(r.position.x + 10, yy), Vector2(r.end.x - 10, yy), Color("e6cbb8"), 1.5)
			Art.blob(ci, Art.rrect(Rect2(r.position.x - 8, r.position.y - 2, r.size.x + 16, 16), 5.0, 2), Color("ffffff"), OUT, 1.6)
			ci.draw_line(Vector2(r.position.x, r.position.y + 14), Vector2(r.position.x, r.end.y), OUT, 1.5)
		"box":
			_shadow(ci, r)
			Art.blob(ci, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), Color("d3a26a"), OUT, 1.8)
			ci.draw_line(Vector2(r.position.x, r.position.y + 9), Vector2(r.end.x, r.position.y + 9), Color("b5844f"), 1.5)
			ci.draw_rect(Rect2(r.get_center().x - 5, r.position.y, 10, 9), Color("efe2c4"))
			Art.tri(ci, r.position, r.position + Vector2(-10, -12), r.position + Vector2(14, 0), Color("dcae78"))
			Art.tri(ci, Vector2(r.end.x, r.position.y), Vector2(r.end.x + 10, r.position.y - 12), Vector2(r.end.x - 14, r.position.y), Color("dcae78"))
		"box_open":
			var bx2 := Rect2(r.position.x - 6, r.end.y - 30, r.size.x + 14, 30)
			Art.blob(ci, PackedVector2Array([bx2.position + Vector2(8, 0), Vector2(bx2.end.x, bx2.position.y), bx2.end, Vector2(bx2.position.x, bx2.end.y)]), Color("d3a26a"), OUT, 1.8)
			Art.blob(ci, Art.ellipse(Vector2(bx2.position.x + 12, bx2.get_center().y), 7, 13, 12), Color("8a6440"), OUT, 1.4)
		"shelf":
			_shadow(ci, r)
			Art.blob(ci, Art.rrect(r, 4.0, 2), Color("c58a5e"), OUT, 2.0)
			var inner := r.grow(-8)
			ci.draw_rect(inner, Color("9a6748"))
			var rows := maxi(1, int(inner.size.y / 62.0))
			var rh := inner.size.y / float(rows)
			var bcols := [Color("f19c79"), Color("8fc1d9"), Color("f4d27a"), Color("c9a3e0"), Color("f6efe6"), Color("e47a7a")]
			for ry in rows:
				var y0 := inner.position.y + float(ry) * rh
				ci.draw_rect(Rect2(inner.position.x, y0 + rh - 6, inner.size.x, 6), Color("c58a5e"))
				var x := inner.position.x + 4.0
				var i := ry * 3
				while x < inner.end.x - 12:
					var bw := 9.0 + float((i * 7) % 6)
					var bh := rh - 12.0 - float((i * 5) % 14)
					ci.draw_rect(Rect2(x, y0 + rh - 6 - bh, bw, bh), bcols[i % bcols.size()])
					ci.draw_rect(Rect2(x, y0 + rh - 6 - bh, bw, bh), OUT, false, 1.0)
					x += bw + 1.0
					i += 1
		"cabinet":
			_shadow(ci, r)
			var cc := Color(opts.get("color", "e9c79c"))
			Art.blob(ci, Art.rrect(r, 5.0, 2), cc, OUT, 2.0)
			ci.draw_rect(Rect2(r.position.x - 4, r.position.y, r.size.x + 8, 9), cc.lightened(0.15))
			ci.draw_rect(Rect2(r.position.x - 4, r.position.y, r.size.x + 8, 9), OUT, false, 1.5)
			var nd := maxi(1, int(r.size.x / 90.0))
			for i in nd:
				var dr := Rect2(r.position.x + 8 + float(i) * (r.size.x - 16) / float(nd), r.position.y + 18, (r.size.x - 16) / float(nd) - 6, r.size.y - 28)
				if dr.size.y > 12:
					ci.draw_rect(dr, cc.darkened(0.08))
					ci.draw_rect(dr, OUT, false, 1.2)
					ci.draw_circle(Vector2(dr.end.x - 8, dr.get_center().y), 3.0, Color("8a6440"))
		"table":
			var legc := Color("a8714f")
			var fy := float(opts.get("floor", 640))
			ci.draw_rect(Rect2(r.position.x + 10, r.end.y, 8, fy - r.end.y), legc)
			ci.draw_rect(Rect2(r.end.x - 18, r.end.y, 8, fy - r.end.y), legc)
			ci.draw_rect(Rect2(r.position.x + 10, r.end.y, 8, fy - r.end.y), OUT, false, 1.2)
			ci.draw_rect(Rect2(r.end.x - 18, r.end.y, 8, fy - r.end.y), OUT, false, 1.2)
			Art.blob(ci, Art.rrect(r, 4.0, 2), Color("c88a5f"), OUT, 1.8)
			if opts.get("cloth", false):
				var cl := PackedVector2Array([r.position + Vector2(-6, -2), Vector2(r.end.x + 6, r.position.y - 2), Vector2(r.end.x + 10, r.end.y + 26), Vector2(r.position.x - 10, r.end.y + 26)])
				Art.blob(ci, cl, Color("f7d8e0"), OUT, 1.5)
				for i in range(int(r.position.x), int(r.end.x), 22):
					ci.draw_circle(Vector2(i + 8, r.end.y + 12), 3.0, Color("f3a0a6"))
		"counter":
			_shadow(ci, r)
			Art.blob(ci, Art.rrect(Rect2(r.position.x, r.position.y + 10, r.size.x, r.size.y - 10), 3.0, 2), Color("bcd9ea"), OUT, 2.0)
			Art.blob(ci, Art.rrect(Rect2(r.position.x - 6, r.position.y, r.size.x + 12, 12), 3.0, 2), Color("fbf6ee"), OUT, 1.8)
			var nd2 := maxi(1, int(r.size.x / 80.0))
			for i in nd2:
				var dx := r.position.x + 8 + float(i) * (r.size.x - 16) / float(nd2)
				var dw := (r.size.x - 16) / float(nd2) - 6
				if r.size.y > 60:
					ci.draw_rect(Rect2(dx, r.position.y + 20, dw, 22), Color("cfe5f1"))
					ci.draw_rect(Rect2(dx, r.position.y + 20, dw, 22), OUT, false, 1.2)
					ci.draw_line(Vector2(dx + dw * 0.35, r.position.y + 31), Vector2(dx + dw * 0.65, r.position.y + 31), OUT, 2.0)
				if r.size.y > 100:
					ci.draw_rect(Rect2(dx, r.position.y + 50, dw, r.size.y - 60), Color("cfe5f1"))
					ci.draw_rect(Rect2(dx, r.position.y + 50, dw, r.size.y - 60), OUT, false, 1.2)
		"stair":
			_stair(ci, r)
		"basket":
			Art.blob(ci, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), Color("d8b07a"), OUT, 1.8)
			for yy in range(int(r.position.y) + 6, int(r.end.y), 9):
				ci.draw_line(Vector2(r.position.x + 2, yy), Vector2(r.end.x - 2, yy), Color("bf935c"), 1.5)
		"wall":
			ci.draw_rect(r, th["wall_bot"].darkened(0.06))
			ci.draw_rect(r, OUT, false, 1.5)
		"radiator":
			_shadow(ci, r)
			Art.blob(ci, Art.rrect(r, 5.0, 2), Color("f2efe9"), OUT, 1.8)
			for x in range(int(r.position.x) + 10, int(r.end.x) - 4, 12):
				ci.draw_line(Vector2(x, r.position.y + 8), Vector2(x, r.end.y - 6), Color("d8d2c8"), 3.0)
		"chimney":
			Art.blob(ci, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), Color("b86a5c"), OUT, 2.0)
			for yy in range(int(r.position.y) + 14, int(r.end.y), 14):
				ci.draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), Color("9c574c"), 1.5)
				var off := 0 if (yy / 14) % 2 == 0 else 12
				for xx in range(int(r.position.x) + off, int(r.end.x), 24):
					ci.draw_line(Vector2(xx, yy - 14), Vector2(xx, yy), Color("9c574c"), 1.5)
			ci.draw_rect(Rect2(r.position.x - 6, r.position.y - 4, r.size.x + 12, 10), Color("c97f70"))
			ci.draw_rect(Rect2(r.position.x - 6, r.position.y - 4, r.size.x + 12, 10), OUT, false, 1.5)
		"roof":
			Art.blob(ci, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), th["floor"], OUT, 2.0)
			for yy in range(int(r.position.y) + 12, int(r.end.y), 14):
				for xx in range(int(r.position.x), int(r.end.x), 20):
					var off2 := 10 if (yy / 14) % 2 == 0 else 0
					ci.draw_arc(Vector2(xx + off2, yy), 10, 0.0, PI, 6, th["floor_line"], 1.5)
		"tank":
			_shadow(ci, r)
			Art.blob(ci, Art.rrect(r, 12.0, 4), Color("8fb0c9"), OUT, 2.0)
			for yy in range(int(r.position.y) + 16, int(r.end.y) - 6, 18):
				ci.draw_line(Vector2(r.position.x + 4, yy), Vector2(r.end.x - 4, yy), Color("7393ab"), 2.0)
		"crate":
			_shadow(ci, r)
			Art.blob(ci, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), Color("c99a68"), OUT, 1.8)
			ci.draw_line(r.position, r.end, Color("a87a4c"), 3.0)
			ci.draw_rect(r.grow(-4), Color("a87a4c"), false, 2.0)
		_:
			ci.draw_rect(r, Color("c9a58a"))
			ci.draw_rect(r, OUT, false, 1.5)


static func _stair(ci: CanvasItem, r: Rect2) -> void:
	# 木楼梯 / 楼梯平台：护墙板 + 踏板 + 地毯
	var face := Color("c99b74")
	ci.draw_rect(r, face)
	if r.size.y > 140.0:
		var n := maxi(1, int(r.size.x / 130.0))
		var pw := (r.size.x - 20.0) / float(n)
		for i in n:
			var pr := Rect2(r.position.x + 10.0 + float(i) * pw + 6.0, r.position.y + 34.0, pw - 12.0, r.size.y - 54.0)
			ci.draw_rect(pr, face.lightened(0.08))
			ci.draw_rect(pr, face.darkened(0.18), false, 2.0)
			ci.draw_rect(pr.grow(-8.0), face.darkened(0.08), false, 1.5)
	else:
		for x in range(int(r.position.x) + 30, int(r.end.x), 46):
			ci.draw_line(Vector2(x, r.position.y + 14), Vector2(x, r.end.y), face.darkened(0.12), 1.5)
	ci.draw_rect(r, OUT, false, 2.0)
	# 踏板
	Art.blob(ci, Art.rrect(Rect2(r.position.x - 6, r.position.y - 2, r.size.x + 12, 14), 4.0, 2), Color("e4bd93"), OUT, 1.8)
	ci.draw_line(Vector2(r.position.x - 4, r.position.y + 13), Vector2(r.end.x + 4, r.position.y + 13), Color(0.3, 0.15, 0.12, 0.25), 3.0)
	# 地毯
	var cw := minf(r.size.x * 0.7, 260.0)
	var cx := r.get_center().x
	ci.draw_rect(Rect2(cx - cw * 0.5, r.position.y - 3, cw, 7), Color("b8577a"))
	ci.draw_rect(Rect2(cx - cw * 0.5, r.position.y + 1, cw, 2), Color("e9a3bf"))


static func _shadow(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_colored_polygon(Art.ellipse(Vector2(r.get_center().x, r.end.y), r.size.x * 0.58, 7.0, 18), Color(0.25, 0.1, 0.12, 0.16))


static func _floor(ci: CanvasItem, r: Rect2, th: Dictionary, tname: String) -> void:
	ci.draw_rect(r, th["floor"])
	if tname == "kitchen":
		var s := 40
		for y in range(int(r.position.y), int(r.end.y), s):
			for x in range(int(r.position.x), int(r.end.x), s):
				if ((x / s) + (y / s)) % 2 == 0:
					ci.draw_rect(Rect2(x, y, s, s), Color("d7e5ef"))
	else:
		for y in range(int(r.position.y) + 14, int(r.end.y), 18):
			var off := 0 if (y / 18) % 2 == 0 else 60
			ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), th["floor_line"], 1.0)
			for x in range(int(r.position.x) + off, int(r.end.x), 120):
				ci.draw_line(Vector2(x, y - 18), Vector2(x, y), th["floor_line"], 1.0)
	ci.draw_line(Vector2(r.position.x, r.position.y + 1), Vector2(r.end.x, r.position.y + 1), th["floor_hi"], 2.5)
	ci.draw_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), OUT, 1.5)
	# 冷地面：一层淡淡的冷色调，提示阿黄不愿意下来
	vgrad(ci, Rect2(r.position.x, r.position.y + 2, r.size.x, 26), Color(0.55, 0.7, 0.95, 0.20), Color(0.55, 0.7, 0.95, 0.0))


static func _sofa(ci: CanvasItem, r: Rect2, opts: Dictionary) -> void:
	var col := Color(opts.get("color", "6fa8bd"))
	var back := Rect2(r.position.x + 10, r.position.y - 52, r.size.x - 20, 60)
	Art.blob(ci, Art.rrect(back, 18.0, 5), col.darkened(0.12).lerp(Color(1, 1, 1), 0.05), OUT, 1.6)
	var nc := maxi(1, int(r.size.x / 130.0))
	for i in nc:
		var cr := Rect2(back.position.x + 10 + float(i) * (back.size.x - 20) / float(nc), back.position.y + 8, (back.size.x - 20) / float(nc) - 8, 46)
		Art.blob(ci, Art.rrect(cr, 14.0, 4), col.darkened(0.04), OUT, 1.2)
	_shadow(ci, r)
	ci.draw_rect(Rect2(r.position.x + 12, r.end.y - 6, 8, 6), Color("6b5148"))
	ci.draw_rect(Rect2(r.end.x - 20, r.end.y - 6, 8, 6), Color("6b5148"))
	Art.blob(ci, Art.rrect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y - 6), 14.0, 4), col, OUT, 2.0)
	for i in nc:
		var sr := Rect2(r.position.x + 8 + float(i) * (r.size.x - 16) / float(nc), r.position.y + 2, (r.size.x - 16) / float(nc) - 4, 22)
		Art.blob(ci, Art.rrect(sr, 10.0, 4), col.lightened(0.14), OUT, 1.2)
	ci.draw_line(Vector2(r.position.x + 10, r.position.y + 34), Vector2(r.end.x - 10, r.position.y + 34), col.darkened(0.15), 2.0)
