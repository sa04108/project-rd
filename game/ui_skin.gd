extends RefCounted

const BUTTON_TEXTURES := {
	"blue": {
		"normal": "res://assets/ui/button_blue_normal.svg",
		"hover": "res://assets/ui/button_blue_hover.svg",
		"pressed": "res://assets/ui/button_blue_pressed.svg",
		"disabled": "res://assets/ui/button_blue_disabled.svg",
	},
	"gold": {
		"normal": "res://assets/ui/button_gold_normal.svg",
		"hover": "res://assets/ui/button_gold_hover.svg",
		"pressed": "res://assets/ui/button_gold_pressed.svg",
		"disabled": "res://assets/ui/button_gold_disabled.svg",
	},
	"dark": {
		"normal": "res://assets/ui/button_dark_normal.svg",
		"hover": "res://assets/ui/button_dark_hover.svg",
		"pressed": "res://assets/ui/button_dark_pressed.svg",
		"disabled": "res://assets/ui/button_dark_disabled.svg",
	},
}
const PANEL_TEXTURES := {
	"parchment": "res://assets/ui/panel_parchment.svg",
	"hud": "res://assets/ui/panel_hud.svg",
	"header": "res://assets/ui/panel_header.svg",
}

static var _textures: Dictionary = {}

static func button_style(kind: String, state: String = "normal") -> StyleBoxTexture:
	if kind in ["brass", "brass_accent"]:
		return _brass_style(kind, state)
	var styles: Dictionary = BUTTON_TEXTURES.get(kind, BUTTON_TEXTURES["blue"])
	var path: String = styles.get(state, styles["normal"])
	return _nine_patch(path, 15.0, 8.0, 7.0)

static func panel_style(kind: String = "parchment") -> StyleBoxTexture:
	if kind == "brass":
		return _brass_style("brass", "normal")
	var resolved_kind := kind
	if kind == "dark":
		resolved_kind = "hud"
	elif kind == "blue":
		resolved_kind = "header"
	var path: String = PANEL_TEXTURES.get(resolved_kind, PANEL_TEXTURES["parchment"])
	return _nine_patch(path, 18.0, 14.0, 14.0)

static func banner_texture() -> Texture2D:
	return _texture("res://assets/ui/guild_pennant.svg")

static func _nine_patch(path: String, edge: float, content_x: float, content_y: float) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _texture(path)
	style.texture_margin_left = edge
	style.texture_margin_top = edge
	style.texture_margin_right = edge
	style.texture_margin_bottom = edge
	style.content_margin_left = content_x
	style.content_margin_top = content_y
	style.content_margin_right = content_x
	style.content_margin_bottom = content_y
	style.draw_center = true
	return style

static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D
	return _textures[path] as Texture2D

static func dropdown_arrow() -> Texture2D:
	return _svg_texture("dropdown_arrow", '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28"><path d="m5 10 9 9 9-9" fill="none" stroke="#f2e5c7" stroke-width="4" stroke-linejoin="round" stroke-linecap="round"/></svg>')

static func icon_texture(kind: String) -> Texture2D:
	if kind == "diamond":
		return _texture("res://assets/ui/diamond.svg")
	var shapes := {
		"home": '<path d="M5 29 31 7l26 22-6 7-20-17-20 17z" fill="url(#metal)"/><path d="M13 31v24h13V39h10v16h13V31L31 16z" fill="url(#paper)"/><path d="M25 55V38h12v17" fill="#29251f"/><path d="M40 10h9v12l-9-8z" fill="url(#metal)"/>',
		"recipes": '<path d="M9 13c8-3 15-2 23 3 8-5 15-6 23-3v37c-8-3-15-2-23 3-8-5-15-6-23-3z" fill="url(#paper)"/><path d="M32 16v37M15 23h10m-10 7h10m-10 7h10" fill="none"/><path d="M44 25v14m-7-7h14" fill="none" stroke-width="3"/>',
		"codex": '<path d="M5 13c9-4 19-2 27 3 8-5 18-7 27-3v40c-9-3-19-1-27 4-8-5-18-7-27-4z" fill="url(#metal)"/><path d="M9 9c8-2 16 1 23 6v35c-7-5-15-7-23-5zM55 9c-8-2-16 1-23 6v35c7-5 15-7 23-5z" fill="url(#paper)"/><path d="M32 15v35M15 20c4 0 7 1 11 3m-11 7c4 0 7 1 11 3m23-13c-4 0-7 1-11 3m11 7c-4 0-7 1-11 3" fill="none" stroke="#886335" stroke-width="2"/>',
		"sound": '<path d="M7 24h11L33 12v40L18 40H7z" fill="url(#paper)"/><path d="M41 22c7 5 7 15 0 20m8-28c12 10 12 26 0 36" fill="none" stroke="url(#paper)" stroke-width="4"/>',
		"sound_muted": '<path d="M7 24h11L33 12v40L18 40H7z" fill="url(#paper)"/><path d="m42 24 14 16m0-16-14 16" fill="none" stroke="#f4b39b" stroke-width="5"/>',
		"settings": '<path d="m27 4 9 0 2 8 5 2 7-4 6 7-5 6 2 5 8 2v9l-8 2-2 5 4 7-7 6-6-5-5 2-2 8h-9l-2-8-5-2-7 4-6-7 5-6-2-5-8-2v-9l8-2 2-5-4-7 7-6 6 5 5-2z" transform="translate(2 -2) scale(.94)" fill="url(#metal)"/><circle cx="31" cy="30" r="11" fill="#29251f" stroke="#f0d396" stroke-width="2"/>',
		"coin": '<circle cx="31" cy="31" r="27" fill="#926023"/><circle cx="31" cy="29" r="24" fill="url(#metal)"/><circle cx="31" cy="29" r="18" fill="none" stroke="#a3762f"/><path d="m31 15 8 14-8 14-8-14z" fill="#fff1b2" stroke="#ad7b29"/><path d="M16 17c3-5 7-7 11-8" fill="none" stroke="#fff4cd" stroke-width="3"/>',
		"summon": '<path d="M11 32c0-30 40-30 40 0v17l-12 8V36l-8-6-8 6v21l-12-8z" fill="url(#metal)"/><path d="M31 5v24M9 30l16 4m28-4-16 4" stroke="#fff1c2" stroke-width="2"/><path d="m15 35 8 3v9l-8-4zm32 0-8 3v9l8-4z" fill="#29251f"/><path d="M30 3h3v9h-3z" fill="#fff1c2"/>',
		"upgrade": '<path d="m12 9 9 2 27 31-7 6-28-30zm39 0-9 2-27 31 7 6 28-30z" fill="url(#paper)"/><path d="m12 36 14 13m11-13 14 13M16 47l-8 9m37-9 8 9" fill="none" stroke="url(#metal)" stroke-width="5"/><path d="m31 3-9 11h6v10h7V14h6z" fill="url(#metal)"/>',
		"gamble": '<rect x="5" y="10" width="29" height="32" rx="5" fill="url(#paper)" transform="rotate(-12 19 26)"/><rect x="27" y="27" width="29" height="31" rx="5" fill="url(#paper)" transform="rotate(13 41 42)"/><g fill="#443020" stroke="none"><circle cx="12" cy="18" r="2.5"/><circle cx="27" cy="33" r="2.5"/><circle cx="19" cy="26" r="2.5"/><circle cx="37" cy="34" r="2.5"/><circle cx="48" cy="37" r="2.5"/><circle cx="33" cy="49" r="2.5"/><circle cx="44" cy="52" r="2.5"/></g>',
		"special": '<circle cx="31" cy="31" r="19" fill="none" stroke="#d3a64e" stroke-width="2"/><path d="m31 2 6 23 23 6-23 6-6 23-6-23L2 31l23-6z" fill="url(#metal)"/><path d="m31 11 3 17 17 3-17 3-3 17-3-17-17-3 17-3z" fill="#fff0ba" stroke="none"/>',
	}
	var shape: String = shapes.get(kind, shapes["special"])
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><defs><linearGradient id="metal" x2=".35" y2="1"><stop stop-color="#fff0bd"/><stop offset=".42" stop-color="#dfb764"/><stop offset="1" stop-color="#a27738"/></linearGradient><linearGradient id="paper" x2="0" y2="1"><stop stop-color="#fff0c9"/><stop offset="1" stop-color="#cfad72"/></linearGradient></defs><g stroke="#604423" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round">%s</g></svg>' % shape
	return _svg_texture("icon_" + kind, svg)

static func _brass_style(kind: String, state: String) -> StyleBoxTexture:
	var palette := {
		"normal": ["#38352b", "#201e19", "#c8ad73", "#766246"],
		"hover": ["#494336", "#2b271f", "#ecd195", "#aa8b53"],
		"pressed": ["#25231c", "#343025", "#d4b16f", "#9c7940"],
		"disabled": ["#302f29", "#26251f", "#837965", "#5f594b"],
	}
	var colors: Array = palette.get(state, palette.normal).duplicate()
	if kind == "brass_accent" and state != "disabled":
		colors[0] = "#51432b" if state == "normal" else colors[0]
		colors[2] = "#edcb83"
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96"><defs><linearGradient id="wood" x2="0" y2="1"><stop stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient><linearGradient id="brass" x2=".15" y2="1"><stop stop-color="#eddbac"/><stop offset=".38" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs><path d="M12 2H84L94 12V84L84 94H12L2 84V12Z" fill="#1a1814" stroke="#100f0c" stroke-width="2"/><path d="M13 5H83L91 13V83L83 91H13L5 83V13Z" fill="url(#wood)" stroke="url(#brass)" stroke-width="2.5"/><path d="M16 10H80L86 16V80L80 86H16L10 80V16Z" fill="none" stroke="%s" stroke-width=".8"/><path d="M18 18H78M18 78H78M18 22H78" stroke="#e9cf91" stroke-opacity=".035"/><path d="M7 19V13l6-6h6m58 0h6l6 6v6M7 77v6l6 6h6m58 0h6l6-6v-6" fill="none" stroke="%s" stroke-width="1.2"/><path d="m10 13 3-3 3 3-3 3zm70 0 3-3 3 3-3 3zM10 83l3-3 3 3-3 3zm70 0 3-3 3 3-3 3z" fill="%s"/></svg>' % [colors[0], colors[1], colors[2], colors[3], colors[3], colors[2], colors[2]]
	return _texture_style(_svg_texture(kind + "_" + state, svg), 15.0, 12.0, 10.0)

static func _svg_texture(key: String, svg: String) -> Texture2D:
	if not _textures.has(key):
		var image := Image.new()
		var error := image.load_svg_from_string(svg, 1.0)
		if error != OK:
			push_error("HUD 벡터 이미지를 읽지 못했습니다: " + key)
			return null
		_textures[key] = ImageTexture.create_from_image(image)
	return _textures[key] as Texture2D

static func _texture_style(texture: Texture2D, edge: float, content_x: float, content_y: float) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = edge
	style.texture_margin_top = edge
	style.texture_margin_right = edge
	style.texture_margin_bottom = edge
	style.content_margin_left = content_x
	style.content_margin_top = content_y
	style.content_margin_right = content_x
	style.content_margin_bottom = content_y
	style.draw_center = true
	return style

static func switch_texture(enabled: bool) -> Texture2D:
	var fill := "#ae8135" if enabled else "#514d43"
	var knob_x := 82 if enabled else 30
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="112" height="60" viewBox="0 0 112 60"><rect x="2" y="2" width="108" height="56" rx="28" fill="%s" stroke="#c7ab74" stroke-width="3"/><circle cx="%d" cy="30" r="22" fill="#fff0ca" stroke="#6c512d" stroke-width="2"/></svg>' % [fill, knob_x]
	return _svg_texture("switch_on" if enabled else "switch_off", svg)

static func style_slider(slider: Slider) -> void:
	for state in ["slider", "grabber_area", "grabber_area_highlight"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("6b604e") if state == "slider" else Color("c99a45")
		style.set_corner_radius_all(10)
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		slider.add_theme_stylebox_override(state, style)
	var grabber := _svg_texture("volume_grabber", '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><circle cx="24" cy="24" r="21" fill="#fff0ca" stroke="#76552c" stroke-width="4"/><circle cx="24" cy="24" r="12" fill="#e3b45e"/></svg>')
	for state in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(state, grabber)
