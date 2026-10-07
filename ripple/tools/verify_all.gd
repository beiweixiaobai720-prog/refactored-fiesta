extends SceneTree
## 一键回归：godot --headless --path . -s tools/verify_all.gd
## 1) 活膜的基本性质（波速、对撞湮灭）
## 2) tools/solutions/ 里每一关的通关回放都能 WIN
## 3) 关卡依赖的涌现现象：第 7、9 关"在错的地方踩"不会形成回环，"在对的地方踩"会一直跳

var fails := 0


func _init() -> void:
	_check_medium()
	_check_solutions()
	_check_rotor(7, [[0.1, "R"], [0.75, "N"], [2.2, "S"]], [[0.1, "R"], [0.75, "N"], [2.0, "R"], [3.7, "N"], [3.8, "S"]], Vector2i(20, 28))
	_check_rotor(9, [[0.1, "R"], [1.0, "N"], [2.5, "S"]], [[0.1, "R"], [1.0, "N"], [2.5, "R"], [3.6, "N"], [4.0, "S"]], Vector2i(30, 20))
	_check_rotor(8, [], [[0.1, "R"], [1.2, "N"], [3.0, "S"]], Vector2i(12, 14))
	print("\n%s  (%d 项失败)" % ["全部通过" if fails == 0 else "有失败", fails])
	quit(1 if fails > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func _check_medium() -> void:
	print("活膜：")
	var m := Medium.new()
	for i in Medium.W * Medium.H:
		m.kind[i] = Medium.MED
	m.reset_state()
	m.stimulate(m.idx(32, 18))
	m.step(1.0)
	var rmax := 0.0
	for y in Medium.H:
		for x in Medium.W:
			if m.is_excited(m.idx(x, y)):
				rmax = maxf(rmax, Vector2(x - 32, y - 18).length())
	_ok(absf(rmax - Medium.SPEED) < 1.0, "1 秒后波前半径≈%.0f 格（实测 %.1f）" % [Medium.SPEED, rmax])
	m.reset_state()
	m.stimulate(m.idx(10, 18))
	m.stimulate(m.idx(50, 18))
	m.step(8.0)
	var n := 0
	for i in Medium.W * Medium.H:
		if m.is_excited(i):
			n += 1
	_ok(n == 0, "两道波对撞后互相湮灭，8 秒后全场平静")


func _run(li: int, rp: Array, limit: float, probe := Vector2i(-1, -1)) -> Dictionary:
	var lv := Level.new()
	root.add_child(lv)
	lv.build(Levels.all()[li - 1], null)
	var res := {"result": "TIMEOUT", "fires": 0}
	lv.won.connect(func(): res.result = "WIN")
	lv.died.connect(func(): res.result = "DIED")
	var ri := 0
	var x := 0.0
	var hold := false
	var last := -10.0
	while lv.time < limit and res.result == "TIMEOUT":
		var inp := {"x": x, "jump": false, "jump_held": hold, "stomp": false}
		while ri < rp.size() and rp[ri][0] <= lv.time:
			match rp[ri][1]:
				"L": x = -1.0
				"R": x = 1.0
				"N": x = 0.0
				"J":
					inp.jump = true
					hold = true
				"j": hold = false
				"S": inp.stomp = true
			ri += 1
		inp.x = x
		inp.jump_held = hold
		lv.physics(1.0 / 60.0, inp)
		if probe.x >= 0:
			var t: float = lv.medium.t_exc[lv.medium.idx(probe.x, probe.y)]
			if t > last + 0.5:
				last = t
				res.fires += 1
	res.time = lv.time
	lv.free()
	return res


func _check_solutions() -> void:
	print("通关回放：")
	var n := Levels.all().size()
	for li in range(1, n + 1):
		var path := "res://tools/solutions/%02d.json" % li
		if not FileAccess.file_exists(path):
			_ok(false, "第 %d 关缺少回放" % li)
			continue
		var rp: Array = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
		var r := _run(li, rp, 60.0)
		_ok(r.result == "WIN", "第 %d 关「%s」 %s %.1f 秒" % [li, Levels.all()[li - 1].name, r.result, r.time])


func _check_rotor(li: int, wrong: Array, right: Array, probe: Vector2i) -> void:
	print("第 %d 关的回环：" % li)
	if not wrong.is_empty():
		var a := _run(li, wrong, 20.0, probe)
		_ok(a.fires <= 1, "在错的地方踩：波只经过探针 %d 次（应 ≤1，没有形成回环）" % a.fires)
	var b := _run(li, right, 20.0, probe)
	_ok(b.fires >= 3, "在对的地方踩：波反复经过探针 %d 次（应 ≥3，形成永不停的回环）" % b.fires)
