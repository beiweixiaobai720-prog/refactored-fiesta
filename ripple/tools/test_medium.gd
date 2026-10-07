extends SceneTree
# 无界面测试：验证活膜的几条涌现性质。
func _init():
	var m := Medium.new()
	# 一大片活膜
	for y in Medium.H:
		for x in Medium.W:
			m.kind[m.idx(x, y)] = Medium.MED
	m.reset_state()
	m.stimulate(m.idx(32, 18))
	m.step(1.0)
	# 1 秒后半径应约为 9 格：统计亮格到中心的距离
	var ds := []
	for y in Medium.H:
		for x in Medium.W:
			if m.is_excited(m.idx(x, y)):
				ds.append(Vector2(x - 32, y - 18).length())
	ds.sort()
	print("ring after 1s: n=", ds.size(), " min=", ds[0], " max=", ds[-1])
	var t0 := Time.get_ticks_msec()
	m.step(5.0)
	print("sim 5s ms=", Time.get_ticks_msec() - t0)
	# 对撞湮灭：两点，过后应全部平静
	m.reset_state()
	m.stimulate(m.idx(10, 18)); m.stimulate(m.idx(50, 18))
	m.step(8.0)
	var n := 0
	for i in Medium.W * Medium.H:
		if m.is_excited(i): n += 1
	print("after annihilation excited=", n)
	quit()
