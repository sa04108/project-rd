extends RefCounted

static func run_all() -> Dictionary:
	var failed: Array[String] = []
	var visuals = preload("res://game/visual_assets.gd").new()
	if visuals.ready_count() != 87 or visuals.families.size() != 7:
		failed.append("모든 87종에 7개 공유 계열의 실제 런타임 아틀라스가 필요합니다")
	if visuals.portraits.size() != 87:
		failed.append("모든 87종의 개별 원화 텍스처가 필요합니다")
	for family in visuals.families:
		var resource: Dictionary = visuals.families[family]
		var texture: Texture2D = visuals.family_texture(family)
		if texture == null:
			failed.append("%s의 아틀라스를 읽을 수 없습니다" % family)
			continue
		var dimensions: Vector2 = texture.get_size()
		var rows: Dictionary = resource.layout.frame_layout.rows
		for state in ["idle", "walk", "attack"]:
			if not rows.has(state) or rows[state].is_empty():
				failed.append("%s의 %s 상태가 누락되었습니다" % [family, state])
				continue
			for cell in rows[state]:
				if cell.x < 0 or cell.y < 0 or cell.w <= 0 or cell.h <= 0 or cell.x + cell.w > dimensions.x or cell.y + cell.h > dimensions.y:
					failed.append("%s/%s의 프레임이 실제 텍스처 밖을 참조합니다" % [family, state])
	for identity in visuals.entries:
		var portrait: Texture2D = visuals.portrait(identity)
		if portrait == null or not portrait.get_image().get_used_rect().has_area():
			failed.append("%s의 개별 원화가 없거나 완전히 투명합니다" % identity)
		for state in ["idle", "walk", "attack"]:
			if visuals.frame(identity, state, 0.0).is_empty() or visuals.frame(identity, state, 1.7).is_empty():
				failed.append("%s/%s의 재생 프레임을 읽을 수 없습니다" % [identity, state])
	return {"passed": 1 if failed.is_empty() else 0, "failed": failed}
