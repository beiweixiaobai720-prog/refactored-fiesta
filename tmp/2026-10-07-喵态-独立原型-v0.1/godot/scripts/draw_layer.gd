extends Node2D
## 通用绘制层：把 _draw 交给外部回调

var drawer: Callable


func _draw() -> void:
	if drawer.is_valid():
		drawer.call(self)
