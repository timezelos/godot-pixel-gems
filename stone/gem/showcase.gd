extends Control

const StoneMesh = preload("res://gem/stone_mesh.gd")
const LETTERING = preload("res://gem/lettering.png")
const CUT_LEVELS := [0.0, 0.43, 1.0, 1.0]
const MESH_STEPS := 28
const FLOOR_Y := -1.69
const INITIAL_YAW := 0.12
const INITIAL_PITCH := 0.12
const STAGE_TIMES := [1.3, 2.2, 2.0, 4.5]

@onready var stone: MeshInstance3D = $Studio/Stone
@onready var camera: Camera3D = $Studio/Camera
@onready var shadow: Polygon2D = $Shadow
@onready var composite: TextureRect = $Composite

var yaw := INITIAL_YAW
var spinning := true
var stage := 3
var pitch := INITIAL_PITCH
var lamp_yaw := 0.0
var cut := 1.0
var polish := 1.0
var _clock := 0.0
var _replay_time := -1.0
var _mesh_step := -1
var _vertices := PackedVector3Array()
var _mesh_cache := {}
var _anchors := PackedVector3Array()
var _toolbar := Node2D.new()
var _drag_button := MOUSE_BUTTON_NONE
var _resume_delay := 0.0


func _ready() -> void:
	camera.look_at_from_position(Vector3(0, 3.8, 7), Vector3.ZERO)
	composite.texture = $Studio.get_texture()
	add_child(_toolbar)
	_toolbar.draw.connect(_draw_toolbar)
	set_stage(3, true)


func set_stage(index: int, immediate := false) -> void:
	stage = clampi(index, 0, 3)
	_replay_time = -1.0
	if immediate:
		cut = CUT_LEVELS[stage]
		polish = 1.0 if stage == 3 else 0.0
		_update_studio()
	_toolbar.queue_redraw()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.08)
	if _replay_time >= 0.0:
		_replay_time += dt
		if _replay_time >= STAGE_TIMES[stage]:
			if stage < 3:
				set_stage(stage + 1)
				_replay_time = 0.0
			else:
				_replay_time = -1.0
	_resume_delay = maxf(0.0, _resume_delay - dt)
	if spinning and _drag_button == MOUSE_BUTTON_NONE and _resume_delay == 0.0:
		if _replay_time < 0.0 or (stage == 3 and polish >= 0.99):
			yaw += dt * 0.29
		_clock += dt
	cut = move_toward(cut, CUT_LEVELS[stage], dt * 0.53)
	# Light enters only after the cutting planes reach their final depth.
	var target_polish := 1.0 if stage == 3 and cut >= 0.99 else 0.0
	polish = move_toward(polish, target_polish, dt * 0.85)
	_update_studio()


func _update_studio() -> void:
	var step_index := roundi(cut * MESH_STEPS)
	if step_index != _mesh_step:
		_mesh_step = step_index
		if not _mesh_cache.has(step_index):
			_mesh_cache[step_index] = StoneMesh.build(float(step_index) / MESH_STEPS)
		stone.mesh = _mesh_cache[step_index]
		var arrays := stone.mesh.surface_get_arrays(0)
		var unique := {}
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			unique[vertex.snappedf(0.0005)] = true
		_vertices = PackedVector3Array(unique.keys())
		_find_glint_anchors()
	var bob := 0.028 * sin(_clock * 1.12)
	stone.position.y = bob
	stone.basis = Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, yaw)
	var light := Vector3(-0.47, 0.88, -0.47).normalized().rotated(Vector3.UP, lamp_yaw)
	stone.material_override.set_shader_parameter("light_dir", light)
	stone.material_override.set_shader_parameter("polish", polish)
	_project_shadow(light)
	_update_glints(light)


func _project_shadow(light: Vector3) -> void:
	# Orthographic projection is affine, so all vertices can share these axes.
	var center := camera.unproject_position(Vector3(0, FLOOR_Y, 0))
	var axis_x := camera.unproject_position(Vector3(1, FLOOR_Y, 0)) - center
	var axis_z := camera.unproject_position(Vector3(0, FLOOR_Y, 1)) - center
	var cast := Vector2(light.x, light.z) / light.y
	var projected := PackedVector2Array()
	for vertex in _vertices:
		var world := stone.transform * vertex
		var floor_xz := Vector2(world.x, world.z) - cast * (world.y - FLOOR_Y)
		projected.append(center + axis_x * floor_xz.x + axis_z * floor_xz.y)
	var hull := Geometry2D.convex_hull(projected)
	if hull.size() < 4:
		return
	hull.resize(hull.size() - 1) # convex_hull closes the loop, Polygon2D does so itself.
	shadow.polygon = hull
	var bounds := Rect2(hull[0], Vector2.ZERO)
	for point in hull:
		bounds = bounds.expand(point)
	shadow.material.set_shader_parameter("footprint_center", bounds.get_center())
	shadow.material.set_shader_parameter("footprint_radius", bounds.size * 0.5)
	shadow.material.set_shader_parameter("azimuth", yaw - lamp_yaw)
	shadow.material.set_shader_parameter("polish", polish)


func _find_glint_anchors() -> void:
	_anchors.clear()
	# Snap each highlight to a facet junction so it travels with the solid.
	for target: Vector3 in [Vector3(0.43,0.48,0.86), Vector3(-0.88,-0.23,0.90),
			Vector3(0.52,0.54,-0.82), Vector3(-1.34,0.22,0.24)]:
		var best := target
		var distance := INF
		for point in _vertices:
			var gap := point.distance_squared_to(target)
			if gap < distance:
				distance = gap
				best = point
		_anchors.append(best)


func _update_glints(light: Vector3) -> void:
	var glints := PackedVector3Array()
	var view := camera.global_basis.z.normalized()
	for i in _anchors.size():
		var anchor := _anchors[i]
		var facing := (stone.basis * (anchor / Vector3(1.55, 0.91, 1.20)).normalized()).dot(view)
		var phase := (yaw - INITIAL_YAW) * 2.6 - lamp_yaw * 1.7 + i * 2.25
		var peak := pow(maxf(0.0, cos(phase)), 8.0)
		var radius := (7.6 if i == 0 else 4.0) * peak
		if facing < 0.20 or light.y <= 0.0:
			radius = -1.0
		var screen := camera.unproject_position(stone.transform * anchor)
		glints.append(Vector3(screen.x, screen.y, radius))
	composite.material.set_shader_parameter("glints", glints)
	composite.material.set_shader_parameter("polish", polish)


func _draw_toolbar() -> void:
	for i in 4:
		var x := 8 + 32*i
		var ink := Color("#147047") if i == stage else Color("#676a65")
		_toolbar.draw_texture_rect_region(LETTERING, Rect2(x,188,32,13), Rect2(32*i,39,32,13), ink)
		if stage == i:
			_toolbar.draw_rect(Rect2(x + 3,203,22,1), ink)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			set_stage(event.keycode - KEY_1)
		elif event.keycode == KEY_SPACE:
			spinning = not spinning
		elif event.keycode == KEY_R:
			yaw = INITIAL_YAW
			pitch = INITIAL_PITCH
			lamp_yaw = 0.0
			spinning = true
			set_stage(0, true)
			_replay_time = 0.0
	elif event is InputEventMouseButton:
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return
		if event.pressed:
			if event.position.y >= 184 and event.button_index == MOUSE_BUTTON_LEFT:
				set_stage(clampi(floori((event.position.x - 8.0)/32.0), 0, 3))
			else:
				_drag_button = event.button_index
		else:
			_drag_button = MOUSE_BUTTON_NONE
	elif event is InputEventMouseMotion and _drag_button != MOUSE_BUTTON_NONE:
		_resume_delay = 1.3
		if _drag_button == MOUSE_BUTTON_RIGHT or event.shift_pressed:
			lamp_yaw += event.relative.x * 0.028
		else:
			yaw += event.relative.x * 0.025
			pitch = clampf(pitch + event.relative.y * 0.018, -1.2, 1.1)
