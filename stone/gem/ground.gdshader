shader_type canvas_item;
render_mode unshaded;

// The polygon is the gemstone's silhouette projected onto the studio floor.
uniform vec2 footprint_center;
uniform vec2 footprint_radius;
uniform float azimuth;
uniform float polish;
varying vec2 sheet_position;

void vertex() {
	sheet_position = VERTEX;
}

void fragment() {
	vec2 p = (sheet_position - footprint_center) / max(footprint_radius, vec2(1.0));
	float s = sin(azimuth);
	p.x += 0.13 * p.y - 0.09 * s;
	p.y += 0.10 * p.x * sin(azimuth + 0.7);
	float scale = max(0.002, smoothstep(0.03, 0.88, polish));
	p /= scale;
	vec3 shadow = vec3(0.6667, 0.6824, 0.7059);
	vec3 color = shadow;
	// Overlapping refraction lobes, broad enough to survive the pixel grid.
	float rim = length((p - vec2(0.022, 0.02)) * vec2(1.32, 1.48));
	if (rim < 1.0) { color = vec3(0.96, 0.855, 0.48); }
	if (rim < 1.0 && p.x - 0.6*p.y + 0.10*s > -0.05) { color = vec3(0.79, 0.924, 0.39); }
	if (length((p - vec2(0.035 - 0.05*s, 0.055)) * vec2(1.68, 1.72)) < 1.0) {
		color = vec3(0.4157, 0.8235, 0.5294);
		if (p.y > 0.42 + p.x * 0.35 && p.x > 0.0) { color = vec3(0.29, 0.796, 0.686); }
	}
	vec2 core = p + vec2(0.055, 0.08);
	core.x -= (0.64 + 0.23*s) * core.y;
	if (pow(abs(core.x * 3.7), 2.4) + pow(abs(core.y * 2.75), 2.4) < 1.0) {
		color = vec3(0.935, 0.973, 0.853);
	}
	COLOR = vec4(mix(shadow, color, smoothstep(0.02, 0.65, polish)), 1.0);
}
