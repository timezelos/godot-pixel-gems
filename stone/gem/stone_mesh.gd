extends RefCounted

## Cuts an ellipsoidal blank with tool planes in unit-sphere coordinates.
## UV.x is distance in model units to the facet rim. UV2 stores (facet ID, cut mask).
const RADII := Vector3(1.55, 0.91, 1.20)
const SIDES := 8
const MERIDIANS := 40
const LATITUDES := 20
const EPSILON := 0.000001
const RINGS := [
	Vector2(0.66, 0.70), Vector2(0.88, 0.40), Vector2(0.97, 0.13),
	Vector2(0.98, -0.075), Vector2(0.85, -0.43), Vector2(0.52, -0.78),
	Vector2(0.14, -0.93),
]


class Face:
	var points: PackedVector3Array
	var normal: Vector3
	var id: int

	func _init(vertices: PackedVector3Array, outward := Vector3.ZERO, facet_id := -1) -> void:
		points = vertices
		normal = outward
		id = facet_id


static var _blank: Array[Face] = []
static var _planes: Array[Plane] = []
static var _start: PackedFloat32Array = []
static var _finish: PackedFloat32Array = []


static func build(cut_progress: float) -> ArrayMesh:
	if _blank.is_empty():
		_make_blank()
		_make_planes()
	var faces: Array[Face] = _blank.duplicate()
	for i in _planes.size():
		var t := smoothstep(_start[i], _finish[i], clampf(cut_progress, 0.0, 1.0))
		if t <= 0.0:
			continue
		var plane := _planes[i]
		# At distance 1 the tool is tangent to the blank. Moving it inward
		# first opens a small round window, then meets neighboring cuts.
		plane.d = lerpf(1.0, plane.d, t)
		faces = _clip(faces, plane, i)
	return _mesh_from_faces(faces)


static func _make_blank() -> void:
	var rings: Array[PackedVector3Array] = []
	for j in range(1, LATITUDES):
		var lat := PI * float(j) / LATITUDES
		var ring := PackedVector3Array()
		for i in MERIDIANS:
			var phi := TAU * float(i) / MERIDIANS
			ring.append(Vector3(sin(lat) * cos(phi), cos(lat), sin(lat) * sin(phi)))
		rings.append(ring)
	for i in MERIDIANS:
		var next := (i + 1) % MERIDIANS
		_blank.append(Face.new(PackedVector3Array([Vector3.UP, rings[0][i], rings[0][next]])))
		for j in range(rings.size() - 1):
			_blank.append(Face.new(PackedVector3Array([
				rings[j][i], rings[j + 1][i], rings[j + 1][next], rings[j][next],
			])))
		_blank.append(Face.new(PackedVector3Array([rings[-1][i], Vector3.DOWN, rings[-1][next]])))


static func _make_planes() -> void:
	_planes.append(Plane(Vector3.UP, RINGS[0].y))
	_start.append(0.44)
	_finish.append(1.0)
	var apothem := cos(PI / SIDES)
	for row in range(RINGS.size() - 1):
		var a: Vector2 = RINGS[row]
		var b: Vector2 = RINGS[row + 1]
		var slope := apothem * (b.x - a.x) / (a.y - b.y)
		for side in SIDES:
			var phi := TAU * (side + 0.5) / SIDES
			var normal := Vector3(cos(phi), slope, sin(phi))
			_planes.append(Plane(normal.normalized(), (a.x * apothem + a.y * slope) / normal.length()))
			# The first four windows appear on the visible crown and front.
			var delay := 0.45 + 0.14 * (1.0 - sin(phi)) + 0.022 * row
			var finish := 1.0
			var first_window := (row == 0 and side in [1, 2]) or (row == 1 and side == 2) or (row == 3 and side == 1)
			if first_window:
				delay = 0.012 * (row + side - 1)
				finish = 0.57
			_start.append(minf(delay, 0.82))
			_finish.append(finish)
	_planes.append(Plane(Vector3.DOWN, -RINGS[-1].y))
	_start.append(0.62)
	_finish.append(1.0)


static func _clip(faces: Array[Face], plane: Plane, id: int) -> Array[Face]:
	var result: Array[Face] = []
	var rim := {}
	for face in faces:
		var points := face.points
		var inside := 0
		for p in points:
			if plane.distance_to(p) <= EPSILON:
				inside += 1
		if inside == points.size():
			result.append(face)
			continue
		if inside == 0:
			continue
		var kept := PackedVector3Array()
		var a := points[-1]
		var da := plane.distance_to(a)
		for b in points:
			var db := plane.distance_to(b)
			if (da <= EPSILON) != (db <= EPSILON):
				var hit := a.lerp(b, clampf(da / (da - db), 0.0, 1.0))
				kept.append(hit)
				rim[Vector3i((hit * 100000.0).round())] = hit
			if db <= EPSILON:
				kept.append(b)
			a = b
			da = db
		if kept.size() >= 3:
			result.append(Face.new(kept, face.normal, face.id))
	if rim.size() >= 3:
		var contour: Array = rim.values()
		var center := Vector3.ZERO
		for p: Vector3 in contour:
			center += p
		center /= float(contour.size())
		var u := (Vector3(contour[0]) - center).normalized()
		var v := plane.normal.cross(u)
		contour.sort_custom(func(pa: Vector3, pb: Vector3) -> bool:
			var va := pa - center
			var vb := pb - center
			return atan2(va.dot(v), va.dot(u)) < atan2(vb.dot(v), vb.dot(u))
		)
		result.append(Face.new(PackedVector3Array(contour), plane.normal, id))
	return result


static func _mesh_from_faces(faces: Array[Face]) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var pts := face.points
		if face.id < 0:
			for j in range(1, pts.size() - 1):
				_add_triangle(tool, pts[0], pts[j], pts[j + 1], face, 0.0)
			continue
		var center := Vector3.ZERO
		for p in pts:
			center += p
		center /= float(pts.size())
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			var edge := (b - a) * RADII
			if edge.length_squared() < EPSILON * EPSILON:
				continue
			var altitude := edge.cross((center - a) * RADII).length() / edge.length()
			_add_triangle(tool, center, a, b, face, altitude)
	return tool.commit()


static func _add_triangle(tool: SurfaceTool, center: Vector3, a: Vector3, b: Vector3,
		face: Face, altitude: float) -> void:
	var cross_normal := (a - center).cross(b - center)
	if cross_normal.length_squared() < EPSILON * EPSILON:
		return
	var cut := face.id >= 0
	var normal := (face.normal / RADII).normalized()
	# Godot's front faces have clockwise winding when seen from outside.
	var outward := face.normal if cut else center
	if cross_normal.dot(outward) > 0.0:
		var old_a := a
		a = b
		b = old_a
	tool.set_uv2(Vector2(maxi(face.id, 0), float(cut)))
	tool.set_normal(normal if cut else (center / RADII).normalized())
	tool.set_uv(Vector2(altitude, 0.0))
	tool.add_vertex(center * RADII)
	tool.set_uv(Vector2.ZERO)
	tool.set_normal(normal if cut else (a / RADII).normalized())
	tool.add_vertex(a * RADII)
	tool.set_normal(normal if cut else (b / RADII).normalized())
	tool.add_vertex(b * RADII)
