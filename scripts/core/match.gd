class_name Match
extends Node3D
## Gestor del partido: construye el estadio, los equipos y el balón; ordena el
## bucle de simulación; resuelve toques, intercepciones, atajadas, goles,
## saques y faltas; y avisa al HUD/FX de lo que pasa.

signal notified(text: String, color: Color)
signal special_used(player: Player, sid: String)
signal goal_scored(team: Team, scorer: Player)

enum Phase { KICKOFF, PLAY, RESTART, GOAL, FULLTIME, HALFTIME }

const PATH_STEP := 0.05
const PATH_TIME := 3.0

const SIZES := {
	3: {"len": 40.0, "wid": 26.0, "gw": 5.0, "gh": 2.0},
	5: {"len": 50.0, "wid": 32.0, "gw": 6.0, "gh": 2.2},
	7: {"len": 68.0, "wid": 44.0, "gw": 7.32, "gh": 2.44},
	11: {"len": 105.0, "wid": 68.0, "gw": 7.32, "gh": 2.44},
}

## Formaciones: (progreso hacia el arco rival 0..1, carril -1..1).
const FORMATIONS := {
	3: [[0.03, 0.0, 0], [0.38, -0.35, 2], [0.55, 0.3, 3]],
	5: [[0.03, 0.0, 0], [0.25, -0.45, 1], [0.25, 0.45, 1], [0.45, 0.0, 2], [0.62, 0.0, 3]],
	7: [[0.03, 0.0, 0], [0.22, -0.5, 1], [0.2, 0.0, 1], [0.22, 0.5, 1], [0.42, -0.35, 2], [0.42, 0.35, 2], [0.62, 0.0, 3]],
	11: [[0.03, 0.0, 0], [0.2, -0.65, 1], [0.17, -0.22, 1], [0.17, 0.22, 1], [0.2, 0.65, 1],
		[0.4, -0.4, 2], [0.36, 0.0, 2], [0.4, 0.4, 2], [0.62, -0.55, 3], [0.66, 0.0, 3], [0.62, 0.55, 3]],
}

const NAMES_HOME := ["Kuon", "Raichi", "Igaguri", "Gagamaru", "Aryu", "Naruhaya", "Imamura", "Tokimitsu", "Kunigami", "Chigiri", "Bachira", "Barou", "Nagi", "Reo"]
const NAMES_AWAY := ["Sendou", "Oliveira", "Kaiser", "Ness", "Lorenzo", "Snuffy", "Aiku", "Shidou", "Ryusei", "Karasu", "Otoya", "Yukimiya", "Hiori", "Niko"]

var hl := 34.0
var hw := 22.0
var gw := 7.32
var gh := 2.44
var gdepth := 2.0
var box_d := 16.5
var box_w := 40.3
var spot_d := 11.0
var circle_r := 9.15

var time := 0.0
var clock := 0.0
var duration := 300.0
## Dos tiempos con descuento. `half_clock` son segundos reales del tiempo actual.
var half := 1
var half_clock := 0.0
var half_len := 150.0
var added_min := 0
var _stoppage := 0.0
var _first_kickoff := 0
var phase: int = Phase.KICKOFF
var phase_time := 0.0
var fatigue_rate := 0.12
var difficulty := 1

var teams: Array[Team] = []
var players: Array[Player] = []
var ball: Ball
var human: HumanController
var cam: CameraRig
var hud: Hud
var ball_path := PackedVector3Array()
var prediction_active := false
var prediction_target := Vector3.ZERO
var stats := {
	"passes": 0, "passes_done": 0, "shots": 0, "on_target": 0, "goals": 0, "tackles": 0,
	"interceptions": 0, "saves": 0, "outs": 0, "fouls": 0, "specials": 0, "skill_moves": 0,
	"dribbles": 0, "feints": 0, "woodwork": 0, "headers": 0, "tackle_attempts": 0, "evades": 0, "resists": 0,
	"corners": 0, "throw_ins": 0, "goal_kicks": 0,
}

var _pass_marker: MeshInstance3D
var _space_marker: MeshInstance3D
var _aim_reticle: MeshInstance3D
var _pred_markers: Array[MeshInstance3D] = []
var _land_marker: MeshInstance3D
var _crowd_mat: ShaderMaterial
var _kickoff_team := 0
var _woodwork_cd := 0.0
var _restart := {}


func _ready() -> void:
	randomize()
	FX.reset()
	FX.world = self
	difficulty = GameConfig.difficulty
	duration = GameConfig.match_minutes * 60.0
	half_len = duration * 0.5
	fatigue_rate = 0.12 * clampf(5.0 / GameConfig.match_minutes, 0.4, 1.6)
	_setup_dims(GameConfig.team_size)
	_build_world()
	ball = Ball.new()
	ball.m = self
	add_child(ball)
	_build_teams(GameConfig.team_size)
	if GameConfig.control_mode != GameConfig.ControlMode.AI_ONLY:
		var start := _pick_human_start(teams[0])
		human = HumanController.new(self, teams[0], start)
	cam = CameraRig.new()
	cam.m = self
	add_child(cam)
	_build_markers()
	hud = Hud.new()
	hud.m = self
	add_child(hud)
	_kickoff(0)


func _exit_tree() -> void:
	FX.reset()
	FX.world = null


# ---------------------------------------------------------------- utilidades

static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func clamp_in_field(p: Vector3, margin: float) -> Vector3:
	return Vector3(clampf(p.x, -hl + margin, hl - margin), p.y, clampf(p.z, -hw + margin, hw - margin))


func in_box(t: Team, pos: Vector3) -> bool:
	var gx := -t.attack_sign * hl
	return absf(pos.x - gx) <= box_d and absf(pos.z) <= box_w * 0.5 and signf(pos.x) == signf(gx)


func notify(text: String, color := Color.WHITE) -> void:
	notified.emit(text, color)


func ai_level(t: Team) -> int:
	if human != null and t != human.team:
		return difficulty
	return 1


func ai_reaction(t: Team) -> float:
	return [0.42, 0.3, 0.2][ai_level(t)]


func ai_tackle_rate(t: Team) -> float:
	return [0.28, 0.42, 0.55][ai_level(t)]


func tackle_bonus(t: Team) -> float:
	return [-0.08, 0.0, 0.06][ai_level(t)]


## Cuánto tarda la IA entre anunciar un quite ("!") y ejecutarlo.
func ai_telegraph(t: Team) -> float:
	if human == null or t == human.team:
		return 0.12
	return [0.28, 0.2, 0.14][ai_level(t)]


func gk_reaction(t: Team) -> float:
	return [0.26, 0.18, 0.11][ai_level(t)]


func gk_bonus(t: Team) -> float:
	return [-0.1, 0.0, 0.08][ai_level(t)]


## Línea de fuera de juego aproximada (en progreso del equipo atacante).
func offside_line(t: Team) -> float:
	var progs: Array[float] = []
	for o in t.opponent.players:
		progs.append(t.progress(o.position.x))
	progs.sort()
	var second_last := progs[progs.size() - 2] if progs.size() >= 2 else 1.0
	return maxf(maxf(second_last, t.progress(ball.position.x)), 0.5)


## Primer punto de la trayectoria prevista alcanzable por el jugador a tiempo.
func intercept_point(p: Player) -> Dictionary:
	var spd := p.top_speed()
	if ball.carrier != null:
		var d0 := flat_dist(p.position, ball.position)
		return {"pos": ball.position, "t": d0 / spd}
	var n := ball_path.size()
	for i in n:
		var bp := ball_path[i]
		if bp.y - p.height > 2.2:
			continue
		var t := (i + 1) * PATH_STEP
		var need := flat_dist(p.position, bp) / spd + 0.12
		if need <= t:
			return {"pos": bp, "t": t}
	if n > 0:
		var last := ball_path[n - 1]
		return {"pos": last, "t": n * PATH_STEP + flat_dist(p.position, last) / spd}
	return {"pos": ball.position, "t": flat_dist(p.position, ball.position) / spd}


func best_intercept_time(t: Team) -> float:
	var best := INF
	for p in t.players:
		if p.state == Player.State.STUN:
			continue
		best = minf(best, float(intercept_point(p)["t"]))
	return best


## ¿La trayectoria prevista termina dentro del arco del equipo t?
func goal_crossing(t: Team) -> Dictionary:
	var s := -t.attack_sign
	if ball.velocity.x * s < 4.0:
		return {"hit": false}
	for i in ball_path.size():
		var bp := ball_path[i]
		if bp.x * s >= hl:
			var hit := absf(bp.z) < gw * 0.5 + 0.6 and bp.y < gh + 0.4
			return {"hit": hit, "pos": bp, "t": (i + 1) * PATH_STEP}
	return {"hit": false}


## Punto (y tiempo) en que el balón alcanza la coordenada x camino al arco de t.
func path_point_toward_goal(t: Team, x: float) -> Dictionary:
	var s := -t.attack_sign
	for i in ball_path.size():
		var bp := ball_path[i]
		if bp.x * s >= x * s:
			return {"pos": bp, "t": (i + 1) * PATH_STEP}
	if ball_path.size() > 0:
		return {"pos": ball_path[ball_path.size() - 1], "t": PATH_TIME}
	return {"pos": ball.position, "t": 0.0}


# ---------------------------------------------------------------- bucle

func _physics_process(dt: float) -> void:
	time += dt
	phase_time += dt
	_woodwork_cd -= dt
	match phase:
		Phase.KICKOFF:
			if phase_time > 1.0:
				for p in players:
					p.frozen = false
				_set_phase(Phase.PLAY)
		Phase.RESTART:
			if phase_time > 0.8:
				_set_phase(Phase.PLAY)
		Phase.GOAL:
			if phase_time > 3.2:
				_kickoff(_kickoff_team)
		Phase.HALFTIME:
			if phase_time > 4.0:
				_start_second_half()
		Phase.PLAY:
			_restart_watchdog()
	if phase == Phase.PLAY or phase == Phase.RESTART:
		clock += dt
		half_clock += dt
		if added_min == 0 and half_clock >= half_len - 0.3:
			# Descuento según faltas, corners, goles y saques del tiempo
			added_min = clampi(roundi(1.0 + _stoppage), 1, 6)
			notify("+%d minuto%s de descuento" % [added_min, "" if added_min == 1 else "s"], Color(1.0, 0.85, 0.35))
			if hud != null:
				hud.show_added_time(added_min)
		if added_min > 0 and half_clock >= half_len + added_min * duration / 90.0 and phase == Phase.PLAY:
			if half == 1:
				_half_time()
			else:
				_full_time()
	_enforce_restart_distance()

	if ball.carrier == null:
		ball_path = ball.predict(PATH_TIME, PATH_STEP)
	else:
		ball_path = PackedVector3Array()

	if human != null:
		human.update(dt)
	for t in teams:
		t.ai.update(dt)
	for p in players:
		p.tick(dt)
	_separate_players()

	if ball.carrier != null:
		ball.carry(dt)
		if absf(ball.position.x) > hl or absf(ball.position.z) > hw:
			var c := ball.carrier
			if not c.restart_lock:
				ball.kick(c, ball.carry_vel, "carry")
	if ball.carrier == null:
		var was_in := ball.in_goal
		# Subpasos para que un tiro fuerte no atraviese el palo
		var n := clampi(ceili(ball.velocity.length() * dt / 0.08), 1, 8)
		for _i in n:
			ball.step(dt / n)
			ball.collide_goal(1.0, hl, gw, gh, gdepth)
			ball.collide_goal(-1.0, hl, gw, gh, gdepth)
		if phase == Phase.PLAY or phase == Phase.RESTART:
			if not was_in and ball.in_goal:
				_goal(signf(ball.position.x))
			elif not ball.in_goal:
				_resolve_touches()
	if (phase == Phase.PLAY or phase == Phase.RESTART) and not ball.in_goal and ball.carrier == null:
		_check_out()
	elif phase == Phase.PLAY and ball.carrier != null and not ball.carrier.restart_lock:
		_check_out()
	_update_markers()


func clock_text() -> String:
	var base := 0 if half == 1 else 45
	var mins := half_clock / half_len * 45.0
	if mins <= 45.0:
		return "%d'" % (base + int(mins))
	return "%d+%d'" % [base + 45, ceili(mins - 45.0)]


func add_stoppage(display_minutes: float) -> void:
	_stoppage += display_minutes


func _half_time() -> void:
	_set_phase(Phase.HALFTIME)
	FX.reset()
	for p in players:
		p.charge_kind = ""
		p.pending = {}
		p.velocity = Vector3.ZERO
		p.frozen = true
	notify("Entretiempo", Color(1.0, 0.85, 0.35))
	if hud != null:
		hud.show_banner("ENTRETIEMPO", "%s %d - %d %s" % [teams[0].short_name, teams[0].score, teams[1].score, teams[1].short_name], Color(1.0, 0.85, 0.35), 3.0)


## Segundo tiempo: se cambia de lado y se recupera parte de la estamina.
func _start_second_half() -> void:
	half = 2
	half_clock = 0.0
	added_min = 0
	_stoppage = 0.0
	for t in teams:
		t.attack_sign = -t.attack_sign
	for p in players:
		p.stamina_cap = minf(100.0, p.stamina_cap + (100.0 - p.stamina_cap) * 0.6)
		p.stamina = p.stamina_cap
	notify("Segundo tiempo · estamina recuperada", Color(0.6, 1.0, 0.7))
	_kickoff(1 - _first_kickoff)


## Durante un saque, los rivales respetan la distancia mínima (y en el saque
## del medio cada equipo se queda en su campo).
func _enforce_restart_distance() -> void:
	if _restart.is_empty():
		return
	var taker: Player = _restart["taker"]
	if not taker.restart_lock:
		return
	var kind: String = _restart["kind"]
	var spot := Vector3(ball.position.x, 0.0, ball.position.z)
	var k := clampf(hl / 52.5, 0.5, 1.0)
	var r := 9.15 * k
	match kind:
		"kickoff":
			r = circle_r + 0.3
		"throw_in":
			r = 4.0
		"goal_kick":
			r = 0.0
	for t in teams:
		for p in t.players:
			if p == taker:
				continue
			var opp := t != taker.team
			if kind == "kickoff":
				# Todos en su propio campo
				if t.progress(p.position.x) > 0.495:
					p.position.x = t.field_point(0.495, 0.0).x
			if not opp:
				continue
			if kind == "penalty" and p.role == Player.Role.GK:
				continue
			if kind == "goal_kick" or kind == "penalty":
				var box_team: Team = taker.team if kind == "goal_kick" else t
				if in_box(box_team, p.position) and p.role != Player.Role.GK:
					p.position.x = box_team.own_goal().x + box_team.attack_dir().x * (box_d + 0.6)
				continue
			var d := flat_dist(p.position, spot)
			if d < r:
				var away := p.position - spot
				away.y = 0.0
				if away.length() < 0.05:
					away = -taker.team.attack_dir()
				var np := clamp_in_field(spot + away.normalized() * r, -2.0)
				p.position.x = np.x
				p.position.z = np.z


func _set_phase(ph: int) -> void:
	phase = ph
	phase_time = 0.0


func _separate_players() -> void:
	var n := players.size()
	for i in n:
		var a := players[i]
		for j in range(i + 1, n):
			var b := players[j]
			var dx := b.position.x - a.position.x
			var dz := b.position.z - a.position.z
			var d2 := dx * dx + dz * dz
			var min_d := Player.BODY_RADIUS * 2.0
			if d2 < min_d * min_d and d2 > 0.0001:
				var d := sqrt(d2)
				var push := (min_d - d) * 0.5
				var nx := dx / d
				var nz := dz / d
				var wa := 0.5
				if a.has_ball() or a.state == Player.State.DASH:
					wa = 0.3
				elif b.has_ball() or b.state == Player.State.DASH:
					wa = 0.7
				a.position.x -= nx * push * 2.0 * wa
				a.position.z -= nz * push * 2.0 * wa
				b.position.x += nx * push * 2.0 * (1.0 - wa)
				b.position.z += nz * push * 2.0 * (1.0 - wa)


# ---------------------------------------------------------------- toques

func _resolve_touches() -> void:
	var b := ball
	var best: Player = null
	var best_score := INF
	var best_type := ""
	for p in players:
		if not p.can_touch() or b.tried.has(p):
			continue
		if b.shot_result == "goal" and b.kick_kind == "shot" and time >= p.wall_until:
			continue
		if b.shield_team >= 0 and p.team_id != b.shield_team and p.state != Player.State.DASH and time >= p.wall_until:
			continue
		var dh := flat_dist(b.position, p.position)
		var bh := b.position.y - p.height
		var hands := p.role == Player.Role.GK and in_box(p.team, b.position) and in_box(p.team, p.position)
		var reach := 0.55 + 0.2 * p.st("intercept")
		if p.want_mark:
			reach += 0.4
		var wall := time < p.wall_until
		if wall:
			reach = 2.3
		var type := "foot"
		if hands:
			reach = 1.0 if p.state != Player.State.DIVE else 1.6
			if b.shot_result == "save":
				reach += 0.8
			if bh > 2.5:
				continue
			type = "hands"
		elif bh > 1.15:
			if bh > (2.6 if wall else 2.05):
				continue
			reach = 2.3 if wall else 0.75
			type = "head"
		if dh > reach:
			continue
		var s := dh - (0.3 if hands else 0.0)
		if s < best_score:
			best_score = s
			best = p
			best_type = type
	if best != null:
		_attempt_touch(best, best_type)


func _attempt_touch(p: Player, type: String) -> void:
	var b := ball
	b.tried[p] = true
	var speed := b.velocity.length()
	var prev := b.last_touch
	var same_team := prev != null and prev.team == p.team
	var intended := b.pass_target == p
	var is_shot := b.kick_kind == "shot"
	var is_pass := b.kick_kind == "pass" or b.kick_kind == "cross"
	if type == "hands":
		_gk_touch(p)
		return
	if not p.first_time.is_empty() and (same_team or not is_shot):
		if type == "head":
			stats["headers"] += 1
		p.first_time_kick()
		if same_team and is_pass and prev != p:
			_pass_completed(prev, p)
		elif not same_team and is_pass:
			_interception(p)
		return
	var chance: float
	var wall := time < p.wall_until and not same_team
	if b.special_id != "" and b.shield_team == p.team_id and same_team:
		chance = 1.0
	elif wall:
		chance = 1.0 if b.shield_team < 0 else 0.5
	elif intended or (same_team and is_pass):
		chance = clampf(1.05 - maxf(speed - 18.0, 0.0) * 0.04, 0.5, 1.0)
	elif is_pass and not same_team:
		chance = clampf(0.3 + p.st("intercept") * 0.45 + (0.25 if p.want_mark else 0.0) - maxf(speed - 12.0, 0.0) * 0.03, 0.08, 0.9)
		if b.vision_pass:
			chance *= 0.5
	elif is_shot:
		chance = clampf(0.35 - (speed - 20.0) * 0.02, 0.05, 0.4)
	else:
		chance = clampf(1.0 - maxf(speed - 10.0, 0.0) * 0.05, 0.4, 1.0)
	if randf() > chance:
		return
	if type == "head":
		stats["headers"] += 1
		if not same_team or speed > 14.0:
			# Despeje de cabeza
			var away := p.team.attack_dir() * 9.0 + Vector3(0, 5.0, randf_range(-4.0, 4.0))
			b.kick(p, away, "clear")
			p.gain_energy(SkillDB.GAIN["header"])
			if not same_team and is_pass:
				_interception(p)
			return
	if is_shot or speed > 22.0:
		var v := b.velocity * randf_range(-0.3, 0.45) + Vector3(randf_range(-4, 4), randf_range(1, 5), randf_range(-4, 4))
		b.kick(p, v, "deflect")
		p.gain_energy(SkillDB.GAIN["block"])
		notify("¡Bloqueo de %s!" % p.player_name, p.team.color.lightened(0.3))
		FX.popup(p.position, "¡BLOQUEO!", p.team.color.lightened(0.5))
		FX.burst(b.position, Color(1, 1, 1), 16, 5.0, 0.4)
		FX.hitstop(0.06)
		return
	b.set_carrier(p, true)
	if same_team and is_pass and prev != p:
		_pass_completed(prev, p)
	elif not same_team and is_pass:
		_interception(p)
	else:
		p.gain_energy(SkillDB.GAIN["touch"])


func _pass_completed(from: Player, to: Player) -> void:
	stats["passes_done"] += 1
	if from != null:
		from.gain_energy(SkillDB.GAIN["through"] if ball.pass_through else SkillDB.GAIN["pass"])
	to.gain_energy(SkillDB.GAIN["touch"])


func _interception(p: Player) -> void:
	stats["interceptions"] += 1
	p.gain_energy(SkillDB.GAIN["interception"])
	notify("¡Interceptación de %s!" % p.player_name, p.team.color.lightened(0.3))
	FX.popup(p.position, "¡CORTADO!", p.team.color.lightened(0.5))
	FX.ring(p.position, p.team.color.lightened(0.3), 2.2, 0.35)


func _gk_touch(gk: Player) -> void:
	var b := ball
	var speed := b.velocity.length()
	var toward := b.velocity.x * -gk.team.attack_sign > 2.0
	var chance := 0.97
	var shotlike := b.kick_kind == "shot" or (toward and speed > 14.0)
	if b.shot_result == "save":
		chance = 1.0
	elif shotlike:
		chance = 0.56 + gk.st("reflex") * 0.45 - maxf(speed - 16.0, 0.0) * 0.02 - b.special_break
		chance += gk_bonus(gk.team)
		var off := Vector2(b.position.x - gk.position.x, b.position.z - gk.position.z).length()
		chance -= maxf(off - 0.7, 0.0) * 0.3
		if gk.state == Player.State.DIVE:
			chance += 0.05
	if b.shot_result != "save":
		chance = clampf(chance, 0.04, 0.97)
	if randf() < chance:
		if shotlike:
			stats["saves"] += 1
			gk.gain_energy(SkillDB.GAIN["save"])
		if not shotlike or (speed < 20.0 and b.special_id == "" and randf() < 0.75):
			b.set_carrier(gk)
			if shotlike:
				notify("Atrapa %s" % gk.player_name, gk.team.color.lightened(0.3))
				FX.popup(gk.position, "¡ATRAPADA!", Color(1, 1, 1))
				FX.ring(b.position, Color(1, 1, 1), 1.6, 0.3)
				FX.hitstop(0.06)
		else:
			b.kick(gk, _parry_velocity(gk, b), "parry")
			notify("¡Atajada de %s!" % gk.player_name, gk.team.color.lightened(0.3))
			FX.popup(gk.position, "¡ATAJADA!", Color(1, 1, 1), 1.2)
			FX.burst(b.position, Color(1, 1, 1), 34, 8.0)
			FX.ring(b.position, gk.team.gk_color, 2.5, 0.35)
			FX.shake(0.5)
			FX.hitstop(0.09)


# ---------------------------------------------------------------- eventos

## Despeje del portero: a veces al córner (por encima del travesaño o por
## fuera del palo, con trayectoria calculada para que nunca entre), a veces
## de vuelta al juego (rebote para el remate).
func _parry_velocity(gk: Player, b: Ball) -> Vector3:
	var away := gk.team.attack_sign
	var pz := signf(b.position.z) if absf(b.position.z) > 0.2 else (1.0 if randf() < 0.5 else -1.0)
	if randf() < 0.45:
		return _over_or_wide(-away, b, pz)
	return Vector3(away * randf_range(4.0, 9.0), randf_range(2.0, 6.0), pz * randf_range(3.0, 9.0))


## Velocidad para que el balón cruce la línea de fondo del lado `sign_x`
## por encima del travesaño o por fuera de un palo.
func _over_or_wide(sign_x: float, b: Ball, pz: float) -> Vector3:
	var vx := randf_range(4.0, 6.0)
	var dx := maxf(hl - absf(b.position.x), 0.0) + 0.35
	var t := dx / vx
	if absf(b.position.z) > gw * 0.5 - 1.2 or randf() < 0.4:
		var z_cross := pz * (gw * 0.5 + randf_range(0.6, 1.5))
		return Vector3(sign_x * vx, randf_range(1.0, 3.0), (z_cross - b.position.z) / t)
	var vy := (gh + 0.6 - b.position.y) / t + 0.5 * Ball.GRAVITY * t
	return Vector3(sign_x * vx, vy, pz * randf_range(0.3, 1.5))


## Un tiro resuelto como atajada/fuera que físicamente iba a entrar: el
## portero lo toca con la punta de los dedos y sale al córner.
func on_fingertip_save(sign_x: float, b: Ball) -> void:
	var defending: Team = teams[0] if teams[0].attack_sign == -sign_x else teams[1]
	var gk := defending.gk()
	var pz := signf(b.position.z) if absf(b.position.z) > 0.2 else (1.0 if randf() < 0.5 else -1.0)
	b.velocity = _over_or_wide(sign_x, b, pz)
	b.side_spin = 0.0
	b.top_spin = 0.0
	b.knuckle = 0.0
	b.shot_result = ""
	b.kick_kind = "parry"
	if gk != null:
		b.last_touch = gk
		stats["saves"] += 1
		gk.gain_energy(SkillDB.GAIN["save"])
		FX.popup(gk.position, "¡CON LA PUNTA DE LOS DEDOS!", Color(1, 1, 1), 0.9)
		FX.hitstop(0.08)


func on_shot_resolved(p: Player, res: Dictionary) -> void:
	stats["shot_prob_sum"] = float(stats.get("shot_prob_sum", 0.0)) + float(res["p_goal"])
	if p.is_human:
		FX.popup(p.position, "GOL %d%%" % roundi(float(res["p_goal"]) * 100.0), Color(1, 1, 1, 0.9), 0.6)


func on_possession(p: Player) -> void:
	p.charge_kind = ""
	if human != null and human.is_team_mode() and p.team == human.team and p.role != Player.Role.GK:
		human.switch_to(p)


func on_pass(from: Player, target: Player, _through: bool) -> void:
	stats["passes"] += 1
	if human != null and human.is_team_mode() and from.is_human and target != null and target.role != Player.Role.GK:
		human.switch_to(target)


func on_shot(p: Player) -> void:
	stats["shots"] += 1
	var path := ball.predict(2.5, 0.05)
	var s := p.team.attack_sign
	for bp in path:
		if bp.x * s >= hl:
			if absf(bp.z) < gw * 0.5 and bp.y < gh:
				stats["on_target"] += 1
				p.gain_energy(SkillDB.GAIN["shot_on_target"])
			break


func on_special(p: Player, sid: String) -> void:
	stats["specials"] += 1
	var sd := SkillDB.special(sid)
	var col: Color = sd["color"]
	var title: String = sd["name"]
	if sid == "despertar":
		var a := SkillDB.awakening_by_id(p.awakening_id)
		col = a["color"]
		title = "DESPERTAR: " + String(a["name"]).to_upper()
	FX.slowmo(0.3, 0.75)
	FX.closeup(p, 0.6)
	FX.burst(p.position + Vector3.UP, col, 36, 7.0)
	FX.ring(p.position, col, 4.5, 0.6)
	special_used.emit(p, sid)
	if hud != null:
		hud.show_special(title, p.player_name, col)


func on_energy_bar(p: Player) -> void:
	if p.is_human and hud != null:
		hud.flash_energy()


func on_woodwork() -> void:
	if _woodwork_cd > 0.0:
		return
	_woodwork_cd = 0.5
	stats["woodwork"] += 1
	notify("¡Al palo!", Color(1, 1, 1))
	FX.popup(ball.position - Vector3.UP * 1.5, "¡PALO!", Color(1, 1, 1))
	FX.shake(0.5)


func foul(by: Player, victim: Player) -> void:
	if phase != Phase.PLAY:
		return
	stats["fouls"] += 1
	victim.stun(0.6, true)
	add_stoppage(0.2)
	notify("¡Falta de %s!" % by.player_name, Color(1.0, 0.85, 0.3))
	FX.popup(victim.position, "¡FALTA!", Color(1.0, 0.85, 0.2), 1.2)
	FX.hitstop(0.08)
	var spot := victim.position
	spot.y = 0.0
	if in_box(by.team, spot):
		_start_restart("penalty", victim.team, by.team.own_goal() + by.team.attack_dir() * spot_d)
	else:
		_start_restart("free_kick", victim.team, clamp_in_field(spot, 0.5))


func _goal(side: float) -> void:
	var scoring: Team = teams[0] if teams[0].attack_sign == side else teams[1]
	scoring.score += 1
	stats["goals"] += 1
	var scorer := ball.last_touch
	var own_goal := scorer != null and scorer.team != scoring
	for mate in scoring.players:
		mate.gain_energy(SkillDB.GAIN["team_goal"])
	if scorer != null and not own_goal:
		scorer.gain_energy(SkillDB.GAIN["goal"])
		var passer := ball.last_passer
		if passer != null and passer != scorer and passer.team == scoring:
			passer.gain_energy(SkillDB.GAIN["assist"])
			FX.popup(passer.position, "¡ASISTENCIA!", scoring.color.lightened(0.5), 0.8)
	_kickoff_team = scoring.opponent.id
	add_stoppage(0.6)
	_set_phase(Phase.GOAL)
	for p in players:
		p.charge_kind = ""
		if p.team == scoring and p.state == Player.State.NORMAL:
			p._set_state(Player.State.CELEBRATE, 3.0)
	FX.slowmo(0.35, 0.9)
	FX.shake(1.0)
	FX.burst(ball.position, scoring.color.lightened(0.4), 60, 9.0, 1.0)
	_crowd_mat.set_shader_parameter("excitement", 1.0)
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if is_instance_valid(_crowd_mat):
			_crowd_mat.set_shader_parameter("excitement", 0.0))
	var who := scorer.player_name if scorer != null else "?"
	if own_goal:
		who += " (en propia)"
	goal_scored.emit(scoring, scorer)
	if hud != null:
		hud.show_goal(scoring, who)


func _check_out() -> void:
	var p := ball.position
	var r := Ball.RADIUS
	if absf(p.x) > hl + r:
		var sx := signf(p.x)
		# El equipo que defiende ese lado
		var defending: Team = teams[0] if teams[0].attack_sign == -sx else teams[1]
		var last := ball.last_touch
		stats["outs"] += 1
		if last != null and last.team == defending:
			var spot := Vector3(sx * (hl - 0.3), 0.0, signf(p.z if absf(p.z) > 0.1 else 1.0) * (hw - 0.3))
			_start_restart("corner", defending.opponent, spot)
		else:
			var spot2 := Vector3(sx * (hl - box_d * 0.33), 0.0, signf(p.z if absf(p.z) > 0.1 else 1.0) * minf(4.0, gw))
			_start_restart("goal_kick", defending, spot2)
	elif absf(p.z) > hw + r:
		stats["outs"] += 1
		var last2 := ball.last_touch
		var t: Team = teams[0] if last2 == null or last2.team == teams[1] else teams[1]
		var spot3 := Vector3(clampf(p.x, -hl + 1.0, hl - 1.0), 0.0, signf(p.z) * (hw - 0.05))
		_start_restart("throw_in", t, spot3)


# ---------------------------------------------------------------- saques

func _start_restart(kind: String, t: Team, spot: Vector3) -> void:
	_set_phase(Phase.RESTART)
	add_stoppage({"corner": 0.3, "goal_kick": 0.1, "throw_in": 0.05, "free_kick": 0.4, "penalty": 1.0}.get(kind, 0.0))
	match kind:
		"corner":
			stats["corners"] += 1
			FX.popup(spot, "CÓRNER", t.color.lightened(0.5), 1.0)
		"throw_in":
			stats["throw_ins"] += 1
		"goal_kick":
			stats["goal_kicks"] += 1
	ball.place(spot)
	var taker: Player
	if kind == "goal_kick":
		taker = t.gk()
	elif kind == "penalty" and human != null and t == human.team:
		taker = human.player
	else:
		taker = t.nearest_field_player(spot)
	for p in players:
		p.charge_kind = ""
		p.pending = {}
		p.first_time = {}
		if p.state != Player.State.STUN:
			p._set_state(Player.State.NORMAL)
	var into := (Vector3(0, 0, 0) - spot)
	into.y = 0.0
	if kind == "penalty" or kind == "free_kick":
		into = t.opp_goal() - spot
		into.y = 0.0
	into = into.normalized()
	taker.position = spot - into * 0.45
	taker.velocity = Vector3.ZERO
	taker.facing = into
	ball.set_carrier(taker)
	taker.restart_lock = true
	taker.restart_kind = kind
	_restart = {"taker": taker, "kind": kind, "time": time}
	# Rivales a distancia
	var keep := 9.15 * clampf(hl / 52.5, 0.5, 1.0)
	for p in t.opponent.players:
		if p.role == Player.Role.GK and kind == "penalty":
			p.position = t.opp_goal() - t.attack_dir() * 0.2
			p.velocity = Vector3.ZERO
			continue
		var d := flat_dist(p.position, spot)
		if d < keep:
			var away := (p.position - spot)
			away.y = 0.0
			away = away.normalized() if away.length() > 0.1 else -into
			p.position = clamp_in_field(spot + away * keep, 0.5)
	if kind == "penalty":
		for p in players:
			if p == taker or p.role == Player.Role.GK:
				continue
			if in_box(t.opponent, p.position):
				p.position.x = t.opponent.own_goal().x + t.attack_dir().x * -(box_d + 1.5)
	if human != null and human.is_team_mode() and t == human.team and taker.role != Player.Role.GK:
		human.switch_to(taker)
	var names := {"corner": "Saque de esquina", "goal_kick": "Saque de arco", "throw_in": "Saque de banda",
		"free_kick": "Tiro libre", "penalty": "¡PENAL!"}
	notify("%s · %s" % [names.get(kind, kind), t.short_name], t.color.lightened(0.4))


## Si el humano tarda demasiado en sacar, se le ayuda (para no atascar).
func _restart_watchdog() -> void:
	if _restart.is_empty():
		return
	var taker: Player = _restart["taker"]
	if not taker.restart_lock or ball.carrier != taker:
		_restart = {}
		return
	if taker.is_human and time - float(_restart["time"]) > 7.0:
		taker.restart_lock = false
		_restart = {}


func _kickoff(team_id: int) -> void:
	_set_phase(Phase.KICKOFF)
	FX.reset()
	_restart = {}
	ball.place(Vector3.ZERO)
	for t in teams:
		for p in t.players:
			var px := p.home.x * 0.85
			var limit := 0.48
			if t.id != team_id:
				limit = 0.5 - (circle_r + 0.6) / (2.0 * hl)
			px = minf(px, limit)
			p.position = t.field_point(px, p.home.y * 0.9)
			p.velocity = Vector3.ZERO
			p.facing = t.attack_dir()
			p.height = 0.0
			p.y_vel = 0.0
			p.charge_kind = ""
			p.pending = {}
			p.first_time = {}
			p.restart_lock = false
			p._set_state(Player.State.NORMAL)
			p.frozen = true
	var kt := teams[team_id]
	var taker: Player = human.player if human != null and kt == human.team and human.player.role != Player.Role.GK else null
	if taker == null:
		taker = kt.nearest_field_player(Vector3.ZERO)
	taker.position = -kt.attack_dir() * 0.45
	taker.facing = kt.attack_dir()
	ball.set_carrier(taker)
	taker.restart_lock = true
	taker.restart_kind = "kickoff"
	_restart = {"taker": taker, "kind": "kickoff", "time": time}


func _full_time() -> void:
	_set_phase(Phase.FULLTIME)
	FX.reset()
	for p in players:
		p.charge_kind = ""
		p.velocity = Vector3.ZERO
	if hud != null:
		hud.show_full_time()


func restart_match() -> void:
	get_tree().paused = false
	FX.reset()
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- construcción

func _setup_dims(size: int) -> void:
	if not SIZES.has(size):
		size = 7
	var d: Dictionary = SIZES[size]
	hl = float(d["len"]) * 0.5
	hw = float(d["wid"]) * 0.5
	gw = d["gw"]
	gh = d["gh"]
	var k := hl / 52.5
	box_d = maxf(16.5 * k, 7.0)
	box_w = minf(40.3 * (hw / 34.0), hw * 1.6)
	spot_d = maxf(11.0 * k, 6.0)
	circle_r = maxf(9.15 * k, 4.0)


func _pick_human_start(t: Team) -> Player:
	var best: Player = null
	for p in t.players:
		if p.role == Player.Role.FWD:
			if best == null or absf(p.home.y) < absf(best.home.y):
				best = p
	return best if best != null else t.players[t.players.size() - 1]


func _build_teams(size: int) -> void:
	if not FORMATIONS.has(size):
		size = 7
	var home := Team.new()
	home.id = 0
	home.team_name = "Blue Lock Azul"
	home.short_name = "AZUL"
	home.color = Color(0.12, 0.32, 0.85)
	home.color2 = Color(0.95, 0.95, 0.98)
	home.gk_color = Color(0.1, 0.75, 0.35)
	home.attack_sign = 1.0
	var away := Team.new()
	away.id = 1
	away.team_name = "Rivales Rojo"
	away.short_name = "ROJO"
	away.color = Color(0.82, 0.12, 0.16)
	away.color2 = Color(0.1, 0.1, 0.12)
	away.gk_color = Color(0.95, 0.75, 0.1)
	away.attack_sign = -1.0
	home.opponent = away
	away.opponent = home
	home.m = self
	away.m = self
	teams = [home, away]
	var human_slot := -1
	if GameConfig.control_mode != GameConfig.ControlMode.AI_ONLY:
		var f: Array = FORMATIONS[size]
		var best_i := -1
		for i in f.size():
			if int(f[i][2]) == 3 and (best_i < 0 or absf(float(f[i][1])) < absf(float(f[best_i][1]))):
				best_i = i
		human_slot = best_i
	for t in teams:
		var names: Array = NAMES_HOME if t.id == 0 else NAMES_AWAY
		var form: Array = FORMATIONS[size]
		for i in form.size():
			var row: Array = form[i]
			var role := int(row[2])
			var p := Player.new()
			var st := _make_stats(role, 0.62 if t.id == 0 else [0.55, 0.62, 0.7][difficulty])
			var pname: String = names[i % names.size()]
			var num := 1 if role == Player.Role.GK else i + 1
			if t.id == 0 and i == human_slot:
				st = (GameConfig.profile["stats"] as Dictionary).duplicate()
				pname = GameConfig.profile["name"]
				num = GameConfig.profile["number"]
				p.is_human = true
			p.setup(self, t, role, num, pname, st, Vector2(float(row[0]), float(row[1])))
			p.name = "%s_%d" % [t.short_name, i]
			t.players.append(p)
			players.append(p)
			add_child(p)
			p.set_human(false)
			p.brain = PlayerAI.new(p)
			var aw: Dictionary = SkillDB.AWAKENINGS[randi() % SkillDB.AWAKENINGS.size()]
			p.awakening_id = aw["id"]
		t.ai = TeamAI.new(t)


func _make_stats(role: int, rating: float) -> Dictionary:
	var s := {}
	for k in ["speed", "accel", "shot_power", "shot_acc", "curve", "passing", "dribble", "tackle", "strength", "jump", "intercept", "reflex"]:
		s[k] = rating + randf_range(-0.08, 0.08)
	match role:
		Player.Role.GK:
			s["reflex"] += 0.2
			s["jump"] += 0.1
			s["speed"] -= 0.1
		Player.Role.DEF:
			s["tackle"] += 0.15
			s["strength"] += 0.12
			s["intercept"] += 0.12
			s["shot_acc"] -= 0.12
		Player.Role.MID:
			s["passing"] += 0.15
			s["intercept"] += 0.05
		Player.Role.FWD:
			s["shot_power"] += 0.12
			s["shot_acc"] += 0.12
			s["curve"] += 0.08
			s["dribble"] += 0.1
			s["speed"] += 0.06
			s["tackle"] -= 0.12
	for k in s:
		s[k] = clampf(s[k], 0.2, 0.95)
	return s


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.42, 0.78)
	sm.sky_horizon_color = Color(0.66, 0.76, 0.9)
	sm.ground_horizon_color = Color(0.4, 0.45, 0.4)
	sm.ground_bottom_color = Color(0.1, 0.12, 0.1)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.04
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -35.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(hl * 2.0 + 18.0, hw * 2.0 + 16.0)
	ground.mesh = pm
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://shaders/pitch.gdshader")
	gmat.set_shader_parameter("half_size", Vector2(hl, hw))
	gmat.set_shader_parameter("stripes", float(roundi(hl / 4.0) * 2))
	gmat.set_shader_parameter("box_depth", box_d)
	gmat.set_shader_parameter("box_width", box_w)
	gmat.set_shader_parameter("small_depth", maxf(5.5 * hl / 52.5, 2.5))
	gmat.set_shader_parameter("small_width", minf(18.3 * hw / 34.0, box_w * 0.6))
	gmat.set_shader_parameter("circle_r", circle_r)
	gmat.set_shader_parameter("spot_dist", spot_d)
	ground.material_override = gmat
	add_child(ground)

	for s in [-1.0, 1.0]:
		_build_goal(s)
	_build_stands()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var flag := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.025
			c.bottom_radius = 0.025
			c.height = 1.5
			flag.mesh = c
			flag.position = Vector3(sx * hl, 0.75, sz * hw)
			add_child(flag)
			var cloth := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.35, 0.25, 0.02)
			cloth.mesh = bm
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(1.0, 0.85, 0.1)
			cloth.material_override = cm
			cloth.position = Vector3(sx * hl + 0.18, 1.35, sz * hw)
			add_child(cloth)


func _build_goal(s: float) -> void:
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.97, 0.97, 0.97)
	post_mat.roughness = 0.3
	for z in [-gw * 0.5, gw * 0.5]:
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = Ball.POST_RADIUS
		cm.bottom_radius = Ball.POST_RADIUS
		cm.height = gh
		post.mesh = cm
		post.material_override = post_mat
		post.position = Vector3(s * hl, gh * 0.5, z)
		add_child(post)
	var bar := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = Ball.POST_RADIUS
	bc.bottom_radius = Ball.POST_RADIUS
	bc.height = gw + Ball.POST_RADIUS * 2.0
	bar.mesh = bc
	bar.material_override = post_mat
	bar.rotation_degrees = Vector3(90, 0, 0)
	bar.position = Vector3(s * hl, gh, 0)
	add_child(bar)
	var net_mat := ShaderMaterial.new()
	net_mat.shader = load("res://shaders/net.gdshader")
	var panels := [
		[Vector3(0.02, gh, gw), Vector3(s * (hl + gdepth), gh * 0.5, 0)],
		[Vector3(gdepth, gh, 0.02), Vector3(s * (hl + gdepth * 0.5), gh * 0.5, -gw * 0.5)],
		[Vector3(gdepth, gh, 0.02), Vector3(s * (hl + gdepth * 0.5), gh * 0.5, gw * 0.5)],
		[Vector3(gdepth, 0.02, gw), Vector3(s * (hl + gdepth * 0.5), gh, 0)],
	]
	for pnl in panels:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pnl[0]
		mi.mesh = bm
		mi.material_override = net_mat
		mi.position = pnl[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _build_stands() -> void:
	_crowd_mat = ShaderMaterial.new()
	_crowd_mat.shader = load("res://shaders/crowd.gdshader")
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.18, 0.19, 0.24)
	# Grada del fondo (lado lejano a la cámara) y las de los arcos
	var stands := [
		[Vector3(hl * 2.0 + 30.0, 1.0, 16.0), Vector3(0, 6.0, -(hw + 16.0)), 0.0],
		[Vector3(hw * 2.0 + 14.0, 1.0, 14.0), Vector3(hl + 16.0, 5.0, -3.0), -90.0],
		[Vector3(hw * 2.0 + 14.0, 1.0, 14.0), Vector3(-(hl + 16.0), 5.0, -3.0), 90.0],
	]
	for st in stands:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = st[0]
		mi.mesh = bm
		mi.material_override = _crowd_mat
		# Gira hacia la cancha y se inclina (la cara superior mira al campo)
		mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(st[2])) * Basis(Vector3.RIGHT, deg_to_rad(38.0)), st[1])
		add_child(mi)
	# Vallas publicitarias
	var colors := [Color(0.1, 0.3, 0.9), Color(0.85, 0.15, 0.2), Color(0.95, 0.95, 0.95), Color(0.05, 0.05, 0.08)]
	var n := int(hl * 2.0 / 8.0)
	for i in n:
		var mi2 := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(7.6, 0.9, 0.15)
		mi2.mesh = bm2
		var mm := StandardMaterial3D.new()
		mm.albedo_color = colors[i % colors.size()]
		mm.emission_enabled = true
		mm.emission = colors[i % colors.size()] * 0.4
		mi2.material_override = mm
		mi2.position = Vector3(-hl + 4.0 + i * 8.0, 0.45, -(hw + 4.0))
		add_child(mi2)
		var lbl := Label3D.new()
		lbl.text = "REDLOCK"
		lbl.font_size = 96
		lbl.pixel_size = 0.006
		lbl.modulate = Color(1, 1, 1) if i % colors.size() != 2 else Color(0.1, 0.1, 0.1)
		lbl.position = Vector3(-hl + 4.0 + i * 8.0, 0.45, -(hw + 3.91))
		add_child(lbl)


func _build_markers() -> void:
	_pass_marker = _marker(Color(1.0, 1.0, 1.0, 0.8), 0.7)
	_space_marker = _marker(Color(1.0, 0.9, 0.3, 0.85), 0.55)
	_land_marker = _marker(Color(0.8, 0.4, 1.0, 0.9), 0.55)
	# Mira del tiro: aro vertical sobre la línea de gol
	_aim_reticle = _make_reticle()
	for i2 in 14:
		var mi := MeshInstance3D.new()
		var s2 := SphereMesh.new()
		s2.radius = 0.09
		s2.height = 0.18
		s2.radial_segments = 6
		s2.rings = 3
		mi.mesh = s2
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.85, 0.5, 1.0)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_pred_markers.append(mi)


## Aro que siempre mira a la cámara: se ve igual desde la cámara de TV.
func _make_reticle() -> MeshInstance3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.28, 0.4, 0.62, 0.92, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.albedo_texture = tex
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.7, 1.7)
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func _marker(c: Color, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = r * 0.8
	torus.outer_radius = r
	mi.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = c
	mi.material_override = mat
	mi.scale = Vector3(1, 0.05, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func _update_markers() -> void:
	_pass_marker.visible = false
	_space_marker.visible = false
	_aim_reticle.visible = false
	var hp: Player = human.player if human != null else null
	if hp != null and ball.carrier == hp and (phase == Phase.PLAY or phase == Phase.RESTART):
		if hp.is_charging(["shot", "curve", "chip"]) or hp.is_winding(Player.SHOT_KINDS):
			pass
		else:
			var kind2 := "through" if hp.is_charging(["through", "through_lob"]) else "pass"
			var plan := hp.pass_plan(kind2, hp.charge_amount(), hp.aim_dir if hp.aim_active else hp.facing)
			var tgt: Player = plan["target"]
			if tgt != null:
				_pass_marker.visible = true
				_pass_marker.position = Vector3(tgt.position.x, 0.04, tgt.position.z)
			if kind2 == "through" or tgt == null:
				var pt: Vector3 = plan["point"]
				_space_marker.visible = true
				_space_marker.position = Vector3(pt.x, 0.05, pt.z)
	# Metavisión predictiva
	var show := prediction_active and human != null
	_land_marker.visible = false
	if show and ball.carrier == null:
		var was_high := ball.position.y > 0.6
		for bp in ball_path:
			if was_high and bp.y < 0.4:
				_land_marker.visible = true
				_land_marker.position = Vector3(bp.x, 0.05, bp.z)
				break
			was_high = was_high or bp.y > 0.6
	for i in _pred_markers.size():
		var mi := _pred_markers[i]
		mi.visible = show
		if show:
			var a := human.player.position
			var k := float(i + 1) / float(_pred_markers.size())
			var pos := a.lerp(prediction_target, k)
			mi.position = Vector3(pos.x, 0.12 + sin(time * 6.0 + i * 0.6) * 0.05, pos.z)
