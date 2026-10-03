extends ScrollContainer

# 터치 기기에서는 Godot의 관성 스크롤을 사용하고, 일반 마우스에도 본문 드래그를 더한다.
var _pointer_down := false
var _dragging := false
var _origin := Vector2.ZERO
var _initial_scroll := 0

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_cancel_pointer()
		return
	if DisplayServer.is_touchscreen_available() or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _inside_content(event.position):
				return
			_pointer_down = true
			_origin = _local_position(event.position)
			_initial_scroll = scroll_vertical
		else:
			_end_pointer()
		# 짧은 클릭과 release는 GUI까지 전달해 버튼 및 마우스 캡처를 정상 해제한다.
	elif event is InputEventMouseMotion and _pointer_down:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_cancel_pointer()
			return
		var distance := _local_position(event.position).y - _origin.y
		if not _dragging and absf(distance) >= maxf(float(scroll_deadzone), 10.0):
			_dragging = true
			# 자식 버튼이 눌린 채 시작한 드래그는 클릭으로 확정되지 않게 한다.
			propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
			scroll_started.emit()
		if _dragging:
			scroll_vertical = _initial_scroll - roundi(distance)
			get_viewport().set_input_as_handled()

func _inside_content(position_value: Vector2) -> bool:
	if vertical_scroll_mode == SCROLL_MODE_DISABLED:
		return false
	var bar := get_v_scroll_bar()
	if bar.max_value <= bar.page or not Rect2(Vector2.ZERO, size).has_point(_local_position(position_value)):
		return false
	for scrollbar in [bar, get_h_scroll_bar()]:
		var local: Vector2 = scrollbar.get_global_transform_with_canvas().affine_inverse() * position_value
		if scrollbar.is_visible_in_tree() and Rect2(Vector2.ZERO, scrollbar.size).has_point(local):
			return false
	return true

func _local_position(position_value: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * position_value

func _end_pointer() -> void:
	_pointer_down = false
	if _dragging:
		_dragging = false
		propagate_notification(Control.NOTIFICATION_SCROLL_END)
		scroll_ended.emit()

func _cancel_pointer() -> void:
	if _pointer_down and not _dragging:
		propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
		propagate_notification(Control.NOTIFICATION_SCROLL_END)
	_end_pointer()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_EXIT_TREE]:
		_cancel_pointer()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_cancel_pointer()
