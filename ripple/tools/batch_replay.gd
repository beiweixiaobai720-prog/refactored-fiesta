extends SceneTree
## 批量回放：godot --headless -s tools/batch_replay.gd -- <关卡号> <回放数组.json> <秒数>
## 每条回放输出一行：序号 结果 用时 终点格坐标 是否着地

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var li := int(a[0]) - 1
	var all: Array = JSON.parse_string(FileAccess.open(a[1], FileAccess.READ).get_as_text())
	var limit := float(a[2])
	var data: Dictionary = Levels.all()[li]
	for k in all.size():
		var rp: Array = all[k]
		var lv := Level.new()
		root.add_child(lv)
		lv.build(data, null)
		var result := ["TIMEOUT"]
		lv.won.connect(func(): result[0] = "WIN")
		lv.died.connect(func(): result[0] = "DIED")
		var ri := 0
		var x := 0.0
		var hold := false
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
			lv.physics(1.0 / 60.0, inp)
		var p := lv.player.position / Medium.CELL
		print("%d %s %.2f %.1f %.1f %s" % [k, result[0], lv.time, p.x, p.y, lv.player.on_ground])
		lv.free()
	quit()
