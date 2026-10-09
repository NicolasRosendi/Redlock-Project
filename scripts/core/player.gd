class_name Player
extends Node3D
## Futbolista. Lo manejan el control humano o la IA escribiendo "intenciones"
## (move_dir, want_sprint, ...) y llamando a acciones (perform, do_tackle...).
## Aquí vive toda la lógica de estamina, energía, despertar, tiros, pases,
## quites, regates y técnicas especiales.

enum Role { GK, DEF, MID, FWD }
enum State { NORMAL, KICK, TACKLE, SLIDE, SHOULDER, STUN, DIVE, DASH, SKILL, CELEBRATE }

const BODY_RADIUS := 0.38
const JUMP_GRAVITY := 18.0
const SHOT_KINDS := ["shot", "chip", "ground", "volley", "header"]
const PASS_KINDS := ["pass", "pass_lob", "through", "through_lob", "cross"]

var m: Match
var team: Team
var team_id := 0
var role: int = Role.MID
var number := 0
var player_name := ""
var is_human := false
var stats := {}
var home := Vector2(0.5, 0.0)
var brain: PlayerAI

# Movimiento
var velocity := Vector3.ZERO
var facing := Vector3.RIGHT
var height := 0.0
var y_vel := 0.0
var state: int = State.NORMAL
var state_time := 0.0
var state_dur := 0.0

# Intenciones (las escribe el control humano o la IA cada frame)
var move_dir := Vector3.ZERO
var want_sprint := false
var want_mark := false
var want_shield := false
var want_press := false
var has_look := false
var look_target := Vector3.ZERO
var aim_dir := Vector3.RIGHT
var frozen := false

# Recursos
var stamina := 100.0
var stamina_cap := 100.0
var energy := 0.0
var awakened := false
var awaken_left := 0.0
var awakening_id := "tiro"

# Temporizadores / banderas
var evade_until := 0.0
var no_touch_until := 0.0
var burst_until := 0.0
var phantom_until := 0.0
var restart_lock := false
var restart_kind := ""
var making_run := false
var path_boost := false
var gk_hold_time := 0.0
var gk_reacted_kick := -1

# Acciones en curso
var charge_kind := ""
var charge_time := 0.0
var pending := {}
var first_time := {}
var skill := {}
var skill_ball_dir := Vector3.FORWARD
var tackle_done := false
var dash := {}
var dribble_check := {}
var phantom_hit := {}
var dive_side := 1.0
var dive_target := Vector3.ZERO

# Visual
var _body: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _ring: MeshInstance3D
var _arrow: MeshInstance3D
var _aura: Node3D
var _aura_mat: StandardMaterial3D
var _aura_light: OmniLight3D
var _aura_particles: CPUParticles3D
var _anim_phase := 0.0
var _kick_anim := 0.0
var _ghost_t := 0.0
var _shirt_mat: StandardMaterial3D


func setup(match_ref: Match, team_ref: Team, role_: int, num: int, name_: String, stats_: Dictionary, home_: Vector2) -> void:
	m = match_ref
	team = team_ref
	team_id = team_ref.id
	role = role_
	number = num
	player_name = name_
	stats = stats_
	home = home_
	facing = team.attack_dir()


func _ready() -> void:
	_build_visual()


# ---------------------------------------------------------------- utilidades

func st(k: String) -> float:
	var v: float = stats.get(k, 0.5)
	if awakened:
		match awakening_id:
			"tiro":
				if k == "shot_power" or k == "shot_acc":
					v += 0.3
			"fisico":
				if k == "strength" or k == "tackle":
					v += 0.35
			"salto":
				if k == "jump":
					v += 0.6
			"velocidad":
				if k == "speed" or k == "accel":
					v += 0.45
			"vision":
				if k == "passing" or k == "intercept":
					v += 0.3
			"prediccion":
				if k == "intercept":
					v += 0.4
	return v


func has_ball() -> bool:
	return m.ball.carrier == self


func can_act() -> bool:
	return state == State.NORMAL and not frozen


func can_touch() -> bool:
	if frozen or m.time < no_touch_until:
		return false
	return state == State.NORMAL or state == State.DIVE or state == State.DASH or state == State.TACKLE


func is_evading() -> bool:
	return m.time < evade_until or m.time < phantom_until


func is_awakened_as(id: String) -> bool:
	return awakened and awakening_id == id


func speed_h() -> float:
	return Vector2(velocity.x, velocity.z).length()


func max_speed() -> float:
	var base := 5.4 + 1.4 * st("speed")
	if want_sprint and stamina > 3.0:
		base = 7.2 + 2.2 * st("speed")
	if has_ball():
		base *= 0.88 + 0.07 * st("dribble")
	if want_mark and not has_ball():
		base = minf(base, 4.2 + st("speed"))
	if want_shield and has_ball():
		base *= 0.55
	if stamina < 12.0:
		base *= 0.82
	if is_awakened_as("velocidad"):
		base *= 1.18
	elif awakened:
		base *= 1.04
	if m.time < burst_until:
		base *= 1.15
	if m.time < phantom_until:
		base *= 1.4
	if path_boost:
		base *= 1.25
	return base


## Velocidad punta estimada (para cálculos de intercepción de la IA).
func top_speed() -> float:
	var v := 7.2 + 2.2 * st("speed")
	if is_awakened_as("velocidad"):
		v *= 1.18
	if stamina < 12.0:
		v *= 0.82
	return v


func accel() -> float:
	var a := 13.0 + 10.0 * st("accel")
	if is_awakened_as("velocidad"):
		a *= 1.4
	return a


func flat_to(pos: Vector3) -> Vector3:
	var d := pos - position
	d.y = 0.0
	return d


func pressure() -> float:
	var d := INF
	for o in team.opponent.players:
		d = minf(d, Match.flat_dist(o.position, position))
	return clampf(1.0 - (d - 0.8) / 3.0, 0.0, 1.0)


func nearest_opponent() -> Player:
	var best: Player = null
	var bd := INF
	for o in team.opponent.players:
		var d := Match.flat_dist(o.position, position)
		if d < bd:
			bd = d
			best = o
	return best


# ---------------------------------------------------------------- recursos

func spend_stamina(a: float) -> void:
	if is_awakened_as("fisico"):
		a *= 0.35
	stamina = maxf(stamina - a, 0.0)
	stamina_cap = maxf(stamina_cap - a * m.fatigue_rate, 40.0)


func gain_energy(a: float) -> void:
	var before := int(energy / SkillDB.BAR)
	energy = minf(energy + a, SkillDB.MAX_ENERGY)
	if int(energy / SkillDB.BAR) > before:
		m.on_energy_bar(self)


func activate_awakening() -> bool:
	if awakened:
		return false
	awakened = true
	awaken_left = SkillDB.AWAKEN_DURATION
	stamina_cap = minf(stamina_cap + 15.0, 100.0)
	stamina = stamina_cap
	var col: Color = SkillDB.awakening_by_id(awakening_id)["color"]
	_aura_mat.albedo_color = Color(col.r, col.g, col.b, 0.22)
	_aura_light.light_color = col
	var pm := _aura_particles.mesh.surface_get_material(0) as StandardMaterial3D
	if pm:
		pm.albedo_color = col
	_aura.visible = true
	_aura_particles.emitting = true
	return true


func _update_resources(dt: float) -> void:
	var spd := speed_h()
	var sprinting := want_sprint and spd > 6.0 and state == State.NORMAL
	if sprinting:
		spend_stamina(6.0 * dt)
	elif want_press and spd > 3.0:
		spend_stamina(2.5 * dt)
	elif want_mark:
		spend_stamina(1.0 * dt)
	elif state == State.NORMAL:
		var regen := 4.0 if spd > 2.5 else 7.0
		if is_awakened_as("fisico"):
			regen *= 3.0
		elif awakened:
			regen *= 1.5
		stamina = minf(stamina + regen * dt, stamina_cap)
	stamina = minf(stamina, stamina_cap)
	if awakened:
		awaken_left -= dt
		if awaken_left <= 0.0:
			awakened = false
			_aura.visible = false
			_aura_particles.emitting = false
			if is_human:
				m.notify("Fin del despertar", Color(0.7, 0.7, 0.8))


# ---------------------------------------------------------------- bucle

func tick(dt: float) -> void:
	state_time += dt
	if charge_kind != "":
		charge_time += dt
		if not has_ball() or state != State.NORMAL:
			charge_kind = ""
	if not first_time.is_empty() and m.time > float(first_time.get("until", 0.0)):
		first_time = {}
	_update_resources(dt)
	if frozen:
		velocity = velocity.move_toward(Vector3.ZERO, 30.0 * dt)
		_finish_tick(dt)
		return
	match state:
		State.NORMAL:
			_move_normal(dt)
		State.KICK:
			velocity = velocity.move_toward(Vector3.ZERO, 18.0 * dt)
			if not pending.is_empty() and not pending.get("done", false) and state_time >= float(pending.get("windup", 0.0)):
				_execute_kick()
			if state_time >= state_dur:
				_set_state(State.NORMAL)
		State.TACKLE:
			velocity = velocity.move_toward(Vector3.ZERO, 12.0 * dt)
			if state_time > 0.05 and state_time < 0.3 and not tackle_done:
				_tackle_contact(1.0 + st("tackle") * 0.35, false)
			if state_time >= state_dur:
				_set_state(State.NORMAL)
		State.SLIDE:
			velocity = velocity.move_toward(Vector3.ZERO, 9.0 * dt)
			if state_time < 0.6 and not tackle_done:
				_tackle_contact(1.05, true)
			if state_time >= state_dur:
				_set_state(State.NORMAL)
		State.SHOULDER:
			velocity = velocity.move_toward(Vector3.ZERO, 10.0 * dt)
			if state_time > 0.08 and not tackle_done:
				_shoulder_contact()
			if state_time >= state_dur:
				_set_state(State.NORMAL)
		State.STUN:
			velocity = velocity.move_toward(Vector3.ZERO, 10.0 * dt)
			if state_time >= state_dur:
				_set_state(State.NORMAL)
		State.DIVE:
			var rem := flat_to(dive_target)
			if rem.dot(velocity) <= 0.0 or rem.length() < 0.15:
				velocity = velocity.move_toward(Vector3.ZERO, 30.0 * dt)
			elif state_time > 0.5:
				velocity = velocity.move_toward(Vector3.ZERO, 9.0 * dt)
			_dive_smother()
			if state_time >= state_dur:
				_set_state(State.NORMAL)
		State.DASH:
			_dash_tick(dt)
		State.SKILL:
			velocity = skill["dir"] * float(skill["speed"])
			if state_time >= state_dur:
				var keep: Vector3 = skill["dir"] * minf(float(skill["speed"]), 5.5)
				if skill.get("turn", false):
					facing = -facing
					keep = facing * 3.0
				velocity = keep
				_set_state(State.NORMAL)
		State.CELEBRATE:
			velocity = velocity.move_toward(Vector3.ZERO, 6.0 * dt)
			if fmod(state_time, 0.7) < dt:
				y_vel = 4.0
	_auto_jump()
	_dribble_reward()
	_phantom_tick(dt)
	_finish_tick(dt)


func _finish_tick(dt: float) -> void:
	if height > 0.0 or y_vel > 0.0:
		y_vel -= JUMP_GRAVITY * dt
		height += y_vel * dt
		if height <= 0.0:
			height = 0.0
			y_vel = 0.0
	position += velocity * dt
	position.y = height
	_clamp_field()
	_animate(dt)


func _set_state(s: int, dur := 0.0) -> void:
	state = s
	state_time = 0.0
	state_dur = dur


func _move_normal(dt: float) -> void:
	var spd := max_speed()
	var md := move_dir
	md.y = 0.0
	if md.length() > 1.0:
		md = md.normalized()
	if restart_lock:
		if md.length() > 0.2:
			facing = _turn(facing, md.normalized(), 8.0 * dt)
		velocity = Vector3.ZERO
		return
	var desired := md * spd
	var a := accel()
	if desired.length() < velocity.length():
		a *= 1.5
	if has_ball() and velocity.length() > 2.0 and desired.length() > 0.1:
		var ang := velocity.angle_to(desired)
		if ang > 1.0:
			a *= 0.55 + 0.4 * st("dribble")
	velocity = velocity.move_toward(desired, a * dt)
	var face := facing
	if has_look:
		var lt := flat_to(look_target)
		if lt.length() > 0.2:
			face = lt.normalized()
	elif velocity.length() > 0.6:
		face = Vector3(velocity.x, 0.0, velocity.z).normalized()
	var turn_rate := 11.0
	if has_ball():
		turn_rate = 7.0 + 6.0 * st("dribble")
		if want_sprint:
			turn_rate *= 0.75
	facing = _turn(facing, face, turn_rate * dt)


func _turn(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var ang := from.signed_angle_to(to, Vector3.UP)
	var step := clampf(ang, -max_angle, max_angle)
	return from.rotated(Vector3.UP, step).normalized()


func _clamp_field() -> void:
	var lim_x := m.hl + 3.0
	var lim_z := m.hw + 3.0
	position.x = clampf(position.x, -lim_x, lim_x)
	position.z = clampf(position.z, -lim_z, lim_z)
	# No meterse dentro de la portería
	if absf(position.x) > m.hl - 0.1 and absf(position.z) < m.gw * 0.5 + 0.4:
		position.x = signf(position.x) * (m.hl - 0.1)


# ---------------------------------------------------------------- carga / patadas

func begin_charge(kind: String) -> void:
	if not can_act() or not has_ball():
		return
	charge_kind = kind
	charge_time = 0.0


func charge_amount() -> float:
	return clampf(charge_time / 0.9, 0.0, 1.0)


func is_charging(kinds: Array) -> bool:
	return charge_kind != "" and kinds.has(charge_kind)


func is_winding(kinds: Array) -> bool:
	return state == State.KICK and not pending.get("done", true) and kinds.has(pending.get("kind", ""))


func release_charge() -> void:
	if charge_kind == "":
		return
	var k := charge_kind
	var c := charge_amount()
	charge_kind = ""
	perform(k, c, {})


func perform(kind: String, charge: float, opts: Dictionary) -> void:
	var ft: bool = opts.get("first_time", false)
	if not ft and (not has_ball() or state != State.NORMAL):
		return
	if restart_lock and restart_kind == "throw_in" and SHOT_KINDS.has(kind):
		kind = "pass"
	var windup := 0.09
	if SHOT_KINDS.has(kind):
		windup = 0.16
	if opts.has("special"):
		windup = float(opts.get("windup", 0.22))
	charge_kind = ""
	pending = {"kind": kind, "charge": charge, "opts": opts, "windup": windup, "done": false}
	if ft:
		_execute_kick()
		_set_state(State.KICK, 0.2)
		return
	_set_state(State.KICK, windup + 0.16)


## Cancelación (amague): pulsar rápido tiro + pase.
func cancel_kick() -> void:
	var was := charge_kind != "" or is_winding(SHOT_KINDS + PASS_KINDS)
	charge_kind = ""
	if state == State.KICK and not pending.get("done", true):
		pending = {}
		_set_state(State.NORMAL)
	if was:
		evade_until = m.time + 0.35
		velocity *= 0.5
		gain_energy(SkillDB.GAIN["feint"])
		m.notify("Amague de %s" % player_name, Color(0.85, 0.85, 0.9))
		m.stats["feints"] += 1


## Doble toque de tiro: convierte el disparo en raso.
func convert_to_ground_shot() -> void:
	if is_winding(["shot"]):
		pending["kind"] = "ground"
		m.notify("Tiro raso", Color(0.85, 0.85, 0.9))


func queue_first_time(kind: String, extra := {}) -> void:
	first_time = {"kind": kind, "start": m.time, "until": m.time + 1.4}
	first_time.merge(extra, true)


func first_time_kick() -> void:
	var ft := first_time
	first_time = {}
	var kind: String = ft["kind"]
	var end_t: float = ft.get("released", m.time)
	var c := clampf((end_t - float(ft["start"])) / 0.9, 0.3, 1.0)
	var bh := m.ball.position.y - height
	if kind == "shot":
		if bh > 1.15:
			kind = "header"
		elif bh > 0.35:
			kind = "volley"
	var opts := {"first_time": true}
	if ft.has("special"):
		opts["special"] = ft["special"]
	perform(kind, c, opts)


func _execute_kick() -> void:
	var kind: String = pending.get("kind", "")
	var charge: float = pending.get("charge", 0.5)
	var opts: Dictionary = pending.get("opts", {})
	pending["done"] = true
	var b := m.ball
	var ft: bool = opts.get("first_time", false)
	if not ft and b.carrier != self:
		return
	restart_lock = false
	_kick_anim = 0.3
	spend_stamina(1.5)
	if SHOT_KINDS.has(kind):
		_kick_shot(kind, charge, opts)
	elif PASS_KINDS.has(kind):
		_kick_pass(kind, charge, opts)


func _kick_pass(kind: String, charge: float, opts: Dictionary) -> void:
	var b := m.ball
	var from := b.position
	var through := kind.begins_with("through")
	var lofted := kind == "pass_lob" or kind == "through_lob" or kind == "cross"
	var sid: String = opts.get("special", "")
	var target: Player = opts.get("target", null)
	var aim: Vector3 = opts.get("aim", aim_dir)
	if target == null and not opts.has("point"):
		target = team.find_pass_target(self, aim, through)
	var point: Vector3
	if opts.has("point"):
		point = opts["point"]
	elif target == null:
		var ad := Vector3(aim.x, 0.0, aim.z)
		point = from + (ad.normalized() if ad.length() > 0.1 else facing) * (10.0 + charge * 22.0)
	else:
		point = target.position
	var arrive := 5.0 + charge * 6.0
	if sid != "":
		arrive = 15.0
	if target != null:
		var lead_dir := Vector3.ZERO
		if through:
			lead_dir = (target.team.attack_dir() * 0.7 + target.flat_to(target.position + target.velocity).normalized() * 0.3)
			lead_dir = lead_dir.normalized()
			point = target.position + lead_dir * (4.0 + charge * 9.0)
			point = m.clamp_in_field(point, 1.5)
			if target.brain != null:
				target.brain.run_to(point, 2.5)
		else:
			for i in 2:
				var d := Match.flat_dist(from, point)
				var t: float
				if lofted:
					t = Kick.lob_time(from.y, _lob_apex(kind, d), 1.4 if kind == "cross" else Ball.RADIUS)
				else:
					t = Kick.ground_time(Kick.ground_speed_for(d, arrive), d)
				point = target.position + target.velocity * t * 0.85
				point = m.clamp_in_field(point, 0.5)
	var vel: Vector3
	var dist := Match.flat_dist(from, point)
	if lofted:
		var land_y := 1.4 if kind == "cross" else Ball.RADIUS
		var land := point
		if kind != "cross":
			land = from + (point - from) * 0.88
		vel = Kick.lob(from, land, _lob_apex(kind, dist), land_y)
	else:
		vel = Kick.ground_pass(from, point, arrive)
		if sid != "":
			var hv := vel.length()
			if hv < 28.0 and hv > 0.01:
				vel *= 28.0 / hv
	var err := (1.0 - st("passing")) * 0.12 + pressure() * 0.06
	if sid != "":
		err = 0.0
	vel = vel.rotated(Vector3.UP, randf_range(-err, err))
	if vel.length() > 40.0:
		vel = vel.normalized() * 40.0
	b.kick(self, vel, "cross" if kind == "cross" else "pass")
	b.pass_target = target
	b.pass_through = through
	b.last_passer = self
	b.vision_pass = is_awakened_as("vision")
	if sid != "":
		var sd := SkillDB.special(sid)
		b.special_id = sid
		b.shield_team = team_id
		b.set_trail(true, sd["color"])
	if target != null and target.brain != null:
		target.brain.expect_pass()
	m.on_pass(self, target, through)


func _lob_apex(kind: String, d: float) -> float:
	if kind == "cross":
		return clampf(3.0 + d * 0.08, 3.0, 9.0)
	return clampf(2.4 + d * 0.15, 2.4, 14.0)


func _kick_shot(kind: String, charge: float, opts: Dictionary) -> void:
	var b := m.ball
	var from := b.position
	var goal := team.opp_goal()
	var half := m.gw * 0.5
	var sid: String = opts.get("special", "")
	var aim: Vector3 = opts.get("aim", aim_dir)
	var z_aim: float
	if opts.has("z"):
		z_aim = opts["z"]
	elif absf(aim.z) < 0.3 or kind == "header":
		var gk := team.opponent.gk()
		var gz := gk.position.z if gk != null else 0.0
		if absf(gz) > 0.3:
			z_aim = -signf(gz) * (half - 0.6)
		elif absf(from.z) > 1.5:
			z_aim = -signf(from.z) * (half - 0.6)
		else:
			z_aim = (half - 0.6) * (1.0 if randf() < 0.5 else -1.0)
		if absf(aim.z) >= 0.3:
			z_aim = clampf(aim.z * 1.3, -1.0, 1.0) * (half - 0.45)
	else:
		z_aim = clampf(aim.z * 1.3, -1.0, 1.0) * (half - 0.45)
	var power_mul := 0.85 + 0.3 * st("shot_power")
	if is_awakened_as("tiro"):
		power_mul *= 1.2
	var speed := lerpf(15.0, 31.0, charge) * power_mul
	var y_aim: float = opts.get("y", lerpf(0.3, m.gh - 0.5, clampf(charge * 0.95, 0.0, 1.0)))
	var top := 0.12
	var side := 0.0
	var dist := Match.flat_dist(from, goal)
	var over := maxf(charge - 0.85, 0.0) / 0.15
	var err := (1.0 - st("shot_acc")) * 0.8 + pressure() * 0.5 + over * 0.8 + dist / 45.0
	match kind:
		"ground":
			speed *= 0.92
			y_aim = Ball.RADIUS
			top = 0.0
		"volley":
			speed *= 1.05
			err *= 1.25
		"header":
			speed = (11.0 + 9.0 * charge) * (1.35 if is_awakened_as("salto") else 1.0)
			y_aim = 0.45
			err *= 1.1
			top = 0.0
			gain_energy(SkillDB.GAIN["header"])
	var sd := {}
	if sid != "":
		sd = SkillDB.special(sid)
		err *= 0.2
		over = 0.0
		match sid:
			"disparo_directo":
				speed = 36.0 * (1.1 if is_awakened_as("tiro") else 1.0)
				top = 0.5
				y_aim = clampf(y_aim, 0.5, m.gh - 0.6)
			"meteoro_descendente":
				speed = 33.0
				top = 1.3
				y_aim = m.gh - 0.4
				z_aim = (signf(z_aim) if absf(z_aim) > 0.01 else 1.0) * (half - 0.45)
	var target := Vector3(goal.x, y_aim, z_aim)
	target.z += randf_range(-1.0, 1.0) * err * 1.1
	target.y += randf_range(-0.35, 0.9) * err * 0.8 + over * randf() * 1.4
	target.y = maxf(target.y, Ball.RADIUS)
	var dir := Vector3(target.x - from.x, 0.0, target.z - from.z).normalized()
	if (kind == "shot" or kind == "volley") and sid == "":
		var crossv := facing.cross(dir).y
		side = clampf(crossv * 1.5, -1.0, 1.0) * (0.25 + (1.0 - charge) * 0.4)
	if sid == "meteoro_descendente":
		var lat := Vector3.UP.cross(dir)
		side = 0.45 * (signf(lat.dot(Vector3(0, 0, -target.z))) if absf(target.z) > 0.1 else 1.0)
	var vel: Vector3
	if kind == "chip":
		var apex := clampf(3.0 + dist * 0.09, 3.2, 9.0)
		target.y = clampf(target.y, 1.2, m.gh - 0.3)
		vel = Kick.lob(from, target, apex, target.y)
		top = 0.0
		side = 0.0
	elif kind == "ground":
		vel = dir * speed
	else:
		vel = Kick.aimed(from, target, speed, top, side)
	b.kick(self, vel, "shot", side, top)
	if sid != "":
		b.special_id = sid
		b.special_break = float(sd.get("break", 0.3))
		b.set_trail(true, sd["color"])
		if sid == "disparo_directo":
			b.knuckle = 0.25
		FX.shake(0.6)
		FX.burst(from, sd["color"], 40, 9.0)
		FX.ring(from, sd["color"], 4.0)
	elif speed > 27.0:
		FX.shake(0.25)
	m.on_shot(self)


# ---------------------------------------------------------------- defensa

func do_tackle() -> void:
	if not can_act() or has_ball():
		return
	_face_ball_if_near(3.5)
	_set_state(State.TACKLE, 0.42)
	tackle_done = false
	spend_stamina(5.0)
	velocity = facing * maxf(speed_h(), 5.5)


func do_slide() -> void:
	if not can_act() or has_ball():
		return
	_face_ball_if_near(7.0)
	_set_state(State.SLIDE, 0.85)
	tackle_done = false
	spend_stamina(10.0)
	velocity = facing * maxf(speed_h() + 2.0, 8.5)


func do_shoulder() -> void:
	if not can_act() or has_ball():
		return
	_face_ball_if_near(2.5)
	_set_state(State.SHOULDER, 0.3)
	tackle_done = false
	spend_stamina(7.0)
	velocity += facing * 2.0


func _face_ball_if_near(r: float) -> void:
	var to := flat_to(m.ball.position)
	if to.length() < r and to.length() > 0.05:
		facing = to.normalized()


func _tackle_contact(reach: float, slide: bool) -> void:
	var b := m.ball
	var foot := position + facing * (0.75 if slide else 0.6)
	var d := Match.flat_dist(b.position, foot)
	var c := b.carrier
	if b.position.y - height > 0.9 or c == self:
		return
	if c != null and c.team == team:
		return
	if d > reach:
		if slide and c != null and Match.flat_dist(c.position, position + facing * 0.5) < 0.75:
			tackle_done = true
			m.foul(self, c)
		return
	tackle_done = true
	if c == null:
		b.kick(self, facing * (9.0 if slide else 6.5) + Vector3.UP * 1.2, "tackle")
		return
	if c.is_evading():
		m.notify("¡%s lo esquiva!" % c.player_name, c.team.color.lightened(0.3))
		c.gain_energy(10.0)
		return
	var p := 0.48 + (st("tackle") - c.st("dribble")) * 0.6 + (st("strength") - c.st("strength")) * 0.15
	if c.want_shield:
		p -= 0.18
	var behind := c.facing.dot((c.position - position).normalized()) > 0.55
	if behind:
		p -= 0.12
	if slide:
		p += 0.08
	p += m.tackle_bonus(team)
	if randf() < clampf(p, 0.1, 0.92):
		if behind and randf() < 0.3:
			m.foul(self, c)
			return
		c.stun(0.6 if slide else 0.35)
		c.dribble_check = {}
		if not slide and randf() < 0.55:
			b.set_carrier(self)
		else:
			var lat := facing.cross(Vector3.UP) * randf_range(-3.0, 3.0)
			b.kick(self, facing * 6.0 + lat + Vector3.UP * 0.8, "tackle")
		gain_energy(SkillDB.GAIN["tackle"])
		m.stats["tackles"] += 1
		m.notify("¡Quite de %s!" % player_name, team.color.lightened(0.3))
		FX.burst(b.position + Vector3.UP * 0.3, Color(1, 1, 1), 14, 4.0, 0.4)
	else:
		c.gain_energy(6.0)


func _shoulder_contact() -> void:
	tackle_done = true
	var b := m.ball
	var c := b.carrier
	if c == null or c.team == team:
		return
	if Match.flat_dist(c.position, position) > 1.7:
		return
	var mine := st("strength") + stamina / 250.0 + randf() * 0.35
	var theirs := c.st("strength") + c.stamina / 250.0 + randf() * 0.35 + (0.2 if c.want_shield else 0.0)
	if mine > theirs:
		var v := c.velocity * 0.6 + facing * 2.5
		c.stun(0.45)
		b.kick(self, v, "tackle")
		gain_energy(18.0)
		m.notify("¡%s gana el choque!" % player_name, team.color.lightened(0.3))
		m.stats["tackles"] += 1
	else:
		stun(0.4)
		c.gain_energy(8.0)


func stun(t: float) -> void:
	charge_kind = ""
	pending = {}
	if has_ball():
		m.ball.kick(self, velocity * 0.5, "drop")
	_set_state(State.STUN, t)


func jump() -> void:
	if height > 0.01 or not (state == State.NORMAL or state == State.KICK):
		return
	var j := 3.8 + st("jump") * 1.2
	if is_awakened_as("salto"):
		j *= 1.45
	y_vel = j
	spend_stamina(5.0)


func _auto_jump() -> void:
	if first_time.is_empty() or height > 0.0 or state != State.NORMAL:
		return
	var b := m.ball
	if b.carrier != null:
		return
	var bh := b.position.y
	if bh < 1.75 or bh > 3.6:
		return
	var d := Match.flat_dist(b.position, position)
	var closing := -flat_to(b.position).normalized().dot(Vector3(b.velocity.x, 0, b.velocity.z))
	if d < 2.4 and (closing > 2.0 or d < 1.0):
		jump()


# ---------------------------------------------------------------- portero

func start_dive(target: Vector3, arrive_t := 0.4) -> void:
	if state == State.DIVE:
		return
	var lat := flat_to(target)
	_set_state(State.DIVE, 0.85)
	tackle_done = false
	dive_target = Vector3(target.x, 0.0, target.z)
	var dir := lat.normalized() if lat.length() > 0.1 else facing.cross(Vector3.UP)
	dive_side = signf(facing.cross(dir).y)
	if dive_side == 0.0:
		dive_side = 1.0
	velocity = dir * clampf(lat.length() / maxf(arrive_t, 0.22), 2.0, 8.0)
	if target.y > 1.3:
		y_vel = clampf((target.y - 1.0) * 3.4, 0.0, 5.5)


func _dive_smother() -> void:
	if tackle_done or role != Role.GK:
		return
	var c := m.ball.carrier
	if c == null or c.team == team:
		return
	if Match.flat_dist(m.ball.position, position) < 1.2:
		tackle_done = true
		if c.is_evading() or randf() > 0.5:
			return
		c.stun(0.4)
		m.ball.set_carrier(self)
		m.notify("¡El portero se lanza a los pies!", team.color.lightened(0.3))


# ---------------------------------------------------------------- regates

func do_dribble_flick(wdir: Vector3, enhanced: bool) -> void:
	if not can_act() or not has_ball() or restart_lock:
		return
	var fwd := facing
	var d := fwd.dot(wdir)
	var lateral := wdir - fwd * d
	lateral.y = 0.0
	lateral = lateral.normalized() if lateral.length() > 0.05 else fwd.cross(Vector3.UP)
	var kind: String
	if d > 0.55:
		kind = "sombrero" if enhanced else "toque_largo"
	elif d < -0.5:
		kind = "ruleta" if enhanced else "arrastre"
	else:
		kind = "elastico" if enhanced else "recorte"
	var cost := 9.0 if enhanced else 5.0
	if stamina < cost:
		if is_human:
			m.notify("Sin estamina", Color(0.8, 0.5, 0.4))
		return
	spend_stamina(cost)
	var opp := nearest_opponent()
	if opp != null and Match.flat_dist(opp.position, position) < 3.5:
		dribble_check = {"until": m.time + 1.0, "opp": opp}
	var b := m.ball
	match kind:
		"toque_largo":
			b.kick(self, fwd * (10.0 + st("speed") * 3.0), "knock")
			no_touch_until = m.time + 0.12
			burst_until = m.time + 0.9
		"sombrero":
			var tgt := position + fwd * 5.0
			b.kick(self, Kick.lob(b.position, tgt, 2.7, Ball.RADIUS), "knock")
			no_touch_until = m.time + 0.35
			evade_until = m.time + 0.7
			burst_until = m.time + 1.0
		"recorte":
			_start_skill(lateral, 1.7, 0.26, 0.3, lateral)
		"elastico":
			_start_skill(lateral, 2.5, 0.36, 0.48, lateral)
		"arrastre":
			_start_skill(-fwd, 0.6, 0.3, 0.28, -fwd)
			skill["turn"] = true
		"ruleta":
			var dir := (lateral * 0.8 + fwd * 0.6).normalized()
			_start_skill(dir, 2.2, 0.5, 0.55, dir)
			skill["spin"] = true
	gain_energy(3.0)
	m.notify(SkillDB.SKILL_MOVE_NAMES[kind], Color(0.9, 0.9, 1.0) if not enhanced else Color(1.0, 0.85, 0.4))
	m.stats["skill_moves"] += 1


func _start_skill(dir: Vector3, dist: float, dur: float, evade: float, ball_dir: Vector3) -> void:
	skill = {"dir": dir, "speed": dist / dur}
	skill_ball_dir = ball_dir
	evade_until = m.time + evade
	_set_state(State.SKILL, dur)


func _dribble_reward() -> void:
	if dribble_check.is_empty() or m.time < float(dribble_check["until"]):
		return
	dribble_check = {}
	if team.has_ball() or (m.ball.carrier == null and m.ball.last_touch == self):
		gain_energy(SkillDB.GAIN["dribble"])
		m.stats["dribbles"] += 1
		m.notify("¡Regate de %s!" % player_name, team.color.lightened(0.4))


# ---------------------------------------------------------------- especiales

func try_special(sid: String) -> bool:
	var sd := SkillDB.special(sid)
	if sd.is_empty() or frozen:
		return false
	var cost := float(sd["bars"]) * SkillDB.BAR
	if energy < cost:
		if is_human:
			m.notify("Energía insuficiente (%d barras)" % int(sd["bars"]), Color(0.7, 0.7, 0.75))
		return false
	if state != State.NORMAL:
		return false
	var ok := false
	match sd["kind"]:
		"pass":
			if has_ball() and not restart_lock:
				var t := team.find_pass_target(self, aim_dir, false)
				if t != null:
					perform("pass", 1.0, {"special": sid, "target": t, "windup": 0.18})
					ok = true
		"shot":
			if has_ball() and (not restart_lock or restart_kind == "penalty" or restart_kind == "free_kick"):
				perform("shot", 1.0, {"special": sid, "windup": 0.22})
				ok = true
		"dribble":
			if has_ball() and not restart_lock:
				phantom_until = m.time + 1.3
				evade_until = phantom_until
				burst_until = phantom_until
				phantom_hit = {}
				ok = true
		"tackle":
			if not has_ball():
				ok = _start_special_dash()
		"awaken":
			ok = activate_awakening()
	if ok:
		energy -= cost
		charge_kind = ""
		m.on_special(self, sid)
	elif is_human and sd["kind"] != "awaken":
		m.notify("No se puede usar ahora", Color(0.7, 0.7, 0.75))
	return ok


func _start_special_dash() -> bool:
	var b := m.ball
	var c := b.carrier
	if c != null and c.team != team and Match.flat_dist(c.position, position) < 12.0:
		dash = {"target": c}
	elif c == null and Match.flat_dist(b.position, position) < 12.0 and b.position.y < 2.6:
		dash = {"target": null}
	else:
		return false
	_set_state(State.DASH, 0.7)
	tackle_done = false
	return true


func _dash_tick(dt: float) -> void:
	var b := m.ball
	var tgt: Vector3 = b.position
	var c := b.carrier
	var to := flat_to(tgt)
	if to.length() > 0.05:
		facing = to.normalized()
	velocity = facing * 19.0
	_ghost_t -= dt
	if _ghost_t <= 0.0:
		_ghost_t = 0.04
		FX.afterimage(self, Color(1.0, 0.9, 0.3), 0.25)
	if to.length() < 1.1 and b.position.y - height < 2.4 and not tackle_done:
		tackle_done = true
		if c != null and c.team != team:
			if m.time < c.phantom_until:
				m.notify("¡%s es intocable!" % c.player_name, c.team.color.lightened(0.3))
				stun(0.5)
				return
			c.stun(0.7)
			b.set_carrier(self)
			gain_energy(10.0)
			m.stats["tackles"] += 1
		elif c == null:
			if b.shield_team >= 0 and b.shield_team != team_id and randf() < 0.5:
				m.notify("¡El pase es demasiado rápido!", Color(0.8, 0.8, 0.9))
			else:
				b.set_carrier(self)
				m.stats["interceptions"] += 1
		FX.burst(b.position + Vector3.UP * 0.4, Color(1.0, 0.9, 0.3), 30, 7.0)
		velocity = facing * 3.0
		_set_state(State.NORMAL)
		return
	if c != null and c.team == team:
		_set_state(State.NORMAL)
		return
	if state_time >= state_dur:
		velocity = facing * 4.0
		_set_state(State.NORMAL)


func _phantom_tick(dt: float) -> void:
	if m.time >= phantom_until:
		return
	_ghost_t -= dt
	if _ghost_t <= 0.0:
		_ghost_t = 0.06
		FX.afterimage(self, Color(0.75, 0.45, 1.0), 0.3)
	for o in team.opponent.players:
		if phantom_hit.has(o) or o.role == Role.GK:
			continue
		if Match.flat_dist(o.position, position) < 1.8:
			phantom_hit[o] = true
			if randf() < 0.6:
				o.stun(0.8)
				m.notify("¡Tobillos rotos!", Color(0.8, 0.55, 1.0))


# ---------------------------------------------------------------- visual

func _build_visual() -> void:
	var shirt := team.gk_color if role == Role.GK else team.color
	var skin: Color = GameConfig.profile["skin"] if is_human and team.id == 0 else Color(0.85, 0.68, 0.52).lerp(Color(0.45, 0.3, 0.2), randf() * 0.7)
	var hair: Color = GameConfig.profile["hair"] if is_human and team.id == 0 else Color(0.1, 0.08, 0.06).lerp(Color(0.85, 0.75, 0.4), randf() * randf())
	_shirt_mat = _mat(shirt)
	var shorts_mat := _mat(team.color2)
	var skin_mat := _mat(skin)
	var sock_mat := _mat(shirt.darkened(0.3))

	_body = Node3D.new()
	add_child(_body)
	var torso := _mesh_child(_body, _capsule(0.26, 0.85), _shirt_mat, Vector3(0, 1.22, 0))
	torso.scale = Vector3(1.0, 1.0, 0.75)
	_mesh_child(_body, _cyl(0.25, 0.28), shorts_mat, Vector3(0, 0.78, 0))
	_mesh_child(_body, _sphere(0.14), skin_mat, Vector3(0, 1.78, 0))
	var hair_mi := _mesh_child(_body, _sphere(0.15), _mat(hair), Vector3(0, 1.84, 0.02))
	hair_mi.scale = Vector3(1.0, 0.7, 1.0)

	_leg_l = _limb(_body, Vector3(-0.12, 0.72, 0), 0.62, sock_mat, 0.075)
	_leg_r = _limb(_body, Vector3(0.12, 0.72, 0), 0.62, sock_mat, 0.075)
	_arm_l = _limb(_body, Vector3(-0.33, 1.52, 0), 0.55, skin_mat, 0.055)
	_arm_r = _limb(_body, Vector3(0.33, 1.52, 0), 0.55, skin_mat, 0.055)

	var num := Label3D.new()
	num.text = str(number)
	num.font_size = 72
	num.pixel_size = 0.004
	num.outline_size = 8
	num.modulate = team.color2 if role != Role.GK else Color(0.1, 0.1, 0.1)
	num.position = Vector3(0, 1.28, 0.21)
	_body.add_child(num)

	var shadow := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.0, 1.0)
	shadow.mesh = pm
	shadow.material_override = Ball._blob_material()
	shadow.position = Vector3(0, 0.012, 0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.set_meta("no_ghost", true)
	add_child(shadow)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.7
	_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.85, 0.1)
	_ring.material_override = ring_mat
	_ring.scale = Vector3(1, 0.04, 1)
	_ring.position.y = 0.03
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.set_meta("no_ghost", true)
	add_child(_ring)

	_arrow = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.35
	_arrow.mesh = cone
	_arrow.material_override = ring_mat
	_arrow.position.y = 2.45
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.set_meta("no_ghost", true)
	add_child(_arrow)

	_aura = Node3D.new()
	add_child(_aura)
	var aura_mi := MeshInstance3D.new()
	aura_mi.mesh = _capsule(0.62, 2.3)
	_aura_mat = StandardMaterial3D.new()
	_aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_aura_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aura_mat.albedo_color = Color(0.3, 0.6, 1.0, 0.2)
	aura_mi.material_override = _aura_mat
	aura_mi.position.y = 1.0
	aura_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aura_mi.set_meta("no_ghost", true)
	_aura.add_child(aura_mi)
	_aura_light = OmniLight3D.new()
	_aura_light.position.y = 1.2
	_aura_light.omni_range = 3.5
	_aura_light.light_energy = 1.6
	_aura.add_child(_aura_light)
	_aura_particles = CPUParticles3D.new()
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.05
	pmesh.height = 0.1
	pmesh.radial_segments = 6
	pmesh.rings = 3
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(0.4, 0.7, 1.0)
	pmesh.material = pmat
	_aura_particles.mesh = pmesh
	_aura_particles.amount = 40
	_aura_particles.lifetime = 0.8
	_aura_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_aura_particles.emission_sphere_radius = 0.6
	_aura_particles.direction = Vector3.UP
	_aura_particles.spread = 15.0
	_aura_particles.gravity = Vector3(0, 3.0, 0)
	_aura_particles.initial_velocity_min = 1.0
	_aura_particles.initial_velocity_max = 2.5
	_aura_particles.position.y = 0.8
	_aura_particles.emitting = false
	_aura.add_child(_aura_particles)
	_aura.visible = false
	set_human(is_human)


func set_human(h: bool) -> void:
	is_human = h
	if _ring != null:
		_ring.visible = h
		_arrow.visible = h


func _animate(dt: float) -> void:
	rotation.y = atan2(-facing.x, -facing.z)
	var spd := speed_h()
	_anim_phase += dt * (spd * 1.9 + 0.5)
	var amp := clampf(spd / 8.0, 0.0, 1.0) * 0.9
	var swing := sin(_anim_phase) * amp
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	_arm_l.rotation.x = -swing * 0.8
	_arm_r.rotation.x = swing * 0.8
	_arm_l.rotation.z = 0.0
	_arm_r.rotation.z = 0.0
	_body.rotation = Vector3(-clampf(spd / 9.0, 0.0, 1.0) * 0.2, 0.0, 0.0)
	_body.position = Vector3.ZERO
	if _kick_anim > 0.0:
		_kick_anim -= dt
		var k := 1.0 - _kick_anim / 0.3
		_leg_r.rotation.x = lerpf(-0.9, 1.3, clampf(k * 1.6, 0.0, 1.0))
	elif state == State.KICK:
		_leg_r.rotation.x = -0.9
	match state:
		State.SLIDE:
			_body.rotation.x = 1.15
			_body.position.y = -0.55
			_leg_l.rotation.x = 1.4
			_leg_r.rotation.x = 1.2
		State.STUN:
			_body.rotation.z = sin(state_time * 14.0) * 0.35
		State.DIVE:
			_body.rotation.z = -dive_side * clampf(state_time * 6.0, 0.0, 1.35)
			_arm_l.rotation.z = -2.6
			_arm_r.rotation.z = 2.6
		State.TACKLE, State.SHOULDER:
			_body.rotation.x = -0.35
			_leg_r.rotation.x = 1.0
		State.SKILL:
			if skill.get("spin", false):
				_body.rotation.y = state_time / maxf(state_dur, 0.01) * TAU
		State.CELEBRATE:
			_arm_l.rotation.z = -2.7
			_arm_r.rotation.z = 2.7
	if m.ball.carrier == self and role == Role.GK and state == State.NORMAL:
		_arm_l.rotation.x = -1.4
		_arm_r.rotation.x = -1.4
	if is_human:
		_arrow.position.y = 2.45 + sin(m.time * 5.0) * 0.08
		_ring.rotation.y += dt * 2.0
	if awakened:
		_aura.scale = Vector3.ONE * (1.0 + sin(m.time * 9.0) * 0.06)


func _mat(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.75
	return mat


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * 0.95
	c.height = h
	c.radial_segments = 12
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


func _mesh_child(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _limb(parent: Node3D, pivot: Vector3, length: float, mat: Material, r: float) -> Node3D:
	var p := Node3D.new()
	p.position = pivot
	parent.add_child(p)
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * 0.85
	c.height = length
	c.radial_segments = 8
	_mesh_child(p, c, mat, Vector3(0, -length * 0.5, 0))
	return p
