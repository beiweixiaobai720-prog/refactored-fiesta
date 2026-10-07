extends RefCounted
## 喵态 · 界面样式（奶油底、珊瑚橙、暖棕字）

const CREAM := Color("fff6ea")
const CREAM_D := Color("f6e6d2")
const CORAL := Color("f2876b")
const CORAL_D := Color("d9694f")
const INK := Color("4a3431")
const INK_L := Color("8a6c66")
const LIQ := Color("f5a35a")
const SOL := Color("7d9ee6")
const GAS := Color("ec6a77")

static var font_body: Font = null
static var font_title: Font = null


static func load_fonts() -> void:
	if font_body == null:
		font_body = load("res://fonts/wenkai.ttf")
		font_title = load("res://fonts/kuaile.ttf")
		# 快乐体没有 ★ ✓ 之类的符号，缺字时借正文字体
		font_title.fallbacks = [font_body]


static func box(bg: Color, radius: int = 16, border: Color = Color(0, 0, 0, 0), bw: int = 0, pad: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.shadow_color = Color(0.3, 0.12, 0.1, 0.18)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	load_fonts()
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 20
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.45, 0.42, 0.6))
	t.set_stylebox("normal", "Button", box(CREAM, 14, CORAL, 2, 16))
	t.set_stylebox("hover", "Button", box(CORAL, 14, CORAL_D, 2, 16))
	t.set_stylebox("pressed", "Button", box(CORAL_D, 14, CORAL_D, 2, 16))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 14, Color(1, 1, 1, 0.0), 0, 16))
	t.set_stylebox("disabled", "Button", box(CREAM_D, 14, Color(0.8, 0.7, 0.65), 2, 16))
	t.set_stylebox("panel", "PanelContainer", box(Color(1.0, 0.97, 0.92, 0.95), 22, Color(0.95, 0.75, 0.65), 2, 22))
	return t


static func label(text: String, size: int = 20, col: Color = INK, title: bool = false) -> Label:
	load_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if title:
		l.add_theme_font_override("font", font_title)
	return l


static func button(text: String, size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


static func pill(bg: Color) -> StyleBoxFlat:
	var s := box(bg, 12, Color(0, 0, 0, 0), 0, 10)
	s.shadow_size = 0
	return s
