extends RefCounted

# 전장 하나가 세 메시를 소유하며 전장이 해제되면 함께 해제된다.
# 위치·크기·색은 그릴 때만 적용하고 표면은 생성 후 변경하지 않는다.
var shadow: ArrayMesh = _build_radial_mesh(24)
var star: ArrayMesh = _build_radial_mesh(10, true)
var range_fill: ArrayMesh = _build_radial_mesh(48)

func _build_radial_mesh(point_count: int, is_star: bool = false) -> ArrayMesh:
	var points := PackedVector2Array()
	for index in range(point_count):
		var angle := TAU * index / float(point_count)
		var radius := 1.0
		if is_star:
			angle = -PI * 0.5 + TAU * index / 10.0
			radius = 1.0 if index % 2 == 0 else 0.45
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_INDEX] = Geometry2D.triangulate_polygon(points)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh
