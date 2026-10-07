extends SceneTree
## 实验台：无界面运行某一关，按脚本输入红点/拍手，导出若干帧状态（JSON），供调参与验证。
## 用法：godot --headless --path godot --script res://tests/lab.gd -- <level_id> <script.json> <out.json> [seed]

const Sim = preload("res://scripts/sim.gd")
const Levels = preload("res://scripts/levels.gd")
const Autoplay = preload("res://scripts/autoplay.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var level_id: String = args[0]
	var script_path: String = args[1]
	var out_path: String = args[2]
	var seed_val := int(args[3]) if args.size() > 3 else 7
	var lv: Dictionary
	if level_id.ends_with(".json"):
		var lf := FileAccess.open(level_id, FileAccess.READ)
		lv = JSON.parse_string(lf.get_as_text())
		lf.close()
	else:
		lv = Levels.get_level(level_id)
	var f := FileAccess.open(script_path, FileAccess.READ)
	var spec: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var res := run(lv, spec, seed_val)
	var fo := FileAccess.open(out_path, FileAccess.WRITE)
	fo.store_string(JSON.stringify(res))
	fo.close()
	print("won=", res["won"], " win_t=", res["win_t"], " old=", res["old_final"], " states=", res["states"])
	quit()


static func input_at(spec: Dictionary, t: float) -> Dictionary:
	var inp := {"dot_on": false}
	for c in spec.get("cmds", []):
		var kind: String = c[0]
		if kind == "dot":
			var t0: float = c[1]
			var t1: float = c[2]
			if t >= t0 and t < t1:
				var a := 0.0 if t1 <= t0 else (t - t0) / (t1 - t0)
				inp["dot_on"] = true
				inp["dot"] = Vector2(lerpf(c[3], c[5], a), lerpf(c[4], c[6], a))
		elif kind == "path":
			# ["path", t0, t1, [x,y, x,y, ...]] 匀速折线
			var p0: float = c[1]
			var p1: float = c[2]
			if t >= p0 and t < p1:
				var pts: Array = c[3]
				var n := pts.size() / 2
				var a2 := (t - p0) / (p1 - p0) * float(n - 1)
				var i := mini(int(a2), n - 2)
				var fr := a2 - float(i)
				inp["dot_on"] = true
				inp["dot"] = Vector2(lerpf(pts[i * 2], pts[i * 2 + 2], fr), lerpf(pts[i * 2 + 1], pts[i * 2 + 3], fr))
	return inp


static func run(lv: Dictionary, spec: Dictionary, seed_val: int) -> Dictionary:
	var sim = Sim.new()
	sim.setup(lv, seed_val)
	var dur: float = spec.get("dur", 30.0)
	var dump_every: float = spec.get("dump_every", 0.0)
	var dump_at: Array = spec.get("dump_at", [])
	var claps: Array = []
	for c in spec.get("cmds", []):
		if c[0] == "clap":
			claps.append(c)
	var frames := []
	var next_dump := 0.0
	var win_t := -1.0
	var ev_counts := {}
	var max_launch := 0.0
	var n := int(dur / Sim.DT)
	var runner = Autoplay.Runner.new(spec)
	for i in n:
		var t := float(i) * Sim.DT
		var inp: Dictionary = runner.input(sim, t, Sim.DT)
		sim.step(inp)
		for e in sim.events:
			if e["t"] == "launch" or e["t"] == "clap" or e["t"] == "land":
				print("  ev t=%.2f %s old=%s" % [t, e, sim.old.pos if sim.old != null else null])
		for e in sim.events:
			ev_counts[e["t"]] = ev_counts.get(e["t"], 0) + 1
			if e["t"] == "launch":
				max_launch = maxf(max_launch, e["v"])
		if sim.won and win_t < 0.0:
			win_t = sim.time
		var want := false
		if dump_every > 0.0 and t >= next_dump:
			want = true
			next_dump += dump_every
		for da in dump_at:
			if absf(t - float(da)) < Sim.DT * 0.5:
				want = true
		if want:
			frames.append(dump(sim, inp))
		if win_t > 0.0 and sim.time > win_t + float(spec.get("after_win", 0.5)):
			break
	frames.append(dump(sim, input_at(spec, sim.time)))
	var o := {}
	if sim.old != null:
		o = {"x": snappedf(sim.old.pos.x, 0.1), "y": snappedf(sim.old.pos.y, 0.1), "mode": sim.old.mode, "why": sim.old.why, "hit": sim.last_hit}
	return {"won": sim.won, "win_t": snappedf(win_t, 0.01), "old_final": o, "states": sim.count_states(),
		"frames": frames, "events": ev_counts, "max_launch": max_launch}


static func dump(sim, inp: Dictionary) -> Dictionary:
	var ks := []
	for k in sim.kits:
		ks.append([snappedf(k.pos.x, 0.1), snappedf(k.pos.y, 0.1), k.state, k.in_sun])
	var o := []
	if sim.old != null:
		o = [snappedf(sim.old.pos.x, 0.1), snappedf(sim.old.pos.y, 0.1), sim.old.mode]
	var bl := []
	for b in sim.blocks:
		if b.kind == "bound":
			continue
		bl.append([b.r.position.x, b.r.position.y, b.r.size.x, b.r.size.y, b.kind, b.solid, b.sight])
	var suns := []
	for s in sim.suns:
		var pts := []
		for p in s:
			pts.append(p.x)
			pts.append(p.y)
		suns.append(pts)
	return {"t": snappedf(sim.time, 0.01), "kits": ks, "old": o, "blocks": bl, "goal": [sim.goal.position.x, sim.goal.position.y, sim.goal.size.x, sim.goal.size.y],
		"dot": [sim.dot.x, sim.dot.y] if inp.get("dot_on", false) else [], "suns": suns}
