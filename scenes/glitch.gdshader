shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float intensity : hint_range(0.0, 1.0) = 0.15;

float rand(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	float band = floor(uv.y * 24.0);
	float t = floor(TIME * 12.0);
	if (rand(vec2(band, t + 7.0)) > 0.6) {
		uv.x += (rand(vec2(band, t)) - 0.5) * 0.15 * intensity;
	}
	float split = 0.01 * intensity;
	float r = texture(screen_tex, uv + vec2(split, 0.0)).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - vec2(split, 0.0)).b;
	float n = rand(uv * 1000.0 + TIME) * intensity * 0.3;
	COLOR = vec4(vec3(r, g, b) + n, 1.0);
}