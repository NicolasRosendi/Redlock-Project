extends Node
## Captura imágenes de momentos clave (requiere renderizado real, p. ej. xvfb).
## Uso: xvfb-run godot --path . --rendering-method gl_compatibility --fixed-fps 60 \
##        res://tests/screenshot.tscn -- --out=/ruta

var m: Match
var frame := 0
var out_dir := "user://"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	GameConfig.control_mode = GameConfig.ControlMode.PRO
	GameConfig.team_size = 7
	GameConfig.awakening = 4
	GameConfig.camera_mode = 0
	m = load("res://scenes/match.tscn").instantiate()
	add_child(m)


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _setup_attack() -> void:
	var h := m.human.player
	m._set_phase(Match.Phase.PLAY)
	for p in m.players:
		p.frozen = false
	h.position = Vector3(m.hl - 22.0, 0, 5.0)
	m.ball.place(h.position)
	m.ball.set_carrier(h)
	h.restart_lock = false
	h.facing = Vector3.RIGHT
	h.energy = SkillDB.MAX_ENERGY


func _physics_process(_delta: float) -> void:
	frame += 1
	match frame:
		150:
			_shot("01_partido")
		160:
			# Con ventana, las pulsaciones simuladas no siempre caen en el mismo
			# frame de física: aquí se llama a la API directamente.
			_setup_attack()
			m.human.player.try_special("meteoro_descendente")
		166:
			_shot("02_corte_tecnica")
		185:
			_shot("03_meteoro_en_vuelo")
		520:
			_setup_attack()
			var h := m.human.player
			h.awakened = false
			h.awakening_id = "prediccion"
			h.try_special("despertar")
		523:
			_shot("04_despertar")
		560:
			var h2 := m.human.player
			m.ball.kick(h2, Vector3(6, 9, -3), "clear")
		572:
			_shot("05_prediccion")
		590:
			m.cam.toggle_mode()
		680:
			_shot("06_camara_detras")
			get_tree().quit()
