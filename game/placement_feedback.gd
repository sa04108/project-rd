extends RefCounted

const Simulation = preload("res://game/simulation.gd")
const DISTANCE_EPSILON := 0.000001

# 직접 공격의 기하학적 도달 여부만 분류한다. 지원 효과·배치 허용·전투 판정은 바꾸지 않는다.
# 전장 밖 좌표도 사각 경로의 가장 가까운 선분까지의 거리로 처리한다.
static func attack_coverage(attack_range: float, ground: Vector2) -> String:
	if not is_finite(attack_range) or attack_range < 0.0 or not is_finite(ground.x) or not is_finite(ground.y):
		return "none"
	var path_min: float = Simulation.PATH_MIN
	var path_max: float = Simulation.PATH_MAX
	var closest := Vector2(clampf(ground.x, path_min, path_max), clampf(ground.y, path_min, path_max))
	var distance: float = ground.distance_to(closest)
	if ground.x >= path_min and ground.x <= path_max and ground.y >= path_min and ground.y <= path_max:
		distance = minf(minf(ground.x - path_min, path_max - ground.x), minf(ground.y - path_min, path_max - ground.y))
	var reach: float = attack_range - distance
	# 전투 거리 비교와 같은 미소 오차만 허용하며, 한 점의 접촉을 실질적인 공격 구간과 구분한다.
	if reach < -DISTANCE_EPSILON:
		return "none"
	if absf(reach) <= DISTANCE_EPSILON:
		return "tangent"
	return "reachable"
