extends SceneTree
## 自动验证：每关的脚本化解法（与真人操作走同一套模拟与输入通道），
## 外加随机种子与输入扰动下的稳健性检查。输出 JSON 报告。
## 用法：godot --headless --path godot --script res://tests/verify.gd -- <out.json> [只跑某关id] [扰动次数]

const Sim = preload("res://scripts/sim.gd")
const Levels = preload("res://scripts/levels.gd")
const Autoplay = preload("res://scripts/autoplay.gd")
const Discover = preload("res://scripts/discover.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://verify.json"
	var only: String = args[1] if args.size() > 1 else ""
	var jitters := int(args[2]) if args.size() > 2 else 6
	var f := FileAccess.open("res://tests/solutions.json", FileAccess.READ)
	var sols: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var report := {"engine": Engine.get_version_info()["string"], "levels": []}
	var all_ok := true
	for lv in Levels.LEVELS:
		var id: String = lv["id"]
		if only != "" and only != "all" and id != only:
			continue
		var entry := {"id": id, "name": lv["name"], "solutions": [], "negatives": []}
		for s in sols.get(id, {}).get("solve", []):
			if OS.get_environment("VERIFY_DEBUG") != "":
				print("== %s %s" % [id, s["name"]])
			var r := run(lv, s, 7)
			var rob := []
			var wins := 0
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(id + s["name"])
			for j in jitters:
				var js := jitter(s, rng)
				var rr := run(lv, js, 100 + j)
				rob.append(rr["won"])
				if rr["won"]:
					wins += 1
			var ok: bool = r["won"]
			all_ok = all_ok and ok
			entry["solutions"].append({"name": s["name"], "won": r["won"], "win_t": r["win_t"], "found": r["found"],
				"robust": "%d/%d" % [wins, jitters], "states": r["states"]})
			print("%-4s %-10s %-22s won=%-5s t=%6.2f robust=%d/%d found=%s" % [id, lv["name"], s["name"], str(r["won"]), r["win_t"], wins, jitters, str(r["found"])])
		for s in sols.get(id, {}).get("fail", []):
			var r2 := run(lv, s, 7)
			entry["negatives"].append({"name": s["name"], "won": r2["won"]})
			if r2["won"]:
				all_ok = false
			print("%-4s %-10s %-22s (应失败) won=%s" % [id, lv["name"], s["name"], str(r2["won"])])
		report["levels"].append(entry)
	report["all_ok"] = all_ok
	var fo := FileAccess.open(out_path, FileAccess.WRITE)
	fo.store_string(JSON.stringify(report, "  "))
	fo.close()
	print("ALL_OK=", all_ok)
	quit()


static func run(lv: Dictionary, spec: Dictionary, seed_val: int) -> Dictionary:
	var sim = Sim.new()
	sim.setup(lv, seed_val)
	var disc = Discover.new()
	disc.setup(sim)
	var dur: float = spec.get("dur", 90.0)
	var n := int(dur / Sim.DT)
	var win_t := -1.0
	var was_on := false
	var runner = Autoplay.Runner.new(spec)
	var bot := Fixer.new(spec)
	for i in n:
		var t := float(i) * Sim.DT
		var inp: Dictionary
		if bot.busy():
			inp = bot.step(sim, t, {"dot_on": false})
		else:
			inp = runner.input(sim, t, Sim.DT)
			# 脚本没在操作（做完了，或在等阿黄到位）而阿黄被一只猫挡住：像真人一样先修路
			if runner.finished or runner.waiting:
				inp = bot.step(sim, t, inp)
		if was_on and not inp["dot_on"]:
			disc.note_release(sim.time)
		was_on = inp["dot_on"]
		sim.step(inp)
		disc.update()
		if sim.won:
			win_t = sim.time
			break
	var info := ""
	if not sim.won and sim.old != null:
		info = "old=(%.0f,%.0f) why=%s hit=%s" % [sim.old.pos.x, sim.old.pos.y, sim.old.why, sim.last_hit]
	if OS.get_environment("VERIFY_DEBUG") != "" and not sim.won:
		print("    FAIL seed=%d %s" % [seed_val, info])
		var dd := OS.get_environment("VERIFY_DUMP")
		if dd != "":
			var fo := FileAccess.open("%s/fail_%s_%d.json" % [dd, lv["id"], seed_val], FileAccess.WRITE)
			fo.store_string(JSON.stringify(spec))
			fo.close()
	return {"won": sim.won, "win_t": snappedf(win_t, 0.01), "found": disc.found.keys(), "states": sim.count_states(), "info": info, "fixups": bot.used}


static func jitter(spec: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# 模拟“人手不准”：位置偏 ±10px，时间偏 ±0.25s
	var out := spec.duplicate(true)
	var cmds: Array = []
	if out.has("cmds"):
		cmds.append_array(out["cmds"])
	for ph in out.get("phases", []):
		cmds.append_array(ph["cmds"])
	var dx := rng.randf_range(-10, 10)
	var dy := rng.randf_range(-8, 8)
	var dt := rng.randf_range(-0.25, 0.25)
	for c in cmds:
		match c[0]:
			"dot":
				c[1] = maxf(0.0, c[1] + dt)
				c[2] = c[2] + dt
				c[3] += dx
				c[4] += dy
				c[5] += dx
				c[6] += dy
			"path":
				c[1] = maxf(0.0, c[1] + dt)
				c[2] = c[2] + dt
				var pts: Array = c[3]
				for i in range(0, pts.size(), 2):
					pts[i] += dx
					pts[i + 1] += dy
			"clap", "clap_old":
				c[1] = maxf(0.0, c[1] + dt * 0.5)
				c[2] += dx
				c[3] += dy
	return out


class Fixer:
	## 像真人一样“修路”：阿黄被某只睡猫挡住时，把红点停在那只猫身上叫醒它，再把它引开、松手。
	var enabled := false
	var end_t := 0.0
	var state := 0
	var timer := 0.0
	var target := -1
	var dest := Vector2.ZERO
	var used := 0
	var cooldown := 0.0

	func _init(spec: Dictionary) -> void:
		enabled = bool(spec.get("fixup", false))
		for c in spec.get("cmds", []):
			if c[0] == "dot" or c[0] == "path":
				end_t = maxf(end_t, float(c[2]))
			elif c[0] == "clap" or c[0] == "clap_old":
				end_t = maxf(end_t, float(c[1]))

	func busy() -> bool:
		return state != 0

	func step(sim, t: float, inp: Dictionary) -> Dictionary:
		if not enabled or sim.old == null or (used >= 6 and state == 0):
			return inp
		cooldown -= Sim.DT
		match state:
			0:
				if cooldown <= 0.0 and sim.all_quiet() and sim.old.mode == Sim.O_WAIT and sim.old.wait_t > 1.5:
					if sim.old.why == "high" and sim.last_hit_kit >= 0:
						target = sim.last_hit_kit
					elif sim.old.why == "drop" and sim.old.on_kit:
						# 阿黄站在猫堆上、前面一下子低下去：叫醒他脚尖底下那只，引到前面去垫一级台阶
						target = _front_kit(sim)
					else:
						target = -1
					if target >= 0:
						state = 1
						timer = 0.0
						used += 1
			1:
				timer += Sim.DT
				var k = sim.kits[target]
				inp = {"dot_on": true, "dot": k.pos}
				if timer > 0.6:
					state = 2
					timer = 0.0
					# 先引到阿黄身后（阿黄不走回头路，那边的猫不挡路）；还不行，下一次往前引去填前面的坑
					if sim.old.why == "drop":
						dest = Vector2(sim.old.pos.x + sim.old.dir * 75.0, sim.old.pos.y + 30.0)
					elif used % 2 == 1:
						dest = k.pos + Vector2(-sim.old.dir * 150.0, -10.0)
					else:
						dest = k.pos + Vector2(sim.old.dir * 110.0, -10.0)
			2:
				timer += Sim.DT
				var k2 = sim.kits[target]
				inp = {"dot_on": true, "dot": k2.pos.lerp(dest, minf(1.0, timer / 0.8))}
				if timer > 1.6:
					state = 0
					cooldown = 2.5
		return inp

	func _front_kit(sim) -> int:
		var o = sim.old
		var best := -1
		var best_x := -INF
		for i in sim.kits.size():
			var k = sim.kits[i]
			if k.state != Sim.SLEEP:
				continue
			if absf((k.pos.y - Sim.R) - o.pos.y) > 8.0 or absf(k.pos.x - o.pos.x) > Sim.AH_W * 0.5 + Sim.R:
				continue
			var fx: float = (k.pos.x - o.pos.x) * o.dir
			if fx > best_x:
				best_x = fx
				best = i
		return best
