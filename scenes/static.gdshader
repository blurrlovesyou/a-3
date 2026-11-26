shader_type canvas_item;
float rand(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 cell = floor(UV * vec2(256.0, 192.0));
	float n = rand(cell + floor(TIME * 24.0));
	COLOR = vec4(vec3(n), 1.0);
}