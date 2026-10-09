class_name KitEditor
extends Control
## Editor del kit de habilidades (antes del partido): 8 ranuras de técnicas
## (R2 + botón y R2 + L2 + botón) y el tipo de Despertar. Puedes llevar, por
## ejemplo, dos regates distintos o un tiro curvo y uno directo.

signal closed

const SLOTS := [
	["palette", "cross", "R2 + Cruz"], ["palette", "circle", "R2 + Círculo"],
	["palette", "triangle", "R2 + Triángulo"], ["palette", "square", "R2 + Cuadrado"],
	["palette_l2", "cross", "R2 + L2 + Cruz"], ["palette_l2", "circle", "R2 + L2 + Círculo"],
	["palette_l2", "triangle", "R2 + L2 + Triángulo"], ["palette_l2", "square", "R2 + L2 + Cuadrado"],
]

var _rows: Array[Button] = []
var _desc: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.05, 0.12)
	add_child(bg)
	var vb := VBoxContainer.new()
	vb.position = Vector2(90, 50)
	vb.custom_minimum_size = Vector2(720, 0)
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var title := Label.new()
	title.text = "KIT DE HABILIDADES"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.3, 0.9))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Equipa tus técnicas en la paleta R2 (y R2 + L2). Puedes repetir tipos: dos tiros, dos regates..."
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vb.add_child(sub)
	for i in SLOTS.size():
		if i == 4:
			var sep := HSeparator.new()
			sep.custom_minimum_size = Vector2(0, 10)
			vb.add_child(sep)
		_add_row(vb, i)
	_add_row(vb, -1)
	var reset := Button.new()
	reset.text = "Restablecer kit por defecto"
	reset.add_theme_font_size_override("font_size", 18)
	reset.pressed.connect(_reset)
	vb.add_child(reset)
	_rows.append(reset)
	var back := Button.new()
	back.text = "◀  Volver"
	back.add_theme_font_size_override("font_size", 24)
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(_close)
	vb.add_child(back)
	_rows.append(back)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.2, 0.9)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(860, 150)
	panel.custom_minimum_size = Vector2(640, 420)
	add_child(panel)
	_desc = RichTextLabel.new()
	_desc.bbcode_enabled = true
	_desc.fit_content = true
	_desc.add_theme_font_size_override("normal_font_size", 20)
	_desc.add_theme_font_size_override("bold_font_size", 30)
	panel.add_child(_desc)
	# Ficha del jugador: atributos (base del futuro modo carrera)
	var ficha := PanelContainer.new()
	ficha.add_theme_stylebox_override("panel", sb.duplicate())
	ficha.position = Vector2(860, 590)
	ficha.custom_minimum_size = Vector2(640, 0)
	add_child(ficha)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	ficha.add_child(grid)
	var st: Dictionary = GameConfig.profile["stats"]
	for key in GameConfig.STAT_NAMES:
		if key == "reflex":
			continue
		var l := Label.new()
		l.text = GameConfig.STAT_NAMES[key]
		l.custom_minimum_size = Vector2(110, 0)
		l.add_theme_font_size_override("font_size", 16)
		grid.add_child(l)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = float(st.get(key, 0.5)) * 100.0
		bar.custom_minimum_size = Vector2(170, 18)
		grid.add_child(bar)
	var hint := Label.new()
	hint.text = "Izq/Der: cambiar técnica · Círculo/Esc: volver"
	hint.position = Vector2(90, 850)
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	add_child(hint)
	for r in _rows:
		r.focus_entered.connect(_refresh)
	_refresh()


func open() -> void:
	visible = true
	_rows[0].grab_focus()
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if visible and e.is_action_pressed("ui_cancel"):
		accept_event()
		_close()


func _close() -> void:
	visible = false
	closed.emit()


func _add_row(vb: VBoxContainer, idx: int) -> void:
	var b := Button.new()
	b.set_meta("slot", idx)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(0, 42)
	b.pressed.connect(func() -> void: _change(idx, 1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left"):
			_change(idx, -1)
			b.accept_event()
		elif e.is_action_pressed("ui_right"):
			_change(idx, 1)
			b.accept_event())
	vb.add_child(b)
	_rows.append(b)


func _slot_value(idx: int) -> String:
	var s: Array = SLOTS[idx]
	return (GameConfig.profile[s[0]] as Dictionary).get(s[1], "")


func _change(idx: int, step: int) -> void:
	if idx < 0:
		GameConfig.awakening = posmod(GameConfig.awakening + step, SkillDB.AWAKENINGS.size())
		_refresh()
		return
	var s: Array = SLOTS[idx]
	var cur := _slot_value(idx)
	var i := SkillDB.KIT_ORDER.find(cur)
	var nxt: String = SkillDB.KIT_ORDER[posmod(i + step, SkillDB.KIT_ORDER.size())]
	# El despertar solo puede ocupar una ranura
	if nxt == "despertar":
		for j in SLOTS.size():
			if j != idx and _slot_value(j) == "despertar":
				(GameConfig.profile[SLOTS[j][0]] as Dictionary)[SLOTS[j][1]] = ""
	(GameConfig.profile[s[0]] as Dictionary)[s[1]] = nxt
	_refresh()


func _reset() -> void:
	GameConfig.profile["palette"] = SkillDB.DEFAULT_PALETTE.duplicate()
	GameConfig.profile["palette_l2"] = SkillDB.DEFAULT_PALETTE_L2.duplicate()
	_refresh()


func _refresh() -> void:
	var focused_text := ""
	for b in _rows:
		if not b.has_meta("slot"):
			continue
		var idx: int = b.get_meta("slot")
		if idx < 0:
			var a := SkillDB.awakening(GameConfig.awakening)
			b.text = "Tipo de despertar:  ‹ %s ›" % a["name"]
			if b.has_focus():
				focused_text = "[b][color=#%s]%s[/color][/b]\n\nTransformación (se activa con la técnica DESPERTAR, 3 barras, 20 s).\n\n%s" % [
					(a["color"] as Color).to_html(false), a["name"], a["desc"]]
			continue
		var sid := _slot_value(idx)
		var sd := SkillDB.special(sid)
		var label := "(vacía)" if sd.is_empty() else String(sd["name"])
		b.text = "%s:  ‹ %s ›" % [SLOTS[idx][2], label]
		if not sd.is_empty():
			b.add_theme_color_override("font_color", (sd["color"] as Color).lightened(0.3))
		else:
			b.remove_theme_color_override("font_color")
		if b.has_focus():
			if sd.is_empty():
				focused_text = "[b]Ranura vacía[/b]\n\nPulsa izquierda/derecha para equipar una técnica."
			else:
				focused_text = "[b][color=#%s]%s[/color][/b]\n%s · %d barra%s de energía\n\n%s" % [
					(sd["color"] as Color).to_html(false), sd["name"], SkillDB.KIND_NAMES[sd["kind"]],
					int(sd["bars"]), "" if int(sd["bars"]) == 1 else "s", sd["desc"]]
	_desc.text = focused_text
