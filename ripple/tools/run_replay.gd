extends SceneTree
## 无界面回放验证：godot --headless -s tools/run_replay.gd -- <关卡号> <回放.json> [秒数] [trace]
## 输出：WIN / DIED / TIMEOUT，以及用时。trace 时每 0.25 秒打印玩家位置（格坐标）。

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var li := int(a[0]) - 1
	var rp: Array = JSON.parse_string(FileAccess.open(a[1], FileAccess.READ).get_as_text())
	var limit := float(a[2]) if a.size() > 2 else 40.0
	var trace := a.size() > 3
	var lv := Level.new()
	root.add_child(lv)
	lv.build(Levels.all()[li], null)
	var result := ["TIMEOUT"]
	lv.won.connect(func(): result[0] = "WIN")
	lv.died.connect(func(): result[0] = "DIED")
	var dt := 1.0 / 60.0
	var ri := 0
	var x := 0.0
	var hold := false
	var next_trace := 0.0
	while lv.time < limit and result[0] == "TIMEOUT":
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
		lv.physics(dt, inp)
		if trace and lv.time >= next_trace:
			next_trace += 0.25
			var p := lv.player.position / Medium.CELL
			print("t=%5.2f  x=%5.1f y=%5.1f  vy=%6.0f  g=%s c=%.2f  bells=%d/%d" % [lv.time, p.x, p.y, lv.player.vel.y, lv.player.on_ground, lv.player.carried, lv.bells.filter(func(b): return b.rung).size(), lv.bells.size()])
	print("%s  t=%.2f  pos=%s" % [result[0], lv.time, lv.player.position / Medium.CELL])
	quit()
