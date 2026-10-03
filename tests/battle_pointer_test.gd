extends SceneTree

const BOARD = preload("res://game/battle_board.gd")
const SIMULATION = preload("res://game/simulation.gd")
var failures: Array[String] = []
var moves: Array = []
var selections: Array = []

func _init() -> void:
	var sim = SIMULATION.new()
	sim.new_run(341)
	sim.units.clear()
	var first: Dictionary = sim.add_unit("u01", 0)
	var board = BOARD.new()
	board.simulation = sim
	board.cell_dragged.connect(func(id, cell): moves.append([id, cell]))
	board.cell_pressed.connect(func(cell): selections.append(cell))
	_check(not board._placement_grid_visible(), "평상시 격자는 숨긴다")
	var origin: Vector2 = board.ground_to_screen(Vector2(0.5, 0.5))
	var target: Vector2 = board.ground_to_screen(Vector2(1.5, 2.5))
	board._begin_pointer(origin)
	board._move_pointer(origin + Vector2(3, 3))
	_check(board._drag_target_cell() == -1, "짧은 누름은 이동 안내를 시작하지 않는다")
	board._end_pointer(origin)
	_check(moves.is_empty() and selections == [0], "클릭은 선택 이벤트만 발생한다")
	board._begin_pointer(origin)
	board._move_pointer(target)
	_check(board._placement_grid_visible(), "드래그 중에만 격자를 표시한다")
	_check(board._drag_target_cell() == 8, "드래그 가이드가 실제 목적지 칸을 가리킨다")
	board._end_pointer(target)
	_check(moves == [[int(first.id), 8]], "드래그를 놓을 때만 이동 이벤트를 발생한다")
	_check(board._drag_target_cell() == -1 and not board._placement_grid_visible(), "놓은 뒤 안내와 격자를 숨긴다")
	board.blocked_screen_rects.assign([Rect2(target - Vector2(10, 10), Vector2(20, 20))])
	board._begin_pointer(origin)
	board._move_pointer(target)
	_check(board._drag_target_cell() == -1, "UI 위에는 유효한 목적지 안내를 그리지 않는다")
	board._end_pointer(target)
	_check(moves.size() == 1, "UI 위에 놓으면 이동을 취소한다")
	board._begin_pointer(origin)
	board._move_pointer(Vector2(-30, -30))
	board._end_pointer(Vector2(-30, -30))
	_check(moves.size() == 1, "전장 밖에 놓으면 이동을 취소한다")
	_check(board.enemy_position(0).is_equal_approx(board.enemy_position(SIMULATION.PATH_LENGTH)), "출입구는 같은 한 점이다")
	_check(board.enemy_position(0.1).y > board.enemy_position(0).y, "성문에서 아래쪽으로 출발한다")
	_check(board.enemy_position(7.1).x > board.enemy_position(7.0).x, "왼쪽 아래 모서리에서 오른쪽으로 돈다")
	_check(board.screen_to_cell(board.unit_foot_position(0)) == 0, "큰 용병의 발은 자기 칸 안에 남는다")
	var paths: Array[Rect2] = board._terrain_path_rects()
	_check(paths.size() == 4, "흙길은 네 개의 축 정렬 직사각형이다")
	_check(paths[0].size == paths[1].size and paths[2].size == paths[3].size, "마주 보는 길의 폭과 길이가 같다")
	_check(paths[0].size.y == board.CELL_SIZE and paths[2].size.x == paths[0].size.y, "네 변의 길 폭이 모두 한 칸으로 같다")
	_check(paths[0].position.x == paths[1].position.x and paths[2].position.y == paths[3].position.y, "마주 보는 길이 정확히 평행하다")
	for distance in [0.0, 1.0, 7.0, 8.0, 14.0, 21.0, 27.0, 28.0]:
		_check(board.enemy_position(distance).is_equal_approx(sim.path_position(distance)), "렌더링과 사거리 판정 경로는 같은 좌표를 쓴다")
	board.free()
	print("BATTLE_POINTER_REPORT ", JSON.stringify({"failed": failures}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
