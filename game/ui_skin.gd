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
	var styles: Dictionary = BUTTON_TEXTURES.get(kind, BUTTON_TEXTURES["blue"])
	var path: String = styles.get(state, styles["normal"])
	return _nine_patch(path, 15.0, 8.0, 7.0)

static func panel_style(kind: String = "parchment") -> StyleBoxTexture:
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
