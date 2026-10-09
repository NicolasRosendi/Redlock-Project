class_name Kick
extends RefCounted
## Resolución de trayectorias: dado un objetivo, calcula la velocidad inicial
## del balón. Es lo que permite que el juego sea arcade (apuntas con el stick y
## el efecto se aplica solo) sin dejar de respetar la física del balón.


## Distancia recorrida por un balón rodando que pasa de v0 a v1.
## Modelo de frenado: dv/dt = -(a + b·v).
static func roll_distance(v0: float, v1: float) -> float:
	var a := Ball.ROLL_DECEL
	var b := Ball.ROLL_DRAG
	var k := a / b
	var t := log((v0 + k) / (v1 + k)) / b
	return (v0 - v1) / b - k * t


static func roll_time(v0: float, v1: float) -> float:
	var k := Ball.ROLL_DECEL / Ball.ROLL_DRAG
	return log((v0 + k) / (v1 + k)) / Ball.ROLL_DRAG


## Velocidad inicial para que un pase raso llegue a `dist` con `arrive` m/s.
static func ground_speed_for(dist: float, arrive: float) -> float:
	var lo := arrive
	var hi := 70.0
	for i in 28:
		var mid := (lo + hi) * 0.5
		if roll_distance(mid, arrive) < dist:
			lo = mid
		else:
			hi = mid
	return hi


static func ground_pass(from: Vector3, to: Vector3, arrive: float) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := d.length()
	if dist < 0.05:
		return Vector3.ZERO
	return d / dist * ground_speed_for(dist, arrive)


## Tiempo que tarda un pase raso de velocidad v0 en recorrer `dist`
## (o el tiempo hasta detenerse si no llega).
static func ground_time(v0: float, dist: float) -> float:
	if roll_distance(v0, 0.0) <= dist:
		return roll_time(v0, 0.0)
	var lo := 0.0
	var hi := v0
	for i in 24:
		var mid := (lo + hi) * 0.5
		if roll_distance(v0, mid) > dist:
			lo = mid
		else:
			hi = mid
	return roll_time(v0, lo)


## Globo/centro: sube hasta `apex` y pasa por `to` (a la altura land_y) cayendo.
static func lob(from: Vector3, to: Vector3, apex: float, land_y := Ball.RADIUS) -> Vector3:
	var g := Ball.GRAVITY
	var h := maxf(apex, maxf(from.y, land_y) + 0.4)
	var vy := sqrt(2.0 * g * (h - from.y))
	var t := lob_time(from.y, h, land_y)
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var vh := d / t * (1.0 + Ball.AIR_DRAG * t * 0.5)
	return Vector3(vh.x, vy * (1.0 + Ball.AIR_DRAG * t * 0.25), vh.z)


static func lob_time(from_y: float, apex: float, land_y: float) -> float:
	var g := Ball.GRAVITY
	var h := maxf(apex, maxf(from_y, land_y) + 0.4)
	var vy := sqrt(2.0 * g * (h - from_y))
	var disc := vy * vy - 2.0 * g * (land_y - from_y)
	return (vy + sqrt(maxf(disc, 0.0))) / g


## Disparo tenso hacia `target` a `speed` m/s, compensando gravedad, caída por
## topspin y la curva del efecto lateral (el jugador no tiene que dosificarlo).
static func aimed(from: Vector3, target: Vector3, speed: float, top := 0.0, side := 0.0) -> Vector3:
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var dist := flat.length()
	if dist < 0.1:
		return Vector3.ZERO
	var dir := flat / dist
	var vh := speed
	var vy := 0.0
	for i in 5:
		var t := dist / vh * (1.0 + Ball.AIR_DRAG * dist / vh * 0.5)
		var down := Ball.GRAVITY + top * vh * Ball.DIP
		vy = (target.y - from.y) / t + 0.5 * down * t
		vh = sqrt(maxf(speed * speed - vy * vy, speed * speed * 0.3))
		if absf(side) > 0.001:
			var lat := Vector3.UP.cross(dir)
			var drift := 0.5 * Ball.MAGNUS * side * vh * t * t * 0.8
			var aim := target - lat * drift
			dir = Vector3(aim.x - from.x, 0.0, aim.z - from.z).normalized()
	return dir * vh + Vector3.UP * vy
