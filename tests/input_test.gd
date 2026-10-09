extends Node
## Simula pulsaciones del mando sobre el jugador humano y verifica que cada
## mecánica responda: pase, tiro con carga, tiro raso (doble toque), amague,
## vaselina, regates, técnicas R2, despertar, quites y estamina.
## Uso: godot --headless --path . --fixed-fps 60 res://tests/input_test.tscn

var m: Match
var step := -1
var t := 0
var failures := 0
var held: Array[String] = []
var log_lines: Array[String] = []

const STEPS := [
	"pass", "shot", "ground_shot", "feint", "chip", "dribble_cut", "dribble_elastic", "sombrero",
	"special_shot", "special_pass", "special_dribble", "awaken", "meteoro", "tackle", "special_tackle", "stamina",
]


func _ready() -> void:
	GameConfig.control_mode = GameConfig.ControlMode.PRO
	GameConfig.team_size = 7
	GameConfig.awakening = 0
	m = load("res://scenes/match.tscn").instantiate()
	add_child(m)


func _press(a: String) -> void:
	Input.action_press(a, 1.0)
	held.append(a)


func _release(a: String) -> void:
	Input.action_release(a)
	held.erase(a)


func _release_all() -> void:
	for a in held.duplicate():
		_release(a)


func _check(name: String, ok: bool, info := "") -> void:
	print("%s %s %s" % ["OK  " if ok else "FAIL", name, info])
	if not ok:
		failures += 1


func _setup_attack() -> void:
	var h := m.human.player
	var b := m.ball
	for p in m.players:
		p.frozen = p != h and p.role != Player.Role.GK
		p._set_state(Player.State.NORMAL)
		p.velocity = Vector3.ZERO
	var opp_gk := m.teams[1].gk()
	opp_gk.position = Vector3(m.hl - 1.0, 0, 0)
	m._set_phase(Match.Phase.PLAY)
	h.restart_lock = false
	h.position = Vector3(m.hl - 17.0, 0, 3.0)
	h.facing = Vector3.RIGHT
	h.stamina = 100.0
	h.stamina_cap = 100.0
	b.place(h.position + Vector3.RIGHT * 0.5)
	b.set_carrier(h)
	# Un compañero libre para los pases
	var mate := m.teams[0].players[4]
	mate.frozen = true
	mate.position = Vector3(m.hl - 12.0, 0, -8.0)


func _physics_process(_dt: float) -> void:
	Engine.time_scale = 1.0
	if m.phase == Match.Phase.KICKOFF and step < 0:
		return
	if step < 0:
		step = 0
		t = 0
	if step >= STEPS.size():
		print("FAILURES: %d" % failures)
		get_tree().quit()
		return
	var h := m.human.player
	var b := m.ball
	var name: String = STEPS[step]
	if t == 0:
		_release_all()
		_setup_attack()
	t += 1
	var done := false
	match name:
		"pass":
			if t == 2: _press("btn_cross")
			if t == 6: _release("btn_cross")
			if t == 30:
				_check("pase con Cruz", b.kick_kind == "pass" and b.carrier != h, "kind=%s" % b.kick_kind)
				done = true
		"shot":
			if t == 2: _press("move_right"); _press("btn_square")
			if t == 40: _release("btn_square")
			if t == 60:
				_check("tiro con carga (Cuadrado)", b.kick_kind == "shot" and b.velocity.length() > 18.0, "v=%.1f" % b.velocity.length())
				done = true
		"ground_shot":
			if t == 2: _press("btn_square")
			if t == 5: _release("btn_square")
			if t == 8: _press("btn_square")
			if t == 10: _release("btn_square")
			if t == 30:
				_check("tiro raso (doble toque)", b.kick_kind == "shot" and b.position.y < 0.2 and absf(b.velocity.y) < 0.5, "y=%.2f vy=%.2f" % [b.position.y, b.velocity.y])
				done = true
		"feint":
			if t == 2: _press("btn_square")
			if t == 12: _press("btn_cross")
			if t == 30:
				_check("amague (tiro + pase cancela)", b.carrier == h and m.stats["feints"] >= 1 and h.state == Player.State.NORMAL, "feints=%d" % m.stats["feints"])
				done = true
		"chip":
			if t == 2: _press("press"); _press("btn_square")
			if t == 30: _release("btn_square")
			if t == 52:
				_check("vaselina (L1 + Cuadrado)", b.kick_kind == "shot" and b.velocity.y > 3.0 and b.position.y > 1.0, "vy=%.1f y=%.1f" % [b.velocity.y, b.position.y])
				done = true
		"dribble_cut":
			if t == 2: _press("dribble_up")
			if t == 4:
				_check("recorte (stick derecho lateral)", h.state == Player.State.SKILL and h.is_evading())
			if t == 6: _release("dribble_up")
			if t == 40:
				_check("conserva el balón tras recorte", b.carrier == h)
				done = true
		"dribble_elastic":
			if t == 2: _press("mark")
			if t == 3: _press("dribble_down")
			if t == 5:
				_check("elástica (L2 + stick derecho)", h.state == Player.State.SKILL and absf(float(h.skill["speed"]) - 2.5 / 0.36) < 0.1)
			if t == 10:
				done = true
		"sombrero":
			if t == 2: _press("mark")
			if t == 3: _press("dribble_right")
			if t == 8:
				_check("sombrero (L2 + stick adelante)", b.carrier == null and b.position.y > 0.4 and b.kick_kind == "knock", "y=%.2f" % b.position.y)
				done = true
		"special_shot":
			if t == 1: h.energy = SkillDB.MAX_ENERGY
			if t == 2: _press("power")
			if t == 3: _press("btn_square")
			if t == 40:
				_check("R2 + Cuadrado = Disparo Directo", b.special_id == "disparo_directo" and h.energy <= SkillDB.MAX_ENERGY - 200.0 + 30.0, "special=%s energy=%.0f" % [b.special_id, h.energy])
				done = true
		"special_pass":
			if t == 1: h.energy = SkillDB.MAX_ENERGY
			if t == 2: _press("power")
			if t == 3: _press("btn_cross")
			if t == 30:
				_check("R2 + Cruz = Pase Meteoro", b.special_id == "pase_meteoro" or (b.carrier != null and b.carrier != h and b.carrier.team == h.team), "special=%s" % b.special_id)
				done = true
		"special_dribble":
			if t == 1: h.energy = SkillDB.MAX_ENERGY
			if t == 2: _press("power")
			if t == 3: _press("btn_triangle")
			if t == 6:
				_check("R2 + Triángulo = Regate Fantasma", h.phantom_until > m.time and h.is_evading())
				done = true
		"awaken":
			if t == 1: h.energy = SkillDB.MAX_ENERGY; h.awakened = false
			if t == 2: _press("power"); _press("mark")
			if t == 3: _press("btn_circle")
			if t == 6:
				_check("R2 + L2 + Círculo = Despertar", h.awakened and h.awakening_id == "tiro", "id=%s" % h.awakening_id)
				done = true
		"meteoro":
			if t == 1: h.energy = SkillDB.MAX_ENERGY
			if t == 2: _press("power"); _press("mark")
			if t == 3: _press("btn_square")
			if t == 40:
				_check("R2 + L2 + Cuadrado = Meteoro Descendente", b.special_id == "meteoro_descendente", "special=%s" % b.special_id)
				done = true
		"tackle":
			if t == 1:
				var opp := m.teams[1].players[3]
				opp.frozen = false
				opp.position = h.position + Vector3.RIGHT * 1.2
				opp.facing = Vector3.RIGHT
				b.place(opp.position + Vector3.RIGHT * 0.4)
				b.set_carrier(opp)
				h.facing = Vector3.RIGHT
			if t == 2: _press("btn_circle")
			if t == 4:
				_check("Círculo sin balón = quite", h.state == Player.State.TACKLE)
				done = true
		"special_tackle":
			if t == 1:
				h.energy = SkillDB.MAX_ENERGY
				var opp2 := m.teams[1].players[3]
				opp2.position = h.position + Vector3(7.0, 0, 2.0)
				b.place(opp2.position + Vector3.RIGHT * 0.4)
				b.set_carrier(opp2)
				opp2.phantom_until = 0.0
				opp2.evade_until = 0.0
			if t == 2: _press("power")
			if t == 3: _press("btn_circle")
			if t == 50:
				_check("R2 + Círculo = Quite Relámpago roba", b.carrier == h, "carrier=%s" % (b.carrier.player_name if b.carrier else "nadie"))
				done = true
		"stamina":
			if t == 1:
				b.place(Vector3(0, 0, 20))
				h.stamina = 100.0
				h.stamina_cap = 100.0
			if t == 2: _press("sprint"); _press("move_right")
			if t == 300: _release("sprint"); _release("move_right")
			if t == 301:
				log_lines.append("tras 5 s esprintando: estamina %.1f tope %.1f" % [h.stamina, h.stamina_cap])
			if t == 900:
				var ok := h.stamina < 100.0 and h.stamina >= h.stamina_cap - 0.5 and h.stamina_cap < 100.0
				_check("estamina: recupera solo hasta el tope", ok, "%s → descanso 10 s: %.1f / tope %.1f" % [log_lines[-1], h.stamina, h.stamina_cap])
				done = true
	if done:
		step += 1
		t = 0
