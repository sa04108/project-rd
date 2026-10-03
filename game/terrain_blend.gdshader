shader_type canvas_item;
render_mode unshaded;

uniform sampler2D grass_texture : source_color, filter_linear, repeat_enable;
uniform sampler2D dirt_texture : source_color, filter_linear, repeat_enable;
uniform vec2 field_origin = vec2(126.0, 158.0);
uniform float field_extent = 468.0;
uniform float path_width = 78.0;

// 표현용 잡음은 지면 좌표만 사용한다. 시간·카메라 거리·게임 난수와 무관하다.
float hash_point(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ground_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_point(cell), hash_point(cell + vec2(1.0, 0.0)), w.x), mix(hash_point(cell + vec2(0.0, 1.0)), hash_point(cell + vec2(1.0)), w.x), w.y);
}

float rectangle_inside(vec2 p, vec2 lo, vec2 hi) {
	vec2 distances = min(p - lo, hi - p);
	return min(distances.x, distances.y);
}

void fragment() {
	vec2 p = UV * vec2(720.0, 656.0) + vec2(0.0, 60.0);
	vec2 hi = field_origin + vec2(field_extent);
	// 길의 기준 폭과 평행선은 고정하고 경계의 풀잎과 흙 알갱이만 부드럽게 섞는다.
	float fringe = (ground_noise(p * 0.085) - 0.5) * 8.0 + (ground_noise(p * 0.43) - 0.5) * 3.5;
	float inner = smoothstep(-3.8, 3.8, rectangle_inside(p, field_origin, hi) + fringe);
	float outer = smoothstep(-3.8, 3.8, rectangle_inside(p, field_origin - vec2(path_width), hi + vec2(path_width)) + fringe);
	float gate = smoothstep(-3.8, 3.8, rectangle_inside(p, vec2(field_origin.x - path_width, 60.0), vec2(field_origin.x, field_origin.y)) + fringe);
	float road = max(outer * (1.0 - inner), gate);
	vec3 grass = texture(grass_texture, p / 1024.0).rgb;
	vec3 dirt = texture(dirt_texture, p / 1024.0).rgb;
	float fade = smoothstep(60.0, 76.0, p.y) * (1.0 - smoothstep(708.0, 716.0, p.y));
	COLOR = vec4(mix(grass, dirt, road), max(fade, gate));
}
