extends Control

signal resume_requested

const TAP_THRESHOLD := 10.0

var _pointer_kind := ""
var _pointer_index := -1
var _press_origin := Vector2.ZERO
var _gesture_invalid := false
var _resume_sent := false
var _mouse_down := false
var _active_touches: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	queue_redraw()

func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color(0.015, 0.025, 0.04, 0.82), true)
	var scale_value := minf(size.x / 720.0, size.y / 1280.0)
	var bar_width := 14.0 * scale_value
	var bar_height := 64.0 * scale_value
	var gap := 18.0 * scale_value
	var center := size * 0.5
	var color := Color("f2e5c7")
	draw_rect(Rect2(Vector2(center.x - gap * 0.5 - bar_width, center.y - bar_height * 0.5), Vector2(bar_width, bar_height)), color, true)
	draw_rect(Rect2(Vector2(center.x + gap * 0.5, center.y - bar_height * 0.5), Vector2(bar_width, bar_height)), color, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventAction:
		accept_event()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.device != InputEvent.DEVICE_ID_EMULATION and mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_mouse_press(mouse.position)
			else:
				_mouse_release(mouse.position, mouse.canceled)
		accept_event()
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.device != InputEvent.DEVICE_ID_EMULATION and _pointer_kind == "mouse":
			_pointer_motion(motion.position)
		accept_event()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_press(touch.index, touch.position)
		else:
			_touch_release(touch.index, touch.position, touch.canceled)
		accept_event()
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_pointer_motion(drag.position, "touch", drag.index)
		accept_event()
		return
	if event is InputEventGesture:
		accept_event()

func _mouse_press(position: Vector2) -> void:
	_mouse_down = true
	if not _active_touches.is_empty() or not _pointer_kind.is_empty():
		_invalidate_gesture()
		return
	_begin_pointer("mouse", 0, position)

func _mouse_release(position: Vector2, canceled: bool) -> void:
	_mouse_down = false
	if _pointer_kind == "mouse":
		_finish_pointer(position, canceled)
	_reset_invalid_if_idle()

func _touch_press(index: int, position: Vector2) -> void:
	_active_touches[index] = true
	if _active_touches.size() > 1 or _mouse_down or not _pointer_kind.is_empty():
		_invalidate_gesture()
		return
	_begin_pointer("touch", index, position)

func _touch_release(index: int, position: Vector2, canceled: bool) -> void:
	var is_pointer := _pointer_kind == "touch" and _pointer_index == index
	_active_touches.erase(index)
	if is_pointer:
		_finish_pointer(position, canceled or not _active_touches.is_empty())
	_reset_invalid_if_idle()

func _begin_pointer(kind: String, index: int, position: Vector2) -> void:
	_pointer_kind = kind
	_pointer_index = index
	_press_origin = position
	_gesture_invalid = false

func _pointer_motion(position: Vector2, kind: String = "mouse", index: int = 0) -> void:
	if _pointer_kind != kind or _pointer_index != index:
		return
	if position.distance_to(_press_origin) >= TAP_THRESHOLD:
		_gesture_invalid = true

func _finish_pointer(position: Vector2, canceled: bool) -> void:
	_pointer_motion(position, _pointer_kind, _pointer_index)
	var should_resume := not canceled and not _gesture_invalid
	_pointer_kind = ""
	_pointer_index = -1
	_press_origin = Vector2.ZERO
	if should_resume and not _resume_sent:
		_resume_sent = true
		resume_requested.emit()

func _invalidate_gesture() -> void:
	_gesture_invalid = true
	_pointer_kind = ""
	_pointer_index = -1
	_press_origin = Vector2.ZERO

func _reset_invalid_if_idle() -> void:
	if not _mouse_down and _active_touches.is_empty() and _pointer_kind.is_empty():
		_gesture_invalid = false

func _cancel_gesture() -> void:
	_pointer_kind = ""
	_pointer_index = -1
	_press_origin = Vector2.ZERO
	_mouse_down = false
	_active_touches.clear()
	_gesture_invalid = true

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_EXIT_TREE]:
		_cancel_gesture()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_cancel_gesture()
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()
