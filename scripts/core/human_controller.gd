class_name HumanController
extends RefCounted
## Traduce el mando a acciones del jugador. Toda la lógica de botones vive
## aquí para poder ajustar el "feel" en un solo sitio.
##
##   Stick izq.  mover            R1  correr          L1  presionar / picar
##   L2          marcar/proteger  R2  paleta de técnicas (+L2: paleta alterna)
##   Cruz        pase             Cuadrado  tiro (mantener = potencia)
##   Triángulo   pase al hueco    Círculo   centro / quite
##   Stick der.  regates (con L2: regates mejorados)

var m: Match
var team: Team
var player: Player = null
var preview_target: Player = null
var _flick_ready := true
var _switch_cd := 0.0
var _palette := {}
var _palette_l2 := {}


func _init(match_ref: Match, t: Team, p: Player) -> void:
	m = match_ref
	team = t
	_palette = GameConfig.profile["palette"]
	_palette_l2 = GameConfig.profile["palette_l2"]
	switch_to(p)


func switch_to(p: Player) -> void:
	if p == player or p == null:
		return
	if player != null:
		player.set_human(false)
		player.charge_kind = ""
	player = p
	player.set_human(true)
	player.awakening_id = SkillDB.awakening(GameConfig.awakening)["id"] if not player.awakened else player.awakening_id
	_switch_cd = 0.6


func is_team_mode() -> bool:
	return GameConfig.control_mode == GameConfig.ControlMode.TEAM


func palette_for(l2: bool) -> Dictionary:
	return _palette_l2 if l2 else _palette


func update(dt: float) -> void:
	if player == null:
		return
	_switch_cd -= dt
	var p := player
	var b := m.ball
	p.has_look = false
	p.want_mark = false
	p.want_shield = false
	p.want_press = false
	p.path_boost = false
	preview_target = null

	var stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := m.cam.stick_to_world(stick)
	var r1 := Input.is_action_pressed("sprint")
	var l2 := Input.is_action_pressed("mark")
	var l1 := Input.is_action_pressed("press")
	var r2 := Input.is_action_pressed("power")
	p.move_dir = dir
	p.want_sprint = r1
	p.aim_dir = dir.normalized() if dir.length() > 0.2 else p.facing

	if Input.is_action_just_pressed("awaken_next"):
		_cycle_awakening(1)
	if Input.is_action_just_pressed("awaken_prev"):
		_cycle_awakening(-1)
	if Input.is_action_just_pressed("debug_energy"):
		p.energy = SkillDB.MAX_ENERGY
		p.stamina = p.stamina_cap
		m.notify("DEBUG: energía al máximo", Color(0.6, 1.0, 0.6))

	if m.phase == Match.Phase.KICKOFF or m.phase == Match.Phase.GOAL or m.phase == Match.Phase.FULLTIME:
		p.move_dir = Vector3.ZERO
		return

	var has_ball := b.carrier == p
	var opp_has := b.carrier != null and b.carrier.team != p.team
	var mate_has := b.carrier != null and b.carrier.team == p.team and not has_ball

	# Movimiento asistido sin balón
	if has_ball:
		p.want_shield = l2
		if not r2:
			preview_target = p.team.find_pass_target(p, p.aim_dir, false)
	else:
		if l2:
			p.want_mark = true
			var focus := b.carrier.position if b.carrier != null else b.position
			p.has_look = true
			p.look_target = focus
			if stick.length() < 0.2 and opp_has:
				# Contención automática: colocarse entre el rival y nuestro arco
				var own := p.team.own_goal()
				var guard := focus + (own - focus).normalized() * 1.8
				var to := p.flat_to(guard)
				p.move_dir = to.normalized() * clampf(to.length(), 0.0, 1.0) if to.length() > 0.2 else Vector3.ZERO
		if l1 and (opp_has or b.carrier == null):
			p.want_press = true
			var target: Vector3
			if opp_has:
				var own2 := p.team.own_goal()
				target = b.carrier.position + (own2 - b.carrier.position).normalized() * 0.9
			else:
				target = m.intercept_point(p)["pos"]
			var to2 := p.flat_to(target)
			if to2.length() > 0.3:
				p.move_dir = to2.normalized()

	_prediction_assist(p)

	if r2:
		if p.charge_kind != "":
			p.charge_kind = ""
		var pal := palette_for(l2)
		for btn in ["cross", "circle", "triangle", "square"]:
			if Input.is_action_just_pressed("btn_" + btn):
				var sid: String = pal.get(btn, "")
				if sid != "":
					p.try_special(sid)
				elif p.is_human:
					m.notify("Ranura libre (personalizable)", Color(0.7, 0.7, 0.75))
	else:
		_buttons(p, has_ball, opp_has, mate_has, l1)

	_dribble_flicks(p, has_ball, l2)
	_switching(p, opp_has, has_ball)


func _buttons(p: Player, has_ball: bool, opp_has: bool, mate_has: bool, l1: bool) -> void:
	var jp_x := Input.is_action_just_pressed("btn_cross")
	var jr_x := Input.is_action_just_released("btn_cross")
	var jp_sq := Input.is_action_just_pressed("btn_square")
	var jr_sq := Input.is_action_just_released("btn_square")
	var jp_tri := Input.is_action_just_pressed("btn_triangle")
	var jr_tri := Input.is_action_just_released("btn_triangle")
	var jp_ci := Input.is_action_just_pressed("btn_circle")
	var jr_ci := Input.is_action_just_released("btn_circle")

	# Cancelaciones (amague) y tiro raso con doble toque
	var shot_kinds := ["shot", "chip"]
	var pass_kinds := ["pass", "pass_lob", "through", "through_lob", "cross"]
	if p.is_charging(shot_kinds) or p.is_winding(shot_kinds + ["ground"]):
		if jp_x:
			p.cancel_kick()
			return
		if jp_sq and p.is_winding(["shot"]):
			p.convert_to_ground_shot()
			return
	if (p.is_charging(pass_kinds) or p.is_winding(pass_kinds)) and jp_sq:
		p.cancel_kick()
		return

	if not p.first_time.is_empty():
		if jr_sq or jr_x or jr_tri or jr_ci:
			p.first_time["released"] = m.time

	if has_ball:
		if jp_x:
			p.begin_charge("pass_lob" if l1 else "pass")
		elif jr_x and p.is_charging(["pass", "pass_lob"]):
			p.release_charge()
		if jp_tri:
			p.begin_charge("through_lob" if l1 else "through")
		elif jr_tri and p.is_charging(["through", "through_lob"]):
			p.release_charge()
		if jp_ci:
			p.begin_charge("cross")
		elif jr_ci and p.is_charging(["cross"]):
			p.release_charge()
		if jp_sq and not p.is_winding(["shot", "ground"]):
			p.begin_charge("chip" if l1 else "shot")
		elif jr_sq and p.is_charging(shot_kinds):
			p.release_charge()
	elif mate_has:
		# Modo Pro: pedir el balón
		if jp_x or jp_sq:
			p.team.request_pass(p, false)
			m.notify("¡Pásala!", Color(1.0, 0.9, 0.4))
		if jp_tri:
			p.team.request_pass(p, true)
			m.notify("¡Al hueco!", Color(1.0, 0.9, 0.4))
	elif opp_has:
		if jp_ci:
			p.do_tackle()
		if jp_sq:
			p.do_slide()
		if jp_x:
			p.do_shoulder()
	else:
		# Balón suelto: remates y pases de primera si viene hacia mí
		var near := Match.flat_dist(p.position, m.ball.position) < 9.0
		if jp_sq:
			if near:
				p.queue_first_time("shot")
			else:
				p.do_slide()
		if jp_x and near:
			p.queue_first_time("pass_lob" if l1 else "pass")
		if jp_tri and near:
			p.queue_first_time("through")
		if jp_ci:
			if near and m.ball.position.y > 0.6:
				p.queue_first_time("cross")
			else:
				p.do_tackle()


func _dribble_flicks(p: Player, has_ball: bool, l2: bool) -> void:
	var rs := Input.get_vector("dribble_left", "dribble_right", "dribble_up", "dribble_down")
	if rs.length() < 0.3:
		_flick_ready = true
	elif rs.length() > 0.75 and _flick_ready:
		_flick_ready = false
		if has_ball:
			var w := m.cam.stick_to_world(rs)
			if w.length() > 0.1:
				p.do_dribble_flick(w.normalized(), l2)


func _switching(p: Player, opp_has: bool, has_ball: bool) -> void:
	if not is_team_mode() or has_ball:
		return
	if Input.is_action_just_pressed("switch_player"):
		var best := _best_defender(true)
		if best != null:
			switch_to(best)
		return
	if _switch_cd > 0.0 or p.state != Player.State.NORMAL:
		return
	if Input.is_action_pressed("btn_circle") or Input.is_action_pressed("press") or Input.is_action_pressed("mark"):
		return
	var b := m.ball
	if not opp_has and b.carrier != null:
		return
	var my_t: float = m.intercept_point(p)["t"] if b.carrier == null else Match.flat_dist(p.position, b.position) / p.top_speed()
	var best2 := _best_defender(false)
	if best2 == null or best2 == p:
		return
	var their_t: float = m.intercept_point(best2)["t"] if b.carrier == null else Match.flat_dist(best2.position, b.position) / best2.top_speed()
	if my_t - their_t > 1.0:
		switch_to(best2)


func _best_defender(exclude_current: bool) -> Player:
	var b := m.ball
	var best: Player = null
	var bd := INF
	for q in team.players:
		if q.role == Player.Role.GK or (exclude_current and q == player):
			continue
		var d := Match.flat_dist(q.position, b.position)
		if d < bd:
			bd = d
			best = q
	return best


func _cycle_awakening(step: int) -> void:
	if player.awakened:
		m.notify("No puedes cambiarlo durante el despertar", Color(0.7, 0.7, 0.75))
		return
	GameConfig.awakening = posmod(GameConfig.awakening + step, SkillDB.AWAKENINGS.size())
	var a := SkillDB.awakening(GameConfig.awakening)
	player.awakening_id = a["id"]
	m.notify("Despertar: %s" % a["name"], a["color"])


## Metavisión Predictiva: calcula el punto ideal y acelera si sigues la ruta.
func _prediction_assist(p: Player) -> void:
	m.prediction_target = Vector3.ZERO
	m.prediction_active = false
	if not p.is_awakened_as("prediccion"):
		return
	var b := m.ball
	var target: Vector3
	if b.carrier == null:
		target = m.intercept_point(p)["pos"]
	elif b.carrier.team != p.team:
		target = b.carrier.position + b.carrier.velocity * 0.6
	else:
		return
	m.prediction_active = true
	m.prediction_target = target
	var to := p.flat_to(target)
	if to.length() > 0.8 and p.speed_h() > 1.0:
		var v := Vector3(p.velocity.x, 0.0, p.velocity.z).normalized()
		p.path_boost = v.dot(to.normalized()) > 0.9
