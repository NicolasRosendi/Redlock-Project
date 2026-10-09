class_name Team
extends RefCounted
## Equipo: jugadores, dirección de ataque y utilidades de geometría.

var id := 0
var team_name := ""
var short_name := ""
var color := Color.BLUE
var color2 := Color.WHITE
var gk_color := Color.YELLOW
var players: Array[Player] = []
var attack_sign := 1.0
var score := 0
var opponent: Team
var m: Match
var ai: TeamAI
var awakening_pool: Array[String] = []

## Petición de pase del jugador humano (modo Pro): "¡pásala!".
var pass_request := {}


func gk() -> Player:
	for p in players:
		if p.role == Player.Role.GK:
			return p
	return null


func opp_goal() -> Vector3:
	return Vector3(attack_sign * m.hl, 0.0, 0.0)


func own_goal() -> Vector3:
	return Vector3(-attack_sign * m.hl, 0.0, 0.0)


func attack_dir() -> Vector3:
	return Vector3(attack_sign, 0.0, 0.0)


## 0 = línea de gol propia, 1 = línea de gol rival.
func progress(x: float) -> float:
	return (x * attack_sign + m.hl) / (2.0 * m.hl)


func field_point(prog: float, zn: float) -> Vector3:
	return Vector3(attack_sign * (prog * 2.0 * m.hl - m.hl), 0.0, zn * m.hw)


func has_ball() -> bool:
	return m.ball.carrier != null and m.ball.carrier.team == self


func in_own_box(pos: Vector3) -> bool:
	return m.in_box(self, pos)


func request_pass(p: Player, through: bool) -> void:
	pass_request = {"player": p, "through": through, "until": m.time + 1.6}


func nearest_field_player(pos: Vector3, exclude: Player = null) -> Player:
	var best: Player = null
	var bd := INF
	for p in players:
		if p == exclude or p.role == Player.Role.GK:
			continue
		var d := Match.flat_dist(p.position, pos)
		if d < bd:
			bd = d
			best = p
	return best


## Pase normal: el compañero MÁS CERCANO en la dirección del stick (cono de
## 35°). Si no hay nadie en el cono se abre a 80° y manda la alineación.
func nearest_in_direction(from: Player, dir: Vector3) -> Player:
	var d0 := Vector3(dir.x, 0.0, dir.z)
	if d0.length() < 0.1:
		d0 = from.facing
	d0 = d0.normalized()
	var best: Player = null
	var best_d := INF
	for t in players:
		if t == from:
			continue
		var to := from.flat_to(t.position)
		var d := to.length()
		if d < 2.5 or d > 70.0:
			continue
		if absf(d0.signed_angle_to(to, Vector3.UP)) <= deg_to_rad(35.0) and d < best_d:
			best_d = d
			best = t
	if best != null:
		return best
	var best_s := INF
	for t in players:
		if t == from:
			continue
		var to2 := from.flat_to(t.position)
		var d2 := to2.length()
		if d2 < 2.5 or d2 > 70.0:
			continue
		var ang := absf(d0.signed_angle_to(to2, Vector3.UP))
		if ang > deg_to_rad(80.0):
			continue
		var s := ang * 20.0 + d2 * 0.15 + (12.0 if t.role == Player.Role.GK else 0.0)
		if s < best_s:
			best_s = s
			best = t
	return best


## Pase al hueco: el compañero mejor alineado con el stick (se prefieren los
## que van al espacio y los que están más adelantados).
func through_target(from: Player, dir: Vector3) -> Player:
	var d0 := Vector3(dir.x, 0.0, dir.z)
	if d0.length() < 0.1:
		d0 = from.facing
	d0 = d0.normalized()
	var best: Player = null
	var best_s := INF
	for t in players:
		if t == from or t.role == Player.Role.GK:
			continue
		var to := from.flat_to(t.position)
		var d := to.length()
		if d < 3.0 or d > 60.0:
			continue
		var ang := absf(d0.signed_angle_to(to, Vector3.UP))
		if ang > deg_to_rad(55.0):
			continue
		var s := ang * 14.0 + absf(d - 16.0) * 0.12 - (3.0 if t.making_run else 0.0)
		if s < best_s:
			best_s = s
			best = t
	return best


## Compatibilidad: receptor para técnicas e IA.
func find_pass_target(from: Player, dir: Vector3, through := false) -> Player:
	return through_target(from, dir) if through else nearest_in_direction(from, dir)
