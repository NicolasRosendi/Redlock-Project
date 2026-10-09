extends Node
## Simulación headless de un partido IA vs IA para detectar errores y medir
## que el juego "fluya" (pases, tiros, quites, goles...).
## Uso: godot --headless --path . --fixed-fps 60 res://tests/sim_test.tscn -- --size=7 --minutes=3

var match_node: Match
var frames := 0
var max_frames := 0


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	GameConfig.control_mode = GameConfig.ControlMode.AI_ONLY
	GameConfig.team_size = int(args.get("size", "7"))
	GameConfig.match_minutes = float(args.get("minutes", "3"))
	GameConfig.difficulty = 1
	seed(int(args.get("seed", "1")))
	max_frames = int(GameConfig.match_minutes * 60.0 * 60.0 * 1.6) + 1200
	match_node = load("res://scenes/match.tscn").instantiate()
	add_child(match_node)


func _physics_process(_delta: float) -> void:
	frames += 1
	Engine.time_scale = 1.0
	if frames >= max_frames or match_node.phase == Match.Phase.FULLTIME:
		var t0 := match_node.teams[0]
		var t1 := match_node.teams[1]
		print("RESULT %dv%d: %s %d - %d %s (clock %.0fs, frames %d)" % [
			GameConfig.team_size, GameConfig.team_size, t0.short_name, t0.score, t1.score, t1.short_name, match_node.clock, frames])
		print("TIEMPO: mitad %d, fase %d (FULLTIME=%d), reloj %s, corners %d" % [match_node.half, match_node.phase, Match.Phase.FULLTIME, match_node.clock_text(), match_node.stats["corners"]])
		print("STATS ", match_node.stats)
		get_tree().quit()
