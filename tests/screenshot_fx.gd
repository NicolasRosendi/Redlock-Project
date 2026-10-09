extends Node
## Capturas de cerca: dragón de energía y cara/pelo de los jugadores.
## Uso: xvfb-run godot --path . --rendering-method gl_compatibility --fixed-fps 60 \
##        res://tests/screenshot_fx.tscn -- --out=/ruta

var m: Match
var frame := 0
var out_dir := "user://"
var dummy: Node3D
var cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	GameConfig.control_mode = GameConfig.ControlMode.PRO
	GameConfig.team_size = 7
	m = load("res://scenes/match.tscn").instantiate()
	add_child(m)
	dummy = Node3D.new()
	m.add_child(dummy)
	cam = Camera3D.new()
	cam.fov = 50.0
	m.add_child(cam)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _physics_process(dt: float) -> void:
	frame += 1
	var t := frame / 60.0
	if frame == 40:
		cam.make_current()
		EnergyDragon.spawn(m, dummy, Color(1.0, 0.35, 0.1), Color(1.0, 0.85, 0.45), 1.3, 30.0)
		EnergyDragon.spawn(m, dummy, Color(0.2, 0.55, 1.0), Color(0.6, 0.95, 1.0), 0.9, 30.0, Vector3(0, 0, 5))
	if frame >= 40 and frame < 200:
		dummy.position = Vector3(-8.0 + (frame - 40) * 0.12, 2.0 + sin(t * 3.0) * 1.0, sin(t * 2.0) * 2.5)
		cam.position = Vector3(dummy.position.x - 2.0, 3.5, 9.0)
		cam.look_at(dummy.position + Vector3(-2.0, 0, 1.0))
	match frame:
		150:
			_shot("f1_dragones")
		200:
			var h := m.human.player
			h.position = Vector3(0, 0, 0)
			h.facing = Vector3.BACK
			cam.position = Vector3(0.5, 1.9, 1.5)
			cam.look_at(Vector3(0, 1.7, 0))
		204:
			_shot("f2_cara_jugador")
		205:
			var p2 := m.teams[1].players[4]
			p2.position = Vector3(2, 0, -1)
			p2.facing = Vector3(-0.3, 0, 1).normalized()
			cam.position = Vector3(2.2, 1.6, 1.8)
			cam.look_at(Vector3(2.0, 1.3, -1.0))
		209:
			_shot("f3_jugador_rival")
			get_tree().quit()
