class_name Ball
extends Node3D
## Balón con física propia: gravedad, rebote, rozamiento al rodar, resistencia
## del aire, efecto Magnus (curva), caída por topspin y "knuckle".
## Cuando un jugador lo controla (carrier) se pega a sus pies.

const RADIUS := 0.11
## Gravedad algo mayor que la real: en cámara de TV el balón real parece flotar.
const GRAVITY := 11.5
const AIR_DRAG := 0.05
const ROLL_DECEL := 2.2
const ROLL_DRAG := 0.2
const BOUNCE := 0.5
const BOUNCE_KEEP := 0.76
const MAGNUS := 0.25
const DIP := 0.22
const SPIN_DECAY := 0.35
const POST_RADIUS := 0.06
const TRAIL_COUNT := 18
const VISUAL_SCALE := 1.3
## Frenado del balón conducido entre toque y toque.
const CARRY_DECEL := 6.0

var m: Match
var velocity := Vector3.ZERO
var side_spin := 0.0
var top_spin := 0.0
var knuckle := 0.0

var carrier: Player = null
var last_touch: Player = null
var last_kicker: Player = null
var last_passer: Player = null
var kick_id := 0
var kick_kind := ""
var kick_time := 0.0
var pass_target: Player = null
var pass_through := false
var shield_team := -1
var vision_pass := false
var special_id := ""
var special_break := 0.0
var in_goal := false
var tried := {}
var carry_vel := Vector3.ZERO
## Resultado del tiro decidido por la "ruleta" ("goal", "save", "miss" o "").
var shot_result := ""
var shot_prob := 0.0

var _mesh: MeshInstance3D
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D
var _trail: Array[MeshInstance3D] = []
var _trail_mats: Array[StandardMaterial3D] = []
var _trail_life: Array[float] = []
var _trail_i := 0
var _trail_t := 0.0
var _trail_on := false
var _trail_color := Color.WHITE
var _touch_cd := 0.0
var _carry_u := 0.0


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS
	sm.height = RADIUS * 2.0
	_mesh.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ball.gdshader")
	_mesh.material_override = mat
	# Algo más grande que el real para que se lea bien desde lejos
	_mesh.scale = Vector3.ONE * VISUAL_SCALE
	_mesh.position.y = RADIUS * (VISUAL_SCALE - 1.0)
	add_child(_mesh)

	_shadow = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.42, 0.42)
	_shadow.mesh = pm
	_shadow_mat = _blob_material()
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)

	for i in TRAIL_COUNT:
		var t := MeshInstance3D.new()
		var ts := SphereMesh.new()
		ts.radius = RADIUS * 1.1
		ts.height = RADIUS * 2.2
		ts.radial_segments = 8
		ts.rings = 4
		t.mesh = ts
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.albedo_color = Color(1, 1, 1, 0)
		t.material_override = tm
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.top_level = true
		t.visible = false
		add_child(t)
		_trail.append(t)
		_trail_mats.append(tm)
		_trail_life.append(0.0)


static func _blob_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	mat.albedo_texture = tex
	return mat


## Integrador compartido por la simulación y por las predicciones (IA,
## porteros, Metavisión). Devuelve [pos, vel, side, top].
static func integrate(pos: Vector3, vel: Vector3, side: float, top: float, dt: float) -> Array:
	if pos.y <= RADIUS + 0.001 and absf(vel.y) < 0.01:
		# Rodando
		pos.y = RADIUS
		vel.y = 0.0
		var hv := Vector3(vel.x, 0.0, vel.z)
		var sp := hv.length()
		if sp > 0.0:
			var ns := maxf(sp - (ROLL_DECEL + ROLL_DRAG * sp) * dt, 0.0)
			hv *= ns / sp
			if absf(side) > 0.01 and ns > 1.0:
				hv += Vector3.UP.cross(hv / ns) * side * ns * MAGNUS * 0.7 * dt
		vel.x = hv.x
		vel.z = hv.z
		side *= exp(-SPIN_DECAY * 1.5 * dt)
		top = 0.0
		pos += vel * dt
	else:
		# En el aire
		vel.y -= GRAVITY * dt
		var hv := Vector3(vel.x, 0.0, vel.z)
		var sp := hv.length()
		if sp > 0.5:
			vel += Vector3.UP.cross(hv / sp) * side * sp * MAGNUS * dt
			vel.y -= top * sp * DIP * dt
		vel -= vel * AIR_DRAG * dt
		side *= exp(-SPIN_DECAY * dt)
		pos += vel * dt
		if pos.y < RADIUS:
			pos.y = RADIUS
			if vel.y < -1.4:
				vel.y = -vel.y * BOUNCE
				vel.x *= BOUNCE_KEEP
				vel.z *= BOUNCE_KEEP
				side *= 0.5
				top *= 0.3
			else:
				vel.y = 0.0
	return [pos, vel, side, top]


func step(dt: float) -> void:
	var r := Ball.integrate(position, velocity, side_spin, top_spin, dt)
	position = r[0]
	velocity = r[1]
	side_spin = r[2]
	top_spin = r[3]
	if knuckle > 0.0:
		if position.y > RADIUS + 0.05:
			velocity += Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * knuckle * 8.0 * dt
		knuckle = maxf(knuckle - dt * 0.7, 0.0)


func predict(duration: float, step_dt: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var pos := position
	var vel := velocity
	var s := side_spin
	var t := top_spin
	var n := int(duration / step_dt)
	for i in n:
		for k in 2:
			var r := Ball.integrate(pos, vel, s, t, step_dt * 0.5)
			pos = r[0]
			vel = r[1]
			s = r[2]
			t = r[3]
		out.append(pos)
	return out


func kick(by: Player, vel: Vector3, kind: String, side := 0.0, top := 0.0) -> void:
	carrier = null
	velocity = vel
	side_spin = side
	top_spin = top
	knuckle = 0.0
	if by != null:
		last_touch = by
		last_kicker = by
		by.no_touch_until = m.time + 0.28
	kick_kind = kind
	kick_id += 1
	kick_time = m.time
	pass_target = null
	pass_through = false
	shield_team = -1
	vision_pass = false
	special_id = ""
	special_break = 0.0
	shot_result = ""
	tried.clear()
	position.y = maxf(position.y, RADIUS)
	set_trail(vel.length() > 26.0, Color(1, 1, 1, 0.5))


## `cushion`: recepción de un balón en movimiento. El primer toque amortigua
## pero conserva parte de la velocidad, así que el balón no se "pega" al pie.
func set_carrier(p: Player, cushion := false) -> void:
	var pv := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if cushion:
		var bv := Vector3(velocity.x, 0.0, velocity.z)
		var keep := clampf(0.14 + maxf(bv.length() - 12.0, 0.0) * 0.015 - p.st("dribble") * 0.08, 0.04, 0.35)
		carry_vel = pv + (bv - pv) * keep
		_carry_u = maxf(carry_vel.dot(p.facing), 0.0)
		_touch_cd = 0.22
		p.on_receive()
	else:
		carry_vel = pv
		_carry_u = maxf(pv.dot(p.facing), 0.0)
		_touch_cd = 0.0
	carrier = p
	velocity = carry_vel
	side_spin = 0.0
	top_spin = 0.0
	knuckle = 0.0
	last_touch = p
	pass_target = null
	shield_team = -1
	special_id = ""
	special_break = 0.0
	kick_kind = "carry"
	shot_result = ""
	in_goal = false
	tried.clear()
	set_trail(false)
	m.on_possession(p)


## Obliga a un toque inmediato (al empezar un regate, por ejemplo).
func force_touch() -> void:
	_touch_cd = 0.0
	_carry_u = 0.0


func place(pos: Vector3) -> void:
	carrier = null
	position = Vector3(pos.x, RADIUS, pos.z)
	velocity = Vector3.ZERO
	side_spin = 0.0
	top_spin = 0.0
	knuckle = 0.0
	in_goal = false
	kick_kind = ""
	shot_result = ""
	pass_target = null
	shield_team = -1
	special_id = ""
	tried.clear()
	set_trail(false)


func set_trail(on: bool, color := Color.WHITE) -> void:
	_trail_on = on
	_trail_color = color


## Conducción por toques "pegada al pie": el balón se mueve sobre el eje
## hacia donde mira el jugador. Cada toque lo adelanta un poco; frena solo
## y el jugador lo vuelve a tocar. Si el jugador gira, el balón se recoloca
## rápido delante de él (nunca se va hacia un lado imprevisible). Al esprintar
## los toques son algo más largos; al proteger, frenar o armar un tiro, el
## balón vuelve al pie. El portero lo lleva en las manos.
func carry(dt: float) -> void:
	var p := carrier
	var pv := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var spd := pv.length()
	var fwd := p.skill_dir_or_facing()
	var right := fwd.cross(Vector3.UP)
	var old := position
	_touch_cd -= dt
	if position.y > RADIUS:
		position.y = maxf(position.y - 4.0 * dt, RADIUS)
	if p.role == Player.Role.GK and m.in_box(p.team, p.position):
		var hands := p.position + p.facing * 0.32 + Vector3.UP * 1.05
		position = position.lerp(hands, 1.0 - exp(-14.0 * dt))
		carry_vel = pv
		velocity = carry_vel
		return
	var s := pv.dot(fwd)
	# En un giro brusco el jugador recoge el balón al pie y lo lleva consigo
	var md := Vector3(p.move_dir.x, 0.0, p.move_dir.z)
	var turning := md.length() > 0.3 and fwd.angle_to(md) > 1.0
	var hold := p.state == Player.State.KICK or p.restart_lock or p.want_shield or spd < 0.8 or turning
	if hold:
		var target := p.position + fwd * 0.42
		if turning:
			var blend := fwd + md.normalized()
			target = p.position + (blend.normalized() if blend.length() > 0.5 else fwd) * 0.45
		if p.want_shield:
			var o := p.nearest_opponent()
			if o != null:
				var away := p.flat_to(p.position * 2.0 - o.position).normalized()
				target = p.position + (away * 0.7 + fwd * 0.3).normalized() * 0.5
		# Rodea el cuerpo del jugador en vez de atravesarlo
		var cur := Vector3(position.x - p.position.x, 0.0, position.z - p.position.z)
		var want := Vector3(target.x - p.position.x, 0.0, target.z - p.position.z)
		var k := 1.0 - exp(-14.0 * dt)
		var ang := cur.signed_angle_to(want, Vector3.UP) if cur.length() > 0.05 else 0.0
		var dir := cur.normalized().rotated(Vector3.UP, ang * k) if cur.length() > 0.05 else want.normalized()
		var rad := lerpf(cur.length(), want.length(), k)
		position.x = p.position.x + dir.x * rad
		position.z = p.position.z + dir.z * rad
		_carry_u = maxf(s, 0.0)
	else:
		var rel := Vector3(position.x - p.position.x, 0.0, position.z - p.position.z)
		var along := rel.dot(fwd)
		var lat := rel.dot(right)
		_carry_u = maxf(_carry_u - (CARRY_DECEL + ROLL_DRAG * _carry_u) * dt, 0.0)
		# `rel` ya incluye cuánto avanzó el jugador: solo se suma lo que rodó el balón
		along += _carry_u * dt
		# El balón vuelve al eje del jugador enseguida (más rápido con el humano)
		lat *= exp(-(16.0 if p.is_human else 10.0) * dt)
		if _touch_cd <= 0.0 and along < 0.38:
			var reach := carry_reach(p, spd)
			_carry_u = maxf(s, 0.0) + sqrt(2.0 * CARRY_DECEL * maxf(reach - maxf(along, 0.0), 0.05))
			_touch_cd = 0.12
			p.on_ball_touch()
		along = clampf(along, -0.3, carry_reach(p, spd) + 0.2)
		var np := p.position + fwd * along + right * lat
		position.x = np.x
		position.z = np.z
	if dt > 0.0:
		carry_vel = Vector3(position.x - old.x, 0.0, position.z - old.z) / dt
	velocity = carry_vel


## Distancia máxima a la que se adelanta el balón en cada toque.
func carry_reach(p: Player, spd: float) -> float:
	var reach := 0.5 + spd * 0.03
	if p.want_sprint and spd > 6.0:
		reach += 0.2 + spd * 0.035 * (1.15 - p.st("dribble") * 0.5)
	if p.is_human:
		reach *= 0.85
	return reach


## Postes, travesaño y red. El gol solo cuenta cuando el balón cruzó
## ENTERO la línea; si pega en el palo rebota según cómo llegó.
func collide_goal(sign_x: float, hl: float, gw: float, gh: float, depth: float) -> void:
	var gx := sign_x * hl
	var r := RADIUS + POST_RADIUS
	# Postes (cilindros verticales)
	for pz in [-gw * 0.5, gw * 0.5]:
		if position.y < gh + RADIUS:
			var d := Vector2(position.x - gx, position.z - pz)
			var dl := d.length()
			if dl < r and dl > 0.0001:
				var n := Vector3(d.x / dl, 0.0, d.y / dl)
				position += n * (r - dl)
				_reflect(n, 0.7)
				m.on_woodwork()
	# Travesaño (cilindro horizontal)
	if absf(position.z) <= gw * 0.5 + RADIUS:
		var d2 := Vector2(position.x - gx, position.y - gh)
		var dl2 := d2.length()
		if dl2 < r and dl2 > 0.0001:
			var n2 := Vector3(d2.x / dl2, d2.y / dl2, 0.0)
			position += n2 * (r - dl2)
			_reflect(n2, 0.65)
			m.on_woodwork()
	# La ruleta dijo que no era gol pero el balón va adentro: el portero lo
	# toca con la punta de los dedos justo antes de la línea
	var to_line := hl - absf(position.x)
	if (shot_result == "save" or shot_result == "miss") and signf(position.x) == sign_x \
			and to_line < 0.7 and velocity.x * sign_x > 0.0 \
			and absf(position.z) < gw * 0.5 + RADIUS and position.y < gh + RADIUS:
		m.on_fingertip_save(sign_x, self)
	var crossed := absf(position.x) > hl + RADIUS and signf(position.x) == sign_x \
		and absf(position.z) < gw * 0.5 and position.y < gh
	if crossed:
		in_goal = true
	# Red: solo una vez que es gol (el balón queda dentro y pierde energía)
	if in_goal and signf(position.x) == sign_x:
		var back := hl + depth - RADIUS
		if absf(position.x) > back:
			position.x = sign_x * back
			velocity.x *= -0.15
		var side := gw * 0.5 - RADIUS
		if absf(position.z) > side:
			position.z = signf(position.z) * side
			velocity.z *= -0.2
		if position.y > gh - RADIUS:
			position.y = gh - RADIUS
			velocity.y *= -0.2
		if absf(position.x) < hl + RADIUS:
			position.x = sign_x * (hl + RADIUS)
			velocity.x = absf(velocity.x) * sign_x * 0.2
		velocity *= 0.985


## Rebote: la componente normal se invierte (con pérdida) y la tangencial se
## conserva casi entera, así que el balón sale según el ángulo con que llegó.
func _reflect(n: Vector3, e: float) -> void:
	var vn := velocity.dot(n)
	if vn < 0.0:
		var vt := velocity - vn * n
		velocity = vt * 0.9 - vn * e * n
		side_spin *= 0.3
		top_spin *= 0.3


func _process(delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var sp := hv.length()
	if sp > 0.05:
		_mesh.rotate(Vector3.UP.cross(hv / sp), sp / RADIUS * delta)
		_mesh.transform.basis = _mesh.transform.basis.orthonormalized()
	_shadow.global_position = Vector3(position.x, 0.015, position.z)
	var s := clampf(1.0 - position.y / 9.0, 0.35, 1.0)
	_shadow.scale = Vector3(s, 1.0, s)
	_update_trail(delta)


func _update_trail(delta: float) -> void:
	_trail_t -= delta
	if _trail_on and _trail_t <= 0.0 and velocity.length() > 6.0:
		_trail_t = 0.016
		var t := _trail[_trail_i]
		t.visible = true
		t.global_position = position
		_trail_life[_trail_i] = 0.32
		_trail_i = (_trail_i + 1) % TRAIL_COUNT
	for i in TRAIL_COUNT:
		if _trail_life[i] <= 0.0:
			continue
		_trail_life[i] -= delta
		var k := clampf(_trail_life[i] / 0.32, 0.0, 1.0)
		_trail_mats[i].albedo_color = Color(_trail_color.r, _trail_color.g, _trail_color.b, k * 0.7)
		_trail[i].scale = Vector3.ONE * (0.4 + k * 1.2)
		if _trail_life[i] <= 0.0:
			_trail[i].visible = false
