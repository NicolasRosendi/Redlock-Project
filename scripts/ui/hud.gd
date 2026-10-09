class_name Hud
extends CanvasLayer
## HUD del partido: marcador, reloj, avisos, banners de técnicas y goles,
## estamina/energía, paleta R2, radar, ayuda de controles, pausa y final.

const HELP_TEXT := """[b]CONTROLES[/b]  (mando PlayStation · teclado entre corchetes)

[b]Movimiento[/b]
Stick izq. [WASD] mover · R1 [Shift] correr
L2 [Q] marcar / contener (con balón: proteger)
L1 [E] presionar al rival · con balón: modificador de picar

[b]Ataque[/b]
Cruz [K] pase raso (mantener = más fuerte) · L1+Cruz pase bombeado
Triángulo [I] pase al hueco · L1+Triángulo al hueco por arriba
Círculo [L] centro
Cuadrado [J] tiro (mantener = potencia) · L1+Cuadrado vaselina
Cuadrado dos veces: tiro raso · Tiro + Cruz rápido: amague (cancelar)
Stick der. [flechas] regates · con L2: regates mejorados
  adelante: toque largo / sombrero · lado: recorte / elástica
  atrás: arrastre / ruleta

[b]Defensa[/b]
Círculo [L] quite · Cuadrado [J] barrida · Cruz [K] cargar con el cuerpo
Balón suelto cerca: Cuadrado/Cruz = remate o pase de primera (cabezazo/volea)
R3 [R] cambiar de jugador (modo Equipo)

[b]Técnicas (gastan energía)[/b]
R2+Cruz Pase Meteoro · R2+Círculo Quite Relámpago
R2+Triángulo Regate Fantasma · R2+Cuadrado Disparo Directo
R2+L2+Cuadrado Meteoro Descendente · R2+L2+Círculo DESPERTAR

[b]Otros[/b]
Cruceta izq/der [1/2] tipo de despertar · arriba [3] energía al máximo (debug)
Select [C] cámara · Start [Esc] pausa · abajo [H] esta ayuda"""

var m: Match
var _score: Label
var _clock: Label
var _feed: VBoxContainer
var _banner: Label
var _banner_sub: Label
var _speed: ColorRect
var _speed_mat: ShaderMaterial
var _bars: HudWidgets.Bars
var _palette: HudWidgets.Palette
var _radar: HudWidgets.Radar
var _charge: HudWidgets.Charge
var _help: PanelContainer
var _pause: PanelContainer
var _end: PanelContainer
var _end_label: Label
var _hint: Label
var _banner_t0 := -100000
var _banner_hold := 1.0
var _speed_t0 := -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_speed = ColorRect.new()
	_speed.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_mat = ShaderMaterial.new()
	_speed_mat.shader = load("res://shaders/speed_lines.gdshader")
	_speed.material = _speed_mat
	root.add_child(_speed)

	# Marcador
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style(Color(0.02, 0.04, 0.1, 0.8), 10))
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-210, 12)
	top.custom_minimum_size = Vector2(420, 0)
	root.add_child(top)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 18)
	top.add_child(hb)
	_score = _label("AZUL 0 - 0 ROJO", 28)
	_clock = _label("0'", 24)
	_clock.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	hb.add_child(_score)
	hb.add_child(_clock)

	_feed = VBoxContainer.new()
	_feed.position = Vector2(20, 20)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)

	_banner = _label("", 64)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position = Vector2(-600, -150)
	_banner.size = Vector2(1200, 90)
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_banner.pivot_offset = Vector2(600, 45)
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	_banner_sub = _label("", 26)
	_banner_sub.set_anchors_preset(Control.PRESET_CENTER)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.position = Vector2(-600, -65)
	_banner_sub.size = Vector2(1200, 40)
	_banner_sub.add_theme_constant_override("outline_size", 8)
	_banner_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_banner_sub.modulate.a = 0.0
	root.add_child(_banner_sub)

	_bars = HudWidgets.Bars.new()
	_bars.m = m
	_bars.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bars.position = Vector2(20, -170)
	_bars.size = Vector2(330, 150)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bars)

	_palette = HudWidgets.Palette.new()
	_palette.m = m
	_palette.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_palette.position = Vector2(-420, -300)
	_palette.size = Vector2(400, 280)
	_palette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_palette)

	_radar = HudWidgets.Radar.new()
	_radar.m = m
	_radar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_radar.position = Vector2(-360, 20)
	_radar.size = Vector2(340, 340.0 * m.hw / m.hl * 0.5 + 40.0)
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_radar)

	_charge = HudWidgets.Charge.new()
	_charge.m = m
	_charge.size = Vector2(90, 12)
	_charge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_charge)

	_hint = _label("Cruceta abajo / H: controles", 14)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-150, -30)
	_hint.size = Vector2(300, 20)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.modulate = Color(1, 1, 1, 0.6)
	root.add_child(_hint)

	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", _style(Color(0.02, 0.04, 0.1, 0.92), 14))
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.position = Vector2(-380, -330)
	_help.custom_minimum_size = Vector2(760, 660)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = HELP_TEXT
	rt.fit_content = true
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 18)
	_help.add_child(rt)
	_help.visible = false
	root.add_child(_help)

	_pause = _menu_panel("PAUSA", [["Continuar", _resume], ["Reiniciar partido", _restart], ["Controles", _toggle_help], ["Menú principal", _to_menu]])
	root.add_child(_pause)
	_end = _menu_panel("FINAL DEL PARTIDO", [["Jugar otra vez", _restart], ["Menú principal", _to_menu]])
	_end_label = _label("", 24)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(_end.get_child(0) as VBoxContainer).add_child(_end_label)
	(_end.get_child(0) as VBoxContainer).move_child(_end_label, 1)
	root.add_child(_end)

	m.notified.connect(_on_notify)
	if m.human == null:
		_bars.visible = false
		_palette.visible = false


func _process(_delta: float) -> void:
	if m == null:
		return
	_animate_real_time()
	var t0 := m.teams[0]
	var t1 := m.teams[1]
	_score.text = "%s %d - %d %s" % [t0.short_name, t0.score, t1.score, t1.short_name]
	var mins := int(m.clock / m.duration * 90.0)
	_clock.text = "%d'" % mins
	if Input.is_action_just_pressed("help"):
		_toggle_help()
	if Input.is_action_just_pressed("pause") and m.phase != Match.Phase.FULLTIME:
		if get_tree().paused:
			_resume()
		else:
			_open_pause()
	elif Input.is_action_just_pressed("ui_cancel") and _help.visible and not get_tree().paused:
		_help.visible = false


func show_special(title: String, who: String, col: Color) -> void:
	_show_banner(title, who, col, 1.1)
	_speed_mat.set_shader_parameter("line_color", Color(col.r, col.g, col.b, 0.85))
	_speed_t0 = Time.get_ticks_msec()


## Las animaciones del HUD usan tiempo real para no ralentizarse con la
## cámara lenta de las técnicas.
func _animate_real_time() -> void:
	var now := Time.get_ticks_msec()
	var bt := (now - _banner_t0) / 1000.0
	var a := 0.0
	var sc := 1.0
	if bt < 0.18:
		a = bt / 0.18
		sc = lerpf(1.6, 1.0, ease(bt / 0.18, 0.4))
	elif bt < 0.18 + _banner_hold:
		a = 1.0
	elif bt < 0.48 + _banner_hold:
		a = 1.0 - (bt - 0.18 - _banner_hold) / 0.3
	_banner.modulate.a = a
	_banner_sub.modulate.a = a
	_banner.scale = Vector2(sc, sc)
	var st := (now - _speed_t0) / 1000.0
	var inten := 0.0
	if st < 0.55:
		inten = 1.0
	elif st < 0.9:
		inten = 1.0 - (st - 0.55) / 0.35
	_speed_mat.set_shader_parameter("intensity", inten)
	_speed.visible = inten > 0.0
	for l in _feed.get_children():
		var age := (now - int(l.get_meta("t0", now))) / 1000.0
		if age > 2.7:
			l.queue_free()
		elif age > 2.2:
			(l as Control).modulate.a = 1.0 - (age - 2.2) / 0.5


func show_goal(t: Team, scorer_name: String) -> void:
	_show_banner("¡GOOOOL!", "%s · %s" % [scorer_name, t.team_name], t.color.lightened(0.35), 2.4)


func flash_energy() -> void:
	_bars.flash = 1.0


func show_full_time() -> void:
	var t0 := m.teams[0]
	var t1 := m.teams[1]
	var res := "Empate"
	if t0.score != t1.score:
		res = "Gana %s" % (t0.team_name if t0.score > t1.score else t1.team_name)
	var s := m.stats
	_end_label.text = "%s %d - %d %s\n%s\n\nTiros %d (%d al arco) · Pases %d/%d · Quites %d\nIntercepciones %d · Atajadas %d · Técnicas %d · Regates %d" % [
		t0.short_name, t0.score, t1.score, t1.short_name, res,
		s["shots"], s["on_target"], s["passes_done"], s["passes"], s["tackles"],
		s["interceptions"], s["saves"], s["specials"], s["dribbles"]]
	_end.visible = true
	_focus_first(_end)


func _show_banner(text: String, sub: String, col: Color, hold: float) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner_sub.text = sub
	_banner_hold = hold
	_banner_t0 = Time.get_ticks_msec()


func _on_notify(text: String, col: Color) -> void:
	var l := _label(text, 18)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	l.set_meta("t0", Time.get_ticks_msec())


func _toggle_help() -> void:
	_help.visible = not _help.visible


func _open_pause() -> void:
	get_tree().paused = true
	_pause.visible = true
	_focus_first(_pause)


func _resume() -> void:
	get_tree().paused = false
	_pause.visible = false
	_help.visible = false


func _restart() -> void:
	m.restart_match()


func _to_menu() -> void:
	get_tree().paused = false
	FX.reset()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _focus_first(panel: Control) -> void:
	for c in panel.find_children("*", "Button", true, false):
		(c as Button).grab_focus()
		return


func _menu_panel(title: String, items: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.04, 0.1, 0.94), 16))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-260, -200)
	panel.custom_minimum_size = Vector2(520, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var t := _label(title, 34)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(0, 48)
		b.pressed.connect(it[1])
		vb.add_child(b)
	panel.visible = false
	return panel


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style(c: Color, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(10)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s
