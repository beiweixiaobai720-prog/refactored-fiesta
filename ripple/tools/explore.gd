extends SceneTree
## 随机探索：godot --headless -s tools/explore.gd -- <关卡号> <次数> <秒数> <种子> [前缀.json]
## 每条随机操作序列结束后记录离出口最近的距离，打印最好的几条（可当回放用）。
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var li := int(a[0]) - 1
	var n := int(a[1])
	var limit := float(a[2])
	seed(int(a[3]))
	var prefix: Array = []
	if a.size() > 4:
		prefix = JSON.parse_string(FileAccess.open(a[4], FileAccess.READ).get_as_text())
	var data: Dictionary = Levels.all()[li]
	var best := []
	for k in n:
		var rp: Array = prefix.duplicate(true)
		var t := 0.0
		for e in prefix:
			t = maxf(t, e[0])
		t += 0.1
		while t < limit:
			var r := randf()
			if r < 0.25:
				rp.append([snappedf(t, 0.05), "L"])
			elif r < 0.5:
				rp.append([snappedf(t, 0.05), "R"])
			elif r < 0.62:
				rp.append([snappedf(t, 0.05), "N"])
			elif r < 0.8:
				rp.append([snappedf(t, 0.05), "J"])
				rp.append([snappedf(t + randf_range(0.1, 0.5), 0.05), "j"])
			else:
				rp.append([snappedf(t, 0.05), "S"])
			t += randf_range(0.15, 0.8)
		rp.sort_custom(func(x, y): return x[0] < y[0])
		var lv := Level.new()
		root.add_child(lv)
		lv.build(data, null)
		var res := ["T"]
		lv.won.connect(func(): res[0] = "WIN")
		lv.died.connect(func(): res[0] = "DIED")
		var ri := 0
		var x := 0.0
		var hold := false
		var dmin := 1e9
		var tmin := 0.0
		var exitc := lv.exit_rect.get_center()
		while lv.time < limit and res[0] == "T":
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
			var dd := lv.player.position.distance_to(exitc) / Medium.CELL
			if dd < dmin and lv.dead_t < 0.0 and lv.player.on_ground:
				dmin = dd
				tmin = lv.time
		if res[0] == "WIN":
			dmin = 0.0
		best.append([dmin, res[0], rp, tmin])
		lv.free()
	best.sort_custom(func(x, y): return x[0] < y[0])
	for k in mini(3, best.size()):
		print("BEST %.1f %s %.2f" % [best[k][0], best[k][1], best[k][3]])
		print(JSON.stringify(best[k][2]))
	quit()
