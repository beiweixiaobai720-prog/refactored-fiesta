extends RefCounted
const Autoplay = preload("res://scripts/autoplay.gd")
## 脚本化输入：用于自动验证、截图与录像（与真人操作走同一套模拟）
## spec = {"cmds": [["dot", t0, t1, x0, y0, x1, y1], ["path", t0, t1, [x,y,...]], ["clap", t, x, y]]}
## ["clap_old", t, dx, dy]：在阿黄当前位置旁边拍手（真人会看着阿黄站在哪儿再拍）


static func input_at(spec: Dictionary, t: float, dt: float, sim = null) -> Dictionary:
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
		elif kind == "clap":
			var ct: float = c[1]
			if t <= ct and ct < t + dt:
				inp["clap"] = Vector2(c[2], c[3])
		elif kind == "clap_old":
			var ct2: float = c[1]
			if t <= ct2 and ct2 < t + dt and sim != null and sim.old != null:
				inp["clap"] = sim.old.pos + Vector2(c[2], c[3])
	return inp


class Runner:
	## 分阶段的脚本：下一阶段等条件满足才开始（比如“阿黄停下来等了”），像真人一样看情况再动手。
	## spec = {"phases": [{"when": "start"|"wait"|"quiet", "cmds": [...相对该阶段开始的时间...]}, ...]}
	## 阶段可带 "x": [x0, x1]：阿黄要停在这段横坐标里才算“到位”（比如走到了墙根下）。
	## 阶段可带 "retry": [[dx, dy], ...]：这一下没成、阿黄又停下来等的时候，像真人一样按 Z 回到动手前，
	## 换个位置（clap_old 的偏移）再拍一次。
	var spec: Dictionary
	var phases: Array = []
	var idx := 0
	var start_t := 0.0
	var end_rel := 0.0
	var waiting := false
	var cond_t := 0.0
	var snap = null
	var tries := 0
	var finished := false

	func _init(s: Dictionary) -> void:
		spec = s
		if s.has("phases"):
			phases = s["phases"]
		else:
			phases = [{"when": "start", "cmds": s.get("cmds", [])}]
		_begin(0, 0.0)

	func _begin(i: int, t: float) -> void:
		idx = i
		start_t = t
		end_rel = 0.0
		snap = null
		tries = 0
		if i < phases.size():
			for c in phases[i]["cmds"]:
				if c[0] == "dot" or c[0] == "path":
					end_rel = maxf(end_rel, float(c[2]))
				elif c[0] == "clap" or c[0] == "clap_old":
					end_rel = maxf(end_rel, float(c[1]))
			waiting = phases[i].get("when", "start") != "start"
		else:
			finished = true
		cond_t = 0.0

	func _cmds() -> Array:
		var cmds: Array = phases[idx]["cmds"]
		if tries == 0:
			return cmds
		var off: Array = phases[idx]["retry"][tries - 1]
		var out: Array = []
		for c in cmds:
			if c[0] == "clap_old":
				out.append(["clap_old", c[1], off[0], off[1]])
			else:
				out.append(c)
		return out

	func input(sim, t: float, dt: float) -> Dictionary:
		if idx >= phases.size():
			return {"dot_on": false}
		var ph: Dictionary = phases[idx]
		if waiting:
			if _cond(sim, ph.get("when", "start"), dt, ph.get("x", [])):
				waiting = false
				start_t = t
				if ph.has("retry") and snap == null:
					snap = sim.snapshot()
			else:
				return {"dot_on": false}
		var rel := t - start_t
		var inp := Autoplay.input_at({"cmds": _cmds()}, rel, dt, sim)
		if rel > end_rel + 0.5:
			if snap != null and not sim.won and tries < ph["retry"].size():
				# 没成：等阿黄又停下来、四下安静，就回到动手前，换个位置再来
				if _cond(sim, "wait", dt):
					sim.restore(snap)
					tries += 1
					start_t = t
					cond_t = 0.0
			elif idx + 1 < phases.size():
				_begin(idx + 1, t)
			elif rel > end_rel + 1.0:
				finished = true
		return inp

	func _cond(sim, when: String, dt: float, xr: Array = []) -> bool:
		var ok := false
		match when:
			"quiet":
				ok = sim.all_quiet()
			"wait":
				ok = sim.old != null and sim.all_quiet() and sim.old.mode == 1 and sim.old.why != "noisy" and sim.old.wait_t > 1.0
				if ok and xr.size() == 2:
					ok = sim.old.pos.x >= float(xr[0]) and sim.old.pos.x <= float(xr[1])
		if ok:
			cond_t += dt
		else:
			cond_t = 0.0
		return cond_t > 0.3

	func last_end() -> float:
		return INF if idx < phases.size() else 0.0
