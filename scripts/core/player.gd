class_name Player
extends Node3D
## Futbolista. Lo manejan el control humano o la IA escribiendo "intenciones"
## (move_dir, want_sprint, ...) y llamando a acciones (perform, do_tackle...).
## Aquí vive la lógica de estamina, energía, despertar, tiros, pases, quites,
## regates, técnicas especiales y la animación procedural del cuerpo.

enum Role { GK, DEF, MID, FWD }
enum State { NORMAL, KICK, TACKLE, SLIDE, SHOULDER, POKE, STUN, DIVE, DASH, SKILL, CELEBRATE }

const BODY_RADIUS := 0.38
const JUMP_GRAVITY := 18.0
const HIP_Y := 0.93
const SHOT_KINDS := ["shot", "curve", "chip", "ground", "volley", "header"]
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
var want_arm := false
var has_look := false
var look_target := Vector3.ZERO
## Dirección del stick ("giroscopio") y si el stick está inclinado.
var aim_dir := Vector3.RIGHT
var aim_active := false
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
var grabbed_until := 0.0
var wall_until := 0.0
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
var fallen := false
var arm_target: Player = null
var arm_time := 0.0
var _arm_resolved := false
## Aviso previo de la IA antes de entrar al quite ("!" rojo): da tiempo a regatear.
var _tele := {}
var _alert: Label3D
var _flick_anim := 0.0
var skill_flash := {}

# Visual
var _root: Node3D
var _pelvis: Node3D
var _torso: Node3D
var _head: Node3D
var _thigh_l: Node3D
var _knee_l: Node3D
var _thigh_r: Node3D
var _knee_r: Node3D
var _arm_l: Node3D
var _elbow_l: Node3D
var _arm_r: Node3D
var _elbow_r: Node3D
var _pose := {}
var _ring: MeshInstance3D
var _arrow: MeshInstance3D
var _aura: Node3D
var _aura_mat: StandardMaterial3D
var _aura_flame: ShaderMaterial
var _aura_light: OmniLight3D
var _aura_particles: CPUParticles3D
var _wall_fx: MeshInstance3D
var _wall_mat: StandardMaterial3D
var _anim_phase := 0.0
var _kick_anim := 0.0
var _kick_was_header := false
var _touch_anim := 0.0
var _touch_leg := 1.0
var _receive_anim := 0.0
var _ghost_t := 0.0
var _dust_t := 0.0
var _turn_rate := 0.0
var _spin := 0.0


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
	return state == State.NORMAL or state == State.DIVE or state == State.DASH or state == State.TACKLE or state == State.POKE


func is_evading() -> bool:
	return m.time < evade_until or m.time < phantom_until


func is_awakened_as(id: String) -> bool:
	return awakened and awakening_id == id


func speed_h() -> float:
	return Vector2(velocity.x, velocity.z).length()


func skill_dir_or_facing() -> Vector3:
	return skill_ball_dir if state == State.SKILL else facing


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
	if want_arm and arm_target != null:
		base = minf(base, 6.0)
	if stamina < 12.0:
		base *= 0.82
	if m.time < grabbed_until:
		base *= 0.75
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
	if m.time < grabbed_until:
		a *= 0.6
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


## `label`: texto del aviso que acompaña a la energía ganada (p. ej. "¡REGATE!").
func gain_energy(a: float, label := "") -> void:
	var before := int(energy / SkillDB.BAR)
	energy = minf(energy + a, SkillDB.MAX_ENERGY)
	if label != "":
		FX.popup(position, "%s +%d" % [label, int(a)] if is_human else label, team.color.lightened(0.5), 0.8)
	elif is_human and a >= 25.0:
		FX.popup(position, "+%d ENERGÍA" % int(a), Color(0.45, 0.9, 1.0), 0.55)
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
	_aura_flame.set_shader_parameter("color", col)
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
	elif state == State.NORMAL and arm_target == null:
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
			_arm_hold(dt)
			_telegraph_tick()
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
		State.POKE:
			velocity = velocity.move_toward(Vector3.ZERO, 14.0 * dt)
			if state_time > 0.04 and state_time < 0.2 and not tackle_done:
				_poke_contact()
			if state_time >= state_dur:
				_set_state(State.NORMAL)
		State.SLIDE:
			velocity = velocity.move_toward(Vector3.ZERO, 8.5 * dt)
			_dust_t -= dt
			if _dust_t <= 0.0 and speed_h() > 2.0:
				_dust_t = 0.05
				FX.dust(position + facing * 0.6, 5)
			if state_time < 0.6 and not tackle_done:
				_tackle_contact(1.1, true)
			if state_time >= state_dur:
				_set_state(State.NORMAL)
		State.SHOULDER:
			velocity = velocity.move_toward(Vector3.ZERO, 10.0 * dt)
			if state_time > 0.08 and not tackle_done:
				_shoulder_contact()
			if state_time >= state_dur:
				_set_state(State.NORMAL)
		State.STUN:
			velocity = velocity.move_toward(Vector3.ZERO, (6.0 if fallen else 10.0) * dt)
			if state_time >= state_dur:
				fallen = false
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
			if skill.get("ghost", false):
				_ghost_t -= dt
				if _ghost_t <= 0.0:
					_ghost_t = 0.03
					FX.afterimage(self, skill.get("color", Color.WHITE), 0.3)
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
	elif has_ball() and md.length() > 0.3:
		# Con balón el cuerpo gira hacia donde apunta el stick (y el balón con él)
		face = md.normalized()
	elif velocity.length() > 0.6:
		face = Vector3(velocity.x, 0.0, velocity.z).normalized()
	var turn_rate := 11.0
	if has_ball():
		turn_rate = 7.0 + 6.0 * st("dribble")
		if want_sprint:
			turn_rate *= 0.75
	var before := facing
	facing = _turn(facing, face, turn_rate * dt)
	if dt > 0.0:
		_turn_rate = lerpf(_turn_rate, before.signed_angle_to(facing, Vector3.UP) / dt, 0.2)


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


func on_ball_touch() -> void:
	_touch_anim = 0.16
	_touch_leg = -_touch_leg


func on_receive() -> void:
	_receive_anim = 0.28
	charge_kind = ""


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
	var windup := 0.1
	if SHOT_KINDS.has(kind):
		windup = 0.17
	if opts.has("special"):
		windup = float(opts.get("windup", 0.22))
	charge_kind = ""
	pending = {"kind": kind, "charge": charge, "opts": opts, "windup": windup, "done": false}
	if ft:
		_execute_kick()
		_set_state(State.KICK, 0.22)
		return
	_set_state(State.KICK, windup + 0.18)


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
		FX.popup(position, "AMAGUE", Color(0.85, 0.9, 1.0), 0.7)
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
	if ft.has("charge"):
		c = ft["charge"]
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
	_kick_was_header = kind == "header"
	spend_stamina(1.5)
	if SHOT_KINDS.has(kind):
		_kick_shot(kind, charge, opts)
	elif PASS_KINDS.has(kind):
		_kick_pass(kind, charge, opts)


## Plan de pase según la dirección del stick (también lo usa el indicador del
## HUD): pase normal al más cercano en esa dirección; al hueco, al espacio
## que hay delante del compañero en la dirección del stick.
func pass_plan(kind: String, charge: float, dir: Vector3) -> Dictionary:
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length() > 0.1 else facing
	if kind.begins_with("through"):
		var t := team.through_target(self, d)
		if t == null:
			return {"target": null, "point": m.clamp_in_field(position + d * (10.0 + charge * 18.0), 1.0)}
		var space_dir := (d * 0.8 + team.attack_dir() * 0.2).normalized()
		var pt := t.position + space_dir * (5.0 + charge * 9.0)
		return {"target": t, "point": m.clamp_in_field(pt, 1.5)}
	var t2 := team.nearest_in_direction(self, d)
	if t2 == null:
		return {"target": null, "point": m.clamp_in_field(position + d * (8.0 + charge * 20.0), 1.0)}
	return {"target": t2, "point": t2.position}


func _kick_pass(kind: String, charge: float, opts: Dictionary) -> void:
	var b := m.ball
	var from := b.position
	var through := kind.begins_with("through")
	var lofted := kind == "pass_lob" or kind == "through_lob" or kind == "cross"
	var sid: String = opts.get("special", "")
	var active: bool = opts.get("aim_active", aim_active)
	var aim: Vector3 = opts.get("aim", aim_dir)
	var target: Player = opts.get("target", null)
	var point: Vector3
	if opts.has("point"):
		point = opts["point"]
	elif target != null:
		point = target.position
		if through:
			point = m.clamp_in_field(target.position + team.attack_dir() * (5.0 + charge * 8.0), 1.5)
	else:
		var plan := pass_plan(kind, charge, aim if active else facing)
		target = plan["target"]
		point = plan["point"]
	# Hacia dónde sale el balón: la del stick ("giroscopio") o recto al objetivo
	var hint := Vector3.ZERO
	if opts.has("hint"):
		hint = opts["hint"]
	elif active and not opts.has("target") and not opts.has("point"):
		hint = aim
	var arrive := 6.5 + charge * 5.0
	if through:
		arrive = 3.5 + charge * 3.0
	if sid != "":
		arrive = 14.0
	var land_y := Ball.RADIUS
	if kind == "cross":
		land_y = 1.5
	if sid == "centro_teledirigido":
		land_y = 1.55
	# Adelantarse a la carrera del receptor
	if target != null and not through and not opts.has("point"):
		for i in 2:
			var d := Match.flat_dist(from, point)
			var t: float
			if lofted:
				t = Kick.lob_time(from.y, _lob_apex(kind, d), land_y)
			else:
				t = Kick.ground_time(Kick.ground_speed_for(d, arrive), d)
			point = m.clamp_in_field(target.position + target.velocity * t * 0.7, 0.5)
	var dist := Match.flat_dist(from, point)
	var land := point
	if lofted and kind != "cross" and sid == "":
		land = from + (point - from) * 0.94
	var res := Kick.curved(from, land, hint, lofted, arrive, _lob_apex(kind, dist), land_y)
	var vel: Vector3 = res["vel"]
	var side: float = res["side"]
	if sid == "pase_meteoro":
		var hv := Vector2(vel.x, vel.z).length()
		if hv < 28.0 and hv > 0.01:
			vel = Vector3(vel.x, 0.0, vel.z) * (28.0 / hv)
			side = 0.0
	var err := (1.0 - st("passing")) * 0.07 + pressure() * 0.04
	if sid != "":
		err = 0.0
	vel = vel.rotated(Vector3.UP, randf_range(-err, err))
	if vel.length() > 40.0:
		vel = vel.normalized() * 40.0
	b.kick(self, vel, "cross" if kind == "cross" else "pass", side, 0.0)
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
		if through:
			target.brain.run_to(point, 2.5)
	if sid == "centro_teledirigido" and target != null:
		var tt := Kick.lob_time(from.y, _lob_apex(kind, dist), land_y)
		target.first_time = {"kind": "shot", "start": m.time, "until": m.time + tt + 0.8, "charge": 0.85}
		if target.brain != null:
			target.brain.run_to(point, tt)
	m.on_pass(self, target, through)


func _lob_apex(kind: String, d: float) -> float:
	if kind == "cross":
		return clampf(2.8 + d * 0.07, 2.8, 7.5)
	return clampf(2.0 + d * 0.11, 2.0, 9.0)


## Intención del tiro: el punto del arco al que "más o menos" apunta el stick.
## Si el stick apunta cerca de un palo se entiende como esa esquina; si apunta
## al centro, al centro; si apunta lejos del arco, el tiro va afuera (a
## propósito). Con el stick suelto, al palo contrario del portero. La altura
## sale de la potencia (poca = abajo, mucha = arriba).
func shot_intent(kind: String, charge: float, aim: Vector3, active: bool, opts: Dictionary) -> Vector3:
	var from := m.ball.position
	var goal := team.opp_goal()
	var half := m.gw * 0.5
	var corner := half - 0.45
	var z_aim: float
	if opts.has("z"):
		z_aim = opts["z"]
	elif not active:
		var gk := team.opponent.gk()
		var gz := gk.position.z if gk != null else 0.0
		if absf(gz) > 0.3:
			z_aim = -signf(gz) * corner
		elif absf(from.z) > 1.5:
			z_aim = -signf(from.z) * corner
		else:
			z_aim = corner * (1.0 if randf() < 0.5 else -1.0)
	else:
		var to_center := Vector3(goal.x - from.x, 0.0, goal.z - from.z).normalized()
		var theta := clampf(to_center.signed_angle_to(Vector3(aim.x, 0.0, aim.z), Vector3.UP), -1.3, 1.3)
		var dir := to_center.rotated(Vector3.UP, theta)
		var dx := goal.x - from.x
		var z_ray: float
		if absf(dir.x) < 0.08 or signf(dir.x) != signf(dx):
			z_ray = signf(dir.z) * (half + 15.0)
		else:
			z_ray = from.z + dir.z * dx / dir.x
		if absf(z_ray) > half + 6.0:
			z_aim = clampf(z_ray, -(half + 15.0), half + 15.0)
		elif absf(z_ray) > half * 0.4:
			z_aim = signf(z_ray) * corner
		else:
			z_aim = z_ray
	var y_aim: float = opts.get("y", lerpf(0.35, m.gh - 0.45, clampf((charge - 0.25) / 0.55, 0.0, 1.0)))
	match kind:
		"ground":
			y_aim = Ball.RADIUS
		"header":
			y_aim = 0.5
		"chip":
			y_aim = m.gh - 0.55
	return Vector3(goal.x, y_aim, z_aim)


## La "ruleta": en el instante del disparo se calcula la probabilidad de que
## vaya al arco y de que sea gol (tiro, curva, potencia, distancia, ángulo,
## presión, portero...) y se resuelve con una tirada. La física después
## solo representa ese resultado.
func resolve_shot(kind: String, charge: float, intent: Vector3, speed: float, sid: String) -> Dictionary:
	var from := m.ball.position
	var half := m.gw * 0.5
	var dist := Match.flat_dist(from, intent)
	var over := maxf(charge - 0.85, 0.0) / 0.15
	var aimed_out := absf(intent.z) > half - 0.25
	var a := Vector3(intent.x, 0, -half) - from
	var b := Vector3(intent.x, 0, half) - from
	a.y = 0.0
	b.y = 0.0
	var angle_score := clampf(a.angle_to(b) / 0.5, 0.0, 1.0)
	# Probabilidad de ir al arco
	var p_t := 0.5 + st("shot_acc") * 0.45 - maxf(dist - 11.0, 0.0) * 0.014 - pressure() * 0.18 \
		- over * 0.45 - (1.0 - angle_score) * 0.12
	match kind:
		"ground":
			p_t += 0.05
		"curve":
			p_t += -0.15 + st("curve") * 0.3
		"chip":
			p_t -= 0.1
		"volley":
			p_t -= 0.15
		"header":
			p_t += -0.08 + (st("jump") - 0.5) * 0.2
	if absf(intent.z) > half * 0.6:
		p_t -= 0.05
	if stamina < 20.0:
		p_t -= 0.08
	if sid != "":
		p_t += 0.3
	p_t = clampf(p_t, 0.05, 0.97)
	if aimed_out:
		p_t = 0.0
	# Probabilidad de que el portero no llegue (si va al arco)
	var gk := team.opponent.gk()
	var p_g := 0.9
	if gk != null:
		var t_arrive := dist / maxf(speed, 8.0)
		var reach := clampf(0.8 + 6.0 * t_arrive, 0.8, 3.2)
		var lateral := absf(intent.z - gk.position.z)
		var rf := clampf((lateral - 0.3) / reach, 0.0, 1.0)
		var placement := absf(intent.z) / half
		p_g = 0.05 + (speed - 18.0) * 0.02 + placement * 0.25 + rf * 0.3 - gk.st("reflex") * 0.35 - m.gk_bonus(gk.team)
		if kind == "curve":
			p_g += st("curve") * 0.12
		if intent.y < 0.6 or intent.y > m.gh - 0.8:
			p_g += 0.06
		if sid != "":
			p_g += float(SkillDB.special(sid).get("break", 0.3))
		p_g = clampf(p_g, 0.03, 0.95)
	var on_target := randf() < p_t
	var goal := on_target and randf() < p_g
	return {"p_target": p_t, "p_goal": p_t * p_g, "on_target": on_target, "goal": goal}


## Ajusta el punto final según el resultado de la ruleta, lo más cerca
## posible de donde apuntaste.
func _shot_final_target(intent: Vector3, res: Dictionary, kind: String, charge: float) -> Vector3:
	var half := m.gw * 0.5
	var t := intent
	var gk := team.opponent.gk()
	if res["goal"]:
		t.z = clampf(t.z, -(half - 0.35), half - 0.35)
		t.y = clampf(t.y, Ball.RADIUS, m.gh - 0.35)
		if gk != null and absf(t.z - gk.position.z) < 1.2:
			# Lejos de las manos del portero, sin salir del arco
			var away := signf(t.z - gk.position.z) if absf(t.z - gk.position.z) > 0.05 else (1.0 if randf() < 0.5 else -1.0)
			t.z = clampf(t.z + away * 0.9, -(half - 0.35), half - 0.35)
	elif res["on_target"]:
		t.z = clampf(t.z, -(half - 0.35), half - 0.35)
		t.y = clampf(t.y, Ball.RADIUS, m.gh - 0.35)
		if gk != null:
			# Al alcance del portero (ataja o despeja)
			var dz := t.z - gk.position.z
			if absf(dz) > 1.6:
				t.z = gk.position.z + signf(dz) * 1.6
			t.y = minf(t.y, 2.0)
	else:
		var over := maxf(charge - 0.85, 0.0) / 0.15
		var side := signf(t.z) if absf(t.z) > 0.2 else (1.0 if randf() < 0.5 else -1.0)
		if absf(t.z) > half + 0.5:
			pass  # Apuntó afuera: va donde apuntó
		elif randf() < 0.15:
			# Al palo (por la cara externa: rebota afuera)
			t.z = side * (half + Ball.POST_RADIUS + Ball.RADIUS * 0.6)
		elif over > 0.2 or kind == "chip" or (kind != "curve" and kind != "ground" and randf() < 0.45):
			t.y = m.gh + randf_range(0.5, 1.6)
		else:
			t.z = side * (half + randf_range(0.5, 1.8))
	return t


func _kick_shot(kind: String, charge: float, opts: Dictionary) -> void:
	var b := m.ball
	var from := b.position
	var half := m.gw * 0.5
	var sid: String = opts.get("special", "")
	var active: bool = opts.get("aim_active", aim_active)
	var aim: Vector3 = opts.get("aim", aim_dir)
	var intent := shot_intent(kind, charge, aim, active, opts)
	var power_mul := 0.85 + 0.3 * st("shot_power")
	if is_awakened_as("tiro"):
		power_mul *= 1.2
	var speed := lerpf(15.0, 31.0, charge) * power_mul
	var top := 0.12
	var side := 0.0
	match kind:
		"ground":
			speed *= 0.92
			top = 0.0
		"volley":
			speed *= 1.05
		"header":
			speed = (11.0 + 9.0 * charge) * (1.35 if is_awakened_as("salto") else 1.0)
			top = 0.0
			gain_energy(SkillDB.GAIN["header"])
		"curve":
			speed = lerpf(14.0, 27.0, charge) * power_mul
	var sd := {}
	if sid != "":
		sd = SkillDB.special(sid)
		match sid:
			"disparo_directo":
				speed = 36.0 * (1.1 if is_awakened_as("tiro") else 1.0)
				top = 0.5
				intent.y = clampf(intent.y, 0.5, m.gh - 0.6)
			"curva_del_ego":
				speed = 30.0
				top = 0.3
				intent.y = clampf(intent.y, 0.6, m.gh - 0.5)
			"tiro_fantasma":
				speed = 31.0
				top = 0.0
				intent.y = clampf(intent.y, 0.6, m.gh - 0.6)
			"meteoro_descendente":
				speed = 33.0
				top = 1.3
				intent.y = m.gh - 0.4
				if absf(intent.z) <= half:
					intent.z = (signf(intent.z) if absf(intent.z) > 0.01 else 1.0) * (half - 0.45)
	var res := resolve_shot(kind, charge, intent, speed, sid)
	var target := _shot_final_target(intent, res, kind, charge)
	target.y = maxf(target.y, Ball.RADIUS)
	var dist := Match.flat_dist(from, target)
	var dir := Vector3(target.x - from.x, 0.0, target.z - from.z).normalized()
	var lat := Vector3.UP.cross(dir)
	var inward := signf(lat.dot(Vector3(0, 0, -target.z))) if absf(target.z) > 0.15 else signf(facing.cross(dir).y + 0.001)
	if (kind == "shot" or kind == "volley") and sid == "":
		var crossv := facing.cross(dir).y
		side = clampf(crossv * 1.5, -1.0, 1.0) * (0.25 + (1.0 - charge) * 0.4) * (0.5 + st("curve") * 0.6)
	elif kind == "curve":
		side = (0.6 + st("curve") * 0.5) * inward
	match sid:
		"curva_del_ego":
			side = 1.35 * inward
		"meteoro_descendente":
			side = 0.45 * inward
	var vel: Vector3
	if kind == "chip":
		var apex := clampf(3.0 + dist * 0.09, 3.2, 9.0)
		vel = Kick.lob(from, target, apex, target.y)
		top = 0.0
		side = 0.0
	elif kind == "ground":
		vel = dir * speed
	else:
		vel = Kick.aimed(from, target, speed, top, side)
	b.kick(self, vel, "shot", side, top)
	b.shot_result = "goal" if res["goal"] else ("save" if res["on_target"] else "miss")
	b.shot_prob = res["p_goal"]
	m.on_shot_resolved(self, res)
	if sid != "":
		b.special_id = sid
		b.special_break = float(sd.get("break", 0.3))
		b.set_trail(true, sd["color"])
		if sid == "tiro_fantasma" and not res["goal"]:
			b.knuckle = 0.4
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
	m.stats["tackle_attempts"] += 1
	_face_ball_if_near(3.5)
	_set_state(State.TACKLE, 0.42)
	tackle_done = false
	spend_stamina(5.0)
	velocity = facing * maxf(speed_h(), 6.5)


func do_slide() -> void:
	if not can_act() or has_ball():
		return
	m.stats["tackle_attempts"] += 1
	_face_ball_if_near(8.0)
	_set_state(State.SLIDE, 0.85)
	tackle_done = false
	spend_stamina(10.0)
	velocity = facing * maxf(speed_h() + 2.5, 9.0)
	FX.dust(position, 10)


## "Meter el pie": estocada corta que suelta el balón (no lo roba).
func do_poke() -> void:
	if not can_act() or has_ball():
		return
	m.stats["tackle_attempts"] += 1
	_face_ball_if_near(3.0)
	_set_state(State.POKE, 0.28)
	tackle_done = false
	spend_stamina(3.0)
	velocity *= 0.6


func do_shoulder() -> void:
	if not can_act() or has_ball():
		return
	_face_ball_if_near(2.5)
	_set_state(State.SHOULDER, 0.3)
	tackle_done = false
	spend_stamina(7.0)
	velocity += facing * 2.0


## La IA anuncia el quite un instante antes (aparece "!" sobre su cabeza).
func prepare_tackle(kind: String, delay: float) -> void:
	if not can_act() or has_ball() or not _tele.is_empty():
		return
	_tele = {"kind": kind, "until": m.time + delay}
	_face_ball_if_near(4.0)


func _telegraph_tick() -> void:
	if _tele.is_empty() or m.time < float(_tele["until"]):
		return
	var kind: String = _tele["kind"]
	_tele = {}
	# Si el rival ya se escapó durante el aviso, no se tira al vacío
	var limit := 4.0 if kind == "slide" else 2.4
	if Match.flat_dist(m.ball.position, position) > limit:
		return
	match kind:
		"tackle":
			do_tackle()
		"poke":
			do_poke()
		"shoulder":
			do_shoulder()
		"slide":
			do_slide()


## Reacción del regateador cuando esquiva un intento de quite: salto corto,
## estela y aviso; quien intentó el quite queda descolocado.
func _on_evaded(by: Player) -> void:
	if height <= 0.01:
		y_vel = 3.2
	FX.afterimage(self, team.color.lightened(0.5), 0.35)
	FX.hitstop(0.05)
	gain_energy(SkillDB.GAIN["evade"], "¡ESQUIVA!")
	m.stats["evades"] += 1
	if by.state != State.SLIDE:
		by.stun(0.4, false)


## Mira hacia donde ESTARÁ el balón (el portador sigue corriendo).
func _face_ball_if_near(r: float) -> void:
	var lead := m.ball.position
	if m.ball.carrier != null and m.ball.carrier != self:
		lead += Vector3(m.ball.carrier.velocity.x, 0.0, m.ball.carrier.velocity.z) * 0.18
	var to := flat_to(lead)
	if to.length() < r and to.length() > 0.05:
		facing = to.normalized()


func _won_ball_fx(text: String) -> void:
	gain_energy(SkillDB.GAIN["tackle"])
	m.stats["tackles"] += 1
	m.notify("%s de %s" % [text.capitalize(), player_name], team.color.lightened(0.3))
	FX.popup(position, text, team.color.lightened(0.45))
	FX.burst(m.ball.position + Vector3.UP * 0.3, Color(1, 1, 1), 18, 5.0, 0.4)
	FX.ring(position, team.color.lightened(0.3), 2.5, 0.35)
	FX.hitstop(0.07)


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
		if slide:
			FX.popup(position, "¡BARRIDA!", Color(1.0, 0.85, 0.4), 0.8)
		return
	if c.is_evading():
		m.notify("¡%s lo esquiva!" % c.player_name, c.team.color.lightened(0.3))
		c._on_evaded(self)
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
		c.stun(0.9 if slide else 0.6, true)
		c.dribble_check = {}
		if not slide and randf() < 0.55:
			b.set_carrier(self)
		else:
			var lat := facing.cross(Vector3.UP) * randf_range(-3.0, 3.0)
			b.kick(self, facing * 6.0 + lat + Vector3.UP * 0.8, "tackle")
		_won_ball_fx("¡BARRIDA!" if slide else "¡QUITE!")
	else:
		# El regateador aguanta el intento
		c.gain_energy(SkillDB.GAIN["resist"])
		m.stats["resists"] += 1
		FX.popup(c.position, "¡RESISTE!", c.team.color.lightened(0.5), 0.75)
		if not slide:
			stun(0.25, false)


func _poke_contact() -> void:
	var b := m.ball
	var c := b.carrier
	if c == self or (c != null and c.team == team):
		return
	if b.position.y - height > 0.6:
		return
	var d := Match.flat_dist(b.position, position + facing * 0.5)
	if d > 1.35 + st("tackle") * 0.2:
		return
	tackle_done = true
	var lat := facing.cross(Vector3.UP) * randf_range(-3.0, 3.0)
	if c == null:
		b.kick(self, facing * 5.0 + lat, "tackle")
		return
	if c.is_evading():
		c._on_evaded(self)
		return
	var ball_far := Match.flat_dist(b.position, c.position) > 0.8
	var p := 0.55 + (st("tackle") - c.st("dribble")) * 0.5 + (0.12 if ball_far else 0.0) - (0.2 if c.want_shield else 0.0)
	p += m.tackle_bonus(team)
	if randf() < clampf(p, 0.15, 0.9):
		b.kick(self, facing * 4.0 + lat + Vector3.UP * 0.4, "tackle")
		c.stun(0.25, false)
		c.dribble_check = {}
		gain_energy(SkillDB.GAIN["poke"])
		m.stats["tackles"] += 1
		FX.popup(position, "¡LE METE EL PIE!", team.color.lightened(0.45), 0.85)
		FX.burst(b.position + Vector3.UP * 0.2, Color(1, 1, 1), 12, 4.0, 0.35)
		FX.hitstop(0.05)
	else:
		c.gain_energy(SkillDB.GAIN["resist"])
		FX.popup(c.position, "¡RESISTE!", c.team.color.lightened(0.5), 0.7)


## Agarrar con el brazo (mantener Cuadrado al lado o detrás del rival): lo
## frena y lo cansa; tras un rato gana el más fuerte. Si te pasas, es falta.
func _arm_hold(dt: float) -> void:
	var c := m.ball.carrier
	if not want_arm or has_ball() or c == null or c.team == team or Match.flat_dist(c.position, position) > 1.7:
		arm_target = null
		arm_time = 0.0
		_arm_resolved = false
		return
	arm_target = c
	arm_time += dt
	c.grabbed_until = m.time + 0.15
	c.spend_stamina(4.0 * dt)
	spend_stamina(2.0 * dt)
	has_look = true
	look_target = c.position
	if arm_time > 0.7 and not _arm_resolved:
		_arm_resolved = true
		var mine := st("strength") + stamina / 250.0 + randf() * 0.4
		var theirs := c.st("strength") + c.stamina / 250.0 + randf() * 0.4 + (0.15 if c.want_shield else 0.0)
		if mine > theirs:
			m.ball.kick(self, c.velocity * 0.6 + flat_to(c.position).normalized() * -1.5, "tackle")
			c.stun(0.5, false)
			gain_energy(SkillDB.GAIN["poke"])
			m.stats["tackles"] += 1
			FX.popup(position, "¡FORCEJEO GANADO!", team.color.lightened(0.45), 0.8)
			FX.hitstop(0.05)
		else:
			c.gain_energy(8.0)
			FX.popup(c.position, "¡AGUANTA!", c.team.color.lightened(0.45), 0.7)
	if arm_time > 1.6:
		arm_time = 0.0
		m.foul(self, c)


func _shoulder_contact() -> void:
	tackle_done = true
	var b := m.ball
	var c := b.carrier
	if c == null or c.team == team:
		return
	if Match.flat_dist(c.position, position) > 1.7:
		return
	if c.is_evading():
		c._on_evaded(self)
		return
	var mine := st("strength") + stamina / 250.0 + randf() * 0.35
	var theirs := c.st("strength") + c.stamina / 250.0 + randf() * 0.35 + (0.2 if c.want_shield else 0.0)
	if mine > theirs:
		var v := c.velocity * 0.6 + facing * 2.5
		c.stun(0.6, true)
		b.kick(self, v, "tackle")
		gain_energy(18.0)
		m.stats["tackles"] += 1
		FX.popup(position, "¡CHOQUE!", team.color.lightened(0.45), 0.85)
		FX.hitstop(0.06)
		FX.shake(0.3)
	else:
		stun(0.45, false)
		c.gain_energy(8.0)
		FX.popup(c.position, "¡AGUANTA!", c.team.color.lightened(0.45), 0.7)


## `fall`: el jugador cae al suelo (queda claro que perdió el duelo).
func stun(t: float, fall := false) -> void:
	charge_kind = ""
	pending = {}
	_tele = {}
	arm_target = null
	if has_ball():
		m.ball.kick(self, velocity * 0.5, "drop")
	fallen = fall
	_set_state(State.STUN, t + (0.3 if fall else 0.0))


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
		c.stun(0.5, true)
		m.ball.set_carrier(self)
		FX.popup(position, "¡A LOS PIES!", team.color.lightened(0.5), 0.85)
		FX.hitstop(0.06)


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
	if opp != null and Match.flat_dist(opp.position, position) < 3.5:
		dribble_check["skill"] = enhanced
	match kind:
		"toque_largo":
			b.kick(self, fwd * (10.0 + st("speed") * 3.0), "knock")
			no_touch_until = m.time + 0.12
			burst_until = m.time + 0.9
			_flick_anim = 0.22
			_kick_was_header = false
		"sombrero":
			var tgt := position + fwd * 5.0
			b.kick(self, Kick.lob(b.position, tgt, 2.7, Ball.RADIUS), "knock")
			no_touch_until = m.time + 0.35
			evade_until = m.time + 0.7
			burst_until = m.time + 1.0
			_flick_anim = 0.3
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
	if state == State.SKILL:
		skill["kind"] = kind
		skill["ghost"] = enhanced
		skill["color"] = Color(1.0, 0.85, 0.4)
	skill_flash = {"kind": kind, "t": 0.0}
	gain_energy(3.0)
	var col := Color(0.9, 0.92, 1.0) if not enhanced else Color(1.0, 0.85, 0.4)
	m.notify(SkillDB.SKILL_MOVE_NAMES[kind], col)
	FX.popup(position, SkillDB.SKILL_MOVE_NAMES[kind].to_upper(), col, 0.55 if not enhanced else 0.7)
	FX.afterimage(self, col, 0.3)
	m.stats["skill_moves"] += 1


func _start_skill(dir: Vector3, dist: float, dur: float, evade: float, ball_dir: Vector3) -> void:
	skill = {"dir": dir, "speed": dist / dur}
	skill_ball_dir = ball_dir
	evade_until = m.time + evade
	_set_state(State.SKILL, dur)
	if has_ball():
		m.ball.force_touch()


func _dribble_reward() -> void:
	if dribble_check.is_empty() or m.time < float(dribble_check["until"]):
		return
	var was_skill: bool = dribble_check.get("skill", false)
	dribble_check = {}
	if team.has_ball() or (m.ball.carrier == null and m.ball.last_touch == self):
		gain_energy(SkillDB.GAIN["dribble_skill"] if was_skill else SkillDB.GAIN["dribble"], "¡REGATE!")
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
	var dir := aim_dir if aim_active else facing
	match sd["kind"]:
		"pass":
			if has_ball() and not restart_lock:
				ok = _special_pass(sid, dir)
		"shot":
			if has_ball() and (not restart_lock or restart_kind == "penalty" or restart_kind == "free_kick"):
				perform("curve" if sid == "curva_del_ego" else "shot", 1.0, {"special": sid, "windup": 0.22})
				ok = true
		"dribble":
			if has_ball() and not restart_lock:
				ok = _special_dribble(sid, dir)
		"tackle":
			if not has_ball():
				if sid == "muro_de_acero":
					wall_until = m.time + 3.0
					ok = true
				else:
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


func _special_pass(sid: String, dir: Vector3) -> bool:
	match sid:
		"pase_meteoro":
			var t := team.nearest_in_direction(self, dir)
			if t == null:
				return false
			perform("pass", 1.0, {"special": sid, "target": t, "windup": 0.18})
		"pase_bumeran":
			var t2 := team.nearest_in_direction(self, dir)
			if t2 == null:
				return false
			# Sale abierto hacia el lado con menos rivales y se cierra al compañero
			var to := flat_to(t2.position).normalized()
			var left := to.rotated(Vector3.UP, deg_to_rad(28.0))
			var right := to.rotated(Vector3.UP, deg_to_rad(-28.0))
			var hint := left if _crowd(left) < _crowd(right) else right
			perform("pass", 0.7, {"special": sid, "target": t2, "hint": hint, "windup": 0.18})
		"centro_teledirigido":
			var t3 := team.through_target(self, dir)
			if t3 == null:
				t3 = team.nearest_in_direction(self, dir)
			if t3 == null:
				return false
			perform("cross", 0.8, {"special": sid, "target": t3, "windup": 0.2})
		_:
			return false
	return true


func _crowd(dir: Vector3) -> float:
	var c := 0.0
	for o in team.opponent.players:
		var rel := flat_to(o.position)
		var d := rel.length()
		if d < 20.0 and d > 0.1:
			c += maxf(rel.normalized().dot(dir), 0.0) / d
	return c


func _special_dribble(sid: String, dir: Vector3) -> bool:
	var sd := SkillDB.special(sid)
	match sid:
		"regate_fantasma":
			phantom_until = m.time + 1.3
			evade_until = phantom_until
			burst_until = phantom_until
			phantom_hit = {}
		"regate_relampago":
			var d := dir
			if not aim_active:
				var o := nearest_opponent()
				var side := facing.cross(Vector3.UP)
				if o != null and side.dot(flat_to(o.position)) > 0.0:
					side = -side
				d = (facing * 0.5 + side).normalized()
			_start_skill(d, 4.5, 0.2, 0.55, d)
			skill["ghost"] = true
			skill["color"] = sd["color"]
		"sombrero_celestial":
			var b := m.ball
			var tgt := m.clamp_in_field(position + facing * 7.0, 1.0)
			b.kick(self, Kick.lob(b.position, tgt, 3.2, Ball.RADIUS), "knock")
			b.shield_team = team_id
			b.set_trail(true, sd["color"])
			no_touch_until = m.time + 0.45
			evade_until = m.time + 1.1
			burst_until = m.time + 1.3
		"torbellino":
			_start_skill(facing, 1.5, 0.55, 0.65, facing)
			skill["spin"] = true
			for o in team.opponent.players:
				if o.role != Role.GK and Match.flat_dist(o.position, position) < 2.8:
					o.stun(0.9, true)
			FX.ring(position, sd["color"], 3.5, 0.5)
		_:
			return false
	return true


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
				FX.popup(c.position, "¡INTOCABLE!", c.team.color.lightened(0.5), 0.9)
				stun(0.5, true)
				return
			c.stun(0.8, true)
			b.set_carrier(self)
			_won_ball_fx("¡ROBO!")
		elif c == null:
			if b.shield_team >= 0 and b.shield_team != team_id and randf() < 0.5:
				m.notify("¡El pase es demasiado rápido!", Color(0.8, 0.8, 0.9))
			else:
				b.set_carrier(self, true)
				m.stats["interceptions"] += 1
				FX.popup(position, "¡CORTADO!", team.color.lightened(0.5))
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
	_wall_fx.visible = m.time < wall_until
	if _wall_fx.visible:
		_wall_mat.albedo_color.a = 0.18 + sin(m.time * 12.0) * 0.06
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
				o.stun(0.8, true)
				m.notify("¡Tobillos rotos!", Color(0.8, 0.55, 1.0))
				FX.popup(o.position, "¡TOBILLOS ROTOS!", Color(0.85, 0.6, 1.0), 0.75)


# ---------------------------------------------------------------- visual

func _build_visual() -> void:
	var gk := role == Role.GK
	var shirt := team.gk_color if gk else team.color
	var mine := is_human and team.id == 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(player_name + str(team_id) + str(number))
	var skin: Color = GameConfig.profile["skin"] if mine else Color(0.96, 0.8, 0.66).lerp(Color(0.55, 0.38, 0.26), rng.randf() * 0.6)
	var hair_palette := [Color(0.07, 0.07, 0.09), Color(0.25, 0.15, 0.08), Color(0.95, 0.85, 0.5), Color(0.85, 0.2, 0.15),
		Color(0.9, 0.9, 0.95), Color(0.15, 0.25, 0.6), Color(0.4, 0.75, 0.35), Color(0.6, 0.35, 0.8)]
	var hair: Color = GameConfig.profile["hair"] if mine else hair_palette[rng.randi() % hair_palette.size()]
	var eye_col: Color = [Color(0.15, 0.4, 0.9), Color(0.35, 0.22, 0.1), Color(0.2, 0.7, 0.4), Color(0.75, 0.2, 0.25), Color(0.85, 0.65, 0.15)][rng.randi() % 5]
	if mine:
		eye_col = GameConfig.profile.get("eyes", Color(0.15, 0.4, 0.9))
	var shirt_mat := _mat(shirt)
	var trim_mat := _mat(shirt.darkened(0.35) if not gk else shirt.lightened(0.3))
	var shorts_mat := _mat(team.color2 if not gk else Color(0.12, 0.12, 0.14))
	var skin_mat := _mat(skin)
	var sock_mat := _mat(shirt.darkened(0.25) if not gk else Color(0.15, 0.15, 0.15))
	var boot_mat := _mat(Color(0.95, 0.95, 0.98) if rng.randf() < 0.3 else Color(0.08, 0.08, 0.1))
	var glove_mat := _mat(Color(0.97, 0.97, 0.97))
	var hair_mat := _mat(hair)

	_root = Node3D.new()
	add_child(_root)
	_pelvis = Node3D.new()
	_pelvis.position.y = HIP_Y
	_root.add_child(_pelvis)
	var shorts := _mesh_child(_pelvis, _cyl(0.2, 0.26), shorts_mat, Vector3(0, 0.02, 0))
	shorts.scale = Vector3(1.05, 1.0, 0.8)

	_torso = Node3D.new()
	_torso.position.y = 0.1
	_pelvis.add_child(_torso)
	# Torso atlético: hombros anchos, cintura estrecha
	var chest := _mesh_child(_torso, _capsule(0.235, 0.66), shirt_mat, Vector3(0, 0.34, 0))
	chest.scale = Vector3(1.12, 1.0, 0.68)
	var waist := _mesh_child(_torso, _cyl(0.2, 0.2), shirt_mat, Vector3(0, 0.08, 0))
	waist.scale = Vector3(1.0, 1.0, 0.75)
	var collar := _mesh_child(_torso, _torus(0.07, 0.1), trim_mat, Vector3(0, 0.66, 0))
	collar.scale = Vector3(1.0, 0.6, 1.0)
	_mesh_child(_torso, _cyl(0.055, 0.12), skin_mat, Vector3(0, 0.7, 0))
	_head = Node3D.new()
	_head.position.y = 0.74
	_torso.add_child(_head)
	_build_anime_head(skin_mat, hair_mat, eye_col, rng)

	_arm_l = _joint(_torso, Vector3(-0.3, 0.58, 0))
	_mesh_child(_arm_l, _sphere(0.062), shirt_mat, Vector3(0, -0.03, 0))
	_mesh_child(_arm_l, _cyl(0.062, 0.16), shirt_mat, Vector3(0, -0.08, 0))
	_mesh_child(_arm_l, _cyl(0.05, 0.16), skin_mat, Vector3(0, -0.22, 0))
	_elbow_l = _joint(_arm_l, Vector3(0, -0.3, 0))
	_mesh_child(_elbow_l, _cyl(0.046, 0.26), skin_mat, Vector3(0, -0.13, 0))
	_mesh_child(_elbow_l, _sphere(0.085 if gk else 0.052), glove_mat if gk else skin_mat, Vector3(0, -0.29, 0))
	_arm_r = _joint(_torso, Vector3(0.3, 0.58, 0))
	_mesh_child(_arm_r, _sphere(0.062), shirt_mat, Vector3(0, -0.03, 0))
	_mesh_child(_arm_r, _cyl(0.062, 0.16), shirt_mat, Vector3(0, -0.08, 0))
	_mesh_child(_arm_r, _cyl(0.05, 0.16), skin_mat, Vector3(0, -0.22, 0))
	_elbow_r = _joint(_arm_r, Vector3(0, -0.3, 0))
	_mesh_child(_elbow_r, _cyl(0.046, 0.26), skin_mat, Vector3(0, -0.13, 0))
	_mesh_child(_elbow_r, _sphere(0.085 if gk else 0.052), glove_mat if gk else skin_mat, Vector3(0, -0.29, 0))

	_thigh_l = _joint(_pelvis, Vector3(-0.11, -0.04, 0))
	_mesh_child(_thigh_l, _cyl(0.088, 0.45), skin_mat, Vector3(0, -0.225, 0))
	_knee_l = _joint(_thigh_l, Vector3(0, -0.45, 0))
	_mesh_child(_knee_l, _cyl(0.07, 0.42), sock_mat, Vector3(0, -0.21, 0))
	var boot_l := _mesh_child(_knee_l, _capsule(0.055, 0.26), boot_mat, Vector3(0, -0.41, -0.05))
	boot_l.rotation_degrees = Vector3(90, 0, 0)
	_thigh_r = _joint(_pelvis, Vector3(0.11, -0.04, 0))
	_mesh_child(_thigh_r, _cyl(0.088, 0.45), skin_mat, Vector3(0, -0.225, 0))
	_knee_r = _joint(_thigh_r, Vector3(0, -0.45, 0))
	_mesh_child(_knee_r, _cyl(0.07, 0.42), sock_mat, Vector3(0, -0.21, 0))
	var boot_r := _mesh_child(_knee_r, _capsule(0.055, 0.26), boot_mat, Vector3(0, -0.41, -0.05))
	boot_r.rotation_degrees = Vector3(90, 0, 0)

	var num := Label3D.new()
	num.text = str(number)
	num.font_size = 72
	num.pixel_size = 0.0042
	num.outline_size = 8
	num.modulate = team.color2 if not gk else Color(0.1, 0.1, 0.1)
	num.position = Vector3(0, 0.33, 0.175)
	_torso.add_child(num)

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
	var aura_cyl := CylinderMesh.new()
	aura_cyl.top_radius = 0.35
	aura_cyl.bottom_radius = 0.75
	aura_cyl.height = 2.6
	aura_cyl.cap_top = false
	aura_cyl.cap_bottom = false
	aura_mi.mesh = aura_cyl
	_aura_mat = _fx_mat(Color(0.3, 0.6, 1.0, 0.2))
	_aura_flame = ShaderMaterial.new()
	_aura_flame.shader = load("res://shaders/aura.gdshader")
	aura_mi.material_override = _aura_flame
	aura_mi.position.y = 1.2
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

	_wall_fx = MeshInstance3D.new()
	_wall_fx.mesh = _sphere(2.2)
	_wall_mat = _fx_mat(Color(0.7, 0.82, 1.0, 0.2))
	_wall_fx.material_override = _wall_mat
	_wall_fx.position.y = 0.6
	_wall_fx.scale = Vector3(1.0, 0.6, 1.0)
	_wall_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall_fx.set_meta("no_ghost", true)
	_wall_fx.visible = false
	add_child(_wall_fx)
	_alert = Label3D.new()
	_alert.text = "!"
	_alert.font_size = 120
	_alert.pixel_size = 0.008
	_alert.outline_size = 24
	_alert.modulate = Color(1.0, 0.2, 0.15)
	_alert.outline_modulate = Color(1, 1, 1)
	_alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert.no_depth_test = true
	_alert.position.y = 2.5
	_alert.visible = false
	add_child(_alert)
	set_human(is_human)


func set_human(h: bool) -> void:
	is_human = h
	if _ring != null:
		_ring.visible = h
		_arrow.visible = h


## Animación procedural: se calcula una pose objetivo según el estado y se
## interpola suavemente hacia ella (sin saltos bruscos entre poses).
func _animate(dt: float) -> void:
	_kick_anim = maxf(_kick_anim - dt, 0.0)
	_flick_anim = maxf(_flick_anim - dt, 0.0)
	_update_alert()
	_touch_anim = maxf(_touch_anim - dt, 0.0)
	_receive_anim = maxf(_receive_anim - dt, 0.0)
	var spd := speed_h()
	var k := clampf(spd / 8.5, 0.0, 1.0)
	var moving := clampf(spd / 1.2, 0.0, 1.0)
	if spd > 0.3:
		_anim_phase += dt * (7.0 + spd * 1.3)
	var s := sin(_anim_phase)
	var c := cos(_anim_phase)
	var amp := (0.3 + 0.65 * k) * moving
	var t := {
		"root_x": 0.0, "root_z": 0.0, "root_y": 0.0,
		"pelvis_y": HIP_Y - 0.05 * k * absf(c),
		"torso_x": -0.06 - 0.24 * k, "torso_z": 0.0, "torso_y": 0.18 * amp * s, "head_x": 0.08 * k,
		"thigh_l": amp * s, "thigh_l_z": 0.0, "knee_l": 0.12 + (0.35 + 1.0 * k) * maxf(0.0, c) * moving,
		"thigh_r": -amp * s, "thigh_r_z": 0.0, "knee_r": 0.12 + (0.35 + 1.0 * k) * maxf(0.0, -c) * moving,
		"arm_l": -0.8 * amp * s, "arm_l_z": 0.12, "elbow_l": 0.35 + 0.9 * k,
		"arm_r": 0.8 * amp * s, "arm_r_z": 0.12, "elbow_r": 0.35 + 0.9 * k,
	}
	if spd < 0.3:
		t["torso_x"] = -0.02 + sin(m.time * 2.2 + number) * 0.025
	# Inclinarse hacia el lado del giro
	t["root_z"] = clampf(_turn_rate * spd * 0.012, -0.28, 0.28)
	var rate := 18.0
	var gk := role == Role.GK

	# Posturas de contexto
	if state == State.NORMAL:
		if want_mark and not has_ball():
			t["pelvis_y"] = HIP_Y - 0.14
			t["thigh_l"] = float(t["thigh_l"]) * 0.4 + 0.45
			t["thigh_r"] = float(t["thigh_r"]) * 0.4 + 0.45
			t["knee_l"] = 0.85
			t["knee_r"] = 0.85
			t["torso_x"] = -0.1
			t["arm_l_z"] = 0.55
			t["arm_r_z"] = 0.55
		if want_shield and has_ball():
			t["torso_x"] = 0.12
			t["arm_l_z"] = 1.1
			t["arm_r_z"] = 0.7
			t["pelvis_y"] = HIP_Y - 0.07
		if arm_target != null:
			var side_sign := signf(facing.cross(flat_to(arm_target.position)).y)
			t["arm_r"] = 1.45
			t["elbow_r"] = 0.15
			t["arm_r_z"] = 0.3
			t["torso_z"] = 0.25 * side_sign
		if gk and not has_ball() and spd < 2.0:
			t["pelvis_y"] = HIP_Y - 0.12
			t["knee_l"] = 0.55
			t["knee_r"] = 0.55
			t["thigh_l"] = 0.3
			t["thigh_r"] = 0.3
			t["arm_l_z"] = 0.6
			t["arm_r_z"] = 0.6
			t["elbow_l"] = 0.7
			t["elbow_r"] = 0.7
		if has_ball() and gk and m.in_box(team, position):
			t["arm_l"] = 1.2
			t["arm_r"] = 1.2
			t["elbow_l"] = 0.9
			t["elbow_r"] = 0.9
	if height > 0.05:
		t["knee_l"] = 0.9
		t["knee_r"] = 0.6
		t["thigh_l"] = 0.5
		t["arm_l"] = -0.4
		t["arm_r"] = -0.4
		t["arm_l_z"] = 0.6
		t["arm_r_z"] = 0.6
	# Toques de conducción y recepción
	if _touch_anim > 0.0 and state == State.NORMAL:
		var tp := sin((1.0 - _touch_anim / 0.16) * PI)
		var leg := "thigh_r" if _touch_leg > 0.0 else "thigh_l"
		t[leg] = float(t[leg]) * 0.5 + 0.55 * tp
	if _receive_anim > 0.0 and state == State.NORMAL:
		var rp := sin((1.0 - _receive_anim / 0.28) * PI)
		t["thigh_r"] = 0.7 * rp
		t["knee_r"] = 0.5 * rp
		t["torso_x"] = -0.15
		t["arm_l_z"] = 0.5
	match state:
		State.KICK:
			rate = 30.0
			var is_pass := PASS_KINDS.has(String(pending.get("kind", "")))
			if not pending.get("done", true):
				# Armado: pierna atrás, cuerpo hacia atrás, brazo opuesto abierto
				t["thigh_r"] = -0.45 if is_pass else -0.8
				t["knee_r"] = 0.9 if is_pass else 1.4
				t["thigh_l"] = 0.12
				t["knee_l"] = 0.3
				t["torso_x"] = 0.14
				t["arm_l"] = 0.5
				t["arm_l_z"] = 0.8
				t["arm_r_z"] = 0.4
	if _flick_anim > 0.0 and state == State.NORMAL:
		# Toque largo: empuje con el empeine · sombrero: taco hacia arriba
		rate = 36.0
		var fp := 1.0 - _flick_anim / 0.3
		if String(skill_flash.get("kind", "")) == "sombrero":
			t["thigh_r"] = -0.3 - 0.4 * sin(fp * PI)
			t["knee_r"] = 1.7 * sin(fp * PI)
			t["torso_x"] = -0.2
			t["arm_l_z"] = 0.9
			t["arm_r_z"] = 0.9
		else:
			t["thigh_r"] = 0.9 * sin(fp * PI)
			t["knee_r"] = 0.2
			t["torso_x"] = -0.3
	if _kick_anim > 0.0:
		rate = 40.0
		var p := 1.0 - _kick_anim / 0.3
		if _kick_was_header:
			t["torso_x"] = -0.7 * sin(p * PI)
			t["head_x"] = -0.5 * sin(p * PI)
		else:
			t["thigh_r"] = lerpf(-0.8, 1.45, clampf(p * 2.5, 0.0, 1.0))
			t["knee_r"] = lerpf(1.4, 0.05, clampf(p * 3.0, 0.0, 1.0))
			t["thigh_l"] = 0.1
			t["knee_l"] = 0.25
			t["torso_x"] = lerpf(0.14, -0.18, p)
			t["arm_l"] = 0.8
			t["arm_l_z"] = 0.7
			t["arm_r"] = -0.5
	match state:
		State.TACKLE, State.POKE:
			rate = 30.0
			t["thigh_r"] = 1.3 if state == State.TACKLE else 1.0
			t["knee_r"] = 0.1
			t["thigh_r_z"] = 0.25
			t["thigh_l"] = -0.35
			t["knee_l"] = 0.8
			t["pelvis_y"] = HIP_Y - (0.2 if state == State.TACKLE else 0.12)
			t["torso_x"] = -0.35
			t["arm_l_z"] = 0.8
			t["arm_r_z"] = 0.5
		State.SHOULDER:
			t["torso_z"] = -0.4
			t["pelvis_y"] = HIP_Y - 0.08
			t["arm_l"] = -0.3
			t["arm_l_z"] = 0.25
		State.SLIDE:
			rate = 25.0
			# Tumbado hacia atrás con la pierna de ataque estirada
			t["root_x"] = 1.2
			t["thigh_r"] = 0.35
			t["knee_r"] = 0.0
			t["thigh_l"] = 0.9
			t["knee_l"] = 1.6
			t["torso_x"] = -0.25
			t["arm_l"] = -0.9
			t["arm_r"] = -0.9
			t["arm_l_z"] = 0.6
			t["arm_r_z"] = 0.6
			t["torso_y"] = 0.0
		State.STUN:
			if fallen:
				var lie := 1.45
				var up_t := state_dur - 0.35
				var f := clampf(state_time / 0.22, 0.0, 1.0)
				if state_time > up_t:
					f = clampf(1.0 - (state_time - up_t) / 0.35, 0.0, 1.0)
				t["root_x"] = lie * f
				t["thigh_l"] = 0.6 * f
				t["thigh_r"] = 0.2 * f
				t["knee_l"] = 0.9 * f
				t["arm_l_z"] = 1.3 * f
				t["arm_r_z"] = 1.0 * f
				t["torso_y"] = 0.0
				rate = 22.0
			else:
				t["torso_z"] = sin(state_time * 16.0) * 0.35
				t["arm_l_z"] = 0.9
				t["arm_r_z"] = 0.9
				t["torso_x"] = 0.15
		State.DIVE:
			rate = 26.0
			t["root_z"] = dive_side * clampf(state_time * 6.0, 0.0, 1.35)
			t["arm_l_z"] = 2.8
			t["arm_r_z"] = 2.8
			t["elbow_l"] = 0.05
			t["elbow_r"] = 0.05
			t["arm_l"] = 0.0
			t["arm_r"] = 0.0
			t["thigh_l"] = 0.0
			t["thigh_r"] = 0.2
			t["knee_l"] = 0.1
			t["knee_r"] = 0.3
			t["torso_y"] = 0.0
		State.DASH:
			t["torso_x"] = -0.55
			t["arm_l"] = -1.0
			t["arm_r"] = -1.0
		State.SKILL:
			_skill_pose(t)
			rate = 32.0
		State.CELEBRATE:
			t["arm_l_z"] = 2.6 + sin(m.time * 10.0) * 0.2
			t["arm_r_z"] = 2.6 - sin(m.time * 10.0) * 0.2
			t["elbow_l"] = 0.2
			t["elbow_r"] = 0.2
	_spin = 0.0
	if state == State.SKILL and skill.get("spin", false):
		_spin = state_time / maxf(state_dur, 0.01) * TAU
	_apply_pose(t, rate, dt)
	rotation.y = atan2(-facing.x, -facing.z) + _spin
	if is_human:
		_arrow.position.y = 2.45 + sin(m.time * 5.0) * 0.08
		_ring.rotation.y += dt * 2.0
	if awakened:
		_aura.scale = Vector3.ONE * (1.0 + sin(m.time * 9.0) * 0.06)


## Poses de cada regate, para que se lea qué está pasando.
func _skill_pose(t: Dictionary) -> void:
	var kind: String = skill.get("kind", "")
	var sd: Vector3 = skill.get("dir", facing)
	var side := signf(facing.cross(sd).y)
	if side == 0.0:
		side = 1.0
	var p := clampf(state_time / maxf(state_dur, 0.01), 0.0, 1.0)
	t["arm_l_z"] = 0.8
	t["arm_r_z"] = 0.8
	t["torso_y"] = 0.0
	match kind:
		"recorte":
			# Amaga hacia un lado y sale hacia el otro con el exterior del pie
			var feint := p < 0.35
			t["torso_z"] = (-0.35 if feint else 0.4) * side
			t["root_z"] = (-0.15 if feint else 0.2) * side
			if side > 0.0:
				t["thigh_r"] = 0.45
				t["thigh_r_z"] = -0.7 * sin(p * PI)
			else:
				t["thigh_l"] = 0.45
				t["thigh_l_z"] = -0.7 * sin(p * PI)
			t["pelvis_y"] = HIP_Y - 0.08
		"elastico":
			# El pie lleva el balón hacia fuera y lo arrastra hacia dentro
			var sweep := sin(p * TAU) * 0.8
			if side > 0.0:
				t["thigh_r"] = 0.4
				t["thigh_r_z"] = sweep
			else:
				t["thigh_l"] = 0.4
				t["thigh_l_z"] = sweep
			t["torso_z"] = -sweep * 0.45
			t["pelvis_y"] = HIP_Y - 0.1
		"arrastre":
			# Pisa el balón con la suela y lo trae hacia atrás
			t["thigh_r"] = lerpf(0.8, -0.2, p)
			t["knee_r"] = lerpf(0.2, 0.6, p)
			t["thigh_l"] = -0.1
			t["knee_l"] = 0.4
			t["torso_x"] = 0.18
		"ruleta":
			t["thigh_r"] = 0.6 * sin(p * TAU)
			t["thigh_l"] = -0.6 * sin(p * TAU)
			t["arm_l_z"] = 1.2
			t["arm_r_z"] = 1.2
			t["pelvis_y"] = HIP_Y - 0.06
		_:
			# Técnicas (relámpago, torbellino...): cuerpo lanzado hacia el lado
			t["torso_x"] = -0.45
			t["torso_z"] = 0.35 * side
			t["arm_l"] = -0.9
			t["arm_r"] = -0.9


## "!" rojo sobre quien está por intentar quitar el balón.
func _update_alert() -> void:
	if _alert == null:
		return
	var attacking := state == State.TACKLE or state == State.SLIDE or state == State.POKE \
		or state == State.SHOULDER or state == State.DASH
	var show := not _tele.is_empty() or (attacking and state_time < 0.3)
	var c := m.ball.carrier
	_alert.visible = show and c != null and c.team != team
	if _alert.visible:
		_alert.position.y = 2.5 + (0.0 if _tele.is_empty() else sin(m.time * 30.0) * 0.05)


func _apply_pose(t: Dictionary, rate: float, dt: float) -> void:
	var w := 1.0 - exp(-rate * dt)
	for key in t:
		_pose[key] = lerpf(float(_pose.get(key, t[key])), float(t[key]), w)
	_root.rotation = Vector3(_pose["root_x"], 0.0, _pose["root_z"])
	_root.position.y = _pose["root_y"]
	_pelvis.position.y = _pose["pelvis_y"]
	_torso.rotation = Vector3(_pose["torso_x"], _pose["torso_y"], _pose["torso_z"])
	_head.rotation.x = _pose["head_x"]
	_thigh_l.rotation = Vector3(_pose["thigh_l"], 0.0, -float(_pose["thigh_l_z"]))
	_knee_l.rotation.x = -float(_pose["knee_l"])
	_thigh_r.rotation = Vector3(_pose["thigh_r"], 0.0, float(_pose["thigh_r_z"]))
	_knee_r.rotation.x = -float(_pose["knee_r"])
	_arm_l.rotation = Vector3(_pose["arm_l"], 0.0, -float(_pose["arm_l_z"]))
	_elbow_l.rotation.x = _pose["elbow_l"]
	_arm_r.rotation = Vector3(_pose["arm_r"], 0.0, float(_pose["arm_r_z"]))
	_elbow_r.rotation.x = _pose["elbow_r"]


static var _toon_cache := {}
static var _outline_mat: ShaderMaterial


## Material anime (toon + contorno). Se reutiliza por color.
func _mat(c: Color) -> ShaderMaterial:
	var key := c.to_html()
	if _toon_cache.has(key):
		return _toon_cache[key]
	if _outline_mat == null:
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = load("res://shaders/outline.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	mat.set_shader_parameter("albedo", c)
	# Sombra tintada hacia el azul/violeta, como en el anime
	mat.set_shader_parameter("shade_color", c.lerp(Color(0.35, 0.4, 0.75), 0.45))
	mat.set_shader_parameter("spec_strength", 0.12)
	mat.next_pass = _outline_mat
	_toon_cache[key] = mat
	return mat


func _flat(c: Color) -> StandardMaterial3D:
	var m2 := StandardMaterial3D.new()
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m2.albedo_color = c
	return m2


## Cabeza anime: ojos grandes con brillo, cejas, boca y pelo en puntas.
func _build_anime_head(skin_mat: Material, hair_mat: Material, eye_col: Color, rng: RandomNumberGenerator) -> void:
	var face := _mesh_child(_head, _sphere(0.125), skin_mat, Vector3(0, 0.12, 0))
	face.scale = Vector3(0.95, 1.08, 1.0)
	# Ojos (hacia -Z)
	var white := _flat(Color(1, 1, 1))
	var iris := _flat(eye_col)
	var pupil := _flat(Color(0.03, 0.03, 0.05))
	var brow := _flat(Color(0.08, 0.06, 0.05))
	for sx in [-1.0, 1.0]:
		var e := _mesh_child(_head, _sphere(0.032), white, Vector3(0.048 * sx, 0.125, -0.108))
		e.scale = Vector3(1.0, 1.25, 0.35)
		e.set_meta("no_ghost", true)
		var ir := _mesh_child(_head, _sphere(0.024), iris, Vector3(0.048 * sx, 0.12, -0.118))
		ir.scale = Vector3(0.95, 1.3, 0.3)
		ir.set_meta("no_ghost", true)
		var pu := _mesh_child(_head, _sphere(0.012), pupil, Vector3(0.048 * sx, 0.118, -0.124))
		pu.scale = Vector3(1.0, 1.3, 0.3)
		pu.set_meta("no_ghost", true)
		var hl := _mesh_child(_head, _sphere(0.007), white, Vector3(0.056 * sx, 0.132, -0.127))
		hl.set_meta("no_ghost", true)
		var b := _mesh_child(_head, _box(Vector3(0.055, 0.01, 0.01)), brow, Vector3(0.05 * sx, 0.17, -0.112))
		b.rotation_degrees = Vector3(0, 0, -12.0 * sx)
		b.set_meta("no_ghost", true)
	var mouth := _mesh_child(_head, _box(Vector3(0.035, 0.006, 0.006)), brow, Vector3(0, 0.055, -0.118))
	mouth.set_meta("no_ghost", true)
	# Pelo: casquete + mechones en punta hacia atrás/arriba + flequillo
	var cap := _mesh_child(_head, _sphere(0.138), hair_mat, Vector3(0, 0.17, 0.02))
	cap.scale = Vector3(1.0, 0.78, 1.05)
	# Mechones en dos capas, inclinados hacia atrás (estilo shōnen)
	var length := rng.randf_range(0.11, 0.19)
	var spiky := rng.randf()
	for layer in 2:
		var count := 7 + layer * 3
		for i in count:
			var ang := lerpf(-2.3, 2.3, float(i) / float(count - 1)) + rng.randf_range(-0.12, 0.12)
			var up := 0.25 + layer * 0.35 + rng.randf() * 0.2 + spiky * 0.2
			var dir := Vector3(sin(ang) * 0.85, up, cos(ang) * 0.55 + 0.75).normalized()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = rng.randf_range(0.035, 0.05)
			cone.height = length * rng.randf_range(0.75, 1.25) * (1.0 + layer * 0.15)
			cone.radial_segments = 5
			var base := Vector3(0, 0.19 + layer * 0.03, 0.02) + Vector3(sin(ang) * 0.11, 0.0, cos(ang) * 0.09)
			var mi := _mesh_child(_head, cone, hair_mat, base + dir * cone.height * 0.4)
			mi.basis = Basis(Quaternion(Vector3.UP, dir))
	for i in 4:
		# Flequillo cayendo sobre la frente
		var cone2 := CylinderMesh.new()
		cone2.top_radius = 0.0
		cone2.bottom_radius = 0.035
		cone2.height = rng.randf_range(0.1, 0.16)
		cone2.radial_segments = 4
		var x := (float(i) - 1.5) * 0.045
		var mi2 := _mesh_child(_head, cone2, hair_mat, Vector3(x, 0.2, -0.1))
		mi2.rotation_degrees = Vector3(-200 + rng.randf_range(-10, 10), 0, x * 200.0)


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 12
	t.ring_segments = 6
	return t


func _fx_mat(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = c
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
	c.bottom_radius = r * 0.9
	c.height = h
	c.radial_segments = 10
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _mesh_child(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j
