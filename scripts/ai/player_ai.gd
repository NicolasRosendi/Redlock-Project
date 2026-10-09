class_name PlayerAI
extends RefCounted
## IA individual. Escribe intenciones en el Player según su rol y toma
## decisiones con un tiempo de reacción (depende de la dificultad).
## También expone `intent`, que el radar de Visión Espacial muestra al humano.

var p: Player
var m: Match
var decide_t := 0.0
var spot := Vector3.ZERO
var spot_t := 0.0
var run_until := 0.0
var run_point := Vector3.ZERO
var expect_until := 0.0
var intent := {}


func _init(player: Player) -> void:
	p = player
	m = player.m


func run_to(point: Vector3, seconds: float) -> void:
	run_point = point
	run_until = m.time + seconds


func expect_pass() -> void:
	expect_until = m.time + 3.0


func update(dt: float) -> void:
	p.move_dir = Vector3.ZERO
	p.want_sprint = false
	p.want_mark = false
	p.want_shield = false
	p.want_press = false
	p.has_look = false
	p.making_run = false
	p.path_boost = false
	intent = {}
	decide_t -= dt
	spot_t -= dt
	if p.frozen or m.phase == Match.Phase.GOAL or m.phase == Match.Phase.FULLTIME:
		_face_ball()
		return
	if p.role == Player.Role.GK:
		_goalkeeper(dt)
		return
	if p.has_ball():
		_carrier(dt)
		return
	var b := m.ball
	if b.carrier == null and b.pass_target == p and m.time < expect_until:
		_receive()
		return
	match p.team.ai.role_of(p):
		"chase":
			_chase()
		"receive":
			_receive()
		"press":
			_press()
		"cover":
			_cover()
		"mark":
			_mark()
		"support":
			_support()
		_:
			_zone()


# ---------------------------------------------------------------- movimiento

func _go(target: Vector3, sprint_dist := 7.0, slow_r := 1.5) -> void:
	var d := p.flat_to(target)
	var dist := d.length()
	if dist < 0.35:
		p.move_dir = Vector3.ZERO
		return
	p.move_dir = d / dist * clampf(dist / slow_r, 0.25, 1.0)
	p.want_sprint = dist > sprint_dist and p.stamina > 20.0


func _face_ball() -> void:
	p.has_look = true
	p.look_target = m.ball.position


func _formation_spot() -> Vector3:
	var t := p.team
	var b := m.ball.position
	var bp := t.progress(b.x)
	var bz := b.z / m.hw
	var attacking := t.has_ball() or (m.ball.carrier == null and m.ball.last_touch != null and m.ball.last_touch.team == t)
	var x := p.home.x + (bp - 0.5) * 0.6 + (0.1 if attacking else -0.04)
	match p.role:
		Player.Role.DEF:
			x = clampf(x, 0.08, 0.6 if attacking else 0.45)
			if not attacking:
				x = minf(x, maxf(bp - 0.03, 0.06))
		Player.Role.MID:
			x = clampf(x, 0.2, 0.78)
		Player.Role.FWD:
			x = clampf(x, 0.35, 0.9)
	if attacking and p.role != Player.Role.DEF:
		x = minf(x, m.offside_line(t) - 0.01)
	var z := p.home.y * (0.95 if attacking else 0.75) + bz * 0.35
	z = clampf(z, -0.92, 0.92)
	return t.field_point(x, z)


# ---------------------------------------------------------------- roles sin balón

func _zone() -> void:
	_go(_formation_spot(), 10.0)
	_face_ball()


func _chase() -> void:
	var ip := m.intercept_point(p)
	_go(ip["pos"], 2.0, 0.5)
	if Match.flat_dist(p.position, m.ball.position) > 2.0:
		p.want_sprint = p.stamina > 10.0
	p.path_boost = p.is_awakened_as("prediccion")
	intent = {"type": "chase", "pos": ip["pos"]}


func _receive() -> void:
	var b := m.ball
	var ip := m.intercept_point(p)
	_go(ip["pos"], 3.0, 0.6)
	_face_ball()
	p.path_boost = p.is_awakened_as("prediccion")
	# Remate de primera en centros y balones aéreos dentro del área
	if p.first_time.is_empty() and p.role != Player.Role.GK:
		var quality := _shot_quality(ip["pos"])
		var high := b.position.y > 1.0 or b.kick_kind == "cross"
		if quality > 0.45 and (high or randf() < 0.02) and Match.flat_dist(p.position, b.position) < 9.0:
			p.queue_first_time("shot")
	intent = {"type": "receive", "pos": ip["pos"]}


func _press() -> void:
	var c := m.ball.carrier
	if c == null:
		_zone()
		return
	var own := p.team.own_goal()
	var to_goal := (own - c.position)
	to_goal.y = 0.0
	to_goal = to_goal.normalized()
	var target := c.position + to_goal * 1.0 + c.velocity * 0.25
	_go(target, 4.0, 0.6)
	p.want_press = true
	p.has_look = true
	p.look_target = c.position
	var d := Match.flat_dist(p.position, c.position)
	intent = {"type": "press", "pos": c.position}
	if decide_t > 0.0 or not p.can_act():
		return
	decide_t = m.ai_reaction(p.team) * randf_range(0.8, 1.4)
	if d < 1.45:
		var r := randf()
		if r < m.ai_tackle_rate(p.team):
			p.do_tackle()
		elif r < m.ai_tackle_rate(p.team) + 0.1:
			p.do_shoulder()
	elif d < 3.0 and d > 1.6 and c.speed_h() > 5.0 and randf() < 0.07:
		p.do_slide()
	elif d > 3.0 and d < 9.0 and p.energy >= SkillDB.BAR and p.team.opponent.progress(c.position.x) > 0.65 \
			and randf() < 0.05 + 0.04 * m.ai_level(p.team):
		p.try_special("quite_relampago")


func _cover() -> void:
	var c := m.ball.carrier
	if c == null:
		_zone()
		return
	var own := p.team.own_goal()
	var dir := (own - c.position)
	dir.y = 0.0
	var target := c.position + dir.normalized() * minf(6.0, dir.length() * 0.5)
	_go(target, 6.0)
	_face_ball()


func _mark() -> void:
	var o: Player = p.team.ai.marks.get(p, null)
	if o == null:
		_zone()
		return
	var b := m.ball
	if b.carrier == null and b.pass_target == o:
		_go(m.intercept_point(p)["pos"], 1.0, 0.5)
		p.want_sprint = true
		p.want_mark = true
		return
	var own := p.team.own_goal()
	var target := o.position + (own - o.position).normalized() * 1.7
	var to_ball := (b.position - o.position)
	to_ball.y = 0.0
	if to_ball.length() > 0.1:
		target += to_ball.normalized() * 0.6
	_go(target, 5.0)
	_face_ball()
	if Match.flat_dist(p.position, target) < 1.2:
		p.want_mark = true


func _support() -> void:
	var t := p.team
	var c := m.ball.carrier
	if spot_t <= 0.0:
		spot_t = randf_range(0.5, 0.9)
		var base := _formation_spot()
		var best := base
		var best_s := -INF
		for i in 6:
			var cand := base
			if i > 0:
				cand += Vector3(randf_range(-7, 7), 0.0, randf_range(-7, 7))
			cand = m.clamp_in_field(cand, 2.0)
			var s := minf(_nearest_opp_dist(cand), 8.0) - 0.15 * Match.flat_dist(cand, base)
			if c != null and c.team == t:
				s += _lane_safety(c.position, cand) * 3.0
			if s > best_s:
				best_s = s
				best = cand
		spot = best
		if c != null and c.team == t and c != p and m.time > run_until + 2.0:
			var runner := p.role == Player.Role.FWD or (p.role == Player.Role.MID and randf() < 0.3)
			if runner and t.progress(c.position.x) > 0.3 and randf() < 0.3:
				var line := m.offside_line(t)
				run_point = t.field_point(minf(line + 0.12, 0.95), clampf(p.position.z / m.hw * 0.7, -0.6, 0.6))
				run_until = m.time + 2.2
	if m.time < run_until:
		p.making_run = true
		_go(run_point, 2.0)
		intent = {"type": "run", "pos": run_point}
	else:
		_go(spot, 9.0)
		_face_ball()


# ---------------------------------------------------------------- con balón

func _carrier(dt: float) -> void:
	var t := p.team
	var goal := t.opp_goal()
	var to_goal := p.flat_to(goal).normalized()
	var mv := _dribble_dir(to_goal)
	p.move_dir = mv
	p.want_sprint = _space_ahead(mv) > 7.0 and p.stamina > 30.0
	p.aim_dir = to_goal
	var best := _best_pass()
	var sq := _shot_quality(p.position)
	if best["target"] != null:
		intent = {"type": "pass", "pos": (best["target"] as Player).position, "score": best["score"]}
	if sq > 0.4:
		intent = {"type": "shot", "pos": goal, "score": sq}
	if not p.can_act() or p.charge_kind != "":
		return
	if decide_t > 0.0:
		return
	decide_t = m.ai_reaction(t) * randf_range(0.7, 1.3)

	if p.restart_lock:
		_restart_decision(best, sq)
		return

	var pr := _nearest_opp_dist(p.position)
	# El humano pidió el pase
	var req := t.pass_request
	if not req.is_empty() and m.time < float(req["until"]) and req["player"] != p:
		var rp: Player = req["player"]
		var through: bool = req["through"]
		if _pass_score(rp, through) > -0.3:
			t.pass_request = {}
			_do_pass(rp, through, _lane_safety(p.position, rp.position) < 0.3)
			return

	var shoot_thr := 0.62 - p.st("shot_power") * 0.12
	if sq > shoot_thr or (sq > 0.35 and pr < 1.5 and randf() < 0.5):
		_do_shot(sq)
		return
	if pr < 2.2:
		if best["target"] != null and best["score"] > 0.2 and randf() < 0.7:
			_do_pass(best["target"], best["through"], best["lob"])
			return
		if p.energy >= SkillDB.BAR and randf() < 0.06 * (1 + m.ai_level(t)):
			if p.try_special("regate_fantasma"):
				return
		if randf() < 0.3 + p.st("dribble") * 0.4:
			var opp := p.nearest_opponent()
			var away := p.flat_to(p.position * 2.0 - opp.position).normalized() if opp != null else to_goal
			var side := (away - to_goal * away.dot(to_goal)).normalized()
			var wdir := (to_goal * 0.3 + side).normalized() if side.length() > 0.1 else to_goal
			p.do_dribble_flick(wdir, p.stamina > 40.0 and randf() < 0.4)
			return
		if pr < 1.2:
			p.want_shield = true
		if best["target"] != null and best["score"] > -0.1:
			_do_pass(best["target"], best["through"], best["lob"])
			return
	elif best["target"] != null and best["score"] > 0.62:
		_do_pass(best["target"], best["through"], best["lob"])


func _restart_decision(best: Dictionary, sq: float) -> void:
	if m.phase != Match.Phase.PLAY or m.phase_time < 0.5:
		return
	var t := p.team
	match p.restart_kind:
		"penalty":
			if m.phase_time > 1.0:
				var z := (m.gw * 0.5 - 0.5) * (1.0 if randf() < 0.5 else -1.0)
				p.perform("shot", randf_range(0.55, 0.8), {"z": z})
		"corner":
			var target := t.opp_goal() - t.attack_dir() * randf_range(5.0, 11.0)
			target.z = randf_range(-m.gw, m.gw)
			p.perform("cross", 0.6, {"point": target})
		"free_kick":
			if sq > 0.3:
				_do_shot(sq)
			elif best["target"] != null:
				_do_pass(best["target"], false, false)
		_:
			if best["target"] != null:
				_do_pass(best["target"], false, best["lob"] or p.role == Player.Role.GK)
			else:
				var fwd := t.nearest_field_player(t.opp_goal())
				if fwd != null:
					_do_pass(fwd, false, true)


func _do_pass(target: Player, through: bool, lob: bool) -> void:
	var d := Match.flat_dist(p.position, target.position)
	var kind := "pass"
	if through:
		kind = "through_lob" if lob else "through"
	elif lob:
		kind = "pass_lob"
	var charge := clampf(d / 40.0, 0.2, 0.85)
	if p.energy >= SkillDB.BAR * 2.0 and not lob and d > 15.0 and randf() < 0.05 * (1 + m.ai_level(p.team)):
		if p.try_special("pase_meteoro"):
			return
	p.aim_dir = p.flat_to(target.position).normalized()
	p.perform(kind, charge, {"target": target})
	intent = {"type": "pass", "pos": target.position}


func _do_shot(sq: float) -> void:
	var t := p.team
	var gk := t.opponent.gk()
	var half := m.gw * 0.5
	var z := (half - 0.5) * (1.0 if randf() < 0.5 else -1.0)
	if gk != null:
		z = -signf(gk.position.z - p.position.z * 0.05) * (half - 0.5)
		if absf(gk.position.z) < 0.2:
			z = (half - 0.5) * (1.0 if randf() < 0.5 else -1.0)
	var d := Match.flat_dist(p.position, t.opp_goal())
	var charge := clampf(0.4 + d / 40.0 + randf_range(-0.08, 0.12), 0.35, 0.95)
	var bars := p.energy / SkillDB.BAR
	if bars >= 3.0 and sq > 0.45 and randf() < 0.25 + 0.1 * m.ai_level(t):
		if p.try_special("meteoro_descendente"):
			return
	if bars >= 2.0 and sq > 0.4 and randf() < 0.3 + 0.1 * m.ai_level(t):
		p.aim_dir = Vector3(0, 0, signf(z))
		if p.try_special("disparo_directo"):
			return
	var kind := "shot"
	if gk != null and Match.flat_dist(gk.position, t.opp_goal()) > 4.0 and d > 14.0 and randf() < 0.35:
		kind = "chip"
	elif d < 14.0 and randf() < 0.25:
		kind = "ground"
	p.perform(kind, charge, {"z": z})
	intent = {"type": "shot", "pos": t.opp_goal()}


# ---------------------------------------------------------------- portero

func _goalkeeper(dt: float) -> void:
	var t := p.team
	var g := t.own_goal()
	var b := m.ball
	if p.has_ball():
		p.gk_hold_time += dt
		_face_ball()
		p.look_target = t.opp_goal()
		if p.gk_hold_time > 1.1 and p.can_act() and m.phase == Match.Phase.PLAY:
			var best := _best_pass()
			if best["target"] != null and best["score"] > 0.15:
				_do_pass(best["target"], false, best["lob"])
			else:
				var fwd := t.nearest_field_player(t.opp_goal())
				if fwd != null:
					_do_pass(fwd, false, true)
		return
	p.gk_hold_time = 0.0
	if p.state != Player.State.NORMAL:
		return
	# Tiro hacia la portería
	if b.carrier == null:
		var cross := m.goal_crossing(t)
		if cross["hit"]:
			var hit := m.path_point_toward_goal(t, p.position.x)
			var plane: Vector3 = hit["pos"]
			if p.gk_reacted_kick != b.kick_id and m.time - b.kick_time > m.gk_reaction(t):
				p.gk_reacted_kick = b.kick_id
				var lat := absf(plane.z - p.position.z)
				if lat > 0.9 or plane.y > 2.0:
					p.start_dive(plane, float(hit["t"]) - 0.05)
					return
			_go(Vector3(p.position.x, 0, plane.z), 99.0, 0.3)
			_face_ball()
			return
		if m.in_box(t, b.position):
			var ip := m.intercept_point(p)
			if float(ip["t"]) < m.best_intercept_time(t.opponent) + 0.2:
				_go(ip["pos"], 1.0, 0.4)
				p.want_sprint = true
				return
	# Mano a mano
	var c := b.carrier
	if c != null and c.team != t and m.in_box(t, c.position) and Match.flat_dist(c.position, p.position) < 7.0:
		_go(c.position, 1.0, 0.5)
		_face_ball()
		if Match.flat_dist(c.position, p.position) < 1.9 and decide_t <= 0.0:
			decide_t = 0.4
			if randf() < 0.45:
				p.start_dive(c.position + c.facing * 0.6)
		return
	# Colocación en el arco
	var to_ball := b.position - g
	to_ball.y = 0.0
	var dist := to_ball.length()
	var off := clampf(dist * 0.1, 0.6, 3.5)
	var pos := g + to_ball.normalized() * off
	pos.z = clampf(pos.z, -m.gw * 0.5 + 0.3, m.gw * 0.5 - 0.3)
	_go(pos, 5.0, 1.0)
	_face_ball()


# ---------------------------------------------------------------- evaluación

func _nearest_opp_dist(pos: Vector3) -> float:
	var d := INF
	for o in p.team.opponent.players:
		d = minf(d, Match.flat_dist(o.position, pos))
	return d


func _space_ahead(dir: Vector3) -> float:
	var d := 30.0
	for o in p.team.opponent.players:
		var rel := p.flat_to(o.position)
		var ahead := rel.dot(dir)
		if ahead > 0.0 and (rel - dir * ahead).length() < 3.0:
			d = minf(d, ahead)
	return d


func _shot_quality(pos: Vector3) -> float:
	var t := p.team
	var g := t.opp_goal()
	var d := Match.flat_dist(pos, g)
	var max_range := 30.0 * clampf(m.hl / 52.5, 0.6, 1.0)
	if d > max_range:
		return 0.0
	var a := Vector3(g.x, 0, -m.gw * 0.5) - pos
	var bb := Vector3(g.x, 0, m.gw * 0.5) - pos
	a.y = 0.0
	bb.y = 0.0
	var ang := a.angle_to(bb)
	var angle_score := clampf(ang / 0.5, 0.0, 1.0)
	var dist_score := clampf(1.0 - (d - 8.0) / (max_range - 8.0), 0.0, 1.0)
	var dir := Vector3(g.x - pos.x, 0, g.z - pos.z).normalized()
	var block := 0.0
	for o in t.opponent.players:
		if o.role == Player.Role.GK:
			continue
		var to_o := o.position - pos
		to_o.y = 0.0
		var proj := to_o.dot(dir)
		if proj > 0.0 and proj < d:
			if (to_o - dir * proj).length() < 1.1:
				block += 0.3
	return angle_score * 0.55 + dist_score * 0.6 - block


func _lane_safety(from: Vector3, to: Vector3) -> float:
	var seg := to - from
	seg.y = 0.0
	var len := seg.length()
	if len < 0.1:
		return 1.0
	var dir := seg / len
	var worst := INF
	for o in p.team.opponent.players:
		var rel := o.position - from
		rel.y = 0.0
		var proj := rel.dot(dir)
		if proj < len * 0.05 or proj > len * 0.95:
			continue
		var perp := (rel - dir * proj).length()
		var reach := 0.6 + proj * 0.08
		worst = minf(worst, perp - reach)
	return clampf(worst / 2.5, 0.0, 1.0)


func _pass_score(t: Player, through: bool) -> float:
	var from := p.position
	var to := t.position
	if through:
		to = m.clamp_in_field(to + t.team.attack_dir() * 6.0, 2.0)
	var d := Match.flat_dist(from, to)
	if d < 3.5 or d > 45.0 * clampf(m.hl / 52.5, 0.6, 1.0):
		return -INF
	var lane := _lane_safety(from, to)
	var space := clampf((_nearest_opp_dist(to) - 1.0) / 5.0, 0.0, 1.0)
	var prog := (t.team.progress(to.x) - t.team.progress(from.x)) * 2.0 * m.hl / 20.0
	prog = clampf(prog, -0.6, 1.0)
	var s := lane * 0.5 + space * 0.35 + prog * 0.45
	if d > 28.0:
		s -= (d - 28.0) * 0.02
	if t.role == Player.Role.GK:
		s -= 0.6
	if through and not t.making_run:
		s -= 0.3
	if t.is_human:
		s += 0.08
	return s


func _best_pass() -> Dictionary:
	var best := {"target": null, "score": -INF, "through": false, "lob": false}
	for t in p.team.players:
		if t == p:
			continue
		for through in [false, true]:
			if through and not t.making_run:
				continue
			var s := _pass_score(t, through)
			if s > float(best["score"]):
				var to := t.position
				var lane := _lane_safety(p.position, to)
				var lob := lane < 0.3 and Match.flat_dist(p.position, to) > 12.0
				best = {"target": t, "score": s, "through": through, "lob": lob}
	return best


func _dribble_dir(goal_dir: Vector3) -> Vector3:
	var d := goal_dir
	var perp := goal_dir.cross(Vector3.UP)
	for o in p.team.opponent.players:
		var rel := p.flat_to(o.position)
		var dist := rel.length()
		if dist > 7.0 or dist < 0.01:
			continue
		if rel.dot(goal_dir) < -1.0:
			continue
		var side := signf(perp.dot(rel))
		if side == 0.0:
			side = 1.0
		d -= perp * side * (2.0 / dist)
	if absf(p.position.z) > m.hw - 3.0:
		d.z -= signf(p.position.z) * 1.5
	d.y = 0.0
	return d.normalized()
