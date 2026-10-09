class_name TeamAI
extends RefCounted
## IA colectiva: reparte roles cada pocos instantes (portador, presión,
## cobertura, marcaje, apoyo, quien persigue el balón suelto...).

var team: Team
var m: Match
var roles := {}
var marks := {}
var _timer := 0.0


func _init(t: Team) -> void:
	team = t
	m = t.m


func update(dt: float) -> void:
	_timer -= dt
	if _timer <= 0.0:
		_timer = 0.15
		_assign_roles()
	for p in team.players:
		if not p.is_human and p.brain != null:
			p.brain.update(dt)


func role_of(p: Player) -> String:
	return roles.get(p, "zone")


func _assign_roles() -> void:
	roles.clear()
	marks.clear()
	var b := m.ball
	var c := b.carrier
	var field: Array[Player] = []
	for p in team.players:
		if p.role != Player.Role.GK:
			field.append(p)
	var ai_field: Array[Player] = field.filter(func(p: Player) -> bool: return not p.is_human)
	var human: Player = null
	for p in field:
		if p.is_human:
			human = p

	if c != null and c.team == team:
		for p in field:
			roles[p] = "support"
		roles[c] = "carrier"
		return

	if c != null:
		# Defender: presión al portador, cobertura y marcajes
		ai_field.sort_custom(func(a: Player, bb: Player) -> bool:
			return Match.flat_dist(a.position, c.position) < Match.flat_dist(bb.position, c.position))
		var idx := 0
		var human_pressing := human != null and Match.flat_dist(human.position, c.position) < 3.0
		if not human_pressing and ai_field.size() > 0:
			roles[ai_field[0]] = "press"
			idx = 1
		if ai_field.size() > idx:
			roles[ai_field[idx]] = "cover"
			idx += 1
		var free_opps: Array[Player] = []
		for o in team.opponent.players:
			if o != c and o.role != Player.Role.GK:
				free_opps.append(o)
		var own := team.own_goal()
		free_opps.sort_custom(func(a: Player, bb: Player) -> bool:
			return Match.flat_dist(a.position, own) < Match.flat_dist(bb.position, own))
		for i in range(idx, ai_field.size()):
			var p := ai_field[i]
			var best: Player = null
			var bd := INF
			for o in free_opps:
				var d := Match.flat_dist(o.position, team.field_point(p.home.x, p.home.y)) * 0.6 + Match.flat_dist(o.position, p.position) * 0.4
				if d < bd:
					bd = d
					best = o
			if best != null and bd < m.hl * 0.6:
				roles[p] = "mark"
				marks[p] = best
				free_opps.erase(best)
			else:
				roles[p] = "zone"
		return

	# Balón suelto
	if b.pass_target != null and b.pass_target.team == team and not b.pass_target.is_human:
		roles[b.pass_target] = "receive"
	var best_ai: Player = null
	var best_t := INF
	for p in ai_field:
		if roles.has(p):
			continue
		var t: float = m.intercept_point(p)["t"]
		if t < best_t:
			best_t = t
			best_ai = p
	var human_t := INF
	if human != null:
		human_t = m.intercept_point(human)["t"]
	var opp_t := m.best_intercept_time(team.opponent)
	if best_ai != null and not roles.has(best_ai):
		if human_t > best_t - 0.15 or opp_t < human_t:
			roles[best_ai] = "chase"
	var ours := b.last_touch != null and b.last_touch.team == team
	for p in ai_field:
		if not roles.has(p):
			roles[p] = "support" if ours else "zone"
