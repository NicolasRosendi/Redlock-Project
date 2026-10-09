extends Node
## Capturas de regates y del aviso "!" de quite (requiere renderizado real).
## Uso: xvfb-run godot --path . --rendering-method gl_compatibility --fixed-fps 60 \
##        res://tests/screenshot_dribble.tscn -- --out=/ruta

var m: Match
var frame := 0
var out_dir := "user://"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	GameConfig.control_mode = GameConfig.ControlMode.PRO
	GameConfig.team_size = 7
	GameConfig.camera_mode = 1
	m = load("res://scenes/match.tscn").instantiate()
	add_child(m)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _setup() -> void:
	var h := m.human.player
	m._set_phase(Match.Phase.PLAY)
	for p in m.players:
		p.frozen = false
	h.restart_lock = false
	h.position = Vector3(5, 0, 2)
	h.facing = Vector3.RIGHT
	m.ball.place(h.position + Vector3.RIGHT * 0.5)
	m.ball.set_carrier(h)
	var d := m.teams[1].players[3]
	d.position = h.position + Vector3(2.2, 0, 0.3)
	d.facing = Vector3.LEFT


func _physics_process(_delta: float) -> void:
	frame += 1
	var h := m.human.player
	var d := m.teams[1].players[3]
	match frame:
		80:
			_setup()
			d.frozen = true
		81:
			d.frozen = false
			d.prepare_tackle("tackle", 0.4)
		88:
			_shot("d1_aviso_quite")
		95:
			h.do_dribble_flick(Vector3(0, 0, -1), false)
		99:
			_shot("d2_recorte")
		160:
			_setup()
			h.stamina = 100.0
			h.do_dribble_flick(Vector3(0, 0, 1), true)
		166:
			_shot("d3_elastica")
		220:
			_setup()
			d.frozen = true
			h.evade_until = m.time + 1.0
			d.position = h.position + Vector3(1.0, 0, 0)
			d.frozen = false
			d.do_tackle()
		232:
			_shot("d4_esquiva")
			get_tree().quit()
