extends Node
## Efectos "anime": cámara lenta, primeros planos, sacudidas, partículas y
## post-imágenes. Usa tiempo real para no quedar atrapado en la cámara lenta.

signal shake_requested(amount: float)
signal closeup_requested(target: Node3D, real_seconds: float)

var world: Node3D
var _slow_until_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _slow_until_ms > 0 and Time.get_ticks_msec() >= _slow_until_ms:
		_slow_until_ms = 0
		Engine.time_scale = 1.0


func slowmo(time_scale: float, real_seconds: float) -> void:
	Engine.time_scale = time_scale
	_slow_until_ms = Time.get_ticks_msec() + int(real_seconds * 1000.0)


func reset() -> void:
	_slow_until_ms = 0
	Engine.time_scale = 1.0


func shake(amount: float) -> void:
	shake_requested.emit(amount)


func closeup(target: Node3D, real_seconds: float) -> void:
	closeup_requested.emit(target, real_seconds)


func burst(pos: Vector3, color: Color, amount := 28, speed := 6.0, life := 0.6) -> void:
	if world == null:
		return
	var p := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -4.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	world.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)


## Copia translúcida del jugador que se desvanece (regates fantasma, despertar).
func afterimage(source: Node3D, color: Color, life := 0.35) -> void:
	if world == null:
		return
	var ghost := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
	for mi in source.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3 == null or not m3.visible or m3.get_meta("no_ghost", false):
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = m3.mesh
		copy.material_override = mat
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(copy)
		copy.global_transform = m3.global_transform
	world.add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(ghost.queue_free)


## Onda expansiva plana sobre el césped.
func ring(pos: Vector3, color: Color, max_radius := 3.0, life := 0.45) -> void:
	if world == null:
		return
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	mi.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.05, pos.z)
	mi.scale = Vector3(0.3, 0.05, 0.3)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(max_radius, 0.05, max_radius), life)
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(mi.queue_free)
