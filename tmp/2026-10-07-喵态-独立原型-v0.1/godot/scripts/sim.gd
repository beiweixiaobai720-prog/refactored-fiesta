extends RefCounted
## 喵态 · 核心模拟（确定性、定步长 60Hz）
##
## 小猫只有几条各自的习性：
##   · 看得见红点 → 追过去，够不着就往上扑（液）
##   · 看不见红点约一秒 → 就地揣手睡着，睡着的猫像家具一样结实（固）
##   · 红点在睡猫身上停一会儿 → 叫醒它
##   · 拍手 → 附近的猫炸毛弹开，碰到谁就把谁也吓到（气）
##   · 晒到太阳 → 秒睡，红点叫不醒
##   · 睡着时身下没了支撑 → 掉下去，摔得够高就醒
## 阿黄（老猫）只会慢慢往前走：一步最多迈上或迈下约两层猫的高度，不肯跳；只踩家具和睡着的猫，
## 不踩冰凉的地面；身边还有醒着的猫在闹，他就坐下来等（怕吵）。
## “流动、堆坡、定形、搭桥、连锁、蹦床、雪崩”都没有写进规则，只从这些习性里长出来。

const R := 15.0
const D := 30.0
const GRAVITY := 1500.0
const DT := 1.0 / 60.0
const SUBSTEPS := 2
const ITERS := 4

enum { AWAKE, SLEEP, FALL, SPOOK }
enum { O_WALK, O_WAIT, O_AIR, O_GOAL }

const RUN_SPEED := 235.0
const JUMP_V := 450.0
const WAKE_DWELL := 0.35
const WAKE_REACH := 23.0          # 红点离睡猫中心这么近就算“照在它身上”
const SPOOK_TIME := 0.8
const SPOOK_PUSH := 150.0
const SPOOK_UP := 240.0
const SPOOK_DENSITY := 0.2
const SPOOK_MAX := 820.0
const CHAIN_GAP := 7.0
const CHAIN_DELAY := 0.05
const CLAP_RADIUS := 95.0
const SUN_SLEEP := 0.22
const MEMORY := 0.55              # 红点被挡住后，还会朝最后看见的地方找一会儿
const START_GRACE := 4.0          # 开局醒着的猫多玩一会儿再犯困
const FALL_WAKE := 15.0           # 睡着时往下掉超过这个高度就会醒

const AH_W := 54.0
const AH_H := 42.0
const AH_SPEED := 62.0
const AH_STEP_UP := 54.0
const AH_STEP_DOWN := 54.0
const CAP := 9.0                  # 猫背顶上能踩稳的宽度（离圆心的水平距离）
const TRAMP_BASE := 255.0
const TRAMP_PER := 105.0
const TRAMP_MAX := 1000.0
const TRAMP_VX := 120.0


class Kit:
	var id := 0
	var pos := Vector2.ZERO
	var prev := Vector2.ZERO
	var vel := Vector2.ZERO
	var state := 0
	var facing := 1.0
	var sees := false
	var react := 0.0
	var idle_t := 0.0
	var sleep_delay := 1.0
	var dwell := 0.0
	var spook_t := 0.0
	var spook_age := 99.0
	var spook_pend := -1.0
	var spook_acc := Vector2.ZERO
	var spook_n := 0
	var spook_hop := 0
	var spook_cid := -1
	var grounded := false
	var on_kit := false
	var blocked := 0.0
	var jump_cd := 0.0
	var speed_k := 1.0
	var jump_k := 1.0
	var fall_y0 := 0.0
	var settle := 0
	var jam_t := 0.0
	var jam_p := Vector2.ZERO
	var unsupported := 0
	var sun_t := 0.0
	var in_sun := false
	var coat := 0
	var seed := 0.0
	var asleep_t := 0.0
	var awake_t := 0.0
	var near: Array = []
	var carried := false        # 阿黄踩过它
	var carried_at := Vector2(-99999, -99999)
	var sleep_why := ""
	var wedged := false            # 卡在缝里、规则判不出来但实际不会动的睡猫
	var mem := Vector2.ZERO        # 最后看见红点的位置
	var mem_t := 99.0              # 失去视线后的时间


class Block:
	var r := Rect2()
	var solid := true
	var sight := true
	var cold := false              # 冰凉的地面：阿黄不肯往上面走
	var kind := "wall"
	var tag := ""
	var opts := {}


class Old:
	var pos := Vector2.ZERO      # 脚底中心
	var vel := Vector2.ZERO
	var dir := 1.0
	var mode := 0
	var wait_t := 0.0
	var walk_t := 0.0
	var air_t := 0.0
	var launch_n := 0
	var launch_t := -1.0
	var launch_y0 := 0.0
	var launch_peak := 0.0
	var on_kit := false
	var over_gap := false
	var under: Array = []
	var steps_up := 0
	var last_launch_v := 0.0
	var start_y := 0.0
	var on_cold := false
	var why := ""                # 停下来的原因：high / drop / cold


var kits: Array = []
var blocks: Array = []
var suns: Array = []
var spawners: Array = []
var goal := Rect2()
var old: Old = null
var bounds := Rect2(0, 0, 1280, 720)
var rng := RandomNumberGenerator.new()
var time := 0.0
var frame := 0
var events: Array = []
var dot_on := false
var dot := Vector2(640, 360)
var won := false
var next_id := 0
var clap_id := 0
var sorted: Array = []
var coat_offset := 0
var last_hit := ""
var last_hit_kit := -1


func setup(level: Dictionary, seed_val: int = 7) -> void:
	rng.seed = seed_val
	kits.clear()
	blocks.clear()
	suns.clear()
	spawners.clear()
	events.clear()
	time = 0.0
	frame = 0
	won = false
	next_id = 0
	clap_id = 0
	dot_on = false
	coat_offset = int(level.get("coat_offset", 0))
	var bd: Array = level.get("bounds", [0, 0, 1280, 720])
	bounds = Rect2(bd[0], bd[1], bd[2], bd[3])
	for b in level.get("blocks", []):
		var bl := Block.new()
		bl.r = Rect2(b[0], b[1], b[2], b[3])
		bl.kind = b[4] if b.size() > 4 else "wall"
		var o: Dictionary = b[5] if b.size() > 5 else {}
		bl.opts = o
		bl.solid = o.get("solid", true)
		bl.sight = o.get("sight", true)
		bl.tag = o.get("tag", "")
		bl.cold = o.get("cold", bl.kind == "floor")
		blocks.append(bl)
	# 看不见的边界墙
	for rr in [Rect2(bounds.position.x - 60, bounds.position.y - 400, 60, bounds.size.y + 800),
			Rect2(bounds.end.x, bounds.position.y - 400, 60, bounds.size.y + 800),
			Rect2(bounds.position.x - 60, bounds.position.y - 60, bounds.size.x + 120, 60)]:
		var w := Block.new()
		w.r = rr
		w.kind = "bound"
		blocks.append(w)
	for s in level.get("sun", []):
		var poly := PackedVector2Array()
		for i in range(0, s.size(), 2):
			poly.append(Vector2(s[i], s[i + 1]))
		suns.append(poly)
	for p in level.get("kits", []):
		var st: int = AWAKE
		if p.size() > 2:
			st = SLEEP if p[2] == "s" else AWAKE
		var k := add_kit(Vector2(p[0], p[1]), st)
		if st == SLEEP:
			k.asleep_t = 5.0
		else:
			k.idle_t = -START_GRACE
	if level.has("old"):
		var od: Array = level["old"]
		old = Old.new()
		old.pos = Vector2(od[0], od[1])
		old.dir = od[2] if od.size() > 2 else 1.0
		old.mode = O_WALK
		old.start_y = old.pos.y
	else:
		old = null
	if level.has("goal"):
		var g: Array = level["goal"]
		goal = Rect2(g[0], g[1], g[2], g[3])
	else:
		goal = Rect2(-9999, -9999, 1, 1)
	for sp in level.get("spawners", []):
		# {"block": index, "n": 15, "dir": 1}
		var s := {
			"block": blocks[int(sp["block"])],
			"n": int(sp["n"]),
			"left": int(sp["n"]),
			"t": 0.25,
			"open": false,
			"dir": float(sp.get("dir", 1.0)),
		}
		spawners.append(s)
	sorted = kits.duplicate()
	_relax_initial()


func _relax_initial() -> void:
	# 开局把互相挤着的猫轻轻推开，但不给它们速度（免得一开局就被“弹飞”）
	_broadphase()
	for it in 90:
		for k: Kit in kits:
			k.prev = k.pos
		_solve()
		if it % 10 == 9:
			_broadphase()
	for k: Kit in kits:
		k.prev = k.pos
		k.vel = Vector2.ZERO


func add_kit(p: Vector2, st: int = AWAKE) -> Kit:
	var k := Kit.new()
	k.id = next_id
	next_id += 1
	k.pos = p
	k.prev = p
	k.state = st
	k.speed_k = rng.randf_range(0.86, 1.12)
	k.jump_k = rng.randf_range(0.93, 1.04)
	k.sleep_delay = rng.randf_range(0.7, 1.25)
	k.coat = (k.id * 5 + coat_offset) % 9
	k.seed = rng.randf() * 100.0
	k.facing = 1.0 if rng.randf() < 0.5 else -1.0
	kits.append(k)
	sorted.append(k)
	return k


# ---------------------------------------------------------------- 主循环

func step(inp: Dictionary) -> void:
	events.clear()
	frame += 1
	time += DT
	dot_on = bool(inp.get("dot_on", false))
	if inp.has("dot"):
		dot = clamp_dot(inp["dot"])
	if inp.has("clap"):
		clap(inp["clap"])
	_spawners_update()
	_spook_update()
	_sun_update()
	_ai_update()
	_broadphase()
	var h := DT / SUBSTEPS
	for s in SUBSTEPS:
		_integrate(h)
		for i in ITERS:
			_solve()
		_post(h)
	_sleepers_update()
	if old != null:
		_old_update()
		_goal_update()


# ---------------------------------------------------------------- 红点与视线

func clamp_dot(p: Vector2) -> Vector2:
	p.x = clampf(p.x, bounds.position.x + 6.0, bounds.end.x - 6.0)
	p.y = clampf(p.y, bounds.position.y + 6.0, bounds.end.y - 6.0)
	for it in 4:
		var moved := false
		for b: Block in blocks:
			if not b.solid:
				continue
			var r: Rect2 = b.r.grow(2.0)
			if r.has_point(p):
				var l := p.x - r.position.x
				var rr := r.end.x - p.x
				var t := p.y - r.position.y
				var bt := r.end.y - p.y
				var m := minf(minf(l, rr), minf(t, bt))
				if m == t:
					p.y = r.position.y - 0.5
				elif m == bt:
					p.y = r.end.y + 0.5
				elif m == l:
					p.x = r.position.x - 0.5
				else:
					p.x = r.end.x + 0.5
				moved = true
		if not moved:
			break
	return p


func los(a: Vector2, b: Vector2) -> bool:
	for bl: Block in blocks:
		if bl.sight and _seg_hits_rect(a, b, bl.r):
			return false
	return true


func _seg_hits_rect(a: Vector2, b: Vector2, r0: Rect2) -> bool:
	var r := r0.grow(-1.0)
	var tmin := 0.0
	var tmax := 1.0
	var dx := b.x - a.x
	if absf(dx) < 0.000001:
		if a.x < r.position.x or a.x > r.end.x:
			return false
	else:
		var t1 := (r.position.x - a.x) / dx
		var t2 := (r.end.x - a.x) / dx
		if t1 > t2:
			var tt := t1
			t1 = t2
			t2 = tt
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return false
	var dy := b.y - a.y
	if absf(dy) < 0.000001:
		if a.y < r.position.y or a.y > r.end.y:
			return false
	else:
		var t3 := (r.position.y - a.y) / dy
		var t4 := (r.end.y - a.y) / dy
		if t3 > t4:
			var tt2 := t3
			t3 = t4
			t4 = tt2
		tmin = maxf(tmin, t3)
		tmax = minf(tmax, t4)
		if tmin > tmax:
			return false
	return true


func kit_sees(k: Kit) -> bool:
	return dot_on and los(k.pos + Vector2(0, -R * 0.35), dot)


# ---------------------------------------------------------------- 拍手与炸毛

func clap(p: Vector2) -> void:
	clap_id += 1
	var cnt := 0
	for k: Kit in kits:
		var d := k.pos.distance_to(p)
		if d <= CLAP_RADIUS:
			var dir := (k.pos - p) / d if d > 1.0 else Vector2.UP
			_queue_spook(k, dir, 0, rng.randf_range(0.0, 0.035), clap_id)
			cnt += 1
	events.append({"t": "clap", "p": p, "n": cnt, "cid": clap_id})


func _queue_spook(k: Kit, dir: Vector2, hop: int, delay: float, cid: int) -> void:
	if k.spook_cid == cid and k.spook_pend < 0.0:
		return
	k.spook_acc += dir
	k.spook_n += 1
	if k.spook_cid != cid:
		k.spook_cid = cid
		k.spook_pend = delay
		k.spook_hop = hop


func _spook_update() -> void:
	for k: Kit in kits:
		if k.spook_pend >= 0.0:
			k.spook_pend -= DT
			if k.spook_pend < 0.0:
				_apply_spook(k)


func _apply_spook(k: Kit) -> void:
	var was := k.state
	var dir := k.spook_acc
	if dir.length() < 0.05:
		dir = Vector2.UP
	dir = dir.normalized()
	k.spook_acc = Vector2.ZERO
	k.spook_n = 0
	# 周围越挤，弹得越猛：密度放大来自邻居数量
	var m := 0
	for j: Kit in kits:
		if j == k:
			continue
		if absf(j.pos.x - k.pos.x) > 2.0 * R + CHAIN_GAP:
			continue
		if j.pos.distance_to(k.pos) <= 2.0 * R + CHAIN_GAP:
			m += 1
	var f := 1.0 + SPOOK_DENSITY * float(m)
	var v := (dir * SPOOK_PUSH + Vector2(0, -SPOOK_UP)) * f * rng.randf_range(0.9, 1.08)
	if v.length() > SPOOK_MAX:
		v = v.normalized() * SPOOK_MAX
	k.vel = v
	k.prev = k.pos
	if was == SLEEP:
		k.wedged = false
		_unwedge_near(k)
	k.state = SPOOK
	k.spook_t = SPOOK_TIME
	k.spook_age = 0.0
	k.dwell = 0.0
	k.unsupported = 0
	events.append({"t": "spook", "id": k.id, "hop": k.spook_hop, "from": was, "cid": k.spook_cid, "m": m})
	for j: Kit in kits:
		if j == k:
			continue
		if absf(j.pos.x - k.pos.x) > 2.0 * R + CHAIN_GAP:
			continue
		var d := j.pos.distance_to(k.pos)
		if d <= 2.0 * R + CHAIN_GAP:
			var jd := (j.pos - k.pos) / d if d > 0.5 else Vector2.UP
			_queue_spook(j, jd, k.spook_hop + 1, CHAIN_DELAY, k.spook_cid)
	if old != null:
		_old_kick(k)


# ---------------------------------------------------------------- 阳光

func _sun_update() -> void:
	if suns.is_empty():
		return
	for k: Kit in kits:
		k.in_sun = false
		for poly in suns:
			if Geometry2D.is_point_in_polygon(k.pos, poly):
				k.in_sun = true
				break


func point_in_sun(p: Vector2) -> bool:
	for poly in suns:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


# ---------------------------------------------------------------- 纸箱等触发

func _spawners_update() -> void:
	for s in spawners:
		var bl: Block = s["block"]
		if not s["open"]:
			for k: Kit in kits:
				if k.state != AWAKE:
					continue
				if _dist_point_rect(k.pos, bl.r) < R + 3.0:
					s["open"] = true
					bl.solid = false
					bl.sight = false
					bl.kind = "box_open"
					events.append({"t": "box", "p": bl.r.get_center()})
					break
		elif s["left"] > 0:
			s["t"] -= DT
			if s["t"] <= 0.0:
				s["t"] = 0.075
				var c: Vector2 = bl.r.get_center()
				var p := Vector2(c.x + rng.randf_range(-6.0, 6.0), bl.r.position.y + 4.0 + rng.randf_range(-4.0, 4.0))
				var k := add_kit(p, AWAKE)
				k.vel = Vector2(float(s["dir"]) * rng.randf_range(40.0, 230.0), -rng.randf_range(160.0, 360.0))
				k.react = rng.randf_range(0.1, 0.5)
				s["left"] -= 1
				events.append({"t": "pour", "id": k.id})


func _dist_point_rect(p: Vector2, r: Rect2) -> float:
	var cx := clampf(p.x, r.position.x, r.end.x)
	var cy := clampf(p.y, r.position.y, r.end.y)
	return Vector2(p.x - cx, p.y - cy).length()


# ---------------------------------------------------------------- 小猫的习性

func _ai_update() -> void:
	for k: Kit in kits:
		k.spook_age += DT
		match k.state:
			SPOOK:
				k.spook_t -= DT
				if k.grounded:
					k.vel.x *= 0.86
				if k.spook_t <= 0.0:
					k.state = AWAKE
					k.idle_t = 0.0
					k.react = 0.12
					k.sees = false
					k.awake_t = 0.0
			SLEEP:
				k.asleep_t += DT
				if dot_on and dot.distance_squared_to(k.pos) < WAKE_REACH * WAKE_REACH:
					if k.in_sun:
						k.dwell = minf(k.dwell + DT, WAKE_DWELL * 0.6)
					else:
						k.dwell += DT
						if k.dwell >= WAKE_DWELL:
							_wake(k, "dot")
				else:
					k.dwell = maxf(0.0, k.dwell - DT * 2.0)
			FALL:
				if k.grounded:
					k.vel.x *= 0.8
			AWAKE:
				_ai_awake(k)


func _ai_awake(k: Kit) -> void:
	k.awake_t += DT
	var see := kit_sees(k)
	if see:
		if not k.sees and k.mem_t > MEMORY:
			k.react = maxf(k.react, rng.randf_range(0.03, 0.26))
		k.sees = true
		k.idle_t = minf(k.idle_t, 0.0)
		if k.idle_t < 0.0:
			k.idle_t = 0.0
		k.mem = dot
		k.mem_t = 0.0
		if k.react > 0.0:
			k.react -= DT
			_brake(k)
		else:
			_chase(k, dot)
	elif dot_on and k.mem_t < MEMORY:
		# 红点被挡住了：先去最后看见它的地方找一找
		k.sees = false
		k.mem_t += DT
		_chase(k, k.mem)
	else:
		k.sees = false
		k.mem_t = maxf(k.mem_t, MEMORY + 0.01) if dot_on else 99.0
		k.idle_t += DT
		_brake(k)
		var settled := k.grounded or (k.idle_t >= k.sleep_delay + 0.8 and k.vel.length() < 15.0)
		var stuck := k.idle_t >= k.sleep_delay + 2.5
		if k.idle_t >= k.sleep_delay and ((settled and k.vel.length() < 70.0) or stuck) and not _overlaps_old(k):
			_fall_asleep(k, "dark")
			return
	k.jump_cd -= DT
	if k.in_sun and k.grounded:
		k.sun_t += DT
		if k.sun_t >= SUN_SLEEP and not _overlaps_old(k):
			_fall_asleep(k, "sun")
	else:
		k.sun_t = 0.0


func _chase(k: Kit, tgt: Vector2) -> void:
	var dx := tgt.x - k.pos.x
	var dy := tgt.y - k.pos.y
	var adx := absf(dx)
	var dir := signf(dx)
	var target := 0.0
	if adx > 5.0:
		target = dir * RUN_SPEED * k.speed_k * clampf(adx / 45.0, 0.3, 1.0)
	var a := 12.0 if k.grounded else 3.5
	k.vel.x += (target - k.vel.x) * minf(1.0, a * DT)
	if adx > 3.0:
		k.facing = dir
	if k.grounded and k.jump_cd <= 0.0 and dy < -R * 1.3:
		var near := adx < D * 1.6
		var toward := k.blocked != 0.0 and k.blocked == dir
		if near or toward:
			var need := sqrt(2.0 * GRAVITY * (-dy + 8.0))
			var jv := minf(JUMP_V * k.jump_k * rng.randf_range(0.9, 1.03), need)
			k.vel.y = -jv
			if near:
				k.vel.x = clampf(dx * 3.0, -160.0, 160.0) + rng.randf_range(-30.0, 30.0)
			else:
				k.vel.x = dir * 90.0
			k.jump_cd = rng.randf_range(0.32, 0.7)
			events.append({"t": "jump", "id": k.id})


func _brake(k: Kit) -> void:
	var a := 10.0 if k.grounded else 1.2
	k.vel.x -= k.vel.x * minf(1.0, a * DT)


func _fall_asleep(k: Kit, why: String) -> void:
	k.state = SLEEP
	k.vel = Vector2.ZERO
	k.dwell = 0.0
	k.asleep_t = 0.0
	k.unsupported = 0
	k.sun_t = 0.0
	k.sleep_why = why
	events.append({"t": "sleep", "id": k.id, "why": why})


func _unwedge_near(k: Kit) -> void:
	for j: Kit in kits:
		if j.wedged and j.pos.distance_squared_to(k.pos) < (2.0 * R + 6.0) * (2.0 * R + 6.0):
			j.wedged = false


func _wake(k: Kit, why: String) -> void:
	k.wedged = false
	_unwedge_near(k)
	k.state = AWAKE
	k.idle_t = 0.0
	k.dwell = 0.0
	k.sees = false
	k.react = 0.04
	k.awake_t = 0.0
	k.prev = k.pos
	k.vel = Vector2(0, -70)
	k.unsupported = 0
	events.append({"t": "wake", "id": k.id, "why": why})


func _overlaps_old(k: Kit) -> bool:
	if old == null:
		return false
	return _dist_point_rect(k.pos, old_rect()) < R - 1.0


# ---------------------------------------------------------------- 物理

func _inv_mass(k: Kit) -> float:
	match k.state:
		SLEEP:
			return 0.0
		FALL:
			return 0.3
	return 1.0


func _broadphase() -> void:
	for k: Kit in kits:
		k.near.clear()
		var q := Rect2(k.pos.x - R - 40.0, k.pos.y - R - 40.0, 2.0 * R + 80.0, 2.0 * R + 80.0)
		for b: Block in blocks:
			if b.solid and b.r.intersects(q):
				k.near.append(b)


func _integrate(h: float) -> void:
	for k: Kit in kits:
		if k.state == SLEEP:
			continue
		k.prev = k.pos
		k.vel.y = minf(k.vel.y + GRAVITY * h, 1150.0)
		k.pos += k.vel * h
		k.grounded = false
		k.on_kit = false
		k.blocked = 0.0


func _solve() -> void:
	var has_old := old != null
	var orect := Rect2()
	if has_old:
		orect = old_rect()
	for k: Kit in kits:
		if k.state == SLEEP:
			continue
		for b in k.near:
			_circle_rect(k, b.r)
		if has_old:
			_circle_old(k, orect)
	_sort_kits()
	var n := sorted.size()
	var rr := 2.0 * R
	var rr2 := rr * rr
	for a in n:
		var ka: Kit = sorted[a]
		var sa := ka.state == SLEEP
		for b in range(a + 1, n):
			var kb: Kit = sorted[b]
			var dx := kb.pos.x - ka.pos.x
			if dx >= rr:
				break
			if sa and kb.state == SLEEP:
				continue
			var dy := kb.pos.y - ka.pos.y
			var d2 := dx * dx + dy * dy
			if d2 >= rr2:
				continue
			var d := sqrt(d2)
			var nx := 0.0
			var ny := -1.0
			if d > 0.0001:
				nx = dx / d
				ny = dy / d
			if absf(nx) < 0.2:
				# 两只猫几乎正上正下地叠着：上面那只会慢慢滑到一边（醒着的猫叠不成柱子）
				var side := signf(nx) if absf(nx) > 0.001 else (1.0 if (ka.id + kb.id) % 2 == 0 else -1.0)
				nx += side * 0.12
				var nl := sqrt(nx * nx + ny * ny)
				nx /= nl
				ny /= nl
			var pen := rr - d
			var wa := _inv_mass(ka)
			var wb := _inv_mass(kb)
			var ws := wa + wb
			if ws <= 0.0:
				continue
			var ca := pen * wa / ws
			var cb := pen * wb / ws
			ka.pos = Vector2(ka.pos.x - nx * ca, ka.pos.y - ny * ca)
			kb.pos = Vector2(kb.pos.x + nx * cb, kb.pos.y + ny * cb)
			if ny > 0.35:
				ka.grounded = true
				ka.on_kit = true
			elif ny < -0.35:
				kb.grounded = true
				kb.on_kit = true
			if nx > 0.7:
				ka.blocked = 1.0
				kb.blocked = -1.0
			elif nx < -0.7:
				ka.blocked = -1.0
				kb.blocked = 1.0


func _sort_kits() -> void:
	# 插入排序：位置帧间变化小，几乎有序
	var n := sorted.size()
	for i in range(1, n):
		var cur: Kit = sorted[i]
		var x := cur.pos.x
		var j := i - 1
		while j >= 0 and (sorted[j] as Kit).pos.x > x:
			sorted[j + 1] = sorted[j]
			j -= 1
		sorted[j + 1] = cur


func _circle_rect(k: Kit, r: Rect2) -> void:
	var px := k.pos.x
	var py := k.pos.y
	var cx := clampf(px, r.position.x, r.end.x)
	var cy := clampf(py, r.position.y, r.end.y)
	var dx := px - cx
	var dy := py - cy
	var d2 := dx * dx + dy * dy
	if d2 >= R * R:
		return
	if d2 > 0.000001:
		var d := sqrt(d2)
		var nx := dx / d
		var ny := dy / d
		var pen := R - d
		k.pos = Vector2(px + nx * pen, py + ny * pen)
		if ny < -0.5:
			k.grounded = true
		if absf(nx) > 0.7:
			k.blocked = -signf(nx)
	else:
		var l := px - r.position.x
		var rt := r.end.x - px
		var t := py - r.position.y
		var bt := r.end.y - py
		var m := minf(minf(l, rt), minf(t, bt))
		if m == t:
			k.pos.y = r.position.y - R
			k.grounded = true
		elif m == bt:
			k.pos.y = r.end.y + R
		elif m == l:
			k.pos.x = r.position.x - R
			k.blocked = 1.0
		else:
			k.pos.x = r.end.x + R
			k.blocked = -1.0


func _circle_old(k: Kit, r: Rect2) -> void:
	# 阿黄对小猫来说是一块会走的实心：在他背上可以站，挤在他身边会被推开
	if k.pos.y < r.position.y:
		var b4 := k.pos
		var v0 := k.pos - k.prev
		_circle_rect(k, r)
		var moved := k.pos - b4
		if moved.length() > 3.0:
			# 被阿黄一下子顶开或接住：只挪位置，不借这一下弹飞；撞向阿黄的那部分速度清零
			var nrm := moved.normalized()
			var vn := v0.dot(nrm)
			if vn < 0.0:
				v0 -= nrm * vn
			k.prev = k.pos - v0
		return
	if k.pos.x + R <= r.position.x or k.pos.x - R >= r.end.x:
		return
	if k.pos.y - R >= r.end.y:
		return
	var cx := r.get_center().x
	var v := k.pos.x - k.prev.x
	k.vel.x *= 0.5
	# 被阿黄挤开只是挪位置，不会被“弹飞”；往阿黄身上撞的那部分速度清零
	# （否则夹在阿黄和猫堆之间的猫，速度会一帧帧越攒越大）
	if k.pos.x < cx:
		k.pos.x = r.position.x - R
		k.blocked = 1.0
		v = minf(v, 0.0)
	else:
		k.pos.x = r.end.x + R
		k.blocked = -1.0
		v = maxf(v, 0.0)
	k.prev.x = k.pos.x - v


func _post(h: float) -> void:
	for k: Kit in kits:
		if k.state == SLEEP:
			continue
		k.vel = (k.pos - k.prev) / h
		if k.pos.y > bounds.end.y + 200.0:
			# 安全网：掉出世界就放回入口附近
			k.pos = Vector2(bounds.get_center().x, bounds.position.y + 40.0)
			k.prev = k.pos
			k.vel = Vector2.ZERO


# ---------------------------------------------------------------- 睡猫的支撑

func _sleepers_update() -> void:
	for k: Kit in kits:
		if k.state == SLEEP:
			if _supported(k):
				k.unsupported = 0
			else:
				k.unsupported += 1
				if k.unsupported >= 2:
					k.state = FALL
					k.fall_y0 = k.pos.y
					k.vel = Vector2.ZERO
					k.prev = k.pos
					k.settle = 0
					k.jam_t = 0.0
					k.jam_p = k.pos
					events.append({"t": "drop", "id": k.id})
		elif k.state == FALL:
			if k.grounded and k.vel.length() < 50.0:
				k.settle += 1
				if k.settle >= 3:
					if k.pos.y - k.fall_y0 > FALL_WAKE:
						_wake(k, "fall")
					elif _supported(k):
						k.state = SLEEP
						k.vel = Vector2.ZERO
						k.unsupported = 0
					elif k.settle >= 45 and k.vel.length() < 8.0:
						# 规则上没托住，但实际上卡稳了：就当它睡稳了
						k.state = SLEEP
						k.vel = Vector2.ZERO
						k.unsupported = 0
						k.wedged = true
			else:
				k.settle = 0
			# 卡死兜底：夹在比自己还窄的缝里（睡猫之间、阿黄和睡猫之间），一秒里几乎没挪窝，
			# 就当它卡稳了；掉得够高的照样摔醒
			if k.state == FALL:
				k.jam_t += DT
				if k.jam_t >= 1.0:
					if k.pos.distance_to(k.jam_p) < 2.0:
						if k.pos.y - k.fall_y0 > FALL_WAKE:
							_wake(k, "fall")
						else:
							k.state = SLEEP
							k.vel = Vector2.ZERO
							k.prev = k.pos
							k.unsupported = 0
							k.wedged = true
					k.jam_t = 0.0
					k.jam_p = k.pos


func _supported(k: Kit) -> bool:
	if k.wedged:
		return true
	var tol := 3.0
	var left := false
	var right := false
	var p := k.pos
	for b: Block in blocks:
		if not b.solid:
			continue
		var r: Rect2 = b.r
		if p.x < r.position.x - R - tol or p.x > r.end.x + R + tol:
			continue
		if p.y < r.position.y - R - tol or p.y > r.end.y + R + tol:
			continue
		var cx := clampf(p.x, r.position.x, r.end.x)
		var cy := clampf(p.y, r.position.y, r.end.y)
		var dx := cx - p.x
		var dy := cy - p.y
		var d := sqrt(dx * dx + dy * dy)
		if d > R + tol:
			continue
		if d < 0.001:
			return true
		# 顶面中间：稳稳托住；台角：像托在另一只猫上一样，偏了就会滚下去
		var on_face := cx > r.position.x + 0.5 and cx < r.end.x - 0.5
		if dy / d >= (0.64 if on_face else 0.97):
			return true
		if dy >= -0.2 * d:
			if dx < 0.0:
				left = true
			else:
				right = true
	if old != null:
		var r2 := old_rect()
		var cx2 := clampf(p.x, r2.position.x, r2.end.x)
		var cy2 := clampf(p.y, r2.position.y, r2.end.y)
		var dx2 := cx2 - p.x
		var dy2 := cy2 - p.y
		var d2 := sqrt(dx2 * dx2 + dy2 * dy2)
		if d2 <= R + tol:
			if d2 < 0.001 or dy2 / d2 >= 0.64:
				return true
			if dy2 >= -0.2 * d2:
				if dx2 < 0.0:
					left = true
				else:
					right = true
	var lim := 2.0 * R + tol
	for j: Kit in kits:
		# 只有睡着的猫才是“实心”的；醒着的、正在掉的、炸毛的都托不住
		if j == k or j.state != SLEEP:
			continue
		var dx3: float = j.pos.x - p.x
		if dx3 > lim or dx3 < -lim:
			continue
		var dy3: float = j.pos.y - p.y
		if dy3 > lim or dy3 < -lim:
			continue
		var d3 := sqrt(dx3 * dx3 + dy3 * dy3)
		if d3 > lim:
			continue
		if d3 < 0.001:
			return true
		if dy3 / d3 >= 0.97:
			return true
		if dy3 >= -0.2 * d3:
			if dx3 < 0.0:
				left = true
			else:
				right = true
	return left and right


# ---------------------------------------------------------------- 阿黄

func old_rect() -> Rect2:
	return Rect2(old.pos.x - AH_W * 0.5, old.pos.y - AH_H, AH_W, AH_H)


func surface_at(x: float, min_y: float, kits_too: bool = true, allow_cold: bool = true) -> float:
	var best := INF
	for b: Block in blocks:
		if not b.solid:
			continue
		if b.cold and not allow_cold:
			continue
		var r: Rect2 = b.r
		if x < r.position.x or x > r.end.x:
			continue
		var y := r.position.y
		if y >= min_y and y < best:
			best = y
	if kits_too:
		for k: Kit in kits:
			if k.state != SLEEP:
				continue
			var dx: float = x - k.pos.x
			if dx <= -R or dx >= R:
				continue
			var y2: float = k.pos.y - sqrt(R * R - dx * dx)
			if y2 >= min_y and y2 < best:
				best = y2
	return best


func _ground(x: float, min_y: float, allow_cold: bool = true, climb_ref: float = INF) -> float:
	var hw := AH_W * 0.5 - 4.0
	return span_surface(x - hw, x + hw, min_y, allow_cold, climb_ref)


func span_surface(x0: float, x1: float, min_y: float, allow_cold: bool = true, climb_ref: float = INF) -> float:
	# 一段横向范围内、不高于 min_y 的最高支撑面（家具顶面，或睡猫在这段范围内的最高点）
	var best := INF
	for b: Block in blocks:
		if not b.solid:
			continue
		if b.cold and not allow_cold:
			continue
		var r: Rect2 = b.r
		if x1 < r.position.x or x0 > r.end.x:
			continue
		var y := r.position.y
		if y >= min_y and y < best:
			best = y
	for k: Kit in kits:
		if k.state != SLEEP:
			continue
		var cx: float = k.pos.x
		if cx + R <= x0 or cx - R >= x1:
			continue
		var xs := clampf(cx, x0, x1)
		var dx := xs - cx
		var y2: float = k.pos.y - sqrt(maxf(R * R - dx * dx, 0.0))
		# 往上迈时只能踩在猫背顶上，圆滚滚的侧面勾不住
		if climb_ref < INF and absf(dx) > CAP and y2 < climb_ref - 4.0:
			continue
		if y2 >= min_y and y2 < best:
			best = y2
	return best


func _box_hit(box: Rect2, reach_y: float = INF, front_x: float = 0.0, dir: float = 0.0) -> bool:
	for b: Block in blocks:
		if b.solid and b.r.intersects(box):
			last_hit = "block %s %s box=%s" % [b.kind, b.r, box]
			last_hit_kit = -1
			return true
	var back_top := INF
	var back_x := 0.0
	if old != null:
		back_top = old.pos.y - AH_H
		back_x = old.pos.x
	for k: Kit in kits:
		if k.state == SLEEP and _circle_box(k.pos, R - 1.5, box):
			# 睡在阿黄背上的猫不算挡路：他一走，它们自己会滑下来
			if k.pos.y + R <= back_top + 5.0 and absf(k.pos.x - back_x) < AH_W * 0.5 + R * 0.6:
				continue
			# 正前方、一步够得着的猫：那是下一级台阶，不是墙
			if dir != 0.0 and k.pos.y - R >= reach_y and (k.pos.x - front_x) * dir > 0.0:
				continue
			last_hit = "kit %d %s box=%s" % [k.id, k.pos, box]
			last_hit_kit = k.id
			return true
	return false


func _circle_box(c: Vector2, rad: float, box: Rect2) -> bool:
	var cx := clampf(c.x, box.position.x, box.end.x)
	var cy := clampf(c.y, box.position.y, box.end.y)
	var dx := c.x - cx
	var dy := c.y - cy
	return dx * dx + dy * dy < rad * rad


func _walk_box(x: float, feet: float, dir: float) -> Rect2:
	# 身体比脚踩的范围略窄：下台阶时不会被身后的台角卡住，上台阶时脚先够到猫背顶
	return Rect2(x - AH_W * 0.5 + 9.0, feet - AH_H, AH_W - 18.0, AH_H - 4.0)


func _paw_strip(x: float, feet: float, dir: float) -> Rect2:
	# 往上迈时，前爪正上方要有空间：直上直下的猫柱子迈不上去
	var fx := x + dir * (AH_W * 0.5 - 4.0)
	return Rect2(minf(fx, fx - dir * 10.0), feet - AH_H, 10.0, AH_H - 4.0)


func _old_kick(k: Kit) -> void:
	var o := old
	if o.mode == O_GOAL:
		return
	if absf(k.pos.x - o.pos.x) > AH_W * 0.5 + R * 0.6:
		return
	var depth := k.pos.y - o.pos.y
	if depth < -R * 0.6 or depth > D * 5.0:
		return
	o.launch_n += 1
	if o.launch_t < 0.0:
		# 等连锁传完一小会儿再一起发力：身下受惊的猫越多，弹得越高
		o.launch_t = 0.22
		o.launch_y0 = o.pos.y


func _old_update() -> void:
	var o := old
	if o.mode == O_GOAL:
		return
	if o.launch_t >= 0.0:
		o.launch_t -= DT
		if o.launch_t < 0.0 and o.launch_n > 0:
			var v := minf(TRAMP_BASE + TRAMP_PER * float(o.launch_n), TRAMP_MAX)
			# 等发力的这一小会儿里阿黄已经往下掉了一点：补上，弹的高度从他原来站的地方算
			var sag := maxf(0.0, o.pos.y - o.launch_y0)
			v = sqrt(v * v + 2.0 * GRAVITY * sag)
			if o.mode == O_AIR:
				o.vel.y = minf(o.vel.y, -v)
			else:
				o.vel.y = -v
				o.air_t = 0.0
				o.launch_peak = o.pos.y
			o.vel.x = o.dir * TRAMP_VX
			o.last_launch_v = v
			o.mode = O_AIR
			events.append({"t": "launch", "v": v, "n": o.launch_n})
			o.launch_n = 0
	if o.mode == O_AIR:
		o.air_t += DT
		o.vel.y = minf(o.vel.y + GRAVITY * DT, 1100.0)
		var nx := o.pos.x + o.vel.x * DT
		if absf(o.vel.x) > 0.01:
			var hb := Rect2(nx - AH_W * 0.5 + 3.0, o.pos.y - AH_H, AH_W - 6.0, AH_H - 3.0)
			if not _box_hit(hb):
				o.pos.x = nx
		var ny := o.pos.y + o.vel.y * DT
		if o.vel.y < 0.0:
			var cb := Rect2(o.pos.x - AH_W * 0.5 + 10.0, ny - AH_H, AH_W - 20.0, 6.0)
			if _box_hit(cb):
				o.vel.y = 0.0
			else:
				o.pos.y = ny
			o.launch_peak = minf(o.launch_peak, o.pos.y)
		else:
			var g := _ground(o.pos.x, o.pos.y - 1.0)
			if ny >= g:
				o.pos.y = g
				o.vel = Vector2.ZERO
				o.mode = O_WALK
				events.append({"t": "land", "air": o.air_t})
			else:
				o.pos.y = ny
		return
	# 站着：脚下的东西还在吗？
	var gh := _ground(o.pos.x, o.pos.y - 2.0)
	if gh > o.pos.y + AH_STEP_DOWN:
		o.mode = O_AIR
		o.vel = Vector2.ZERO
		o.air_t = 0.0
		o.launch_peak = o.pos.y
		events.append({"t": "old_fall"})
		return
	if gh > o.pos.y:
		o.pos.y = gh
	# 他怕吵：只要还有小猫醒着、在闹，他就坐着等
	if commotion():
		if o.mode != O_WAIT:
			events.append({"t": "old_wait"})
		o.mode = O_WAIT
		o.why = "noisy"
		o.wait_t += DT
		_old_footing()
		return
	# 他怕凉：已经在冰凉地面上才肯在上面走，否则把地面当成走不过去的沟
	o.on_cold = _ground(o.pos.x, o.pos.y - 2.0, false) > o.pos.y + 1.0
	var nx2 := o.pos.x + o.dir * AH_SPEED * DT
	var g2 := _ground(nx2, o.pos.y - AH_STEP_UP, o.on_cold, o.pos.y)
	# 前爪能够到的一小段：跨得过猫与家具之间的小缝，跨不过真正的沟
	var fx := nx2 + o.dir * (AH_W * 0.5 - 4.0)
	var fa := fx - o.dir * 16.0
	var fb := fx + o.dir * 10.0
	var front := span_surface(minf(fa, fb), maxf(fa, fb), o.pos.y - AH_STEP_UP, o.on_cold)
	# 往下走楼梯：身子底下一步够得着、前面还连着往下的台阶，也算能走
	if front > o.pos.y + AH_STEP_DOWN and front <= o.pos.y + AH_STEP_DOWN * 2.0:
		var wa := fx - o.dir * 30.0
		var near := span_surface(minf(wa, fb), maxf(wa, fb), o.pos.y - AH_STEP_UP, o.on_cold)
		if near <= o.pos.y + AH_STEP_DOWN:
			front = near
	var ok := true
	if g2 == INF or front > o.pos.y + AH_STEP_DOWN:
		ok = false
		o.why = "drop"
		if not o.on_cold:
			var fc := span_surface(minf(fa, fb), maxf(fa, fb), o.pos.y - AH_STEP_UP, true)
			if fc <= o.pos.y + AH_STEP_DOWN:
				o.why = "cold"
	elif _box_hit(_walk_box(nx2, g2, o.dir), o.pos.y - AH_STEP_UP, nx2 + o.dir * (AH_W * 0.5 - 9.0), o.dir):
		ok = false
		o.why = "high"
	elif g2 < o.pos.y - 4.0 and _box_hit(_paw_strip(nx2, g2, o.dir), o.pos.y - AH_STEP_UP, nx2 + o.dir * (AH_W * 0.5 - 4.0), o.dir):
		ok = false
		o.why = "high"
	if ok:
		if g2 < o.pos.y - 4.0:
			o.steps_up += 1
			events.append({"t": "step_up", "h": o.pos.y - g2})
		o.pos.x = nx2
		o.pos.y = g2
		if o.mode != O_WALK:
			events.append({"t": "old_go"})
		o.mode = O_WALK
		o.walk_t += DT
		o.wait_t = 0.0
		o.why = ""
	else:
		if o.mode != O_WAIT:
			events.append({"t": "old_wait"})
		o.mode = O_WAIT
		o.wait_t += DT
	_old_footing()


func _old_footing() -> void:
	# 记录脚下踩着什么（供“猫桥/猫阶”等发现判断）
	var o := old
	o.under.clear()
	o.on_kit = false
	var hw := AH_W * 0.5 - 3.0
	for k: Kit in kits:
		if k.state != SLEEP:
			continue
		if absf(k.pos.x - o.pos.x) > hw + R * 0.7:
			continue
		var top := k.pos.y - R
		if absf(top - o.pos.y) < 7.0:
			o.under.append(k.id)
			o.on_kit = true
			if not k.carried or k.carried_at.distance_to(k.pos) > D * 4.0:
				if k.carried and k.carried_at.distance_to(k.pos) > D * 4.0:
					events.append({"t": "reuse", "id": k.id})
				k.carried = true
				k.carried_at = k.pos
	var furniture := surface_at(o.pos.x, o.pos.y - 1.0, false)
	o.over_gap = o.on_kit and furniture - o.pos.y > D * 1.4


func _goal_update() -> void:
	var o := old
	if o.mode == O_GOAL or o.mode == O_AIR:
		return
	if goal.has_point(o.pos - Vector2(0, 3)):
		o.mode = O_GOAL
		won = true
		events.append({"t": "goal"})


# ---------------------------------------------------------------- 统计与快照

func commotion() -> bool:
	for k: Kit in kits:
		if k.state == AWAKE or k.state == SPOOK:
			return true
	return false


func count_states() -> Array:
	var c := [0, 0, 0, 0]
	for k: Kit in kits:
		c[k.state] += 1
	return c


func all_quiet() -> bool:
	for k: Kit in kits:
		if k.state != SLEEP:
			return false
		if k.spook_pend >= 0.0:
			return false
	return old == null or old.mode != O_AIR


func snapshot() -> Dictionary:
	var ks := []
	for k: Kit in kits:
		ks.append({
			"id": k.id, "pos": k.pos, "vel": k.vel, "state": k.state, "facing": k.facing,
			"sleep_delay": k.sleep_delay, "speed_k": k.speed_k, "jump_k": k.jump_k, "coat": k.coat,
			"seed": k.seed, "carried": k.carried, "carried_at": k.carried_at, "asleep_t": k.asleep_t,
		})
	var o := {}
	if old != null:
		o = {"pos": old.pos, "vel": old.vel, "dir": old.dir, "mode": old.mode, "steps_up": old.steps_up}
	var sp := []
	for s in spawners:
		var bl: Block = s["block"]
		sp.append({"open": s["open"], "left": s["left"], "t": s["t"], "solid": bl.solid, "sight": bl.sight, "kind": bl.kind})
	return {"kits": ks, "old": o, "sp": sp, "time": time, "frame": frame, "next_id": next_id,
		"rng": rng.state, "won": won}


func restore(s: Dictionary) -> void:
	kits.clear()
	sorted.clear()
	for d in s["kits"]:
		var k := Kit.new()
		k.id = d["id"]
		k.pos = d["pos"]
		k.prev = d["pos"]
		k.vel = d["vel"]
		k.state = d["state"]
		if k.state == FALL or k.state == SPOOK:
			k.state = AWAKE
		k.facing = d["facing"]
		k.sleep_delay = d["sleep_delay"]
		k.speed_k = d["speed_k"]
		k.jump_k = d["jump_k"]
		k.coat = d["coat"]
		k.seed = d["seed"]
		k.carried = d["carried"]
		k.carried_at = d["carried_at"]
		k.asleep_t = d["asleep_t"]
		kits.append(k)
		sorted.append(k)
	if old != null and not s["old"].is_empty():
		var o: Dictionary = s["old"]
		old.pos = o["pos"]
		old.vel = o["vel"]
		old.dir = o["dir"]
		old.mode = o["mode"]
		old.steps_up = o["steps_up"]
		old.launch_n = 0
		old.launch_t = -1.0
	for i in spawners.size():
		var sd: Dictionary = s["sp"][i]
		var sp: Dictionary = spawners[i]
		sp["open"] = sd["open"]
		sp["left"] = sd["left"]
		sp["t"] = sd["t"]
		var bl: Block = sp["block"]
		bl.solid = sd["solid"]
		bl.sight = sd["sight"]
		bl.kind = sd["kind"]
	time = s["time"]
	frame = s["frame"]
	next_id = s["next_id"]
	rng.state = s["rng"]
	won = s["won"]
