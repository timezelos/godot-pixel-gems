shader_type canvas_item;
render_mode unshaded;

uniform float polish;
uniform vec3 glints[4]; // screen pixel xy, signed radius (hidden when negative)

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec4 stone = texture(TEXTURE, UV);
	float neighbors = max(max(texture(TEXTURE, UV + vec2(texel.x,0.0)).a,
			texture(TEXTURE, UV - vec2(texel.x,0.0)).a),
			max(texture(TEXTURE, UV + vec2(0.0,texel.y)).a, texture(TEXTURE, UV - vec2(0.0,texel.y)).a));
	vec4 result = stone.a > 0.5 ? vec4(stone.rgb / stone.a, 1.0)
			: vec4(0.022, 0.068, 0.049, step(0.5, neighbors));
	vec2 pixel = floor(UV / texel);
	for (int i = 0; i < 4; i++) {
		vec2 delta = abs(pixel - floor(glints[i].xy));
		float radius = glints[i].z * polish;
		if (radius >= 1.0 && ( (min(delta.x, delta.y) < 0.5 && max(delta.x, delta.y) <= radius)
				|| (radius >= 4.0 && max(delta.x, delta.y) <= 1.0) )) {
			bool tip = max(delta.x, delta.y) > radius * 0.57;
			result = vec4(tip ? vec3(0.56,0.91,0.68) : vec3(0.995,1.0,0.93), 1.0);
		}
	}
	COLOR = result;
}
