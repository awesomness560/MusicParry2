// Universal attack indicator
// Put on a ColorRect (square, pivot at its centre). One material per indicator.
//
//   progress : 0 -> 1 over the attack's lead time (fills centre -> edges)
//   morph    : 0 = "#" shape tracked on the attacker
//              1 = ring marker (circle + direction arrow) for off-screen attackers
//              Rotate the node so its local UP points toward the attacker.
//   flash    : pulse to 1 on impact and decay, for the "now" moment
//   Node modulate tints the whole thing (e.g. per attack type) and fades it.

shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float morph    : hint_range(0.0, 1.0) = 0.0;
uniform float flash    : hint_range(0.0, 1.0) = 0.0;

group_uniforms colors;
uniform vec4 ghost_color   : source_color = vec4(0.45, 0.22, 0.06, 0.35); // unfilled part
uniform vec4 fill_color    : source_color = vec4(1.0, 0.70, 0.22, 1.0);
uniform vec4 edge_color    : source_color = vec4(1.0, 0.97, 0.85, 1.0);  // hot leading edge
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.55);   // keeps it readable on bright scenes
uniform float outline_width : hint_range(0.0, 0.1) = 0.025;
uniform float edge_width    : hint_range(0.0, 0.2) = 0.05;
uniform float glow_size     : hint_range(0.001, 0.3) = 0.07;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.6;

group_uniforms hash_shape;
uniform float hash_rotation_deg = 45.0;
uniform float bar_spacing     : hint_range(0.05, 0.6) = 0.27; // distance of each bar from centre
uniform float bar_half_length : hint_range(0.2, 1.0)  = 0.72;
uniform float bar_half_width  : hint_range(0.01, 0.2) = 0.055;
uniform float taper_start     : hint_range(0.0, 1.0)  = 0.4;  // fraction of half-length where the point begins
uniform float bar_offset      : hint_range(0.0, 0.3)  = 0.08; // slides bars along their length for a pinwheel feel

group_uniforms ring_shape;
uniform float circle_radius    : hint_range(0.1, 0.8) = 0.5;
uniform float arrow_tip        : hint_range(0.5, 1.0) = 0.9;   // distance of arrow apex from centre
uniform float arrow_height     : hint_range(0.05, 0.5) = 0.26;
uniform float arrow_half_width : hint_range(0.05, 0.5) = 0.22;
group_uniforms;

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Bar along the local Y axis, centred at origin, with pointed (tapered) ends.
float sd_bar(vec2 q) {
	float ay = abs(q.y);
	float t0 = taper_start * bar_half_length;
	float w = bar_half_width * clamp((bar_half_length - ay) / max(bar_half_length - t0, 1e-4), 0.0, 1.0);
	return max(abs(q.x) - w, ay - bar_half_length);
}

// Fill coordinate along a bar: 0 at its midpoint, 1 at its tips.
// d_lit tracks the distance to the already-lit part of any bar (for the glow).
void add_bar(vec2 q, float front, inout float d, inout float t_near, inout float t_in, inout float d_lit) {
	float di = sd_bar(q);
	float ti = abs(q.y) / bar_half_length;
	if (di < d) { d = di; t_near = ti; }
	if (di < 0.0) { t_in = min(t_in, ti); }   // where bars overlap, lit if either bar is lit
	d_lit = min(d_lit, max(di, (ti - front) * bar_half_length));
}

// How far along a bar (0..1) the fill front must be so that the lit AREA equals `prog`
// of the bar's area. Compensates for the thin tapered tips, so the fill reads at a steady rate.
float bar_front(float prog) {
	float a = taper_start;
	float area = prog * (1.0 + a) * 0.5;          // total area of a bar (width-normalised) is (1+a)/2
	if (area <= a) {
		return area;
	}
	float k = 1.0 - a;
	return a + k - sqrt(max(k * k - 2.0 * k * (area - a), 0.0));
}

// x = signed distance to the "#", y = fill coordinate (0 at bar middles -> 1 at tips),
// z = distance to the lit part of the "#"
vec3 hash_field(vec2 p, float front) {
	float s = bar_spacing;
	float o = bar_offset;
	float d = 1e5;
	float t_near = 1.0;
	float t_in = 2.0;
	float d_lit = 1e5;
	add_bar(vec2(p.x - s, p.y - o), front, d, t_near, t_in, d_lit);        // right bar, nudged down
	add_bar(vec2(p.x + s, p.y + o), front, d, t_near, t_in, d_lit);        // left bar, nudged up
	add_bar(vec2(p.y - s, -(p.x + o)), front, d, t_near, t_in, d_lit);     // bottom bar, nudged left
	add_bar(vec2(p.y + s, -(p.x - o)), front, d, t_near, t_in, d_lit);     // top bar, nudged right
	return vec3(d, t_in < 2.0 ? t_in : t_near, d_lit);
}

// Isosceles triangle, apex at origin, base at y = q.y (iq).
float sd_triangle_iso(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)),
	             vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
}

// Premultiplied "over" compositing helper.
vec4 over(vec4 top, vec4 bottom) {
	return vec4(top.rgb * top.a + bottom.rgb * (1.0 - top.a), top.a + bottom.a * (1.0 - top.a));
}

void fragment() {
	vec4 tint = COLOR;
	vec2 p = (UV - 0.5) * 2.0;            // -1..1, y points down
	float px = length(fwidth(p));         // ~1 pixel in p units, for anti-aliasing

	// --- shape: morph "#" -> circle ---
	float front = bar_front(progress);
	vec3 hf = hash_field(rot(radians(hash_rotation_deg)) * p, front);
	float r = length(p);
	float d = mix(hf.x, r - circle_radius, morph);

	// --- fill front: signed distance to it, negative = filled ---
	// "#": each bar fills from its middle to its tips; lit area grows linearly with progress.
	// circle: radius follows sqrt(progress) so the filled area grows linearly.
	float fd_hash = (hf.y - front) * bar_half_length - 2.0 * px * progress;
	float fd_circ = r - (circle_radius + 2.0 * px) * sqrt(progress);
	float fd = mix(fd_hash, fd_circ, morph);

	float lit = step(0.001, progress);
	float inside = 1.0 - smoothstep(-px, px, d);
	float filled = (1.0 - smoothstep(-px, px, fd)) * lit;
	float edge_on = lit * (1.0 - step(0.999, progress));
	float edge = (1.0 - smoothstep(0.0, edge_width, abs(fd))) * edge_on;

	// shape body (premultiplied)
	vec3 body_rgb = mix(ghost_color.rgb, fill_color.rgb, filled);
	body_rgb = mix(body_rgb, edge_color.rgb, edge * filled);
	body_rgb = mix(body_rgb, edge_color.rgb, flash);
	float body_a = mix(ghost_color.a, fill_color.a, filled);
	body_a = max(body_a, edge * edge_color.a);
	body_a = max(body_a, flash);
	vec4 body = vec4(body_rgb * body_a, body_a) * inside;

	// dark outline just outside the shape
	float ol = (1.0 - smoothstep(outline_width, outline_width + px, d)) * (1.0 - inside);
	vec4 outline = vec4(outline_color.rgb * outline_color.a, outline_color.a) * ol;

	// glow around the filled part only
	// distance to the lit part of the shape, so the glow only surrounds what has filled
	float d_lit = mix(hf.z, max(d, fd), morph);
	float g = exp(-max(d_lit, 0.0) / glow_size) * (1.0 - inside) * lit;
	g *= glow_strength * (1.0 + 2.0 * flash);
	g = clamp(g, 0.0, 1.0);
	vec3 glow_rgb = mix(fill_color.rgb, edge_color.rgb, flash);
	vec4 glow = vec4(glow_rgb * g, g);

	vec4 col = over(body, over(outline, glow));

	// --- direction arrow (ring mode only), points toward local UP ---
	float d_arrow = sd_triangle_iso(p - vec2(0.0, -arrow_tip), vec2(arrow_half_width, arrow_height));
	float arrow_in = (1.0 - smoothstep(-px, px, d_arrow)) * morph;
	float arrow_ol = (1.0 - smoothstep(outline_width, outline_width + px, d_arrow)) * morph * (1.0 - arrow_in);
	vec3 arrow_rgb = mix(fill_color.rgb, edge_color.rgb, flash);
	col = over(vec4(outline_color.rgb * outline_color.a, outline_color.a) * arrow_ol, col);
	col = over(vec4(arrow_rgb, 1.0) * arrow_in, col);

	// un-premultiply and apply node modulate
	vec3 rgb = col.a > 0.0001 ? col.rgb / col.a : vec3(0.0);
	COLOR = vec4(rgb * tint.rgb, col.a * tint.a);
}