class_name CameraRig
extends Camera3D
## Cámara de transmisión (lateral, como la TV) o detrás del jugador.
## Hace primeros planos durante las técnicas especiales y vibra con los golpes.

var m: Match
var mode := 0
var _look := Vector3.ZERO
var _shake := 0.0
var _closeup_target: Node3D = null
var _closeup_until_ms := 0


func _ready() -> void:
	mode = GameConfig.camera_mode
	fov = 42.0
	current = true
	far = 600.0
	FX.shake_requested.connect(func(a: float) -> void: _shake = maxf(_shake, a))
	FX.closeup_requested.connect(_on_closeup)
	_snap()


func _on_closeup(target: Node3D, real_seconds: float) -> void:
	_closeup_target = target
	_closeup_until_ms = Time.get_ticks_msec() + int(real_seconds * 1000.0)


func toggle_mode() -> void:
	mode = 1 - mode
	GameConfig.camera_mode = mode


## Convierte el stick a una dirección en el césped. Usa la orientación "base"
## de la cámara para que los controles no cambien durante los primeros planos.
func stick_to_world(stick: Vector2) -> Vector3:
	var right := Vector3.RIGHT
	var fwd := Vector3.FORWARD
	if mode == 1 and m.human != null and m.human.player != null:
		fwd = m.human.team.attack_dir()
		right = fwd.cross(Vector3.UP)
	return right * stick.x + fwd * (-stick.y)


func _snap() -> void:
	var t := _targets()
	position = t[0]
	_look = t[1]
	look_at(_look)


func _targets() -> Array:
	var b := m.ball.position
	var hp: Player = m.human.player if m.human != null else null
	if mode == 1 and hp != null:
		var fwd := m.human.team.attack_dir()
		var focus := hp.position.lerp(b, 0.25)
		var pos := hp.position - fwd * 9.0 + Vector3(0, 5.5, 0)
		pos.z = lerpf(pos.z, b.z, 0.2)
		return [pos, focus + fwd * 6.0 + Vector3(0, 0.5, 0)]
	var focus2 := Vector3(b.x, 0.0, b.z)
	if hp != null:
		focus2 = focus2.lerp(Vector3(hp.position.x, 0.0, hp.position.z), 0.25)
	var size_k := clampf((m.hl - 20.0) / 32.5, 0.0, 1.0)
	var dist := lerpf(20.0, 36.0, size_k)
	var height := dist * 0.62
	var pos2 := Vector3(focus2.x * 0.93, height, focus2.z * 0.35 + m.hw * 0.25 + dist)
	return [pos2, Vector3(focus2.x * 0.96, 0.0, focus2.z * 0.8)]


func _process(delta: float) -> void:
	if m == null:
		return
	var real_dt := delta / maxf(Engine.time_scale, 0.05)
	if get_tree().paused:
		real_dt = 0.0
	if Input.is_action_just_pressed("camera_toggle"):
		toggle_mode()
	var t := _targets()
	var want_pos: Vector3 = t[0]
	var want_look: Vector3 = t[1]
	var want_fov := 42.0 if mode == 0 else 60.0
	var rate := 4.0
	if _closeup_target != null and Time.get_ticks_msec() < _closeup_until_ms and is_instance_valid(_closeup_target):
		var ct := _closeup_target
		var f: Vector3 = ct.get("facing") if ct.get("facing") != null else Vector3.RIGHT
		var side := f.cross(Vector3.UP)
		want_pos = ct.global_position + f * 3.4 + side * 2.2 + Vector3(0, 1.6, 0)
		want_look = ct.global_position + Vector3(0, 1.1, 0)
		want_fov = 36.0
		rate = 9.0
	var k := 1.0 - exp(-rate * real_dt)
	position = position.lerp(want_pos, k)
	_look = _look.lerp(want_look, k)
	fov = lerpf(fov, want_fov, k)
	var shake_off := Vector3.ZERO
	if _shake > 0.0:
		shake_off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.25
		_shake = maxf(_shake - real_dt * 2.5, 0.0)
	look_at(_look + shake_off)
