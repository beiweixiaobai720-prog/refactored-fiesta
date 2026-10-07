class_name Medium
extends RefCounted
## 活膜：可激发介质。
##
## 全部规则只有三条：
##   静 —— 可以被点亮（被玩家踩，或邻格正亮着）。
##   亮 —— 持续 EXC 秒，是实心的，可以站人；点亮后把邻格排进队列。
##   倦 —— 亮过之后的 REF 秒内不能再被点亮，之后回到"静"。
##
## 用事件队列按连续时间传播（不是固定节拍），邻域包含 16 个方向并使用
## 真实距离作延迟，所以波纹是圆的、速度均匀，而且完全确定可复现。

signal cell_excited(idx: int, t: float)

const W := 64
const H := 36
const CELL := 20.0

const SPEED := 9.0          # 波速：格/秒
const EXC := 0.26           # "亮"持续时间（秒）
const REF := 1.1            # "倦"持续时间（秒）
const NEVER := -1.0e9
const INF := 1.0e9

enum { EMPTY, WALL, MED, SPIKE, GATE, DAM, SPIKE_DOWN }

var kind := PackedByteArray()
var t_exc := PackedFloat32Array()   # 上次点亮的时刻
var t_pend := PackedFloat32Array()  # 已排队、将要点亮的最早时刻
var pdir := PackedByteArray()       # 被谁点亮：(dx+1)*3+(dy+1)，4 = 无来源（被踩/起搏）
var now := 0.0

var pacers: Array = []              # [{idx, period, next}]

# 最小堆（并行数组）
var _ht := PackedFloat32Array()
var _hc := PackedInt32Array()
var _hp := PackedInt32Array()
var _hn := 0

# 邻域：[dx, dy, 延迟, 需要为介质的中间格...]
var _nb: Array = []


func _init() -> void:
	kind.resize(W * H)
	t_exc.resize(W * H)
	t_pend.resize(W * H)
	pdir.resize(W * H)
	reset_state()
	var s2 := sqrt(2.0)
	var s5 := sqrt(5.0)
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		_nb.append([d[0], d[1], 1.0 / SPEED, []])
	for d in [[1, 1], [1, -1], [-1, 1], [-1, -1]]:
		# 对角：两条直边至少一条通，才能斜着穿过去（不会从两堵墙的角缝漏过去）
		_nb.append([d[0], d[1], s2 / SPEED, [[d[0], 0], [0, d[1]]], true])
	for d in [[2, 1], [2, -1], [-2, 1], [-2, -1], [1, 2], [1, -2], [-1, 2], [-1, -2]]:
		# 马步：路径上的两格都必须是介质，避免穿墙
		var a := [signi(d[0]) if absi(d[0]) == 2 else 0, signi(d[1]) if absi(d[1]) == 2 else 0]
		var b := [signi(d[0]), signi(d[1])]
		_nb.append([d[0], d[1], s5 / SPEED, [a, b], false])


func reset_state() -> void:
	now = 0.0
	for i in W * H:
		t_exc[i] = NEVER
		t_pend[i] = INF
		pdir[i] = 4
	_hn = 0
	_ht.resize(0)
	_hc.resize(0)
	_hp.resize(0)
	for p in pacers:
		p.next = p.first


func idx(x: int, y: int) -> int:
	return y * W + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H


func is_med_xy(x: int, y: int) -> bool:
	return in_bounds(x, y) and kind[y * W + x] == MED


func is_excited(i: int) -> bool:
	return kind[i] == MED and now - t_exc[i] < EXC


func is_rest(i: int, t: float) -> bool:
	return t - t_exc[i] >= EXC + REF


func is_solid(x: int, y: int) -> bool:
	if x < 0 or x >= W:
		return true
	if y < 0 or y >= H:
		return false
	var k := kind[y * W + x]
	if k == WALL or k == GATE or k == DAM:
		return true
	if k == MED:
		return now - t_exc[y * W + x] < EXC
	return false


func is_static_solid(x: int, y: int) -> bool:
	if x < 0 or x >= W:
		return true
	if y < 0 or y >= H:
		return false
	var k := kind[y * W + x]
	return k == WALL or k == GATE or k == DAM


## 立即点亮一格（踩、起搏器）。成功返回 true。
func stimulate(i: int) -> bool:
	if kind[i] != MED or not is_rest(i, now):
		return false
	_excite(i, now, -1)
	return true


func add_pacer(i: int, period: float, first: float) -> void:
	pacers.append({"idx": i, "period": period, "first": first, "next": first})


func step(dt: float) -> void:
	var target := now + dt
	# 起搏器与事件都按时间顺序推进
	while true:
		var next_ev := _ht[0] if _hn > 0 else INF
		var next_pace := INF
		var pace_i := -1
		for k in pacers.size():
			if pacers[k].next < next_pace:
				next_pace = pacers[k].next
				pace_i = k
		var t := minf(next_ev, next_pace)
		if t > target:
			break
		now = t
		if next_pace <= next_ev:
			var p: Dictionary = pacers[pace_i]
			p.next += p.period
			if kind[p.idx] == MED and is_rest(p.idx, t):
				_excite(p.idx, t, -1)
		else:
			var c := _hc[0]
			var par := _hp[0]
			_pop()
			if t_pend[c] <= t:
				t_pend[c] = INF
			if kind[c] == MED and is_rest(c, t):
				_excite(c, t, par)
	now = target


func _excite(c: int, t: float, parent: int) -> void:
	t_exc[c] = t
	t_pend[c] = INF
	var cx := c % W
	var cy := c / W
	if parent >= 0:
		var dx := signi(cx - parent % W)
		var dy := signi(cy - parent / W)
		pdir[c] = (dx + 1) * 3 + (dy + 1)
	else:
		pdir[c] = 4
	for nb in _nb:
		var nx: int = cx + nb[0]
		var ny: int = cy + nb[1]
		if not is_med_xy(nx, ny):
			continue
		var reqs: Array = nb[3]
		if reqs.size() > 0:
			var any_ok: bool = nb[4]
			var ok := not any_ok
			for r in reqs:
				var m := is_med_xy(cx + r[0], cy + r[1])
				if any_ok and m:
					ok = true
				elif not any_ok and not m:
					ok = false
			if not ok:
				continue
		var n := ny * W + nx
		var tn: float = t + nb[2]
		if tn < t_pend[n] and is_rest(n, tn):
			t_pend[n] = tn
			_push(tn, n, c)
	cell_excited.emit(c, t)


## 把某格变成介质（坝被打开）。
func open_dam(i: int) -> void:
	kind[i] = MED
	t_exc[i] = NEVER


## 打包给着色器：R = 年龄（负数=即将点亮），G = 是否介质，B = 来源方向（调试用）。
func pack_texture_data(out: PackedFloat32Array) -> void:
	var lim := EXC + REF + 0.4
	for i in W * H:
		var o := i * 4
		if kind[i] == MED:
			var age := now - t_exc[i]
			if age > lim:
				age = 99.0
				if t_pend[i] < INF:
					age = now - t_pend[i]
			out[o] = age
			out[o + 1] = 1.0
		else:
			out[o] = 99.0
			out[o + 1] = 0.0
		out[o + 2] = 0.0
		out[o + 3] = 1.0


# ---------------- 堆 ----------------
func _push(t: float, c: int, p: int) -> void:
	if _hn >= _ht.size():
		var ns := maxi(64, _ht.size() * 2)
		_ht.resize(ns)
		_hc.resize(ns)
		_hp.resize(ns)
	var i := _hn
	_hn += 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _ht[parent] <= t:
			break
		_ht[i] = _ht[parent]
		_hc[i] = _hc[parent]
		_hp[i] = _hp[parent]
		i = parent
	_ht[i] = t
	_hc[i] = c
	_hp[i] = p


func _pop() -> void:
	_hn -= 1
	if _hn <= 0:
		_hn = 0
		return
	var t := _ht[_hn]
	var c := _hc[_hn]
	var p := _hp[_hn]
	var i := 0
	while true:
		var l := i * 2 + 1
		if l >= _hn:
			break
		var r := l + 1
		var m := l
		if r < _hn and _ht[r] < _ht[l]:
			m = r
		if _ht[m] >= t:
			break
		_ht[i] = _ht[m]
		_hc[i] = _hc[m]
		_hp[i] = _hp[m]
		i = m
	_ht[i] = t
	_hc[i] = c
	_hp[i] = p
