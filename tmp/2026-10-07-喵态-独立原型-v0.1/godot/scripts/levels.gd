extends RefCounted
## 喵态 · 关卡数据
## 方块：[x, y, w, h, 种类, {选项}]；"floor" 是冰凉的地面（阿黄不肯往上走）

const CHAPTERS := ["客厅 · 黄昏", "厨房 · 清晨", "楼梯间 · 傍晚", "屋顶 · 夜"]

static var _levels: Array = []
static var LEVELS: Array:
	get:
		if _levels.is_empty():
			var f := FileAccess.open("res://levels/levels.json", FileAccess.READ)
			_levels = JSON.parse_string(f.get_as_text())
			f.close()
		return _levels


static func demo() -> Dictionary:
	var kits := []
	for i in 22:
		kits.append([180 + (i % 11) * 70, 560 - (i / 11) * 40])
	return {
		"id": "demo", "name": "标题", "theme": "living", "seed": 3,
		"blocks": [
			[0, 640, 1280, 80, "floor"],
			[980, 520, 300, 120, "sill"],
			[40, 590, 150, 50, "pouf"],
		],
		"kits": kits,
		"old": [1120, 520, -1],
		"old_goal": true,
		"goal": [-999, -999, 1, 1],
		"deco": [
			{"type": "window", "rect": [1010, 250, 230, 200], "sun": true},
			{"type": "frame", "rect": [700, 250, 90, 70], "art": "cat"},
			{"type": "frame", "rect": [820, 270, 60, 50], "art": "moon", "bg": "8c8fd0"},
			{"type": "lamp", "x": 560, "floor": 640, "h": 260},
			{"type": "plant", "x": 930, "y": 612},
			{"type": "rug", "x0": 260, "x1": 900, "y": 640},
		],
	}


static func chapters() -> Array:
	var out := []
	for c in CHAPTERS.size():
		var idx := []
		for i in LEVELS.size():
			if int(LEVELS[i]["chapter"]) == c:
				idx.append(i)
		if not idx.is_empty():
			out.append({"name": CHAPTERS[c], "levels": idx})
	return out


static func chapter_name(lv: Dictionary) -> String:
	return CHAPTERS[int(lv.get("chapter", 0))]


static func get_level(id: String) -> Dictionary:
	for l in LEVELS:
		if l["id"] == id:
			return l
	return {}
