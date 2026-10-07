extends SceneTree
## 探针：在第 N 关的指定时刻于玩家脚下点亮，然后报告若干格第一次被点亮的时刻。
## godot --headless -s tools/probe.gd -- <关卡号> <踩的时刻 或 回放.json> <x,y;x,y;...> [持续秒数]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var lv := Level.new()
	root.add_child(lv)
	lv.build(Levels.all()[int(a[0]) - 1], null)
	var ts := float(a[1]) if a[1].is_valid_float() else 1.0e9
	var rp: Array = [] if a[1].is_valid_float() else JSON.parse_string(FileAccess.open(a[1], FileAccess.READ).get_as_text())
	var ri := 0
	var rx := 0.0
	var pts := []
	for s in a[2].split(";"):
		var xy := s.split(",")
		pts.append(Vector2i(int(xy[0]), int(xy[1])))
	var dur := float(a[3]) if a.size() > 3 else 20.0
	var first := {}
	var stomped := false
	while lv.time < dur:
		var inp := {"x": 0.0, "jump": false, "jump_held": false, "stomp": false}
		if not stomped and lv.time >= ts:
			inp.stomp = true
			stomped = true
		while ri < rp.size() and rp[ri][0] <= lv.time:
			match rp[ri][1]:
				"L": rx = -1.0
				"R": rx = 1.0
				"N": rx = 0.0
				"J": inp.jump = true
				"S": inp.stomp = true
			ri += 1
		inp.x = rx
		lv.physics(1.0 / 60.0, inp)
		for p in pts:
			var i: int = lv.medium.idx(p.x, p.y)
			if lv.medium.is_excited(i):
				if not first.has(p):
					first[p] = []
				var lst: Array = first[p]
				if lst.is_empty() or lv.medium.t_exc[i] - lst[-1] > 0.5:
					lst.append(snappedf(lv.medium.t_exc[i], 0.01))
	for p in pts:
		print(p, " -> ", first.get(p, "never"))
	print("bells rung: ", lv.bells.filter(func(b): return b.rung).size(), "/", lv.bells.size())
	quit()
