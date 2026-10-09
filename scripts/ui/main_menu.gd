extends Control
## Menú principal: opciones de la partida de prueba. Navegable con mando
## (cruceta/stick + Cruz) o teclado. Izquierda/derecha cambian el valor.

var _rows: Array[Button] = []
var _desc: Label
var _pad_label: Label
var _main: Control
var _kit: KitEditor


func _ready() -> void:
	FX.reset()
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.05, 0.12)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.color = Color(0.85, 0.12, 0.18, 0.85)
	stripe.position = Vector2(-200, 640)
	stripe.size = Vector2(2600, 14)
	stripe.rotation = -0.18
	add_child(stripe)

	_main = Control.new()
	_main.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_main)
	var vb := VBoxContainer.new()
	vb.position = Vector2(110, 70)
	vb.custom_minimum_size = Vector2(640, 0)
	vb.add_theme_constant_override("separation", 10)
	_main.add_child(vb)

	var title := Label.new()
	title.text = "REDLOCK"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.3, 0.9))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Prototipo de gameplay · fútbol arcade con técnicas especiales"
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vb.add_child(sub)
	vb.add_child(_spacer(20))

	_add_row(vb, "control")
	_add_row(vb, "size")
	_add_row(vb, "awakening")
	_add_row(vb, "difficulty")
	_add_row(vb, "duration")
	_add_row(vb, "camera")
	var kit := Button.new()
	kit.text = "★  Kit de habilidades…"
	kit.alignment = HORIZONTAL_ALIGNMENT_LEFT
	kit.add_theme_font_size_override("font_size", 22)
	kit.custom_minimum_size = Vector2(0, 46)
	kit.pressed.connect(_open_kit)
	vb.add_child(kit)
	_rows.append(kit)
	vb.add_child(_spacer(10))
	var play := Button.new()
	play.text = "▶  JUGAR"
	play.add_theme_font_size_override("font_size", 30)
	play.custom_minimum_size = Vector2(0, 64)
	play.pressed.connect(_play)
	vb.add_child(play)
	_rows.append(play)
	var quit := Button.new()
	quit.text = "Salir"
	quit.add_theme_font_size_override("font_size", 20)
	quit.pressed.connect(func() -> void: get_tree().quit())
	vb.add_child(quit)
	_rows.append(quit)

	_desc = Label.new()
	_desc.position = Vector2(820, 300)
	_desc.size = Vector2(680, 300)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 20)
	_desc.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_main.add_child(_desc)
	_pad_label = Label.new()
	_pad_label.position = Vector2(820, 220)
	_pad_label.add_theme_font_size_override("font_size", 18)
	_main.add_child(_pad_label)
	var hint := Label.new()
	hint.text = "Cruceta/stick: navegar · Izq/Der: cambiar · Cruz/Enter: aceptar"
	hint.position = Vector2(110, 840)
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_main.add_child(hint)
	_kit = KitEditor.new()
	_kit.visible = false
	_kit.closed.connect(_close_kit)
	add_child(_kit)

	for r in _rows:
		r.focus_entered.connect(_refresh)
	_rows[_rows.size() - 2].grab_focus()
	_refresh()


func _process(_delta: float) -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_pad_label.text = "Sin mando detectado (se puede jugar con teclado)"
		_pad_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	else:
		_pad_label.text = "Mando: %s" % Input.get_joy_name(pads[0])
		_pad_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _add_row(vb: VBoxContainer, key: String) -> void:
	var b := Button.new()
	b.set_meta("key", key)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(func() -> void: _change(key, 1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left"):
			_change(key, -1)
			b.accept_event()
		elif e.is_action_pressed("ui_right"):
			_change(key, 1)
			b.accept_event())
	vb.add_child(b)
	_rows.append(b)


func _change(key: String, step: int) -> void:
	match key:
		"control":
			GameConfig.control_mode = posmod(GameConfig.control_mode + step, 3)
		"size":
			var i := GameConfig.TEAM_SIZES.find(GameConfig.team_size)
			GameConfig.team_size = GameConfig.TEAM_SIZES[posmod(i + step, GameConfig.TEAM_SIZES.size())]
		"awakening":
			GameConfig.awakening = posmod(GameConfig.awakening + step, SkillDB.AWAKENINGS.size())
		"difficulty":
			GameConfig.difficulty = posmod(GameConfig.difficulty + step, 3)
		"duration":
			var j := GameConfig.DURATIONS.find(GameConfig.match_minutes)
			GameConfig.match_minutes = GameConfig.DURATIONS[posmod(j + step, GameConfig.DURATIONS.size())]
		"camera":
			GameConfig.camera_mode = posmod(GameConfig.camera_mode + step, 2)
	_refresh()


func _refresh() -> void:
	var desc := ""
	for b in _rows:
		if not b.has_meta("key"):
			continue
		var key: String = b.get_meta("key")
		match key:
			"control":
				b.text = "Modo:  ‹ %s ›" % GameConfig.CONTROL_NAMES[GameConfig.control_mode]
			"size":
				b.text = "Formato:  ‹ %dvs%d ›" % [GameConfig.team_size, GameConfig.team_size]
			"awakening":
				b.text = "Despertar:  ‹ %s ›" % SkillDB.awakening(GameConfig.awakening)["name"]
			"difficulty":
				b.text = "Dificultad IA:  ‹ %s ›" % GameConfig.DIFFICULTIES[GameConfig.difficulty]
			"duration":
				b.text = "Duración:  ‹ %d min ›" % int(GameConfig.match_minutes)
			"camera":
				b.text = "Cámara:  ‹ %s ›" % GameConfig.CAMERA_NAMES[GameConfig.camera_mode]
		if b.has_focus():
			match key:
				"control":
					desc = ["Controlas solo a tu delantero creado (estilo Blue Lock / Be a Pro). Con Cruz pides el pase a tus compañeros.",
						"Controlas a todo el equipo: el control salta al jugador con balón o al mejor defensor. R3 cambia manualmente.",
						"La IA juega contra la IA. Útil para observar el sistema."][GameConfig.control_mode]
				"awakening":
					desc = SkillDB.awakening(GameConfig.awakening)["desc"] + "\n\nSe activa con la técnica DESPERTAR del kit (3 barras de energía)."
				"size":
					desc = "El tamaño de la cancha y de los arcos se ajusta al formato."
				"difficulty":
					desc = "Afecta reflejos, quites y atajadas del rival."
	_desc.text = desc


func _open_kit() -> void:
	_main.visible = false
	_kit.open()


func _close_kit() -> void:
	_main.visible = true
	for r in _rows:
		if r.text.begins_with("★"):
			r.grab_focus()
	_refresh()


func _play() -> void:
	get_tree().change_scene_to_file("res://scenes/match.tscn")
