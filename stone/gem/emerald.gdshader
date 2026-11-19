shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

// Amount of polish on each exposed facet. UV2.y marks the freshly cut surface.
uniform float polish : hint_range(0.0, 1.0) = 1.0;
uniform vec3 light_dir = vec3(-0.48, 0.82, -0.40);

const vec3 AXES = vec3(1.55, 0.91, 1.20);
const float APOTHEM = 0.92387953;
// Same girdle, crown and pavilion as the mesh, in normalized ellipsoid space.
const vec2 RINGS[7] = {vec2(.66,.70), vec2(.88,.40), vec2(.97,.13),
	vec2(.98,-.075), vec2(.85,-.43), vec2(.52,-.78), vec2(.14,-.93)};
const vec2 SECTORS[8] = {vec2(.9238795,.3826834), vec2(.3826834,.9238795),
	vec2(-.3826834,.9238795), vec2(-.9238795,.3826834),
	vec2(-.9238795,-.3826834), vec2(-.3826834,-.9238795),
	vec2(.3826834,-.9238795), vec2(.9238795,-.3826834)};

// Palette values are display sRGB. Switch to linear only on linear renderers.
const vec3 INK   = vec3(.020,.078,.057);
const vec3 DEEP  = vec3(.040,.210,.130);
const vec3 PINE  = vec3(.072,.408,.251);
const vec3 JADE  = vec3(.162,.648,.375);
const vec3 MINT  = vec3(.411,.842,.551);
const vec3 AQUA  = vec3(.286,.832,.753);
const vec3 LIME  = vec3(.802,.944,.407);
const vec3 GOLD  = vec3(1.00,.864,.473);
const vec3 WHITE = vec3(.945,1.0,.870);

varying vec3 object_position;
varying vec3 object_normal;

void vertex() {
	object_position = VERTEX;
	object_normal = NORMAL;
}

// Exit of a ray inside the stone: clip against every plane of the convex hull.
// The smallest positive hit gives both the exit distance and the exact back facet.
vec4 hull_exit(vec3 origin, vec3 direction) {
	vec3 p = origin / AXES;
	vec3 ray = direction / AXES;
	vec4 best = vec4(0., 1., 0., 20.);
	if (abs(ray.y) > .0001) {
		float cap_y = ray.y > 0. ? RINGS[0].y : RINGS[6].y;
		float dist = (cap_y - p.y) / ray.y;
		if (dist > .0001) {
			best = vec4(0., sign(ray.y), 0., dist);
		}
	}
	for (int i = 0; i < 8; i++) {
		vec2 side = SECTORS[i];
		float radial_position = dot(side, p.xz);
		float radial_rate = dot(side, ray.xz);
		for (int j = 0; j < 6; j++) {
			vec2 top = RINGS[j];
			vec2 bottom = RINGS[j + 1];
			float slope = APOTHEM * (bottom.x - top.x) / (top.y - bottom.y);
			float closing_speed = radial_rate + slope * ray.y;
			if (closing_speed > .0001) {
				float dist = (APOTHEM * top.x + slope * (top.y - p.y) - radial_position) / closing_speed;
				if (dist > .0001 && dist < best.w) {
					best = vec4(side.x, slope, side.y, dist);
				}
			}
		}
	}
	return vec4(normalize(best.xyz / AXES), best.w);
}

// A broad softbox, a green side panel, and a narrow strip reflected by the cut.
// Angular boundaries stay hard at native pixel resolution.
float studio_cards(vec3 ray, vec3 hit, vec3 lamp) {
	vec3 side = normalize(cross(lamp, abs(lamp.y) > .98 ? vec3(0.,0.,1.) : vec3(0.,1.,0.)));
	vec3 vertical = cross(side, lamp);
	// Finite-distance lighting: rays leaving at different points see different
	// parts of the same panel, even within one perfectly planar facet.
	vec3 r = normalize(ray + hit * .66);
	// Panels are aimed obliquely across the table to leave a deep central facet.
	float x = dot(r, .95534 * side + .29552 * lamp);
	float y = dot(r, vertical);
	float z = dot(r, .95534 * lamp - .29552 * side);
	float main_card = min((.74 - abs(x + .02)) * 2.4, (.37 - abs(y - .05)) * 3.5);
	main_card = min(main_card, (z - .34) * 2.7);
	float side_card = min((.50 - abs(y + .04)) * 2.2, (.48 - abs(z + .20)) * 2.4);
	side_card = min(side_card, (-x - .32) * 2.0);
	float strip = min((.12 - abs(z + .58)) * 6.5, (.65 - abs(x - .25)) * 2.2);
	return 1.45 * max(max(main_card, side_card), strip);
}

vec3 return_color(float energy, float spectral_edge, float hue) {
	if (energy > .60) { return WHITE; }
	if (energy > .50) { return hue > .85 ? GOLD : (hue > -.12 ? LIME : AQUA); }
	if (energy > .34) { return spectral_edge > .72 ? LIME : MINT; }
	if (energy > .14) { return JADE; }
	if (energy > -.07) { return PINE; }
	if (energy > -.65) { return DEEP; }
	return INK;
}

vec3 polished_color(vec3 p, vec3 n, vec3 view_dir, vec3 lamp) {
	// Beryl-like refractive index. Trace the entering ray to the actual pavilion,
	// then reflect once more; both exits contribute hard-edged internal facets.
	vec3 incident = refract(-view_dir, n, 1.0 / 1.58);
	vec3 start = p + incident * .002;
	vec4 back = hull_exit(start, incident);
	vec3 hit = start + incident * back.w;
	vec3 bounce = reflect(incident, back.xyz);
	vec4 next = hull_exit(hit + bounce * .002, bounce);
	vec3 next_hit = hit + bounce * (next.w + .002);
	vec3 twice = reflect(bounce, next.xyz);
	float first_card = studio_cards(bounce, hit, lamp);
	float second_card = studio_cards(twice, next_hit, lamp);
	float surface_card = studio_cards(reflect(-view_dir, n), p, lamp);
	// The long optical path through the middle stays dark. Around the perimeter,
	// near-surface reflections and short paths retain their brilliant return.
	vec3 q = p / AXES;
	vec3 ortho = normalize(view_dir / AXES);
	float radius = length(q - ortho * dot(q, ortho));
	float rim = smoothstep(.42, .89, radius);
	float energy = max(first_card - .84 * (1.0 - rim), second_card - .93 + .78 * rim);
	energy = max(energy, surface_card - .98 + .98 * rim);
	energy -= .28 * (1.0 - rim) + .05;
	float fill = -.35 + .52 * dot(back.xyz, lamp) + .28 * dot(next.xyz, lamp);
	energy = max(energy, fill) + .16 * rim + .04;
	float spectral_edge = dot(bounce, next.xyz);
	vec3 reflected = return_color(energy, spectral_edge, dot(bounce, lamp));
	// Adjacent pavilion facets retain distinct values inside the broad dark table.
	if (all(equal(reflected, DEEP))) {
		float inner_face = dot(back.xyz, lamp) + .45 * dot(next.xyz, lamp);
		if (inner_face < -.40) { reflected = mix(INK, DEEP, .43); }
		else if (inner_face > .38) { reflected = mix(DEEP, PINE, .55); }
	}
	return reflected;
}

float cell_hash(vec3 p) {
	p = fract(p * vec3(.1031,.11369,.13787));
	p += dot(p, p.yxz + 19.19);
	return fract((p.x + p.y) * p.z);
}

vec3 rough_color(vec3 p, vec3 n, vec3 lamp, vec3 view_dir) {
	float light = dot(n, normalize(lamp + .65 * view_dir + vec3(-.12,.25,0.)));
	vec3 chip_position = p * 3.1 + vec3(.3,1.5,.25);
	vec3 cell = floor(chip_position);
	vec3 within_cell = abs(fract(chip_position) - .5);
	float chip = cell_hash(cell);
	if (chip > .74 && max(within_cell.x, max(within_cell.y, within_cell.z)) < .43) {
		light = light > .26 ? .16 : light - .32;
	}
	if (light > .26) { return vec3(.500,.557,.505); }
	if (light > -.22) { return vec3(.442,.494,.449); }
	return vec3(.380,.435,.392);
}

vec3 cut_color(vec3 n, vec3 lamp, vec3 eye, vec3 strip_lamp) {
	float light = dot(n, normalize(lamp + eye * .30));
	float shine = dot(reflect(-eye,n), strip_lamp);
	if (shine > .83 && n.y < .995) { return WHITE; }
	if (light > .28) { return JADE; }
	if (light > -.12) { return PINE; }
	return DEEP;
}

void fragment() {
	mat3 world_to_object = inverse(mat3(MODEL_MATRIX));
	vec3 world_view = PROJECTION_MATRIX[3][3] == 1.0 ? INV_VIEW_MATRIX[2].xyz : mat3(INV_VIEW_MATRIX) * VIEW;
	vec3 eye = normalize(world_to_object * world_view);
	vec3 lamp = normalize(world_to_object * light_dir);
	// A second studio strip on the opposite side catches the right crown facet.
	vec3 strip_lamp = normalize(world_to_object * vec3(-light_dir.z, light_dir.y, light_dir.x));
	vec3 normal = normalize(object_normal);
	// UV.x measures distance to the polygon boundary. Derivatives size the bevel
	// in screen pixels and avoid highlighting the triangle fan inside the table.
	float edge_width = max(length(vec2(dFdx(UV.x), dFdy(UV.x))), .00001);
	bool edge = UV.x < edge_width * .77;
	vec3 rgb = rough_color(object_position, normal, lamp, eye);
	if (UV2.y > .5) {
		rgb = cut_color(normal, lamp, eye, strip_lamp);
		if (edge) { rgb = dot(normal,lamp) > -.15 ? MINT : PINE; }
		if (polish > .001) {
			vec3 gem = polished_color(object_position, normal, eye, lamp);
			if (edge) {
				float mark = dot(gem, vec3(.22,.68,.10));
				gem = mark > .60 ? WHITE : (mark > .30 ? MINT : PINE);
			}
			rgb = mix(rgb, gem, polish);
		}
	}
	ALBEDO = OUTPUT_IS_SRGB ? rgb : mix(rgb / 12.92, pow((rgb + .055) / 1.055, vec3(2.4)), step(vec3(.04045),rgb));
}
