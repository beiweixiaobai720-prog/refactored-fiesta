extends Node
## 喵态 · 入口：标题、选关、图鉴、结尾、存档

const Game = preload("res://scripts/game.gd")
const Levels = preload("res://scripts/levels.gd")
const Discover = preload("res://scripts/discover.gd")
const UI = preload("res://scripts/ui.gd")
const Audio = preload("res://scripts/audio.gd")

const SAVE_PATH := "user://miaotai_save.json"

var audio
var game: Node2D = null
var overlay: Control = null
var ui_layer: CanvasLayer
var data := {"done": {}, "found": {}, "muted": false, "best": {}}
# 自动截图 / 录像用（命令行参数）
var shot_times: Array = []
var shot_dir := ""
var shot_i := 0
var quit_after := -1.0
var screen_t := 0.0
var autoplay_spec: Dictionary = {}


func _ready() -> void:
	DisplayServer.window_set_title("喵态 · 一只猫只是猫，一群猫是液体")
	RenderingServer.set_default_clear_color(Color("e9b4a6"))
	_load_save()
	audio = Audio.new()
	add_child(audio)
	audio.set_muted(bool(data.get("muted", false)))
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	var args := OS.get_cmdline_user_args()
	var start := -1
	var screen := ""
	for a in args:
		if a.begins_with("--level="):
			start = int(a.substr(8)) - 1
		elif a.begins_with("--autoplay="):
			var f := FileAccess.open(a.substr(11), FileAccess.READ)
			autoplay_spec = JSON.parse_string(f.get_as_text())
			f.close()
		elif a.begins_with("--shots="):
			for x in a.substr(8).split(","):
				shot_times.append(float(x))
		elif a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
		elif a.begins_with("--quit_after="):
			quit_after = float(a.substr(13))
		elif a.begins_with("--screen="):
			screen = a.substr(9)
		elif a == "--fresh":
			data = {"done": {}, "found": {}, "muted": false, "best": {}}
	if start >= 0:
		play_level(start)
	elif screen == "select":
		show_select()
	elif screen == "notebook":
		show_notebook("title")
	elif screen == "ending":
		show_ending()
	else:
		show_title()


func _process(delta: float) -> void:
	screen_t += delta
	if shot_dir == "" and quit_after < 0.0:
		return
	var lt := screen_t
	if game != null and not game.demo:
		lt = game.level_time
	while shot_i < shot_times.size() and lt >= float(shot_times[shot_i]):
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%02d.png" % [shot_dir, shot_i])
		shot_i += 1
	if quit_after > 0.0 and lt >= quit_after:
		get_tree().quit()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match (ev as InputEventKey).keycode:
			KEY_M:
				toggle_mute()
			KEY_F11:
				toggle_fullscreen()


func toggle_mute() -> void:
	data["muted"] = not bool(data.get("muted", false))
	audio.set_muted(data["muted"])
	_save()


func toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


# ================================================================ 存档

func _load_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		if d is Dictionary:
			for k in d.keys():
				data[k] = d[k]


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


func add_discovery(id: String) -> bool:
	var fresh: bool = not data["found"].has(id)
	data["found"][id] = true
	_save()
	return fresh


func level_done(index: int, secs: float) -> void:
	var id: String = Levels.LEVELS[index]["id"]
	data["done"][id] = true
	var best: float = float(data["best"].get(id, 99999.0))
	data["best"][id] = minf(best, secs)
	_save()


# ================================================================ 场景切换

func _clear() -> void:
	if game != null:
		game.queue_free()
		game = null
	if overlay != null:
		overlay.queue_free()
		overlay = null


func play_level(index: int) -> void:
	_clear()
	index = clampi(index, 0, Levels.LEVELS.size() - 1)
	game = Game.new()
	game.setup(self, index, false)
	game.request.connect(_on_game_request)
	add_child(game)
	if not autoplay_spec.is_empty():
		game.autoplay = autoplay_spec


func _on_game_request(action: String) -> void:
	audio.play("click")
	match action:
		"next":
			var nxt: int = game.level_index + 1
			if nxt >= Levels.LEVELS.size():
				show_ending()
			else:
				play_level(nxt)
		"select":
			show_select()
		"notebook":
			show_notebook("select")
		"title":
			show_title()


func _demo_bg() -> void:
	game = Game.new()
	game.setup(self, 0, true)
	add_child(game)


func _overlay() -> Control:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.theme = UI.theme()
	ui_layer.add_child(overlay)
	return overlay


func show_title() -> void:
	_clear()
	_demo_bg()
	var o := _overlay()
	var vb := VBoxContainer.new()
	vb.position = Vector2(80, 70)
	vb.add_theme_constant_override("separation", 6)
	o.add_child(vb)
	var title := UI.label("喵态", 112, Color.WHITE, true)
	title.add_theme_color_override("font_outline_color", Color("c0565a"))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", Color(0.4, 0.1, 0.15, 0.35))
	title.add_theme_constant_override("shadow_offset_y", 6)
	vb.add_child(title)
	var sub := UI.label("一只猫只是猫，一群猫是液体。", 30, Color.WHITE)
	sub.add_theme_color_override("font_outline_color", Color(0.45, 0.18, 0.2, 0.7))
	sub.add_theme_constant_override("outline_size", 6)
	vb.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	vb.add_child(gap)
	var first := _first_unfinished()
	var items := []
	if first > 0:
		items.append(["继续：%s %s" % [Levels.LEVELS[first]["id"], Levels.LEVELS[first]["name"]], func(): play_level(first)])
		items.append(["从头开始", func(): play_level(0)])
	else:
		items.append(["开始", func(): play_level(0)])
	items.append(["选关", show_select])
	items.append(["喵态图鉴  %d / %d" % [data["found"].size(), Discover.LIST.size()], func(): show_notebook("title")])
	items.append(["静音 / 取消静音  M", toggle_mute])
	items.append(["退出", func(): get_tree().quit()])
	for it in items:
		var b := UI.button(it[0], 24)
		b.custom_minimum_size = Vector2(330, 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): audio.play("click"); it[1].call())
		vb.add_child(b)
	var foot := UI.label("按住左键：红点　松开：猫睡着　右键：拍手　·　原型 v0.1", 16, Color(1, 1, 1, 0.92))
	foot.add_theme_color_override("font_outline_color", Color(0.4, 0.15, 0.18, 0.6))
	foot.add_theme_constant_override("outline_size", 4)
	foot.position = Vector2(80, 720 - 46)
	o.add_child(foot)


func _first_unfinished() -> int:
	for i in Levels.LEVELS.size():
		if not data["done"].has(Levels.LEVELS[i]["id"]):
			return i
	return 0


func show_select() -> void:
	_clear()
	_demo_bg()
	var o := _overlay()
	var dim := ColorRect.new()
	dim.color = Color(0.25, 0.08, 0.14, 0.25)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	var pc := PanelContainer.new()
	o.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	head.add_child(UI.label("选关", 34, UI.CORAL, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var nb := UI.button("喵态图鉴", 18)
	nb.pressed.connect(func(): audio.play("click"); show_notebook("select"))
	head.add_child(nb)
	var back := UI.button("返回标题", 18)
	back.pressed.connect(func(): audio.play("click"); show_title())
	head.add_child(back)
	var chapters := Levels.chapters()
	for ch in chapters:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vb.add_child(row)
		var cl := UI.label(ch["name"], 20, UI.INK_L, true)
		cl.custom_minimum_size = Vector2(150, 0)
		row.add_child(cl)
		for idx in ch["levels"]:
			var L: Dictionary = Levels.LEVELS[idx]
			var done: bool = data["done"].has(L["id"])
			var b := UI.button(("✓ " if done else "") + L["id"] + "  " + L["name"], 19)
			b.custom_minimum_size = Vector2(196, 50)
			var i2: int = idx
			b.pressed.connect(func(): audio.play("click"); play_level(i2))
			row.add_child(b)
	var note := UI.label("所有关卡都可直接进入。每关过后会记下这一关里“冒出来”的现象。", 16, UI.INK_L)
	vb.add_child(note)
	pc.reset_size()
	await get_tree().process_frame
	if is_instance_valid(pc):
		pc.reset_size()
		pc.position = Vector2(640, 360) - pc.size * 0.5


func show_notebook(back_to: String) -> void:
	_clear()
	_demo_bg()
	var o := _overlay()
	var dim := ColorRect.new()
	dim.color = Color(0.25, 0.08, 0.14, 0.3)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	var pc := PanelContainer.new()
	o.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	head.add_child(UI.label("喵态图鉴", 34, UI.CORAL, true))
	var cnt := UI.label("   已看见 %d / %d" % [data["found"].size(), Discover.LIST.size()], 20, UI.INK_L)
	head.add_child(cnt)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := UI.button("返回", 18)
	back.pressed.connect(func(): audio.play("click"); show_select() if back_to == "select" else show_title())
	head.add_child(back)
	var sub := UI.label("这些都不是规则。规则只有：看见红点就追、看不见就睡、受惊就炸毛。下面这些，是猫多了以后自己冒出来的。", 16, UI.INK_L)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(1000, 0)
	vb.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	for d in Discover.LIST:
		var got: bool = data["found"].has(d["id"])
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.box(Color("fff3df") if got else Color(0.95, 0.92, 0.9, 0.9), 14, Color("f4c06a") if got else Color(0.85, 0.8, 0.78), 2, 12))
		card.custom_minimum_size = Vector2(494, 0)
		var cb := VBoxContainer.new()
		cb.add_theme_constant_override("separation", -2)
		card.add_child(cb)
		if got:
			cb.add_child(UI.label("★ " + d["name"], 20, Color("c86a2a"), true))
			cb.add_child(UI.label(d["line"], 17))
		else:
			cb.add_child(UI.label("？？？", 20, Color(0.6, 0.55, 0.55), true))
			cb.add_child(UI.label("线索：" + d["hint"], 16, Color(0.55, 0.5, 0.5)))
		grid.add_child(card)
	pc.reset_size()
	await get_tree().process_frame
	if is_instance_valid(pc):
		pc.reset_size()
		pc.position = Vector2(640, 360) - pc.size * 0.5


func show_ending() -> void:
	_clear()
	game = Game.new()
	game.setup(self, Levels.LEVELS.size() - 1, true)
	add_child(game)
	var o := _overlay()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.15, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.position = Vector2(110, 120)
	o.add_child(vb)
	var lines := [
		["阿黄又看见了月亮。", 46],
		["一只猫只是猫。", 28],
		["一群猫，是会流的水，是一级级的台阶，", 28],
		["是填平沟的桥，也是一张会炸开的蹦床。", 28],
		["这些都没有写进规则——它们是“冒”出来的。", 24],
	]
	for i in lines.size():
		var l := UI.label(lines[i][0], lines[i][1], Color.WHITE, i == 0)
		l.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.3, 0.7))
		l.add_theme_constant_override("outline_size", 6)
		l.modulate.a = 0.0
		vb.add_child(l)
		var tw := create_tween()
		tw.tween_interval(0.8 + 1.1 * float(i))
		tw.tween_property(l, "modulate:a", 1.0, 0.9)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.modulate.a = 0.0
	vb.add_child(hb)
	var b1 := UI.button("喵态图鉴  %d / %d" % [data["found"].size(), Discover.LIST.size()], 20)
	b1.pressed.connect(func(): audio.play("click"); show_notebook("title"))
	hb.add_child(b1)
	var b2 := UI.button("回到标题", 20)
	b2.pressed.connect(func(): audio.play("click"); show_title())
	hb.add_child(b2)
	var tw2 := create_tween()
	tw2.tween_interval(6.6)
	tw2.tween_property(hb, "modulate:a", 1.0, 0.8)
	audio.chime([72, 76, 79, 84, 79, 84, 88])
