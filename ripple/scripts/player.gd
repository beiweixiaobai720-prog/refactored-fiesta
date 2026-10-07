class_name Player
extends Node2D
## 玩家：一个发光的小长方形。
## 碰撞全部基于格子：墙、关闭的门/坝、以及"正亮着"的活膜格是实心的。

signal jumped
signal landed(impact: float)
signal stomped(hit_medium: bool)

const HW := 6.0             # 半宽
const HH := 11.0            # 半高
const RUN := 190.0
const ACC_GROUND := 2600.0
const ACC_AIR := 1700.0
const GRAVITY := 1500.0
const JUMP_V := 505.0
const MAX_FALL := 720.0
const COYOTE := 0.11
const JUMP_BUFFER := 0.12
const STOMP_CD := 0.18

var medium: Medium
var vel := Vector2.ZERO
var on_ground := false
var carried := 0.0          # >0：正被波托着（计时）
var coyote := 0.0
var jump_buf := 0.0
var stomp_cd := 0.0
var facing := 1
var dead := false
var alive_time := 0.0

# 视觉
var draw_pos := Vector2.ZERO
var squash := Vector2.ONE
var trail: Array = []
var stomp_flash := 0.0
var color := Color(1.0, 0.86, 0.52)


func setup(m: Medium, start: Vector2) -> void:
	medium = m
	position = start
	draw_pos = start
	vel = Vector2.ZERO
	dead = false
	trail.clear()


func rect_at(p: Vector2) -> Rect2:
	return Rect2(p.x - HW, p.y - HH, HW * 2.0, HH * 2.0)


func _cells_in(r: Rect2) -> Array:
	var out := []
	var C := Medium.CELL
	var x0 := int(floor((r.position.x + 0.01) / C))
	var x1 := int(floor((r.end.x - 0.01) / C))
	var y0 := int(floor((r.position.y + 0.01) / C))
	var y1 := int(floor((r.end.y - 0.01) / C))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			out.append(Vector2i(x, y))
	return out


func _solid_cells(r: Rect2, static_only := false) -> Array:
	var out := []
	for c in _cells_in(r):
		var s := medium.is_static_solid(c.x, c.y) if static_only else medium.is_solid(c.x, c.y)
		if s:
			out.append(c)
	return out


## 被新亮起的波格挤到时，顺着波的方向把玩家推出去。
func resolve_wave_push() -> void:
	var r := rect_at(position)
	var over := []
	for c in _cells_in(r):
		if medium.in_bounds(c.x, c.y):
			var i: int = medium.idx(c.x, c.y)
			if medium.kind[i] == Medium.MED and medium.is_excited(i):
				over.append(c)
	if over.is_empty():
		return
	var sum := Vector2.ZERO
	for c in over:
		var d: int = medium.pdir[medium.idx(c.x, c.y)]
		sum += Vector2(d / 3 - 1, d % 3 - 1)
	var C := Medium.CELL
	var target := position
	if absf(sum.x) > absf(sum.y) * 1.2:
		# 横向推
		if sum.x > 0:
			target.x = (_max_x(over) + 1) * C + HW + 0.01
		else:
			target.x = _min_x(over) * C - HW - 0.01
	elif sum.y > 0.5:
		return   # 向下走的波从玩家身上穿过去，不拖人
	else:
		# 向上托（包括原地被踩亮）
		var top := INF
		for c in over:
			top = minf(top, c.y * C)
		target.y = top - HH - 0.01
	# 推完之后不能嵌进墙里；嵌进别的亮格就再推一次
	for _k in 4:
		var r2 := rect_at(target)
		if not _solid_cells(r2, true).is_empty():
			return
		var more := _solid_cells(r2)
		if more.is_empty():
			break
		if target.y < position.y:
			var top2 := INF
			for c in more:
				top2 = minf(top2, c.y * C)
			target.y = top2 - HH - 0.01
		elif target.x > position.x:
			target.x = (_max_x(more) + 1) * C + HW + 0.01
		else:
			target.x = _min_x(more) * C - HW - 0.01
	if not _solid_cells(rect_at(target)).is_empty():
		return
	var moved := target - position
	position = target
	if moved.y < -0.1:
		vel.y = minf(vel.y, -Medium.SPEED * C * 0.95)
		carried = 0.16
		on_ground = true
		coyote = COYOTE
	elif absf(moved.x) > 0.1:
		vel.x = signf(moved.x) * Medium.SPEED * C


func _max_x(cells: Array) -> int:
	var m := -999
	for c in cells:
		m = maxi(m, c.x)
	return m


func _min_x(cells: Array) -> int:
	var m := 999
	for c in cells:
		m = mini(m, c.x)
	return m


## 沿某轴移动，只被"前缘新碰到"的实心格阻挡。返回是否撞到。
func _sweep(axis: int, amount: float) -> bool:
	if absf(amount) < 0.0001:
		return false
	var C := Medium.CELL
	var start_cells := {}
	for c in _solid_cells(rect_at(position)):
		start_cells[c] = true
	var remaining := amount
	var sgn := signf(amount)
	while absf(remaining) > 0.0001:
		var stepv := sgn * minf(absf(remaining), 4.0)
		var np := position
		np[axis] += stepv
		var hits := []
		for c in _solid_cells(rect_at(np)):
			if not start_cells.has(c):
				hits.append(c)
		if not hits.is_empty():
			if axis == 1:
				if sgn > 0:
					var row := 9999
					for c in hits:
						row = mini(row, c.y)
					position.y = minf(np.y, row * C - HH - 0.001)
				else:
					var row2 := -9999
					for c in hits:
						row2 = maxi(row2, c.y)
					position.y = maxf(np.y, (row2 + 1) * C + HH + 0.001)
			else:
				if sgn > 0:
					var col := 9999
					for c in hits:
						col = mini(col, c.x)
					position.x = minf(np.x, col * C - HW - 0.001)
				else:
					var col2 := -9999
					for c in hits:
						col2 = maxi(col2, c.x)
					position.x = maxf(np.x, (col2 + 1) * C + HW + 0.001)
			return true
		position = np
		remaining -= stepv
	return false


func _ground_below(static_only := false) -> bool:
	var here := {}
	for c in _solid_cells(rect_at(position), static_only):
		here[c] = true
	for c in _solid_cells(rect_at(position + Vector2(0, 1.5)), static_only):
		if not here.has(c):
			return true
	return false


func physics(dt: float, inp: Dictionary) -> void:
	if dead:
		return
	alive_time += dt
	stomp_cd = maxf(0.0, stomp_cd - dt)
	carried = maxf(0.0, carried - dt)
	jump_buf = maxf(0.0, jump_buf - dt)
	stomp_flash = maxf(0.0, stomp_flash - dt * 4.0)

	var was_ground := on_ground
	on_ground = _ground_below() or carried > 0.0
	if on_ground:
		coyote = COYOTE
	else:
		coyote = maxf(0.0, coyote - dt)

	# 水平
	var ix: float = inp.get("x", 0.0)
	if ix != 0.0:
		facing = int(signf(ix))
	var acc := ACC_GROUND if on_ground else ACC_AIR
	var target_vx := ix * RUN
	vel.x = move_toward(vel.x, target_vx, acc * dt)

	# 跳
	if inp.get("jump", false):
		jump_buf = JUMP_BUFFER
	if jump_buf > 0.0 and coyote > 0.0:
		var boost := 0.0
		if carried > 0.0:
			boost = Medium.SPEED * Medium.CELL * 0.55
		vel.y = -JUMP_V - boost
		jump_buf = 0.0
		coyote = 0.0
		carried = 0.0
		on_ground = false
		squash = Vector2(0.7, 1.35)
		jumped.emit()
	if not inp.get("jump_held", false) and vel.y < -180.0 and carried <= 0.0:
		vel.y += GRAVITY * dt * 1.6   # 松开跳键，跳得更低

	# 踩：只能踩在实地上（墙、门、坝）；站在波上踩不出新的波
	if inp.get("stomp", false) and stomp_cd <= 0.0 and _ground_below(true):
		stomp_cd = STOMP_CD
		var hit := _do_stomp()
		stomp_flash = 1.0
		squash = Vector2(1.35, 0.7)
		stomped.emit(hit)

	vel.y = minf(vel.y + GRAVITY * dt, MAX_FALL)

	var vy_before := vel.y
	if _sweep(0, vel.x * dt):
		vel.x = 0.0
	if _sweep(1, vel.y * dt):
		if vel.y > 0.0 and not was_ground and vy_before > 200.0:
			squash = Vector2(1.0 + vy_before / 2000.0, 1.0 - vy_before / 2600.0)
			landed.emit(vy_before)
		vel.y = 0.0


func _do_stomp() -> bool:
	var C := Medium.CELL
	var feet := position + Vector2(0, HH)
	var hit := false
	# 脚下所在行与左右各一格
	var area := Rect2(feet.x - HW - C * 0.6, feet.y - C * 0.9, HW * 2.0 + C * 1.2, C * 0.85)
	for c in _cells_in(area):
		if medium.in_bounds(c.x, c.y):
			var i: int = medium.idx(c.x, c.y)
			if medium.stimulate(i):
				hit = true
	return hit


func update_visual(dt: float) -> void:
	draw_pos = draw_pos.lerp(position, 1.0 - exp(-dt * 28.0))
	if draw_pos.distance_to(position) > 60.0:
		draw_pos = position
	squash = squash.lerp(Vector2.ONE, 1.0 - exp(-dt * 12.0))
	trail.push_front(draw_pos)
	if trail.size() > 8:
		trail.pop_back()
	queue_redraw()


func _draw() -> void:
	if dead:
		return
	var off := draw_pos - position
	# 拖影
	for k in range(trail.size() - 1, 0, -1):
		var tp: Vector2 = trail[k] - position
		var a := 0.12 * (1.0 - float(k) / trail.size())
		if carried > 0.0 or absf(vel.y) > 300.0:
			a *= 2.0
		draw_rect(Rect2(tp.x - HW, tp.y - HH, HW * 2, HH * 2), Color(color, a))
	var sz := Vector2(HW * 2.0 * squash.x, HH * 2.0 * squash.y)
	var bottom := off + Vector2(0, HH)
	var r := Rect2(bottom.x - sz.x * 0.5, bottom.y - sz.y, sz.x, sz.y)
	# 光晕
	for k in 4:
		var g := 3.0 + k * 3.5
		draw_rect(r.grow(g), Color(color.r, color.g * 0.9, color.b * 0.7, 0.07 - k * 0.012))
	draw_rect(r, color)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(1, 1, 0.95))
	# 眼睛缝
	var ey := r.position.y + r.size.y * 0.3
	var ex := r.get_center().x + facing * 1.5
	draw_rect(Rect2(ex - 3, ey, 6, 2), Color(0.12, 0.08, 0.2, 0.85))
	if stomp_flash > 0.0:
		draw_rect(r.grow(2), Color(1, 1, 1, stomp_flash * 0.6), false, 2.0)
