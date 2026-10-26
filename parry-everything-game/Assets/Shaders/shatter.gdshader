// Generic shatter burst: solid triangular shards that fly outward from the centre, spin, fall and fade.
// Put on a ColorRect centred on the rank letter (a few times its size). Animate `progress` 0 -> 1.

shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform int count = 24;              // number of shards
uniform float start_radius = 0.18;   // area the shards start in (1 = edge of the rect)
uniform float force = 0.75;          // how far they travel (1 = edge of the rect)
uniform float shard_size = 0.07;     // average shard size
uniform float spin = 5.0;            // max rotation, radians
uniform float gravity = 0.25;        // downward pull
uniform float seed = 0.0;            // change per burst
uniform vec4 shard_color : source_color = vec4(0.95, 0.63, 0.14, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash = 0.7;           // shards start this white and cool to shard_color

const int MAX_SHARDS = 64;

float hash11(float n) {
	return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453);
}

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// signed distance-ish to a triangle (negative inside), good enough for anti-aliasing
float tri_dist(vec2 p, vec2 a, vec2 b, vec2 c) {
	vec2 e0 = b - a, e1 = c - b, e2 = a - c;
	float s = sign(e0.y * e2.x - e0.x * e2.y);   // triangle winding, so "inside" is always positive
	float d0 = s * (e0.x * (p.y - a.y) - e0.y * (p.x - a.x)) / length(e0);
	float d1 = s * (e1.x * (p.y - b.y) - e1.y * (p.x - b.x)) / length(e1);
	float d2 = s * (e2.x * (p.y - c.y) - e2.y * (p.x - c.x)) / length(e2);
	return -min(min(d0, d1), d2);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;              // -1..1 across the rect, y down
	float px = length(fwidth(p));
	float t = progress;
	float travel = 1.0 - (1.0 - t) * (1.0 - t);
	int n = clamp(count, 1, MAX_SHARDS);

	float cover = 0.0;
	float shade = 1.0;
	for (int i = 0; i < MAX_SHARDS; i++) {
		if (i >= n) { break; }
		float fi = float(i);
		float a = hash11(fi) * TAU;
		float r = sqrt(hash11(fi + 0.31)) * start_radius;
		vec2 start = vec2(cos(a), sin(a)) * r;
		vec2 dir = normalize(start + (vec2(hash11(fi + 0.57), hash11(fi + 0.83)) - 0.5) * 0.3 + vec2(0.0001));
		vec2 centre = start + dir * force * travel * (0.6 + 0.8 * hash11(fi + 1.7))
		              + vec2(0.0, gravity * t * t);
		float ang = (hash11(fi + 2.3) - 0.5) * 2.0 * spin * travel + a;
		float size = shard_size * (0.5 + hash11(fi + 3.1)) * (1.0 - 0.5 * travel);

		// shard in its own space: a random, slightly elongated triangle
		vec2 q = rot(-ang) * (p - centre) / size;
		q.x /= 1.0 + hash11(fi + 4.7);          // stretch some shards into splinters
		float a0 = hash11(fi + 5.3) * TAU;
		float a1 = a0 + 1.9 + hash11(fi + 6.1);
		float a2 = a1 + 1.9 + hash11(fi + 6.9);
		vec2 v0 = vec2(cos(a0), sin(a0));
		vec2 v1 = vec2(cos(a1), sin(a1)) * (0.6 + 0.4 * hash11(fi + 7.7));
		vec2 v2 = vec2(cos(a2), sin(a2));
		float d = tri_dist(q, v0, v1, v2) * size;
		float c = 1.0 - smoothstep(-px, px, d);
		if (c > cover) {
			cover = c;
			shade = 0.75 + 0.35 * hash11(fi + 8.3);   // per-shard brightness variation
		}
	}

	float hot = flash * pow(1.0 - t, 3.0);
	vec3 rgb = mix(shard_color.rgb * shade, flash_color.rgb, hot);
	float alpha = cover * shard_color.a * (1.0 - smoothstep(0.5, 1.0, t));
	COLOR = vec4(rgb, alpha) * COLOR;
}