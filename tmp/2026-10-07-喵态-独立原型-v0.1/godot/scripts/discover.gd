extends RefCounted
## 喵态图鉴：这些现象没有写进任何一条规则，只在猫群里“长”出来。
## 这里只负责在它们真的发生时认出来、记下来。

const Sim = preload("res://scripts/sim.gd")

const LIST := [
	{"id": "flow", "name": "猫流", "line": "一只猫只会跑；一群猫，会流。", "hint": "让一大群猫一起追同一个红点。"},
	{"id": "mound", "name": "猫丘", "line": "红点挂得高，猫自己就堆成了坡。", "hint": "把红点挂在高处，看它们怎么够。"},
	{"id": "set", "name": "定形", "line": "松手的一刻，流动的形状就成了地形。", "hint": "猫群堆起来的时候松开左键。"},
	{"id": "bridge", "name": "猫桥", "line": "坑被填满，就成了路。", "hint": "让阿黄踩着睡猫走过一道沟。"},
	{"id": "stairs", "name": "猫阶", "line": "睡着的猫，一级一级的。", "hint": "让阿黄踩着睡猫连上三级台阶。"},
	{"id": "melt", "name": "融化", "line": "红点停一停，固体就化了。", "hint": "把红点停在一只睡猫身上。"},
	{"id": "avalanche", "name": "猫雪崩", "line": "叫醒最底下那只，整座猫塔都会流下来。", "hint": "叫醒一堆睡猫最下面的那只。"},
	{"id": "split", "name": "分流", "line": "看不见红点的猫，就留下来当墙。", "hint": "把红点藏到东西后面，只让一部分猫看见。"},
	{"id": "reuse", "name": "拆桥", "line": "同一群猫，先当这段路，再当那段路。", "hint": "阿黄走过以后，把那些猫叫醒挪去别处。"},
	{"id": "chain", "name": "连锁炸毛", "line": "挤得越密，惊得越远。", "hint": "在一堆挤得紧紧的猫旁边拍手。"},
	{"id": "fizzle", "name": "传不开", "line": "离得太远，惊慌就传不下去。", "hint": "对着稀稀拉拉、互不挨着的几只猫拍手。"},
	{"id": "tramp", "name": "猫蹦床", "line": "一群受惊的猫，能把老猫弹上去。", "hint": "阿黄站在猫堆上时，在猫堆旁拍手。"},
	{"id": "sunmold", "name": "晒成形", "line": "阳光照到哪儿，猫就在哪儿凝固。", "hint": "把猫群引进一束阳光里。"},
	{"id": "piggy", "name": "踩背", "line": "阿黄的背，也是台阶。", "hint": "让小猫爬到阿黄背上。"},
]

var sim
var found := {}            # 本关已触发
var claps := {}            # cid -> {t, n, hop, direct}
var drop_times: Array = []
var fallwake_times: Array = []
var dark_sleeps: Array = []   # [time] 红点亮着时因为看不见而睡着
var steps_on_kits := 0
var release_t := -99.0
var release_sleeps := 0
var _scan := 0


static func info(id: String) -> Dictionary:
	for d in LIST:
		if d["id"] == id:
			return d
	return {}


func setup(s) -> void:
	sim = s
	found.clear()
	claps.clear()
	drop_times.clear()
	fallwake_times.clear()
	dark_sleeps.clear()
	steps_on_kits = 0


func note_release(t: float) -> void:
	release_t = t
	release_sleeps = 0


## 每个物理帧调用一次，返回本帧新认出的现象 id 列表
func update() -> Array:
	var out: Array = []
	var t: float = sim.time
	if t < 1.5:
		return out
	for e in sim.events:
		match e["t"]:
			"wake":
				if e["why"] == "dot":
					_hit("melt", out)
				elif e["why"] == "fall":
					fallwake_times.append(t)
			"drop":
				drop_times.append(t)
			"sleep":
				if e["why"] == "dark":
					if sim.dot_on:
						dark_sleeps.append(t)
					elif t - release_t < 3.0:
						release_sleeps += 1
			"clap":
				claps[e["cid"]] = {"t": t, "n": 0, "hop": 0, "direct": e["n"]}
			"spook":
				var c = claps.get(e["cid"])
				if c != null:
					c["n"] += 1
					c["hop"] = maxi(c["hop"], e["hop"])
			"launch":
				if e["v"] >= 520.0:
					_hit("tramp", out)
			"reuse":
				_hit("reuse", out)
			"step_up":
				if sim.old != null and sim.old.on_kit:
					steps_on_kits += 1
					if steps_on_kits >= 3:
						_hit("stairs", out)
			"old_wait":
				steps_on_kits = 0
	# 连锁 / 传不开
	for cid in claps.keys():
		var c: Dictionary = claps[cid]
		if t - c["t"] > 0.7:
			if c["n"] >= 8 and c["hop"] >= 3:
				_hit("chain", out)
			elif c["direct"] >= 3 and c["hop"] == 0:
				_hit("fizzle", out)
			claps.erase(cid)
	# 雪崩
	_trim(drop_times, t, 1.5)
	_trim(fallwake_times, t, 1.5)
	if sim.dot_on and drop_times.size() >= 5 and fallwake_times.size() >= 3:
		_hit("avalanche", out)
	# 分流
	_trim(dark_sleeps, t, 3.0)
	if sim.dot_on and dark_sleeps.size() >= 3:
		var chasing := 0
		for k in sim.kits:
			if k.state == Sim.AWAKE and k.sees:
				chasing += 1
		if chasing >= 3:
			_hit("split", out)
	# 定形
	if release_sleeps >= 6 and t - release_t < 3.5:
		var raised := 0
		for k in sim.kits:
			if k.state == Sim.SLEEP and k.asleep_t < 3.0:
				var fs: float = sim.surface_at(k.pos.x, k.pos.y, false)
				if fs - (k.pos.y + Sim.R) > Sim.D * 1.2:
					raised += 1
		if raised >= 3:
			_hit("set", out)
	# 猫桥
	if sim.old != null and sim.old.over_gap and sim.old.mode == Sim.O_WALK:
		_hit("bridge", out)
	# 逐帧轮流扫描一部分猫，避免每帧全量
	_scan += 1
	if _scan % 6 == 0:
		_scan_kits(out)
	return out


func _scan_kits(out: Array) -> void:
	var run_l := 0
	var run_r := 0
	var sun_sleep := 0
	var sun_raised := 0
	for k in sim.kits:
		if k.state == Sim.AWAKE:
			if k.grounded and absf(k.vel.x) > 110.0:
				if k.vel.x > 0.0:
					run_r += 1
				else:
					run_l += 1
			if k.grounded and k.on_kit and k.sees and sim.dot.y < k.pos.y - Sim.R:
				var fs: float = sim.surface_at(k.pos.x, k.pos.y, false)
				if fs - (k.pos.y + Sim.R) >= Sim.D * 2.3:
					_hit("mound", out)
			if sim.old != null:
				var o = sim.old
				if absf(k.pos.x - o.pos.x) < Sim.AH_W * 0.5 and absf((k.pos.y + Sim.R) - (o.pos.y - Sim.AH_H)) < 4.0:
					_hit("piggy", out)
		elif k.state == Sim.SLEEP and k.in_sun:
			sun_sleep += 1
			var fs2: float = sim.surface_at(k.pos.x, k.pos.y, false)
			if fs2 - (k.pos.y + Sim.R) > Sim.D * 0.8:
				sun_raised += 1
	if run_l >= 8 or run_r >= 8:
		_hit("flow", out)
	if sun_sleep >= 5 and sun_raised >= 2:
		_hit("sunmold", out)


func _hit(id: String, out: Array) -> void:
	if found.has(id):
		return
	found[id] = true
	out.append(id)


func _trim(arr: Array, t: float, win: float) -> void:
	while not arr.is_empty() and t - float(arr[0]) > win:
		arr.pop_front()
