extends Node
## Capturas de animaciones y avisos (barrida, caída, estirada, carrera, mira).
## Uso: xvfb-run godot --path . --rendering-method gl_compatibility --fixed-fps 60 \
##        res://tests/screenshot_anim.tscn -- --out=/ruta

var m: Match
var frame := 0
var out_dir := "user://"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	GameConfig.control_mode = GameConfig.ControlMode.PRO
	GameConfig.team_size = 7
	GameConfig.camera_mode = 0
	m = load("res://scenes/match.tscn").instantiate()
	add_child(m)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _physics_process(_delta: float) -> void:
	frame += 1
	var h := m.human.player
	var opp := m.teams[1].players[3]
	match frame:
		80:
			m._set_phase(Match.Phase.PLAY)
			for p in m.players:
				p.frozen = false
			h.restart_lock = false
			h.position = Vector3(5, 0, 2)
			m.ball.place(h.position + Vector3.RIGHT * 0.5)
			m.ball.set_carrier(h)
			Input.action_press("move_right")
			Input.action_press("sprint")
		130:
			_shot("a1_conduccion_carrera")
		140:
			Input.action_release("sprint")
			Input.action_release("move_right")
			h.begin_charge("shot")
		185:
			_shot("a2_mira_tiro")
		190:
			h.charge_kind = ""
			h.position = Vector3(10, 0, 0)
			opp.position = Vector3(14, 0, 0.5)
			opp.facing = Vector3.LEFT
			m.ball.place(opp.position + Vector3.LEFT * 0.5)
			m.ball.set_carrier(opp)
			h.facing = Vector3.RIGHT
			h.do_slide()
		203:
			_shot("a3_barrida")
		240:
			opp.stun(1.5, true)
			FX.popup(opp.position, "¡QUITE!", Color(0.6, 0.8, 1.0))
		262:
			_shot("a4_caida_y_aviso")
		300:
			var gk := m.teams[1].gk()
			gk.start_dive(gk.position + Vector3(0, 1.6, 2.8), 0.4)
		318:
			m.cam.toggle_mode()
		322:
			_shot("a5_estirada_portero")
			get_tree().quit()
