extends Node
## Pruebas de la física de patadas y del portero.
## Uso: godot --headless --path . --fixed-fps 60 res://tests/unit_test.tscn

var m: Match
var failures := 0
var _shots: Array = []
var _cur := -1
var _t := 0.0
var _results := {"goal": 0, "save": 0, "miss": 0}
var _done := false


func _ready() -> void:
	var sd := 7
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			sd = int(a.trim_prefix("--seed="))
	seed(sd)
	_test_ground_pass()
	_test_lob()
	_test_aimed()
	_test_curved()
	GameConfig.control_mode = GameConfig.ControlMode.AI_ONLY
	GameConfig.team_size = 11
	m = load("res://scenes/match.tscn").instantiate()
	add_child(m)
	for i in 40:
		_shots.append({"dist": randf_range(12.0, 24.0), "z": randf_range(-12.0, 12.0), "charge": randf_range(0.5, 0.9), "aim": randf_range(-1.0, 1.0)})


func _check(name: String, ok: bool, info: String) -> void:
	print("%s %s  %s" % ["OK  " if ok else "FAIL", name, info])
	if not ok:
		failures += 1


func _sim(pos: Vector3, vel: Vector3, side: float, top: float, until_x: float) -> Vector3:
	var r := [pos, vel, side, top]
	for i in 600:
		r = Ball.integrate(r[0], r[1], r[2], r[3], 1.0 / 120.0)
		if (r[0] as Vector3).x >= until_x:
			return r[0]
	return r[0]


func _test_ground_pass() -> void:
	for d in [5.0, 12.0, 25.0, 40.0]:
		var v := Kick.ground_pass(Vector3(0, Ball.RADIUS, 0), Vector3(d, 0, 0), 6.0)
		var r := [Vector3(0, Ball.RADIUS, 0), v, 0.0, 0.0]
		var t := 0.0
		while (r[0] as Vector3).x < d and t < 10.0:
			r = Ball.integrate(r[0], r[1], r[2], r[3], 1.0 / 120.0)
			t += 1.0 / 120.0
		var arr := (r[1] as Vector3).length()
		var tp := Kick.ground_time(v.length(), d)
		_check("pase raso %dm" % d, absf(arr - 6.0) < 0.6 and absf(t - tp) < 0.15, "v0=%.1f llegada=%.2f t=%.2f pred=%.2f" % [v.length(), arr, t, tp])


func _test_lob() -> void:
	for d in [15.0, 30.0]:
		var from := Vector3(0, Ball.RADIUS, 0)
		var v := Kick.lob(from, Vector3(d, 0, 3), 5.0, 1.4)
		var r := [from, v, 0.0, 0.0]
		var prev: Vector3 = from
		var hit := Vector3.ZERO
		for i in 1200:
			r = Ball.integrate(r[0], r[1], r[2], r[3], 1.0 / 120.0)
			var p: Vector3 = r[0]
			if (r[1] as Vector3).y < 0.0 and p.y <= 1.4 and prev.y > 1.4:
				hit = p
				break
			prev = p
		_check("centro %dm" % d, Vector2(hit.x - d, hit.z - 3).length() < 1.0, "cae en (%.1f, %.1f, %.1f)" % [hit.x, hit.y, hit.z])


func _test_aimed() -> void:
	var cases := [[20.0, 0.0, 0.0, 25.0], [20.0, 0.5, 0.12, 22.0], [25.0, -0.6, 0.12, 22.0], [22.0, 0.45, 1.3, 33.0], [16.0, 0.0, 0.5, 36.0]]
	for c in cases:
		var from := Vector3(0, Ball.RADIUS, 2.0)
		var target := Vector3(c[0], 1.6, -2.5)
		var v := Kick.aimed(from, target, c[3], c[2], c[1])
		var p := _sim(from, v, c[1], c[2], c[0])
		var err := Vector2(p.y - target.y, p.z - target.z).length()
		_check("tiro d=%d efecto=%.2f top=%.1f v=%d" % [c[0], c[1], c[2], c[3]], err < 0.6, "error %.2fm (y=%.2f z=%.2f)" % [err, p.y, p.z])


func _test_curved() -> void:
	# Pases "giroscopio": salen hacia el stick y la curva los lleva al objetivo
	var cases := [[14.0, 18.0, false], [20.0, -20.0, false], [25.0, 25.0, true], [9.0, 22.0, false]]
	for c in cases:
		var from := Vector3(0, Ball.RADIUS, 0)
		var to := Vector3(c[0], 0, 0)
		var hint := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(c[1]))
		var res := Kick.curved(from, to, hint, c[2], 7.0, 4.0, Ball.RADIUS)
		var v: Vector3 = res["vel"]
		var r := [from, v, res["side"], 0.0]
		var best := INF
		for i in 600:
			r = Ball.integrate(r[0], r[1], r[2], r[3], 1.0 / 120.0)
			var p: Vector3 = r[0]
			best = minf(best, Vector2(p.x - to.x, p.z - to.z).length())
		var launch := rad_to_deg(Vector3.RIGHT.signed_angle_to(Vector3(v.x, 0, v.z), Vector3.UP))
		_check("pase curvo %dm stick %+d°%s" % [c[0], c[1], " (bombeado)" if c[2] else ""], best < 0.7 and absf(launch) > 4.0,
			"sale a %+.0f°, pasa a %.2fm del objetivo, efecto %.2f" % [launch, best, res["side"]])


func _physics_process(dt: float) -> void:
	Engine.time_scale = 1.0
	if m == null or m.phase == Match.Phase.KICKOFF or _done:
		return
	_t += dt
	var b := m.ball
	var shooter := m.teams[0].players[9]
	var gk := m.teams[1].gk()
	for p in m.players:
		if p != gk and p != shooter:
			p.frozen = true
			p.position = Vector3(-40, 0, -30 + p.get_index() * 0.5)
	if _cur >= 0:
		# Esperar resultado
		var outcome := ""
		if m.phase == Match.Phase.GOAL:
			outcome = "goal"
		elif b.carrier == gk or (b.last_touch == gk and b.kick_kind == "parry"):
			outcome = "save"
		elif m.phase == Match.Phase.RESTART or _t > 3.0:
			outcome = "miss"
		if outcome == "":
			return
		_results[outcome] += 1
		if OS.get_environment("GKDEBUG") != "":
			print("  %s touched=%s state=%d gkpos=(%.1f,%.1f) ball=(%.1f,%.1f,%.1f) speed=%.1f" % [outcome, b.tried.has(gk), gk.state, gk.position.x, gk.position.z, b.position.x, b.position.y, b.position.z, b.velocity.length()])
	_cur += 1
	if _cur >= _shots.size():
		_done = true
		var total := float(_shots.size())
		print("PORTERO vs tiros normales (12-24 m): goles %d, atajadas %d, fuera %d" % [_results["goal"], _results["save"], _results["miss"]])
		_check("ratio gol razonable", _results["goal"] / total < 0.55, "%.0f%% goles" % (_results["goal"] / total * 100.0))
		print("FAILURES: %d" % failures)
		get_tree().quit()
		return
	var s: Dictionary = _shots[_cur]
	m._set_phase(Match.Phase.PLAY)
	m.ball.in_goal = false
	var goal_x := m.hl
	shooter.position = Vector3(goal_x - s["dist"], 0, s["z"])
	shooter.facing = (Vector3(goal_x, 0, 0) - shooter.position).normalized()
	shooter.velocity = Vector3.ZERO
	shooter._set_state(Player.State.NORMAL)
	shooter.frozen = false
	gk.position = Vector3(goal_x - 1.0, 0, 0)
	gk._set_state(Player.State.NORMAL)
	gk.velocity = Vector3.ZERO
	b.place(shooter.position + shooter.facing * 0.5)
	b.set_carrier(shooter)
	shooter.aim_dir = Vector3(0.6, 0, s["aim"]).normalized()
	shooter.aim_active = true
	shooter.perform("shot", s["charge"], {})
	_t = 0.0
