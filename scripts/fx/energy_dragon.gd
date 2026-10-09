class_name EnergyDragon
extends Node3D
## Dragón de energía de las técnicas especiales (estilo Captain Tsubasa):
## su cuerpo serpentea siguiendo al objetivo (el balón o el jugador) y la
## cabeza lleva el balón entre las fauces. Todo procedural.

const SEGMENTS := 36
const RING := 12

var target: Node3D
var offset := Vector3.ZERO
var color_a := Color(1.0, 0.35, 0.1)
var color_b := Color(1.0, 0.9, 0.45)
var size := 1.0
var life := 2.6
var spacing := 0.3

var _age := 0.0
var _points: Array[Vector3] = []
var _body: MeshInstance3D
var _mesh := ArrayMesh.new()
var _mat: ShaderMaterial
var _head_mat: ShaderMaterial
var _head: Node3D
var _jaw: Node3D
var _whiskers: Array[Node3D] = []
var _fins: Array[MeshInstance3D] = []
var _sparks: CPUParticles3D
var _last_pos := Vector3.ZERO


## Crea un dragón que sigue a `target`.
static func spawn(world: Node3D, target_: Node3D, col_a: Color, col_b: Color, size_ := 1.0, life_ := 2.6, offset_ := Vector3.ZERO) -> EnergyDragon:
	var d := EnergyDragon.new()
	d.target = target_
	d.color_a = col_a
	d.color_b = col_b
	d.size = size_
	d.life = life_
	d.offset = offset_
	d.spacing = 0.3 * size_
	world.add_child(d)
	return d


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var shader: Shader = load("res://shaders/dragon.gdshader")
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("color_a", color_a)
	_mat.set_shader_parameter("color_b", color_b)
	_head_mat = ShaderMaterial.new()
	_head_mat.shader = shader
	_head_mat.set_shader_parameter("color_a", color_a)
	_head_mat.set_shader_parameter("color_b", color_b)
	_head_mat.set_shader_parameter("body", 0.0)
	_head_mat.set_shader_parameter("intensity", 1.3)
	_body = MeshInstance3D.new()
	_body.mesh = _mesh
	_body.material_override = _mat
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)
	_build_head()
	for i in 9:
		var fin := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.07 * size
		cone.height = 0.32 * size
		cone.radial_segments = 4
		fin.mesh = cone
		fin.material_override = _head_mat
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fin)
		_fins.append(fin)
	_sparks = CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04 * size
	sm.height = 0.08 * size
	sm.radial_segments = 4
	sm.rings = 2
	var spm := StandardMaterial3D.new()
	spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spm.albedo_color = color_b
	sm.material = spm
	_sparks.mesh = sm
	_sparks.amount = 60
	_sparks.lifetime = 0.7
	_sparks.direction = Vector3.UP
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 0.5
	_sparks.initial_velocity_max = 2.5
	_sparks.gravity = Vector3(0, 1.0, 0)
	_sparks.local_coords = false
	_head.add_child(_sparks)
	if is_instance_valid(target):
		_last_pos = target.global_position + offset
		for i in 4:
			_points.append(_last_pos - Vector3.UP * 0.001 * i)


func _cone(r: float, h: float, segs := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r * size
	c.height = h * size
	c.radial_segments = segs
	return c


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, rot_deg: Vector3, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat != null else _head_mat
	mi.position = pos * size
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Cabeza: mira hacia -Z (adelante).
func _build_head() -> void:
	_head = Node3D.new()
	_head.scale = Vector3.ONE * 1.35
	add_child(_head)
	# Cráneo
	var skull := CapsuleMesh.new()
	skull.radius = 0.2 * size
	skull.height = 0.62 * size
	_part(_head, skull, Vector3(0, 0.05, 0.12), Vector3(90, 0, 0))
	# Hocico superior (se afina hacia adelante)
	var snout := CylinderMesh.new()
	snout.top_radius = 0.07 * size
	snout.bottom_radius = 0.15 * size
	snout.height = 0.5 * size
	var sn := _part(_head, snout, Vector3(0, 0.06, -0.32), Vector3(-90, 0, 0))
	sn.scale = Vector3(1.25, 1.0, 0.75)
	# Mandíbula inferior (se abre y se cierra)
	_jaw = Node3D.new()
	_jaw.position = Vector3(0, -0.04, -0.05) * size
	_head.add_child(_jaw)
	var jaw := CylinderMesh.new()
	jaw.top_radius = 0.05 * size
	jaw.bottom_radius = 0.11 * size
	jaw.height = 0.46 * size
	var jm := _part(_jaw, jaw, Vector3(0, -0.04, -0.24), Vector3(-90, 0, 0))
	jm.scale = Vector3(1.2, 1.0, 0.5)
	# Colmillos
	var tooth_mat := StandardMaterial3D.new()
	tooth_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tooth_mat.albedo_color = Color(1, 1, 1)
	for sx in [-1.0, 1.0]:
		_part(_head, _cone(0.025, 0.12, 4), Vector3(0.07 * sx, -0.06, -0.45), Vector3(180, 0, 0), tooth_mat)
		_part(_head, _cone(0.02, 0.09, 4), Vector3(0.09 * sx, -0.05, -0.3), Vector3(180, 0, 0), tooth_mat)
	# Cuernos hacia atrás
	for sx in [-1.0, 1.0]:
		_part(_head, _cone(0.06, 0.6), Vector3(0.12 * sx, 0.24, 0.32), Vector3(-62, 0, -18 * sx))
		_part(_head, _cone(0.035, 0.32), Vector3(0.17 * sx, 0.12, 0.28), Vector3(-75, 0, -40 * sx))
	# Melena de púas
	for i in 5:
		_part(_head, _cone(0.05, 0.36), Vector3((i - 2) * 0.06, 0.15 - absf(i - 2) * 0.02, 0.42), Vector3(-80 + absf(i - 2) * 6.0, 0, (i - 2) * -12.0))
	# Ojos brillantes
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(1, 1, 0.85)
	var eye := SphereMesh.new()
	eye.radius = 0.045 * size
	eye.height = 0.07 * size
	for sx in [-1.0, 1.0]:
		var e := _part(_head, eye, Vector3(0.12 * sx, 0.14, -0.08), Vector3(0, 0, 0), eye_mat)
		e.scale = Vector3(1.0, 0.6, 1.4)
	# Bigotes largos
	for sx in [-1.0, 1.0]:
		var w := Node3D.new()
		w.position = Vector3(0.09 * sx, 0.02, -0.5) * size
		_head.add_child(w)
		var wm := CylinderMesh.new()
		wm.top_radius = 0.004 * size
		wm.bottom_radius = 0.018 * size
		wm.height = 0.9 * size
		_part(w, wm, Vector3(0, 0, 0.42), Vector3(-90, 0, 0))
		_whiskers.append(w)


func _process(delta: float) -> void:
	_age += delta
	var fade := clampf((life - _age) / 0.6, 0.0, 1.0) * clampf(_age / 0.15, 0.0, 1.0)
	_mat.set_shader_parameter("fade", fade)
	_head_mat.set_shader_parameter("fade", fade)
	if _age > life:
		queue_free()
		return
	if is_instance_valid(target):
		_last_pos = target.global_position + offset
	if _points.size() < 2 or _last_pos.distance_to(_points[1]) > spacing:
		_points.push_front(_last_pos)
		if _points.size() > SEGMENTS:
			_points.pop_back()
	else:
		_points[0] = _last_pos
	_build_body()
	_place_head()


func _frame(i: int) -> Array:
	var n := _points.size()
	var a := _points[maxi(i - 1, 0)]
	var b := _points[mini(i + 1, n - 1)]
	var t := a - b
	if t.length() < 0.001:
		t = Vector3.FORWARD
	t = t.normalized()
	var side := t.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(t).normalized()
	return [t, side, up]


func _center(i: int, side: Vector3, up: Vector3) -> Vector3:
	# Ondulación de serpiente que viaja por el cuerpo (más amplia hacia la cola)
	var k := float(i) / float(SEGMENTS)
	var env := sin(k * PI) * 0.7 + k * 0.3
	var w := sin(_age * 6.0 - i * 0.42) * 1.1 * size * env
	var v := cos(_age * 4.5 - i * 0.36) * 0.7 * size * env
	return _points[i] + side * w + up * v


func _build_body() -> void:
	_mesh.clear_surfaces()
	var n := _points.size()
	if n < 3:
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in n:
		var fr := _frame(i)
		var side: Vector3 = fr[1]
		var up: Vector3 = fr[2]
		var c := _center(i, side, up)
		var k := float(i) / float(SEGMENTS)
		# Grueso detrás de la cabeza y se afina hacia la cola
		var r := size * (0.05 + 0.3 * pow(1.0 - k, 0.7) * (0.85 + 0.15 * sin(k * 18.0)))
		if i == 0:
			r *= 0.7
		for j in RING + 1:
			var ang := TAU * float(j) / float(RING)
			var nrm := side * cos(ang) + up * sin(ang)
			verts.append(c + nrm * r)
			normals.append(nrm)
			uvs.append(Vector2(k, float(j) / float(RING)))
	for i in n - 1:
		for j in RING:
			var a := i * (RING + 1) + j
			var b := a + RING + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# Aletas dorsales sobre el lomo
	for f in _fins.size():
		var i2 := 2 + f * 3
		_fins[f].visible = i2 < n - 1
		if not _fins[f].visible:
			continue
		var fr2 := _frame(i2)
		var t2: Vector3 = fr2[0]
		var up2: Vector3 = fr2[2]
		var k2 := float(i2) / float(SEGMENTS)
		var r2 := size * (0.05 + 0.24 * pow(1.0 - k2, 0.7))
		var base := _center(i2, fr2[1], up2) + up2 * r2 * 0.9
		var fin_up := (up2 * 0.6 - t2 * 0.8).normalized()
		var xa := fin_up.cross(t2).normalized()
		var za := xa.cross(fin_up).normalized()
		var sc := 1.0 - k2 * 0.6
		_fins[f].global_transform = Transform3D(Basis(xa * sc, fin_up * sc, za * sc), base)


func _place_head() -> void:
	if _points.size() < 2:
		_head.global_position = _last_pos
		return
	var fwd := (_points[0] - _points[mini(2, _points.size() - 1)])
	if fwd.length() < 0.01:
		fwd = -_head.global_transform.basis.z
	fwd = fwd.normalized()
	# El balón queda entre las fauces
	var pos := _points[0] - fwd * 0.05 * size + Vector3.UP * 0.02
	var up := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	_head.global_transform = Transform3D(Basis.looking_at(fwd, up), pos)
	_jaw.rotation.x = 0.25 + sin(_age * 9.0) * 0.18
	for i in _whiskers.size():
		_whiskers[i].rotation = Vector3(sin(_age * 6.0 + i) * 0.35, (0.35 if i == 0 else -0.35) + sin(_age * 4.0 + i * 2.0) * 0.25, 0.0)
