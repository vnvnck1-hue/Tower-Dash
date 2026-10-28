## Debug settings panel: one row of toggle buttons per preset group, the active one is
## highlighted. Choices persist in user://settings.cfg and are restored on launch.
## Toggle with F10 or ` (backquote). Tab is swallowed by the GUI focus navigation once a
## panel button has focus, so it never reached _unhandled_input reliably.
class_name DebugPanel
extends CanvasLayer

signal changed(group: String, index: int)

const SAVE_PATH := "user://settings.cfg"
var _groups := {}      # group -> [label, options, buttons]
var _values := {}
var _panel: PanelContainer


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.name = "PanelContainer"
	_panel.position = Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.09, 0.82)
	sb.border_color = Color(0.5, 0.45, 0.8, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.name = "VB"
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)
	var title := Label.new()
	title.text = "DEBUG SETTINGS   [F10] or [`] hide/show   (saved automatically)"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.75, 0.72, 1.0))
	vb.add_child(title)


func add_group(key: String, label: String, options: Array, default_index: int) -> void:
	var vb: VBoxContainer = _panel.get_node("VB")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	var buttons := []
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func() -> void: set_value(key, i, true))
		row.add_child(b)
		buttons.append(b)
	vb.add_child(row)
	_groups[key] = [label, options, buttons]
	_values[key] = default_index
	_refresh(key)


func set_value(key: String, index: int, emit := true) -> void:
	_values[key] = index
	_refresh(key)
	if emit:
		changed.emit(key, index)
	save()


func get_value(key: String) -> int:
	return _values.get(key, 0)


func _refresh(key: String) -> void:
	var buttons: Array = _groups[key][2]
	for i in buttons.size():
		var b: Button = buttons[i]
		b.set_pressed_no_signal(i == _values[key])
		b.modulate = Color(1.0, 0.95, 0.6) if i == _values[key] else Color(0.75, 0.75, 0.85)
		b.text = ("> " if i == _values[key] else "") + str(_groups[key][1][i])


func save() -> void:
	var cf := ConfigFile.new()
	for k in _values:
		cf.set_value("presets", k, _values[k])
	cf.set_value("ui", "visible", _panel.visible)
	cf.save(SAVE_PATH)


## Restore saved values (call after all groups are added); emits changed for each.
func load_saved() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for k in _values:
		if cf.has_section_key("presets", k):
			var v: int = int(cf.get_value("presets", k))
			if v >= 0 and v < _groups[k][1].size():
				_values[k] = v
				_refresh(k)
				changed.emit(k, v)
	_panel.visible = bool(cf.get_value("ui", "visible", true))


func _input(event: InputEvent) -> void:
	# _input (not _unhandled_input) so the toggle works even while a panel button holds focus
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F10 or event.keycode == KEY_QUOTELEFT):
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()
		save()
